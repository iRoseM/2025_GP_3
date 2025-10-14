// lib/pages/admin_map.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:open_location_code/open_location_code.dart' as olc;

// استيراد صفحات الأدمن
import 'admin_home.dart' as home;
import 'admin_task.dart';
import 'admin_reward.dart' as reward;
import 'admin_bottom_nav.dart';
import 'admin_report.dart' as report;

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
  final Set<Polyline> _polylines = {};

  bool _myLocationEnabled = false;
  bool _isLoadingLocation = false;

  // 🔹 حالة الفلاتر (نتذكر آخر تحديد)
  bool fBottles = true;
  bool fClothes = true;
  bool fFood = true;
  bool fPapers = true;
  bool fMixed = true;

  Set<Marker> _allMarkers = {}; // كل الماركرات الأصلية

  @override
  void initState() {
    super.initState();
    _ensureLocationPermission();
    _addDefaultRecyclingBins();
  }

  LatLng? _decodePlusCodeToLatLng(String rawPlusCode) {
    try {
      var pc = olc.PlusCode.unverified(rawPlusCode);
      if (pc.isShort()) {
        pc = pc.recoverNearest(olc.LatLng(_riyadh.latitude, _riyadh.longitude));
      }
      if (!pc.isValid) return null;
      final area = pc.decode();
      final center = area.center;
      return LatLng(center.latitude, center.longitude);
    } catch (e) {
      debugPrint('PlusCode decode error: $e');
      return null;
    }
  }

  /// 🗺️ يضيف نقاط افتراضية لأنواع مختلفة من الحاويات
  Future<void> _addDefaultRecyclingBins() async {
    final List<Map<String, dynamic>> defaultBins = [
      {
        'name': 'حاوية إعادة تدوير القوارير – حي النخيل',
        'type': 'حاوية إعادة تدوير القوارير',
        'position': const LatLng(24.7425, 46.6532),
      },
      {
        'name': 'حاوية إعادة تدوير الملابس – حي الياسمين',
        'type': 'حاوية إعادة تدوير الملابس',
        'position': const LatLng(24.8030, 46.6380),
      },
      {
        'name': 'حاوية إعادة تدوير بقايا الطعام – حي المروج',
        'type': 'حاوية إعادة تدوير بقايا الطعام',
        'position': const LatLng(24.7568, 46.6615),
      },
      {
        'name': 'حاوية إعادة تدوير الأوراق – حي العليا',
        'type': 'حاوية إعادة تدوير الأوراق',
        'position': const LatLng(24.6941, 46.6850),
      },
      {
        'name': 'حاوية إعادة تدوير متعددة المواد – حي قرطبة',
        'type': 'حاوية إعادة تدوير متعددة المواد',
        'position': const LatLng(24.7900, 46.7500),
      },
    ];

    final Set<Marker> markers = {};

    for (final item in defaultBins) {
      final type = item['type'] as String;
      final pos = item['position'] as LatLng;
      final name = item['name'] as String;

      double hue;
      switch (type) {
        case 'حاوية إعادة تدوير القوارير':
          hue = BitmapDescriptor.hueBlue;
          break;
        case 'حاوية إعادة تدوير الملابس':
          hue = BitmapDescriptor.hueViolet;
          break;
        case 'حاوية إعادة تدوير بقايا الطعام':
          hue = BitmapDescriptor.hueGreen;
          break;
        case 'حاوية إعادة تدوير الأوراق':
          hue = BitmapDescriptor.hueOrange;
          break;
        case 'حاوية إعادة تدوير متعددة المواد':
          hue = BitmapDescriptor.hueAzure;
          break;
        default:
          hue = BitmapDescriptor.hueRed;
      }

      markers.add(
        Marker(
          markerId: MarkerId(name),
          position: pos,
          infoWindow: InfoWindow(title: name, snippet: type),
          icon: BitmapDescriptor.defaultMarkerWithHue(hue),
          onTap: () => _onMarkerTapped(MarkerId(name), name, type, pos),
        ),
      );
    }

    setState(() {
      _markers
        ..clear()
        ..addAll(markers);

      // نحفظ النسخة الأصلية في allMarkers
      _allMarkers
        ..clear()
        ..addAll(markers);
    });

    final controller = await _mapCtrl.future;
    await controller.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: const LatLng(24.67, 46.60),
          northeast: const LatLng(24.83, 46.76),
        ),
        50,
      ),
    );
  }

  LatLngBounds _extendBounds(LatLngBounds? current, LatLng p) {
    if (current == null) {
      return LatLngBounds(southwest: p, northeast: p);
    }
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
          body: Stack(
            children: [
              GoogleMap(
                initialCameraPosition: const CameraPosition(
                  target: _riyadh,
                  zoom: _initZoom,
                ),
                onMapCreated: (c) => _mapCtrl.complete(c),
                myLocationEnabled: _myLocationEnabled,
                myLocationButtonEnabled: false,
                compassEnabled: true,
                zoomControlsEnabled: false,
                markers: _markers,
                polylines: _polylines,
                mapToolbarEnabled: false,
                onTap: _onMapTap,
              ),

              // شريط البحث
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                  child: Column(
                    children: [
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
                      onTap: _addDefaultRecyclingBins,
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
                        builder: (_) => report.AdminReportPage(),
                      ),
                    );
                  },
                ),
              ),

              // زر إضافة موقع جديد (أسفل يسار)
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

          // الناف بار الخاص بالأدمن
          bottomNavigationBar: isKeyboardOpen
              ? null
              : AdminBottomNav(
                  currentIndex: 2,
                  onTap: (i) {
                    if (i == 0) {
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(builder: (_) => home.AdminHomePage()),
                      );
                    } else if (i == 1) {
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(builder: (_) => AdminTasksPage()),
                      );
                    } else if (i == 2) {
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(builder: (_) => AdminMapPage()),
                      );
                    } else if (i == 3) {
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                          builder: (_) => report.AdminReportPage(),
                        ),
                      );
                    }
                  },
                ),
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
        return StatefulBuilder(
          builder: (context, setSt) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'فلتر حاويات إعادة التدوير',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 12),

                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      FilterChip(
                        label: const Text('حاويات إعادة تدوير القوارير'),
                        selected: fBottles,
                        onSelected: (v) => setSt(() => fBottles = v),
                      ),
                      FilterChip(
                        label: const Text('حاويات إعادة تدوير الملابس'),
                        selected: fClothes,
                        onSelected: (v) => setSt(() => fClothes = v),
                      ),
                      FilterChip(
                        label: const Text('حاويات إعادة تدوير بقايا الطعام'),
                        selected: fFood,
                        onSelected: (v) => setSt(() => fFood = v),
                      ),
                      FilterChip(
                        label: const Text('حاويات إعادة تدوير الأوراق'),
                        selected: fPapers,
                        onSelected: (v) => setSt(() => fPapers = v),
                      ),
                      FilterChip(
                        label: const Text('حاويات إعادة تدوير متعددة المواد'),
                        selected: fMixed,
                        onSelected: (v) => setSt(() => fMixed = v),
                      ),
                    ],
                  ),

                  const SizedBox(height: 18),

                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: home.AppColors.primary,
                      ),
                      onPressed: () {
                        Navigator.pop(context);

                        // قائمة الأنواع المفعّلة
                        final activeTypes = <String>{};
                        if (fBottles)
                          activeTypes.add('حاوية إعادة تدوير القوارير');
                        if (fClothes)
                          activeTypes.add('حاوية إعادة تدوير الملابس');
                        if (fFood)
                          activeTypes.add('حاوية إعادة تدوير بقايا الطعام');
                        if (fPapers)
                          activeTypes.add('حاوية إعادة تدوير الأوراق');
                        if (fMixed)
                          activeTypes.add('حاوية إعادة تدوير متعددة المواد');

                        // تطبيق الفلترة على الماركرات
                        setState(() {
                          // نخزن آخر حالة للفلاتر
                          this.fBottles = fBottles;
                          this.fClothes = fClothes;
                          this.fFood = fFood;
                          this.fPapers = fPapers;
                          this.fMixed = fMixed;

                          _markers
                            ..clear()
                            ..addAll(
                              _allMarkers.where((m) {
                                final snippet = m.infoWindow.snippet ?? '';
                                return activeTypes.contains(snippet);
                              }),
                            );
                        });

                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('تم تطبيق الفلتر بنجاح ✅'),
                          ),
                        );
                      },
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
        String selectedType = 'حاوية إعادة تدوير القوارير';
        bool selectingFromMap = false;
        LatLng? selectedLocation;

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

                  // 🏷️ اسم الموقع
                  const Text(
                    'اسم الموقع',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: nameCtrl,
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
                        borderSide: const BorderSide(color: Colors.black12),
                      ),
                    ),
                  ),

                  const SizedBox(height: 14),

                  // 🧩 نوع الحاوية
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
                      border: Border.all(color: Colors.black12),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: selectedType,
                        isExpanded: true,
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
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            setSt(() => selectedType = val);
                          }
                        },
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // 📍 تحديد الموقع
                  const Text(
                    'الموقع',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),

                  // زرّي الموقع
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () async {
                            final pos = await Geolocator.getCurrentPosition(
                              desiredAccuracy: LocationAccuracy.high,
                            );
                            if (!mounted) return;

                            _addMarkerToMap(
                              LatLng(pos.latitude, pos.longitude),
                              nameCtrl.text,
                              selectedType,
                            );

                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('تمت إضافة الحاوية بنجاح ✅'),
                              ),
                            );
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
                            // ✅ أولاً: نتأكد أنه كتب الاسم قبل ما يختار من الخريطة
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

                            // ✅ نغلق النافذة ونفعل وضع التحديد
                            Navigator.pop(context);
                            setState(() {
                              _isSelecting = true;
                              _lastAddedName = nameCtrl.text;
                              _lastAddedType = selectedType;
                            });

                            // ✅ تنبيه لطيف أنه الحين لازم يختار الموقع من الخريطة
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

  /// 🔹 يعرض خيارات عند الضغط على أي ماركر (تعديل / حذف)
  void _onMarkerTapped(
    MarkerId markerId,
    String name,
    String type,
    LatLng position,
  ) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              Text(type, style: const TextStyle(color: Colors.grey)),
              const Divider(height: 20),

              // ✏️ زر تعديل
              ListTile(
                leading: const Icon(Icons.edit, color: Colors.teal),
                title: const Text('تعديل الموقع'),
                onTap: () {
                  Navigator.pop(context);
                  _editMarker(markerId, name, type, position);
                },
              ),

              // 🗑️ زر حذف
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text('حذف الموقع'),
                onTap: () {
                  Navigator.pop(context);
                  _confirmDelete(markerId, name);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  /// ✏️ دالة تعديل بيانات الموقع
  void _editMarker(
    MarkerId markerId,
    String oldName,
    String oldType,
    LatLng position,
  ) {
    final TextEditingController nameCtrl = TextEditingController(text: oldName);
    String selectedType = oldType;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) {
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
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
                ],
                onChanged: (val) => selectedType = val ?? oldType,
              ),

              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: Colors.teal),
                  onPressed: () {
                    if (nameCtrl.text.trim().isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('يرجى إدخال اسم الموقع')),
                      );
                      return;
                    }

                    setState(() {
                      _markers.removeWhere((m) => m.markerId == markerId);
                      _addMarkerToMap(position, nameCtrl.text, selectedType);
                    });

                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('تم تحديث الموقع بنجاح ✅')),
                    );
                  },
                  child: const Text('حفظ التعديلات'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 🗑️ دالة تأكيد الحذف
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
            onPressed: () {
              setState(
                () => _markers.removeWhere((m) => m.markerId == markerId),
              );
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('تم حذف الموقع بنجاح ✅')),
              );
            },
            child: const Text('حذف', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  /// 🔹 حالة إضافية لتفعيل وضع التحديد
  bool _isSelecting = false;
  LatLng? _tempLocation;
  String? _lastAddedName;
  String? _lastAddedType;

  /// 🔹 لما يضغط الأدمن على الخريطة
  void _onMapTap(LatLng position) {
    if (_isSelecting) {
      setState(() {
        _tempLocation = position;
      });
    }
  }

  /// 🔹 زر تأكيد الموقع (داخل build)
  Widget _buildConfirmButton() {
    if (_isSelecting) {
      // ✅ نتحقق من أن كل البيانات مكتملة
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
              ? () {
                  _addMarkerToMap(
                    _tempLocation!,
                    _lastAddedName!,
                    _lastAddedType!,
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

  /// 🔹 يضيف الماركر فعليًا حسب اللون والنوع
  void _addMarkerToMap(LatLng pos, String name, String type) {
    double hue;
    switch (type) {
      case 'حاوية إعادة تدوير القوارير':
        hue = BitmapDescriptor.hueBlue;
        break;
      case 'حاوية إعادة تدوير الملابس':
        hue = BitmapDescriptor.hueViolet;
        break;
      case 'حاوية إعادة تدوير بقايا الطعام':
        hue = BitmapDescriptor.hueGreen;
        break;
      case 'حاوية إعادة تدوير الأوراق':
        hue = BitmapDescriptor.hueOrange;
        break;
      case 'حاوية إعادة تدوير متعددة المواد':
        hue = BitmapDescriptor.hueAzure;
        break;
      default:
        hue = BitmapDescriptor.hueRed;
    }

    setState(() {
      final markerId = MarkerId(DateTime.now().toString());

      final marker = Marker(
        markerId: markerId,
        position: pos,
        infoWindow: InfoWindow(
          title: name.isEmpty ? 'موقع جديد' : name,
          snippet: type,
        ),
        icon: BitmapDescriptor.defaultMarkerWithHue(hue),
        onTap: () => _onMarkerTapped(markerId, name, type, pos),
      );

      // نضيف الماركر في القائمتين (الأساسية والفعلية)
      _markers.add(marker);
      _allMarkers.add(marker);
    });
    ;
  }
}

/* ===== Widgets ===== */

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
