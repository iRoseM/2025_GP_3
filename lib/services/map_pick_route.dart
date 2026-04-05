import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';

// ─── Models ───────────────────────────────────────────────────────────────────

class MapRoutePickResult {
  final LatLng start;
  final LatLng end;
  final String startName;
  final String endName;
  final double distanceKm;

  MapRoutePickResult({
    required this.start,
    required this.end,
    required this.startName,
    required this.endName,
    required this.distanceKm,
  });
}

class _Station {
  final String id;
  final String nameAr;
  final String nameEn;
  final LatLng position;

  const _Station({
    required this.id,
    required this.nameAr,
    required this.nameEn,
    required this.position,
  });

  factory _Station.fromJson(Map<String, dynamic> j) => _Station(
        id: j['id']?.toString() ?? '',
        nameAr: j['name_ar']?.toString() ?? '',
        nameEn: j['name_en']?.toString() ?? '',
        position: LatLng(
          (j['lat'] as num).toDouble(),
          (j['lng'] as num).toDouble(),
        ),
      );
}

// ─── Page ─────────────────────────────────────────────────────────────────────

/// [stationType] = 'metro' | 'bus'
class MapPickRoutePage extends StatefulWidget {
  final String stationType;
  final LatLng? initialStart;
  final LatLng? initialEnd;

  const MapPickRoutePage({
    super.key,
    required this.stationType,
    this.initialStart,
    this.initialEnd,
  });

  @override
  State<MapPickRoutePage> createState() => _MapPickRoutePageState();
}

class _MapPickRoutePageState extends State<MapPickRoutePage> {
  static const _riyadhCenter = LatLng(24.7136, 46.6753);

  GoogleMapController? _mapController;

  // المحطات المحمّلة من JSON
  List<_Station> _stations = [];
  bool _loadingStations = true;

  // المحطتان المختارتان
  _Station? _startStation;
  _Station? _endStation;

  // موقع المستخدم الحالي
  LatLng _userLocation = _riyadhCenter;
  bool _gotGps = false;

  // حالة الاختيار: 0 = ننتظر البداية, 1 = ننتظر النهاية
  int _pickStep = 0;

