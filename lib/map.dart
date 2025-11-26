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
import 'dart:convert';
import 'package:http/http.dart' as http;

// صفحات أخرى
import 'home.dart';
import 'task.dart';
import 'community.dart';
import 'levels.dart';
import 'profile.dart';
import 'services/bottom_nav.dart';
import 'services/connection.dart';
import 'package:Nameer/secret/api.dart';

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
  //final String city;
  final String address;
  final String status; // 'نشط' أو 'متوقف'

  Facility({
    required this.id,
    required this.lat,
    required this.lng,
    required this.type,
    required this.provider,
    //required this.city,
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
  final int _currentIndex = 3;

  void _onTap(int i) {
    if (i == _currentIndex) return;
    switch (i) {
      case 0:
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const homePage()),
        );
        break;
      case 1:
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const taskPage()),
        );
        break;
      case 2:
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const levelsPage()),
        );
        break;
      case 3:
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const mapPage()),
        );
        break;
      case 4:
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const communityPage()),
        );
        break;
    }
  }

  static const _riyadh = LatLng(24.7136, 46.6753);
  static const _initZoom = 12.5;
  static const double _nearbyKm = 7.0;

  final Set<Marker> _markers = {};
  final Set<Marker> _allMarkers = {};
  final Set<Polyline> _polylines = {};
  final Map<String, Facility> _facilitiesByMarkerId = {};
  Set<String> _allowedTypes = {}; // ✅ أنواع الحاويات المفعّلة في الفلتر

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
  bool _isLoadingFacilities = false;
  bool _didInitialLoad = false;
  bool _showEmptyOverlay = false;
  Timer? _emptyTimer;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _ensureLocationPermission();
    await _loadMarkerIcons();
    await _loadFacilitiesFromFirestore();

    // إن كانت صلاحية الموقع مفعّلة: تمركز
    if (mounted && _myLocationEnabled) {
      await _centerOnUserOnly();
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
    _iconClothes = await _bitmapFromAsset(
      'assets/img/clothPin.png',
      width: 100,
    );
    _iconPapers = await _bitmapFromAsset('assets/img/paperPin.png', width: 100);
    _iconRvm = await _bitmapFromAsset('assets/img/rvmPin.png', width: 100);
    _iconFood = await _bitmapFromAsset('assets/img/foodPin.png', width: 100);
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
    if (isRvm) return 'آلة إعادة التدوير (RVM)';
    if (isPapers) return 'حاوية إعادة تدوير الأوراق';
    if (isFood) return 'حاوية إعادة تدوير بقايا الطعام';

    // أنواع أخرى شائعة
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
      case 'آلة إعادة التدوير (RVM)':
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
    if (!await hasInternetConnection()) {
      if (context.mounted) showNoInternetDialog(context);
      return;
    }
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
        //final String city = (m['city'] ?? '').toString();
        final String address = (m['address'] ?? '').toString();

        final String status = (m['status'] ?? 'نشط').toString(); // 👈 الحالة

        final pos = LatLng(lat, lng);
        final markerId = MarkerId(d.id);

        final facility = Facility(
          id: d.id,
          lat: lat,
          lng: lng,
          type: type,
          provider: provider,
          //city: city,
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
                      //if (city.isNotEmpty) city,
                    ].join(' • '),
              onTap: () => _showFacilitySheet(facility),
            ),
            onTap: () => _showFacilitySheet(facility),
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

      // ✅ تطبيق الفلاتر الحالية بعد كل تحميل/تحديث
      _applyCurrentFilters();

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
          SnackBar(
            backgroundColor: Colors.redAccent,
            content: Text(
              'تعذّر تحميل نقاط الخريطة',
              style: GoogleFonts.ibmPlexSansArabic(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
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

      // إن كانت الصلاحية مفعلة ولم نتمركز تلقائياً بعد، نعمل تمركز فقط
      if (mounted && _myLocationEnabled && !_didAutoCenter) {
        await _centerOnUserOnly();
        _didAutoCenter = true;
      }
    }
  }

  // ===== فتح الاتجاهات في Google Maps =====
  Future<void> _openInMaps(Facility f) async {
    final googleMapsUri = Uri.parse(
      'comgooglemaps://?daddr=${f.lat},${f.lng}&directionsmode=driving',
    );
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

      final controller = await _mapCtrl.future;
      await controller.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: userLatLng, zoom: 15.5),
        ),
      );

      _filterMarkersByDistance(userLatLng, _nearbyKm);
    } catch (e) {
      debugPrint('❌ center/filter error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text(
            'تعذّر تحديد موقعك. تأكد من الإذن وGPS',
            style: GoogleFonts.ibmPlexSansArabic(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    }
  }

  Future<void> _centerOnUserOnly() async {
    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      final userLatLng = LatLng(pos.latitude, pos.longitude);
      final controller = await _mapCtrl.future;
      await controller.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: userLatLng, zoom: 15.5),
        ),
      );
    } catch (e) {
      debugPrint('❌ center-only error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text(
            'تعذّر تحديد موقعك. تأكد من الإذن وGPS',
            style: GoogleFonts.ibmPlexSansArabic(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'لا توجد نقاط قريبة ضمن النطاق — تم عرض جميع النقاط',
            style: GoogleFonts.ibmPlexSansArabic(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
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

      // لا نفلتر بالمسافة هنا حتى تظل كل الفاسيلتي ظاهرة
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.redAccent,
            content: Text(
              'تعذّر تحديد موقعك. تأكد من الإذن وGPS',
              style: GoogleFonts.ibmPlexSansArabic(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoadingLocation = false);
    }
  }

  Future<void> _onSearchSubmitted(String query) async {
    if (!await hasInternetConnection()) {
      if (context.mounted) showNoInternetDialog(context);
      return;
    }

    query = query.trim();
    if (query.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'يرجى إدخال نص البحث',
            style: GoogleFonts.ibmPlexSansArabic(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
      return;
    }

    // ===== توحيد / تنظيف النص =====
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

    // كلمات عامة جدًا (حاوية / حاويات / سلة..)
    final Set<String> genericQueryTokens = {
      normalizeArabic('حاوية'),
      normalizeArabic('حاويات'),
      normalizeArabic('سلة'),
      normalizeArabic('سله'),
      normalizeArabic('سلات'),
    };

    final bool isNearestSearch = query.contains('اقرب');
    final bool isAreaSearch = query.contains('حي') || query.contains('شارع');

    // 🧩 قاموس المترادفات لأنواع الحاويات
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

    String? searchCategory;
    for (final entry in synonyms.entries) {
      if (entry.value.any(
        (w) => normalizedQuery.contains(normalizeArabic(w)),
      )) {
        searchCategory = entry.key;
        break;
      }
    }

    // ✅ توكنز مفيدة بعد تنظيف الكلمات العامة (مثلاً: "حاوية مسك حي العليا" → ["مسك", "العليا"])
    final List<String> tokens = normalizedQuery
        .split(' ')
        .where((t) => t.isNotEmpty)
        .where((t) => !genericQueryTokens.contains(t))
        .toList();

    // ===== تجهيز معلومات الحي/المنطقة مرة وحدة =====
    final queryNorm = normalizeArabic(query);

    String? possibleArea;
    final areaMatchGlobal = RegExp(
      r'(?:حي|شارع|طريق)\s*([^\s]+)',
    ).firstMatch(query);
    if (areaMatchGlobal != null && areaMatchGlobal.groupCount >= 1) {
      possibleArea = normalizeArabic(areaMatchGlobal.group(1)!);
    } else {
      final words = queryNorm.split(' ');
      if (words.isNotEmpty) {
        possibleArea = words.last;
      }
    }

    final bool queryHasAreaWord =
        query.contains('حي') ||
        query.contains('شارع') ||
        query.contains('طريق');

    // 🔎 هل هذا "بحث حي فقط" (بدون مزوّد / نوع معيّن)؟
    // مثال: "حي اليرموك" أو "حاوية حي اليرموك"
    final bool isPureAreaOnlyQuery =
        queryHasAreaWord && searchCategory == null && tokens.length <= 1;

    // 🔎 حالة "منطقة ضمنياً" مثل: "حاوية مسك العليا" (ما فيها كلمة حي لكن فيها اسم حي واضح)
    final bool hasImplicitArea =
        !queryHasAreaWord &&
        possibleArea != null &&
        tokens.length >= 2 &&
        tokens.contains(possibleArea);

    // 🟡 لو كتب المستخدم "حاوية" أو "حاويات" فقط → نعرض كل النقاط مع zoom out
    if (genericQueryTokens.contains(normalizedQuery)) {
      if (_allMarkers.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'لا توجد حاويات متاحة حاليًا',
              style: GoogleFonts.ibmPlexSansArabic(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );
        return;
      }

      setState(() {
        _markers
          ..clear()
          ..addAll(_allMarkers);
      });

      // نحسب bounds لكل الماركرات ونسوي zoom out عليهم
      LatLngBounds? bounds;
      for (final m in _markers) {
        if (bounds == null) {
          bounds = LatLngBounds(southwest: m.position, northeast: m.position);
        } else {
          bounds = LatLngBounds(
            southwest: LatLng(
              m.position.latitude < bounds.southwest.latitude
                  ? m.position.latitude
                  : bounds.southwest.latitude,
              m.position.longitude < bounds.southwest.longitude
                  ? m.position.longitude
                  : bounds.southwest.longitude,
            ),
            northeast: LatLng(
              m.position.latitude > bounds.northeast.latitude
                  ? m.position.latitude
                  : bounds.northeast.latitude,
              m.position.longitude > bounds.northeast.longitude
                  ? m.position.longitude
                  : bounds.northeast.longitude,
            ),
          );
        }
      }

      if (bounds != null) {
        final ctrl = await _mapCtrl.future;
        await ctrl.animateCamera(CameraUpdate.newLatLngBounds(bounds, 80));
      }

      return;
    }

    // 📍 موقع المستخدم (أو افتراضي الرياض)
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

    final List<Map<String, dynamic>> matches = [];

    // ✅ توكنات المزوّد فقط (نستثني اسم الحي إذا كان ضمن التوكنز)
    List<String> providerTokensMain = tokens;
    if ((queryHasAreaWord || hasImplicitArea) &&
        possibleArea != null &&
        tokens.length >= 2) {
      providerTokensMain = tokens.where((t) => t != possibleArea).toList();
    }
    if (isPureAreaOnlyQuery && searchCategory == null) {
      providerTokensMain = [];
    }

    final bool hasAnyAreaConstraint = queryHasAreaWord || hasImplicitArea;

    for (final f in _facilitiesByMarkerId.values) {
      final combined = normalizeArabic('${f.type} ${f.address} ${f.provider}');

      // ===== 1) تطابق بالنص (نوع / مزوّد / ... ) =====
      bool baseMatch = false;

      if (searchCategory != null) {
        final keywords = synonyms[searchCategory]!
            .map(normalizeArabic)
            .toList();
        for (final k in keywords) {
          if (combined.contains(k)) {
            baseMatch = true;
            break;
          }
        }
      } else {
        if (providerTokensMain.isNotEmpty) {
          // يكفي أي كلمة من كلمات المزوّد
          baseMatch = providerTokensMain.any((t) => combined.contains(t));
        }
      }

      // ===== 2) تطابق الحي/الشارع =====
      final addressNorm = normalizeArabic(f.address);
      //final cityNorm = normalizeArabic(f.city);

      final bool areaMatchesThisFacility =
          possibleArea != null && (addressNorm.contains(possibleArea));

      // ===== 3) منطق الدمج =====
      bool isMatch = false;

      if (hasAnyAreaConstraint) {
        if (isPureAreaOnlyQuery && searchCategory == null) {
          // مثل: "حي اليرموك" أو "حاوية حي اليرموك" → نعتمد على الحي فقط
          isMatch = areaMatchesThisFacility;
        } else {
          // كل الحالات الأخرى اللي فيها مزوّد + حي (صريح أو ضمني)
          // مثل: "حاوية مسك حي العليا" أو "حاوية مسك العليا"
          isMatch = baseMatch && areaMatchesThisFacility;
        }
      } else {
        // ما فيه أي كلمة حي/شارع/طريق ولا implicit area → نكتفي بالمزوّد / النوع
        isMatch = baseMatch;
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

    // ✅ لو لقينا نتائج في Firestore → نعرضها ونوقف، ما نروح لـ Google Places
    if (matches.isNotEmpty) {
      List<Map<String, dynamic>> top = [];

      // هنا أضفنا isPureAreaOnlyQuery → نفس منطق "أقرب" أو نوع معيّن
      if (isNearestSearch || searchCategory != null || isPureAreaOnlyQuery) {
        matches.sort((a, b) => a['dist'].compareTo(b['dist']));
        top = matches.take(5).toList();
      } else {
        top = matches;
      }

      final nearest = top.first['facility'] as Facility;

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

      if (bounds != null) {
        await ctrl.animateCamera(CameraUpdate.newLatLngBounds(bounds, 100));
      }

      String message;
      final categoryText = searchCategory ?? 'نقطة استدامة';
      if (isNearestSearch || (!isAreaSearch && searchCategory != null)) {
        message = 'تم العثور على ${top.length} من $categoryText.';
      } else if (isAreaSearch || isPureAreaOnlyQuery || hasImplicitArea) {
        message = 'تم عرض أقرب ${top.length} من $categoryText في الحي المحدد.';
      } else {
        message = 'تم العثور على ${top.length} من نقاط الاستدامة.';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.primary,
          content: Text(
            message,
            style: GoogleFonts.ibmPlexSansArabic(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );

      if (isNearestSearch ||
          searchCategory != null ||
          isPureAreaOnlyQuery ||
          hasImplicitArea) {
        Future.delayed(const Duration(seconds: 1), () {
          _showFacilitySheet(nearest);
        });
      }

      return; // 🛑 مهم: لا نكمل لـ Google Places
    }

    // ===== Fallback: لو المستخدم كتب مزوّد + حي (صريح أو ضمني) وما لقينا أي نقطة تطابق الاثنين معاً =====
    if ((queryHasAreaWord || hasImplicitArea) &&
        tokens.isNotEmpty &&
        !isPureAreaOnlyQuery) {
      // نفصل توكنات المزوّد عن اسم الحي (لو قدرنا نعرفه)
      final providerTokens = (possibleArea == null)
          ? tokens
          : tokens.where((t) => t != possibleArea).toList();

      if (providerTokens.isNotEmpty) {
        final List<Map<String, dynamic>> providerMatches = [];

        for (final f in _facilitiesByMarkerId.values) {
          final combined = normalizeArabic(
            '${f.type} ${f.address} ${f.provider}',
          );

          final providerMatch = providerTokens.any((t) => combined.contains(t));

          if (providerMatch) {
            final dist = Geolocator.distanceBetween(
              pos.latitude,
              pos.longitude,
              f.lat,
              f.lng,
            );
            providerMatches.add({'facility': f, 'dist': dist});
          }
        }

        if (providerMatches.isNotEmpty) {
          providerMatches.sort((a, b) => a['dist'].compareTo(b['dist']));
          final top = providerMatches;
          final nearest = top.first['facility'] as Facility;

          setState(() {
            _markers
              ..clear()
              ..addAll(
                _allMarkers.where((m) {
                  return top.any(
                    (t) =>
                        (m.position.latitude ==
                            (t['facility'] as Facility).lat) &&
                        (m.position.longitude ==
                            (t['facility'] as Facility).lng),
                  );
                }),
              );
          });

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

          if (bounds != null) {
            await ctrl.animateCamera(CameraUpdate.newLatLngBounds(bounds, 100));
          }

          final rawProviderName = (nearest.provider).toString().trim();
          final displayProviderName = rawProviderName.isNotEmpty
              ? rawProviderName
              : providerTokens.join(' ');

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'لا توجد حاويات لـ "$displayProviderName" داخل الحي المحدد — تم عرض أقرب حاويات "$displayProviderName" لموقعك.',
                style: GoogleFonts.ibmPlexSansArabic(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          );

          return;
        }
      }
    }

    // ===== المرحلة 2 — إذا Firestore ما لقى شيء، نجرب نفهمه كموقع عبر Google Places =====
    final url = Uri.parse(
      "https://maps.googleapis.com/maps/api/place/autocomplete/json"
      "?input=$query&language=ar&components=country:sa&key=$kMapsApiKey",
    );

    final response = await http.get(url);
    final data = json.decode(response.body);

    if (data['status'] == "OK" && data['predictions'].isNotEmpty) {
      final placeId = data['predictions'][0]['place_id'];

      final detailsUrl = Uri.parse(
        "https://maps.googleapis.com/maps/api/place/details/json"
        "?place_id=$placeId&key=$kMapsApiKey",
      );

      final detailsRes = await http.get(detailsUrl);
      final detailsData = json.decode(detailsRes.body);

      final loc = detailsData['result']['geometry']['location'];
      final lat = (loc['lat'] as num).toDouble();
      final lng = (loc['lng'] as num).toDouble();

      final ctrl = await _mapCtrl.future;
      await ctrl.animateCamera(
        CameraUpdate.newLatLngZoom(LatLng(lat, lng), 15),
      );

      return;
    }

    // ولا Firestore ولا Google Places فهموا النص
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'لم يتم العثور على مواقع حاويات مطابقة لعبارة "$query".',
          style: GoogleFonts.ibmPlexSansArabic(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  // ===== Bottom sheet لتفاصيل الفاسيليتي =====
  void _showFacilitySheet(Facility f) {
    final bool isActive = (f.status == 'نشط');
    final String statusText = isActive ? 'نشطة' : 'متوقفة';
    final Color statusColor = isActive ? Colors.green : Colors.redAccent;

    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        f.type,
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.1),
                        border: Border.all(color: statusColor),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        statusText,
                        style: GoogleFonts.ibmPlexSansArabic(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: statusColor,
                        ),
                      ),
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
                    Expanded(
                      child: Text(
                        f.provider.isEmpty ? 'مزود غير محدد' : f.provider,
                        textAlign: TextAlign.right,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                if (f.address.isNotEmpty)
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
                        child: Text(f.address, textAlign: TextAlign.right),
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
                      textAlign: TextAlign.right,
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
          ),
        );
      },
    );
  }

  // ===== BottomSheet لإرسال بلاغ =====
  void _openReportDialog(Facility f) {
    final descCtrl = TextEditingController();
    String? selectedType;
    final _formKey = GlobalKey<FormState>();
    bool showValidation = false;

    final types = <String>[
      'الموقع غير دقيق',
      'الحاوية ممتلئة',
      'عطل/مكسورة',
      'غير نظيفة',
      'أخرى',
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSt) {
            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 8,
                bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 16,
              ),
              child: Directionality(
                textDirection: TextDirection.rtl,
                child: Form(
                  key: _formKey,
                  autovalidateMode: showValidation
                      ? AutovalidateMode.always
                      : AutovalidateMode.disabled,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 4),
                        const Text(
                          'إرسال بلاغ عن الحاويات',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 16),

                        // نوع البلاغ
                        DropdownButtonFormField<String>(
                          decoration: const InputDecoration(
                            labelText: 'نوع البلاغ',
                            alignLabelWithHint: true,
                            border: OutlineInputBorder(),
                          ),
                          isExpanded: true,
                          alignment: Alignment.centerRight,
                          icon: const Icon(Icons.arrow_drop_down),
                          items: types
                              .map(
                                (t) => DropdownMenuItem(
                                  value: t,
                                  child: Align(
                                    alignment: Alignment.centerRight,
                                    child: Text(t),
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (v) {
                            setSt(() => selectedType = v);
                          },
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) {
                              return 'اختر نوع البلاغ';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 10),

                        // وصف المشكلة
                        TextFormField(
                          controller: descCtrl,
                          maxLines: 3,
                          textAlign: TextAlign.right,
                          decoration: InputDecoration(
                            alignLabelWithHint: true,
                            border: const OutlineInputBorder(),
                            label: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text('وصف المشكلة'),
                                if (selectedType == 'أخرى')
                                  const Text(
                                    ' *',
                                    style: TextStyle(
                                      color: Colors.redAccent,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                              ],
                            ),
                            hintText: selectedType == 'أخرى'
                                ? 'يجب كتابة وصف عند اختيار "أخرى"'
                                : 'اكتب وصفًا مختصرًا للمشكلة (اختياري لباقي الأنواع)',
                          ),
                          validator: (v) {
                            if (selectedType == 'أخرى' &&
                                (v == null || v.trim().isEmpty)) {
                              return 'يرجى كتابة وصف للمشكلة';
                            }
                            return null;
                          },
                        ),

                        const SizedBox(height: 20),

                        Row(
                          children: [
                            Expanded(
                              child: TextButton(
                                onPressed: () => Navigator.pop(sheetContext),
                                child: const Text('إلغاء'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: FilledButton(
                                style: FilledButton.styleFrom(
                                  backgroundColor: AppColors.primary,
                                ),
                                onPressed: () async {
                                  setSt(() => showValidation = true);
                                  if (!_formKey.currentState!.validate()) {
                                    return;
                                  }

                                  Navigator.pop(sheetContext);
                                  await _submitFacilityReport(
                                    facility: f,
                                    type: selectedType!.trim(),
                                    description: descCtrl.text.trim(),
                                  );
                                },
                                child: const Text('إرسال'),
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
          },
        );
      },
    );
  }

  Future<void> _submitFacilityReport({
    required Facility facility,
    required String type,
    required String description,
  }) async {
    if (!await hasInternetConnection()) {
      if (context.mounted) showNoInternetDialog(context);
      return;
    }
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid ?? 'anonymous';
      await FirebaseFirestore.instance.collection('facilityReports').add({
        'decision': 'pending',
        'description': description,
        'type': type,
        'facilityID': facility.id,
        'reportedBy': uid,
        //'managedBy': '',
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) {
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
                      'شكرًا لك',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.ibmPlexSansArabic(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: AppColors.dark,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'تم استلام بلاغك بنجاح\nسيتم مراجعته وسنقوم بإشعارك عند معالجته',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.ibmPlexSansArabic(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: AppColors.dark,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Center(
                      child: SizedBox(
                        width: 140,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 10,
                            ),
                          ),
                          onPressed: () => Navigator.pop(context),
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
    } catch (e) {
      debugPrint('❌ report error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text(
            'تعذّر إرسال البلاغ، حاول لاحقًا',
            style: GoogleFonts.ibmPlexSansArabic(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
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
                    children: const [
                      _LegendIcon(
                        path: 'assets/img/clothPin.png',
                        label: 'ملابس',
                      ),
                      SizedBox(width: 8),
                      _LegendIcon(
                        path: 'assets/img/paperPin.png',
                        label: 'أوراق',
                      ),
                      SizedBox(width: 8),
                      _LegendIcon(
                        path: 'assets/img/rvmPin.png',
                        label: 'آلات إعادة التدوير (RVM)',
                      ),
                      SizedBox(width: 8),
                      _LegendIcon(
                        path: 'assets/img/foodPin.png',
                        label: 'طعام',
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          bottomNavigationBar: isKeyboardOpen
              ? null
              : BottomNavPage(currentIndex: _currentIndex, onTap: _onTap),
        ),
      ),
    );
  }

  // ===== فلاتر نوع الحاوية =====
  void _showFiltersBottomSheet() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) {
        // ننسخ الفلاتر الحالية إلى كائن محلي نلعب فيه
        final selectedTypes = Set<String>.from(_allowedTypes);

        const typeOptions = [
          'حاوية إعادة تدوير الملابس',
          'حاوية إعادة تدوير الأوراق',
          'آلة إعادة التدوير (RVM)',
          'حاوية إعادة تدوير بقايا الطعام',
        ];

        return StatefulBuilder(
          builder: (context, setSt) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'تصفية النقاط',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        'حسب نوع الحاوية',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppColors.dark,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: typeOptions.map((type) {
                        final selected = selectedTypes.contains(type);
                        return FilterChip(
                          label: Text(type),
                          selected: selected,
                          selectedColor: AppColors.primary.withOpacity(.15),
                          labelStyle: TextStyle(
                            color: selected
                                ? AppColors.primary
                                : AppColors.dark,
                            fontWeight: FontWeight.w700,
                          ),
                          onSelected: (v) => setSt(() {
                            if (v) {
                              selectedTypes.add(type);
                            } else {
                              selectedTypes.remove(type);
                            }
                          }),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 20),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                      ),
                      onPressed: () {
                        Navigator.pop(context);
                        setState(() {
                          _allowedTypes = selectedTypes;
                        });
                        _applyCurrentFilters();

                        if (_didInitialLoad &&
                            !_isLoadingFacilities &&
                            _markers.isEmpty) {
                          _flashEmptyMsg();
                        }
                      },
                      child: const Text('تطبيق'),
                    ),
                    TextButton(
                      onPressed: () {
                        Navigator.pop(context);
                        setState(() {
                          _allowedTypes.clear();
                        });
                        _applyCurrentFilters(); // يرجع يعرض كل النقاط
                      },
                      child: const Text('إلغاء الفلاتر'),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ✅ فلترة الماركرات حسب نوع الحاوية فقط
  void _applyCurrentFilters() {
    setState(() {
      if (_allowedTypes.isEmpty) {
        _markers
          ..clear()
          ..addAll(_allMarkers);
        return;
      }

      _markers
        ..clear()
        ..addAll(
          _allMarkers.where((m) {
            final fid = m.markerId.value;
            final facility = _facilitiesByMarkerId[fid];
            if (facility == null) return true; // احتياط
            return _allowedTypes.contains(facility.type);
          }),
        );
    });
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
        Text(
          label,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        ),
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

/// =================== الهيدر الجديد ببيانات المستخدم (قابل للنقر) ===================
class _HeaderUser extends StatelessWidget {
  final String name;
  final int points;
  final String? avatarPath;
  final VoidCallback? onTap;

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
          Expanded(
            child: Text(
              'مرحبًا، $name',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          InkWell(
            borderRadius: BorderRadius.circular(100),
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [
                    AppColors.primary,
                    AppColors.primary,
                    AppColors.mint,
                  ],
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
                  const Icon(
                    Icons.stars_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
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
          ),
        ],
      ),
    );

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
