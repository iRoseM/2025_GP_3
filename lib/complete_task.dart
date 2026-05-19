import 'dart:io';
import 'dart:math' as math;
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:camera/camera.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'services/location_validator.dart';
import 'services/map_pick_route.dart';
import 'services/task_verification_service.dart';
import '../services/app_colors.dart';
import '../../home.dart';
import 'services/ocr_service.dart';
import 'task.dart';
import 'services/xp_service.dart';
import 'services/gemini_resolver_service.dart';

// ─────────────────────────────────────────────
//  كلاسات مساعدة لتتبع المسار
// ─────────────────────────────────────────────

class _TrackPoint {
  final double lat;
  final double lng;
  final DateTime time;
  const _TrackPoint({required this.lat, required this.lng, required this.time});
}

class _TrackAnalysis {
  final bool isValid;
  final double avgSpeed;
  final double maxSpeed;
  final int totalPoints;
  final String? rejectionReason;

  const _TrackAnalysis({
    required this.isValid,
    this.avgSpeed = 0,
    this.maxSpeed = 0,
    this.totalPoints = 0,
    this.rejectionReason,
  });
}

// ─────────────────────────────────────────────
//  Thresholds حسب نوع المواصلات
//  (مبنية على أرقام مترو الرياض ونقل العام
//   مع هامش خطأ سخي لصالح اليوزر)
// ─────────────────────────────────────────────

class _TransportThresholds {
  final double maxAvgSpeed; // رفض لو المتوسط فوق هذا
  final double maxPeakSpeed; // رفض لو القصوى فوق هذا
  const _TransportThresholds({
    required this.maxAvgSpeed,
    required this.maxPeakSpeed,
  });
}

const _metroThresholds = _TransportThresholds(
  maxAvgSpeed: 75, // مترو الرياض متوسط فعلي ~35-50، نعطي هامش حتى 75
  maxPeakSpeed: 130, // سرعة قصوى رسمية 120، نعطي هامش 10 إضافية
);

const _bicycleThresholds = _TransportThresholds(
  maxAvgSpeed: 30, // دراجة متوسط ~15-20، هامش حتى 30
  maxPeakSpeed: 50, // قصوى ~45، هامش 5 إضافية
);

const _scooterThresholds = _TransportThresholds(
  maxAvgSpeed: 35, // سكوتر متوسط ~20-25، هامش حتى 35
  maxPeakSpeed: 55,
);

const _walkThresholds = _TransportThresholds(
  maxAvgSpeed: 10, // مشي متوسط ~4-6، هامش حتى 10
  maxPeakSpeed: 15,
);

const _busThresholds = _TransportThresholds(
  maxAvgSpeed: 55, // باص نقل متوسط ~15-35، نعطي هامش حتى 55
  maxPeakSpeed: 90, // سرعة قصوى باص ~80، نعطي هامش 10 إضافية
);

class CompleteTaskSheet extends StatefulWidget {
  final Map<String, dynamic> taskData;
  final DateTime selectedDay;
  final String userTaskDocId;

  const CompleteTaskSheet({
    super.key,
    required this.taskData,
    required this.selectedDay,
    required this.userTaskDocId,
  });

  @override
  State<CompleteTaskSheet> createState() => _CompleteTaskSheetState();
}

class _CompleteTaskSheetState extends State<CompleteTaskSheet> {
  static const String _localProductTaskId = 'z5MNCTfrWZBkXFHVL9aS';

