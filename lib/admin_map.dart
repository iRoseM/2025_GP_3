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
import 'admin_reports.dart' as report;
import 'profile.dart';
import 'services/connection.dart';

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
  final Set<Marker> _allMarkers = {};
  final Set<Polyline> _polylines = {};
  final Map<String, String> _statusById = {};
  Set<String> _allowedTypes = {};

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

  // === حالة التحميل/الرسالة المؤقتة ===
  bool _isLoadingFacilities = false;
  bool _didInitialLoad = false;
  bool _showEmptyOverlay = false;
  Timer? _emptyTimer;

  @override
  void initState() {
    super.initState();
    _initAdminMap();
  }

  @override
  void dispose() {
    _emptyTimer?.cancel();
    super.dispose();
  }

  Future<void> _initAdminMap() async {
    if (!await hasInternetConnection()) {
      if (mounted) showNoInternetDialog(context);
      return;
    }
    await _ensureLocationPermission();
    await _loadMarkerIcons();
    await _loadFacilitiesFromFirestore();
  }

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
    final lower = t.toLowerCase();
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
    if (lower.contains('قوارير') ||
        lower.contains('بلاستيك') ||
        lower.contains('علب') ||
        lower.contains('bottle') ||
        lower.contains('plastic')) {
      // أبقينا التطبيع كما هو لدعم البيانات القديمة،
      // لكن الخيار أُزيل من الواجهات.
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

  /// ✅ تحميل كل الفاسيلتيز من Firestore
  Future<void> _loadFacilitiesFromFirestore() async {
    if (!await hasInternetConnection()) {
      if (mounted) showNoInternetDialog(context);
      return;
    }

    setState(() => _isLoadingFacilities = true);

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
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingFacilities = false;
          if (!_didInitialLoad) _didInitialLoad = true;
          // عرض رسالة "لا توجد حاويات" إذا لم توجد نتائج
          if (_markers.isEmpty) _flashEmptyMsg();
        });
      }
    }
  }

  /// وميض رسالة "لا توجد حاويات" لمدة 3 ثوانٍ
  void _flashEmptyMsg() {
    _emptyTimer?.cancel();
    setState(() => _showEmptyOverlay = true);
    _emptyTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _showEmptyOverlay = false);
    });
  }

  /// تراكب "لا توجد حاويات" المؤقت
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

      final queryParts = normalizedQuery.split(' ');
      for (int i = 0; i < queryParts.length; i++) {
        final part = queryParts[i];
        if (part.isEmpty) continue;

        if (part == 'حي') {
          if (i + 1 < queryParts.length) {
            final next = queryParts[i + 1];
            if (normalizedData.contains(next)) {
              matchedMarkers.add(m);
              break;
            }
          }
        } else if (normalizedData.contains(part)) {
          matchedMarkers.add(m);
          break;
        }
      }
    }

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

              // 👇 تراكب الرسالة المؤقتة
              _buildEmptyStateOverlay(),

              // 🔍 شريط البحث
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
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

              // 🎨 الـ Legend
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
            _allowedTypes.contains('آلة إعادة التدوير (RVM)');
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
                    label: const Text('آلة إعادة التدوير (RVM)'),
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
                        if (fRvm) allowed.add('آلة إعادة التدوير (RVM)');
                        if (fFood)
                          allowed.add('حاوية إعادة تدوير بقايا الطعام');
                        setState(() => _allowedTypes = allowed);
                        _applyCurrentFilters();

                        // بعد تطبيق الفلاتر: لو ما فيه نتائج، أظهري الرسالة مؤقتًا
                        if (_didInitialLoad &&
                            !_isLoadingFacilities &&
                            _markers.isEmpty) {
                          _flashEmptyMsg();
                        }
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

  void _onAddNewLocation() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return Dialog(
          insetPadding: const EdgeInsets.fromLTRB(24, 60, 24, 100),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          child: _FacilityFormCard(
            title: 'إضافة موقع استدامة جديد',
            initialName: '',
            // ⛔️ أزلنا خيار "حاوية إعادة تدوير القوارير" وجعلنا الافتراضي "الأوراق"
            initialType: 'حاوية إعادة تدوير الأوراق',
            initialProvider: '',
            initialActive: true,
            onSubmit:
                ({
                  required String name,
                  required String type,
                  required bool isActive,
                  required String provider,
                  double? lat,
                  double? lng,
                }) async {
                  await _addMarkerToMapAndSave(
                    LatLng(lat!, lng!),
                    name,
                    type,
                    provider: (provider.trim().isEmpty
                        ? 'غير محدد'
                        : provider.trim()),
                    statusStr: isActive ? 'نشط' : 'متوقف',
                  );
                },
          ),
        );
      },
    );
  }

  // ✅ تصميم الحقول الموحدة
  InputDecoration _inputDeco(String hint, {Widget? prefixIcon}) {
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      prefixIcon: prefixIcon,
      errorMaxLines: 2,
      errorStyle: const TextStyle(fontSize: 12, height: 1.2),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: home.AppColors.primary),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: home.AppColors.primary),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: home.AppColors.dark, width: 1.2),
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

  /// ✅ ورقة تفاصيل + أزرار تعديل/حذف
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
            final type = _normalizeType((data['type'] ?? '').toString());
            final provider = (data['provider'] ?? '').toString();
            final city = (data['city'] ?? '').toString();
            final address = (data['address'] ?? '').toString();
            final statusStr =
                (data['status'] ?? _statusById[markerId.value] ?? 'نشط')
                    .toString();
            final isActive = statusStr == 'نشط';
            final statusColor = isActive ? Colors.teal : Colors.redAccent;
            final statusText = isActive ? 'نشط' : 'متوقفة';

            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ✅ صف العنوان والحالة بتصميمك
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // المربع الجديد للحالة (على اليسار)
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

                      // النص على اليمين
                      Expanded(
                        child: Text(
                          type,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.right,
                        ),
                      ),
                    ],
                  ),

                  // المعلومات التفصيلية
                  if (provider.isNotEmpty && provider != 'غير محدد')
                    _kvRightAligned('المزود', provider),
                  if (city.isNotEmpty) _kvRightAligned('المدينة', city),
                  if (address.isNotEmpty) _kvRightAligned('العنوان', address),

                  const Divider(height: 24),

                  // أزرار التعديل والحذف
                  ListTile(
                    leading: const Icon(
                      Icons.edit_outlined,
                      color: Colors.grey,
                    ),
                    title: const Text(
                      'تعديل الموقع',
                      textAlign: TextAlign.right,
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      _editMarker(markerId, type, type, position);
                    },
                  ),
                  ListTile(
                    leading: const Icon(
                      Icons.delete_outline_rounded,
                      color: Colors.red,
                    ),
                    title: const Text('حذف الموقع', textAlign: TextAlign.right),
                    onTap: () {
                      Navigator.pop(context);
                      _confirmDelete(markerId, type);
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

  // ✅ دالة مساعدة لعرض المفاتيح والقيم بمحاذاة لليمين
  Widget _kvRightAligned(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment:
            CrossAxisAlignment.start, // 👈 يخلي النصوص تطلع فوق بعض لو طويلة
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          // 👇 Expanded عشان يسمح للنص الطويل يلف سطر
          Expanded(
            child: Text(
              v,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              textAlign: TextAlign.right,
              softWrap: true, // 👈 يسمح بتعدد الأسطر
              overflow: TextOverflow.visible, // 👈 ما يقص النص الطويل
            ),
          ),
          const SizedBox(width: 8),
          Text(
            k,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.grey,
            ),
            textAlign: TextAlign.right,
          ),
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

            return Padding(
              padding: EdgeInsets.only(
                left: 0,
                right: 0,
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: _FacilityFormCard(
                title: 'تعديل بيانات الموقع',
                initialName: (data['address'] ?? '').toString(),
                initialType: _normalizeType(
                  (data['type'] ?? oldType).toString(),
                ),
                initialProvider: (data['provider'] ?? '').toString(),
                initialActive: ((data['status'] ?? 'نشط') == 'نشط'),
                fixedPosition: position,
                onSubmit:
                    ({
                      required String name,
                      required String type,
                      required bool isActive,
                      required String provider,
                      double? lat,
                      double? lng,
                    }) async {
                      final statusStr = isActive ? 'نشط' : 'متوقف';
                      await FirebaseFirestore.instance
                          .collection('facilities')
                          .doc(markerId.value)
                          .set({
                            'name': name.isEmpty ? _normalizeType(type) : name,
                            'type': _normalizeType(type),
                            'lat': lat,
                            'lng': lng,
                            'provider': provider.trim().isEmpty
                                ? 'غير محدد'
                                : provider.trim(),
                            'status': statusStr,
                            'updatedAt': FieldValue.serverTimestamp(),
                          }, SetOptions(merge: true));

                      // حدّث الماركر محليًا
                      setState(() {
                        _statusById[markerId.value] = statusStr;
                        _markers.removeWhere((m) => m.markerId == markerId);
                        final normalized = _normalizeType(type);
                        final marker = Marker(
                          markerId: markerId,
                          position: LatLng(lat!, lng!),
                          infoWindow: InfoWindow(
                            title: name.trim().isNotEmpty
                                ? name.trim()
                                : normalized,
                            snippet:
                                '$normalized${provider.trim().isNotEmpty ? ' • ${provider.trim()}' : ''}',
                            onTap: () =>
                                _showMarkerSheet(markerId, LatLng(lat, lng)),
                          ),
                          icon: _iconForType(normalized),
                          consumeTapEvents: true,
                          onTap: () =>
                              _showMarkerSheet(markerId, LatLng(lat, lng)),
                        );
                        _allMarkers.removeWhere((m) => m.markerId == markerId);
                        _allMarkers.add(marker);
                      });
                      _applyCurrentFilters();
                    },
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
      barrierDismissible: true,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  size: 48,
                  color: Colors.redAccent,
                ),
                const SizedBox(height: 8),
                const Text(
                  'تأكيد الحذف',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Text(
                  'هل أنت متأكد من حذف "$name"؟',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.black87),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    icon: const Icon(Icons.delete_outline_rounded),
                    label: const Text('تأكيد الحذف'),
                    style: FilledButton.styleFrom(
                      backgroundColor: home.AppColors.primary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: () async {
                      try {
                        await FirebaseFirestore.instance
                            .collection('facilities')
                            .doc(markerId.value)
                            .delete();
                        setState(() {
                          _statusById.remove(markerId.value);
                          _markers.removeWhere((m) => m.markerId == markerId);
                          _allMarkers.removeWhere(
                            (m) => m.markerId == markerId,
                          );
                        });
                        if (mounted) Navigator.pop(context);
                      } catch (e) {
                        if (mounted) Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('فشل حذف السحابة')),
                        );
                      }
                    },
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: () => Navigator.pop(context),
                    child: const Text('إلغاء'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
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

class _FacilityFormCard extends StatefulWidget {
  final String title;
  final String initialName;
  final String initialType;
  final String initialProvider;
  final bool initialActive;
  final LatLng? fixedPosition;
  final Future<void> Function({
    required String name,
    required String type,
    required bool isActive,
    required String provider,
    double? lat,
    double? lng,
  })
  onSubmit;

  const _FacilityFormCard({
    required this.title,
    required this.initialName,
    required this.initialType,
    required this.initialProvider,
    required this.initialActive,
    required this.onSubmit,
    this.fixedPosition,
  });

  @override
  State<_FacilityFormCard> createState() => _FacilityFormCardState();
}

class _FacilityFormCardState extends State<_FacilityFormCard> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _providerCtrl;
  late String _type;
  bool _isActive = true;

  bool _showCoords = false;
  final _latCtrl = TextEditingController();
  final _lngCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.initialName);
    _providerCtrl = TextEditingController(text: widget.initialProvider);
    _type = widget.initialType;
    _isActive = widget.initialActive;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _providerCtrl.dispose();
    _latCtrl.dispose();
    _lngCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          child: Form(
            key: _formKey,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // العنوان + إغلاق
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        widget.title,
                        style: const TextStyle(
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

                  // اسم الموقع (إلزامي)
                  Row(
                    children: const [
                      Text(
                        'اسم الموقع',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        ' *',
                        style: TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _nameCtrl,
                    textAlign: TextAlign.right,
                    decoration: _inputDeco(
                      'مثال: حي النخيل',
                      prefixIcon: const Icon(Icons.badge_outlined),
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) {
                        return 'يرجى إدخال اسم الموقع';
                      }
                      if (v.trim().length < 2) {
                        return 'الاسم قصير جدًا';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),

                  // نوع الحاوية (إلزامي)
                  Row(
                    children: const [
                      Text(
                        'نوع الحاوية',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        ' *',
                        style: TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    value: _type,
                    decoration: _inputDeco(
                      'اختر النوع',
                      prefixIcon: const Icon(Icons.category_outlined),
                    ),
                    isExpanded: true,
                    items: const [
                      // ⛔️ تمت إزالة "حاوية إعادة تدوير القوارير"
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
                        value: 'آلة إعادة التدوير (RVM)',
                        child: Text('آلة إعادة التدوير (RVM)'),
                      ),
                    ],
                    onChanged: (val) => setState(() => _type = val ?? _type),
                    validator: (v) =>
                        (v == null || v.isEmpty) ? 'اختر نوع الحاوية' : null,
                  ),
                  const SizedBox(height: 14),

                  // provider (اختياري)
                  const Text(
                    'مقدم الخدمة (اختياري)',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _providerCtrl,
                    textAlign: TextAlign.right,
                    decoration: _inputDeco(
                      'مثال: Sparklo / البلدية / KSU',
                      prefixIcon: const Icon(Icons.handshake_outlined),
                    ),
                    validator: (_) => null,
                  ),

                  const SizedBox(height: 10),
                  SwitchListTile(
                    title: Text('الحالة: ${_isActive ? 'نشط' : 'متوقفة'}'),
                    value: _isActive,
                    onChanged: (v) => setState(() => _isActive = v),
                    contentPadding: EdgeInsets.zero,
                  ),

                  // أزرار اختيار تحديد الموقع
                  if (widget.fixedPosition == null)
                    Row(
                      children: [
                        Flexible(
                          fit: FlexFit.tight,
                          child: _LocationOptionButton(
                            icon: Icons.edit_location_alt_outlined,
                            label: 'إدخال بالإحداثيات',
                            selected: _showCoords == true,
                            onTap: () =>
                                setState(() => _showCoords = !_showCoords),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Flexible(
                          fit: FlexFit.tight,
                          child: _LocationOptionButton(
                            icon: Icons.my_location,
                            label: ' موقعي الحالي',
                            selected: _showCoords == false,
                            onTap: () async {
                              setState(() => _showCoords = false);
                              if (!_formKey.currentState!.validate()) return;
                              try {
                                final p = await Geolocator.getCurrentPosition(
                                  desiredAccuracy: LocationAccuracy.high,
                                );
                                await widget.onSubmit(
                                  name: _nameCtrl.text.trim(),
                                  type: _type,
                                  isActive: _isActive,
                                  provider: _providerCtrl.text.trim(),
                                  lat: p.latitude,
                                  lng: p.longitude,
                                );
                                if (mounted) Navigator.pop(context);
                              } catch (_) {
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

                  if (_showCoords && widget.fixedPosition == null) ...[
                    const SizedBox(height: 16),
                    Row(
                      children: const [
                        Text(
                          'إحداثيات الموقع',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          ' *',
                          style: TextStyle(
                            color: Colors.red,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _latCtrl,
                            textAlign: TextAlign.right,
                            keyboardType: TextInputType.number,
                            decoration: _inputDeco(
                              'Latitude',
                              prefixIcon: const Icon(Icons.straighten_outlined),
                            ),
                            validator: (v) {
                              if (v == null || v.trim().isEmpty)
                                return 'إلزامي';
                              final d = double.tryParse(v);
                              if (d == null || d < -90 || d > 90)
                                return 'قيمة غير صحيحة';
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextFormField(
                            controller: _lngCtrl,
                            textAlign: TextAlign.right,
                            keyboardType: TextInputType.number,
                            decoration: _inputDeco(
                              'Longitude',
                              prefixIcon: const Icon(Icons.straighten),
                            ),
                            validator: (v) {
                              if (v == null || v.trim().isEmpty)
                                return 'إلزامي';
                              final d = double.tryParse(v);
                              if (d == null || d < -180 || d > 180)
                                return 'قيمة غير صحيحة';
                              return null;
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        gradient: const LinearGradient(
                          colors: [
                            AppColors.mint,
                            AppColors.primary,
                            AppColors.primary,
                          ],
                          begin: Alignment.centerRight,
                          end: Alignment.centerLeft,
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x33000000),
                            blurRadius: 8,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      child: FilledButton.icon(
                        icon: const Icon(Icons.check, color: Colors.white),
                        label: const Text(
                          'تأكيد الإحداثيات',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          padding: const EdgeInsets.symmetric(
                            vertical: 8,
                            horizontal: 18,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          minimumSize: const Size.fromHeight(42),
                        ),
                        onPressed: () async {
                          if (!_formKey.currentState!.validate()) return;
                          final lat = double.parse(_latCtrl.text.trim());
                          final lng = double.parse(_lngCtrl.text.trim());
                          await widget.onSubmit(
                            name: _nameCtrl.text.trim(),
                            type: _type,
                            isActive: _isActive,
                            provider: _providerCtrl.text.trim(),
                            lat: lat,
                            lng: lng,
                          );
                          if (mounted) Navigator.pop(context);
                        },
                      ),
                    ),
                  ],

                  if (widget.fixedPosition != null) ...[
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.teal,
                        ),
                        onPressed: () async {
                          if (!_formKey.currentState!.validate()) return;
                          await widget.onSubmit(
                            name: _nameCtrl.text.trim(),
                            type: _type,
                            isActive: _isActive,
                            provider: _providerCtrl.text.trim(),
                            lat: widget.fixedPosition!.latitude,
                            lng: widget.fixedPosition!.longitude,
                          );
                          if (mounted) Navigator.pop(context);
                        },
                        child: const Text('حفظ التعديلات'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDeco(String hint, {Widget? prefixIcon}) {
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      prefixIcon: prefixIcon,
      errorMaxLines: 2,
      errorStyle: const TextStyle(fontSize: 12, height: 1.2),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: home.AppColors.primary),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: home.AppColors.primary),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: home.AppColors.dark, width: 1.2),
      ),
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
        Text(
          label,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
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
              : Icon(icon, color: home.AppColors.dark),
        ),
      ),
    );
  }
}

// ================== الهيدر الجديد ببيانات المستخدم ===================
class _HeaderUser extends StatelessWidget {
  final String name;
  final ImageProvider<Object>? avatarImage;
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
      if (url.startsWith('http://') || url.startsWith('https://')) {
        return NetworkImage(url);
      }
    }

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

class _LocationOptionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _LocationOptionButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = selected
        ? AppColors.primary.withOpacity(0.12)
        : Colors.transparent;
    final border = selected ? AppColors.primary : AppColors.light;
    final fg = selected ? AppColors.dark : Colors.black.withOpacity(.7);

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: border, width: 1.2),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: AppColors.primary),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.ibmPlexSansArabic(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: fg,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
