import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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
  final Set<Marker> _allMarkers = {}; // نخزّن جميع الماركرات للفلترة
  final Set<Polyline> _polylines = {};

  bool _myLocationEnabled = false;
  bool _isLoadingLocation = false;

  /// وضع تحديد موقع جديد من الخريطة
  bool _isSelecting = false;
  LatLng? _tempLocation;
  String? _lastAddedName;
  String? _lastAddedType;

  @override
  void initState() {
    super.initState();
    _ensureLocationPermission();
    _loadFacilitiesFromFirestore();
  }

  // ===== سلوك الناف بار (مطابق للـ AdminHome) =====
  void _onTap(int i) {
    if (i == 1) return; // أنت في تبويب الخريطة بالفعل
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

  // ===== Helpers (مطابقة لصفحة اليوزر) =====
  String _normalizeType(String raw) {
    final t = (raw).trim();
    if (t.contains('ملابس')) return 'حاوية إعادة تدوير الملابس';
    if (t.contains('RVM') || t.contains('آلة استرجاع'))
      return 'آلة استرجاع (RVM)';
    if (t.contains('قوارير') || t.contains('بلاستيك'))
      return 'حاوية إعادة تدوير القوارير';
    if (t.contains('بقايا') || t.contains('طعام'))
      return 'حاوية إعادة تدوير بقايا الطعام';
    if (t.contains('أوراق') || t.contains('ورق'))
      return 'حاوية إعادة تدوير الأوراق';
    return t.isEmpty ? 'نقطة استدامة' : t;
  }

  double _hueForType(String type) {
    // نفس ألوان صفحة اليوزر
    switch (type) {
      case 'حاوية إعادة تدوير الملابس':
        return BitmapDescriptor.hueViolet;
      case 'آلة استرجاع (RVM)':
        return BitmapDescriptor.hueAzure;
      case 'حاوية إعادة تدوير القوارير':
        return BitmapDescriptor.hueBlue;
      case 'حاوية إعادة تدوير بقايا الطعام':
        return BitmapDescriptor.hueGreen;
      case 'حاوية إعادة تدوير الأوراق':
        return BitmapDescriptor.hueOrange;
      default:
        return BitmapDescriptor.hueRed;
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

  /// ✅ تحميل كل الفاسيلتيز من Firestore وعرضها كعلامات
  Future<void> _loadFacilitiesFromFirestore() async {
    try {
      final qs = await FirebaseFirestore.instance
          .collection('facilities')
          .get();

      final markers = <Marker>{};
      LatLngBounds? bounds;

      for (final d in qs.docs) {
        final m = d.data();
        final double? lat = (m['lat'] as num?)?.toDouble();
        final double? lng = (m['lng'] as num?)?.toDouble();
        if (lat == null || lng == null) continue;

        // تحقّق حدود منطقية
        final valid = lat > 20 && lat < 30 && lng > 40 && lng < 55;
        if (!valid) continue;

        final String typeRaw = (m['type'] ?? '').toString();
        final String type = _normalizeType(typeRaw);

        final String provider = (m['provider'] ?? '').toString();
        final String city = (m['city'] ?? '').toString();
        final String address = (m['address'] ?? '').toString();

        final pos = LatLng(lat, lng);

        // ✅ مطابق لليوزر: العنوان في الـ snippet وإن لم يوجد نعرض provider • city
        final String snippet = address.isNotEmpty
            ? address
            : [
                if (provider.isNotEmpty) provider,
                if (city.isNotEmpty) city,
              ].join(' • ');

        final marker = Marker(
          markerId: MarkerId(d.id),
          position: pos,
          infoWindow: InfoWindow(
            title: type, // ✅ نفس اليوزر: العنوان هو النوع
            snippet: snippet,
          ),
          icon: BitmapDescriptor.defaultMarkerWithHue(_hueForType(type)),
          onTap: () => _onMarkerTapped(MarkerId(d.id), type, type, pos),
        );

        markers.add(marker);
        bounds = _extendBounds(bounds, pos);
      }

      setState(() {
        _markers
          ..clear()
          ..addAll(markers);
        _allMarkers
          ..clear()
          ..addAll(markers);
      });

      if (bounds != null && markers.isNotEmpty) {
        final ctrl = await _mapCtrl.future;
        await ctrl.animateCamera(CameraUpdate.newLatLngBounds(bounds, 60));
      }

      debugPrint('✅ تم تحميل ${markers.length} موقع من Firestore');
    } catch (e) {
      debugPrint('❌ خطأ أثناء تحميل الفاسيلتيز: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر تحميل المواقع من السحابة')),
        );
      }
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

              // شريط البحث
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                  child: Column(
                    children: [
                      _SearchBar(
                        controller: _searchCtrl,
                        onSubmitted: _onSearchSubmitted,
                        onFilterTap: _showFiltersBottomSheet, // ✅ نفس اليوزر
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
                      onTap:
                          _loadFacilitiesFromFirestore, // ✅ تحديث من Firestore
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

          // ===== ناف بار مطابق لصفحة الـ AdminHome =====
          bottomNavigationBar: isKeyboardOpen
              ? null
              : AdminBottomNav(
                  currentIndex: 1, // تبويب الخريطة
                  onTap: _onTap,
                ),
        ),
      ),
    );
  }

  // ===== فلتر الأنواع (مطابق لليوزر: ملابس + RVM فقط) =====
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
                    label: const Text('آلة استرجاع (RVM)'),
                    selected: fRvm,
                    onSelected: (v) => setSt(() => fRvm = v),
                  ),

                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () {
                        Navigator.pop(context);

                        final allowed = <String>{};
                        if (fClothes) allowed.add('حاوية إعادة تدوير الملابس');
                        if (fRvm) allowed.add('آلة استرجاع (RVM)');

                        setState(() {
                          _markers
                            ..clear()
                            ..addAll(
                              _allMarkers.where((m) {
                                // ✅ نفلتر بناءً على العنوان (title) لأنه هو النوع
                                final t = m.infoWindow.title ?? '';
                                return allowed.isEmpty || allowed.contains(t);
                              }),
                            );
                        });
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
        String selectedType = 'حاوية إعادة تدوير القوارير';

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
                            alignment: Alignment.centerRight,
                            child: Text('حاوية إعادة تدوير القوارير'),
                          ),
                          DropdownMenuItem(
                            value: 'حاوية إعادة تدوير الملابس',
                            alignment: Alignment.centerRight,
                            child: Text('حاوية إعادة تدوير الملابس'),
                          ),
                          DropdownMenuItem(
                            value: 'حاوية إعادة تدوير بقايا الطعام',
                            alignment: Alignment.centerRight,
                            child: Text('حاوية إعادة تدوير بقايا الطعام'),
                          ),
                          DropdownMenuItem(
                            value: 'حاوية إعادة تدوير الأوراق',
                            alignment: Alignment.centerRight,
                            child: Text('حاوية إعادة تدوير الأوراق'),
                          ),
                          DropdownMenuItem(
                            value: 'حاوية إعادة تدوير متعددة المواد',
                            alignment: Alignment.centerRight,
                            child: Text('حاوية إعادة تدوير متعددة المواد'),
                          ),
                          DropdownMenuItem(
                            value: 'آلة استرجاع (RVM)',
                            alignment: Alignment.centerRight,
                            child: Text('آلة استرجاع (RVM)'),
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

  /// 🔹 يعرض خيارات عند الضغط على أي ماركر (تعديل / حذف)
  void _onMarkerTapped(
    MarkerId markerId,
    String nameOrType, // نعرض النوع في العنوان
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
                nameOrType,
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
                  _editMarker(markerId, nameOrType, type, position);
                },
              ),

              // 🗑️ زر حذف
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text('حذف الموقع'),
                onTap: () {
                  Navigator.pop(context);
                  _confirmDelete(markerId, nameOrType);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  /// ✏️ تعديل بيانات الموقع + تحديث Firestore
  void _editMarker(
    MarkerId markerId,
    String oldNameOrType,
    String oldType,
    LatLng position,
  ) {
    final TextEditingController nameCtrl = TextEditingController(
      text: oldNameOrType,
    );
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
                'اسم / نوع الموقع',
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
                onChanged: (val) => selectedType = val ?? oldType,
              ),

              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: Colors.teal),
                  onPressed: () async {
                    if (nameCtrl.text.trim().isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('يرجى إدخال اسم الموقع')),
                      );
                      return;
                    }

                    try {
                      // ✅ تحديث Firestore
                      await FirebaseFirestore.instance
                          .collection('facilities')
                          .doc(markerId.value)
                          .set({
                            'name': nameCtrl.text.trim(),
                            'type': selectedType,
                            'lat': position.latitude,
                            'lng': position.longitude,
                            'updatedAt': FieldValue.serverTimestamp(),
                          }, SetOptions(merge: true));

                      // ✅ تحديث العلامة في الخريطة
                      setState(() {
                        _markers.removeWhere((m) => m.markerId == markerId);
                        final hue = _hueForType(_normalizeType(selectedType));
                        final marker = Marker(
                          markerId: markerId,
                          position: position,
                          infoWindow: InfoWindow(
                            // نخلي العنوان النوع (مطابق لليوزر)
                            title: _normalizeType(selectedType),
                            snippet: nameCtrl.text.trim().isEmpty
                                ? ''
                                : nameCtrl.text.trim(),
                          ),
                          icon: BitmapDescriptor.defaultMarkerWithHue(hue),
                          onTap: () => _onMarkerTapped(
                            markerId,
                            _normalizeType(selectedType),
                            _normalizeType(selectedType),
                            position,
                          ),
                        );
                        _markers.add(marker);

                        _allMarkers.removeWhere((m) => m.markerId == markerId);
                        _allMarkers.add(marker);
                      });

                      if (mounted) Navigator.pop(context);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('تم تحديث الموقع بنجاح ✅'),
                          ),
                        );
                      }
                    } catch (e) {
                      debugPrint('❌ تحديث Firestore فشل: $e');
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('فشل تحديث السحابة')),
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
  }

  /// 🗑️ تأكيد الحذف + حذف من Firestore
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

  /// لما يضغط الأدمن على الخريطة في وضع التحديد
  void _onMapTap(LatLng position) {
    if (_isSelecting) {
      setState(() {
        _tempLocation = position;
      });
    }
  }

  /// زر تأكيد الموقع (داخل build)
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

  /// ✅ إضافة ماركر + حفظ المستند أولًا في Firestore للحصول على docId
  Future<void> _addMarkerToMapAndSave(
    LatLng pos,
    String name,
    String type,
  ) async {
    try {
      final normalizedType = _normalizeType(type);

      final docRef = FirebaseFirestore.instance.collection('facilities').doc();
      await docRef.set({
        'name': name.isEmpty ? 'موقع جديد' : name.trim(),
        'type': normalizedType,
        'lat': pos.latitude,
        'lng': pos.longitude,
        'status': 'نشط',
        'city': 'الرياض',
        'provider': 'الأدمن',
        'createdAt': FieldValue.serverTimestamp(),
      });

      final hue = _hueForType(normalizedType);

      setState(() {
        final markerId = MarkerId(docRef.id);
        final marker = Marker(
          markerId: markerId,
          position: pos,
          infoWindow: InfoWindow(
            // ✅ العنوان هو النوع (مطابق لليوزر)
            title: normalizedType,
            snippet: name.isEmpty ? '' : name.trim(),
          ),
          icon: BitmapDescriptor.defaultMarkerWithHue(hue),
          onTap: () =>
              _onMarkerTapped(markerId, normalizedType, normalizedType, pos),
        );

        _markers.add(marker);
        _allMarkers.add(marker);
      });

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
