// lib/pages/map_page.dart
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart'; // 👈 فتح الخرائط

// صفحات أخرى
import 'home.dart';
import 'task.dart';
import 'community.dart';
import 'levels.dart';
import 'profile.dart';

/// ================== ألوان الواجهة ==================
class AppColors {
  static const primary = Color(0xFF009688);
  static const dark = Color(0xFF00695C);
  static const light = Color(0xFF4DB6AC);
  static const background = Color(0xFFFAFCFB);
  static const mint = Color(0xFFB6E9C1);
  static const sea = Color(0xFF1F7A8C);
}

/// نموذج مبسّط لعنصر Facility
class Facility {
  final String id;
  final double lat;
  final double lng;
  final String type; // مثل: RVM أو حاوية ملابس...
  final String provider; // من الداتابيس
  final String city;
  final String address;
  final String status; // 'نشط' أو 'متوقف'

  Facility({
    required this.id,
    required this.lat,
    required this.lng,
    required this.type,
    required this.provider,
    required this.city,
    required this.address,
    required this.status,
  });
}

class mapPage extends StatefulWidget {
  const mapPage({super.key});
  @override
  State<mapPage> createState() => _mapPageState();
}

class _mapPageState extends State<mapPage> {
  final Completer<GoogleMapController> _mapCtrl = Completer();
  final TextEditingController _searchCtrl = TextEditingController();

  static const _riyadh = LatLng(24.7136, 46.6753);
  static const _initZoom = 12.5;
  static const double _nearbyKm = 7.0; // 👈 نصف قطر "القريب"

  final Set<Marker> _markers = {};
  final Set<Marker> _allMarkers = {};
  final Set<Polyline> _polylines = {};
  final Map<String, Facility> _facilitiesByMarkerId = {};

  bool _myLocationEnabled = false;
  bool _isLoadingLocation = false;
  bool _didAutoCenter = false; // لمنع التمركز التلقائي أكثر من مرة

  // === أيقونات مخصّصة للماركرز
  BitmapDescriptor? _iconClothes;
  BitmapDescriptor? _iconPapers;
  BitmapDescriptor? _iconRvm;
  BitmapDescriptor? _iconFood;
  BitmapDescriptor? _iconDefault;

  // === حالة التحميل/الرسالة المؤقتة ===
  bool _isLoadingFacilities = false; // تحميل بيانات الحاويات
  bool _didInitialLoad = false; // تمّ أول تحميل؟
  bool _showEmptyOverlay = false; // إظهار "لا توجد حاويات" مؤقتًا
  Timer? _emptyTimer; // مؤقّت الإخفاء

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _ensureLocationPermission();
    await _loadMarkerIcons();
    await _loadFacilitiesFromFirestore();

