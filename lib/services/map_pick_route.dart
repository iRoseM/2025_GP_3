import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:google_place_plus/google_place_plus.dart';
import 'package:geolocator/geolocator.dart';

class MapRoutePickResult {
  final LatLng start;
  final LatLng end;
  MapRoutePickResult(this.start, this.end);
}

class MapPickRoutePage extends StatefulWidget {
  final LatLng? initialStart;
  final LatLng? initialEnd;
  final String googleApiKey; // ✅ مفتاح Places

  const MapPickRoutePage({
    super.key,
    this.initialStart,
    this.initialEnd,
    required this.googleApiKey,
  });

  @override
  State<MapPickRoutePage> createState() => _MapPickRoutePageState();
}

class _MapPickRoutePageState extends State<MapPickRoutePage> {
  // افتراضي الرياض لو ما قدرنا نجيب GPS
  static const _riyadhCenter = LatLng(24.7136, 46.6753);

  GoogleMapController? _controller;

  // نقاط المسار
  LatLng? _start;
  LatLng? _end;

  // نصوص البحث
  final _startController = TextEditingController();
  final _endController = TextEditingController();

  // Google Places
  late GooglePlace _places;
  final _debounce = _Debouncer(const Duration(milliseconds: 280));
  List<AutocompletePrediction> _startPreds = [];
  List<AutocompletePrediction> _endPreds = [];
  String? _sessionStart;
  String? _sessionEnd;

  // مركز التحيّز للبحث (location bias)
  LatLng _biasCenter = _riyadhCenter;
  static const int _biasRadiusMeters = 5000;

  // نقطة بداية الكاميرا
  LatLng _cameraStart = _riyadhCenter;
  bool _gotGpsOnce = false;

  @override
  void initState() {
    super.initState();
    _places = GooglePlace(widget.googleApiKey);
    _start = widget.initialStart;
    _end = widget.initialEnd;
    _sessionStart = _newSessionToken();
    _sessionEnd = _newSessionToken();

    _initGpsAndCenter();
  }

  @override
  void dispose() {
    _startController.dispose();
    _endController.dispose();
    _debounce.dispose();
    super.dispose();
  }

