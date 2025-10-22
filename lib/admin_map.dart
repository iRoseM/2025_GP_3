// lib/pages/admin_map.dart
import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:open_location_code/open_location_code.dart' as olc;
import 'package:firebase_auth/firebase_auth.dart';

// استيراد صفحات
import 'admin_home.dart' as home;
import 'admin_task.dart';
import 'admin_reward.dart' as reward;
import 'services/admin_bottom_nav.dart';
import 'admin_report.dart' as report;
import 'profile.dart';
import 'services/connection.dart';

class AdminMapPage extends StatefulWidget {
  const AdminMapPage({super.key});

  @override
  State<AdminMapPage> createState() => _AdminMapPageState();
}

class _AdminMapPageState extends State<AdminMapPage> {
  final Completer<GoogleMapController> _mapCtrl = Completer();
  final TextEditingController _searchCtrl = TextEditingController();

  static const _riyadh = LatLng(24.7136, 46.6753);
  static const _initZoom = 12.5;

  final Set<Marker> _markers = {};
  final Set<Marker> _allMarkers = {}; // نخزّن جميع الماركرات للفلترة
  final Set<Polyline> _polylines = {};
  final Map<String, String> _statusById = {}; // docId -> 'نشط'/'متوقف'
  Set<String> _allowedTypes = {}; // أنواع مختارة من شيت الفلاتر (فارغة=الكل)

  bool _myLocationEnabled = false;
  bool _isLoadingLocation = false;

  /// وضع تحديد موقع جديد من الخريطة
  bool _isSelecting = false;
  LatLng? _tempLocation;
  String? _lastAddedName;
  String? _lastAddedType;
  String? _lastProvider;
  String _lastStatusStr = 'نشط';

  // === أيقونات مخصّصة للماركرز
  BitmapDescriptor? _iconClothes;
  BitmapDescriptor? _iconPapers;
  BitmapDescriptor? _iconRvm;
  BitmapDescriptor? _iconFood;
  BitmapDescriptor? _iconDefault;

  @override
  void initState() {
    super.initState();
    _initAdminMap();
  }

  Future<void> _initAdminMap() async {
    if (!await hasInternetConnection()) {
      if (mounted) showNoInternetDialog(context);
      return;
    }
    await _ensureLocationPermission();
    await _loadMarkerIcons();
    await _loadFacilitiesFromFirestore();

    // 👇 بعد الإذن، تمركز تلقائي على موقع الأدمن
    if (mounted && _myLocationEnabled) {
      await _goToMyLocation();
    }
  }

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

