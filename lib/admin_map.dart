// lib/pages/admin_map.dart
import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:open_location_code/open_location_code.dart' as olc;

// استيراد صفحات الأدمن
import 'admin_home.dart' as home;
import 'admin_task.dart';
import 'admin_reward.dart' as reward;
import 'admin_bottom_nav.dart';
import 'admin_report.dart' as report;

// ✅ استيراد صفحة البروفايل (للتنقل عند الضغط على الهيدر)
import 'profile.dart';

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

  // ✅ لا توجد فلترة بالحالة الآن — فقط حسب النوع (اختياري)
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

  // ===== حالات الإظهار للرسالة المؤقّتة =====
  bool _isLoadingFacilities = false; // تحميل قائمة الحاويات من السحابة
  bool _didInitialLoad = false; // هل انتهى التحميل الأولي مرة واحدة؟
  bool _showEmptyOverlay = false; // عرض تراكب "لا توجد حاويات" مؤقّتًا
  Timer? _emptyTimer; // مؤقّت الإخفاء

  @override
  void initState() {
    super.initState();
    _ensureLocationPermission();
    _loadMarkerIcons().then((_) => _loadFacilitiesFromFirestore());
  }

  @override
  void dispose() {
    _emptyTimer?.cancel();
    super.dispose();
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

  LatLng? _decodePlusCodeToLatLng(String rawPlusCode) {
    try {
      var pc = olc.PlusCode.unverified(rawPlusCode);
      if (pc.isShort())
        pc = pc.recoverNearest(olc.LatLng(_riyadh.latitude, _riyadh.longitude));
      if (!pc.isValid) return null;
      final area = pc.decode();
      final center = area.center;
      return LatLng(center.latitude, center.longitude);
    } catch (e) {
      debugPrint('PlusCode decode error: $e');
      return null;
    }
  }

  // ===== وميض رسالة "لا توجد حاويات" لمدة 3 ثوانٍ =====
  void _flashEmptyMsg() {
    _emptyTimer?.cancel();
    setState(() => _showEmptyOverlay = true);
    _emptyTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _showEmptyOverlay = false);
    });
  }

  /// ✅ تحميل كل الفاسيلتيز من Firestore (بدون فلترة حالة)
  Future<void> _loadFacilitiesFromFirestore() async {
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

      _applyCurrentFilters(); // يحدّث _markers حسب فلاتر النوع فقط

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

          if (_markers.isEmpty && !_isSelecting) {
            _flashEmptyMsg();
          }
        });
      }
    }
  }

  /// ✅ الآن: فلترة بالأنواع فقط (بدون حالة)
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

    if (_didInitialLoad &&
        !_isLoadingFacilities &&
        _markers.isEmpty &&
        !_isSelecting) {
      _flashEmptyMsg();
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

  void _onSearchSubmitted(String query) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('بحث: $query')));
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

              // تراكب "لا توجد حاويات" المؤقّت
              _buildEmptyStateOverlay(),

              // 🔹 الهيدر + شريط البحث (SafeArea)
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // ====== الهيدر (قابل للنقر ويفتح البروفايل) ======
                      HeaderUserLive(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const profilePage(),
                            ),
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

              // أزرار جانبية
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

              // 📄 زر الذهاب لصفحة التقارير
              Positioned(
                left: 12,
                bottom: 100,
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

              // زر إضافة موقع جديد
              Positioned(
                left: 12,
                bottom: isKeyboardOpen ? 12 : 28,
                child: _RoundBtn(
                  icon: Icons.add_location_alt_rounded,
                  tooltip: 'إضافة موقع جديد',
                  onTap: _onAddNewLocation,
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

  void _onAddNewLocation() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) {
        final TextEditingController nameCtrl = TextEditingController();
        final TextEditingController providerCtrl = TextEditingController();
        String selectedType = 'حاوية إعادة تدوير القوارير';
        bool isActive = true;

        return StatefulBuilder(
          builder: (context, setSt) {
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
                      'إضافة موقع استدامة جديد',
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
                    textAlign: TextAlign.right,
                    decoration: InputDecoration(
                      hintText: 'مثال: حي النخيل',
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(
                          color: home.AppColors.primary,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 14),
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
                            value: 'حاوية إعادة تدوير متعددة المواد',
                            child: Text('حاوية إعادة تدوير متعددة المواد'),
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
                  const Text(
                    'مقدم الخدمة',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: providerCtrl,
                    textAlign: TextAlign.right,
                    decoration: InputDecoration(
                      hintText: 'مثال: Sparklo / البلدية / KSU',
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(
                          color: home.AppColors.primary,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 6),
                  SwitchListTile(
                    title: Text(isActive ? 'الحالة: نشطة' : 'الحالة: متوقفة'),
                    value: isActive,
                    onChanged: (v) => setSt(() => isActive = v),
                    contentPadding: EdgeInsets.zero,
                  ),

                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () async {
                            final pos = await Geolocator.getCurrentPosition(
                              desiredAccuracy: LocationAccuracy.high,
                            );
                            if (!mounted) return;
                            await _addMarkerToMapAndSave(
                              LatLng(pos.latitude, pos.longitude),
                              nameCtrl.text,
                              selectedType,
                              provider: providerCtrl.text,
                              statusStr: isActive ? 'نشط' : 'متوقف',
                            );
                            if (mounted) Navigator.pop(context);
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('تمت إضافة الحاوية بنجاح ✅'),
                                ),
                              );
                            }
                          },
                          icon: const Icon(Icons.my_location),
                          label: const Text('استخدام موقعي الحالي'),
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.teal,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () {
                            if (nameCtrl.text.trim().isEmpty) {
                              showDialog(
                                context: context,
                                builder: (context) => AlertDialog(
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  title: const Text(
                                    'تنبيه',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  content: const Text(
                                    'رجاءً أدخل اسم الموقع أولاً 🏷️',
                                    textAlign: TextAlign.center,
                                  ),
                                  actionsAlignment: MainAxisAlignment.center,
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(context),
                                      child: const Text('حسنًا'),
                                    ),
                                  ],
                                ),
                              );
                              return;
                            }

                            Navigator.pop(context);
                            setState(() {
                              _isSelecting = true;
                              _lastAddedName = nameCtrl.text;
                              _lastAddedType = selectedType;
                              _lastProvider = providerCtrl.text;
                              _lastStatusStr = isActive ? 'نشط' : 'متوقف';
                            });

                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'اضغط على الخريطة لتحديد موقع "$selectedType" 📍',
                                ),
                              ),
                            );
                          },
                          icon: const Icon(Icons.add_location_alt_rounded),
                          label: const Text('اختيار من الخريطة'),
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.orange,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
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

  /// 🔧 تعديل الماركر
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

            return StatefulBuilder(
              builder: (context, setSt) {
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
                            value: 'حاوية إعادة تدوير متعددة المواد',
                            child: Text('حاوية إعادة تدوير متعددة المواد'),
                          ),
                          DropdownMenuItem(
                            value: 'آلة استرجاع (RVM)',
                            child: Text('آلة استرجاع (RVM)'),
                          ),
                        ],
                        onChanged: (val) =>
                            setSt(() => selectedType = val ?? selectedType),
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
                        title: Text(
                          isActive ? 'الحالة: نشطة' : 'الحالة: متوقفة',
                        ),
                        value: isActive,
                        onChanged: (v) => setSt(() => isActive = v),
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
                            try {
                              final normalized = _normalizeType(selectedType);
                              final inputName = nameCtrl.text.trim();
                              final currentName = (data['name'] ?? '')
                                  .toString()
                                  .trim();
                              final finalName = inputName.isNotEmpty
                                  ? inputName
                                  : currentName;

                              final String statusStr = isActive
                                  ? 'نشط'
                                  : 'متوقف';
                              final String providerFinal =
                                  providerCtrl.text.trim().isEmpty
                                  ? 'غير محدد'
                                  : providerCtrl.text.trim();

                              final Map<String, dynamic> payload = {
                                'type': normalized,
                                'lat': position.latitude,
                                'lng': position.longitude,
                                'provider': providerFinal,
                                'status': statusStr,
                                'updatedAt': FieldValue.serverTimestamp(),
                              };
                              if (finalName.isNotEmpty) {
                                payload['name'] = finalName;
                              }

                              await FirebaseFirestore.instance
                                  .collection('facilities')
                                  .doc(markerId.value)
                                  .set(payload, SetOptions(merge: true));

                              // تحديث الماركر محليًا
                              setState(() {
                                _statusById[markerId.value] = statusStr;
                                _markers.removeWhere(
                                  (m) => m.markerId == markerId,
                                );

                                final titleForMarker = (finalName.isNotEmpty
                                    ? finalName
                                    : normalized);
                                final marker = Marker(
                                  markerId: markerId,
                                  position: position,
                                  infoWindow: InfoWindow(
                                    title: titleForMarker,
                                    snippet:
                                        '$normalized${providerFinal.isNotEmpty ? ' • $providerFinal' : ''}',
                                    onTap: () =>
                                        _showMarkerSheet(markerId, position),
                                  ),
                                  icon: _iconForType(normalized),
                                  consumeTapEvents: true,
                                  onTap: () =>
                                      _showMarkerSheet(markerId, position),
                                );

                                _allMarkers.removeWhere(
                                  (m) => m.markerId == markerId,
                                );
                                _allMarkers.add(marker);
                              });

                              _applyCurrentFilters();

                              if (mounted) Navigator.pop(context);
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('تم حفظ التعديلات ✅'),
                                  ),
                                );
                              }
                            } catch (e) {
                              debugPrint('❌ تحديث Firestore فشل: $e');
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('فشل تحديث السحابة'),
                                  ),
                                );
                              }
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
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('تم حذف الموقع بنجاح ✅')),
                  );
                }
              } catch (e) {
                debugPrint('❌ حذف Firestore فشل: $e');
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('فشل حذف السحابة')),
                  );
                }
              }
            },
            child: const Text('حذف', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _onMapTap(LatLng position) {
    if (_isSelecting) {
      setState(() => _tempLocation = position);
    }
  }

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
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('تمت إضافة "${_lastAddedName!}" بنجاح ✅'),
                      ),
                    );
                  }
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

  /// يُظهر تراكبًا لطيفًا لرسالة "لا توجد حاويات" بشكل مؤقّت
  Widget _buildEmptyStateOverlay() {
    if (!_showEmptyOverlay || _isSelecting || _isLoadingFacilities) {
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

  /// ✅ إضافة ماركر + حفظ المستند
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('حدث خطأ أثناء حفظ البيانات')),
        );
      }
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
