// lib/pages/map_page.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart'; // ✅ لالتقاط UID عند الإبلاغ

// صفحات أخرى
import 'home.dart';
import 'task.dart';
import 'community.dart';
import 'levels.dart';

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
  final String provider; // ✅ مأخوذ من الداتابيس
  final String city;
  final String address;

  Facility({
    required this.id,
    required this.lat,
    required this.lng,
    required this.type,
    required this.provider,
    required this.city,
    required this.address,
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

  final Set<Marker> _markers = {};
  final Set<Marker> _allMarkers = {};
  final Set<Polyline> _polylines = {};

  // نحتاج نعرف أي ماركر لأي Facility
  final Map<String, Facility> _facilitiesByMarkerId = {};

  bool _myLocationEnabled = false;
  bool _isLoadingLocation = false;

  @override
  void initState() {
    super.initState();
    _ensureLocationPermission();
    _loadFacilitiesFromFirestore();
  }

  // ===== Helpers =====
  String _normalizeType(String raw) {
    final t = (raw).trim();
    if (t.contains('ملابس')) return 'حاوية إعادة تدوير الملابس';
    if (t.contains('RVM') || t.contains('آلة استرجاع'))
      return 'آلة استرجاع (RVM)';
    if (t.contains('قوارير') || t.contains('بلاستيك'))
      return 'حاوية إعادة تدوير القوارير';
    return t.isEmpty ? 'نقطة استدامة' : t;
  }

  double _hueForType(String type) {
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

  // ===== Load facilities from Firestore =====
  Future<void> _loadFacilitiesFromFirestore() async {
    try {
      final qs = await FirebaseFirestore.instance
          .collection('facilities')
          // .where('status', isEqualTo: 'نشط') // إن أردت
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
        final String provider = (m['provider'] ?? '').toString(); // ✅
        final String city = (m['city'] ?? '').toString();
        final String address = (m['address'] ?? '').toString();

        final pos = LatLng(lat, lng);
        final markerId = MarkerId(d.id);

        // نخزّن الموديل لسهولة الوصول وقت الضغط
        final facility = Facility(
          id: d.id,
          lat: lat,
          lng: lng,
          type: type,
          provider: provider,
          city: city,
          address: address,
        );
        mapFacilities[markerId.value] = facility;

        markers.add(
          Marker(
            markerId: markerId,
            position: pos,
            icon: BitmapDescriptor.defaultMarkerWithHue(_hueForType(type)),
            infoWindow: InfoWindow(
              title: type,
              snippet: address.isNotEmpty
                  ? address
                  : [
                      if (provider.isNotEmpty) provider,
                      if (city.isNotEmpty) city,
                    ].join(' • '),
            ),
            onTap: () =>
                _showFacilitySheet(facility), // ✅ فتح التفاصيل + زر إبلاغ
          ),
        );

        bounds = _extendBounds(bounds, pos);
      }

      if (!mounted) return;
      setState(() {
        _facilitiesByMarkerId
          ..clear()
          ..addAll(mapFacilities);
        _markers
          ..clear()
          ..addAll(markers);
        _allMarkers
          ..clear()
          ..addAll(markers);
      });

      if (bounds != null && _markers.isNotEmpty) {
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
    }
  }

  // ===== Location =====
  Future<void> _ensureLocationPermission() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    LocationPermission permission = await Geolocator.checkPermission();
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

  // ===== Bottom sheet لتفاصيل الفاسيليتي =====
  void _showFacilitySheet(Facility f) {
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
              Text(
                f.type,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
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
                      f.provider.isEmpty
                          ? 'مزود غير محدد'
                          : f.provider, // ✅ إظهار provider
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
              const SizedBox(height: 12),
              FilledButton.icon(
                icon: const Icon(Icons.report_gmailerrorred_outlined),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                ),
                onPressed: () {
                  Navigator.pop(context);
                  _openReportDialog(f); // ✅ إنشاء بلاغ
                },
                label: const Text('الإبلاغ عن مشكلة'),
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
        'decision': 'pending', // في انتظار مراجعة الأدمن
        'description': description,
        'type': type,
        'facilityID': facility.id,
        'reportedBy': uid,
        'managedBy': '', // يملؤها الأدمن لاحقًا
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;

      // ✅ بعد الإرسال بنجاح، نعرض بوب-أب شكر
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

              // Header + Search
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                  child: Column(
                    children: [
                      const _Header(points: 1500),
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

              // لوجند بسيط
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
                      Icon(Icons.place, size: 18, color: Colors.purple),
                      SizedBox(width: 6),
                      Text(
                        'حاوية الملابس / RVM',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
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
                                final t = m.infoWindow.title ?? '';
                                return allowed.isEmpty || allowed.contains(t);
                              }),
                            );
                        });
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

class _Header extends StatelessWidget {
  final int points;
  const _Header({required this.points});

  @override
  Widget build(BuildContext context) {
    return Container(
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
              child: const CircleAvatar(
                radius: 18,
                backgroundColor: Colors.transparent,
                child: Icon(
                  Icons.person_outline,
                  color: AppColors.primary,
                  size: 22,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'مرحبًا، Nameer',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
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
              children: const [
                Icon(Icons.stars_rounded, color: Colors.white, size: 18),
                SizedBox(width: 6),
                Text(
                  '1500',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                  ),
                ),
                SizedBox(width: 4),
                Text(
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