  // ===== GPS & تمركز أولي =====
  Future<void> _initGpsAndCenter() async {
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
        _gotGpsOnce = true;
        setState(() {
          _cameraStart = here;
          _biasCenter = here;
        });
        if (_controller != null) {
          unawaited(_moveCameraTo(here, zoom: 16.5));
        }
      }
    } catch (_) {}
  }

  // ===== Helpers =====
  String _newSessionToken() {
    final r = math.Random();
    return List.generate(24, (_) => r.nextInt(16).toRadixString(16)).join();
  }

  double _deg2rad(double deg) => deg * math.pi / 180.0;
  double _haversineKm(LatLng a, LatLng b) {
    const R = 6371.0;
    final dLat = _deg2rad(b.latitude - a.latitude);
    final dLon = _deg2rad(b.longitude - a.longitude);
    final la1 = _deg2rad(a.latitude);
    final la2 = _deg2rad(b.latitude);
    final h =
        (math.sin(dLat / 2) * math.sin(dLat / 2)) +
        (math.cos(la1) *
            math.cos(la2) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2));
    return 2 * R * math.atan2(math.sqrt(h), math.sqrt(1 - h));
  }

  Future<void> _moveCameraTo(LatLng pos, {double zoom = 17.8}) async {
    await _controller?.animateCamera(
      CameraUpdate.newCameraPosition(CameraPosition(target: pos, zoom: zoom)),
    );
  }

  Future<void> _fitBoth() async {
    if (_start == null || _end == null || _controller == null) return;
    final sw = LatLng(
      math.min(_start!.latitude, _end!.latitude),
      math.min(_start!.longitude, _end!.longitude),
    );
    final ne = LatLng(
      math.max(_start!.latitude, _end!.latitude),
      math.max(_start!.longitude, _end!.longitude),
    );
    final bounds = LatLngBounds(southwest: sw, northeast: ne);
    await _controller!.animateCamera(CameraUpdate.newLatLngBounds(bounds, 60));
  }

  // 🚀 قفزة دقيقة إلى إحداثيات المكان نفسه + ماركر + زوم عالي
  Future<void> _goToExact({
    required LatLng pos,
    required String which, // 'start' أو 'end'
    required String labelForTextField,
  }) async {
    setState(() {
      if (which == 'start') {
        _start = pos;
        _startController.text = labelForTextField;
      } else {
        _end = pos;
        _endController.text = labelForTextField;
      }
      _biasCenter = pos;
    });

    // زوم قوي مباشرة (ونعرض InfoWindow)
    await _moveCameraTo(pos, zoom: 17.8);
    await Future.delayed(const Duration(milliseconds: 90));
    _controller?.showMarkerInfoWindow(MarkerId(which));
  }

  // 🔎 بحث نصّي مباشر لو ما اخترت من الاقتراحات
  // 🔎 بحث نصّي مباشر بالاعتماد على Autocomplete + Details (بدون TextSearchRequest)
  Future<void> _searchByTextAndGo({
    required String query,
    required String which, // 'start' أو 'end'
  }) async {
    if (query.trim().isEmpty) return;

    try {
      final ac = await _places.autocomplete.get(
        query,
        language: 'ar',
        components: [Component('country', 'sa')],
        location: LatLon(_biasCenter.latitude, _biasCenter.longitude),
        radius: _biasRadiusMeters,
        sessionToken: (which == 'start') ? _sessionStart : _sessionEnd,
      );

      final preds = ac?.predictions ?? const <AutocompletePrediction>[];
      if (preds.isEmpty) return;

      final first = preds.first;
      final det = await _places.details.get(
        first.placeId!,
        language: 'ar',
        sessionToken: (which == 'start') ? _sessionStart : _sessionEnd,
      );

      final loc = det?.result?.geometry?.location;
      if (loc == null) return;

      final pos = LatLng(loc.lat!, loc.lng!);
      final label = det?.result?.name ?? first.description ?? 'موقع مختار';

      await _goToExact(pos: pos, which: which, labelForTextField: label);

      if (which == 'start') {
        _sessionStart = _newSessionToken();
        setState(() => _startPreds = []);
      } else {
        _sessionEnd = _newSessionToken();
        setState(() => _endPreds = []);
      }

      if (_start != null && _end != null) {
        await _fitBoth();
      }
    } catch (_) {}
  }

  // اسم ودّي لموقع (lat,lng) بدون إحداثيات صِرفة
  Future<String> _nameForLatLng(LatLng p) async {
    try {
      final res = await _places.search.getNearBySearch(
        Location(lat: p.latitude, lng: p.longitude),
        80,
        language: 'ar',
      );
      final first = res?.results?.firstWhere(
        (r) => (r.name ?? '').isNotEmpty,
        orElse: () => (res?.results?.isNotEmpty ?? false)
            ? res!.results!.first
            : null as dynamic,
      );
      final name = first?.name ?? first?.vicinity;
      if (name != null && name.trim().isNotEmpty) return name;
    } catch (_) {}
    return 'الموقع على الخريطة';
  }

  // ======= Places Autocomplete (متحيز حول _biasCenter) =======
  void _onStartChanged(String value) {
    _debounce.run(() async {
      if (value.trim().isEmpty) {
        setState(() => _startPreds = []);
        return;
      }
      final res = await _places.autocomplete.get(
        value,
        language: 'ar',
        components: [Component('country', 'sa')],
        sessionToken: _sessionStart,
        location: LatLon(_biasCenter.latitude, _biasCenter.longitude),
        radius: _biasRadiusMeters,
      );
      setState(() => _startPreds = res?.predictions ?? []);
    });
  }

  void _onEndChanged(String value) {
    _debounce.run(() async {
      if (value.trim().isEmpty) {
        setState(() => _endPreds = []);
        return;
      }
      final res = await _places.autocomplete.get(
        value,
        language: 'ar',
        components: [Component('country', 'sa')],
        sessionToken: _sessionEnd,
        location: LatLon(_biasCenter.latitude, _biasCenter.longitude),
        radius: _biasRadiusMeters,
      );
      setState(() => _endPreds = res?.predictions ?? []);
    });
  }

  Future<void> _pickStartFromPrediction(AutocompletePrediction p) async {
    final det = await _places.details.get(
      p.placeId!,
      language: 'ar',
      sessionToken: _sessionStart,
    );
    final loc = det?.result?.geometry?.location;
    if (loc == null) return;
    final pos = LatLng(loc.lat!, loc.lng!);

    // نستخدم اسم المكان (أسهل لليوزر)
    final label = det?.result?.name ?? p.description ?? 'موقع مختار';
    _sessionStart = _newSessionToken();
    setState(() => _startPreds = []);

    // viewport لو موجود بيستعمله Google، لكن نجبر بعدها على موقع دقيق وزوم قوي
    final vp = det?.result?.geometry?.viewport;
    if (vp != null && _controller != null) {
      final bounds = LatLngBounds(
        southwest: LatLng(vp.southwest!.lat!, vp.southwest!.lng!),
        northeast: LatLng(vp.northeast!.lat!, vp.northeast!.lng!),
      );
      await _controller!.animateCamera(
        CameraUpdate.newLatLngBounds(bounds, 50),
      );
      await Future.delayed(const Duration(milliseconds: 60));
    }
    await _goToExact(pos: pos, which: 'start', labelForTextField: label);

    if (_end != null) _fitBoth();
  }

  Future<void> _pickEndFromPrediction(AutocompletePrediction p) async {
    final det = await _places.details.get(
      p.placeId!,
      language: 'ar',
      sessionToken: _sessionEnd,
    );
    final loc = det?.result?.geometry?.location;
    if (loc == null) return;
    final pos = LatLng(loc.lat!, loc.lng!);

    final label = det?.result?.name ?? p.description ?? 'موقع مختار';
    _sessionEnd = _newSessionToken();
    setState(() => _endPreds = []);

    final vp = det?.result?.geometry?.viewport;
    if (vp != null && _controller != null) {
      final bounds = LatLngBounds(
        southwest: LatLng(vp.southwest!.lat!, vp.southwest!.lng!),
        northeast: LatLng(vp.northeast!.lat!, vp.northeast!.lng!),
      );
      await _controller!.animateCamera(
        CameraUpdate.newLatLngBounds(bounds, 50),
      );
      await Future.delayed(const Duration(milliseconds: 60));
    }
    await _goToExact(pos: pos, which: 'end', labelForTextField: label);

    if (_start != null) _fitBoth();
  }

  // ===== واجهة =====
  @override
  Widget build(BuildContext context) {
    final markers = <Marker>{};
    if (_start != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('start'),
          position: _start!,
          infoWindow: const InfoWindow(title: 'نقطة البداية'),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueGreen,
          ),
          draggable: true,
          onDragEnd: (p) async {
            final label = await _nameForLatLng(p);
            setState(() {
              _start = p;
              _startPreds = [];
              _startController.text = label;
              _biasCenter = p;
            });
          },
        ),
      );
    }
    if (_end != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('end'),
          position: _end!,
          infoWindow: const InfoWindow(title: 'نقطة النهاية'),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueAzure,
          ),
          draggable: true,
          onDragEnd: (p) async {
            final label = await _nameForLatLng(p);
            setState(() {
              _end = p;
              _endPreds = [];
              _endController.text = label;
              _biasCenter = p;
            });
          },
        ),
      );
    }

    final hasBoth = _start != null && _end != null;
    final km = hasBoth ? _haversineKm(_start!, _end!) : null;

    return Scaffold(
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: (_start ?? _end ?? _cameraStart),
              zoom: _gotGpsOnce ? 16.0 : 13.0,
            ),
            onMapCreated: (c) {
              _controller = c;
              if (_gotGpsOnce) {
                unawaited(_moveCameraTo(_cameraStart, zoom: 16.5));
              }
            },
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            markers: markers,
            polylines: hasBoth
                ? {
                    Polyline(
                      polylineId: const PolylineId('seg'),
                      points: [_start!, _end!],
                      width: 4,
                    ),
                  }
                : {},
            onTap: (p) async {
              final label = await _nameForLatLng(p);
              setState(() {
                if (_start == null) {
                  _start = p;
                  _startController.text = label;
                  _startPreds = [];
                } else if (_end == null) {
                  _end = p;
                  _endController.text = label;
                  _endPreds = [];
                } else {
                  final dStart = _haversineKm(_start!, p);
                  final dEnd = _haversineKm(_end!, p);
                  if (dStart < dEnd) {
                    _start = p;
                    _startController.text = label;
                    _startPreds = [];
                  } else {
                    _end = p;
                    _endController.text = label;
                    _endPreds = [];
                  }
                }
                _biasCenter = p;
              });
            },
            onCameraIdle: () async {
              try {
                final vr = await _controller?.getVisibleRegion();
                if (vr != null) {
                  final center = LatLng(
                    (vr.southwest.latitude + vr.northeast.latitude) / 2,
                    (vr.southwest.longitude + vr.northeast.longitude) / 2,
                  );
                  _biasCenter = center;
                }
              } catch (_) {}
            },
          ),

          // 🔹 زر الرجوع
          Positioned(
            top: 45,
            right: 12,
            child: Material(
              color: Colors.white.withOpacity(0.9),
              borderRadius: BorderRadius.circular(50),
              child: IconButton(
                icon: const Icon(Icons.arrow_forward_ios_rounded),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ),

          // 🔹 زر تبديل البداية/النهاية
          Positioned(
            top: 45,
            left: 12,
            child: Material(
              color: Colors.white.withOpacity(0.9),
              borderRadius: BorderRadius.circular(50),
              child: IconButton(
                icon: const Icon(Icons.swap_vert_rounded),
                tooltip: 'تبديل البداية والنهاية',
                onPressed: () {
                  setState(() {
                    final tmp = _start;
                    _start = _end;
                    _end = tmp;
                    final t2 = _startController.text;
                    _startController.text = _endController.text;
                    _endController.text = t2;
                  });
                  _fitBoth();
                },
              ),
            ),
          ),

          // 🔹 خانات البحث + اقتراحات
          Positioned(
            top: 90,
            left: 16,
            right: 16,
            child: Column(
              children: [
                _SearchField(
                  hint: 'ابحث عن نقطة البداية',
                  controller: _startController,
                  color: Colors.green,
                  onChanged: _onStartChanged,
                  onClear: () {
                    setState(() {
                      _startPreds = [];
                      _startController.clear();
                      _start = null;
                    });
                  },
                  onSubmitted: (txt) async {
                    if (_startPreds.isNotEmpty) {
                      await _pickStartFromPrediction(_startPreds.first);
                    } else {
                      // 🔁 ما في اقتراحات؟ جرّب Text Search مباشرة
                      await _searchByTextAndGo(query: txt, which: 'start');
                    }
                  },
                ),
                _PredictionsList(
                  preds: _startPreds,
                  onPick: _pickStartFromPrediction,
                  colorDot: Colors.green,
                ),
                const SizedBox(height: 10),
                _SearchField(
                  hint: 'ابحث عن نقطة النهاية',
                  controller: _endController,
                  color: Colors.blue,
                  onChanged: _onEndChanged,
                  onClear: () {
                    setState(() {
                      _endPreds = [];
                      _endController.clear();
                      _end = null;
                    });
                  },
                  onSubmitted: (txt) async {
                    if (_endPreds.isNotEmpty) {
                      await _pickEndFromPrediction(_endPreds.first);
                    } else {
                      await _searchByTextAndGo(query: txt, which: 'end');
                    }
                  },
                ),
                _PredictionsList(
                  preds: _endPreds,
                  onPick: _pickEndFromPrediction,
                  colorDot: Colors.blue,
                ),
              ],
            ),
          ),

          if (hasBoth)
            Positioned(
              bottom: 96,
              left: 16,
              right: 16,
              child: _HintCard(
                text: 'المسافة التقريبية: ${km!.toStringAsFixed(2)} كم',
              ),
            ),

          // 🔹 زر اعتماد
          Positioned(
            bottom: 20,
            left: 16,
            right: 16,
            child: ElevatedButton.icon(
              onPressed: hasBoth
                  ? () => Navigator.pop(
                      context,
                      MapRoutePickResult(_start!, _end!),
                    )
                  : null,
              icon: const Icon(Icons.check_circle_outline),
              label: Text(
                hasBoth ? 'اعتماد المسار' : 'اختر البداية ثم النهاية',
                style: GoogleFonts.ibmPlexSansArabic(
                  fontWeight: FontWeight.w700,
                ),
              ),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ],
      ),

      // 🔹 أزرار عائمة (مرفوعة شوي وتصغير Reset)
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 72),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FloatingActionButton.small(
              heroTag: 'center_me',
              onPressed: () async {
                try {
                  var perm = await Geolocator.checkPermission();
                  if (perm == LocationPermission.denied ||
                      perm == LocationPermission.deniedForever) {
                    perm = await Geolocator.requestPermission();
                  }
                  final pos = await Geolocator.getCurrentPosition(
                    desiredAccuracy: LocationAccuracy.high,
                  );
                  final here = LatLng(pos.latitude, pos.longitude);
                  setState(() {
                    _biasCenter = here;
                  });
                  unawaited(_moveCameraTo(here, zoom: 16.5));
                } catch (_) {}
              },
              tooltip: 'موقعي الحالي',
              child: const Icon(Icons.my_location),
            ),
            const SizedBox(height: 14),
            if (_start != null || _end != null)
              FloatingActionButton.small(
                heroTag: 'reset_points',
                backgroundColor: Colors.red.shade400,
                onPressed: () => setState(() {
                  _start = null;
                  _end = null;
                  _startController.clear();
                  _endController.clear();
                  _startPreds = [];
                  _endPreds = [];
                }),
                tooltip: 'إعادة تعيين',
                child: const Icon(Icons.clear),
              ),
          ],
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }
}

