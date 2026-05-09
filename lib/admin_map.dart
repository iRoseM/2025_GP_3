// lib/pages/admin_map.dart
import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/services.dart' show rootBundle;
import 'admin_home.dart' as home;
import 'admin_task.dart';
import 'admin_reward.dart' as reward;
import 'services/admin_bottom_nav.dart';
import 'admin_reports.dart' as report;
import 'profile.dart';
import 'services/connection.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../services/app_colors.dart';

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
  Set<String> _allowedStatuses = {};

  bool _myLocationEnabled = false;
  bool _isLoadingLocation = false;

  String? _mapsApiKey;
  bool _isLoadingMapsKey = false;

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
  String? _selectedLocationType;
  bool _reportsViewed = false;
  DateTime? _lastReportsVisit;

  /// 🔔 إشعارات البلاغات الجديدة
  bool _hasNewReports = false;
  bool _isLoadingNotifications = false;
  StreamSubscription? _reportsSubscription;
  Set<String> _unreadReportIds = {};

  @override
  void initState() {
    super.initState();
    _initAdminMap();
    _loadMapsApiKey();
    _startListeningForNewReports();
  }

  @override
  void dispose() {
    _reportsSubscription?.cancel();
    _emptyTimer?.cancel();
    super.dispose();
  }

  void _startListeningForNewReports() {
    if (!mounted) return;

    setState(() => _isLoadingNotifications = true);

    debugPrint('🔔 بدء الاستماع للبلاغات الجديدة...');

    _reportsSubscription = FirebaseFirestore.instance
        .collection('facilityReports')
        .where('decision', isEqualTo: 'pending')
        .snapshots()
        .listen(
          (snapshot) {
            if (!mounted) return;

            final hasPending = snapshot.docs.isNotEmpty;

            // ✅ نتحقق: هل هناك بلاغات جديدة بعد آخر زيارة؟
            bool shouldShowNotification = false;

            if (_lastReportsVisit != null) {
              // نتفقد إذا كان هناك أي بلاغات تم إنشاؤها بعد آخر زيارة
              bool hasNewReportsAfterVisit = false;
              for (final doc in snapshot.docs) {
                final timestamp = doc['createdAt'] as Timestamp?;
                if (timestamp != null) {
                  final reportTime = timestamp.toDate();
                  if (reportTime.isAfter(_lastReportsVisit!)) {
                    hasNewReportsAfterVisit = true;
                    break;
                  }
                }
              }
              shouldShowNotification = hasNewReportsAfterVisit;
            } else {
              // إذا لم نزُر التقارير مطلقاً، نعرض النقطة
              shouldShowNotification = hasPending;
            }

            debugPrint(
              '🔔 هناك ${snapshot.docs.length} بلاغ pending، '
              'آخر زيارة: $_lastReportsVisit، '
              'نعرض الإشعار: $shouldShowNotification',
            );

            setState(() {
              _hasNewReports = shouldShowNotification;
              _isLoadingNotifications = false;
            });

            if (shouldShowNotification) {
              debugPrint('🔔 إظهار إشعار جديد!');
            }
          },
          onError: (error) {
            debugPrint('❌ خطأ في الاستماع للبلاغات: $error');
            if (mounted) {
              setState(() => _isLoadingNotifications = false);
            }
          },
        );
  }

  // ✅ دالة لمسح البلاغات المقروءة (نستدعيها عند الدخول للتقارير)
  void _markReportsAsRead() {
    setState(() {
      _unreadReportIds.clear();
      _hasNewReports = false;
    });
    debugPrint('✅ تم مسح البلاغات غير المقروءة');
  }

  Future<void> _checkForNewReports() async {
    if (!mounted) return;

    setState(() => _isLoadingNotifications = true);

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('facilityReports')
          .where('decision', isEqualTo: 'pending')
          .get();

      final hasPending = snapshot.docs.isNotEmpty;

      bool shouldShowNotification = false;

      if (_lastReportsVisit != null) {
        // نتفقد البلاغات الجديدة بعد آخر زيارة
        bool hasNewReportsAfterVisit = false;
        for (final doc in snapshot.docs) {
          final timestamp = doc['createdAt'] as Timestamp?;
          if (timestamp != null) {
            final reportTime = timestamp.toDate();
            if (reportTime.isAfter(_lastReportsVisit!)) {
              hasNewReportsAfterVisit = true;
              break;
            }
          }
        }
        shouldShowNotification = hasNewReportsAfterVisit;
      } else {
        shouldShowNotification = hasPending;
      }

      setState(() {
        _hasNewReports = shouldShowNotification;
        _isLoadingNotifications = false;
      });

      debugPrint(
        '🔔 تفقد البلاغات: هناك $hasPending بلاغ، نعرض: $shouldShowNotification',
      );
    } catch (error) {
      debugPrint('❌ خطأ في تفقد البلاغات: $error');
      if (mounted) {
        setState(() => _isLoadingNotifications = false);
      }
    }
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
      case 'حاوية إعادة تدوير القوارير':
        return _iconDefault ?? BitmapDescriptor.defaultMarker;
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
        final String address = (m['address'] ?? '').toString();
        final String status = (m['status'] ?? 'نشط').toString();

        statusMap[d.id] = status;
        final pos = LatLng(lat, lng);

        final title = address.isNotEmpty ? address : type;

        final snippetParts = <String>[
          type,
          if (provider.isNotEmpty) provider,
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

      debugPrint(' تم تحميل ${markers.length} موقع (نشط ومتوقف) من Firestore');
    } catch (e) {
      debugPrint(' خطأ أثناء تحميل الفاسيلتيز: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: slackMesseges.red,
            content: Text(
              'تعذر تحميل المواقع من السحابة',
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
          _applyCurrentFilters();
          if (_markers.isEmpty) _flashEmptyMsg();
        });
      }
    }
  }

  void _flashEmptyMsg() {
    _emptyTimer?.cancel();
    setState(() => _showEmptyOverlay = true);
    _emptyTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _showEmptyOverlay = false);
    });
  }

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
          SnackBar(
            backgroundColor: slackMesseges.red,
            content: Text(
              'تعذّر تحديد الموقع الحالي. يرجى التحقق من إذن الموقع وGPS',
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
      setState(() {
        _tempLocation = position;
      });

      // ✅ رسالة مختصرة
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم تحديد الموقع'),
          duration: Duration(milliseconds: 800),
        ),
      );
    }
  }

  Future<void> _loadMapsApiKey() async {
    setState(() => _isLoadingMapsKey = true);
    try {
      final callable = FirebaseFunctions.instance.httpsCallable('getMapsKey');
      final result = await callable();
      final key = result.data['apiKey'] as String?;

      if (key == null || key.isEmpty) {
        debugPrint('❌ MAPS API key is empty from getMapsKey');
        return;
      }

      setState(() {
        _mapsApiKey = key;
      });
      debugPrint('✅ Loaded Maps API key from Cloud Functions');
    } catch (e) {
      debugPrint('❌ Failed to load Maps API key: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoadingMapsKey = false);
      }
    }
  }

  void _onSearchSubmitted(String query) async {
    query = query.trim();
    if (query.isEmpty) {
      if (_allMarkers.isEmpty) return;

      setState(() {
        _markers
          ..clear()
          ..addAll(_allMarkers);
      });

      final ctrl = await _mapCtrl.future;
      LatLngBounds? bounds;
      for (final m in _markers) {
        final p = m.position;
        bounds = bounds == null
            ? LatLngBounds(southwest: p, northeast: p)
            : LatLngBounds(
                southwest: LatLng(
                  p.latitude < bounds!.southwest.latitude
                      ? p.latitude
                      : bounds!.southwest.latitude,
                  p.longitude < bounds!.southwest.longitude
                      ? p.longitude
                      : bounds!.southwest.longitude,
                ),
                northeast: LatLng(
                  p.latitude > bounds!.northeast.latitude
                      ? p.latitude
                      : bounds!.northeast.latitude,
                  p.longitude > bounds!.northeast.longitude
                      ? p.longitude
                      : bounds!.northeast.longitude,
                ),
              );
      }

      if (bounds != null) {
        await ctrl.animateCamera(CameraUpdate.newLatLngBounds(bounds, 100));
      }
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

    final generic = {
      'حاويه',
      'حاويات',
      'سله',
      'سلة',
      'سلات',
      'نقطه',
      'نقطة',
      'اقرب',
      'الاقرب',
      'وين',
      'فين',
      'ابي',
      'ابغى',
      'اريد',
      'دلني',
      'دليني',
      'في',
      'فيه',
      'الحي',
    };

    final parts = normalizedQuery
        .split(' ')
        .where((x) => x.isNotEmpty)
        .toList();

    final nonGenericParts = parts
        .where((p) => !generic.contains(p) && p != 'حي')
        .toList();

    final bool queryHasAreaWord =
        query.contains('حي') ||
        query.contains('شارع') ||
        query.contains('طريق');

    String? possibleArea;
    final areaMatch = RegExp(r'(?:حي|شارع|طريق)\s*([^\s]+)').firstMatch(query);
    if (areaMatch != null && areaMatch.groupCount >= 1) {
      possibleArea = normalize(areaMatch.group(1)!);
    } else if (parts.isNotEmpty) {
      possibleArea = parts.last;
    }

    final bool isPureAreaOnlyQuery =
        queryHasAreaWord && nonGenericParts.length <= 1;

    final bool hasImplicitArea =
        !queryHasAreaWord &&
        possibleArea != null &&
        nonGenericParts.length >= 2 &&
        nonGenericParts.contains(possibleArea);

    List<String> providerTokensMain = nonGenericParts;
    if ((queryHasAreaWord || hasImplicitArea) &&
        possibleArea != null &&
        nonGenericParts.length >= 2) {
      providerTokensMain = nonGenericParts
          .where((t) => t != possibleArea)
          .toList();
    }
    if (isPureAreaOnlyQuery) {
      providerTokensMain = [];
    }

    final bool hasAnyAreaConstraint = queryHasAreaWord || hasImplicitArea;

    if (nonGenericParts.isEmpty && !hasAnyAreaConstraint) {
      if (_allMarkers.isEmpty) return;

      setState(() {
        _markers
          ..clear()
          ..addAll(_allMarkers);
      });

      final ctrl = await _mapCtrl.future;
      LatLngBounds? bounds;
      for (final m in _markers) {
        final p = m.position;
        bounds = bounds == null
            ? LatLngBounds(southwest: p, northeast: p)
            : LatLngBounds(
                southwest: LatLng(
                  p.latitude < bounds!.southwest.latitude
                      ? p.latitude
                      : bounds!.southwest.latitude,
                  p.longitude < bounds!.southwest.longitude
                      ? p.longitude
                      : bounds!.southwest.longitude,
                ),
                northeast: LatLng(
                  p.latitude > bounds!.northeast.latitude
                      ? p.latitude
                      : bounds!.northeast.latitude,
                  p.longitude > bounds!.northeast.longitude
                      ? p.longitude
                      : bounds!.northeast.longitude,
                ),
              );
      }

      if (bounds != null) {
        final ctrl = await _mapCtrl.future;
        await ctrl.animateCamera(CameraUpdate.newLatLngBounds(bounds, 100));
      }
      return;
    }

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

    for (final m in _allMarkers) {
      final text = normalize(
        '${m.infoWindow.title ?? ""} ${m.infoWindow.snippet ?? ""}',
      );

      final bool tokenMatch = providerTokensMain.isEmpty
          ? false
          : providerTokensMain.any((t) => text.contains(t));

      final bool areaMatchThisMarker =
          possibleArea != null && text.contains(possibleArea);

      bool isMatch;

      if (hasAnyAreaConstraint) {
        if (isPureAreaOnlyQuery) {
          isMatch = areaMatchThisMarker;
        } else {
          isMatch = tokenMatch && areaMatchThisMarker;
        }
      } else {
        isMatch = tokenMatch;
      }

      if (isMatch) {
        final d = Geolocator.distanceBetween(
          pos.latitude,
          pos.longitude,
          m.position.latitude,
          m.position.longitude,
        );
        matches.add({'marker': m, 'dist': d});
      }
    }

    if (matches.isNotEmpty) {
      List<Map<String, dynamic>> top;
      if (isPureAreaOnlyQuery ||
          (hasImplicitArea && providerTokensMain.isEmpty)) {
        matches.sort((a, b) => a['dist'].compareTo(b['dist']));
        top = matches.take(5).toList();
      } else {
        top = matches;
      }

      final selectedMarkers = top
          .map<Marker>((e) => e['marker'] as Marker)
          .toSet();

      setState(() {
        _markers
          ..clear()
          ..addAll(selectedMarkers);
      });

      final ctrl = await _mapCtrl.future;

      LatLngBounds? bounds;
      for (final m in selectedMarkers) {
        final p = m.position;
        bounds = bounds == null
            ? LatLngBounds(southwest: p, northeast: p)
            : LatLngBounds(
                southwest: LatLng(
                  p.latitude < bounds!.southwest.latitude
                      ? p.latitude
                      : bounds!.southwest.latitude,
                  p.longitude < bounds!.southwest.longitude
                      ? p.longitude
                      : bounds!.southwest.longitude,
                ),
                northeast: LatLng(
                  p.latitude > bounds!.northeast.latitude
                      ? p.latitude
                      : bounds!.northeast.latitude,
                  p.longitude > bounds!.northeast.longitude
                      ? p.longitude
                      : bounds!.northeast.longitude,
                ),
              );
      }

      if (bounds != null) {
        await ctrl.animateCamera(CameraUpdate.newLatLngBounds(bounds, 100));
      }

      return;
    }

    if (hasAnyAreaConstraint &&
        nonGenericParts.isNotEmpty &&
        !isPureAreaOnlyQuery) {
      final providerTokens = (possibleArea == null)
          ? nonGenericParts
          : nonGenericParts.where((t) => t != possibleArea).toList();

      if (providerTokens.isNotEmpty) {
        final List<Map<String, dynamic>> founderMatches = [];

        for (final m in _allMarkers) {
          final text = normalize(
            '${m.infoWindow.title ?? ""} ${m.infoWindow.snippet ?? ""}',
          );
          final providerMatch = providerTokens.any((t) => text.contains(t));
          if (providerMatch) {
            final d = Geolocator.distanceBetween(
              pos.latitude,
              pos.longitude,
              m.position.latitude,
              m.position.longitude,
            );
            founderMatches.add({'marker': m, 'dist': d});
          }
        }

        if (founderMatches.isNotEmpty) {
          founderMatches.sort((a, b) => a['dist'].compareTo(b['dist']));
          final selectedMarkers = founderMatches
              .map<Marker>((e) => e['marker'] as Marker)
              .toSet();

          setState(() {
            _markers
              ..clear()
              ..addAll(selectedMarkers);
          });

          final ctrl = await _mapCtrl.future;
          LatLngBounds? bounds;
          for (final m in selectedMarkers) {
            final p = m.position;
            bounds = bounds == null
                ? LatLngBounds(southwest: p, northeast: p)
                : LatLngBounds(
                    southwest: LatLng(
                      p.latitude < bounds!.southwest.latitude
                          ? p.latitude
                          : bounds!.southwest.latitude,
                      p.longitude < bounds!.southwest.longitude
                          ? p.longitude
                          : bounds!.southwest.longitude,
                    ),
                    northeast: LatLng(
                      p.latitude > bounds!.northeast.latitude
                          ? p.latitude
                          : bounds!.northeast.latitude,
                      p.longitude > bounds!.northeast.longitude
                          ? p.longitude
                          : bounds!.northeast.longitude,
                    ),
                  );
          }

          if (bounds != null) {
            await ctrl.animateCamera(CameraUpdate.newLatLngBounds(bounds, 100));
          }

          final providerLabel = providerTokens.join(' ');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'لا توجد حاويات لـ "$providerLabel" داخل الحي المحدد — تم عرض حاويات "$providerLabel" الأقرب لموقعك.',
                style: GoogleFonts.ibmPlexSansArabic(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              behavior: SnackBarBehavior.floating,
            ),
          );

          return;
        }
      }
    }

    if (_mapsApiKey == null) {
      debugPrint('⚠️ Maps API key not loaded, skipping Google Places search');
      return;
    }
    try {
      final url = Uri.parse(
        "https://maps.googleapis.com/maps/api/place/autocomplete/json"
        "?input=$query&language=ar&components=country:sa&key=$_mapsApiKey",
      );

      final response = await http.get(url);
      final data = json.decode(response.body);

      if (data["status"] == "OK" && data["predictions"].isNotEmpty) {
        final placeId = data['predictions'][0]['place_id'];

        final detailsUrl = Uri.parse(
          "https://maps.googleapis.com/maps/api/place/details/json"
          "?place_id=$placeId&key=$_mapsApiKey",
        );

        final detailsRes = await http.get(detailsUrl);
        final details = json.decode(detailsRes.body);

        final loc = details['result']['geometry']['location'];
        final lat = (loc['lat'] as num).toDouble();
        final lng = (loc['lng'] as num).toDouble();

        if (_allMarkers.isNotEmpty) {
          Marker? nearest;
          double? minDist;

          for (final m in _allMarkers) {
            final d = Geolocator.distanceBetween(
              lat,
              lng,
              m.position.latitude,
              m.position.longitude,
            );
            if (minDist == null || d < minDist) {
              minDist = d;
              nearest = m;
            }
          }

          if (nearest != null) {
            setState(() {
              _markers
                ..clear()
                ..add(nearest!);
            });

            final ctrl = await _mapCtrl.future;
            await ctrl.animateCamera(
              CameraUpdate.newLatLngZoom(nearest.position, 15),
            );
            return;
          }
        }

        final ctrl = await _mapCtrl.future;
        await ctrl.animateCamera(
          CameraUpdate.newLatLngZoom(LatLng(lat, lng), 15),
        );
        return;
      }
    } catch (_) {
      // تجاهل أي خطأ في Google Places
    }
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

              _buildEmptyStateOverlay(),

              // 🔍 شريط البحث
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      HeaderUserLive(
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const profilePage(),
                          ),
                        ),
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
              // 📄 زر التقارير
              Positioned(
                left: 8,
                bottom: 140,
                child: _NotificationButton(
                  icon: Icons.article_rounded,
                  tooltip: 'عرض التقارير',
                  hasNotification: _hasNewReports,
                  isLoading: _isLoadingNotifications,
                  onTap: () {
                    // ✅ عند الدخول للتقارير، نسجل وقت الزيارة
                    setState(() {
                      _lastReportsVisit = DateTime.now();
                      _hasNewReports = false; // نخفي النقطة الحمراء فوراً
                      _reportsViewed = true;
                    });

                    debugPrint('⏰ وقت زيارة التقارير: ${_lastReportsVisit}');

                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const report.AdminReportPage(),
                      ),
                    ).then((_) {
                      // ✅ عندما نرجع من صفحة التقارير
                      if (mounted) {
                        _checkForNewReports(); // نتفقد إذا جاءت بلاغات جديدة
                      }
                    });
                  },
                  onLongPress: () {
                    // ✅ عند الضغط الطويل، نتفقد البلاغات يدوياً
                    _checkForNewReports();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'جاري تفقد البلاغات الجديدة...',
                          style: GoogleFonts.ibmPlexSansArabic(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        duration: const Duration(seconds: 1),
                        backgroundColor: appColors.primary,
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

              // 📍 مؤقت Pin باللون الأحمر
              if (_isSelecting && _tempLocation != null)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.location_pin,
                            color: appColors.primary,
                            size: 60,
                          ),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.1),
                                  blurRadius: 8,
                                ),
                              ],
                            ),
                            child: Text(
                              'موقع محدد',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: appColors.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              // زر تأكيد
              if (_isSelecting) _buildConfirmButton(),
            ],
          ),
          bottomNavigationBar: isKeyboardOpen
              ? null
              : AdminBottomNav(currentIndex: 1, onTap: _onTap),
        ),
      ),
    );
  }

  // في _startListeningForNewReports، أضف:

  void _showFiltersBottomSheet() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) {
        final selectedTypes = Set<String>.from(_allowedTypes);
        final selectedStatuses = Set<String>.from(_allowedStatuses);

        const typeOptions = [
          'حاوية إعادة تدوير الملابس',
          'حاوية إعادة تدوير الأوراق',
          'آلة إعادة التدوير (RVM)',
          'حاوية إعادة تدوير بقايا الطعام',
          'حاوية إعادة تدوير القوارير',
        ];

        const statusOptions = {'نشط': 'نشطة', 'متوقف': 'متوقفة'};

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
                        'حسب النوع',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: appColors.dark,
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
                          selectedColor: appColors.primary.withOpacity(.15),
                          labelStyle: TextStyle(
                            color: selected
                                ? appColors.primary
                                : appColors.dark,
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

                    const SizedBox(height: 16),

                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        'حسب الحالة',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: appColors.dark,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: statusOptions.entries.map((e) {
                        final String valueInData = e.key;
                        final String label = e.value;
                        final selected = selectedStatuses.contains(valueInData);

                        return FilterChip(
                          label: Text(label),
                          selected: selected,
                          selectedColor: appColors.primary.withOpacity(.15),
                          labelStyle: TextStyle(
                            color: selected
                                ? appColors.primary
                                : appColors.dark,
                            fontWeight: FontWeight.w700,
                          ),
                          onSelected: (v) => setSt(() {
                            if (v) {
                              selectedStatuses.add(valueInData);
                            } else {
                              selectedStatuses.remove(valueInData);
                            }
                          }),
                        );
                      }).toList(),
                    ),

                    const SizedBox(height: 20),

                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: appColors.primary,
                      ),
                      onPressed: () {
                        Navigator.pop(context);
                        setState(() {
                          _allowedTypes = selectedTypes;
                          _allowedStatuses = selectedStatuses;
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
                          _allowedStatuses.clear();
                        });
                        _applyCurrentFilters();
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

  void _applyCurrentFilters() {
    setState(() {
      _markers
        ..clear()
        ..addAll(
          _allMarkers.where((m) {
            final snippet = m.infoWindow.snippet ?? '';
            final title = m.infoWindow.title ?? '';

            final matchesType =
                _allowedTypes.isEmpty ||
                _allowedTypes.any(
                  (t) => snippet.contains(t) || title.contains(t),
                );

            if (!matchesType) return false;

            if (_allowedStatuses.isEmpty) return true;

            final id = m.markerId.value;
            final st = _statusById[id] ?? 'نشط';
            return _allowedStatuses.contains(st);
          }),
        );
    });
  }

  // ✅ ميثود مساعدة للحصول على رسالة التعليمات
  String _getInstructionsMessage(
    bool isNameValid,
    bool isTypeValid,
    bool isLocationSelected,
  ) {
    final messages = <String>[];

    if (!isNameValid) messages.add('• أدخل اسم الموقع 🏷️');
    if (!isTypeValid) messages.add('• اختر نوع الحاوية ♻️');
    if (!isLocationSelected)
      messages.add('• انقر على الخريطة لتحديد الموقع 📍');

    return messages.join('\n');
  }

  // ✅ ميثود مساعدة لعرض صف المعلومات
  Widget _buildConfirmButton() {
    if (!_isSelecting) return const SizedBox.shrink();

    final bool hasLocation = _tempLocation != null;
    final bool isReady = (_lastAddedName?.isNotEmpty ?? false) && hasLocation;

    return Positioned(
      bottom: 20,
      left: 20,
      right: 20,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 20,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ✅ معلومات الموقع
            Row(
              children: [
                Icon(
                  hasLocation ? Icons.check_circle : Icons.location_on,
                  color: hasLocation ? Colors.green : Colors.blue,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _lastAddedName ?? 'موقع جديد',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (_tempLocation != null)
                        Text(
                          '${_tempLocation!.latitude.toStringAsFixed(5)}, '
                          '${_tempLocation!.longitude.toStringAsFixed(5)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // ✅ أزرار التحكم - تصميم أنيق
            Row(
              children: [
                // زر إلغاء - بسيط
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      setState(() {
                        _isSelecting = false;
                        _tempLocation = null;
                        _lastAddedName = null;
                        _lastAddedType = null;
                        _lastProvider = null;
                      });
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.grey[700],
                      side: BorderSide(color: Colors.grey[300]!),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text('إلغاء'),
                  ),
                ),

                const SizedBox(width: 12),

                // زر تأكيد - بسيط
                Expanded(
                  child: ElevatedButton(
                    onPressed: isReady ? () => _confirmLocation() : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isReady
                          ? appColors.primary
                          : Colors.grey[300],
                      foregroundColor: isReady
                          ? Colors.white
                          : Colors.grey[500],
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      elevation: 0,
                    ),
                    child: const Text('تأكيد'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmLocation() async {
    if (_tempLocation == null ||
        _lastAddedName == null ||
        _lastAddedType == null) {
      return;
    }

    debugPrint(
      '📍 تأكيد الموقع: ${_tempLocation!.latitude}, ${_tempLocation!.longitude}',
    );

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
      _lastAddedName = null;
      _lastAddedType = null;
      _lastProvider = null;
    });
  }

  void _onAddNewLocation() {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return Dialog(
          insetPadding: const EdgeInsets.fromLTRB(24, 60, 24, 100),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          child: _FacilityFormCard(
            title: 'إضافة موقع جديد',
            initialName: '',
            initialType: 'حاوية إعادة تدوير الأوراق',
            initialProvider: '',
            initialActive: true,
            onSelectOption:
                (
                  String name,
                  String type,
                  String provider,
                  bool isActive,
                  String option,
                ) async {
                  debugPrint('🎯 خيار: $option');

                  // تعيين المتغيرات
                  setState(() {
                    _lastAddedName = name.isNotEmpty ? name : 'موقع جديد';
                    _lastAddedType = type;
                    _lastProvider = provider.isNotEmpty ? provider : 'غير محدد';
                    _lastStatusStr = isActive ? 'نشط' : 'متوقف';
                    _isSelecting = true;
                  });

                  // إغلاق الـ Dialog
                  Navigator.pop(context);

                  if (option == 'موقعي الحالي') {
                    // ✅ اوتوماتيكي: مباشرة استخدام الموقع الحالي
                    await _useCurrentLocation();
                  } else if (option == 'تحديد يدوي') {
                    // ✅ إظهار رسالة مختصرة
                    _showManualSelectionMessage();
                  } else if (option == 'إحداثيات') {
                    _showCoordinatesDialog(name, type, provider, isActive);
                  }
                },
          ),
        );
      },
    );
  }

  void _showManualSelectionMessage() {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('انقر على الخريطة لتحديد الموقع'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _useCurrentLocation() async {
    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      setState(() {
        _tempLocation = LatLng(pos.latitude, pos.longitude);
      });

      final controller = await _mapCtrl.future;
      await controller.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: LatLng(pos.latitude, pos.longitude), zoom: 15),
        ),
      );

      // ✅ إظهار رسالة مختصرة
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ تم استخدام موقعك الحالي'),
            duration: Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ خطأ في الموقع الحالي: $e');
      // إذا فشل، نذهب للرياض الافتراضية
      setState(() {
        _tempLocation = _riyadh;
      });
    }
  }

  // ✅ أضف هذه الميثود في فئة _AdminMapPageState
  void _showLocationErrorDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('⚠️ خطأ في الموقع'),
        content: const Text(
          'تعذر الوصول إلى موقعك الحالي. يرجى اختيار خيار آخر لتحديد الموقع.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('حسناً'),
          ),
        ],
      ),
    );
  }

  // ✅ ميثود مساعدة لمعالجة خيار "موقعي الحالي"
  Future<void> _handleCurrentLocationOption() async {
    debugPrint('📍 محاولة الوصول للموقع الحالي...');
    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      debugPrint('📍 الموقع الحالي: ${pos.latitude}, ${pos.longitude}');

      setState(() {
        _tempLocation = LatLng(pos.latitude, pos.longitude);
      });

      final controller = await _mapCtrl.future;
      await controller.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: LatLng(pos.latitude, pos.longitude), zoom: 15),
        ),
      );

      debugPrint('✅ تم تحريك الكاميرا للموقع الحالي');

      // ✅ إظهار رسالة للمستخدم
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '✅ تم استخدام موقعك الحالي',
              style: GoogleFonts.ibmPlexSansArabic(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
            backgroundColor: Colors.teal,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ خطأ في الوصول للموقع الحالي: $e');
      _showLocationErrorDialog();
    }
  }

  // ✅ ميثود مساعدة لمعالجة خيار "تحديد يدوي"
  Future<void> _handleManualSelectionOption() async {
    debugPrint('📍 تفعيل وضع التحديد اليدوي...');

    // ✅ إظهار رسالة واضحة للمستخدم
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.touch_app, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'تم تفعيل وضع التحديد. انقر على الخريطة في أي مكان لوضع علامة الموقع',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          backgroundColor: appColors.primary,
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }

    // ✅ تحريك الكاميرا للموقع الحالي للبدء (اختياري)
    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
      );
      final controller = await _mapCtrl.future;
      await controller.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: LatLng(pos.latitude, pos.longitude), zoom: 15),
        ),
      );
      debugPrint('✅ تم تحريك الكاميرا للموقع الحالي للبدء');
    } catch (e) {
      debugPrint('⚠️ لا يمكن الوصول للموقع الحالي، تجاهل... $e');
    }

    debugPrint('📍 جاهز لتلقي النقرات على الخريطة...');
  }

  // ✅ دالة جديدة لعرض مربع حوار لإدخال الإحداثيات
  void _showCoordinatesDialog(
    String name,
    String type,
    String provider,
    bool isActive,
  ) {
    final latCtrl = TextEditingController();
    final lngCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'إدخال الإحداثيات',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: latCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'خط العرض (Latitude)',
                    hintText: 'مثال: 24.7136',
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: lngCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'خط الطول (Longitude)',
                    hintText: 'مثال: 46.6753',
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('إلغاء'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed: () {
                          final lat = double.tryParse(latCtrl.text);
                          final lng = double.tryParse(lngCtrl.text);
                          if (lat != null && lng != null) {
                            // تعيين المتغيرات المؤقتة
                            setState(() {
                              _lastAddedName = name;
                              _lastAddedType = type;
                              _lastProvider = provider.isEmpty
                                  ? 'غير محدد'
                                  : provider;
                              _lastStatusStr = isActive ? 'نشط' : 'متوقف';
                              _isSelecting = true;
                              _tempLocation = LatLng(lat, lng);
                            });

                            // تحريك الكاميرا للإحداثيات المدخلة
                            final controller = _mapCtrl.future.then((ctrl) {
                              ctrl.animateCamera(
                                CameraUpdate.newCameraPosition(
                                  CameraPosition(
                                    target: LatLng(lat, lng),
                                    zoom: 15,
                                  ),
                                ),
                              );
                            });

                            Navigator.pop(context);
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('الرجاء إدخال إحداثيات صحيحة'),
                              ),
                            );
                          }
                        },
                        child: const Text('تأكيد'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
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
        borderSide: const BorderSide(color: appColors.primary),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: appColors.primary),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: appColors.dark, width: 1.2),
      ),
    );
  }

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
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
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

                  if (provider.isNotEmpty && provider != 'غير محدد')
                    _kvRightAligned('المزود', provider),
                  if (address.isNotEmpty) _kvRightAligned('العنوان', address),

                  const Divider(height: 24),

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

  Widget _kvRightAligned(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Expanded(
            child: Text(
              v,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              textAlign: TextAlign.right,
              softWrap: true,
              overflow: TextOverflow.visible,
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
                onSelectOption:
                    (
                      String name,
                      String type,
                      String provider,
                      bool isActive,
                      String option,
                    ) async {
                      if (option == 'تحديد يدوي' || option == 'موقعي الحالي') {
                        Navigator.pop(context);
                        _lastAddedName = name;
                        _lastAddedType = type;
                        _lastProvider = provider.isEmpty
                            ? 'غير محدد'
                            : provider;
                        _lastStatusStr = isActive ? 'نشط' : 'متوقف';
                        _isSelecting = true;

                        if (option == 'موقعي الحالي') {
                          try {
                            final pos = await Geolocator.getCurrentPosition(
                              desiredAccuracy: LocationAccuracy.high,
                            );
                            setState(() {
                              _tempLocation = LatLng(
                                pos.latitude,
                                pos.longitude,
                              );
                            });
                            final controller = await _mapCtrl.future;
                            await controller.animateCamera(
                              CameraUpdate.newCameraPosition(
                                CameraPosition(
                                  target: LatLng(pos.latitude, pos.longitude),
                                  zoom: 15,
                                ),
                              ),
                            );
                          } catch (_) {
                            setState(() {
                              _tempLocation = position;
                            });
                          }
                        } else {
                          setState(() {
                            _tempLocation = position;
                          });
                        }
                      } else if (option == 'إحداثيات') {
                        // هنا سيتم التعامل مع الإحداثيات مباشرة
                        final latCtrl = TextEditingController(
                          text: position.latitude.toStringAsFixed(6),
                        );
                        final lngCtrl = TextEditingController(
                          text: position.longitude.toStringAsFixed(6),
                        );

                        showDialog(
                          context: context,
                          builder: (context) {
                            return Dialog(
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Text(
                                      'إدخال الإحداثيات',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    TextFormField(
                                      controller: latCtrl,
                                      keyboardType: TextInputType.number,
                                      decoration: const InputDecoration(
                                        labelText: 'خط العرض (Latitude)',
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    TextFormField(
                                      controller: lngCtrl,
                                      keyboardType: TextInputType.number,
                                      decoration: const InputDecoration(
                                        labelText: 'خط الطول (Longitude)',
                                      ),
                                    ),
                                    const SizedBox(height: 20),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: TextButton(
                                            onPressed: () =>
                                                Navigator.pop(context),
                                            child: const Text('إلغاء'),
                                          ),
                                        ),
                                        Expanded(
                                          child: FilledButton(
                                            onPressed: () async {
                                              final lat = double.tryParse(
                                                latCtrl.text,
                                              );
                                              final lng = double.tryParse(
                                                lngCtrl.text,
                                              );
                                              if (lat != null && lng != null) {
                                                await FirebaseFirestore.instance
                                                    .collection('facilities')
                                                    .doc(markerId.value)
                                                    .set({
                                                      'address':
                                                          name.trim().isEmpty
                                                          ? 'عنوان غير محدد'
                                                          : name.trim(),
                                                      'type': _normalizeType(
                                                        type,
                                                      ),
                                                      'lat': lat,
                                                      'lng': lng,
                                                      'provider':
                                                          provider
                                                              .trim()
                                                              .isEmpty
                                                          ? 'غير محدد'
                                                          : provider.trim(),
                                                      'status': isActive
                                                          ? 'نشط'
                                                          : 'متوقف',
                                                    }, SetOptions(merge: true));

                                                setState(() {
                                                  _statusById[markerId.value] =
                                                      isActive
                                                      ? 'نشط'
                                                      : 'متوقف';
                                                  _markers.removeWhere(
                                                    (m) =>
                                                        m.markerId == markerId,
                                                  );
                                                  final normalized =
                                                      _normalizeType(type);
                                                  final marker = Marker(
                                                    markerId: markerId,
                                                    position: LatLng(lat, lng),
                                                    infoWindow: InfoWindow(
                                                      title:
                                                          name.trim().isNotEmpty
                                                          ? name.trim()
                                                          : normalized,
                                                      snippet:
                                                          '$normalized${provider.trim().isNotEmpty ? ' • ${provider.trim()}' : ''}',
                                                      onTap: () =>
                                                          _showMarkerSheet(
                                                            markerId,
                                                            LatLng(lat, lng),
                                                          ),
                                                    ),
                                                    icon: _iconForType(
                                                      normalized,
                                                    ),
                                                    consumeTapEvents: true,
                                                    onTap: () =>
                                                        _showMarkerSheet(
                                                          markerId,
                                                          LatLng(lat, lng),
                                                        ),
                                                  );
                                                  _allMarkers.removeWhere(
                                                    (m) =>
                                                        m.markerId == markerId,
                                                  );
                                                  _allMarkers.add(marker);
                                                });
                                                _applyCurrentFilters();
                                                Navigator.pop(context);
                                                Navigator.pop(context);
                                              }
                                            },
                                            child: const Text('حفظ'),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        );
                      }
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
                  'هل تريد تأكيد حذف "$name"؟',
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
                      backgroundColor: Colors.red,
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
                          SnackBar(
                            backgroundColor: slackMesseges.red,
                            content: Text(
                              'فشل حذف السحابة',
                              style: GoogleFonts.ibmPlexSansArabic(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
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
                      foregroundColor: appColors.primary,
                      side: const BorderSide(color: appColors.primary),
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

  Future<void> _addMarkerToMapAndSave(
    LatLng pos,
    String address,
    String type, {
    String provider = 'غير محدد',
    String statusStr = 'نشط',
  }) async {
    try {
      final normalizedType = _normalizeType(type);
      final docRef = FirebaseFirestore.instance.collection('facilities').doc();

      debugPrint('🎯 محاولة حفظ الموقع في Firestore...');
      debugPrint('📍 الإحداثيات: ${pos.latitude}, ${pos.longitude}');
      debugPrint('🏷️  الاسم: $address');
      debugPrint('♻️  النوع: $type -> $normalizedType');

      await docRef.set({
        'address': address.isEmpty ? 'عنوان غير محدد' : address.trim(),
        'type': normalizedType,
        'lat': pos.latitude,
        'lng': pos.longitude,
        'provider': provider.trim().isEmpty ? 'غير محدد' : provider.trim(),
        'status': statusStr,
      });

      debugPrint('✅ تم حفظ الموقع في Firestore مع ID: ${docRef.id}');

      // إنشاء الـ Marker جديد
      final markerId = MarkerId(docRef.id);
      final marker = Marker(
        markerId: markerId,
        position: pos,
        infoWindow: InfoWindow(
          title: address.trim().isNotEmpty ? address.trim() : normalizedType,
          snippet:
              '$normalizedType${provider.trim().isNotEmpty ? ' • ${provider.trim()}' : ''}',
          onTap: () => _showMarkerSheet(markerId, pos),
        ),
        icon: _iconForType(normalizedType),
        consumeTapEvents: true,
        onTap: () => _showMarkerSheet(markerId, pos),
      );

      // تحديث الحالة
      setState(() {
        _statusById[docRef.id] = statusStr;
        _allMarkers.add(marker);
        debugPrint(
          '✅ تم إضافة الماركر إلى _allMarkers، العدد الحالي: ${_allMarkers.length}',
        );
      });

      // تطبيق الفلاتر الحالية
      _applyCurrentFilters();
      debugPrint(
        '✅ تم تطبيق الفلاتر، عدد الماركرات المرئية: ${_markers.length}',
      );

      // عرض رسالة نجاح
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: slackMesseges.primary,
            content: Text(
              '✅ تم إضافة "$address" بنجاح',
              style: GoogleFonts.ibmPlexSansArabic(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }

      // ✅ لا نحرك الكاميرا - نبقى في نفس المكان
      debugPrint('✅ تم الانتهاء من حفظ وإضافة الموقع بنجاح');
    } catch (e) {
      debugPrint('❌ خطأ في الحفظ: $e');
      debugPrint('❌ StackTrace: ${e.toString()}');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: slackMesseges.red,
            content: Text(
              '❌ حدث خطأ أثناء حفظ البيانات: ${e.toString()}',
              style: GoogleFonts.ibmPlexSansArabic(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      }
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
  final Function(
    String name,
    String type,
    String provider,
    bool isActive,
    String option,
  )
  onSelectOption;

  const _FacilityFormCard({
    required this.title,
    required this.initialName,
    required this.initialType,
    required this.initialProvider,
    required this.initialActive,
    required this.onSelectOption,
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
                      DropdownMenuItem(
                        value: 'حاوية إعادة تدوير القوارير',
                        child: Text('حاوية إعادة تدوير القوارير'),
                      ),
                    ],
                    onChanged: (val) => setState(() => _type = val ?? _type),
                    validator: (v) =>
                        (v == null || v.isEmpty) ? 'اختر نوع الحاوية' : null,
                  ),
                  const SizedBox(height: 14),

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

                  const SizedBox(height: 16),
                  const Text(
                    'طريقة تحديد الموقع',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'سيتم فتح الخريطة لتحديد الموقع',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 16),

                  // أزرار الخيارات
                  _LocationOptionButton(
                    icon: Icons.edit_location_alt_outlined,
                    label: 'تحديد يدوي على الخريطة',
                    description: 'اختر الموقع بالضغط على الخريطة',
                    onTap: () {
                      if (_formKey.currentState!.validate()) {
                        widget.onSelectOption(
                          _nameCtrl.text.trim(),
                          _type,
                          _providerCtrl.text.trim(),
                          _isActive,
                          'تحديد يدوي',
                        );
                      }
                    },
                  ),
                  const SizedBox(height: 12),

                  _LocationOptionButton(
                    icon: Icons.my_location,
                    label: 'استخدام موقعي الحالي',
                    description: 'سيتم وضع علامة على موقعك الحالي',
                    onTap: () {
                      if (_formKey.currentState!.validate()) {
                        widget.onSelectOption(
                          _nameCtrl.text.trim(),
                          _type,
                          _providerCtrl.text.trim(),
                          _isActive,
                          'موقعي الحالي',
                        );
                      }
                    },
                  ),
                  const SizedBox(height: 12),

                  _LocationOptionButton(
                    icon: Icons.straighten_outlined,
                    label: 'إدخال الإحداثيات يدوياً',
                    description: 'أدخل خط العرض وخط الطول',
                    onTap: () {
                      if (_formKey.currentState!.validate()) {
                        widget.onSelectOption(
                          _nameCtrl.text.trim(),
                          _type,
                          _providerCtrl.text.trim(),
                          _isActive,
                          'إحداثيات',
                        );
                      }
                    },
                  ),
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
        borderSide: const BorderSide(color: appColors.primary),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: appColors.primary),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: appColors.dark, width: 1.2),
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
            child: const Icon(Icons.tune, color: appColors.dark),
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
              : Icon(icon, color: appColors.dark),
        ),
      ),
    );
  }
}

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
          Material(
            color: Colors.transparent,
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    appColors.primary.withOpacity(.2),
                    appColors.primary.withOpacity(.08),
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: appColors.primary.withOpacity(.18),
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
                        color: appColors.primary,
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
  final String description;
  final VoidCallback onTap;

  const _LocationOptionButton({
    required this.icon,
    required this.label,
    required this.description,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: appColors.primary, width: 1.2),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: appColors.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: appColors.primary, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    description,
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
          ],
        ),
      ),
    );
  }
}

class _NotificationButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool hasNotification;
  final bool isLoading;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _NotificationButton({
    required this.icon,
    required this.tooltip,
    required this.hasNotification,
    required this.isLoading,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // ✅ الزر الأساسي
        Tooltip(
          message: tooltip,
          child: InkResponse(
            onTap: onTap,
            onLongPress: onLongPress,
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
                  : Icon(icon, color: appColors.dark),
            ),
          ),
        ),

        // ✅ النقطة الحمراء (فقط إذا كان هناك إشعارات)
        if (hasNotification && !isLoading)
          Positioned(
            top: -4,
            right: -4,
            child: Container(
              width: 16, // أصغر قليلاً
              height: 16,
              decoration: BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.red.withOpacity(0.4),
                    blurRadius: 6,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