  void _onTap(int i) {
    if (i == 1) return;
    switch (i) {
      case 0:
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => reward.AdminRewardsPage()),
        );
        break;
      case 2:
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const AdminTasksPage()),
        );
        break;
      case 3:
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => home.AdminHomePage()),
        );
        break;
    }
  }

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
        return _iconDefault ?? BitmapDescriptor.defaultMarker;
    }
  }

  Future<void> _ensureLocationPermission() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    final granted =
        permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
    if (mounted) setState(() => _myLocationEnabled = granted);
  }

  /// ✅ تحميل كل الفاسيلتيز من Firestore (بدون فلترة حالة)
  Future<void> _loadFacilitiesFromFirestore() async {
    if (!await hasInternetConnection()) {
      if (mounted) showNoInternetDialog(context);
      return;
    }
    try {
      final qs = await FirebaseFirestore.instance
          .collection('facilities')
          .get();

      final markers = <Marker>{};
      final statusMap = <String, String>{};
      LatLngBounds? bounds;

      for (final d in qs.docs) {
        final m = d.data();
        final double? lat = (m['lat'] as num?)?.toDouble();
        final double? lng = (m['lng'] as num?)?.toDouble();
        if (lat == null || lng == null) continue;

        final valid = lat > 20 && lat < 30 && lng > 40 && lng < 55;
        if (!valid) continue;

        final String type = _normalizeType((m['type'] ?? '').toString());
        final String provider = (m['provider'] ?? '').toString();
        final String name = (m['name'] ?? '').toString();
        final String city = (m['city'] ?? '').toString();
        final String address = (m['address'] ?? '').toString();
        final String status = (m['status'] ?? 'نشط').toString();

        statusMap[d.id] = status;
        final pos = LatLng(lat, lng);
        final title = (name.isNotEmpty) ? name : type;
        final snippetParts = <String>[
          type,
          if (provider.isNotEmpty) provider,
          if (city.isNotEmpty) city,
          if (address.isNotEmpty) address,
        ];
        final snippet = snippetParts.join(' • ');
        final markerId = MarkerId(d.id);

        final marker = Marker(
          markerId: markerId,
          position: pos,
          infoWindow: InfoWindow(
            title: title,
            snippet: snippet,
            onTap: () => _showMarkerSheet(markerId, pos),
          ),
          icon: _iconForType(type),
          consumeTapEvents: true,
          onTap: () => _showMarkerSheet(markerId, pos),
        );

        markers.add(marker);
        bounds = _extendBounds(bounds, pos);
      }

      if (!mounted) return;
      setState(() {
        _allMarkers
          ..clear()
          ..addAll(markers);
        _statusById
          ..clear()
          ..addAll(statusMap);
      });

      _applyCurrentFilters();

      if (bounds != null && markers.isNotEmpty) {
        final ctrl = await _mapCtrl.future;
        await ctrl.animateCamera(CameraUpdate.newLatLngBounds(bounds, 60));
      }

      debugPrint('✅ تم تحميل ${markers.length} موقع (نشط ومتوقف) من Firestore');
    } catch (e) {
      debugPrint('❌ خطأ أثناء تحميل الفاسيلتيز: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر تحميل المواقع من السحابة')),
        );
      }
    }
  }

  Future<void> _goToMyLocation() async {
    setState(() => _isLoadingLocation = true);
    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      final controller = await _mapCtrl.future;
      await controller.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: LatLng(pos.latitude, pos.longitude),
            zoom: 15.5,
          ),
        ),
      );
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

  /// ✅ لتوسيع حدود الكاميرا بحيث تشمل كل النقاط
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

  /// ✅ لما يضغط المستخدم على الخريطة (مثلاً أثناء تحديد موقع جديد)
  void _onMapTap(LatLng position) {
    if (_isSelecting) {
      setState(() => _tempLocation = position);
    }
  }

  void _onSearchSubmitted(String query) async {
    query = query.trim();
    if (query.isEmpty) {
      setState(() {
        _markers
          ..clear()
          ..addAll(_allMarkers);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم عرض جميع المواقع على الخريطة 📍'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // 🔤 تهيئة النص
    String normalize(String text) {
      return text
          .toLowerCase()
          .replaceAll(RegExp(r'[إأآا]'), 'ا')
          .replaceAll(RegExp(r'[ة]'), 'ه')
          .replaceAll(RegExp(r'[^\u0621-\u064Aa-z0-9 ]'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
    }

    final normalizedQuery = normalize(query);

    // 🔍 البحث في جميع الحقول (provider, address, city, type, name)
    final matchedMarkers = <Marker>{};

    for (final m in _allMarkers) {
      final textData =
          '''
      ${(m.infoWindow.title ?? '').toLowerCase()}
      ${(m.infoWindow.snippet ?? '').toLowerCase()}
    ''';

      final normalizedData = normalize(textData);

      if (normalizedData.contains(normalizedQuery)) {
        matchedMarkers.add(m);
        continue;
      }

      // 🔎 البحث بالكلمات الجزئية (يدعم المزود + الأحياء فقط)
      final queryParts = normalizedQuery.split(' ');
      for (int i = 0; i < queryParts.length; i++) {
        final part = queryParts[i];
        if (part.isEmpty) continue;

        // ✅ لو الكلمة "حي" نبحث باللي بعدها فقط
        if (part == 'حي') {
          if (i + 1 < queryParts.length) {
            final next = queryParts[i + 1];
            if (normalizedData.contains(next)) {
              matchedMarkers.add(m);
              break;
            }
          }
        }
        // ✅ أي كلمة عادية (مزود – مدينة – نوع)
        else if (normalizedData.contains(part)) {
          matchedMarkers.add(m);
          break;
        }
      }
    }

    // ✅ عرض النتائج
    if (matchedMarkers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('لم يتم العثور على نتائج لعبارة "$query".'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() {
      _markers
        ..clear()
        ..addAll(matchedMarkers);
    });

    // 🗺️ تقريب الكاميرا لتشمل النتائج
    final ctrl = await _mapCtrl.future;
    LatLngBounds? bounds;
    for (final m in matchedMarkers) {
      final p = m.position;
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

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'تم العثور على ${matchedMarkers.length} موقعًا مطابقًا ✅',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // باقي الدوال والـ UI

  @override
  Widget build(BuildContext context) {
    final bool isKeyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;
    final themeWithIbmPlex = Theme.of(context).copyWith(
      textTheme: GoogleFonts.ibmPlexSansArabicTextTheme(
        Theme.of(context).textTheme,
      ),
    );

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
                onTap: _onMapTap,
              ),

              // 🔍 شريط البحث
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // ⬅️ هذا هو الهيدر اللي يجيب الاسم/الصورة من Firestore
                      HeaderUserLive(
                        // onTap: () => Navigator.push(context,
                        //   MaterialPageRoute(builder: (_) => const profilePage())),
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

              // 🧭 أزرار جانبية
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

              // 📄 زر التقارير
              Positioned(
                left: 8,
                bottom: 140,
                child: _RoundBtn(
                  icon: Icons.article_rounded,
                  tooltip: 'عرض التقارير',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const report.AdminReportPage(),
                      ),
                    );
                  },
                ),
              ),

              // ➕ زر إضافة موقع جديد
              Positioned(
                left: 8,
                bottom: 80,
                child: _RoundBtn(
                  icon: Icons.add_location_alt_rounded,
                  tooltip: 'إضافة موقع جديد',
                  onTap: _onAddNewLocation,
                ),
              ),

              // 🎨 الـ Legend (اللي فيه الأيقونات)
              Positioned(
                left: 8,
                bottom: 30,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
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
                        path: 'assets/img/clothes.png',
                        label: 'ملابس',
                      ),
                      SizedBox(width: 10),
                      _LegendIcon(
                        path: 'assets/img/papers.png',
                        label: 'أوراق',
                      ),
                      SizedBox(width: 10),
                      _LegendIcon(path: 'assets/img/rvm.png', label: 'RVM'),
                      SizedBox(width: 10),
                      _LegendIcon(path: 'assets/img/food.png', label: 'أكل'),
                    ],
                  ),
                ),
              ),

              _buildConfirmButton(),
            ],
          ),
          bottomNavigationBar: isKeyboardOpen
              ? null
              : AdminBottomNav(currentIndex: 1, onTap: _onTap),
        ),
      ),
    );
  }

  // ===================== الفلاتر =====================
  void _showFiltersBottomSheet() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) {
        bool fClothes =
            _allowedTypes.isEmpty ||
            _allowedTypes.contains('حاوية إعادة تدوير الملابس');
        bool fRvm =
            _allowedTypes.isEmpty ||
            _allowedTypes.contains('آلة استرجاع (RVM)');
        bool fPapers =
            _allowedTypes.isEmpty ||
            _allowedTypes.contains('حاوية إعادة تدوير الأوراق');
        bool fFood =
            _allowedTypes.isEmpty ||
            _allowedTypes.contains('حاوية إعادة تدوير بقايا الطعام');

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
                        setState(() => _allowedTypes = allowed);
                        _applyCurrentFilters();
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: home.AppColors.primary,
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

  // ✅ فلترة الماركرات حسب الأنواع
  void _applyCurrentFilters() {
    setState(() {
      _markers
        ..clear()
        ..addAll(
          _allMarkers.where((m) {
            final typeInSnippet = (m.infoWindow.snippet ?? '');
            if (_allowedTypes.isEmpty) return true;
            return _allowedTypes.any(
              (t) =>
                  typeInSnippet.contains(t) ||
                  (m.infoWindow.title ?? '').contains(t),
            );
          }),
        );
    });
  }

  // ✅ إضافة موقع جديد يدوي أو بالموقع الحالي
  void _onAddNewLocation() {
    bool showCoords = false;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        final TextEditingController nameCtrl = TextEditingController();
        final TextEditingController providerCtrl = TextEditingController();
        final TextEditingController latCtrl = TextEditingController();
        final TextEditingController lngCtrl = TextEditingController();
        String selectedType = 'حاوية إعادة تدوير القوارير';
        bool isActive = true;

        return StatefulBuilder(
          builder: (context, setSt) {
            return Dialog(
              insetPadding: const EdgeInsets.fromLTRB(24, 60, 24, 100),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ===== العنوان =====
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'إضافة موقع استدامة جديد',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.grey),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ],
                      ),
                      const Divider(height: 10),
                      const SizedBox(height: 10),

                      // ===== اسم الموقع =====
                      const Text(
                        'اسم الموقع',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: nameCtrl,
                        textAlign: TextAlign.right,
                        decoration: _inputDeco('مثال: حي النخيل'),
                      ),
                      const SizedBox(height: 14),

                      // ===== نوع الحاوية =====
                      const Text(
                        'نوع الحاوية',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: home.AppColors.primary),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: selectedType,
                            isExpanded: true,
                            alignment: Alignment.centerRight,
                            items: const [
                              DropdownMenuItem(
                                value: 'حاوية إعادة تدوير القوارير',
                                child: Text('حاوية إعادة تدوير القوارير'),
                              ),
                              DropdownMenuItem(
                                value: 'حاوية إعادة تدوير الملابس',
                                child: Text('حاوية إعادة تدوير الملابس'),
                              ),
                              DropdownMenuItem(
                                value: 'حاوية إعادة تدوير بقايا الطعام',
                                child: Text('حاوية إعادة تدوير بقايا الطعام'),
                              ),
                              DropdownMenuItem(
                                value: 'حاوية إعادة تدوير الأوراق',
                                child: Text('حاوية إعادة تدوير الأوراق'),
                              ),
                              DropdownMenuItem(
                                value: 'آلة استرجاع (RVM)',
                                child: Text('آلة استرجاع (RVM)'),
                              ),
                            ],
                            onChanged: (val) {
                              if (val != null) setSt(() => selectedType = val);
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),

                      // ===== المزود =====
                      const Text(
                        'مقدم الخدمة',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: providerCtrl,
                        textAlign: TextAlign.right,
                        decoration: _inputDeco('مثال: Sparklo / البلدية / KSU'),
                      ),
                      const SizedBox(height: 10),

                      SwitchListTile(
                        title: const Text('الحالة: نشطة'),
                        value: isActive,
                        onChanged: (v) => setSt(() => isActive = v),
                        contentPadding: EdgeInsets.zero,
                      ),

                      const SizedBox(height: 10),
                      const Text(
                        'طريقة تحديد الموقع:',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 10),

                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              icon: const Icon(
                                Icons.edit_location_alt_outlined,
                              ),
                              label: const Text('إدخال بالإحداثيات'),
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.orange,
                              ),
                              onPressed: () => setSt(() => showCoords = true),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: FilledButton.icon(
                              icon: const Icon(Icons.my_location),
                              label: const Text('استخدام موقعي الحالي'),
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.teal,
                              ),
                              onPressed: () async {
                                if (!await hasInternetConnection()) {
                                  if (context.mounted)
                                    showNoInternetDialog(context);
                                  return;
                                }
                                if (nameCtrl.text.trim().isEmpty ||
                                    providerCtrl.text.trim().isEmpty) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        '⚠️ يرجى تعبئة جميع الحقول قبل الإضافة',
                                      ),
                                    ),
                                  );
                                  return;
                                }
                                try {
                                  final pos =
                                      await Geolocator.getCurrentPosition(
                                        desiredAccuracy: LocationAccuracy.high,
                                      );
                                  await _addMarkerToMapAndSave(
                                    LatLng(pos.latitude, pos.longitude),
                                    nameCtrl.text,
                                    selectedType,
                                    provider: providerCtrl.text,
                                    statusStr: isActive ? 'نشط' : 'متوقف',
                                  );
                                  if (mounted) Navigator.pop(context);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'تمت إضافة الموقع من موقعك الحالي ✅',
                                      ),
                                    ),
                                  );
                                } catch (e) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'تعذّر تحديد موقعك. تأكد من الإذن وGPS',
                                      ),
                                    ),
                                  );
                                }
                              },
                            ),
                          ),
                        ],
                      ),

                      if (showCoords) ...[
                        const SizedBox(height: 20),
                        const Text(
                          'إحداثيات الموقع',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: latCtrl,
                                keyboardType: TextInputType.number,
                                decoration: _inputDeco('Latitude'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: lngCtrl,
                                keyboardType: TextInputType.number,
                                decoration: _inputDeco('Longitude'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        FilledButton.icon(
                          icon: const Icon(Icons.check),
                          label: const Text('تأكيد الإحداثيات'),
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.orange,
                          ),
                          onPressed: () async {
                            if (!await hasInternetConnection()) {
                              if (context.mounted)
                                showNoInternetDialog(context);
                              return;
                            }
                            if (nameCtrl.text.trim().isEmpty ||
                                providerCtrl.text.trim().isEmpty ||
                                latCtrl.text.trim().isEmpty ||
                                lngCtrl.text.trim().isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    '⚠️ يرجى تعبئة جميع الحقول قبل التأكيد',
                                  ),
                                ),
                              );
                              return;
                            }
                            final lat = double.tryParse(latCtrl.text.trim());
                            final lng = double.tryParse(lngCtrl.text.trim());
                            if (lat == null ||
                                lng == null ||
                                lat < -90 ||
                                lat > 90 ||
                                lng < -180 ||
                                lng > 180) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('⚠️ الإحداثيات غير صحيحة'),
                                ),
                              );
                              return;
                            }
                            final pos = LatLng(lat, lng);
                            await _addMarkerToMapAndSave(
                              pos,
                              nameCtrl.text,
                              selectedType,
                              provider: providerCtrl.text,
                              statusStr: isActive ? 'نشط' : 'متوقف',
                            );
                            if (mounted) Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('تمت إضافة الموقع بنجاح ✅'),
                              ),
                            );
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ✅ تصميم الحقول الموحدة
  InputDecoration _inputDeco(String hint) {
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: home.AppColors.primary),
      ),
    );
  }

  // ✅ تأكيد الموقع بعد الاختيار على الخريطة
  Widget _buildConfirmButton() {
    if (_isSelecting) {
      final bool isNameValid = _lastAddedName?.trim().isNotEmpty ?? false;
      final bool isTypeValid = _lastAddedType?.trim().isNotEmpty ?? false;
      final bool isLocationSelected = _tempLocation != null;
      final bool isReady = isNameValid && isTypeValid && isLocationSelected;

      return Positioned(
        bottom: 40,
        left: 20,
        right: 20,
        child: FilledButton.icon(
          icon: const Icon(Icons.check),
          label: const Text('تأكيد الموقع'),
          onPressed: isReady
              ? () async {
                  await _addMarkerToMapAndSave(
                    _tempLocation!,
                    _lastAddedName!,
                    _lastAddedType!,
                    provider: _lastProvider ?? 'غير محدد',
                    statusStr: _lastStatusStr,
                  );
                  setState(() {
                    _isSelecting = false;
                    _tempLocation = null;
                  });
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('تمت إضافة "${_lastAddedName!}" بنجاح ✅'),
                    ),
                  );
                }
              : () {
                  String msg = 'رجاءً أكمل البيانات التالية:\n';
                  if (!isNameValid) msg += '• اسم الموقع 🏷️\n';
                  if (!isTypeValid) msg += '• نوع الحاوية ♻️\n';
                  if (!isLocationSelected)
                    msg += '• تحديد الموقع على الخريطة 📍';
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text(msg)));
                },
          style: FilledButton.styleFrom(
            backgroundColor: isReady ? Colors.teal : Colors.grey,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  /// ✅ ورقة تفاصيل + أزرار تعديل/حذف — تعرض الحالة بوضوح
  void _showMarkerSheet(MarkerId markerId, LatLng position) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          future: FirebaseFirestore.instance
              .collection('facilities')
              .doc(markerId.value)
              .get(),
          builder: (context, snap) {
            if (!snap.hasData) {
              return const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              );
            }

            final data = snap.data!.data() ?? {};
            final name = (data['name'] ?? '').toString();
            final type = _normalizeType((data['type'] ?? '').toString());
            final provider = (data['provider'] ?? '').toString();
            final city = (data['city'] ?? '').toString();
            final address = (data['address'] ?? '').toString();
            final statusStr =
                (data['status'] ?? _statusById[markerId.value] ?? 'نشط')
                    .toString();
            final isActive = statusStr == 'نشط';

            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          name.isNotEmpty ? name : type,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Chip(
                        label: Text(
                          isActive ? 'نشط' : 'متوقف',
                          style: const TextStyle(color: Colors.white),
                        ),
                        backgroundColor: isActive
                            ? Colors.teal
                            : Colors.redAccent,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(type, style: const TextStyle(color: Colors.grey)),
                  const SizedBox(height: 10),
                  if (provider.isNotEmpty) _kv('المزوّد', provider),
                  if (city.isNotEmpty) _kv('المدينة', city),
                  if (address.isNotEmpty) _kv('العنوان', address),
                  const Divider(height: 24),
                  ListTile(
                    leading: const Icon(Icons.edit, color: Colors.teal),
                    title: const Text('تعديل الموقع'),
                    onTap: () {
                      Navigator.pop(context);
                      _editMarker(
                        markerId,
                        name.isNotEmpty ? name : type,
                        type,
                        position,
                      );
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.delete, color: Colors.red),
                    title: const Text('حذف الموقع'),
                    onTap: () {
                      Navigator.pop(context);
                      _confirmDelete(markerId, name.isNotEmpty ? name : type);
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Text(k, style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          Expanded(child: Text(v, textAlign: TextAlign.right)),
        ],
      ),
    );
  }

  void _editMarker(
    MarkerId markerId,
    String oldNameOrType,
    String oldType,
    LatLng position,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) {
        return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          future: FirebaseFirestore.instance
              .collection('facilities')
              .doc(markerId.value)
              .get(),
          builder: (context, snap) {
            if (!snap.hasData) {
              return const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              );
            }

            final data = snap.data!.data() ?? {};
            final TextEditingController nameCtrl = TextEditingController(
              text: (data['name'] ?? '').toString(),
            );
            String selectedType = _normalizeType(
              (data['type'] ?? oldType).toString(),
            );
            final TextEditingController providerCtrl = TextEditingController(
              text: (data['provider'] ?? '').toString(),
            );
            bool isActive = ((data['status'] ?? 'نشط') == 'نشط');

            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 12,
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Center(
                    child: Text(
                      'تعديل بيانات الموقع',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'اسم الموقع',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: nameCtrl,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: Colors.black12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'نوع الحاوية',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    value: selectedType,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: Colors.black12),
                      ),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'حاوية إعادة تدوير القوارير',
                        child: Text('حاوية إعادة تدوير القوارير'),
                      ),
                      DropdownMenuItem(
                        value: 'حاوية إعادة تدوير الملابس',
                        child: Text('حاوية إعادة تدوير الملابس'),
                      ),
                      DropdownMenuItem(
                        value: 'حاوية إعادة تدوير بقايا الطعام',
                        child: Text('حاوية إعادة تدوير بقايا الطعام'),
                      ),
                      DropdownMenuItem(
                        value: 'حاوية إعادة تدوير الأوراق',
                        child: Text('حاوية إعادة تدوير الأوراق'),
                      ),
                      DropdownMenuItem(
                        value: 'آلة استرجاع (RVM)',
                        child: Text('آلة استرجاع (RVM)'),
                      ),
                    ],
                    onChanged: (val) => selectedType = val ?? selectedType,
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'مقدم الخدمة',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: providerCtrl,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: Colors.black12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  SwitchListTile(
                    title: const Text('الحالة: نشطة'),
                    value: isActive,
                    onChanged: (v) => isActive = v,
                    contentPadding: EdgeInsets.zero,
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.teal,
                      ),
                      onPressed: () async {
                        if (!await hasInternetConnection()) {
                          if (context.mounted) showNoInternetDialog(context);
                          return;
                        }
                        if (nameCtrl.text.trim().isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('يرجى إدخال اسم الموقع'),
                            ),
                          );
                          return;
                        }
                        try {
                          final statusStr = isActive ? 'نشط' : 'متوقف';
                          await FirebaseFirestore.instance
                              .collection('facilities')
                              .doc(markerId.value)
                              .set({
                                'name': nameCtrl.text.trim(),
                                'type': _normalizeType(selectedType),
                                'lat': position.latitude,
                                'lng': position.longitude,
                                'provider': providerCtrl.text.trim().isEmpty
                                    ? 'غير محدد'
                                    : providerCtrl.text.trim(),
                                'status': statusStr,
                                'updatedAt': FieldValue.serverTimestamp(),
                              }, SetOptions(merge: true));

                          setState(() {
                            _statusById[markerId.value] = statusStr;
                            _markers.removeWhere((m) => m.markerId == markerId);
                            final normalized = _normalizeType(selectedType);
                            final marker = Marker(
                              markerId: markerId,
                              position: position,
                              infoWindow: InfoWindow(
                                title: nameCtrl.text.trim().isNotEmpty
                                    ? nameCtrl.text.trim()
                                    : normalized,
                                snippet:
                                    '$normalized${providerCtrl.text.trim().isNotEmpty ? ' • ${providerCtrl.text.trim()}' : ''}',
                                onTap: () =>
                                    _showMarkerSheet(markerId, position),
                              ),
                              icon: _iconForType(normalized),
                              consumeTapEvents: true,
                              onTap: () => _showMarkerSheet(markerId, position),
                            );
                            _allMarkers.removeWhere(
                              (m) => m.markerId == markerId,
                            );
                            _allMarkers.add(marker);
                          });
                          _applyCurrentFilters();
                          if (mounted) Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('تم تحديث الموقع بنجاح ✅'),
                            ),
                          );
                        } catch (e) {
                          debugPrint('❌ تحديث Firestore فشل: $e');
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('فشل تحديث السحابة')),
                          );
                        }
                      },
                      child: const Text('حفظ التعديلات'),
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

  void _confirmDelete(MarkerId markerId, String name) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: Text('هل أنت متأكد من حذف "$name"؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () async {
              if (!await hasInternetConnection()) {
                if (context.mounted) showNoInternetDialog(context);
                return;
              }
              try {
                await FirebaseFirestore.instance
                    .collection('facilities')
                    .doc(markerId.value)
                    .delete();
                setState(() {
                  _statusById.remove(markerId.value);
                  _markers.removeWhere((m) => m.markerId == markerId);
                  _allMarkers.removeWhere((m) => m.markerId == markerId);
                });
                if (mounted) Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('تم حذف الموقع بنجاح ✅')),
                );
              } catch (e) {
                debugPrint('❌ حذف Firestore فشل: $e');
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('فشل حذف السحابة')),
                );
              }
            },
            child: const Text('حذف', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  /// ✅ إضافة ماركر + حفظه في Firestore
  Future<void> _addMarkerToMapAndSave(
    LatLng pos,
    String name,
    String type, {
    String provider = 'غير محدد',
    String statusStr = 'نشط',
  }) async {
    try {
      final normalizedType = _normalizeType(type);
      final docRef = FirebaseFirestore.instance.collection('facilities').doc();
      await docRef.set({
        'name': name.isEmpty ? 'موقع جديد' : name.trim(),
        'type': normalizedType,
        'lat': pos.latitude,
        'lng': pos.longitude,
        'city': 'الرياض',
        'provider': provider.trim().isEmpty ? 'غير محدد' : provider.trim(),
        'status': statusStr,
        'createdAt': FieldValue.serverTimestamp(),
      });

      setState(() {
        _statusById[docRef.id] = statusStr;
        final markerId = MarkerId(docRef.id);
        final marker = Marker(
          markerId: markerId,
          position: pos,
          infoWindow: InfoWindow(
            title: name.trim().isNotEmpty ? name.trim() : normalizedType,
            snippet:
                '$normalizedType${provider.trim().isNotEmpty ? ' • ${provider.trim()}' : ''}',
            onTap: () => _showMarkerSheet(markerId, pos),
          ),
          icon: _iconForType(normalizedType),
          consumeTapEvents: true,
          onTap: () => _showMarkerSheet(markerId, pos),
        );
        _allMarkers.add(marker);
      });

      _applyCurrentFilters();
      debugPrint('✅ تم حفظ الفاسيلتي في Firestore وإظهارها على الخريطة');
    } catch (e) {
      debugPrint('❌ خطأ في الحفظ: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('حدث خطأ أثناء حفظ البيانات')),
      );
    }
  }
}
/* ===== Widgets صغيرة ===== */

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
                hintText: 'ابحث عن أقرب حاوية/ نقطة تدوير...',
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
            child: const Icon(Icons.tune, color: home.AppColors.dark),
          ),
        ),
      ],
    );
  }
}

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
              : Icon(icon, color: home.AppColors.dark),
        ),
      ),
    );
  }
}