    // إن كانت صلاحية الموقع مفعّلة: تمركز + تصفية القريب
    if (mounted && _myLocationEnabled) {
      await _centerOnUserAndFilterNearby();
      _didAutoCenter = true;
    }
  }

  @override
  void dispose() {
    _emptyTimer?.cancel();
    super.dispose();
  }

  /// تحميل صور الأيقونات كـ BitmapDescriptor حادّ (يدعم كثافات الشاشة)
  Future<void> _loadMarkerIcons() async {
    _iconClothes = await _bitmapFromAsset('assets/img/clothes.png', width: 200);
    _iconPapers = await _bitmapFromAsset('assets/img/papers.png', width: 200);
    _iconRvm = await _bitmapFromAsset('assets/img/rvm.png', width: 200);
    _iconFood = await _bitmapFromAsset('assets/img/food.png', width: 200);
    _iconDefault = BitmapDescriptor.defaultMarkerWithHue(
      BitmapDescriptor.hueRed,
    );
  }

  Future<BitmapDescriptor> _bitmapFromAsset(
    String path, {
    int width = 112,
  }) async {
    final data = await rootBundle.load(path);
    final codec = await ui.instantiateImageCodec(
      data.buffer.asUint8List(),
      targetWidth: width,
      targetHeight: width,
    );
    final fi = await codec.getNextFrame();
    final byteData = await fi.image.toByteData(format: ui.ImageByteFormat.png);
    final bytes = byteData!.buffer.asUint8List();
    return BitmapDescriptor.fromBytes(bytes);
  }

  // ===== Helpers =====
  String _normalizeType(String raw) {
    final t = raw.trim();
    final lower = t;
    final isClothes =
        lower.contains('ملابس') ||
        lower.contains('كسوة') ||
        lower.contains('clothes');
    final isRvm =
        lower.contains('rvm') ||
        lower.contains('آلة') ||
        lower.contains('استرجاع') ||
        lower.contains('reverse vending');
    final isPapers =
        lower.contains('ورق') ||
        lower.contains('أوراق') ||
        lower.contains('كتب') ||
        lower.contains('paper') ||
        lower.contains('books');
    final isFood =
        lower.contains('أكل') ||
        lower.contains('طعام') ||
        lower.contains('عضوي') ||
        lower.contains('بقايا') ||
        lower.contains('food') ||
        lower.contains('organic');

    if (isClothes) return 'حاوية إعادة تدوير الملابس';
    if (isRvm) return 'آلة استرجاع (RVM)';
    if (isPapers) return 'حاوية إعادة تدوير الأوراق';
    if (isFood) return 'حاوية إعادة تدوير بقايا الطعام';
<<<<<<< HEAD

    // أنواع أخرى شائعة
=======
>>>>>>> 872b0d3858cb1905760691324c07d3eeedfacd56
    if (lower.contains('قوارير') ||
        lower.contains('بلاستيك') ||
        lower.contains('علب') ||
        lower.contains('bottle') ||
        lower.contains('plastic')) {
      return 'حاوية إعادة تدوير القوارير';
    }
    return t.isEmpty ? 'نقطة استدامة' : t;
  }

  BitmapDescriptor _iconForType(String type) {
    switch (type) {
      case 'حاوية إعادة تدوير الملابس':
        return _iconClothes ??
            BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet);
      case 'حاوية إعادة تدوير الأوراق':
        return _iconPapers ??
            BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange);
      case 'آلة استرجاع (RVM)':
        return _iconRvm ??
            BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure);
      case 'حاوية إعادة تدوير بقايا الطعام':
        return _iconFood ??
            BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen);
      default:
        return _iconDefault ??
            BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed);
    }
  }

  LatLngBounds _extendBounds(LatLngBounds? current, LatLng p) {
    if (current == null) return LatLngBounds(southwest: p, northeast: p);
    final sw = LatLng(
      p.latitude < current.southwest.latitude
          ? p.latitude
          : current.southwest.latitude,
      p.longitude < current.southwest.longitude
          ? p.longitude
          : current.southwest.longitude,
    );
    final ne = LatLng(
      p.latitude > current.northeast.latitude
          ? p.latitude
          : current.northeast.latitude,
      p.longitude > current.northeast.longitude
          ? p.longitude
          : current.northeast.longitude,
    );
    return LatLngBounds(southwest: sw, northeast: ne);
  }

  // === وميض رسالة "لا توجد حاويات" لمدة 3 ثوانٍ ===
  void _flashEmptyMsg() {
    _emptyTimer?.cancel();
    setState(() => _showEmptyOverlay = true);
    _emptyTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _showEmptyOverlay = false);
    });
  }

  // ===== Load facilities from Firestore =====
  Future<void> _loadFacilitiesFromFirestore() async {
    setState(() => _isLoadingFacilities = true);
    try {
      final qs = await FirebaseFirestore.instance
          .collection('facilities')
          .get();

      final markers = <Marker>{};
      final mapFacilities = <String, Facility>{};
      LatLngBounds? bounds;

      for (final d in qs.docs) {
        final m = d.data();

        final double? lat = (m['lat'] as num?)?.toDouble();
        final double? lng = (m['lng'] as num?)?.toDouble();
        if (lat == null || lng == null) continue;

        // تحقّق حدود منطقية حول الرياض
        final valid = lat > 20 && lat < 30 && lng > 40 && lng < 55;
        if (!valid) continue;

        final String type = _normalizeType((m['type'] ?? '').toString());
        final String provider = (m['provider'] ?? '').toString();
        final String city = (m['city'] ?? '').toString();
        final String address = (m['address'] ?? '').toString();
<<<<<<< HEAD
        final String status = (m['status'] ?? 'نشط')
            .toString(); // 👈 قراءة الحالة
=======
        final String status = (m['status'] ?? 'نشط').toString();
>>>>>>> 872b0d3858cb1905760691324c07d3eeedfacd56

        final pos = LatLng(lat, lng);
        final markerId = MarkerId(d.id);

        final facility = Facility(
          id: d.id,
          lat: lat,
          lng: lng,
          type: type,
          provider: provider,
          city: city,
          address: address,
          status: status,
        );
        mapFacilities[markerId.value] = facility;

        markers.add(
          Marker(
            markerId: markerId,
            position: pos,
            icon: _iconForType(type),
            consumeTapEvents: true,
            infoWindow: InfoWindow(
              title: type,
              snippet: address.isNotEmpty
                  ? address
                  : [
                      if (provider.isNotEmpty) provider,
                      if (city.isNotEmpty) city,
                    ].join(' • '),
<<<<<<< HEAD
              onTap: () =>
                  _showFacilitySheet(facility), // 👈 فتح الورقة من البابل
            ),
            onTap: () => _showFacilitySheet(facility), // 👈 فتح الورقة من البن
=======
              onTap: () => _showFacilitySheet(facility),
            ),
            onTap: () => _showFacilitySheet(facility),
>>>>>>> 872b0d3858cb1905760691324c07d3eeedfacd56
          ),
        );

        bounds = _extendBounds(bounds, pos);
      }

      if (!mounted) return;
      setState(() {
        _facilitiesByMarkerId
          ..clear()
          ..addAll(mapFacilities);
        _allMarkers
          ..clear()
          ..addAll(markers);
        _markers
          ..clear()
          ..addAll(markers);
      });

      // لو المستخدم ما فعّل الموقع، نملأ الخريطة bounds لكل النقاط.
      if (!_myLocationEnabled && bounds != null && _markers.isNotEmpty) {
        final ctrl = await _mapCtrl.future;
        await ctrl.animateCamera(CameraUpdate.newLatLngBounds(bounds, 60));
      }

      debugPrint('✅ Loaded ${markers.length} facilities from Firestore');
    } catch (e) {
      debugPrint('❌ Facilities load error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذّر تحميل نقاط الخريطة')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingFacilities = false;
          if (!_didInitialLoad) _didInitialLoad = true;
          // بعد اكتمال التحميل: إن كانت النتيجة فارغة أظهري الرسالة مؤقتًا
          if (_markers.isEmpty) _flashEmptyMsg();
        });
      }

      // إن كانت الصلاحية مفعلة ولم نتمركز تلقائياً بعد، نعمل تمركز + تصفية قريب
      if (mounted && _myLocationEnabled && !_didAutoCenter) {
        await _centerOnUserAndFilterNearby();
        _didAutoCenter = true;
      }
    }
  }

  // ===== فتح الاتجاهات في Google Maps =====
  Future<void> _openInMaps(Facility f) async {
<<<<<<< HEAD
    // نحاول أولًا مخطط comgooglemaps:// (يفتح التطبيق مباشرة على iOS/Android إن كان مثبت)
    final googleMapsUri = Uri.parse(
      'comgooglemaps://?daddr=${f.lat},${f.lng}&directionsmode=driving',
    );
    // رابط ويب عام يفتح التطبيق إن كان مثبت أو المتصفح كخيار احتياطي
=======
    final googleMapsUri = Uri.parse(
      'comgooglemaps://?daddr=${f.lat},${f.lng}&directionsmode=driving',
    );
>>>>>>> 872b0d3858cb1905760691324c07d3eeedfacd56
    final webUri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=${f.lat},${f.lng}&travelmode=driving',
    );

    try {
      if (await canLaunchUrl(googleMapsUri)) {
        await launchUrl(googleMapsUri, mode: LaunchMode.externalApplication);
      } else {
        await launchUrl(webUri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      await launchUrl(webUri, mode: LaunchMode.externalApplication);
    }
  }

  // ===== Location =====
  Future<void> _ensureLocationPermission() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      // ما في GPS — نخلي الخريطة على الرياض بدون تمركز
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    final granted =
        permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;

    if (mounted) setState(() => _myLocationEnabled = granted);
  }

  Future<void> _centerOnUserAndFilterNearby() async {
    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      final userLatLng = LatLng(pos.latitude, pos.longitude);

      // حرّك الكاميرا
      final controller = await _mapCtrl.future;
      await controller.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: userLatLng, zoom: 15.5),
        ),
      );

      // صفّي النقاط القريبة ضمن نصف القطر
      _filterMarkersByDistance(userLatLng, _nearbyKm);
    } catch (e) {
      debugPrint('❌ center/filter error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذّر تحديد موقعك. تأكد من الإذن وGPS')),
      );
    }
  }

  void _filterMarkersByDistance(LatLng center, double kmRadius) {
    if (_allMarkers.isEmpty) return;

    final nearby = _allMarkers.where((m) {
      final d = Geolocator.distanceBetween(
        center.latitude,
        center.longitude,
        m.position.latitude,
        m.position.longitude,
      ); // بالأمتار
      return d <= kmRadius * 1000.0;
    }).toSet();

    setState(() {
      _markers
        ..clear()
        ..addAll(nearby.isNotEmpty ? nearby : _allMarkers);
    });

    if (nearby.isEmpty) {
      // لا توجد نقاط قريبة — نعرض الكل ونبلغ المستخدم
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('لا توجد نقاط قريبة ضمن النطاق — تم عرض جميع النقاط'),
        ),
      );
    }
  }

  Future<void> _goToMyLocation() async {
    setState(() => _isLoadingLocation = true);
    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      final user = LatLng(pos.latitude, pos.longitude);
      final controller = await _mapCtrl.future;
      await controller.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: user, zoom: 15.5),
        ),
      );

      // مع التركيز، نعيد تصفية النقاط القريبة
      _filterMarkersByDistance(user, _nearbyKm);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تعذّر تحديد موقعك. تأكد من الإذن وGPS'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoadingLocation = false);
    }
  }

  Future<void> _onSearchSubmitted(String query) async {
    query = query.trim();
    if (query.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى إدخال نص البحث أولاً.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // 🔤 توحيد الحروف العربية
    String normalizeArabic(String input) {
      return input
          .replaceAll(RegExp(r'[إأآا]'), 'ا')
          .replaceAll('ى', 'ي')
          .replaceAll('ئ', 'ي')
          .replaceAll('ؤ', 'و')
          .replaceAll('ة', 'ه')
          .replaceAll(RegExp(r'[ًٌٍَُِّْ]'), '')
          .replaceAll(RegExp(r'[^\u0621-\u064Aa-z0-9 ]'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim()
          .toLowerCase();
    }

    // 🧹 إزالة كلمات عامة غير مؤثرة
    String cleanInput(String input) {
      final wordsToRemove = [
        'اقرب',
        'الاقرب',
        'وين',
        'فين',
        'ابي',
        'ابغى',
        'اريد',
        'دلني',
        'دليني',
        'فيه',
        'مكان',
        'نقطه',
        'نقطة',
        'تدوير',
        'حول',
        'قريب',
        'قريبه',
        'في',
        'الحي',
        'حي',
        'شارع',
        'طريق',
        'اين',
      ];
      for (final w in wordsToRemove) {
        input = input.replaceAll(w, '');
      }
      return input.trim();
    }

    final normalizedQuery = normalizeArabic(cleanInput(query.toLowerCase()));

    // 🧠 نحدد نية المستخدم (نوع البحث)
    final isNearestSearch = query.contains('اقرب');
    final isAreaSearch = query.contains('حي') || query.contains('شارع');

    // 🧩 قاموس المترادفات
    final Map<String, List<String>> synonyms = {
      'قوارير': [
        'قوارير',
        'علب',
        'بلاستيك',
        'زجاج',
        'bottle',
        'bottles',
        'plastic',
      ],
      'ملابس': [
        'ملابس',
        'تبرع',
        'كسوة',
        'cloth',
        'clothes',
        'clothing',
        'donation',
        'clothes box',
      ],
      'اوراق': ['اوراق', 'ورق', 'كتب', 'paper', 'papers', 'books'],
      'طعام': ['طعام', 'اكل', 'بقايا', 'عضوي', 'organic', 'food'],
      'rvm': ['rvm', 'اله', 'آلة', 'استرجاع', 'reverse vending', 'rvm machine'],
    };

    // ✅ تحديد نوع البحث
    String? searchCategory;
    for (final entry in synonyms.entries) {
      if (entry.value.any(
        (w) => normalizedQuery.contains(normalizeArabic(w)),
      )) {
        searchCategory = entry.key;
        break;
      }
    }

    // 📍 تحديد موقع المستخدم (افتراضي الرياض)
    Position pos;
    try {
      pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
    } catch (_) {
      pos = Position(
        latitude: 24.7136,
        longitude: 46.6753,
        timestamp: DateTime.now(),
        accuracy: 10,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: 0,
        speedAccuracy: 0,
      );
    }

    // 🔍 نبحث عن الحاويات المطابقة
    final List<Map<String, dynamic>> matches = [];

    for (final f in _facilitiesByMarkerId.values) {
      final combined = normalizeArabic(
        '${f.type} ${f.address} ${f.city} ${f.provider}',
      );
      bool isMatch = false;

      // 🟢 نتحقق من نوع الحاوية
      if (searchCategory != null) {
        final keywords = synonyms[searchCategory]!
            .map(normalizeArabic)
            .toList();
        for (final k in keywords) {
          if (combined.contains(k)) {
            isMatch = true;
            break;
          }
        }
      } else {
        isMatch = combined.contains(normalizedQuery);
      }

      // 🟣 نتحقق من الموقع (حي أو شارع)
      final addressNorm = normalizeArabic(f.address);
      final cityNorm = normalizeArabic(f.city);
      final queryNorm = normalizeArabic(normalizedQuery);

      String? possibleArea;

      // 🔍 نحاول نكتشف اسم الحي أو الشارع من الجملة
      final areaMatch = RegExp(
        r'(?:حي|شارع|طريق)\s*([^\s]+)',
      ).firstMatch(query);
      if (areaMatch != null && areaMatch.groupCount >= 1) {
        possibleArea = normalizeArabic(areaMatch.group(1)!);
      } else {
        // لو ما فيه كلمة "حي" أو "شارع"، ناخذ آخر كلمة (احتمال تكون اسم الحي)
        final words = queryNorm.split(' ');
        if (words.isNotEmpty) {
          possibleArea = words.last;
        }
      }

      // 🔎 نتحقق فعلاً من وجودها في العنوان أو المدينة
      if (possibleArea != null &&
          (addressNorm.contains(possibleArea) ||
              cityNorm.contains(possibleArea))) {
        isMatch = true;
      }

      if (isMatch) {
        final dist = Geolocator.distanceBetween(
          pos.latitude,
          pos.longitude,
          f.lat,
          f.lng,
        );
        matches.add({'facility': f, 'dist': dist});
      }
    }

    // 🚫 في حال ما لقى نتائج
    if (matches.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('لم يتم العثور على مواقع مطابقة لعبارة "$query".'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // 📏 نقرر كيف نعرض النتائج (أقرب أو الكل)
    List<Map<String, dynamic>> top = [];
    if (isNearestSearch || (!isAreaSearch && searchCategory != null)) {
      matches.sort((a, b) => a['dist'].compareTo(b['dist']));
      top = matches.take(5).toList();
    } else if (isAreaSearch) {
      top = matches;
    } else {
      top = matches;
    }

    final nearest = top.first['facility'] as Facility;
    final nearestDist = top.first['dist'] as double;

    // 🗺️ نعرض النتائج على الخريطة
    setState(() {
      _markers
        ..clear()
        ..addAll(
          _allMarkers.where((m) {
            return top.any(
              (t) =>
                  (m.position.latitude == (t['facility'] as Facility).lat) &&
                  (m.position.longitude == (t['facility'] as Facility).lng),
            );
          }),
        );
    });

    // 🎯 تقريب الكاميرا لتشمل كل النتائج (سواء أقرب أو حي/شارع)
    final ctrl = await _mapCtrl.future;
    LatLngBounds? bounds;

    for (final t in top) {
      final f = t['facility'] as Facility;
      final p = LatLng(f.lat, f.lng);

      if (bounds == null) {
        bounds = LatLngBounds(southwest: p, northeast: p);
      } else {
        bounds = LatLngBounds(
          southwest: LatLng(
            p.latitude < bounds.southwest.latitude
                ? p.latitude
                : bounds.southwest.latitude,
            p.longitude < bounds.southwest.longitude
                ? p.longitude
                : bounds.southwest.longitude,
          ),
          northeast: LatLng(
            p.latitude > bounds.northeast.latitude
                ? p.latitude
                : bounds.northeast.latitude,
            p.longitude > bounds.northeast.longitude
                ? p.longitude
                : bounds.northeast.longitude,
          ),
        );
      }
    }

    // إذا عندنا نتائج، نقرب الكاميرا لتشملها كلها
    if (bounds != null) {
      await ctrl.animateCamera(CameraUpdate.newLatLngBounds(bounds, 100));
    }

    // 📢 نص الرسالة حسب نوع البحث
    String message;
    final categoryText = searchCategory ?? 'نقطة استدامة';
    if (isNearestSearch || (!isAreaSearch && searchCategory != null)) {
      message =
          'تم العثور على ${top.length} من $categoryText. أقربها يبعد ${nearestDist > 1000 ? (nearestDist / 1000).toStringAsFixed(1) + " كم" : nearestDist.toStringAsFixed(0) + " متر"}.';
    } else if (isAreaSearch) {
      message = 'تم العثور على ${top.length} من $categoryText .';
    } else {
      message = 'تم العثور على ${top.length} من نقاط الاستدامة.';
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );

    // 🕓 نعرض السناك بار أول، وبعدها بثانية نظهر تفاصيل الحاوية
    if (isNearestSearch || (!isAreaSearch && searchCategory != null)) {
      Future.delayed(const Duration(seconds: 1), () {
        _showFacilitySheet(nearest);
      });
    }
  }

  // ===== Bottom sheet لتفاصيل الفاسيليتي =====
  void _showFacilitySheet(Facility f) {
    final bool isActive = (f.status == 'نشط');

    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      f.type,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  Chip(
                    label: Text(
                      isActive ? 'نشطة' : 'متوقفة',
                      style: const TextStyle(color: Colors.white),
                    ),
                    backgroundColor: isActive ? Colors.teal : Colors.redAccent,
                  ),
                ],
              ),
              const SizedBox(height: 6),

              Row(
                children: [
                  const Icon(
                    Icons.factory_outlined,
                    size: 18,
                    color: AppColors.dark,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      f.provider.isEmpty ? 'مزود غير محدد' : f.provider,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),

              if (f.address.isNotEmpty || f.city.isNotEmpty)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.place_outlined,
                      size: 18,
                      color: AppColors.dark,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(f.address.isNotEmpty ? f.address : f.city),
                    ),
                  ],
                ),

              if (!isActive) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0x1FFF5252),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    'تنبيه: هذه الحاوية حالياً متوقفة عن العمل.',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],

              const SizedBox(height: 12),

              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      icon: const Icon(Icons.directions_outlined),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.blue,
                      ),
                      onPressed: () {
                        Navigator.pop(context);
                        _openInMaps(f);
                      },
                      label: const Text('عرض الاتجاهات'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      icon: const Icon(Icons.report_gmailerrorred_outlined),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                      ),
                      onPressed: () {
                        Navigator.pop(context);
                        _openReportDialog(f);
                      },
                      label: const Text('الإبلاغ عن مشكلة'),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  // ===== Dialog لإرسال بلاغ =====
  void _openReportDialog(Facility f) {
    final descCtrl = TextEditingController();
    String? selectedType;
    final types = <String>[
      'الموقع غير دقيق',
      'الحاوية ممتلئة',
      'عطل/مكسورة',
      'غير نظيفة',
      'أخرى',
    ];

    showDialog(
      context: context,
      builder: (_) {
        return AlertDialog(
          title: const Text('إرسال بلاغ عن الحاويات'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(labelText: 'نوع البلاغ'),
                items: types
                    .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                    .toList(),
                onChanged: (v) => selectedType = v,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: descCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'وصف المشكلة (اختياري)',
                  hintText: 'اكتب وصفًا مختصرًا للمشكلة',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () async {
                if (selectedType == null || selectedType!.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('اختر نوع البلاغ')),
                  );
                  return;
                }
                Navigator.pop(context);
                await _submitFacilityReport(
                  facility: f,
                  type: selectedType!.trim(),
                  description: descCtrl.text.trim(),
                );
              },
              child: const Text('إرسال'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _submitFacilityReport({
    required Facility facility,
    required String type,
    required String description,
  }) async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid ?? 'anonymous';
      await FirebaseFirestore.instance.collection('facilityReports').add({
        'decision': 'pending',
        'description': description,
        'type': type,
        'facilityID': facility.id,
        'reportedBy': uid,
        'managedBy': '',
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;

      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          title: const Text('شكرًا لك 💚', textAlign: TextAlign.center),
          content: const Text(
            'تم استلام بلاغك بنجاح وسنقوم بمراجعته قريبًا\n\nنقدّر مساهمتك في تحسين نقاط الاستدامة',
            textAlign: TextAlign.center,
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
              onPressed: () => Navigator.pop(context),
              child: const Text('تم'),
            ),
          ],
        ),
      );
    } catch (e) {
      debugPrint('❌ report error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذّر إرسال البلاغ، حاول لاحقًا')),
      );
    }
  }

  // === تراكب "لا توجد حاويات" المؤقّت ===
  Widget _buildEmptyStateOverlay() {
    if (!_showEmptyOverlay || _isLoadingFacilities) {
      return const SizedBox.shrink();
    }
    return Positioned.fill(
      child: IgnorePointer(
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x22000000),
                  blurRadius: 12,
                  offset: Offset(0, 6),
                ),
              ],
            ),
            child: const Text(
              'لا توجد حاويات',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isKeyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;

    final themeWithIbmPlex = Theme.of(context).copyWith(
      textTheme: GoogleFonts.ibmPlexSansArabicTextTheme(
        Theme.of(context).textTheme,
      ),
      primaryTextTheme: GoogleFonts.ibmPlexSansArabicTextTheme(
        Theme.of(context).primaryTextTheme,
      ),
    );

    final _authUser = FirebaseAuth.instance.currentUser;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Theme(
        data: themeWithIbmPlex,
        child: Scaffold(
          resizeToAvoidBottomInset: true,
          body: Stack(
            children: [
              GoogleMap(
                mapType: MapType.normal,
                initialCameraPosition: const CameraPosition(
                  target: _riyadh,
                  zoom: _initZoom,
                ),
                onMapCreated: (c) {
                  if (!_mapCtrl.isCompleted) _mapCtrl.complete(c);
                },
                myLocationEnabled: _myLocationEnabled,
                myLocationButtonEnabled: false,
                compassEnabled: true,
                zoomControlsEnabled: false,
                markers: _markers,
                polylines: _polylines,
                mapToolbarEnabled: false,
              ),

              // 👇 تراكب الرسالة المؤقتة
              _buildEmptyStateOverlay(),

              // Header + Search
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                  child: Column(
                    children: [
                      // ✅ الهيدر الآن من Firestore بدل القيم الثابتة
                      (_authUser == null)
                          ? const SizedBox.shrink()
                          : StreamBuilder<
                              DocumentSnapshot<Map<String, dynamic>>
                            >(
                              stream: FirebaseFirestore.instance
                                  .collection('users')
                                  .doc(_authUser.uid)
                                  .snapshots(),
                              builder: (context, snap) {
                                final isLoading =
                                    snap.connectionState ==
                                    ConnectionState.waiting;
                                final data = snap.data?.data() ?? {};

                                final username = (data['username'] ?? 'مستخدم')
                                    .toString();
                                final points = (data['points'] is int)
                                    ? data['points'] as int
                                    : int.tryParse('${data['points'] ?? 0}') ??
                                          0;

                                final int? pfpIndex = (data['pfpIndex'] is int)
                                    ? data['pfpIndex'] as int
                                    : int.tryParse('${data['pfpIndex'] ?? ''}');
                                final String? avatarPath =
                                    (pfpIndex != null &&
                                        pfpIndex >= 0 &&
                                        pfpIndex < 8)
                                    ? 'assets/pfp/pfp${pfpIndex + 1}.png'
                                    : null;

                                if (isLoading) {
                                  return Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(16),
                                      boxShadow: const [
                                        BoxShadow(
                                          color: Color(0x14000000),
                                          blurRadius: 16,
                                          offset: Offset(0, 8),
                                        ),
                                      ],
                                    ),
                                    child: Row(
                                      children: [
                                        const CircleAvatar(
                                          radius: 18,
                                          backgroundColor: Color(0x11009688),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Container(
                                            height: 14,
                                            decoration: BoxDecoration(
                                              color: const Color(0x11000000),
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Container(
                                          width: 98,
                                          height: 30,
                                          decoration: BoxDecoration(
                                            color: const Color(0x11000000),
                                            borderRadius: BorderRadius.circular(
                                              100,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }

                                return _HeaderUser(
                                  name: username,
                                  points: points,
                                  avatarPath: avatarPath,
                                );
                              },
                            ),
                      const SizedBox(height: 10),
                      _SearchBar(
                        controller: _searchCtrl,
                        onSubmitted: _onSearchSubmitted,
                        onFilterTap: _showFiltersBottomSheet,
                      ),
                    ],
                  ),
                ),
              ),

              // أزرار عائمة يمين
              Positioned(
                right: 12,
                bottom: isKeyboardOpen ? 12 : 28,
                child: Column(
                  children: [
                    _RoundBtn(
                      icon: Icons.my_location,
                      tooltip: 'موقعي الحالي',
                      onTap: _goToMyLocation,
                      isLoading: _isLoadingLocation,
                    ),
                    const SizedBox(height: 10),
                    _RoundBtn(
                      icon: Icons.refresh_rounded,
                      tooltip: 'تحديث النقاط',
                      onTap: _loadFacilitiesFromFirestore,
                    ),
                  ],
                ),
              ),

              // لوجند يطابق الأيقونات
              Positioned(
                left: 12,
                bottom: isKeyboardOpen ? 12 : 28,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x14000000),
                        blurRadius: 12,
                        offset: Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
<<<<<<< HEAD
                    children: [
=======
                    children: const [
>>>>>>> 872b0d3858cb1905760691324c07d3eeedfacd56
                      _LegendIcon(
                        path: 'assets/img/clothes.png',
                        label: 'ملابس',
                      ),
<<<<<<< HEAD
                      const SizedBox(width: 10),
=======
                      SizedBox(width: 10),
>>>>>>> 872b0d3858cb1905760691324c07d3eeedfacd56
                      _LegendIcon(
                        path: 'assets/img/papers.png',
                        label: 'أوراق',
                      ),
<<<<<<< HEAD
                      const SizedBox(width: 10),
=======
                      SizedBox(width: 10),
>>>>>>> 872b0d3858cb1905760691324c07d3eeedfacd56
                      _LegendIcon(path: 'assets/img/rvm.png', label: 'RVM'),
                      SizedBox(width: 10),
                      _LegendIcon(path: 'assets/img/food.png', label: 'أكل'),
                    ],
                  ),
                ),
              ),
            ],
          ),

          // === BottomNav ===
          bottomNavigationBar: isKeyboardOpen
              ? null
              : BottomNav(
                  currentIndex: 3,
                  onTap: (i) {
                    if (i == 3) return;
                    switch (i) {
                      case 0:
                        Navigator.of(context).pushAndRemoveUntil(
                          MaterialPageRoute(builder: (_) => const homePage()),
                          (route) => false,
                        );
                        break;
                      case 1:
                        Navigator.of(context).pushReplacement(
                          MaterialPageRoute(builder: (_) => const taskPage()),
                        );
                        break;
                      case 4:
                        Navigator.of(context).pushReplacement(
                          MaterialPageRoute(
                            builder: (_) => const communityPage(),
                          ),
                        );
                        break;
                      default:
                        break;
                    }
                  },
                  onCenterTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const levelsPage()),
                    );
                  },
                ),
        ),
      ),
    );
  }

  // ===== Filters (اختياري) =====
  void _showFiltersBottomSheet() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) {
        bool fClothes = true;
        bool fRvm = true;
        bool fPapers = true;
        bool fFood = true;

        return StatefulBuilder(
          builder: (context, setSt) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'فلاتر النقاط',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 12),
                  FilterChip(
                    label: const Text('حاوية إعادة تدوير الملابس'),
                    selected: fClothes,
                    onSelected: (v) => setSt(() => fClothes = v),
                  ),
                  const SizedBox(height: 6),
                  FilterChip(
                    label: const Text('حاوية إعادة تدوير الأوراق'),
                    selected: fPapers,
                    onSelected: (v) => setSt(() => fPapers = v),
                  ),
                  const SizedBox(height: 6),
                  FilterChip(
                    label: const Text('آلة استرجاع (RVM)'),
                    selected: fRvm,
                    onSelected: (v) => setSt(() => fRvm = v),
                  ),
                  const SizedBox(height: 6),
                  FilterChip(
                    label: const Text('حاوية إعادة تدوير بقايا الطعام'),
                    selected: fFood,
                    onSelected: (v) => setSt(() => fFood = v),
                  ),

                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () {
                        Navigator.pop(context);
                        final allowed = <String>{};
                        if (fClothes) allowed.add('حاوية إعادة تدوير الملابس');
                        if (fPapers) allowed.add('حاوية إعادة تدوير الأوراق');
                        if (fRvm) allowed.add('آلة استرجاع (RVM)');
                        if (fFood)
                          allowed.add('حاوية إعادة تدوير بقايا الطعام');

                        setState(() {
                          _markers
                            ..clear()
                            ..addAll(
                              _allMarkers.where((m) {
                                final t = m.infoWindow.title ?? '';
                                return allowed.isEmpty || allowed.contains(t);
                              }),
                            );
                        });

                        // بعد تطبيق الفلاتر: لو ما فيه نتائج وخلصنا التحميل، أظهري الرسالة مؤقتًا
                        if (_didInitialLoad &&
                            !_isLoadingFacilities &&
                            _markers.isEmpty) {
                          _flashEmptyMsg();
                        }
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                      ),
                      child: const Text('تطبيق'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

/* ======================= Widgets ======================= */

class _LegendIcon extends StatelessWidget {
  final String path;
  final String label;
  const _LegendIcon({required this.path, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Image.asset(path, width: 18, height: 18),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
      ],
    );
  }
}

class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onFilterTap;

  const _SearchBar({
    required this.controller,
    required this.onSubmitted,
    required this.onFilterTap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            elevation: 4,
            child: TextField(
              controller: controller,
              textInputAction: TextInputAction.search,
              onSubmitted: onSubmitted,
              decoration: const InputDecoration(
                hintText: 'ابحث عن أقرب حاوية/نقطة تدوير...',
                prefixIcon: Icon(Icons.search),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        InkWell(
          onTap: onFilterTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x14000000),
                  blurRadius: 12,
                  offset: Offset(0, 6),
                ),
              ],
            ),
            child: const Icon(Icons.tune, color: AppColors.dark),
          ),
        ),
      ],
    );
  }
}