  @override
  void initState() {
    super.initState();
    _loadStations();
    _initGps();
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  // ─── Load stations from assets ────────────────────────────────────────────

  Future<void> _loadStations() async {
    final path = widget.stationType == 'metro'
        ? 'assets/data/metro_stations.json'
        : 'assets/data/bus_stations.json';

    try {
      final raw = await rootBundle.loadString(path);
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final list = (json['stations'] as List)
          .map((e) => _Station.fromJson(e as Map<String, dynamic>))
          .toList();

      if (mounted) setState(() { _stations = list; _loadingStations = false; });
    } catch (e) {
      debugPrint('❌ Error loading stations: $e');
      if (mounted) setState(() => _loadingStations = false);
    }
  }

  // ─── GPS ──────────────────────────────────────────────────────────────────

  Future<void> _initGps() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.whileInUse ||
          perm == LocationPermission.always) {
        final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        );
        final here = LatLng(pos.latitude, pos.longitude);
        if (mounted) setState(() { _userLocation = here; _gotGps = true; });
        _mapController?.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(target: here, zoom: 13.0),
          ),
        );
      }
    } catch (e) {
      debugPrint('GPS error: $e');
    }
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────

  double _haversineKm(LatLng a, LatLng b) {
    const R = 6371.0;
    final dLat = _deg2rad(b.latitude - a.latitude);
    final dLon = _deg2rad(b.longitude - a.longitude);
    final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_deg2rad(a.latitude)) *
            math.cos(_deg2rad(b.latitude)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return 2 * R * math.atan2(math.sqrt(h), math.sqrt(1 - h));
  }

  double _deg2rad(double d) => d * math.pi / 180.0;

  void _fitBoth() {
    if (_startStation == null || _endStation == null || _mapController == null) return;
    final a = _startStation!.position;
    final b = _endStation!.position;
    final sw = LatLng(math.min(a.latitude, b.latitude), math.min(a.longitude, b.longitude));
    final ne = LatLng(math.max(a.latitude, b.latitude), math.max(a.longitude, b.longitude));
    _mapController!.animateCamera(
      CameraUpdate.newLatLngBounds(LatLngBounds(southwest: sw, northeast: ne), 80),
    );
  }

  // ─── Station tap ──────────────────────────────────────────────────────────

  void _onStationTap(_Station station) {
    if (_pickStep == 0) {
      // اختيار البداية
      setState(() {
        _startStation = station;
        _endStation = null; // reset النهاية عند تغيير البداية
        _pickStep = 1;
      });
      _mapController?.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: station.position, zoom: 14.5),
        ),
      );
    } else {
      // اختيار النهاية
      if (station.id == _startStation?.id) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'اختر محطة مختلفة عن البداية',
              style: GoogleFonts.ibmPlexSansArabic(),
            ),
            duration: const Duration(seconds: 2),
          ),
        );
        return;
      }
      setState(() {
        _endStation = station;
        _pickStep = 2;
      });
      Future.delayed(const Duration(milliseconds: 200), _fitBoth);
    }
  }

  // ─── Build markers ────────────────────────────────────────────────────────

  Set<Marker> _buildMarkers() {
    final markers = <Marker>{};

    for (final station in _stations) {
      final isStart = station.id == _startStation?.id;
      final isEnd = station.id == _endStation?.id;

      // لون الـ pin حسب الحالة
      double hue;
      if (isStart) {
        hue = BitmapDescriptor.hueGreen;
      } else if (isEnd) {
        hue = BitmapDescriptor.hueAzure;
      } else {
        hue = widget.stationType == 'metro'
            ? BitmapDescriptor.hueViolet
            : BitmapDescriptor.hueOrange;
      }

      markers.add(
        Marker(
          markerId: MarkerId(station.id),
          position: station.position,
          icon: BitmapDescriptor.defaultMarkerWithHue(hue),
          infoWindow: InfoWindow(
            title: station.nameAr,
            snippet: isStart
                ? '🟢 محطة البداية'
                : isEnd
                    ? '🔵 محطة النهاية'
                    : 'اضغط للاختيار',
          ),
          onTap: () => _onStationTap(station),
          zIndex: (isStart || isEnd) ? 2.0 : 1.0,
        ),
      );
    }

    return markers;
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final hasBoth = _startStation != null && _endStation != null;
    final km = hasBoth
        ? _haversineKm(_startStation!.position, _endStation!.position)
        : null;

    final isMetro = widget.stationType == 'metro';
    final typeColor = isMetro ? const Color(0xFF7B2FBE) : const Color(0xFFF4A340);
    final typeLabel = isMetro ? 'مترو' : 'باص';

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: Stack(
          children: [
            // ─── الخريطة ────────────────────────────────────────────────────
            GoogleMap(
              initialCameraPosition: CameraPosition(
                target: _userLocation,
                zoom: _gotGps ? 13.0 : 11.5,
              ),
              onMapCreated: (c) {
                _mapController = c;
                if (_gotGps) {
                  c.animateCamera(CameraUpdate.newCameraPosition(
                    CameraPosition(target: _userLocation, zoom: 13.0),
                  ));
                }
              },
              myLocationEnabled: true,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              markers: _loadingStations ? {} : _buildMarkers(),
              polylines: hasBoth
                  ? {
                      Polyline(
                        polylineId: const PolylineId('route'),
                        points: [
                          _startStation!.position,
                          _endStation!.position,
                        ],
                        color: typeColor,
                        width: 4,
                        patterns: [PatternItem.dash(20), PatternItem.gap(10)],
                      ),
                    }
                  : {},
            ),

            // ─── Loading overlay ──────────────────────────────────────────
            if (_loadingStations)
              Container(
                color: Colors.black.withOpacity(0.3),
                child: const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
              ),

            // ─── زر الرجوع ───────────────────────────────────────────────
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              right: 12,
              child: _MapButton(
                icon: Icons.arrow_forward_ios_rounded,
                onTap: () => Navigator.pop(context),
              ),
            ),

            // ─── زر موقعي الحالي ─────────────────────────────────────────
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              left: 12,
              child: _MapButton(
                icon: Icons.my_location_rounded,
                onTap: () {
                  if (_gotGps) {
                    _mapController?.animateCamera(
                      CameraUpdate.newCameraPosition(
                        CameraPosition(target: _userLocation, zoom: 14.0),
                      ),
                    );
                  }
                },
              ),
            ),

            // ─── Step indicator + selected stations card ──────────────────
            Positioned(
              top: MediaQuery.of(context).padding.top + 64,
              left: 12,
              right: 12,
              child: _StepCard(
                step: _pickStep,
                typeLabel: typeLabel,
                typeColor: typeColor,
                startStation: _startStation,
                endStation: _endStation,
                onResetStart: () => setState(() {
                  _startStation = null;
                  _endStation = null;
                  _pickStep = 0;
                }),
                onResetEnd: () => setState(() {
                  _endStation = null;
                  _pickStep = 1;
                }),
              ),
            ),

            // ─── Distance hint ────────────────────────────────────────────
            if (hasBoth)
              Positioned(
                bottom: 100,
                left: 16,
                right: 16,
                child: _HintCard(
                  text: 'المسافة بين المحطتين: ${km!.toStringAsFixed(2)} كم',
                  color: typeColor,
                ),
              ),

            // ─── زر اعتماد ───────────────────────────────────────────────
            Positioned(
              bottom: 24,
              left: 16,
              right: 16,
              child: _ConfirmButton(
                enabled: hasBoth,
                typeColor: typeColor,
                label: hasBoth
                    ? 'اعتماد المسار'
                    : _pickStep == 0
                        ? 'اضغط على محطة البداية'
                        : 'اضغط على محطة النهاية',
                onTap: hasBoth
                    ? () => Navigator.pop(
                          context,
                          MapRoutePickResult(
                            start: _startStation!.position,
                            end: _endStation!.position,
                            startName: _startStation!.nameAr,
                            endName: _endStation!.nameAr,
                            distanceKm: km!,
                          ),
                        )
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Helper Widgets ───────────────────────────────────────────────────────────

class _MapButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _MapButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(50),
      elevation: 3,
      child: InkWell(
        borderRadius: BorderRadius.circular(50),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, size: 22),
        ),
      ),
    );
  }
}