  bool get _isLocalProductTask {
    final id = (widget.taskData['id'] ?? '').toString().trim().toLowerCase();
    final taskId = (widget.taskData['taskId'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    return id == _localProductTaskId.toLowerCase() ||
        taskId == _localProductTaskId.toLowerCase();
  }

  CameraController? _controller;
  List<CameraDescription>? _cameras;
  final TextEditingController _itemCountCtrl = TextEditingController();
  late final GeminiResolverService _geminiResolver;
  String? _selectedMeasureUnit; // kg, g, L, mL
  double? _enteredMeasureValue;
  String? _selectedProductType; // solid or liquid
  String? _enteredProductName;
  bool _ready = false;
  bool _openingCamera = false;
  bool _isCapturing = false;
  bool _isUploading = false;
  bool _isCompleted = false;
  bool _locationDenied = false; // ← أضيفيه مع باقي المتغيرات

  // ─── Route Tracking ───
  final List<_TrackPoint> _trackPoints = [];
  Timer? _trackingTimer;
  bool _isTracking = false;
  String _transportVerifyPhase = 'start'; // 'start' أو 'end'

  bool _isAiApproved(TaskVerificationResult? r) {
    if (r == null) return false;
    if (r.success != true) return false;
    if (r.verified != true) return false;

    if (r.verificationSource == 'location') return true;

    final conf = r.confidence ?? 0.0;
    if (conf < 0.70) return false;

    if (r.verificationSource == 'origin_check') return true;
    if (r.verificationSource == 'ocr_smart') return true;

    if (r.verificationSource == 'vision' || r.verificationSource == null) {
      final isLogical = OCRService.isModelResultValid(
        r.taskName,
        widget.taskData['title']?.toString() ?? '',
      );
      return isLogical;
    }

    return false;
  }

  String _dayId(DateTime dt) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)}';
  }

  String _fmtKgLocal(double kg) {
    final v = ((kg * 100).roundToDouble() / 100.0);
    return v.toStringAsFixed(v.truncateToDouble() == v ? 0 : 2);
  }

  String? _inlineError;
  String? _capturedPath;
  double _flashOpacity = 0.0;

  int _currentCameraIndex = 0;
  FlashMode _flashMode = FlashMode.off;

  double _minZoom = 1.0, _maxZoom = 1.0, _zoom = 1.0;
  double _minExposure = 0.0, _maxExposure = 0.0, _exposure = 0.0;

  Position? _startPos;
  GeoPoint? _geoStart, _geoEnd;
  double? _autoDistanceKmComputed;

  LatLng? _manualStart;
  LatLng? _manualEnd;
  double? _manualDistanceKm;

  int? _itemCount;
  String? _verificationHint;
  String? _geminiCanonicalQuery;
  String? _geminiCategory;

  double? _resolvedDensityKgPerLiter;
  String? _resolvedDensitySource;
  double? _resolvedDensityConfidence;
  bool _resolvedDensityTrusted = false;

  TaskVerificationResult? _verificationResult;
  bool _isVerifying = false;
  bool _usedEstimatedLocalFallback = false;

  static const double _defaultLocalItemMassKg = 0.5;

  Map<String, dynamic> get _calcRequires {
    final v = widget.taskData['calc_requires'];
    return (v is Map)
        ? v.map((k, v) => MapEntry(k.toString(), v))
        : <String, dynamic>{};
  }

  bool get _autoDistance =>
      (_calcRequires['autoDistance'] == true) ||
      (widget.taskData['autoDistance'] == true);

  bool get _isTransportTask {
    final s =
        '${widget.taskData['category'] ?? ''} ${widget.taskData['title'] ?? ''}';
    final kws = [
      'نقل',
      'المواصلات',
      'مترو',
      'ميترو',
      'قطار',
      'باص',
      'حافلة',
      'دراجة',
      'سكوتر',
      'مشياً',
      'مشيا',
    ];

    // ← أضيفي هذا
    final validation =
        (widget.taskData['validationStrategy'] ??
                widget.taskData['taskValidation'] ??
                '')
            .toString();
    if (validation == 'التحقق عبر الموقع') return true;

    return kws.any((k) => s.contains(k));
  }

  bool get _requiresItemDialog {
    final mode = (widget.taskData['calcMode'] ?? '')
        .toString()
        .toLowerCase()
        .trim();
    return mode == 'deltaperitem';
  }

  String _yyyyMMdd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';

  double _deg2rad(double deg) => deg * math.pi / 180.0;

  double _haversineKm(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371.0;
    final dLat = _deg2rad(lat2 - lat1);
    final dLon = _deg2rad(lon2 - lon1);
    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_deg2rad(lat1)) *
            math.cos(_deg2rad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return R * c;
  }

  String _friendlyError(Object e) {
    if (e is CameraException) {
      switch (e.code) {
        case 'cameraAccessDenied':
        case 'CameraAccessDenied':
          return 'السماح للكاميرا مرفوض.';
        case 'cameraDisconnected':
          return 'تم فصل الكاميرا.';
        default:
          return 'خطأ في الكاميرا.';
      }
    }
    if (e is FirebaseException) {
      final code = e.code.toLowerCase();
      if (code.contains('permission-denied')) return 'صلاحيات غير كافية.';
      if (code.contains('unauthorized')) return 'غير مُخوّل.';
      if (code.contains('object-not-found')) return 'المسار غير موجود.';
      if (code.contains('not-found')) return 'المورد غير موجود.';
      if (code.contains('quota-exceeded')) return 'تم تجاوز الحصة.';
      if (code.contains('retry-limit-exceeded')) return 'انقطع الاتصال.';
      if (code.contains('unavailable')) return 'الخدمة غير متاحة مؤقتًا.';
      return 'خطأ (${e.code}).';
    }
    final s = e.toString();
    if (s.contains('socket') || s.contains('host')) return 'تحقق من الإنترنت.';
    return 'حدث خطأ غير متوقع.';
  }

  void _showInlineError(String msg) {
    if (!mounted) return;
    setState(() => _inlineError = msg);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _inlineError = null);
    });
  }

  // ─────────────────────────────────────────────
  //  Route Tracking — بدء / إيقاف / تسجيل نقطة
  // ─────────────────────────────────────────────

  void _startRouteTracking() {
    _trackPoints.clear();
    _isTracking = true;
    _trackingTimer?.cancel();

    // نسجل أول نقطة فوراً
    _recordTrackPoint();

    // ثم كل 15 ثانية — توازن بين الدقة واستهلاك البطارية
    _trackingTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (_isTracking) _recordTrackPoint();
    });
    print('🛤️ بدأ تتبع المسار');
  }

  void _stopRouteTracking() {
    _trackingTimer?.cancel();
    _trackingTimer = null;
    _isTracking = false;
    print('🛑 توقف تتبع المسار — عدد النقاط: ${_trackPoints.length}');
  }

  Future<void> _recordTrackPoint() async {
    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium, // medium يوفر البطارية
        timeLimit: const Duration(seconds: 8),
      );

      // تجاهل قراءات GPS ضعيفة الدقة (أكثر من 50 متر خطأ)
      if (pos.accuracy > 50) {
        print('⚠️ دقة GPS ضعيفة: ${pos.accuracy}م — تجاهل النقطة');
        return;
      }

      _trackPoints.add(
        _TrackPoint(
          lat: pos.latitude,
          lng: pos.longitude,
          time: DateTime.now(),
        ),
      );
      print(
        '📍 نقطة #${_trackPoints.length}: ${pos.latitude}, ${pos.longitude}',
      );
    } catch (e) {
      // نتجاهل الخطأ — الانقطاعات القصيرة طبيعية في الأنفاق
      print('⚠️ فشل تسجيل نقطة GPS: $e');
    }
  }

  // ─────────────────────────────────────────────
  //  تحليل المسار مع thresholds حسب نوع المواصلات
  // ─────────────────────────────────────────────

  _TrackAnalysis _analyzeTrack(
    List<_TrackPoint> points,
    _TransportThresholds thresholds,
  ) {
    // رحلة قصيرة جداً — نقاط غير كافية للتحليل، نقبلها
    if (points.length < 2) {
      print('ℹ️ نقاط غير كافية للتحليل (${points.length}) — قبول تلقائي');
      return const _TrackAnalysis(isValid: true);
    }

    final speeds = <double>[];

    for (int i = 1; i < points.length; i++) {
      final distKm = _haversineKm(
        points[i - 1].lat,
        points[i - 1].lng,
        points[i].lat,
        points[i].lng,
      );
      final seconds = points[i].time.difference(points[i - 1].time).inSeconds;
      if (seconds <= 0) continue;

      final speedKmh = (distKm / seconds) * 3600;

      // تجاهل القفزات الشاذة في GPS
      // (أكثر من 200 كم/س = خطأ في الجهاز وليس سرعة حقيقية)
      if (speedKmh > 200) {
        print('⚠️ قفزة GPS شاذة: ${speedKmh.toStringAsFixed(0)} كم/س — تجاهل');
        continue;
      }

      speeds.add(speedKmh);
    }

    if (speeds.isEmpty) {
      return const _TrackAnalysis(isValid: true, totalPoints: 0);
    }

    final avgSpeed = speeds.reduce((a, b) => a + b) / speeds.length;
    final maxSpeed = speeds.reduce(math.max);

    print('📊 تحليل المسار:');
    print('   - نقاط: ${points.length}');
    print('   - متوسط السرعة: ${avgSpeed.toStringAsFixed(1)} كم/س');
    print('   - السرعة القصوى: ${maxSpeed.toStringAsFixed(1)} كم/س');
    print('   - الحد المسموح للمتوسط: ${thresholds.maxAvgSpeed} كم/س');
    print('   - الحد المسموح للقصوى: ${thresholds.maxPeakSpeed} كم/س');

    // الرفض يتطلب تجاوز الحدين معاً (شرط مزدوج)
    // عشان ما نعاقب يوزر شريف بسبب قراءة GPS عرضية واحدة
    final avgTooHigh = avgSpeed > thresholds.maxAvgSpeed;
    final peakTooHigh = maxSpeed > thresholds.maxPeakSpeed;

    if (avgTooHigh && peakTooHigh) {
      return _TrackAnalysis(
        isValid: false,
        avgSpeed: avgSpeed,
        maxSpeed: maxSpeed,
        totalPoints: points.length,
        rejectionReason:
            'السرعة المسجلة تتجاوز حد المواصلات العامة\n'
            'متوسط: ${avgSpeed.toStringAsFixed(0)} كم/س  •  '
            'أقصى: ${maxSpeed.toStringAsFixed(0)} كم/س',
      );
    }

    return _TrackAnalysis(
      isValid: true,
      avgSpeed: avgSpeed,
      maxSpeed: maxSpeed,
      totalPoints: points.length,
    );
  }

  // ─────────────────────────────────────────────
  //  تحديد الـ thresholds من عنوان المهمة
  // ─────────────────────────────────────────────

  _TransportThresholds _getThresholdsForTask() {
    final title = (widget.taskData['title'] ?? '').toString().toLowerCase();
    if (title.contains('مترو') || title.contains('metro'))
      return _metroThresholds;
    if (title.contains('باص') ||
        title.contains('bus') ||
        title.contains('حافلة'))
      return _busThresholds;
    if (title.contains('دراجة') ||
        title.contains('سيكل') ||
        title.contains('cycle'))
      return _bicycleThresholds;
    if (title.contains('سكوتر') || title.contains('scooter'))
      return _scooterThresholds;
    if (title.contains('مشياً') ||
        title.contains('مشيا') ||
        title.contains('مشي'))
      return _walkThresholds;
    return _busThresholds;
  }

  String _getTransportButtonLabel() {
    final t = (widget.taskData['title'] ?? '').toString().toLowerCase();
    if (t.contains('مترو') || t.contains('metro')) return 'اختر محطات المترو';
    if (t.contains('باص') || t.contains('bus') || t.contains('حافلة'))
      return 'اختر محطات الباص';
    if (t.contains('دراجة') || t.contains('سيكل') || t.contains('cycle'))
      return 'حدد مسار الدراجة';
    if (t.contains('سكوتر') || t.contains('scooter')) return 'حدد مسار السكوتر';
    if (t.contains('مشياً') || t.contains('مشيا') || t.contains('مشي'))
      return 'حدد مسار المشي';
    return 'اختر المسار';
  }

  String _getArrivalLabel() {
    final t = (widget.taskData['title'] ?? '').toString().toLowerCase();
    if (t.contains('مترو') || t.contains('metro'))
      return 'وصلت إلى محطة المترو';
    if (t.contains('باص') || t.contains('bus') || t.contains('حافلة'))
      return 'وصلت إلى محطة الباص';
    if (t.contains('دراجة') || t.contains('سيكل') || t.contains('cycle'))
      return 'وصلت إلى وجهتي بالدراجة';
    if (t.contains('سكوتر') || t.contains('scooter'))
      return 'وصلت إلى وجهتي بالسكوتر';
    if (t.contains('مشياً') || t.contains('مشيا') || t.contains('مشي'))
      return 'وصلت إلى وجهتي مشياً';
    return 'وصلت إلى نقطة الوصول';
  }

  IconData _getTransportIcon() {
    final t = (widget.taskData['title'] ?? '').toString().toLowerCase();
    if (t.contains('مترو') || t.contains('metro')) return Icons.train_rounded;
    if (t.contains('باص') || t.contains('bus') || t.contains('حافلة'))
      return Icons.directions_bus_rounded;
    if (t.contains('دراجة') || t.contains('سيكل') || t.contains('cycle'))
      return Icons.directions_bike_rounded;
    if (t.contains('سكوتر') || t.contains('scooter'))
      return Icons.electric_scooter_rounded;
    if (t.contains('مشياً') || t.contains('مشيا') || t.contains('مشي'))
      return Icons.directions_walk_rounded;
    return Icons.map_outlined;
  }

  // ─────────────────────────────────────────────
  //  Transport Flow
  // ─────────────────────────────────────────────

  Future<void> _startFlowForTransportTask() async {
    final taskTitle = widget.taskData['title']?.toString() ?? '';
    final t = taskTitle.toLowerCase(); // ← أضيفي هذا السطر

    final String stationType;
    if (t.contains('ميترو') || t.contains('metro')) {
      // ← غيري taskTitle إلى t
      stationType = 'metro';
    } else if (t.contains('باص') || t.contains('bus') || t.contains('حافلة')) {
      // ← t
      stationType = 'bus';
    } else if (t.contains('دراجة') ||
        t.contains('سيكل') ||
        t.contains('cycle')) {
      // ← t
      stationType = 'bicycle';
    } else if (t.contains('سكوتر') || t.contains('scooter')) {
      // ← t
      stationType = 'scooter';
    } else {
      stationType = 'walk';
    }

    final MapRoutePickResult? res =
        await Navigator.of(
          context,
          rootNavigator: true,
        ).push<MapRoutePickResult>(
          MaterialPageRoute(
            builder: (_) => MapPickRoutePage(stationType: stationType),
            fullscreenDialog: true,
          ),
        );

    if (!mounted || res == null) return;

    setState(() {
      _manualStart = res.start;
      _manualEnd = res.end;
      _manualDistanceKm = res.distanceKm;
      _geoStart = GeoPoint(_manualStart!.latitude, _manualStart!.longitude);
      _geoEnd = GeoPoint(_manualEnd!.latitude, _manualEnd!.longitude);
      _transportVerifyPhase = 'start';
    });

    await _verifyTransportByLocation();
  }

  Future<void> _verifyTransportByLocation() async {
    if (_manualStart == null || _manualEnd == null) return;
    if (mounted) setState(() => _isVerifying = true);

    try {
      await _ensureLocationPermission();
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );

      const radiusMeters = 150.0;

      double haversineMeters(LatLng a, LatLng b) {
        const R = 6371000.0;
        final dLat = _deg2rad(b.latitude - a.latitude);
        final dLon = _deg2rad(b.longitude - a.longitude);
        final h =
            math.sin(dLat / 2) * math.sin(dLat / 2) +
            math.cos(_deg2rad(a.latitude)) *
                math.cos(_deg2rad(b.latitude)) *
                math.sin(dLon / 2) *
                math.sin(dLon / 2);
        return 2 * R * math.atan2(math.sqrt(h), math.sqrt(1 - h));
      }

      final userLatLng = LatLng(pos.latitude, pos.longitude);
      final distToStart = haversineMeters(userLatLng, _manualStart!);
      final distToEnd = haversineMeters(userLatLng, _manualEnd!);
      final nearStart = distToStart <= radiusMeters;
      final nearEnd = distToEnd <= radiusMeters;

      if (mounted) setState(() => _isVerifying = false);

      // ══════════════════════════════════════
      //  المرحلة الأولى — عند محطة البداية
      // ══════════════════════════════════════
      if (_transportVerifyPhase == 'start') {
        if (nearStart) {
          // ✅ بدأ التتبع فوراً
          _startRouteTracking();

          if (!mounted) return;
          await showDialog<void>(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => Directionality(
              textDirection: TextDirection.rtl,
              child: Dialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                insetPadding: const EdgeInsets.symmetric(horizontal: 24),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _getTransportIcon(),
                        color: appColors.primary,
                        size: 52,
                      ),

                      const SizedBox(height: 12),
                      Text(
                        'تم التحقق من محطة البداية ✅',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.ibmPlexSansArabic(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: appColors.dark,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'سيتم تتبع مسارك تلقائياً أثناء الرحلة.\n'
                        'عند وصولك لمحطة الوصول اضغط "وصلت".',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.ibmPlexSansArabic(
                          fontSize: 14,
                          height: 1.7,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.of(ctx).pop();
                            if (mounted) {
                              setState(() => _transportVerifyPhase = 'end');
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: appColors.primary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: Text(
                            'حسناً، سأتوجه الآن',
                            style: GoogleFonts.ibmPlexSansArabic(
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        } else {
          // ❌ بعيد عن محطة البداية
          await _showNotNearStationDialog(
            distanceMeters: distToStart,
            radiusMeters: radiusMeters,
            message: 'يجب أن تكون عند محطة البداية أولاً',
            onRetry: _verifyTransportByLocation,
            onChangeStations: () => setState(() {
              _manualStart = _manualEnd = null;
              _manualDistanceKm = null;
              _geoStart = _geoEnd = null;
              _transportVerifyPhase = 'start';
              _stopRouteTracking();
              _trackPoints.clear();
            }),
          );
        }
        return;
      }

      // ══════════════════════════════════════
      //  المرحلة الثانية — عند محطة النهاية
      // ══════════════════════════════════════
      if (_transportVerifyPhase == 'end') {
        // أوقف التتبع وسجل آخر نقطة قبل التحليل
        _stopRouteTracking();
        await _recordTrackPoint();

        if (nearEnd) {
          // ✅ موقع النهاية صحيح — حلل المسار
          final thresholds = _getThresholdsForTask();
          final analysis = _analyzeTrack(_trackPoints, thresholds);

          if (analysis.isValid) {
            // ✅ كل شيء سليم — أكمل المهمة
            setState(() {
              _verificationResult = TaskVerificationResult(
                success: true,
                verified: true,
                verificationSource: 'location',
              );
              _transportVerifyPhase = 'start';
            });
            await _uploadAndComplete();
          } else {
            // ❌ تحليل المسار يشير لسيارة
            if (!mounted) return;
            await showDialog<void>(
              context: context,
              barrierDismissible: false,
              builder: (ctx) => Directionality(
                textDirection: TextDirection.rtl,
                child: Dialog(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  insetPadding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Image.asset(
                          'assets/img/nameerSad.png',
                          height: 100,
                          fit: BoxFit.contain,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'لم يتم التحقق من الرحلة',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.ibmPlexSansArabic(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: appColors.dark,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          analysis.rejectionReason ??
                              'يبدو أن الرحلة لم تكن بالمواصلات العامة',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.ibmPlexSansArabic(
                            fontSize: 14,
                            height: 1.6,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () {
                                  Navigator.of(ctx).pop();
                                  setState(() {
                                    _manualStart = _manualEnd = null;
                                    _manualDistanceKm = null;
                                    _geoStart = _geoEnd = null;
                                    _transportVerifyPhase = 'start';
                                    _trackPoints.clear();
                                  });
                                },
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(
                                    color: appColors.primary,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                ),
                                child: Text(
                                  'تغيير المحطات',
                                  style: GoogleFonts.ibmPlexSansArabic(
                                    fontWeight: FontWeight.w700,
                                    color: appColors.primary,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: () {
                                  Navigator.of(ctx).pop();
                                  // إعادة المحاولة من محطة البداية
                                  setState(() {
                                    _transportVerifyPhase = 'start';
                                    _trackPoints.clear();
                                  });
                                  _verifyTransportByLocation();
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: appColors.primary,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                ),
                                child: Text(
                                  'إعادة المحاولة',
                                  style: GoogleFonts.ibmPlexSansArabic(
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }
        } else {
          // ❌ بعيد عن محطة النهاية — نعيد التتبع لو قرر يكمل
          await _showNotNearStationDialog(
            distanceMeters: distToEnd,
            radiusMeters: radiusMeters,
            message: 'يجب أن تكون عند محطة الوصول للتحقق',
            onRetry: () {
              // نكمل التتبع من حيث توقف
              _startRouteTracking();
              _verifyTransportByLocation();
            },
            onChangeStations: () => setState(() {
              _manualStart = _manualEnd = null;
              _manualDistanceKm = null;
              _geoStart = _geoEnd = null;
              _transportVerifyPhase = 'start';
              _stopRouteTracking();
              _trackPoints.clear();
            }),
          );
        }
      }
    } catch (e) {
      _stopRouteTracking();
      if (mounted) setState(() => _isVerifying = false);
      _showInlineError('تعذر الحصول على الموقع');
    }
  }

  // ─────────────────────────────────────────────
  //  Dialog مساعد — "أنت بعيد عن المحطة"
  // ─────────────────────────────────────────────

  Future<void> _showNotNearStationDialog({
    required double distanceMeters,
    required double radiusMeters,
    required String message,
    required VoidCallback onRetry,
    required VoidCallback onChangeStations,
  }) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          insetPadding: const EdgeInsets.symmetric(horizontal: 24),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.location_off_rounded,
                  color: Colors.redAccent,
                  size: 52,
                ),
                const SizedBox(height: 12),
                Text(
                  'الموقع الحالي بعيد عن المحطة',
                  style: GoogleFonts.ibmPlexSansArabic(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: appColors.dark,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  '$message\n'
                  'المسافة الحالية: ${distanceMeters.toStringAsFixed(0)} متر\n'
                  'المسافة المسموحة: ${radiusMeters.toInt()} متر',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.ibmPlexSansArabic(
                    fontSize: 14,
                    height: 1.6,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          onChangeStations();
                        },
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: appColors.primary),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: Text(
                          'تغيير المحطات',
                          style: GoogleFonts.ibmPlexSansArabic(
                            fontWeight: FontWeight.w700,
                            color: appColors.primary,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          onRetry();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: appColors.primary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: Text(
                          'إعادة المحاولة',
                          style: GoogleFonts.ibmPlexSansArabic(
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> showTaskCompletedDialogAndRedirect(BuildContext context) async {
    await Future.delayed(const Duration(milliseconds: 300));

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          insetPadding: const EdgeInsets.symmetric(horizontal: 24),
          child: SizedBox(
            width: 340,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset(
                    'assets/img/nameerLove.png',
                    height: 120,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'تم إنجاز المهمة',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.ibmPlexSansArabic(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: appColors.dark,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'تم تسجيل إنجاز المهمة بنجاح\nوتمت إضافة النقاط مباشرة',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.ibmPlexSansArabic(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: appColors.dark,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Center(
                    child: SizedBox(
                      width: 140,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: appColors.primary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 10,
                          ),
                        ),
                        onPressed: () async {
                          Navigator.of(dialogContext).pop();
                          await Future.delayed(
                            const Duration(milliseconds: 200),
                          );
                          if (!mounted) return;
                          Navigator.of(context).pop(true);
                          Navigator.of(context).pushAndRemoveUntil(
                            MaterialPageRoute(builder: (_) => const taskPage()),
                            (route) => false,
                          );
                        },
                        child: Text(
                          'تم',
                          style: GoogleFonts.ibmPlexSansArabic(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String _getCategoryKey(String title) {
    final t = title.toLowerCase();
    if (t.contains('مترو') || t.contains('metro')) return 'metro';
    if (t.contains('باص') || t.contains('bus') || t.contains('حافلة'))
      return 'bus';
    if (t.contains('دراجة') || t.contains('سيكل') || t.contains('cycle'))
      return 'cycle';
    if (t.contains('تدوير') || t.contains('recycl')) return 'recycling';
    if (t.contains('مقال') || t.contains('اختبار') || t.contains('article'))
      return 'article';
    if (t.contains('محلي') || t.contains('local') || t.contains('منتج'))
      return 'local'; // ← جديد
    if (t.contains('سكوتر') || t.contains('scooter')) return 'scooter';
    return 'other';
  }

  Future<TaskVerificationResult?> _verifyTaskImage(String imagePath) async {
    if (!mounted) return null;

    setState(() {
      _isVerifying = true;
      _verificationResult = null;
    });

    try {
      final taskTitle = widget.taskData['title']?.toString() ?? '';

      if (_isLocalProductTask) {
        final originResult = await TaskVerificationService.verifyOriginFromFile(
          File(imagePath),
          threshold: 0.7,
        );

        final c = originResult.countryOfOrigin;
        final isLocal = originResult.isLocalSaudi == true;
        final conf = originResult.confidence ?? 0.0;

        String msg;
        if (c == null || c.trim().isEmpty || conf < 0.6) {
          msg =
              '🔎 تم التحقق: بلد المنشأ غير واضح, يرجى إعادة التقاط صورة أوضح';
        } else if (isLocal) {
          msg = '✅ تم التحقق: بلد المنشأ $c (محلي)';
        } else {
          msg = '❌ تم التحقق: بلد المنشأ $c (غير محلي)';
        }

        if (mounted) {
          setState(() {
            _verificationResult = originResult.copyWith(
              verificationSource: 'origin_check',
            );
            _verificationHint = msg;
            _isVerifying = false;
          });
        }

        if (originResult.verified == true) {
          WidgetsBinding.instance.endOfFrame.then((_) {
            if (mounted) _uploadAndComplete();
          });
        }

        return originResult;
      }

      final cloudResult = await _tryCloudModelFirst(imagePath, taskTitle);
      final extractedText = await OCRService.extractTextFromFile(
        File(imagePath),
      );

      final isModelLogical = OCRService.isModelResultValid(
        cloudResult?.taskName,
        taskTitle,
      );
      final doesImageMatch = OCRService.doesImageMatchTask(
        extractedText,
        taskTitle,
      );

      TaskVerificationResult finalResult;

      if (cloudResult != null &&
          cloudResult.success == true &&
          isModelLogical) {
        finalResult = cloudResult.copyWith(verificationSource: 'vision');
      } else {
        finalResult = TaskVerificationResult(
          success: doesImageMatch,
          taskName: taskTitle,
          taskNameAr: OCRService.extractArabicTitle(taskTitle),
          confidence: doesImageMatch ? 0.85 : 0.0,
          confidencePercent: doesImageMatch ? '85%' : '0%',
          verified: doesImageMatch,
          matchesExpected: doesImageMatch,
          verificationSource: 'ocr_smart',
          extractedText: extractedText,
        );
      }

      if (mounted) {
        setState(() {
          _verificationResult = finalResult;
          _isVerifying = false;
        });
      }

      if (finalResult.verified == true) {
        WidgetsBinding.instance.endOfFrame.then((_) {
          if (mounted) _uploadAndComplete();
        });
      } else {
        _showInlineError('❌ الصورة غير مطابقة للمهمة');
        WidgetsBinding.instance.endOfFrame.then((_) {
          if (mounted) showTaskFailedDialogAndRedirect(context);
        });
      }

      return finalResult;
    } catch (e) {
      if (mounted) {
        setState(() => _isVerifying = false);
        _showInlineError('❌ فشل التحقق من الصورة');
      }
      return TaskVerificationResult(
        success: false,
        error: 'فشل التحقق: $e',
        verificationSource: 'system',
      );
    }
  }

  String _getDisplayTaskName(TaskVerificationResult? result, String taskTitle) {
    if (result?.taskNameAr != null && result!.taskNameAr!.isNotEmpty) {
      return result.taskNameAr!;
    }
    return OCRService.extractArabicTitle(taskTitle);
  }

  Future<TaskVerificationResult?> _tryCloudModelFirst(
    String imagePath,
    String taskTitle,
  ) async {
    try {
      final modelResult = await TaskVerificationService.verifyFromFile(
        File(imagePath),
        expectedTask: taskTitle,
        threshold: 0.7,
      );
      return modelResult;
    } catch (e) {
      print('❌ خطأ في Cloud Run: $e');
      return null;
    }
  }

  Future<void> _uploadAndComplete() async {
    if (_isUploading || _isVerifying) return;

    final isLocationVerified =
        _verificationResult?.verificationSource == 'location';

    if (_capturedPath == null && !isLocationVerified) {
      _showInlineError('لم يتم التقاط صورة');
      return;
    }

    final task = widget.taskData;
    final pts = (task['points'] ?? 0) as int;
    final taskId = task['id'] as String?;

    int? safeItems = _itemCount;
    final mode = (task['calcMode'] ?? '').toString().toLowerCase();
    if (_isLocalProductTask) {
      if (!_usedEstimatedLocalFallback &&
          (safeItems == null ||
              safeItems <= 0 ||
              _enteredMeasureValue == null ||
              _selectedMeasureUnit == null)) {
        final filled = await _promptForLocalProductInput();
        if (!filled) {
          if (!mounted) return;
          Navigator.of(context).pop(true);
          return;
        }

        safeItems = _itemCount;

        if (!_usedEstimatedLocalFallback &&
            (safeItems == null ||
                safeItems <= 0 ||
                _enteredMeasureValue == null ||
                _selectedMeasureUnit == null)) {
          _showInlineError('يرجى إدخال بيانات المنتج.');
          return;
        }
      }

      safeItems = _itemCount ?? 1;

      if (!_usedEstimatedLocalFallback &&
          _enteredProductName != null &&
          _enteredProductName!.trim().isNotEmpty) {
        await _resolveProductWithGemini();
      }
    } else if (mode == 'deltaperitem' &&
        (safeItems == null || safeItems <= 0)) {
      await _promptForItemCountIfNeeded();
      safeItems = _itemCount;
      if (safeItems == null || safeItems <= 0) {
        _showInlineError('يرجى إدخال عدد العناصر.');
        return;
      }
    }

    if (!mounted) return;
    setState(() {
      _isUploading = true;
      _isVerifying = false;
    });

    try {
      final isDistanceMode = mode == 'perkm' || mode == 'deltaperkm';
      double? pickedKm;

      if (isDistanceMode) {
        final manualKm = _manualDistanceKm;
        await _captureEndAndComputeDistance();
        double? straightKm;
        if (_autoDistanceKmComputed != null &&
            _autoDistanceKmComputed!.isFinite &&
            _autoDistanceKmComputed! > 0) {
          straightKm = double.parse(
            _autoDistanceKmComputed!.toStringAsFixed(3),
          );
        }
        if (manualKm != null && manualKm > 0) {
          pickedKm = manualKm;
        } else if (straightKm != null && straightKm > 0) {
          pickedKm = straightKm;
        }

        final askDistanceKm = task['askDistanceKm'] == true;
        final defaultKmOnSubmit = (task['defaultKmOnSubmit'] is num)
            ? (task['defaultKmOnSubmit'] as num).toDouble()
            : null;
        if (pickedKm == null && askDistanceKm && defaultKmOnSubmit != null) {
          pickedKm = defaultKmOnSubmit;
        }

        double? minKm, maxKm;
        final mk = task['minKm'];
        final xk = task['maxKm'];
        if (mk is num) minKm = mk.toDouble();
        if (xk is num) maxKm = xk.toDouble();
        if (pickedKm != null && pickedKm > 0) {
          final clamped = pickedKm.clamp(minKm ?? 0.2, maxKm ?? 50.0) as num;
          pickedKm = double.parse(clamped.toStringAsFixed(3));
        }

        if (_manualStart != null && _manualEnd != null) {
          _geoStart = GeoPoint(_manualStart!.latitude, _manualStart!.longitude);
          _geoEnd = GeoPoint(_manualEnd!.latitude, _manualEnd!.longitude);
        }
      }

      double? carbonSaved;
      final efId =
          (task['ef_ref'] ??
                  task['efRef'] ??
                  task['emissionFactorRef'] ??
                  task['emission_factor_ref'])
              ?.toString();
      final valueFieldFromTask = (task['ef_valueField'] ?? task['valueField'])
          ?.toString();
      if (efId != null && efId.isNotEmpty) {
        final saved = await _computeCarbonSavedFlexible(
          efIdFromTask: efId,
          km: pickedKm,
          items: safeItems,
          measureValue: _enteredMeasureValue,
          measureUnit: _selectedMeasureUnit,
          productType: _selectedProductType,
          valueFieldFromTask: valueFieldFromTask,
        );
        if (saved.isFinite) {
          carbonSaved = double.parse(saved.toStringAsFixed(3));
        }
      }

      await _createSubmissionAndAutoApprove(
        localPath: _capturedPath ?? '',
        taskPoints: pts,
        taskId: taskId,
        distanceKm: pickedKm,
        carbonSaved: carbonSaved,
        itemCount: safeItems,
      );

      setState(() => _isCompleted = true);

      if (!mounted) return;
      await showTaskCompletedDialogAndRedirect(context);

      try {
        if (_capturedPath != null) {
          final f = File(_capturedPath!);
          if (await f.exists()) await f.delete();
        }
      } catch (_) {}

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e, stackTrace) {
      print('❌ خطأ في _uploadAndComplete: $e\n$stackTrace');
      if (!mounted) return;

      String errorMessage = 'حدث خطأ أثناء إكمال المهمة';
      if (e.toString().contains('403'))
        errorMessage = 'خطأ في صلاحيات التطبيق. يرجى المحاولة مرة أخرى.';
      else if (e.toString().contains('Too many attempts'))
        errorMessage =
            'محاولات كثيرة جداً. يرجى الانتظار قليلاً ثم المحاولة مرة أخرى.';
      else if (e.toString().contains('network') ||
          e.toString().contains('اتصال'))
        errorMessage = 'مشكلة في الاتصال بالإنترنت. يرجى التحقق من الاتصال.';
      else if (e is TimeoutException) // ← أضيفي هذا
        errorMessage =
            'انتهت مهلة رفع الصورة. يرجى التحقق من الاتصال ثم المحاولة مرة أخرى.';
      _showInlineError(errorMessage);
      if (mounted) setState(() => _isUploading = false);
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  String? _getArabicTaskName(String? taskName) {
    if (taskName == null) return null;
    const arabicNames = {
      'plastic': 'بلاستيك',
      'paper': 'ورق',
      'food': 'نفايات عضوية',
      'cloth': 'ملابس',
      'metro': 'مترو',
      'bus': 'باص',
      'bicycle': 'دراجة هوائية',
      'scooter': 'سكوتر',
      'rvm': 'آلة التدوير',
    };
    return arabicNames[taskName] ?? taskName;
  }

  TaskType? _getLocationTaskType(String title) {
    final t = title.toLowerCase();
    if (t.contains('مترو') || t.contains('metro')) return TaskType.metro;
    if (t.contains('باص') || t.contains('bus') || t.contains('حافلة'))
      return TaskType.bus;
    if (t.contains('ملابس') || t.contains('cloth')) return TaskType.clothing;
    if (t.contains('ورق') || t.contains('paper') || t.contains('أوراق'))
      return TaskType.paper;
    if (t.contains('طعام') || t.contains('food') || t.contains('عضوي'))
      return TaskType.food;
    if (t.contains('rvm') || t.contains('تدوير') || t.contains('بلاستيك'))
      return TaskType.rvm;
    return null;
  }

  Future<void> _ensureLocationPermission() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        perm = await Geolocator.requestPermission();
      }
    } catch (_) {}
  }

  Future<void> _captureStartIfNeeded() async {
    if (!(_autoDistance || _isTransportTask)) return;
    try {
      await _ensureLocationPermission();
      final p = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      _startPos = p;
      _geoStart = GeoPoint(p.latitude, p.longitude);
    } catch (_) {}
  }

  Future<void> _captureEndAndComputeDistance() async {
    if (!(_autoDistance || _isTransportTask)) return;
    try {
      await _ensureLocationPermission();
      final end = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      _geoEnd = GeoPoint(end.latitude, end.longitude);
      final start = _startPos ?? end;
      _autoDistanceKmComputed = _haversineKm(
        start.latitude,
        start.longitude,
        end.latitude,
        end.longitude,
      );
      if (mounted) setState(() {});
    } catch (_) {}
  }

  static const String _kEfCollection = 'emissionFactors';

  double? _asDouble(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v.trim());
    return null;
  }

  int? _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v.trim());
    return null;
  }

  Future<Map<String, dynamic>?> _getEfDoc(String id) async {
    if (id.isEmpty) return null;
    final doc = await FirebaseFirestore.instance
        .collection(_kEfCollection)
        .doc(id)
        .get();
    return doc.data();
  }

  Future<double?> _getEfPerUnit(String id, {String? valueFieldFromTask}) async {
    final d = await _getEfDoc(id);
    if (d == null) return null;
    if (valueFieldFromTask != null && valueFieldFromTask.isNotEmpty) {
      final v = _asDouble(d[valueFieldFromTask]);
      if (v != null) return v;
    }
    final vfInDoc = d['valueField'] ?? d['efValueField'];
    if (vfInDoc is String && vfInDoc.isNotEmpty) {
      final v = _asDouble(d[vfInDoc]);
      if (v != null) return v;
    }
    for (final k in [
      'ef_kgco2_per_unit',
      'ef_kgco2_per_item',
      'value',
      'kgPerItem',
      'perItem',
      'kgPerKm',
      'perKm',
      'co2PerKm',
      'co2_per_km',
      'factor',
    ]) {
      final v = _asDouble(d[k]);
      if (v != null) return v;
    }
    return null;
  }

  Future<double> _computeCarbonSavedFlexible({
    required String efIdFromTask,
    double? km,
    int? items,
    double? measureValue,
    String? measureUnit,
    String? productType,
    String? valueFieldFromTask,
  }) async {
    final efDoc = await _getEfDoc(efIdFromTask) ?? {};
    final taskCalcMode = (widget.taskData['calcMode'] ?? '').toString().trim();
    final efCalcMode = (efDoc['calcMode'] ?? '').toString().trim();
    final calcMode = (taskCalcMode.isNotEmpty ? taskCalcMode : efCalcMode)
        .toLowerCase();

    // ✅ منطق المنتج المحلي حسب معادلة النقل:
    // avoided_emissions = mass_tonnes × distance_km × EF_transport
    if (_isLocalProductTask) {
      if (items == null || items <= 0) return 0.0;

      double? massKg;

      if (_usedEstimatedLocalFallback) {
        massKg = _defaultLocalItemMassKg * items;
      } else {
        if (measureValue == null ||
            measureValue <= 0 ||
            measureUnit == null ||
            measureUnit.isEmpty ||
            productType == null ||
            productType.isEmpty) {
          return 0.0;
        }

        final densityKgPerLiter =
            _resolvedDensityKgPerLiter ??
            _asDouble(
              efDoc['density_kg_per_liter'] ??
                  efDoc['densityKgPerLiter'] ??
                  efDoc['density'],
            );

        massKg = _computeLocalProductMassKg(
          measureValue: measureValue,
          measureUnit: measureUnit,
          itemCount: items,
          productType: productType,
          densityKgPerLiter: densityKgPerLiter,
        );
      }

      if (massKg == null || massKg <= 0) return 0.0;

      final massTonnes = massKg / 1000.0;

      final referenceDistanceKm = _asDouble(
        widget.taskData['referenceDistanceKm'] ??
            widget.taskData['reference_distance_km'] ??
            efDoc['referenceDistanceKm'] ??
            efDoc['reference_distance_km'],
      );

      final transportEf = _asDouble(
        efDoc['ef_kgco2e_per_tonne_km'] ??
            efDoc['ef_kgco2_per_tonne_km'] ??
            efDoc['transportEfPerTonneKm'] ??
            efDoc['factor'] ??
            efDoc['value'],
      );

      if (referenceDistanceKm == null ||
          referenceDistanceKm <= 0 ||
          transportEf == null ||
          transportEf <= 0) {
        return 0.0;
      }

      final avoided = massTonnes * referenceDistanceKm * transportEf;
      debugPrint('massKg: $massKg');
      debugPrint('massTonnes: $massTonnes');
      debugPrint('referenceDistanceKm: $referenceDistanceKm');
      debugPrint('transportEf: $transportEf');
      debugPrint('avoided: $avoided');
      debugPrint('usedEstimatedFallback: $_usedEstimatedLocalFallback');

      return double.parse(avoided.toStringAsFixed(3));
    }

    // ✅ باقي المهام القديمة كما هي
    if (calcMode == 'deltaperitem' && items != null && items > 0) {
      final directDelta = _asDouble(
        efDoc['ef_kgco2_per_unit'] ??
            efDoc['ef_kgco2_per_item'] ??
            efDoc['value'] ??
            efDoc['factor'],
      );
      if (directDelta != null && directDelta > 0) {
        return double.parse((directDelta * items).toStringAsFixed(3));
      }
    }

    return 0.0;
  }

  Future<XFile?> _safeTakePicture() async {
    if (_controller == null || !_controller!.value.isInitialized) {
      _showInlineError('الكاميرا غير جاهزة.');
      return null;
    }
    if (_controller!.value.isTakingPicture) return null;
    try {
      return await _controller!.takePicture();
    } on CameraException catch (e) {
      try {
        await Future.delayed(const Duration(milliseconds: 150));
        if (!_controller!.value.isInitialized ||
            _controller!.value.isTakingPicture)
          return null;
        return await _controller!.takePicture();
      } catch (_) {
        _showInlineError(_friendlyError(e));
        return null;
      }
    } catch (e) {
      _showInlineError(_friendlyError(e));
      return null;
    }
  }

  Future<void> _createSubmissionAndAutoApprove({
    required String localPath,
    required int taskPoints,
    String? taskId,
    double? distanceKm,
    double? carbonSaved,
    int? itemCount,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('يرجى تسجيل الدخول.');

    final uid = user.uid;
    final dayKey = _yyyyMMdd(widget.selectedDay);
    final taskTitle = (widget.taskData['title'] ?? '').toString();

    final bool hasPhoto = localPath.isNotEmpty;
    String downloadUrl = '';
    String storagePath = '';

    if (hasPhoto) {
      final file = File(localPath);
      final basePath = 'submissions/$uid/${dayKey}_${widget.userTaskDocId}';
      final name = DateTime.now().millisecondsSinceEpoch.toString();
      final storageRef = FirebaseStorage.instance.ref('$basePath/$name.jpg');
      // For performance, we set a timeout on the upload and download operations.
      await storageRef
          .putFile(file, SettableMetadata(contentType: 'image/jpeg'))
          .timeout(
            const Duration(seconds: 60),
            onTimeout: () => throw TimeoutException(
              'انتهت مهلة رفع الصورة، يرجى المحاولة مرة أخرى',
            ),
          );
      downloadUrl = await storageRef.getDownloadURL().timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw TimeoutException('انتهت مهلة جلب رابط الصورة'),
      );
      downloadUrl = await storageRef.getDownloadURL();
      storagePath = storageRef.fullPath;
    }

    final double carbonForStore = (carbonSaved != null && carbonSaved.isFinite)
        ? double.parse(carbonSaved.toStringAsFixed(3))
        : 0.0;

    final firestore = FirebaseFirestore.instance;
    final usersRef = firestore.collection('users').doc(uid);
    final utRef = firestore.collection('userTasks').doc(widget.userTaskDocId);
    final subRef = firestore.collection('submissions').doc();
    final todayId = _dayId(DateTime.now());
    final dayMarkRef = firestore
        .collection('users')
        .doc(uid)
        .collection('dayMarks')
        .doc(todayId);
    final dailyTaskRef = firestore
        .collection('dailyTasks')
        .doc(uid)
        .collection('tasks')
        .doc(_dayId(widget.selectedDay));

    final utSnapshot = await utRef.get();
    String currentStatus = 'pending';
    if (utSnapshot.exists) {
      currentStatus =
          ((utSnapshot.data() as Map<String, dynamic>)['status'] as String?) ??
          'pending';
    }

    await firestore.runTransaction((trx) async {
      trx.set(subRef, {
        'userId': uid,
        'userTaskDocId': widget.userTaskDocId,
        'taskId': taskId ?? '',
        'taskTitle': taskTitle,
        'taskPoints': taskPoints,
        'status': 'approved',
        'imageUrls': hasPhoto ? [downloadUrl] : [],
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'carbonSaved': carbonForStore,
        if (distanceKm != null) 'distanceKm': distanceKm,
        if (itemCount != null) 'itemCount': itemCount,

        if (_geoStart != null) 'geoStart': _geoStart,
        if (_geoEnd != null) 'geoEnd': _geoEnd,
        if (_selectedProductType != null) 'productType': _selectedProductType,
        if (_enteredMeasureValue != null) 'measureValue': _enteredMeasureValue,
        if (_selectedMeasureUnit != null) 'measureUnit': _selectedMeasureUnit,
        if (_enteredProductName != null) 'productName': _enteredProductName,
        if (_geminiCanonicalQuery != null)
          'geminiCanonicalQuery': _geminiCanonicalQuery,
        if (_geminiCategory != null) 'geminiCategory': _geminiCategory,
        if (_resolvedDensityKgPerLiter != null)
          'densityKgPerLiter': _resolvedDensityKgPerLiter,
        if (_resolvedDensitySource != null)
          'densitySource': _resolvedDensitySource,
        if (_resolvedDensityConfidence != null)
          'densityConfidence': _resolvedDensityConfidence,
        'densityTrusted': _resolvedDensityTrusted,
      }, SetOptions(merge: true));

      trx.set(utRef, {
        'userId': uid,
        'status': 'completed',
        'completedAt': FieldValue.serverTimestamp(),
        'taskPoints': taskPoints,
        'taskTitle': taskTitle,
        'carbonSaved': carbonForStore,
        'evidence': hasPhoto
            ? {'type': 'photo', 'url': downloadUrl, 'storagePath': storagePath}
            : {'type': 'location'},
        if (distanceKm != null) 'distanceKm': distanceKm,
        if (itemCount != null) 'itemCount': itemCount,
        if (_selectedProductType != null) 'productType': _selectedProductType,
        if (_geoStart != null) 'geoStart': _geoStart,
        if (_geoEnd != null) 'geoEnd': _geoEnd,
        if (_enteredProductName != null) 'productName': _enteredProductName,
        if (_geminiCanonicalQuery != null)
          'geminiCanonicalQuery': _geminiCanonicalQuery,
        if (_geminiCategory != null) 'geminiCategory': _geminiCategory,
        if (_resolvedDensityKgPerLiter != null)
          'densityKgPerLiter': _resolvedDensityKgPerLiter,
        if (_resolvedDensitySource != null)
          'densitySource': _resolvedDensitySource,
        if (_resolvedDensityConfidence != null)
          'densityConfidence': _resolvedDensityConfidence,
        'densityTrusted': _resolvedDensityTrusted,
      }, SetOptions(merge: true));

      if (currentStatus != 'completed' && taskPoints > 0) {
        trx.set(usersRef, {
          'points': FieldValue.increment(taskPoints),
          'completedTask': FieldValue.increment(1),
          'updatedAt': FieldValue.serverTimestamp(),
          'taskCounts.${_getCategoryKey(taskTitle)}': FieldValue.increment(
            1,
          ), // اضيفي هذا
        }, SetOptions(merge: true));
      }

      final historyRef = firestore
          .collection('users')
          .doc(uid)
          .collection('history')
          .doc();
      trx.set(historyRef, {
        'type': 'task_approved',
        'submissionId': subRef.id,
        'points': taskPoints,
        'taskTitle': taskTitle,
        'carbonSaved': carbonForStore,
        'at': FieldValue.serverTimestamp(),
      });

      trx.set(usersRef, {
        'lastCarbonUpdateAt': FieldValue.serverTimestamp(),
        if (carbonForStore > 0)
          'totalCarbonSaved': FieldValue.increment(carbonForStore),
      }, SetOptions(merge: true));

      trx.set(dailyTaskRef, {
        'status': 'completed',
        'completedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      trx.set(dayMarkRef, {
        'count': FieldValue.increment(1),
        'lastAt': FieldValue.serverTimestamp(),
        'userId': uid,
      }, SetOptions(merge: true));
    });

    try {
      final dailyTaskRef = firestore
          .collection('dailyTasks')
          .doc(uid)
          .collection('tasks')
          .doc(todayId);

      final dailySnap = await dailyTaskRef.get();
      if (dailySnap.exists && dailySnap.data()?['completed'] != true) {
        await dailyTaskRef.set({
          'completed': true,
          'completedAt': FieldValue.serverTimestamp(),
          'status': 'completed',
        }, SetOptions(merge: true));
      }
    } catch (_) {}

    try {
      // ✅ نحدث الستريك بس لو اليوزر أكمل كل المهام المطلوبة لليوم
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        final today = DateTime.now();
        final dayKey =
            '${today.year.toString().padLeft(4, '0')}${today.month.toString().padLeft(2, '0')}${today.day.toString().padLeft(2, '0')}';

        // جلب مستوى اليوزر ومعرفة كم مهمة مطلوبة
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .get();
        final xp = (userDoc.data()?['xp'] ?? 0) as int;

        int requiredTasks = 1;
        if (xp >= 900) requiredTasks = 4;
        else if (xp >= 500) requiredTasks = 3;
        else if (xp >= 100) requiredTasks = 2;

        // عد المهام المكتملة لليوم
        int completedToday = 0;

        final mainSnap = await FirebaseFirestore.instance
            .collection('userTasks')
            .doc('${uid}_$dayKey')
            .get();
        if (mainSnap.exists && mainSnap.data()?['status'] == 'completed') {
          completedToday++;
        }

        for (int i = 2; i <= requiredTasks; i++) {
          final snap = await FirebaseFirestore.instance
              .collection('userTasks')
              .doc('${uid}_${dayKey}_task$i')
              .get();
          if (snap.exists && snap.data()?['status'] == 'completed') {
            completedToday++;
          }
        }

        // تحديث الستريك بس لو اكتملت كل المهام
        if (completedToday >= requiredTasks) {
          await StreakService.updateStreakOnTaskCompletion();
        }
      }
    } catch (_) {}

    try {
      await XpService.addXpForTask(
        taskPoints: (widget.taskData['points'] ?? 0) as int,
      );
    } catch (e) {
      print('⚠️ خطأ في إضافة XP: $e');
    }

    await _grantEcoReward(uid, taskTitle);
    print('🎉 المهمة اكتملت بنجاح');
  }

  Future<void> _openCamera({int? index}) async {
    if (_openingCamera) return;
    if (!mounted) return;

    setState(() {
      _openingCamera = true;
      _capturedPath = null;
      _ready = false;
      _verificationResult = null;
      _isCompleted = false;
      _verificationHint = null;
    });

    try {
      try {
        await _controller?.dispose();
      } catch (_) {}
      _controller = null;

      await Future.delayed(const Duration(milliseconds: 50));

      _cameras ??= await availableCameras();
      if (_cameras == null || _cameras!.isEmpty) {
        throw CameraException('NoCamera', 'لا توجد كاميرا متاحة.');
      }

      if (index != null) {
        _currentCameraIndex = index.clamp(0, _cameras!.length - 1);
      }

      final description = _cameras![_currentCameraIndex];
      final controller = CameraController(
        description,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await controller.initialize();

      _minZoom = await controller.getMinZoomLevel();
      _maxZoom = await controller.getMaxZoomLevel();
      _zoom = _zoom.clamp(_minZoom, _maxZoom);
      _minExposure = await controller.getMinExposureOffset();
      _maxExposure = await controller.getMaxExposureOffset();
      _exposure = _exposure.clamp(_minExposure, _maxExposure);

      await controller.setFlashMode(_flashMode);
      await controller.setZoomLevel(_zoom);
      await controller.setExposureOffset(_exposure);

      if (!mounted) {
        await controller.dispose();
        return;
      }

      _controller = controller;
      setState(() => _ready = true);
    } catch (e) {
      _showInlineError(_friendlyError(e));
    } finally {
      if (mounted) setState(() => _openingCamera = false);
    }
  }

  Future<void> _startTaskFlow() async {
    print('🔍 DEBUG: ${widget.taskData}');
    final taskTitle = widget.taskData['title']?.toString() ?? '';
    final t = taskTitle.toLowerCase(); // ← أضيفي هذا

    // ← غيري الشرط كله ليعتمد على t فقط
    final bool isAnyTransport =
        t.contains('ميترو') ||
        t.contains('metro') ||
        t.contains('باص') ||
        t.contains('bus') ||
        t.contains('حافلة') ||
        t.contains('دراجة') ||
        t.contains('سيكل') ||
        t.contains('cycle') ||
        t.contains('سكوتر') ||
        t.contains('scooter') ||
        t.contains('مشياً') ||
        t.contains('مشيا') ||
        t.contains('مشي');

    if (isAnyTransport) {
      final permission = await Geolocator.checkPermission();
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();

      if (!serviceEnabled ||
          permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (!mounted) return;
        await showDialog(
          context: context,
          builder: (_) => Directionality(
            textDirection: TextDirection.rtl,
            child: AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: Text(
                'الموقع غير متاح',
                style: GoogleFonts.ibmPlexSansArabic(
                  fontWeight: FontWeight.w800,
                  color: appColors.dark,
                ),
              ),
              content: Text(
                'لم نتمكن من الوصول لموقعك، لذلك سيتم التحقق من المهمة عبر الصورة بدلاً من الموقع.',
                style: GoogleFonts.ibmPlexSansArabic(fontSize: 14, height: 1.6),
              ),
              actions: [
                ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: appColors.primary,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    'تأكيد',
                    style: GoogleFonts.ibmPlexSansArabic(
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
        setState(() => _locationDenied = true); // ← أضيفي هذا
        return;
      }

      await _startFlowForTransportTask();
      return;
    }
    _openCamera();
  }

  Future<void> _switchCamera() async {
    if ((_cameras?.length ?? 0) < 2) {
      _showInlineError('لا توجد كاميرا أخرى.');
      return;
    }
    final next = (_currentCameraIndex + 1) % _cameras!.length;
    await _openCamera(index: next);
  }

  Future<void> _cycleFlash() async {
    if (!(_controller?.value.isInitialized ?? false)) return;
    switch (_flashMode) {
      case FlashMode.off:
        _flashMode = FlashMode.auto;
        break;
      case FlashMode.auto:
        _flashMode = FlashMode.always;
        break;
      case FlashMode.always:
        _flashMode = FlashMode.torch;
        break;
      case FlashMode.torch:
        _flashMode = FlashMode.off;
        break;
    }
    try {
      await _controller!.setFlashMode(_flashMode);
      if (mounted) setState(() {});
    } catch (e) {
      _showInlineError(_friendlyError(e));
    }
  }

  Future<void> _setZoom(double value) async {
    if (!(_controller?.value.isInitialized ?? false)) return;
    _zoom = value.clamp(_minZoom, _maxZoom);
    try {
      await _controller!.setZoomLevel(_zoom);
      if (mounted) setState(() {});
    } catch (_) {
      _showInlineError('تعذر ضبط التقريب.');
    }
  }

  Future<void> _setExposure(double value) async {
    if (!(_controller?.value.isInitialized ?? false)) return;
    _exposure = value.clamp(_minExposure, _maxExposure);
    try {
      await _controller!.setExposureOffset(_exposure);
      if (mounted) setState(() {});
    } catch (_) {
      _showInlineError('تعذر ضبط التعريض.');
    }
  }

  Future<void> _setFocusAndExposurePoint(
    TapDownDetails d,
    Size previewSize,
  ) async {
    if (!(_controller?.value.isInitialized ?? false)) return;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final localPos = box.globalToLocal(d.globalPosition);
    final nx = (localPos.dx / previewSize.width).clamp(0.0, 1.0);
    final ny = (localPos.dy / previewSize.height).clamp(0.0, 1.0);
    try {
      await _controller!.setFocusPoint(Offset(nx, ny));
      await _controller!.setExposurePoint(Offset(nx, ny));
      _showInlineError('تم التركيز.');
    } catch (_) {
      _showInlineError('تعذر التركيز هنا.');
    }
  }

  Future<void> _resolveProductWithGemini() async {
    final name = _enteredProductName?.trim() ?? '';
    if (name.isEmpty) {
      _showInlineError('أدخل اسم المنتج أولاً.');
      return;
    }

    try {
      final result = await _geminiResolver.resolveProductName(
        productName: name,
        productType: _selectedProductType,
      );

      if (result == null) {
        _showInlineError('تعذر تحليل المنتج.');
        return;
      }

      if (mounted) {
        setState(() {
          _geminiCanonicalQuery = result.canonicalQuery;
          _geminiCategory = result.category;
          _resolvedDensityKgPerLiter = result.densityKgPerLiter;
          _resolvedDensitySource = result.source;
          _resolvedDensityConfidence = result.confidence;
          _resolvedDensityTrusted = result.trusted;
        });
      }

      debugPrint('🤖 Gemini canonical_query: ${result.canonicalQuery}');
      debugPrint('🤖 Gemini alternatives: ${result.alternatives}');
      debugPrint('🤖 Gemini category: ${result.category}');
      debugPrint('🤖 Gemini densityKgPerLiter: ${result.densityKgPerLiter}');
      debugPrint('🤖 Gemini source: ${result.source}');
      debugPrint('🤖 Gemini confidence: ${result.confidence}');
      debugPrint('🤖 Gemini trusted: ${result.trusted}');
    } catch (e) {
      _showInlineError('فشل تحليل المنتج عبر Gemini');
      debugPrint('❌ Gemini resolver error: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    _geminiResolver = GeminiResolverService();

    if (_autoDistance || _isTransportTask) {
      _captureStartIfNeeded();
    }
  }

  @override
  void dispose() {
    _stopRouteTracking(); // ← مهم: أوقف التتبع عند إغلاق الشاشة
    _controller?.dispose();
    _itemCountCtrl.dispose();
    super.dispose();
  }

  Future<bool> _promptForLocalProductInput() async {
    final TextEditingController measureCtrl = TextEditingController(
      text: _enteredMeasureValue != null ? _enteredMeasureValue.toString() : '',
    );
    final TextEditingController productNameCtrl = TextEditingController(
      text: _enteredProductName ?? '',
    );

    String tempUnit = _selectedMeasureUnit ?? 'kg';
    String? tempProductType = _selectedProductType;
    bool showFieldErrors = false;
    _itemCountCtrl.text = (_itemCount ?? 1).toString();

    final result = await showGeneralDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'local_product_input',
      barrierColor: Colors.black54,
      useRootNavigator: true,
      pageBuilder: (_, __, ___) => const SizedBox.shrink(),
      transitionDuration: const Duration(milliseconds: 180),
      transitionBuilder: (ctx, anim, _, __child) {
        return Transform.scale(
          scale: 0.95 + 0.05 * anim.value,
          child: Opacity(
            opacity: anim.value,
            child: StatefulBuilder(
              builder: (context, setLocalState) {
                OutlineInputBorder normalBorder() => OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                    color: Color(0xFF67CDB3),
                    width: 1.4,
                  ),
                );

                OutlineInputBorder errorBorder() => OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                    color: Colors.redAccent,
                    width: 2,
                  ),
                );
                Widget fieldErrorText(String message) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 6, right: 8),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        message,
                        style: GoogleFonts.ibmPlexSansArabic(
                          fontSize: 12.5,
                          color: Colors.redAccent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  );
                }

                return Center(
                  child: Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 360),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: appColors.mint.withOpacity(0.10),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: appColors.mint.withOpacity(0.35),
                                  ),
                                ),
                                child: Text(
                                  'أدخل البيانات لحساب الأثر الكربوني بشكل أدق ، أو تخطي وسيتم استخدام قيمة تقديرية',
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.ibmPlexSansArabic(
                                    fontSize: 12.5,
                                    height: 1.6,
                                    color: appColors.dark,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),

                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  const Icon(
                                    Icons.inventory_2_outlined,
                                    color: appColors.primary,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'أدخل بيانات المنتج',
                                    style: GoogleFonts.ibmPlexSansArabic(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                      color: appColors.dark,
                                    ),
                                  ),
                                ],
                              ),

                              const SizedBox(height: 12),

                              DropdownButtonFormField<String>(
                                value: tempProductType,
                                decoration: InputDecoration(
                                  labelText: 'نوع المنتج',
                                  border: normalBorder(),
                                  enabledBorder:
                                      showFieldErrors && tempProductType == null
                                      ? errorBorder()
                                      : normalBorder(),
                                  focusedBorder:
                                      showFieldErrors && tempProductType == null
                                      ? errorBorder()
                                      : normalBorder(),
                                  contentPadding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                    horizontal: 12,
                                  ),
                                ),
                                hint: Text(
                                  'اختار نوع المنتج',
                                  style: GoogleFonts.ibmPlexSansArabic(
                                    fontSize: 16,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                                items: const [
                                  DropdownMenuItem(
                                    value: 'solid',
                                    child: Text('صلب'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'liquid',
                                    child: Text('سائل'),
                                  ),
                                ],
                                onChanged: (value) {
                                  if (value == null) return;
                                  setLocalState(() {
                                    tempProductType = value;
                                    tempUnit = value == 'solid' ? 'kg' : 'L';
                                  });
                                },
                              ),
                              if (showFieldErrors && tempProductType == null)
                                fieldErrorText('يرجى اختيار نوع المنتج'),
                              const SizedBox(height: 12),
                              TextField(
                                controller: productNameCtrl,
                                textAlign: TextAlign.center,
                                decoration: InputDecoration(
                                  labelText: 'ما هو المنتج؟',
                                  hintText: 'مثال: ماء، عصير، لبن',
                                  border: normalBorder(),
                                  enabledBorder:
                                      showFieldErrors &&
                                          productNameCtrl.text.trim().isEmpty
                                      ? errorBorder()
                                      : normalBorder(),
                                  focusedBorder:
                                      showFieldErrors &&
                                          productNameCtrl.text.trim().isEmpty
                                      ? errorBorder()
                                      : normalBorder(),
                                  contentPadding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                    horizontal: 12,
                                  ),
                                ),
                                onChanged: (_) {
                                  if (showFieldErrors) setLocalState(() {});
                                },
                              ),
                              if (showFieldErrors &&
                                  productNameCtrl.text.trim().isEmpty)
                                fieldErrorText('يرجى إدخال اسم المنتج'),
                              const SizedBox(height: 12),
                              // عدد المنتجات
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: const Color(0xFF67CDB3),
                                    width: 1.4,
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      tempProductType == null
                                          ? 'العدد'
                                          : tempProductType == 'solid'
                                          ? 'عدد القطع'
                                          : 'عدد العبوات',
                                      style: GoogleFonts.ibmPlexSansArabic(
                                        fontSize: 14,
                                        color: Colors.black54,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    Row(
                                      children: [
                                        _counterButton(
                                          icon: Icons.remove_rounded,
                                          onTap: () {
                                            final cur =
                                                int.tryParse(
                                                  _itemCountCtrl.text.trim(),
                                                ) ??
                                                1;
                                            final next = cur > 1 ? cur - 1 : 1;
                                            setLocalState(() {
                                              _itemCountCtrl.text = next
                                                  .toString();
                                            });
                                          },
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Text(
                                            _itemCountCtrl.text.isEmpty
                                                ? '1'
                                                : _itemCountCtrl.text,
                                            textAlign: TextAlign.center,
                                            style:
                                                GoogleFonts.ibmPlexSansArabic(
                                                  fontSize: 28,
                                                  fontWeight: FontWeight.w600,
                                                  color: appColors.dark,
                                                ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        _counterButton(
                                          icon: Icons.add_rounded,
                                          onTap: () {
                                            final cur =
                                                int.tryParse(
                                                  _itemCountCtrl.text.trim(),
                                                ) ??
                                                1;
                                            setLocalState(() {
                                              _itemCountCtrl.text = (cur + 1)
                                                  .toString();
                                            });
                                          },
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 12),

                              // الوزن/الحجم
                              TextField(
                                controller: measureCtrl,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                textAlign: TextAlign.center,
                                decoration: InputDecoration(
                                  labelText: tempProductType == null
                                      ? 'الكمية'
                                      : tempProductType == 'solid'
                                      ? 'وزن القطعة'
                                      : 'حجم العبوة',
                                  hintText: 'مثال: 1 أو 500',
                                  border: normalBorder(),
                                  enabledBorder:
                                      showFieldErrors &&
                                          ((double.tryParse(
                                                    measureCtrl.text.trim(),
                                                  ) ??
                                                  0) <=
                                              0)
                                      ? errorBorder()
                                      : normalBorder(),
                                  focusedBorder:
                                      showFieldErrors &&
                                          ((double.tryParse(
                                                    measureCtrl.text.trim(),
                                                  ) ??
                                                  0) <=
                                              0)
                                      ? errorBorder()
                                      : normalBorder(),
                                  contentPadding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                    horizontal: 12,
                                  ),
                                ),
                                onChanged: (_) {
                                  if (showFieldErrors) setLocalState(() {});
                                },
                              ),
                              if (showFieldErrors &&
                                  ((double.tryParse(measureCtrl.text.trim()) ??
                                          0) <=
                                      0))
                                fieldErrorText('يرجى إدخال الكمية'),
                              const SizedBox(height: 12),

                              DropdownButtonFormField<String>(
                                value: tempProductType == null
                                    ? null
                                    : tempUnit,
                                decoration: InputDecoration(
                                  labelText: 'الوحدة',
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                    horizontal: 12,
                                  ),
                                ),
                                hint: Text(
                                  'اختر الوحدة',
                                  style: GoogleFonts.ibmPlexSansArabic(
                                    fontSize: 16,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                                items: tempProductType == null
                                    ? const []
                                    : tempProductType == 'solid'
                                    ? const [
                                        DropdownMenuItem(
                                          value: 'kg',
                                          child: Text('كجم'),
                                        ),
                                        DropdownMenuItem(
                                          value: 'g',
                                          child: Text('جرام'),
                                        ),
                                      ]
                                    : const [
                                        DropdownMenuItem(
                                          value: 'L',
                                          child: Text('لتر'),
                                        ),
                                        DropdownMenuItem(
                                          value: 'mL',
                                          child: Text('مل'),
                                        ),
                                      ],
                                onChanged: tempProductType == null
                                    ? null
                                    : (value) {
                                        if (value == null) return;
                                        setLocalState(() => tempUnit = value);
                                      },
                              ),

                              const SizedBox(height: 10),
                              Text(
                                tempProductType == null
                                    ? 'يرجى اختيار نوع المنتج أولاً'
                                    : tempProductType == 'solid'
                                    ? 'يرجى إدخال الوزن كما هو مكتوب على العبوة'
                                    : 'يرجى إدخال الحجم كما هو مكتوب على العبوة',
                                style: GoogleFonts.ibmPlexSansArabic(
                                  fontSize: 12.5,
                                  color: Colors.black54,
                                ),
                              ),

                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed: () {
                                        Navigator.of(ctx).pop({'skip': true});
                                      },
                                      style: OutlinedButton.styleFrom(
                                        side: const BorderSide(
                                          color: appColors.primary,
                                          width: 2,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 10,
                                        ),
                                      ),
                                      child: Text(
                                        'تخطي',
                                        style: GoogleFonts.ibmPlexSansArabic(
                                          color: appColors.primary,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: ElevatedButton(
                                      onPressed: () {
                                        final count = int.tryParse(
                                          _itemCountCtrl.text.trim(),
                                        );
                                        final measure = double.tryParse(
                                          measureCtrl.text.trim(),
                                        );
                                        final productName = productNameCtrl.text
                                            .trim();

                                        final hasError =
                                            tempProductType == null ||
                                            productName.isEmpty ||
                                            count == null ||
                                            count <= 0 ||
                                            measure == null ||
                                            measure <= 0;

                                        if (hasError) {
                                          setLocalState(() {
                                            showFieldErrors = true;
                                          });
                                          return;
                                        }

                                        Navigator.of(ctx).pop({
                                          'skip': false,
                                          'count': count,
                                          'measureValue': measure,
                                          'measureUnit': tempUnit,
                                          'productType': tempProductType,
                                          'productName': productName,
                                        });
                                      },
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: appColors.primary,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 12,
                                        ),
                                      ),
                                      child: Text(
                                        'حفظ',
                                        style: GoogleFonts.ibmPlexSansArabic(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );

    if (!mounted || result == null) return false;

    if (result['skip'] == true) {
      setState(() {
        _usedEstimatedLocalFallback = true;
        _itemCount = int.tryParse(_itemCountCtrl.text.trim()) ?? 1;

        _enteredMeasureValue = null;
        _selectedMeasureUnit = null;
        _selectedProductType = null;
        _enteredProductName = null;

        _geminiCanonicalQuery = null;
        _geminiCategory = null;
        _resolvedDensityKgPerLiter = null;
        _resolvedDensitySource = 'estimated_default_mass';
        _resolvedDensityConfidence = null;
        _resolvedDensityTrusted = false;
      });

      return true;
    }

    setState(() {
      _usedEstimatedLocalFallback = false;
      _itemCount = result['count'] as int;
      _enteredMeasureValue = (result['measureValue'] as num).toDouble();
      _selectedMeasureUnit = result['measureUnit']?.toString();
      _selectedProductType = result['productType']?.toString();
      _enteredProductName = result['productName']?.toString();
    });

    return true;
  }

  double? _computeLocalProductMassKg({
    required double measureValue,
    required String measureUnit,
    required int itemCount,
    required String productType,
    double? densityKgPerLiter,
  }) {
    final unit = measureUnit.trim();

    double singleMassKg;

    if (productType == 'solid') {
      switch (unit) {
        case 'kg':
          singleMassKg = measureValue;
          break;
        case 'g':
          singleMassKg = measureValue / 1000.0;
          break;
        default:
          return null;
      }
    } else if (productType == 'liquid') {
      if (densityKgPerLiter == null || densityKgPerLiter <= 0) return null;

      double liters;
      switch (unit) {
        case 'L':
          liters = measureValue;
          break;
        case 'mL':
          liters = measureValue / 1000.0;
          break;
        default:
          return null;
      }

      singleMassKg = liters * densityKgPerLiter;
    } else {
      return null;
    }

    return double.parse((singleMassKg * itemCount).toStringAsFixed(6));
  }

  Widget _buildVerificationResult() {
    if (_verificationResult == null && !_isVerifying) {
      return const SizedBox.shrink();
    }
    if (_verificationResult!.verified == true) return const SizedBox.shrink();
    if (_verificationResult?.verificationSource == 'origin_check')
      return const SizedBox.shrink();

    if (_isVerifying) {
      return Container(
        padding: const EdgeInsets.all(12),
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.blue.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.blue.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Text(
              'جاري التحقق من الصورة...',
              style: GoogleFonts.ibmPlexSansArabic(
                fontWeight: FontWeight.w600,
                color: Colors.blue,
              ),
            ),
          ],
        ),
      );
    }

    if (_verificationResult!.verified == true) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning, color: Colors.orange, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'الصورة غير مطابقة',
                  style: GoogleFonts.ibmPlexSansArabic(
                    fontWeight: FontWeight.w600,
                    color: Colors.orange,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'يرجى إعادة التقاط صورة أوضح للمهمة',
                  style: GoogleFonts.ibmPlexSansArabic(
                    fontSize: 13,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final task = widget.taskData;
    final title = task['title'] ?? 'مهمة غير معروفة';
    final desc = task['description'] ?? '';
    final pts = (task['points'] ?? 0) as int;
    final requiresPhotoExact = true;
    final isTransport = (_autoDistance || _isTransportTask);
    final String validationLabel = isTransport
        ? 'التحقق عبر الموقع'
        : (task['validationStrategy']?.toString() ?? 'التحقق عبر معالجة الصور');

    return Directionality(
      textDirection: TextDirection.rtl,
      child: DraggableScrollableSheet(
        initialChildSize: 0.92,
        minChildSize: 0.6,
        maxChildSize: 0.98,
        expand: false,
        builder: (context, scrollController) {
          return Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: SingleChildScrollView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 44,
                      height: 5,
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Colors.black12,
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  Text(
                    'إتمام المهمة',
                    style: GoogleFonts.ibmPlexSansArabic(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: appColors.dark,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    title,
                    style: GoogleFonts.ibmPlexSansArabic(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: appColors.primary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(
                        Icons.star_border,
                        color: appColors.primary,
                        size: 20,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '$pts نقطة',
                        style: GoogleFonts.ibmPlexSansArabic(
                          fontWeight: FontWeight.w700,
                          color: appColors.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    desc,
                    style: GoogleFonts.ibmPlexSansArabic(
                      fontSize: 14,
                      height: 1.7,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (!_ready) _buildPhotoInstructions(),
                  if (!_ready) const SizedBox(height: 16),

                  // ─── زر مهام غير مواصلات ───
                  if (requiresPhotoExact && !isTransport && !_ready)
                    _gradientButton(
                      label: 'ابدأ التصوير',
                      icon: Icons.camera_alt,
                      onTap: (_openingCamera || _isVerifying)
                          ? null
                          : () => _startTaskFlow(),
                      loading: _openingCamera || _isVerifying,
                    ),

                  // ─── زر مهام المواصلات (يتغير حسب المرحلة) ───
                  if (requiresPhotoExact && isTransport && !_ready) ...[
                    _gradientButton(
                      label: _locationDenied
                          ? 'ابدأ التصوير'
                          : (_transportVerifyPhase == 'end'
                                ? _getArrivalLabel()
                                : _getTransportButtonLabel()),
                      icon: _locationDenied
                          ? Icons.camera_alt
                          : (_transportVerifyPhase == 'end'
                                ? Icons.location_on
                                : _getTransportIcon()),
                      onTap: (_openingCamera || _isVerifying)
                          ? null
                          : () => _locationDenied
                                ? _openCamera()
                                : (_transportVerifyPhase == 'end'
                                      ? _verifyTransportByLocation()
                                      : _startTaskFlow()),
                      loading: _openingCamera || _isVerifying,
                    ),
                    // مؤشر التتبع الجاري
                    if (_isTracking) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: appColors.primary.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: appColors.primary.withOpacity(0.3),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: appColors.primary,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              'جاري تتبع مسارك... (${_trackPoints.length} نقطة)',
                              style: GoogleFonts.ibmPlexSansArabic(
                                fontSize: 13,
                                color: appColors.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    if (_manualDistanceKm != null &&
                        _transportVerifyPhase == 'start') ...[
                      const SizedBox(height: 10),
                      _hintCard(
                        'المسار المحدد: ${_manualDistanceKm!.toStringAsFixed(2)} كم',
                      ),
                    ],
                  ],

                  const SizedBox(height: 16),

                  // ─── الكاميرا ───
                  if (_ready)
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      child: SizedBox(
                        height: 420,
                        child: LayoutBuilder(
                          builder: (context, cons) {
                            final w = cons.maxWidth;
                            final h = cons.maxHeight;
                            return Stack(
                              alignment: Alignment.center,
                              children: [
                                Positioned.fill(
                                  child: _capturedPath != null
                                      ? ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                          child: Image.file(
                                            File(_capturedPath!),
                                            fit: BoxFit.cover,
                                          ),
                                        )
                                      : ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                          child: FittedBox(
                                            fit: BoxFit.cover,
                                            child: SizedBox(
                                              width:
                                                  _controller!
                                                      .value
                                                      .previewSize
                                                      ?.height ??
                                                  w,
                                              height:
                                                  _controller!
                                                      .value
                                                      .previewSize
                                                      ?.width ??
                                                  h,
                                              child: GestureDetector(
                                                behavior:
                                                    HitTestBehavior.opaque,
                                                onTapDown: (d) =>
                                                    _setFocusAndExposurePoint(
                                                      d,
                                                      Size(w, h),
                                                    ),
                                                child: CameraPreview(
                                                  _controller!,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                ),
                                Positioned(
                                  top: 10,
                                  right: 10,
                                  left: 10,
                                  child: Row(
                                    children: [
                                      _roundedGlass(
                                        child: IconButton(
                                          tooltip: 'تبديل الكاميرا',
                                          icon: const Icon(
                                            Icons.cameraswitch_rounded,
                                            color: Colors.white,
                                          ),
                                          onPressed: _switchCamera,
                                        ),
                                      ),
                                      const Spacer(),
                                      _roundedGlass(
                                        child: IconButton(
                                          tooltip: 'وضع الفلاش',
                                          onPressed: _cycleFlash,
                                          icon: Icon(
                                            _flashMode == FlashMode.off
                                                ? Icons.flash_off_rounded
                                                : _flashMode == FlashMode.auto
                                                ? Icons.flash_auto_rounded
                                                : _flashMode == FlashMode.always
                                                ? Icons.flash_on_rounded
                                                : Icons.highlight_rounded,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Positioned(
                                  bottom: 10,
                                  left: 12,
                                  right: 12,
                                  child: Column(
                                    children: [
                                      _sliderCard(
                                        label: 'التقريب',
                                        value: _zoom,
                                        min: _minZoom,
                                        max: _maxZoom,
                                        onChanged: (v) => _setZoom(v),
                                      ),
                                      const SizedBox(height: 8),
                                      _sliderCard(
                                        label: 'التعريض',
                                        value: _exposure,
                                        min: _minExposure,
                                        max: _maxExposure,
                                        onChanged: (v) => _setExposure(v),
                                      ),
                                    ],
                                  ),
                                ),
                                if (_requiresItemDialog &&
                                    (_itemCount != null && _itemCount! > 0))
                                  Positioned(
                                    top: 54,
                                    right: 12,
                                    child: _roundedGlass(
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 8,
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              'عدد العناصر: $_itemCount',
                                              style:
                                                  GoogleFonts.ibmPlexSansArabic(
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                            ),
                                            const SizedBox(width: 6),
                                            InkWell(
                                              onTap:
                                                  _promptForItemCountIfNeeded,
                                              borderRadius:
                                                  BorderRadius.circular(999),
                                              child: const Icon(
                                                Icons.edit,
                                                size: 18,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                if (_inlineError != null)
                                  Positioned(
                                    top: 12,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 10,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withOpacity(0.72),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        _inlineError!,
                                        style: GoogleFonts.ibmPlexSansArabic(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ),
                                IgnorePointer(
                                  child: AnimatedOpacity(
                                    opacity: _flashOpacity,
                                    duration: const Duration(milliseconds: 120),
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.9),
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ),

                  const SizedBox(height: 12),
                  const SizedBox(height: 10),

                  if (_ready) ...[
                    if (_capturedPath == null)
                      _gradientButton(
                        label: _isCapturing
                            ? 'جاري الالتقاط...'
                            : 'التقاط صورة',
                        icon: Icons.camera,
                        onTap: _isCapturing
                            ? null
                            : () async {
                                if (!mounted) return;
                                setState(() {
                                  _isCapturing = true;
                                  _flashOpacity = 0.9;
                                });
                                await Future.delayed(
                                  const Duration(milliseconds: 90),
                                );
                                if (mounted)
                                  setState(() => _flashOpacity = 0.0);

                                final shot = await _safeTakePicture();
                                if (!mounted) return;
                                if (shot != null) {
                                  setState(() => _capturedPath = shot.path);
                                  await _verifyTaskImage(shot.path);
                                }
                                if (mounted)
                                  setState(() => _isCapturing = false);
                              },
                      )
                    else if (_isUploading)
                      _gradientButton(
                        label: 'جاري إكمال المهمة...',
                        icon: Icons.cloud_upload,
                        enabled: false,
                        loading: true,
                        onTap: null,
                      )
                    else if (_isVerifying)
                      _gradientButton(
                        label: 'جاري التحقق...',
                        icon: Icons.search,
                        enabled: false,
                        loading: true,
                        onTap: null,
                      )
                    else if (!_isCompleted)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (_verificationResult != null)
                            _buildVerificationResult(),
                          if (_verificationHint != null) ...[
                            const SizedBox(height: 10),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.blueGrey.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.blueGrey.withOpacity(0.25),
                                ),
                              ),
                              child: Text(
                                _verificationHint!,
                                style: GoogleFonts.ibmPlexSansArabic(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                  color: appColors.dark,
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 16),
                          OutlinedButton.icon(
                            icon: Icon(Icons.refresh, color: appColors.primary),
                            label: Text(
                              'إعادة التقاط',
                              style: GoogleFonts.ibmPlexSansArabic(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                                color: appColors.primary,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(
                                color: appColors.primary,
                                width: 2,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            onPressed: () async {
                              try {
                                if (_capturedPath != null) {
                                  final f = File(_capturedPath!);
                                  if (await f.exists()) await f.delete();
                                }
                              } catch (_) {}
                              if (mounted) {
                                setState(() {
                                  _capturedPath = null;
                                  _verificationResult = null;
                                  _isUploading = false;
                                  _isVerifying = false;
                                  _isCompleted = false;
                                  _verificationHint = null;
                                });
                              }
                            },
                          ),
                          if (_verificationResult != null &&
                              _isAiApproved(_verificationResult) &&
                              !_isUploading)
                            Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.green.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.green),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.check_circle,
                                      color: Colors.green,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'الصورة معتمدة',
                                            style:
                                                GoogleFonts.ibmPlexSansArabic(
                                                  fontWeight: FontWeight.w600,
                                                  color: Colors.green,
                                                ),
                                          ),
                                          Text(
                                            'سيتم إكمال المهمة تلقائياً...',
                                            style:
                                                GoogleFonts.ibmPlexSansArabic(
                                                  fontSize: 12,
                                                  color: Colors.black87,
                                                ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.green,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _hintCard(String text) => Material(
    elevation: 2,
    borderRadius: BorderRadius.circular(12),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(text, textAlign: TextAlign.center),
    ),
  );

  Future<void> showTaskFailedDialogAndRedirect(BuildContext context) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          insetPadding: const EdgeInsets.symmetric(horizontal: 24),
          child: SizedBox(
            width: 340,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset(
                    'assets/img/nameerSad.png',
                    height: 120,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'لم يتم التحقق',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.ibmPlexSansArabic(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: appColors.dark,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'يرجى إعادة التقاط الصورة مع:\n• إضاءة مناسبة\n• وضوح العنصر\n• زاوية تصوير جيدة',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.ibmPlexSansArabic(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: appColors.dark,
                      height: 1.6,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Center(
                    child: SizedBox(
                      width: 140,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: appColors.primary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 10,
                          ),
                        ),
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        child: Text(
                          'حسناً',
                          style: GoogleFonts.ibmPlexSansArabic(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _roundedGlass({required Widget child}) => Container(
    decoration: BoxDecoration(
      color: Colors.black.withOpacity(0.25),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.white24, width: 1),
    ),
    child: child,
  );

  Widget _sliderCard({
    required String label,
    required double value,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.25),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white24, width: 1),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 56,
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: GoogleFonts.ibmPlexSansArabic(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Slider(
              value: value.clamp(min, max).toDouble(),
              min: min,
              max: max == min ? min + 0.001 : max,
              onChanged: onChanged,
              activeColor: Colors.white,
              inactiveColor: Colors.white54,
            ),
          ),
          SizedBox(
            width: 58,
            child: Text(
              label == 'التقريب'
                  ? '${value.toStringAsFixed(1)}x'
                  : value.toStringAsFixed(1),
              textAlign: TextAlign.center,
              style: GoogleFonts.ibmPlexSansArabic(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _gradientButton({
    required String label,
    IconData? icon,
    required VoidCallback? onTap,
    bool loading = false,
    bool enabled = true,
  }) {
    final bool isDisabled = !enabled || loading || onTap == null;
    final child = loading
        ? const SizedBox(
            height: 22,
            width: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white,
            ),
          )
        : Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, color: Colors.white),
                const SizedBox(width: 8),
              ],
              Text(
                label,
                style: GoogleFonts.ibmPlexSansArabic(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  color: Colors.white,
                ),
              ),
            ],
          );

    return SizedBox(
      width: double.infinity,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: isDisabled
              ? LinearGradient(
                  colors: [Colors.grey.shade400, Colors.grey.shade400],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                )
              : const LinearGradient(
                  colors: [appColors.primary, appColors.mint],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: InkWell(
          onTap: isDisabled ? null : onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Center(child: child),
          ),
        ),
      ),
    );
  }

  Widget _buildPhotoInstructions() {
    final isLocalProductTask = _isLocalProductTask;
    final t = (widget.taskData['title'] ?? '').toString().toLowerCase();

    // ← أضيفي هذا الشرط في أول الدالة قبل أي شيء
    final bool isTransportTask =
        t.contains('مترو') ||
        t.contains('ميترو') ||
        t.contains('metro') ||
        t.contains('باص') ||
        t.contains('bus') ||
        t.contains('حافلة') ||
        t.contains('دراجة') ||
        t.contains('سكوتر') ||
        t.contains('مشي');

    if (isTransportTask && !_locationDenied) {
      return _buildTransportGpsInstructions(); // ← return مبكر، ما يكمل
    }

    final bullets = [
      'تأكد من أن الإضاءة جيدة والعنصر واضح.',
      if (isLocalProductTask)
        'التقط صورة واضحة لبلد الصنع أو عبارة "صنع في السعودية" على المنتج.',
      if (!isLocalProductTask) 'التقط صورة تُظهر قيامك بالمهمة.',
      'تأكد أن النص أو المنتج ظاهر بشكل مستقيم وغير مقلوب.',
      'لا تستخدم صورًا من الإنترنت.',
      'التقط من زاوية مناسبة وبدون فلاش إن أمكن.',
      'إذا واجهت مشكلة في المهمة، يمكنك الانتقال إلى صفحة الدعم وتقديم بلاغ عن المهمة ليتم مراجعته.',
    ];

    final isRecyclingTask = () {
      final t = (widget.taskData['title'] ?? '').toString().toLowerCase();
      return t.contains('تدوير') ||
          t.contains('حاوية') ||
          t.contains('بلاستيك') ||
          t.contains('ورق') ||
          t.contains('recycl') ||
          t.contains('rvm') ||
          t.contains('ملابس') ||
          t.contains('طعام');
    }();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: appColors.mint.withOpacity(0.15),
        border: Border.all(color: appColors.mint, width: 1.5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.camera_alt_outlined,
                color: appColors.primary,
                size: 22,
              ),
              const SizedBox(width: 8),
              Text(
                'تعليمات التصوير',
                style: GoogleFonts.ibmPlexSansArabic(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: appColors.dark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...bullets.map(
            (txt) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('•  ', style: TextStyle(height: 1.7)),
                  Expanded(
                    child: Text(
                      txt,
                      style: GoogleFonts.ibmPlexSansArabic(
                        fontSize: 13.8,
                        height: 1.8,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── مثال الصورة لمهام الحاويات ──
          Builder(
            builder: (context) {
              final t = (widget.taskData['title'] ?? '')
                  .toString()
                  .toLowerCase();

              String? exampleImage;
              String? exampleLabel;
              // بعد — أضيفي شرط _locationDenied
              // if ((t.contains('مترو') || t.contains('ميترو') || t.contains('metro') ||
              //     t.contains('باص') || t.contains('bus') || t.contains('حافلة') ||
              //     t.contains('دراجة') || t.contains('سكوتر') || t.contains('مشي')) &&
              //     !_locationDenied) {
              //   // ✅ تعليمات GPS
              //   return _buildTransportGpsInstructions();
              // }
              if (t.contains('تدوير') ||
                  t.contains('حاوية') ||
                  t.contains('بلاستيك') ||
                  t.contains('ورق') ||
                  t.contains('rvm') ||
                  t.contains('ملابس') ||
                  t.contains('طعام')) {
                exampleImage = 'assets/img/recycling_example.webp';
                exampleLabel = 'مثال على الصورة المطلوبة:';
              } else if (t.contains('مترو') ||
                  t.contains('ميترو') ||
                  t.contains('metro')) {
                exampleImage = 'assets/img/metro_example.jpg';
                exampleLabel = 'مثال على الصورة المطلوبة:';
              } else if (t.contains('باص') ||
                  t.contains('bus') ||
                  t.contains('حافلة')) {
                exampleImage = 'assets/img/bus_example.jpeg';
                exampleLabel = 'مثال على الصورة المطلوبة:';
              } else if (t.contains('دراجة') || t.contains('سيكل')) {
                exampleImage = 'assets/img/bicycle_example.jpg';
                exampleLabel = 'مثال على الصورة المطلوبة:';
              } else if (t.contains('محلي') || t.contains('منتج')) {
                exampleImage = 'assets/img/local_example.png';
                exampleLabel = 'مثال على الصورة المطلوبة:';
              } else if (t.contains('سكوتر') || t.contains('scooter')) {
                exampleImage = 'assets/img/scooter_example.jpg';
                exampleLabel = 'مثال على الصورة المطلوبة:';
              }

              if (exampleImage == null) return const SizedBox.shrink();

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 14),
                  Text(
                    exampleLabel!,
                    style: GoogleFonts.ibmPlexSansArabic(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: appColors.dark,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.asset(
                      exampleImage,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTransportGpsInstructions() {
    final t = (widget.taskData['title'] ?? '').toString().toLowerCase();

    String transportName = 'المواصلات';
    if (t.contains('مترو') || t.contains('ميترو'))
      transportName = 'المترو';
    else if (t.contains('باص') || t.contains('حافلة'))
      transportName = 'الباص';
    else if (t.contains('دراجة'))
      transportName = 'الدراجة';
    else if (t.contains('سكوتر'))
      transportName = 'السكوتر';
    else if (t.contains('مشي'))
      transportName = 'المشي';

    final steps = [
      (
        '1',
        Icons.map_outlined,
        'اختر المحطات',
        'اضغط الزر واختر محطة البداية ومحطة الوصول على الخريطة.',
      ),
      (
        '2',
        Icons.location_on_outlined,
        'كن عند محطة البداية',
        'توجه إلى محطة البداية التي اخترتها — سيتحقق التطبيق من وجودك فيها (في نطاق 150 متر).',
      ),
      (
        '3',
        Icons.directions,
        'ابدأ رحلتك',
        'بعد التأكيد، سيبدأ التطبيق بتتبع مسارك تلقائياً أثناء استخدامك لـ$transportName.',
      ),
      (
        '4',
        Icons.check_circle_outline,
        'سجّل وصولك',
        'عند وصولك لمحطة الوصول، اضغط زر "وصلت" ليتحقق التطبيق من موقعك ويكمل المهمة.',
      ),
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: appColors.mint.withOpacity(0.15),
        border: Border.all(color: appColors.mint, width: 1.5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.route_outlined,
                color: appColors.primary,
                size: 22,
              ),
              const SizedBox(width: 8),
              Text(
                'كيف تُكمل مهمة $transportName',
                style: GoogleFonts.ibmPlexSansArabic(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: appColors.dark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...steps.map(
            (s) => Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: appColors.primary,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        s.$1,
                        style: GoogleFonts.ibmPlexSansArabic(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s.$3,
                          style: GoogleFonts.ibmPlexSansArabic(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: appColors.dark,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          s.$4,
                          style: GoogleFonts.ibmPlexSansArabic(
                            fontSize: 13,
                            height: 1.6,
                            color: Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.amber.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.amber.shade300),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: Colors.amber, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'تأكد من تفعيل خدمة الموقع على جهازك طوال فترة الرحلة.',
                    style: GoogleFonts.ibmPlexSansArabic(
                      fontSize: 13,
                      color: Colors.black87,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _counterButton({required IconData icon, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: appColors.primary.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: appColors.primary.withOpacity(0.45),
            width: 1.3,
          ),
        ),
        child: Icon(icon, size: 22, color: appColors.primary),
      ),
    );
  }

  Future<void> _promptForItemCountIfNeeded() async {
    if (!_requiresItemDialog) return;

    final minItems = _asInt(widget.taskData['minItems']) ?? 1;
    final maxItems = _asInt(widget.taskData['maxItems']) ?? 999;
    int clamp(int v) => v.clamp(minItems, maxItems);

    final def = (_itemCount != null && _itemCount! > 0)
        ? _itemCount!
        : (_asInt(widget.taskData['defaultItems']) ?? minItems);

    _itemCountCtrl.text = def.toString();

    final result = await showGeneralDialog<int>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'items',
      barrierColor: Colors.black54,
      useRootNavigator: true,
      pageBuilder: (_, __, ___) => const SizedBox.shrink(),
      transitionDuration: const Duration(milliseconds: 180),
      transitionBuilder: (ctx, anim, _, __child) {
        return Transform.scale(
          scale: 0.95 + 0.05 * anim.value,
          child: Opacity(
            opacity: anim.value,
            child: Center(
              child: Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.format_list_numbered,
                              color: appColors.primary,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'عدد العناصر المنجزة',
                              style: GoogleFonts.ibmPlexSansArabic(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: appColors.dark,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            _counterButton(
                              icon: Icons.remove_rounded,
                              onTap: () {
                                final cur = _asInt(_itemCountCtrl.text) ?? def;
                                _itemCountCtrl.text = clamp(cur - 1).toString();
                                setState(() {});
                              },
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextField(
                                controller: _itemCountCtrl,
                                keyboardType:
                                    const TextInputType.numberWithOptions(),
                                textAlign: TextAlign.center,
                                decoration: InputDecoration(
                                  contentPadding: const EdgeInsets.symmetric(
                                    vertical: 10,
                                    horizontal: 12,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  hintText: '$def',
                                ),
                                onChanged: (_) => setState(() {}),
                              ),
                            ),
                            const SizedBox(width: 12),
                            _counterButton(
                              icon: Icons.add_rounded,
                              onTap: () {
                                final cur = _asInt(_itemCountCtrl.text) ?? def;
                                _itemCountCtrl.text = clamp(cur + 1).toString();
                                setState(() {});
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'الحد الأدنى: $minItems  •  الأقصى: $maxItems',
                            style: GoogleFonts.ibmPlexSansArabic(
                              fontSize: 12.5,
                              color: Colors.black54,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => Navigator.of(ctx).pop(null),
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(
                                    color: appColors.primary,
                                    width: 2,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 10,
                                  ),
                                ),
                                child: Text(
                                  'إلغاء',
                                  style: GoogleFonts.ibmPlexSansArabic(
                                    color: appColors.primary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: () {
                                  final raw = _asInt(_itemCountCtrl.text);
                                  if (raw == null || raw <= 0) {
                                    _showInlineError('يرجى إدخال عدد صحيح.');
                                    return;
                                  }
                                  final safe = clamp(raw);
                                  _itemCountCtrl.text = safe.toString();
                                  Navigator.of(ctx).pop(safe);
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: appColors.primary,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                ),
                                child: Text(
                                  'حفظ',
                                  style: GoogleFonts.ibmPlexSansArabic(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    if (!mounted) return;
    if (result != null && result > 0) {
      setState(() => _itemCount = clamp(result));
    }
  }
}

// ─────────────────────────────────────────────
//  🎁 منح مكافأة EcoLand عند إنجاز المهمة
// ─────────────────────────────────────────────

Future<void> _grantEcoReward(String userId, String taskTitle) async {
  try {
    String? rewardId;
    String? rewardName;
    String? glbPath;
    String? category;

    final title = taskTitle.toLowerCase();

    if (title.contains('مترو') || title.contains('metro')) {
      rewardId = 'metro';
      rewardName = 'مترو';
      glbPath = 'assets/models/metro.glb';
      category = 'transport';
    } else if (title.contains('تدوير') ||
        title.contains('recycling') ||
        title.contains('recycle')) {
      rewardId = 'recycle';
      rewardName = 'إعادة تدوير';
      glbPath = 'assets/models/recycle.glb';
      category = 'recycling';
    } else if (title.contains('مقال') ||
        title.contains('اختبار') ||
        title.contains('article')) {
      rewardId = 'article';
      rewardName = 'مقال بيئي';
      glbPath = 'assets/models/article.glb';
      category = 'article';
    }

    if (rewardId == null) return;

    final today = DateTime.now();
    final todayKey =
        '${today.year}${today.month.toString().padLeft(2, '0')}${today.day.toString().padLeft(2, '0')}';

    final ecoRewardsRef = FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('ecolandRewards');

    final existingQuery = await ecoRewardsRef
        .where('rewardId', isEqualTo: rewardId)
        .where('earnedDate', isEqualTo: todayKey)
        .limit(1)
        .get();

    if (existingQuery.docs.isNotEmpty) return;

    await ecoRewardsRef.add({
      'rewardId': rewardId,
      'name': rewardName,
      'glbPath': glbPath,
      'category': category,
      'earnedAt': FieldValue.serverTimestamp(),
      'earnedDate': todayKey,
      'taskTitle': taskTitle,
    });

    print('🎁 تم منح مكافأة: $rewardName للمستخدم $userId');
  } catch (e) {
    print('❌ خطأ في منح المكافأة: $e');
  }
}
