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

import 'services/map_pick_route.dart';

const String kMapsApiKey = 'YOUR_GOOGLE_PLACES_API_KEY';

class AppColors {
  static const primary = Color(0xFF4BAA98);
  static const dark = Color(0xFF3C3C3B);
  static const accent = Color(0xFFF4A340);
  static const sea = Color(0xFF1F7A8C);
  static const primary60 = Color(0x994BAA98);
  static const primary33 = Color(0x544BAA98);
  static const light = Color(0xFF79D0BE);
  static const background = Color(0xFFF3FAF7);
  static const mint = Color(0xFFB6E9C1);
  static const tealSoft = Color(0xFF75BCAF);
}

class CompleteTaskSheet extends StatefulWidget {
  final Map<String, dynamic> taskData;
  final DateTime selectedDay;

  /// ✅ بدال userTaskDocId نمرّر taskId نفسه
  final String taskId;

  const CompleteTaskSheet({
    super.key,
    required this.taskData,
    required this.selectedDay,
    required this.taskId,
  });

  @override
  State<CompleteTaskSheet> createState() => _CompleteTaskSheetState();
}

class _CompleteTaskSheetState extends State<CompleteTaskSheet> {
  CameraController? _controller;
  List<CameraDescription>? _cameras;
  final TextEditingController _itemCountCtrl = TextEditingController();

  bool _ready = false;
  bool _openingCamera = false;
  bool _isCapturing = false;
  bool _isUploading = false;

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