class _StepCard extends StatelessWidget {
  final int step;
  final String typeLabel;
  final Color typeColor;
  final _Station? startStation;
  final _Station? endStation;
  final VoidCallback onResetStart;
  final VoidCallback onResetEnd;

  const _StepCard({
    required this.step,
    required this.typeLabel,
    required this.typeColor,
    required this.startStation,
    required this.endStation,
    required this.onResetStart,
    required this.onResetEnd,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // ─── العنوان
            Row(
              children: [
                Icon(
                  typeLabel == 'مترو'
                      ? Icons.train_rounded
                      : Icons.directions_bus_rounded,
                  color: typeColor,
                  size: 20,
                ),
                const SizedBox(width: 6),
                Text(
                  'اختر محطات $typeLabel',
                  style: GoogleFonts.ibmPlexSansArabic(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: const Color(0xFF3C3C3B),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // ─── Step indicator
            Row(
              children: [
                _StepDot(
                  number: '1',
                  label: 'البداية',
                  done: startStation != null,
                  active: step == 0,
                  color: Colors.green,
                ),
                Expanded(
                  child: Container(
                    height: 2,
                    margin: const EdgeInsets.symmetric(horizontal: 6),
                    color: startStation != null
                        ? Colors.green
                        : Colors.grey.shade300,
                  ),
                ),
                _StepDot(
                  number: '2',
                  label: 'النهاية',
                  done: endStation != null,
                  active: step == 1,
                  color: Colors.blue,
                ),
              ],
            ),

            // ─── محطة البداية المختارة
            if (startStation != null) ...[
              const SizedBox(height: 10),
              _SelectedChip(
                label: startStation!.nameAr,
                icon: Icons.radio_button_checked,
                color: Colors.green,
                onClear: onResetStart,
              ),
            ],

            // ─── محطة النهاية المختارة
            if (endStation != null) ...[
              const SizedBox(height: 6),
              _SelectedChip(
                label: endStation!.nameAr,
                icon: Icons.location_on_rounded,
                color: Colors.blue,
                onClear: onResetEnd,
              ),
            ],

            // ─── تعليمة
            if (startStation == null || endStation == null) ...[
              const SizedBox(height: 8),
              Text(
                step == 0
                    ? '🟢 اضغط على محطة البداية من الخريطة'
                    : '🔵 اضغط على محطة النهاية',
                style: GoogleFonts.ibmPlexSansArabic(
                  fontSize: 12.5,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StepDot extends StatelessWidget {
  final String number;
  final String label;
  final bool done;
  final bool active;
  final Color color;

  const _StepDot({
    required this.number,
    required this.label,
    required this.done,
    required this.active,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: done || active ? color : Colors.grey.shade200,
          ),
          child: Center(
            child: done
                ? const Icon(Icons.check, color: Colors.white, size: 14)
                : Text(
                    number,
                    style: TextStyle(
                      color: active ? Colors.white : Colors.grey,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 3),
        Text(
          label,
          style: GoogleFonts.ibmPlexSansArabic(
            fontSize: 10.5,
            color: done || active ? color : Colors.grey,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _SelectedChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onClear;

  const _SelectedChip({
    required this.label,
    required this.icon,
    required this.color,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.ibmPlexSansArabic(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: color,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          GestureDetector(
            onTap: onClear,
            child: Icon(Icons.close_rounded, color: color, size: 16),
          ),
        ],
      ),
    );
  }
}

class _HintCard extends StatelessWidget {
  final String text;
  final Color color;

  const _HintCard({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 3,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.straighten_rounded, color: color, size: 18),
            const SizedBox(width: 8),
            Text(
              text,
              textAlign: TextAlign.center,
              style: GoogleFonts.ibmPlexSansArabic(
                fontWeight: FontWeight.w700,
                color: const Color(0xFF3C3C3B),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConfirmButton extends StatelessWidget {
  final bool enabled;
  final Color typeColor;
  final String label;
  final VoidCallback? onTap;

  const _ConfirmButton({
    required this.enabled,
    required this.typeColor,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: enabled ? typeColor : Colors.grey.shade300,
          borderRadius: BorderRadius.circular(14),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 15),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  enabled
                      ? Icons.check_circle_outline_rounded
                      : Icons.touch_app_rounded,
                  color: enabled ? Colors.white : Colors.grey.shade600,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: GoogleFonts.ibmPlexSansArabic(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    color: enabled ? Colors.white : Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}