// ------------------- Widgets -------------------

class _SearchField extends StatefulWidget {
  final String hint;
  final TextEditingController controller;
  final Color color;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final ValueChanged<String>? onSubmitted;

  const _SearchField({
    required this.hint,
    required this.controller,
    required this.color,
    required this.onChanged,
    required this.onClear,
    this.onSubmitted,
  });

  @override
  State<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<_SearchField> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onCtl);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onCtl);
    super.dispose();
  }

  void _onCtl() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final hasText = widget.controller.text.isNotEmpty;
    return Material(
      elevation: 3,
      borderRadius: BorderRadius.circular(12),
      child: TextField(
        controller: widget.controller,
        textInputAction: TextInputAction.search,
        onChanged: widget.onChanged,
        onSubmitted: widget.onSubmitted,
        decoration: InputDecoration(
          hintText: widget.hint,
          prefixIcon: Icon(Icons.search, color: widget.color),
          suffixIcon: hasText
              ? IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: widget.onClear,
                )
              : null,
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 10,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }
}

class _PredictionsList extends StatelessWidget {
  final List<AutocompletePrediction> preds;
  final Future<void> Function(AutocompletePrediction) onPick;
  final Color colorDot;

  const _PredictionsList({
    required this.preds,
    required this.onPick,
    required this.colorDot,
  });

  @override
  Widget build(BuildContext context) {
    if (preds.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(top: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6)],
      ),
      child: ListView.separated(
        shrinkWrap: true,
        itemCount: preds.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (ctx, i) {
          final p = preds[i];
          return ListTile(
            leading: Icon(Icons.place_rounded, color: colorDot),
            title: Text(
              p.structuredFormatting?.mainText ?? p.description ?? '',
            ),
            subtitle: Text(p.structuredFormatting?.secondaryText ?? ''),
            onTap: () => onPick(p),
          );
        },
      ),
    );
  }
}

class _HintCard extends StatelessWidget {
  final String text;
  const _HintCard({required this.text});
  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 2,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(text, textAlign: TextAlign.center),
      ),
    );
  }
}

// ====== Debouncer بسيط ======
class _Debouncer {
  final Duration delay;
  Timer? _t;
  _Debouncer(this.delay);
  void run(VoidCallback f) {
    _t?.cancel();
    _t = Timer(delay, f);
  }

  void dispose() => _t?.cancel();
}