class _RoundBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool isLoading;

  const _RoundBtn({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkResponse(
        onTap: isLoading ? null : onTap,
        radius: 32,
        child: Container(
          width: 48,
          height: 48,
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Color(0x22000000),
                blurRadius: 12,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: isLoading
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(icon, color: AppColors.dark),
        ),
      ),
    );
  }
}

/* ======================= BottomNav (نسخة مضمنة) ======================= */

class NavItem {
  final IconData outlined;
  final IconData filled;
  final String label;
  final bool isCenter;
  const NavItem({
    required this.outlined,
    required this.filled,
    required this.label,
    this.isCenter = false,
  });
}

class BottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final VoidCallback onCenterTap;

  const BottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.onCenterTap,
  });

  @override
  Widget build(BuildContext context) {
    const items = [
      NavItem(
        outlined: Icons.home_outlined,
        filled: Icons.home,
        label: 'الرئيسية',
      ),
      NavItem(
        outlined: Icons.fact_check_outlined,
        filled: Icons.fact_check,
        label: 'مهامي',
      ),
      NavItem(
        outlined: Icons.flag_outlined,
        filled: Icons.flag,
        label: 'المراحل',
        isCenter: true,
      ),
      NavItem(
        outlined: Icons.map_outlined,
        filled: Icons.map,
        label: 'الخريطة',
      ),
      NavItem(
        outlined: Icons.group_outlined,
        filled: Icons.group,
        label: 'الأصدقاء',
      ),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: Container(
          height: 70,
          color: Colors.white,
          child: Row(
            children: List.generate(items.length, (i) {
              final it = items[i];
              final selected = i == currentIndex;

              if (it.isCenter) {
                return Expanded(
                  child: Center(
                    child: InkResponse(
                      onTap: onCenterTap,
                      radius: 40,
                      child: Container(
                        width: 58,
                        height: 58,
                        decoration: const BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.flag_outlined,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                    ),
                  ),
                );
              }

              final iconData = selected ? it.filled : it.outlined;
              final color = selected ? AppColors.primary : Colors.black54;

              return Expanded(
                child: InkWell(
                  onTap: () => onTap(i),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(iconData, color: color, size: 26),
                      const SizedBox(height: 2),
                      Text(
                        it.label,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: selected
                              ? FontWeight.w800
                              : FontWeight.w500,
                          color: color,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

/// =================== الهيدر الجديد ببيانات المستخدم (قابل للنقر) ===================
class _HeaderUser extends StatelessWidget {
  final String name;
  final int points;
  final String? avatarPath; // Asset path (اختياري): مثال assets/pfp/pfp1.png
  final VoidCallback? onTap; // لو حاب تمرّر أكشن مخصص

  const _HeaderUser({
    required this.name,
    required this.points,
    this.avatarPath,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final card = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 16,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          // أفاتار
          Material(
            color: Colors.transparent,
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    AppColors.primary.withOpacity(.2),
                    AppColors.sea.withOpacity(.1),
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withOpacity(.2),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: CircleAvatar(
                radius: 18,
                backgroundColor: Colors.transparent,
                backgroundImage: (avatarPath != null && avatarPath!.isNotEmpty)
                    ? AssetImage(avatarPath!)
                    : null,
                child: (avatarPath == null || avatarPath!.isEmpty)
                    ? const Icon(
                        Icons.person_outline,
                        color: AppColors.primary,
                        size: 22,
                      )
                    : null,
              ),
            ),
          ),
          const SizedBox(width: 8),

          // الترحيب بالاسم
          Expanded(
            child: Text(
              'مرحبًا، $name',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),

          // شارة النقاط
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.primary, AppColors.primary, AppColors.mint],
                stops: [0.0, 0.5, 1.0],
                begin: Alignment.bottomLeft,
                end: Alignment.topRight,
              ),
              borderRadius: BorderRadius.circular(100),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withOpacity(.35),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.stars_rounded, color: Colors.white, size: 18),
                const SizedBox(width: 6),
                Text(
                  '$points',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(width: 4),
                const Text(
                  'نقطة',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    // 👇 نفس فكرة التنقل: البطاقة كلها قابلة للنقر وتفتح صفحة البروفايل
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap:
          onTap ??
          () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const profilePage()),
            );
          },
      child: card,
    );
  }
}

/// ===== نسخة Live: تجيب الاسم + النقاط + الأفاتار من Firestore وتستعمل _HeaderUser =====
class HeaderUserLiveWithPoints extends StatelessWidget {
  final VoidCallback? onTap;

  const HeaderUserLiveWithPoints({super.key, this.onTap});

  String _extractName(Map<String, dynamic> data, User? user) {
    return (data['displayName'] ??
            data['fullName'] ??
            data['name'] ??
            data['username'] ??
            user?.displayName ??
            user?.email ??
            'مسؤول')
        .toString();
  }

  int _extractPoints(Map<String, dynamic> data) {
    final p = data['points'] ?? data['score'] ?? 0;
    if (p is int) return p;
    return int.tryParse(p.toString()) ?? 0;
  }

  /// يختار صورة الأفاتار من pfpIndex (0..7) -> assets/pfp/pfp{index+1}.png
  String? _extractAvatarAsset(Map<String, dynamic> data) {
    final raw = data['pfpIndex'];
    int? idx;
    if (raw is int) {
      idx = raw;
    } else if (raw != null) {
      idx = int.tryParse(raw.toString());
    }
    if (idx != null && idx >= 0 && idx < 8) {
      return 'assets/pfp/pfp${idx + 1}.png';
    }
    // لو عندك حقل جاهز لمسار الأصول (avatarPath) استخدمه:
    final asset = data['avatarPath']?.toString();
    if (asset != null && asset.trim().isNotEmpty) return asset.trim();

    return null; // سيظهر أيقونة افتراضية
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return _HeaderUser(
        name: 'مسؤول',
        points: 0,
        avatarPath: null,
        onTap:
            onTap ??
            () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const profilePage()),
              );
            },
      );
    }

    final docRef = FirebaseFirestore.instance.collection('users').doc(user.uid);

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: docRef.snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return _HeaderUser(
            name: '...',
            points: 0,
            avatarPath: null,
            onTap:
                onTap ??
                () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const profilePage()),
                  );
                },
          );
        }

        final data = snap.data?.data() ?? {};
        final name = _extractName(data, user);
        final points = _extractPoints(data);
        final avatarPath = _extractAvatarAsset(data);

        return _HeaderUser(
          name: name,
          points: points,
          avatarPath: avatarPath,
          onTap:
              onTap ??
              () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const profilePage()),
                );
              },
        );
      },
    );
  }
}