  // ✅ عدد العناصر المدخَل في الـ popup
  int? _itemCount;

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
    return kws.any((k) => s.contains(k));
  }

  bool get _isPerItemMode {
    final raw = (_calcRequires['calcMode'] ?? widget.taskData['calcMode'] ?? '')
        .toString()
        .toLowerCase()
        .trim();
    return raw == 'peritem' || raw == 'deltaperitem';
  }

  bool get _askCountFlag =>
      (_calcRequires['askCount'] == true) ||
      (widget.taskData['askCount'] == true) ||
      (widget.taskData['itemsEnabled'] == true) ||
      (widget.taskData['perItem'] == true);

  // 🚫 ما عاد نستخدم خانة "عدد العناصر" في الواجهة (لكن نستخدم popup)
  bool get _shouldAskCount => false;

  // ✅ هل هذه المهمة تحتاج popup لعدد العناصر؟
  bool get _requiresItemDialog {
    final mode = (widget.taskData['calcMode'] ?? '')
        .toString()
        .toLowerCase()
        .trim();
    return mode == 'deltaperitem';
  }

  String _yyyyMMdd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';

  /// ✅ نبني userTaskId داخليًا من uid + اليوم + taskId
  String _buildUserTaskId({
    required String uid,
    required DateTime day,
    required String taskId,
  }) {
    final dayKey = _yyyyMMdd(day);
    return '${uid}_${dayKey}_$taskId';
  }

  double _deg2rad(double deg) => deg * math.pi / 180.0;
  double _haversineKm(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371.0;
    final dLat = _deg2rad(lat2 - lat1);
    final dLon = _deg2rad(lat2 - lon1);
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
      final km = _haversineKm(
        start.latitude,
        start.longitude,
        end.latitude,
        end.longitude,
      );
      _autoDistanceKmComputed = km;
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
    if (d == null) {
      return null;
    }

    if (valueFieldFromTask != null && valueFieldFromTask.isNotEmpty) {
      final v = _asDouble(d[valueFieldFromTask]);
      if (v != null) {
        return v;
      }
    }
    final vfInDoc = d['valueField'] ?? d['efValueField'];
    if (vfInDoc is String && vfInDoc.isNotEmpty) {
      final v = _asDouble(vfInDoc);
      if (v != null) {
        return v;
      }
    }
    final candidates = [
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
    ];
    for (final k in candidates) {
      final v = _asDouble(d[k]);
      if (v != null) {
        return v;
      }
    }
    return null;
  }

  Future<double> _computeCarbonSavedFlexible({
    required String efIdFromTask,
    double? km,
    int? items,
    String? valueFieldFromTask,
  }) async {
    final efDoc = await _getEfDoc(efIdFromTask) ?? {};
    final taskCalcMode = (widget.taskData['calcMode'] ?? '').toString().trim();
    final efCalcMode = (efDoc['calcMode'] ?? '').toString().trim();
    final rawMode = (taskCalcMode.isNotEmpty ? taskCalcMode : efCalcMode);
    final calcMode = rawMode.toLowerCase();

    final baseRef =
        (widget.taskData['baselineFactorRef'] ?? efDoc['baselineFactorRef'])
            ?.toString();
    final actRef =
        (widget.taskData['actualFactorRef'] ?? efDoc['actualFactorRef'])
            ?.toString();

    if (calcMode == 'deltaperkm' && km != null && km > 0) {
      final baseline = baseRef != null
          ? await _getEfPerUnit(baseRef, valueFieldFromTask: valueFieldFromTask)
          : null;
      double? actual = await _getEfPerUnit(
        efIdFromTask,
        valueFieldFromTask: valueFieldFromTask,
      );
      if ((actual == null || actual == 0.0) && actRef != null) {
        actual = await _getEfPerUnit(
          actRef,
          valueFieldFromTask: valueFieldFromTask,
        );
      }
      final delta = ((baseline ?? 0.0) - (actual ?? 0.0));
      final res = (delta > 0 ? delta : 0.0) * km;
      return res;
    }

    if (calcMode == 'deltaperitem' && items != null && items > 0) {
      const defaultField = 'ef_kgco2_per_unit';

      final baseline = baseRef != null
          ? await _getEfPerUnit(
              baseRef,
              valueFieldFromTask: valueFieldFromTask ?? defaultField,
            )
          : null;

      double? actual = await _getEfPerUnit(
        efIdFromTask,
        valueFieldFromTask: valueFieldFromTask ?? defaultField,
      );

      if ((actual == null || actual == 0.0) && actRef != null) {
        actual = await _getEfPerUnit(
          actRef,
          valueFieldFromTask: valueFieldFromTask ?? defaultField,
        );
      }

      if (baseline == null && actual == null) {
        return 0.0;
      }

      final delta = ((baseline ?? 0.0) - (actual ?? 0.0));
      final perItem = delta > 0 ? delta : 0.0;
      final res = perItem * items;
      return res;
    }

    if ((calcMode.isEmpty || calcMode == 'auto') &&
        items != null &&
        items > 0) {
      await _getEfPerUnit(
        efIdFromTask,
        valueFieldFromTask: valueFieldFromTask ?? 'ef_kgco2_per_unit',
      );
    }

    if ((calcMode.isEmpty || calcMode == 'auto') && km != null && km > 0) {
      await _getEfPerUnit(efIdFromTask, valueFieldFromTask: valueFieldFromTask);
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
            _controller!.value.isTakingPicture) {
          return null;
        }
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

  Future<void> _createSubmissionAndMarkSubmitted({
    required String localPath,
    required int taskPoints,
    required String taskId,
    double? distanceKm,
    double? carbonSaved,
    int? itemCount,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('يرجى تسجيل الدخول.');
    }

    final file = File(localPath);
    if (!await file.exists()) {
      throw Exception('لم يتم العثور على ملف الصورة.');
    }

    final uid = user.uid;
    final dayKey = _yyyyMMdd(widget.selectedDay);

    /// ✅ نبني userTaskId موحّد
    final userTaskId = _buildUserTaskId(
      uid: uid,
      day: widget.selectedDay,
      taskId: taskId,
    );

    /// ✅ مسار أوضح في التخزين: submissions/{uid}/{dayKey}/{userTaskId}/{timestamp}.jpg
    final basePath = 'submissions/$uid/$dayKey/$userTaskId';
    final name = DateTime.now().millisecondsSinceEpoch.toString();

    final storage = FirebaseStorage.instance;
    final storageRef = storage.ref('$basePath/$name.jpg');

    Future<void> tryUpload() async {
      await storageRef
          .putFile(
            file,
            SettableMetadata(
              contentType: 'image/jpeg',
              cacheControl: 'public,max-age=3600',
            ),
          )
          .timeout(const Duration(seconds: 60));
    }

    try {
      try {
        await tryUpload();
      } catch (_) {
        await Future.delayed(const Duration(milliseconds: 300));
        await tryUpload();
      }
    } on FirebaseException catch (e) {
      throw FirebaseException(
        plugin: e.plugin,
        code: e.code,
        message: _friendlyError(e),
      );
    } on TimeoutException {
      throw Exception('انتهى وقت رفع الصورة.');
    } catch (e) {
      throw Exception(_friendlyError(e));
    }

    Future<String> getUrlWithRetry() async {
      try {
        return await storageRef.getDownloadURL().timeout(
          const Duration(seconds: 20),
        );
      } on TimeoutException {
        await Future.delayed(const Duration(milliseconds: 200));
        return await storageRef.getDownloadURL().timeout(
          const Duration(seconds: 20),
        );
      }
    }

    String downloadUrl;
    try {
      downloadUrl = await getUrlWithRetry();
    } on FirebaseException catch (e) {
      try {
        await storageRef.delete();
      } catch (_) {}
      throw FirebaseException(
        plugin: e.plugin,
        code: e.code,
        message: _friendlyError(e),
      );
    } on TimeoutException {
      try {
        await storageRef.delete();
      } catch (_) {}
      throw Exception('انتهى وقت جلب رابط الصورة.');
    } catch (e) {
      try {
        await storageRef.delete();
      } catch (_) {}
      throw Exception(_friendlyError(e));
    }

    final subRef = FirebaseFirestore.instance.collection('submissions').doc();

    /// ✅ نستخدم userTaskId الموحد هنا
    final utRef = FirebaseFirestore.instance
        .collection('userTasks')
        .doc(userTaskId);

    final extra = <String, dynamic>{};

    if (distanceKm != null) {
      extra['distanceKm'] = distanceKm;
    }

    final double carbonForStore = (carbonSaved != null && carbonSaved.isFinite)
        ? double.parse(carbonSaved.toStringAsFixed(3))
        : 0.0;

    extra['carbonSaved'] = carbonForStore;

    if (_geoStart != null) extra['geoStart'] = _geoStart;
    if (_geoEnd != null) extra['geoEnd'] = _geoEnd;

    if (itemCount != null) {
      extra['itemCount'] = itemCount;
    }
    final efId =
        (widget.taskData['ef_ref'] ??
                widget.taskData['efRef'] ??
                widget.taskData['emissionFactorRef'] ??
                widget.taskData['emission_factor_ref'])
            ?.toString();
    if (efId != null && efId.isNotEmpty) {
      extra['emissionFactorRef'] = efId;
    }

    final calcMode = widget.taskData['calcMode']?.toString();
    if (calcMode != null && calcMode.isNotEmpty) {
      extra['calcMode'] = calcMode;
    }

    /// ✅ ما نرجع نخزّن userTaskDocId كسطر منفصل
    await subRef.set({
      'userId': uid,
      'userTaskId': userTaskId,
      'taskId': taskId,
      'taskTitle': widget.taskData['title'] ?? '',
      'taskPoints': taskPoints,
      'status': 'pending',
      'imageUrls': [downloadUrl],
      'createdAt': FieldValue.serverTimestamp(),
      ...extra,
    });

    await utRef.set({
      'userId': uid,
      'userTaskId': userTaskId,
      'status': 'submitted',
      //'submittedAt': FieldValue.serverTimestamp(),
      'evidence': {
        'type': 'photo',
        'url': downloadUrl,
        'storagePath': storageRef.fullPath,
        //'uploadedAt': FieldValue.serverTimestamp(),
      },
      'taskTitle': widget.taskData['title'] ?? '',
      'taskPoints': taskPoints,
      'taskId': taskId,
      if (distanceKm != null) 'distanceKm': distanceKm,
      'carbonSaved': carbonForStore,
      if (_geoStart != null) 'geoStart': _geoStart,
      if (_geoEnd != null) 'geoEnd': _geoEnd,
      if (itemCount != null) 'itemCount': itemCount,
    }, SetOptions(merge: true));
  }

  Future<void> _openCamera({int? index}) async {
    if (_openingCamera) return;
    if (!mounted) return;

    setState(() {
      _openingCamera = true;
      _capturedPath = null;
      _ready = false;
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

      final minZoom = await controller.getMinZoomLevel();
      final maxZoom = await controller.getMaxZoomLevel();
      final minExposure = await controller.getMinExposureOffset();
      final maxExposure = await controller.getMaxExposureOffset();

      _minZoom = minZoom;
      _maxZoom = maxZoom;
      _zoom = _zoom.clamp(_minZoom, _maxZoom);
      _minExposure = minExposure;
      _maxExposure = maxExposure;
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

  @override
  void initState() {
    super.initState();
    if (_autoDistance || _isTransportTask) {
      _captureStartIfNeeded();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    _itemCountCtrl.dispose();
    super.dispose();
  }

  Future<void> _startFlowForTransportTask() async {
    final MapRoutePickResult? res =
        await Navigator.of(
          context,
          rootNavigator: true,
        ).push<MapRoutePickResult>(
          MaterialPageRoute(
            builder: (_) => MapPickRoutePage(
              initialStart: _manualStart,
              initialEnd: _manualEnd,
            ),
            fullscreenDialog: true,
          ),
        );

    if (!mounted || res == null) return;

    setState(() {
      _manualStart = res.start;
      _manualEnd = res.end;
      _manualDistanceKm = _haversineKm(
        res.start.latitude,
        res.start.longitude,
        res.end.latitude,
        res.end.longitude,
      );
      _geoStart = GeoPoint(_manualStart!.latitude, _manualStart!.longitude);
      _geoEnd = GeoPoint(_manualEnd!.latitude, _manualEnd!.longitude);
    });
    await Future.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _openCamera();
      }
    });
  }

  // ======================================================
  // ✅ Popup لإدخال عدد العناصر عند calcMode = deltaPerItem
  //    بدون صورة — وبنفس ستايل ديالوج تسجيل الخروج
  // ======================================================
  Future<void> _promptForItemCountIfNeeded() async {
    if (!_requiresItemDialog) return;

    // نحاول نقرأ أقل وأعلى قيمة من الـ taskData (لو موجودة), وإلا افتراضيًا 1..999
    final minItems = _asInt(widget.taskData['minItems']) ?? 1;
    final maxItems = _asInt(widget.taskData['maxItems']) ?? 999;

    int clamp(int v) => v.clamp(minItems, maxItems);

    // القيمة الافتراضية: آخر قيمة محفوظة، أو defaultItems من التاسك، أو minItems
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
                        // ===== العنوان + الأيقونة =====
                        Row(
                          children: [
                            const Icon(
                              Icons.format_list_numbered,
                              color: AppColors.primary,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'عدد العناصر المنجزة',
                              style: GoogleFonts.ibmPlexSansArabic(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: AppColors.dark,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // ===== أزرار - [TextField] + =====
                        Row(
                          children: [
                            _counterButton(
                              icon: Icons.remove_rounded,
                              onTap: () {
                                final cur = _asInt(_itemCountCtrl.text) ?? def;
                                final next = clamp(cur - 1);
                                _itemCountCtrl.text = next.toString();
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
                                final next = clamp(cur + 1);
                                _itemCountCtrl.text = next.toString();
                                setState(() {});
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),

                        // ===== نص الحد الأدنى والأقصى =====
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

                        // ===== أزرار إلغاء / حفظ =====
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => Navigator.of(ctx).pop(null),
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(
                                    color: AppColors.primary,
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
                                    color: AppColors.primary,
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
                                    _showInlineError('أدخل عددًا صحيحًا.');
                                    return;
                                  }
                                  final safe = clamp(raw);
                                  _itemCountCtrl.text = safe.toString();
                                  Navigator.of(ctx).pop(safe);
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.primary,
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

    // حفظ النتيجة في _itemCount
    if (result != null && result > 0) {
      setState(() {
        _itemCount = clamp(result);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final task = widget.taskData;
    final title = task['title'] ?? 'مهمة غير معروفة';
    final desc = task['description'] ?? '';
    final pts = (task['points'] ?? 0) as int;

    /// ✅ نستخدم taskId القادم من الـ widget
    final taskId = widget.taskId;

    final requiresPhotoExact = true;
    final isTransport = (_autoDistance || _isTransportTask);

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
                      color: AppColors.dark,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    title,
                    style: GoogleFonts.ibmPlexSansArabic(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(
                        Icons.star_border,
                        color: AppColors.primary,
                        size: 20,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '$pts نقطة',
                        style: GoogleFonts.ibmPlexSansArabic(
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
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
                  if (requiresPhotoExact && !isTransport && !_ready)
                    _gradientButton(
                      label: 'ابدأ التصوير',
                      icon: Icons.camera_alt,
                      onTap: _openingCamera ? null : () => _openCamera(),
                      loading: _openingCamera,
                    ),
                  if (requiresPhotoExact && isTransport && !_ready) ...[
                    _gradientButton(
                      label: 'ابدأ',
                      icon: Icons.play_arrow_rounded,
                      onTap: () => _startFlowForTransportTask(),
                    ),
                    if (_manualDistanceKm != null) ...[
                      const SizedBox(height: 10),
                      _hintCard(
                        'المسار المحدد: ${_manualDistanceKm!.toStringAsFixed(2)} كم\nاضغط "ابدأ" مرة أخرى لفتح الكاميرا إذا رغبت بتعديل المسار.',
                      ),
                    ],
                  ],
                  const SizedBox(height: 16),
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
                                              'عدد العناصر: ${_itemCount}',
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
                                if (mounted) {
                                  setState(() => _flashOpacity = 0.0);
                                }
                                final shot = await _safeTakePicture();
                                if (!mounted) return;
                                if (shot != null) {
                                  setState(() => _capturedPath = shot.path);

                                  // ✅ بعد التصوير مباشرة، نسأل عن عدد العناصر لو المهمة deltaPerItem
                                  await _promptForItemCountIfNeeded();
                                }
                                if (mounted) {
                                  setState(() => _isCapturing = false);
                                }
                              },
                      )
                    else
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _gradientButton(
                            label: _isUploading
                                ? 'جاري الإرسال...'
                                : 'إرسال للمراجعة',
                            icon: Icons.cloud_upload,
                            onTap: _isUploading
                                ? null
                                : () async {
                                    if (_capturedPath == null) return;

                                    // ✅ نجهّز عدد العناصر (من الـ popup)
                                    int? safeItems = _itemCount;

                                    final mode =
                                        (widget.taskData['calcMode'] ?? '')
                                            .toString()
                                            .toLowerCase();

                                    // ✅ لو المهمة deltaPerItem لازم يكون عندنا عدد عناصر
                                    if (mode == 'deltaperitem' &&
                                        (safeItems == null || safeItems <= 0)) {
                                      await _promptForItemCountIfNeeded();
                                      safeItems = _itemCount;
                                      if (safeItems == null || safeItems <= 0) {
                                        _showInlineError(
                                          'يرجى إدخال عدد العناصر.',
                                        );
                                        return;
                                      }
                                    }

                                    if (!mounted || _isUploading) return;
                                    setState(() => _isUploading = true);

                                    try {
                                      final isDistanceMode =
                                          mode == 'perkm' ||
                                          mode == 'deltaperkm';
                                      double? pickedKm;

                                      if (isDistanceMode) {
                                        final manualKm = _manualDistanceKm;
                                        await _captureEndAndComputeDistance();
                                        double? straightKm;
                                        if (_autoDistanceKmComputed != null &&
                                            _autoDistanceKmComputed!.isFinite &&
                                            _autoDistanceKmComputed! > 0) {
                                          straightKm = double.parse(
                                            _autoDistanceKmComputed!
                                                .toStringAsFixed(3),
                                          );
                                        }
                                        if (manualKm != null && manualKm > 0) {
                                          pickedKm = manualKm;
                                        } else if (straightKm != null &&
                                            straightKm > 0) {
                                          pickedKm = straightKm;
                                        }
                                        final askDistanceKm =
                                            widget.taskData['askDistanceKm'] ==
                                            true;
                                        final defaultKmOnSubmit =
                                            (widget.taskData['defaultKmOnSubmit']
                                                is num)
                                            ? (widget.taskData['defaultKmOnSubmit']
                                                      as num)
                                                  .toDouble()
                                            : null;
                                        if (pickedKm == null &&
                                            askDistanceKm &&
                                            defaultKmOnSubmit != null) {
                                          pickedKm = defaultKmOnSubmit;
                                        }
                                        double? minKm, maxKm;
                                        final mk = widget.taskData['minKm'];
                                        final xk = widget.taskData['maxKm'];
                                        if (mk is num) {
                                          minKm = mk.toDouble();
                                        }
                                        if (xk is num) {
                                          maxKm = xk.toDouble();
                                        }
                                        if (pickedKm != null && pickedKm > 0) {
                                          final clamped =
                                              pickedKm.clamp(
                                                    minKm ?? 0.2,
                                                    maxKm ?? 50.0,
                                                  )
                                                  as num;
                                          pickedKm = double.parse(
                                            clamped.toStringAsFixed(3),
                                          );
                                        }

                                        if (_manualStart != null &&
                                            _manualEnd != null) {
                                          _geoStart = GeoPoint(
                                            _manualStart!.latitude,
                                            _manualStart!.longitude,
                                          );
                                          _geoEnd = GeoPoint(
                                            _manualEnd!.latitude,
                                            _manualEnd!.longitude,
                                          );
                                        }
                                      }

                                      double? carbonSaved;
                                      final efId =
                                          (widget.taskData['ef_ref'] ??
                                                  widget.taskData['efRef'] ??
                                                  widget
                                                      .taskData['emissionFactorRef'] ??
                                                  widget
                                                      .taskData['emission_factor_ref'])
                                              ?.toString();
                                      final valueFieldFromTask =
                                          (widget.taskData['ef_valueField'] ??
                                                  widget.taskData['valueField'])
                                              ?.toString();
                                      if (efId != null && efId.isNotEmpty) {
                                        final saved =
                                            await _computeCarbonSavedFlexible(
                                              efIdFromTask: efId,
                                              km: pickedKm,
                                              items: safeItems,
                                              valueFieldFromTask:
                                                  valueFieldFromTask,
                                            );

                                        if (saved.isFinite) {
                                          carbonSaved = double.parse(
                                            saved.toStringAsFixed(3),
                                          );
                                        }
                                      }

                                      await _createSubmissionAndMarkSubmitted(
                                        localPath: _capturedPath!,
                                        taskPoints: pts,
                                        taskId: taskId,
                                        distanceKm: pickedKm,
                                        carbonSaved: carbonSaved,
                                        itemCount: safeItems,
                                      );

                                      if (!mounted) return;
                                      await showDialog(
                                        context: context,
                                        barrierDismissible: false,
                                        useRootNavigator: true,
                                        builder: (context) {
                                          return Dialog(
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(20),
                                            ),
                                            insetPadding:
                                                const EdgeInsets.symmetric(
                                                  horizontal: 24,
                                                ),
                                            child: SizedBox(
                                              width: 340,
                                              child: Padding(
                                                padding: const EdgeInsets.all(
                                                  20,
                                                ),
                                                child: Column(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    Image.asset(
                                                      'assets/img/nameerCamera.png',
                                                      height: 120,
                                                      fit: BoxFit.contain,
                                                    ),
                                                    const SizedBox(height: 16),
                                                    Text(
                                                      '!تم تسجيل مشاركتك بنجاح',
                                                      textAlign:
                                                          TextAlign.center,
                                                      style:
                                                          GoogleFonts.ibmPlexSansArabic(
                                                            fontSize: 20,
                                                            fontWeight:
                                                                FontWeight.w700,
                                                            color:
                                                                AppColors.dark,
                                                          ),
                                                    ),
                                                    const SizedBox(height: 12),
                                                    Text(
                                                      'جاري إرسالها للجنة المراجعة.\nعند الاعتماد، ستُضاف نقاطك تلقائيًا',
                                                      textAlign:
                                                          TextAlign.center,
                                                      style:
                                                          GoogleFonts.ibmPlexSansArabic(
                                                            fontSize: 16,
                                                            fontWeight:
                                                                FontWeight.w500,
                                                            color:
                                                                AppColors.dark,
                                                          ),
                                                    ),
                                                    const SizedBox(height: 24),
                                                    SizedBox(
                                                      width: 140,
                                                      child: ElevatedButton(
                                                        style: ElevatedButton.styleFrom(
                                                          backgroundColor:
                                                              AppColors.primary,
                                                          shape: RoundedRectangleBorder(
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                  12,
                                                                ),
                                                          ),
                                                          padding:
                                                              const EdgeInsets.symmetric(
                                                                horizontal: 24,
                                                                vertical: 10,
                                                              ),
                                                        ),
                                                        onPressed: () =>
                                                            Navigator.pop(
                                                              context,
                                                            ),
                                                        child: Text(
                                                          'تم',
                                                          style:
                                                              GoogleFonts.ibmPlexSansArabic(
                                                                color: Colors
                                                                    .white,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w700,
                                                                fontSize: 16,
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

                                      try {
                                        if (_capturedPath != null) {
                                          final f = File(_capturedPath!);
                                          if (await f.exists()) {
                                            await f.delete();
                                          }
                                        }
                                      } catch (_) {}
                                      if (!mounted) return;
                                      Navigator.of(context).pop(true);
                                    } catch (e) {
                                      if (!mounted) return;
                                      _showInlineError(_friendlyError(e));
                                    } finally {
                                      if (mounted) {
                                        setState(() => _isUploading = false);
                                      }
                                    }
                                  },
                          ),
                          const SizedBox(height: 10),
                          OutlinedButton.icon(
                            icon: const Icon(
                              Icons.refresh,
                              color: AppColors.primary,
                            ),
                            label: Text(
                              'إعادة التقاط',
                              style: GoogleFonts.ibmPlexSansArabic(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                                color: AppColors.primary,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(
                                color: AppColors.primary,
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
                                });
                              }
                            },
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

  Widget _hintCard(String text) => _hintCardWidget(text);

  Widget _hintCardWidget(String text) {
    return Material(
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
  }

  Widget _roundedGlass({required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.25),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white24, width: 1),
      ),
      child: child,
    );
  }

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
  }) {
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
          gradient: const LinearGradient(
            colors: [AppColors.primary, AppColors.mint],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: InkWell(
          onTap: onTap,
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
    final bullets = [
      'تأكد من أن الإضاءة جيدة والعنصر واضح.',
      'التقط صورة تُظهر قيامك بالمهمة (مثل العناصر المجمعة).',
      'لا تستخدم صورًا من الإنترنت.',
      'التقط من زاوية مناسبة وبدون فلاش إن أمكن.',
    ];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.mint.withOpacity(0.15),
        border: Border.all(color: AppColors.mint, width: 1.5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.camera_alt_outlined,
                color: AppColors.primary,
                size: 22,
              ),
              const SizedBox(width: 8),
              Text(
                'تعليمات التصوير',
                style: GoogleFonts.ibmPlexSansArabic(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.dark,
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
          color: AppColors.primary.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppColors.primary.withOpacity(0.45),
            width: 1.3,
          ),
        ),
        child: Icon(icon, size: 22, color: AppColors.primary),
      ),
    );
  }
}