// ================== الهيدر الجديد ببيانات المستخدم ===================
// ✅ يبني ImageProvider من الداتابيس (avatarUrl أو pfpIndex) + كليك يفتح البروفايل
class _HeaderUser extends StatelessWidget {
  final String name;
  final ImageProvider<Object>? avatarImage; // بدل avatarUrl نصيًا
  final VoidCallback? onTap;

  const _HeaderUser({required this.name, this.avatarImage, this.onTap});

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
                    home.AppColors.primary.withOpacity(.2),
                    home.AppColors.primary.withOpacity(.08),
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: home.AppColors.primary.withOpacity(.18),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: CircleAvatar(
                radius: 18,
                backgroundColor: Colors.transparent,
                backgroundImage: avatarImage,
                child: (avatarImage == null)
                    ? const Icon(
                        Icons.person_outline,
                        color: home.AppColors.primary,
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
        ],
      ),
    );

    // 👇 البطاقة قابلة للنقر دائمًا -> تفتح صفحة البروفايل
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

/// ===== نسخة "لايف" تقرأ من Firestore وتبني ImageProvider تلقائيًا =====
class HeaderUserLive extends StatelessWidget {
  final VoidCallback? onTap;

  const HeaderUserLive({super.key, this.onTap});

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

  ImageProvider<Object>? _buildAvatarProvider(
    Map<String, dynamic> data,
    User? user,
  ) {
    // 1) جرّب روابط الشبكة (حقول محتملة)
    final candidates =
        <String?>[
              data['avatarUrl']?.toString(),
              data['photoURL']?.toString(),
              data['photoUrl']?.toString(),
              data['imageUrl']?.toString(),
              data['profileImage']?.toString(),
              data['picture']?.toString(),
              user?.photoURL,
            ]
            .where((s) => s != null && s!.trim().isNotEmpty)
            .map((s) => s!.trim())
            .toList();

    for (final url in candidates) {
      // NetworkImage يدعم http/https فقط
      if (url.startsWith('http://') || url.startsWith('https://')) {
        return NetworkImage(url);
      }
    }

    // 2) Fallback إلى pfpIndex -> assets/pfp/pfp{index+1}.png (0..7)
    final raw = data['pfpIndex'];
    int? idx;
    if (raw is int) {
      idx = raw;
    } else if (raw != null) {
      idx = int.tryParse(raw.toString());
    }
    if (idx != null && idx >= 0 && idx < 8) {
      return AssetImage('assets/pfp/pfp${idx + 1}.png');
    }

    // 3) لا شي — نرجّع null عشان تظهر الأيقونة الافتراضية
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return _HeaderUser(
        name: 'مسؤول',
        avatarImage: null,
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
            avatarImage: null,
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
        final avatarImage = _buildAvatarProvider(data, user);

        return _HeaderUser(
          name: name,
          avatarImage: avatarImage,
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
