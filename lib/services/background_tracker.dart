import 'dart:async';
import 'dart:math' as math;
import 'package:geolocator/geolocator.dart';

class BackgroundTracker {
  BackgroundTracker._();
  static final BackgroundTracker instance = BackgroundTracker._();

  StreamSubscription<Position>? _sub;
  final List<Position> _points = [];
  Position? _last;
  double _km = 0.0;

  // فلترة الضوضاء
  double minMoveMeters = 8.0; // تجاهل اهتزازات أقل من 8 م
  double maxJumpMeters = 800.0; // تجاهل قفزات غير منطقية
  double maxAccuracyMeters = 45.0; // تجاهل نقاط ضعيفة الدقة

  // إعدادات الموقع
  LocationAccuracy accuracy = LocationAccuracy.high;
  int distanceFilterMeters = 5;

  // كولباك اختياري لتحديثات المسافة
  void Function(double km)? onDistanceKm;

  bool get isRunning => _sub != null;
  double get totalKm => _km;
  List<Position> get path => List.unmodifiable(_points);

  // لتجنّب التضارب مع start(...)
  Position? get startPosition => _points.isNotEmpty ? _points.first : null;
  Position? get endPosition => _points.isNotEmpty ? _points.last : null;

  /// تشغيل التتبّع
  Future<void> start({
    LocationAccuracy? accuracy,
    int? distanceFilterMeters,
    double? minMoveMeters,
    double? maxJumpMeters,
    double? maxAccuracyMeters,
    double? maxSpeedMps,
    int? minIntervalSeconds,
    bool resetOnStart = true,
  }) async {
    if (_sub != null) return; // يعمل مسبقًا

    // تطبيق القيم المُمرّرة (إن وُجدت)
    if (accuracy != null) this.accuracy = accuracy;
    if (distanceFilterMeters != null) {
      this.distanceFilterMeters = distanceFilterMeters;
    }
    if (minMoveMeters != null) this.minMoveMeters = minMoveMeters;
    if (maxJumpMeters != null) this.maxJumpMeters = maxJumpMeters;
    if (maxAccuracyMeters != null) this.maxAccuracyMeters = maxAccuracyMeters;

    if (resetOnStart) {
      reset();
    }

    // تحقق من الخدمة + الأذونات
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw StateError('خدمة تحديد الموقع مغلقة. فعّلي GPS أولاً.');
    }

    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      throw StateError('صلاحية الموقع مرفوضة. امنحي الإذن من الإعدادات.');
    }

    // نقطة بداية (اختياري)
    try {
      final p0 = await Geolocator.getCurrentPosition(
        desiredAccuracy: this.accuracy,
      );
      _pushPoint(p0);
    } catch (e) {
      print('getCurrentPosition error: $e');
    }

    final settings = LocationSettings(
      accuracy: this.accuracy,
      distanceFilter: this.distanceFilterMeters,
    );

    // لتطبيق حد زمني بين النقاط (throttling)
    DateTime? _lastTick;

    _sub = Geolocator.getPositionStream(locationSettings: settings).listen(
      (pos) {
        // 1) فلترة الدقة
        if (pos.accuracy.isFinite && pos.accuracy > (this.maxAccuracyMeters)) {
          return;
        }

        // 2) فلترة الحدّ الأدنى للفاصل الزمني
        if (minIntervalSeconds != null && minIntervalSeconds > 0) {
          final now = DateTime.now();
          if (_lastTick != null) {
            final diff = now.difference(_lastTick!).inSeconds;
            if (diff < minIntervalSeconds) {
              return;
            }
          }
          _lastTick = now;
        }

        // 3) حساب المسافة
        if (_last == null) {
          _pushPoint(pos);
          _notify();
          return;
        }

        final dMeters = _haversineMeters(
          _last!.latitude,
          _last!.longitude,
          pos.latitude,
          pos.longitude,
        );

        // 4) فلترة الاهتزازات والقفزات
        if (dMeters < this.minMoveMeters || dMeters > this.maxJumpMeters) {
          _last = pos; // نحدّث آخر نقطة حتى لو تجاهلنا المسافة
          return;
        }

        // 5) فلترة السرعة غير الواقعية (اختياري)
        if (maxSpeedMps != null && maxSpeedMps > 0) {
          final dtSec = pos.timestamp != null && _last!.timestamp != null
              ? pos.timestamp!.difference(_last!.timestamp!).inMilliseconds /
                    1000.0
              : null;
          if (dtSec != null && dtSec > 0) {
            final speed = dMeters / dtSec; // m/s
            if (speed > maxSpeedMps) {
              _last = pos; // تجاهل هذه النقطة
              return;
            }
          }
        }

        _km += dMeters / 1000.0;
        _pushPoint(pos);
        _notify();
      },
      onError: (e) => print('position stream error: $e'),
      cancelOnError: false,
    );
  }

  /// إيقاف التتبّع
  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
  }

  /// تصفير الحالة
  void reset() {
    _points.clear();
    _last = null;
    _km = 0.0;
  }

  /// خرائط مبسّطة للبداية/النهاية
  Map<String, dynamic>? get startMap => startPosition == null
      ? null
      : {
          'lat': startPosition!.latitude,
          'lng': startPosition!.longitude,
          'accuracy': startPosition!.accuracy,
        };

  Map<String, dynamic>? get endMap => endPosition == null
      ? null
      : {
          'lat': endPosition!.latitude,
          'lng': endPosition!.longitude,
          'accuracy': endPosition!.accuracy,
        };

  // ===== Helpers =====
  void _pushPoint(Position p) {
    _points.add(p);
    _last = p;
  }

  void _notify() {
    if (onDistanceKm != null) onDistanceKm!(_km);
  }

  double _haversineMeters(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371000.0; // نصف قطر الأرض بالمتر
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

  double _deg2rad(double d) => d * math.pi / 180.0;

  /// بدء رحلة بضغطة واحدة
  static Future<void> startTrip() async {
    final t = BackgroundTracker.instance;
    if (!t.isRunning) {
      await t.start(
        accuracy: LocationAccuracy.high,
        distanceFilterMeters: 5,
        minMoveMeters: 8.0,
        maxJumpMeters: 800.0,
        maxAccuracyMeters: 45.0,
        maxSpeedMps: 42.0, // ≈ 150 كم/س
        minIntervalSeconds: 1,
        resetOnStart: true,
      );
    }
  }

  /// إيقاف الرحلة وإرجاع مجموع الكيلومترات
  static Future<double?> stopAndGetDistanceKm() async {
    final t = BackgroundTracker.instance;
    if (t.isRunning) {
      await t.stop();
    }
    return t.totalKm > 0 ? t.totalKm : null;
  }

  /// تهيئة اختيارية (يمكنك استدعاؤها في main)
  static Future<void> initialize() async {
    final t = BackgroundTracker.instance;
    // قيم افتراضية
    t.accuracy = LocationAccuracy.high;
    t.distanceFilterMeters = 5;
    t.minMoveMeters = 8.0;
    t.maxJumpMeters = 800.0;
    t.maxAccuracyMeters = 45.0;

    // طلب صلاحية الموقع مبدئيًا (اختياري)
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        // لا نرمي خطأ الآن — سنتحقق وقت start()
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        await Geolocator.requestPermission();
      }
    } catch (_) {}
  }
}
