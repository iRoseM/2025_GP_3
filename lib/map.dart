// lib/pages/map_page.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'home.dart';

// إذا عندك ملف ألوان مشترك، استورده بدله
class AppColors {
  static const primary = Color(0xFF009688);
  static const dark = Color(0xFF00695C);
  static const light = Color(0xFF4DB6AC);
  static const background = Color(0xFFFAFCFB);
}

class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  final Completer<GoogleMapController> _mapCtrl = Completer();
  final TextEditingController _searchCtrl = TextEditingController();

  static const _riyadh = LatLng(24.7136, 46.6753);
  static const _initZoom = 13.0;

  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};

  bool _myLocationEnabled = false;
  bool _isLoadingLocation = false;

  @override
  void initState() {
    super.initState();
    _seedDemoData();
    _ensureLocationPermission();
  }

  void _seedDemoData() {
    final m1 = Marker(
      markerId: const MarkerId('bin_1'),
      position: const LatLng(24.726, 46.680),
      infoWindow: const InfoWindow(
        title: 'حاوية تدوير - شارع العليا',
        snippet: 'بلاستيك/علب معدنية',
      ),
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
    );
    final m2 = Marker(
      markerId: const MarkerId('bin_2'),
      position: const LatLng(24.708, 46.690),
      infoWindow: const InfoWindow(
        title: 'حاوية تدوير - الحي الدبلوماسي',
        snippet: 'ورق/كرتون',
      ),
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
    );
    final m3 = Marker(
      markerId: const MarkerId('bin_3'),
      position: const LatLng(24.700, 46.660),
      infoWindow: const InfoWindow(
        title: 'حاوية تدوير - الملك عبدالله',
        snippet: 'زجاج',
      ),
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRose),
    );

    final poly = Polyline(
      polylineId: const PolylineId('route_demo'),
      width: 5,
      color: AppColors.primary,
      points: const [
        LatLng(24.726, 46.680),
        LatLng(24.715, 46.686),
        LatLng(24.708, 46.690),
        LatLng(24.705, 46.675),
        LatLng(24.700, 46.660),
      ],
    );

    _markers.addAll([m1, m2, m3]);
    _polylines.add(poly);
  }

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
    if (mounted) {
      setState(() => _myLocationEnabled = granted);
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
            tilt: 0,
            bearing: 0,
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
    final isKeyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        resizeToAvoidBottomInset: true,
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
            ),

            // Header + Search
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                child: Column(
                  children: [
                    _Header(points: 1500),
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

            // Floating buttons (right)
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
                    icon: Icons.layers_outlined,
                    tooltip: 'طبقات الخريطة',
                    onTap: () {},
                  ),
                ],
              ),
            ),

            // Mini bottom bar — يختفي عند ظهور الكيبورد
            if (!isKeyboardOpen)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    child: _MiniBottomBar(
                      onHomeTap: () {
                        // ✅ الانتقال إلى الصفحة الرئيسية
                        Navigator.of(context).pushAndRemoveUntil(
                          MaterialPageRoute(builder: (_) => const HomePage()),
                          (route) => false,
                        );
                      },
                      onCenterAction: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('بدء مهمة ميدانية من الخريطة'),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
          ],
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
        bool fPlastic = true;
        bool fPaper = true;
        bool fGlass = false;
        bool fMetal = true;

        return StatefulBuilder(
          builder: (context, setSt) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'فلاتر الحاويات',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilterChip(
                        label: const Text('بلاستيك'),
                        selected: fPlastic,
                        onSelected: (v) => setSt(() => fPlastic = v),
                      ),
                      FilterChip(
                        label: const Text('ورق/كرتون'),
                        selected: fPaper,
                        onSelected: (v) => setSt(() => fPaper = v),
                      ),
                      FilterChip(
                        label: const Text('زجاج'),
                        selected: fGlass,
                        onSelected: (v) => setSt(() => fGlass = v),
                      ),
                      FilterChip(
                        label: const Text('معادن'),
                        selected: fMetal,
                        onSelected: (v) => setSt(() => fMetal = v),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () {
                        // TODO: طبّق الفلاتر على _markers
                        Navigator.pop(context);
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
          const CircleAvatar(
            radius: 18,
            backgroundColor: Color(0x22009688),
            child: Icon(Icons.person_outline, color: AppColors.primary),
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'مرحبًا، Nameer',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(100),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.monetization_on_outlined,
                  size: 18,
                  color: Colors.white,
                ),
                const SizedBox(width: 4),
                Text(
                  '$points',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
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

class _MiniBottomBar extends StatelessWidget {
  final VoidCallback onCenterAction;
  final VoidCallback onHomeTap;
  const _MiniBottomBar({required this.onCenterAction, required this.onHomeTap});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: Container(
        height: 66,
        color: Colors.white,
        child: Row(
          children: [
            // ✅ زر البيت → HomePage
            Expanded(
              child: IconButton(
                onPressed: onHomeTap,
                icon: const Icon(Icons.home_outlined, color: Colors.black54),
              ),
            ),
            const _MiniIcon(icon: Icons.camera_alt_outlined),
            Expanded(
              child: Center(
                child: InkResponse(
                  onTap: onCenterAction,
                  radius: 40,
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: const BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.flag_outlined, color: Colors.white),
                  ),
                ),
              ),
            ),
            const _MiniIcon(icon: Icons.insert_chart_outlined),
            const _MiniIcon(icon: Icons.person_outline),
          ],
        ),
      ),
    );
  }
}

class _MiniIcon extends StatelessWidget {
  final IconData icon;
  const _MiniIcon({required this.icon});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: IconButton(
        onPressed: () {},
        icon: Icon(icon, color: Colors.black54),
      ),
    );
  }
}
