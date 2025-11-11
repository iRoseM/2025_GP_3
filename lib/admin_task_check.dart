import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';

// 🧭 نفس ستايل صفحات الأدمن
import 'services/admin_bottom_nav.dart';
import 'admin_home.dart';
import 'admin_task.dart';
import 'admin_map.dart';
import 'services/background_container.dart';
import 'services/connection.dart';
import 'services/title_header.dart';

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

// =====================================================
// 🔰 حساب وربط عوامل الانبعاث + التسجيل عند الاعتماد
// =====================================================

final _fs = FirebaseFirestore.instance;

// ——— إعدادات موحّدة لمجموعة العوامل ———
const String _efCollection = 'emissionFactors';
const String _efValueField = 'ef_kgco2_per_unit'; // حقلك الحالي

class CarbonCalcResult {
  final double kgCO2;
  final String direction; // "save" | "emit"
  final Map<String, dynamic> meta;
  CarbonCalcResult({
    required this.kgCO2,
    required this.direction,
    required this.meta,
  });
}

// 🔎 جلب مستند عامل بالمعرّف
Future<Map<String, dynamic>?> _getEfDoc(String id) async {
  if (id.isEmpty) return null;
  final snap = await _fs.collection(_efCollection).doc(id).get();
  if (!snap.exists) return null;
  final data = snap.data();
  if (data == null) return null;
  return {'id': snap.id, ...data};
}

double _numOr0(dynamic v) =>
    (v is num) ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0.0;

// ✅ قارئ مرن لقيمة العامل (يدعم أسماء متعددة + valueField داخل الوثيقة)
double? _readEfValueFlexible(
  Map<String, dynamic> efDoc, {
  String? preferField,
}) {
  double? _asDouble(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v.trim());
    return null;
  }

  if (preferField != null && preferField.isNotEmpty) {
    final v = _asDouble(efDoc[preferField]);
    if (v != null) return v;
  }

  final vfInDoc = efDoc['valueField'] ?? efDoc['efValueField'];
  if (vfInDoc is String && vfInDoc.isNotEmpty) {
    final v = _asDouble(efDoc[vfInDoc]);
    if (v != null) return v;
  }

  final candidates = <String>[
    'ef_kgco2_per_unit',
    'value',
    'kgPerKm',
    'perKm',
    'co2PerKm',
    'co2_per_km',
    'factor',
  ];
  for (final k in candidates) {
    final v = _asDouble(efDoc[k]);
    if (v != null) return v;
  }
  return null;
}

// للتوافق مع الاستدعاءات القديمة
double? _readEfValue(Map<String, dynamic> efDoc) =>
    _readEfValueFlexible(efDoc, preferField: _efValueField);

Future<Map<String, dynamic>?> resolveEmissionFactorForTask(
  Map<String, dynamic> task,
) async {
  final directRef = (task['emissionFactorRef'] ?? task['emission_factor_ref'])
      ?.toString()
      .trim();

  if (directRef != null && directRef.isNotEmpty) {
    final doc = await _getEfDoc(directRef);
    if (doc != null) return doc;
  }

  String normalize(String? s) =>
      (s ?? '').toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

  final title = normalize(task['title'] ?? task['title_normalized']);
  final desc = normalize(task['description']);
  final cat = (task['category'] ?? '').toString();

  final words = <String>{
    ...title.split(' ').where((w) => w.isNotEmpty),
    ...desc.split(' ').where((w) => w.isNotEmpty),
  };

  final qs = await _fs.collection(_efCollection).limit(50).get();
  int bestScore = -1;
  Map<String, dynamic>? best;

  for (final d in qs.docs) {
    final data = d.data();
    final kws =
        (data['keywords'] as List?)?.map((e) => e.toString()).toList() ?? [];
    final efCat = data['category']?.toString() ?? '';

    int score = 0;
    if (cat.isNotEmpty && efCat.isNotEmpty && efCat == cat) score += 2;
    for (final k in kws) {
      final nk = k.toLowerCase();
      if (words.contains(nk)) score += 1;
      if (nk.length > 2 && (title.contains(nk) || desc.contains(nk))) {
        score += 1;
      }
    }

    if (score > bestScore) {
      bestScore = score;
      best = {'id': d.id, ...data};
    }
  }

  return best;
}

Future<CarbonCalcResult?> computeCarbonForTask({
  required Map<String, dynamic> task,
  required int count,
  required double distanceKm,
}) async {
  final ef = await resolveEmissionFactorForTask(task);
  if (ef == null) return null;

  final rawMode = (ef['calcMode'] ?? ef['calc_mode'] ?? 'perItem').toString();
  final calcMode = rawMode.toLowerCase();
  final direction = (ef['direction'] ?? 'save').toString();

  double kg = 0.0;
  final meta = <String, dynamic>{
    'mode': rawMode,
    'ef_id': ef['id'],
    'ef_name': ef['name'],
    'direction': direction,
  };

  Future<double?> _efValByRef(String? ref) async {
    if (ref == null || ref.isEmpty) return null;
    final doc = await _getEfDoc(ref);
    if (doc == null) return null;
    return _readEfValueFlexible(doc, preferField: _efValueField);
  }

  if (calcMode == 'peritem') {
    final perItem = _readEfValueFlexible(ef, preferField: _efValueField) ?? 0.0;
    kg = perItem * count.clamp(0, 1000000);
    meta.addAll({'count': count, 'ef': perItem});
  } else if (calcMode == 'perkm') {
    final perKm = _readEfValueFlexible(ef, preferField: _efValueField) ?? 0.0;
    kg = perKm * distanceKm.clamp(0, 1000000);
    meta.addAll({'distanceKm': distanceKm, 'ef': perKm});
  } else if (calcMode == 'deltaperkm') {
    final baselineRef = (ef['baselineFactorRef'] ?? ef['baseline_factor_ref'])
        ?.toString();
    final actualRef = (ef['actualFactorRef'] ?? ef['actual_factor_ref'])
        ?.toString();
    if (baselineRef == null ||
        baselineRef.isEmpty ||
        actualRef == null ||
        actualRef.isEmpty) {
      return null;
    }
    final base = await _efValByRef(baselineRef) ?? 0.0;
    final act = await _efValByRef(actualRef) ?? 0.0;
    final delta = base - act;
    kg = (delta > 0 ? delta : 0.0) * distanceKm.clamp(0, 1000000);
    meta.addAll({
      'distanceKm': distanceKm,
      'ef_baseline_id': baselineRef,
      'ef_actual_id': actualRef,
      'baseline_per_km': base,
      'actual_per_km': act,
      'delta_per_km': delta,
    });
  } else {
    final perItem = _readEfValueFlexible(ef, preferField: _efValueField) ?? 0.0;
    kg = perItem * count.clamp(0, 1000000);
    meta.addAll({'count': count, 'ef': perItem, 'fallback': true});
  }

  if (kg < 0) kg = 0;
  final finalKg = (direction.toLowerCase() == 'save') ? kg : 0.0;

  return CarbonCalcResult(kgCO2: finalKg, direction: direction, meta: meta);
}

// =====================================================

class AdminTaskCheckPage extends StatefulWidget {
  const AdminTaskCheckPage({super.key});

  @override
  State<AdminTaskCheckPage> createState() => _AdminTaskCheckPageState();
}

class _AdminTaskCheckPageState extends State<AdminTaskCheckPage> {
  int _currentIndex = 2;
  bool _isAdmin = false;
  String? _uid;

  @override
  void initState() {
    super.initState();
    _checkConnection();
    _ensureAdminClaims();
  }

  Future<void> _checkConnection() async {
    if (!await hasInternetConnection()) {
      if (mounted) showNoInternetDialog(context);
    }
  }

  void _onTap(int i) {
    if (i == _currentIndex) return;
    switch (i) {
      case 0:
        break;
      case 1:
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const AdminMapPage()),
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
          MaterialPageRoute(builder: (_) => const AdminHomePage()),
        );
        break;
    }
  }

  Future<void> _ensureAdminClaims() async {
    final u = FirebaseAuth.instance.currentUser;
    _uid = u?.uid;
    if (u == null) return;
    await u.getIdToken(true);
    final tok = await u.getIdTokenResult();
    final isAdm =
        (tok.claims?['admin'] == true) || (tok.claims?['role'] == 'admin');
    debugPrint(
      '[claims] admin=${tok.claims?['admin']} role=${tok.claims?['role']} uid=${u.uid}',
    );
    if (mounted) {
      setState(() {
        _isAdmin = isAdm;
      });
    }
  }

  Stream<QuerySnapshot> _pendingSubs() {
    final col = FirebaseFirestore.instance.collection('submissions');
    if (_isAdmin) {
      return col
          .where('status', isEqualTo: 'pending')
          .snapshots(includeMetadataChanges: true);
    } else {
      final uid = _uid ?? FirebaseAuth.instance.currentUser?.uid ?? '';
      return col
          .where('status', isEqualTo: 'pending')
          .where('userId', isEqualTo: uid)
          .snapshots(includeMetadataChanges: true);
    }
  }

  String _dayId(DateTime dt) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)}';
  }

  // =================== helpers لحساب الكربون ===================

  Future<Map<String, dynamic>?> _getFactorByRef(String refId) async {
    if (refId.isEmpty) return null;
    final snap = await FirebaseFirestore.instance
        .collection(_efCollection)
        .doc(refId)
        .get();
    if (!snap.exists) return null;
    return snap.data() as Map<String, dynamic>;
  }

  double _round2(double v) => (v * 100).roundToDouble() / 100.0;

  Future<double> _computeSavedKgCO2({
    String? calcMode,
    String? efRef,
    String? baselineRef,
    String direction = 'save',
    required int count,
    required double distanceKm,
    required Map<String, dynamic> taskSnapshotOrMinimal,
  }) async {
    calcMode ??= taskSnapshotOrMinimal['calcMode'] as String?;
    efRef ??= taskSnapshotOrMinimal['emissionFactorRef'] as String?;
    baselineRef ??= taskSnapshotOrMinimal['baselineFactorRef'] as String?;
    direction = (taskSnapshotOrMinimal['direction'] as String?) ?? direction;

    final mode = (calcMode ?? 'perItem').toString().toLowerCase();
    if (direction.toLowerCase() != 'save') return 0.0;

    if (mode == 'peritem') {
      if ((efRef ?? '').isEmpty || count <= 0) return 0.0;
      final f = await _getFactorByRef(efRef!);
      if (f == null) return 0.0;
      final factor = _readEfValueFlexible(f, preferField: _efValueField) ?? 0.0;
      return _round2(count * factor);
    }

    if (mode == 'perkm') {
      if ((efRef ?? '').isEmpty || distanceKm <= 0) return 0.0;
      final f = await _getFactorByRef(efRef!);
      if (f == null) return 0.0;
      final factor = _readEfValueFlexible(f, preferField: _efValueField) ?? 0.0;
      return _round2(distanceKm * factor);
    }

    if (mode == 'deltaperkm') {
      if ((baselineRef ?? '').isEmpty ||
          (efRef ?? '').isEmpty ||
          distanceKm <= 0) {
        return 0.0;
      }
      final baseF = await _getFactorByRef(baselineRef!);
      final actF = await _getFactorByRef(efRef!);
      if (baseF == null || actF == null) return 0.0;
      final base =
          _readEfValueFlexible(baseF, preferField: _efValueField) ?? 0.0;
      final act = _readEfValueFlexible(actF, preferField: _efValueField) ?? 0.0;
      final delta = base - act;
      if (delta <= 0) return 0.0;
      return _round2(delta * distanceKm);
    }

    // fallback perItem
    if ((efRef ?? '').isEmpty || count <= 0) return 0.0;
    final f = await _getFactorByRef(efRef!);
    if (f == null) return 0.0;
    final factor = _readEfValueFlexible(f, preferField: _efValueField) ?? 0.0;
    return _round2(count * factor);
  }

  // =====================================================
  // 🧮 deltaPerKm: تحسب + تحدث userTasks و users
  // =====================================================
  Future<double> _computeAndPersistDeltaPerKm({
    required Map<String, dynamic> task, // ممكن ما يحتوي baseline/actual
    required String userTaskDocId,
    required String uid,
    required double distanceKm,
  }) async {
    try {
      if (distanceKm <= 0) {
        throw Exception('distanceKm يجب أن تكون أكبر من صفر');
      }

      // 1) جرّب تقرا من المهمة
      String? baselineRef =
          (task['baselineFactorRef'] ?? task['baseline_factor_ref'])
              ?.toString();
      String? actualRef =
          (task['emissionFactorRef'] ??
                  task['actualFactorRef'] ??
                  task['emission_factor_ref'])
              ?.toString();

      // 2) إن ما وُجدت بالمهمة، حاول تجيب وثيقة EF ثم استخرج منها
      Future<Map<String, dynamic>?> _loadEfFromTaskOrResolve() async {
        final taskEfId =
            (task['emissionFactorRef'] ?? task['emission_factor_ref'])
                ?.toString();
        if (taskEfId != null && taskEfId.isNotEmpty) {
          return await _getEfDoc(taskEfId);
        }
        return await resolveEmissionFactorForTask(task);
      }

      if ((baselineRef == null || baselineRef.isEmpty) ||
          (actualRef == null || actualRef.isEmpty)) {
        final efDoc = await _loadEfFromTaskOrResolve();
        if (efDoc != null) {
          baselineRef ??=
              (efDoc['baselineFactorRef'] ?? efDoc['baseline_factor_ref'])
                  ?.toString();
          actualRef ??=
              (efDoc['actualFactorRef'] ??
                      efDoc['emissionFactorRef'] ??
                      efDoc['actual_factor_ref'] ??
                      efDoc['emission_factor_ref'])
                  ?.toString();
        }
      }

      if (baselineRef == null ||
          baselineRef.isEmpty ||
          actualRef == null ||
          actualRef.isEmpty) {
        final idOrTitle = task['id'] ?? task['title'] ?? '(task?)';
        throw Exception(
          'baseline/actual factor refs مفقودة (task=$idOrTitle). تأكد من baselineFactorRef و actualFactorRef في EF.',
        );
      }

      Future<double?> _getVal(String id) async {
        final snap = await FirebaseFirestore.instance
            .collection(_efCollection)
            .doc(id)
            .get();
        if (!snap.exists) return null;
        final m = snap.data() as Map<String, dynamic>?;
        if (m == null) return null;
        return _readEfValueFlexible(m, preferField: _efValueField);
      }

      final base = await _getVal(baselineRef) ?? 0.0;
      final act = await _getVal(actualRef) ?? 0.0;
      final delta = base - act;
      final savedKg = delta > 0 ? (delta * distanceKm) : 0.0;

      final batch = FirebaseFirestore.instance.batch();
      final utRef = FirebaseFirestore.instance
          .collection('userTasks')
          .doc(userTaskDocId);
      final userRef = FirebaseFirestore.instance.collection('users').doc(uid);

      batch.update(utRef, {
        'savedKgCO2': savedKg,
        'distanceKm': distanceKm,
        'completedAt': FieldValue.serverTimestamp(),
      });

      batch.set(userRef, {
        'totalCarbonSaved': FieldValue.increment(savedKg),
        'lastCarbonUpdateAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await batch.commit();
      debugPrint(
        '[deltaPerKm] ✅ saved=+$savedKg kgCO₂ @ $distanceKm km (base=$base, act=$act) [baseline=$baselineRef, actual=$actualRef]',
      );
      return savedKg;
    } catch (e) {
      debugPrint('❌ _computeAndPersistDeltaPerKm error: $e');
      rethrow;
    }
  }

  // =================== الدالة الرئيسية (اعتماد) ===================

  @override
  Widget build(BuildContext context) {
    final baseTheme = Theme.of(context);
    final textTheme = GoogleFonts.ibmPlexSansArabicTextTheme(
      baseTheme.textTheme,
    );

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Theme(
        data: baseTheme.copyWith(
          textTheme: textTheme,
          primaryTextTheme: textTheme,
          appBarTheme: const AppBarTheme(
            backgroundColor: Colors.transparent,
            elevation: 0,
            iconTheme: IconThemeData(color: Colors.white),
          ),
        ),
        child: Scaffold(
          extendBody: true,
          extendBodyBehindAppBar: true,
          backgroundColor: Colors.transparent,
          appBar: const NameerAppBar(showTitleInBar: false, showBack: true),
          body: AnimatedBackgroundContainer(
            child: Builder(
              builder: (context) {
                final statusBar = MediaQuery.of(context).padding.top;
                const headerH = 20.0;
                const fadeH = 0.0;
                const gap = 12.0;
                final topPadding = statusBar + headerH + fadeH + gap;

                return Padding(
                  padding: EdgeInsets.fromLTRB(16, topPadding, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'مراجعة المهام',
                            style: GoogleFonts.ibmPlexSansArabic(
                              fontSize: 24,
                              fontWeight: FontWeight.w700,
                              color: AppColors.dark,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: _isAdmin
                                  ? AppColors.primary33
                                  : Colors.orange.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              _isAdmin ? 'أدمن' : 'حساب عادي',
                              style: GoogleFonts.ibmPlexSansArabic(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: _isAdmin
                                    ? AppColors.dark
                                    : Colors.orange,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      // 🔎 Debug يظهر حالة الأدمن
                      Text(
                        'debug • isAdmin: $_isAdmin',
                        style: TextStyle(fontSize: 11, color: Colors.grey[700]),
                      ),
                      const SizedBox(height: 15),

                      Expanded(
                        child: StreamBuilder<QuerySnapshot>(
                          stream: _pendingSubs(),
                          builder: (context, snap) {
                            if (snap.connectionState ==
                                ConnectionState.waiting) {
                              return const Center(
                                child: CircularProgressIndicator(),
                              );
                            }

                            if (snap.hasError) {
                              return Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(
                                      Icons.error_outline,
                                      size: 64,
                                      color: Colors.red,
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      'خطأ في تحميل البيانات',
                                      style: GoogleFonts.ibmPlexSansArabic(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.dark,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      '${snap.error}',
                                      style: GoogleFonts.ibmPlexSansArabic(
                                        fontSize: 12,
                                        color: Colors.grey,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                    const SizedBox(height: 20),
                                    ElevatedButton(
                                      onPressed: () => setState(() {}),
                                      child: Text(
                                        'إعادة المحاولة',
                                        style: GoogleFonts.ibmPlexSansArabic(),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }

                            if (!snap.hasData || snap.data!.docs.isEmpty) {
                              return Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Image.asset(
                                      'assets/img/nameerSleep.png',
                                      width: 200,
                                      height: 200,
                                      fit: BoxFit.contain,
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      _isAdmin
                                          ? 'لا توجد طلبات قيد الانتظار.'
                                          : 'لا توجد طلباتك قيد الانتظار.',
                                      style: GoogleFonts.ibmPlexSansArabic(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.dark,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ),
                              );
                            }

                            final docs = [...snap.data!.docs];
                            int _ts(QueryDocumentSnapshot d) {
                              final v =
                                  (d.data()
                                      as Map<String, dynamic>)['createdAt'];
                              if (v is Timestamp)
                                return v.millisecondsSinceEpoch;
                              return -1;
                            }

                            docs.sort((a, b) => _ts(b).compareTo(_ts(a)));

                            return ListView.separated(
                              padding: const EdgeInsets.only(bottom: 12),
                              itemCount: docs.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 12),
                              itemBuilder: (context, i) {
                                final d = docs[i];
                                final m = d.data() as Map<String, dynamic>;
                                final images =
                                    (m['imageUrls'] as List?)?.cast<String>() ??
                                    [];

                                // ✅ نقرأ العدد من itemCount أولاً ثم count (للخلفية)
                                final countStr =
                                    (m['itemCount'] ?? m['count'])
                                        ?.toString() ??
                                    '';
                                final km = (m['distanceKm']?.toString() ?? '');

                                return Card(
                                  key: ValueKey(d.id),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  elevation: 2,
                                  child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          m['taskTitle'] ?? '(بدون عنوان)',
                                          style: GoogleFonts.ibmPlexSansArabic(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 16,
                                            color: AppColors.dark,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'المستخدم: ${m['userId']} • النقاط: ${m['taskPoints'] ?? 0}',
                                          style: GoogleFonts.ibmPlexSansArabic(
                                            fontSize: 13,
                                            color: Colors.grey[700],
                                          ),
                                        ),
                                        if (countStr.isNotEmpty ||
                                            km.isNotEmpty)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              top: 6,
                                            ),
                                            child: Text(
                                              [
                                                if (countStr.isNotEmpty)
                                                  'العدد: $countStr',
                                                if (km.isNotEmpty)
                                                  'المسافة: $km كم',
                                              ].join(' • '),
                                              style:
                                                  GoogleFonts.ibmPlexSansArabic(
                                                    fontSize: 12,
                                                    color: Colors.grey[700],
                                                  ),
                                            ),
                                          ),
                                        const SizedBox(height: 8),
                                        if (images.isNotEmpty)
                                          Wrap(
                                            spacing: 8,
                                            runSpacing: 8,
                                            children: images
                                                .map(
                                                  (url) => ClipRRect(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          12,
                                                        ),
                                                    child: Image.network(
                                                      url,
                                                      key: ValueKey(url),
                                                      height: 100,
                                                      width: 100,
                                                      fit: BoxFit.cover,
                                                      errorBuilder: (context, error, stackTrace) {
                                                        return Container(
                                                          height: 100,
                                                          width: 100,
                                                          decoration: BoxDecoration(
                                                            color: Colors
                                                                .grey[200],
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                  12,
                                                                ),
                                                          ),
                                                          child: Column(
                                                            mainAxisAlignment:
                                                                MainAxisAlignment
                                                                    .center,
                                                            children: [
                                                              Icon(
                                                                Icons
                                                                    .error_outline,
                                                                color: Colors
                                                                    .grey[500],
                                                                size: 30,
                                                              ),
                                                              const SizedBox(
                                                                height: 4,
                                                              ),
                                                              Text(
                                                                'خطأ في التحميل',
                                                                style: GoogleFonts.ibmPlexSansArabic(
                                                                  fontSize: 10,
                                                                  color: Colors
                                                                      .grey[600],
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                        );
                                                      },
                                                    ),
                                                  ),
                                                )
                                                .toList(),
                                          )
                                        else
                                          Container(
                                            height: 100,
                                            width: double.infinity,
                                            decoration: BoxDecoration(
                                              color: Colors.grey[100],
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              border: Border.all(
                                                color: Colors.grey.shade300,
                                              ),
                                            ),
                                            child: Column(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                Icon(
                                                  Icons.photo_library_outlined,
                                                  color: Colors.grey[400],
                                                  size: 40,
                                                ),
                                                const SizedBox(height: 8),
                                                Text(
                                                  'لا توجد صور مرفوعة',
                                                  style:
                                                      GoogleFonts.ibmPlexSansArabic(
                                                        fontSize: 12,
                                                        color: Colors.grey[600],
                                                      ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        const SizedBox(height: 10),
                                        Row(
                                          children: [
                                            Expanded(
                                              child: ElevatedButton.icon(
                                                onPressed: _isAdmin
                                                    ? () async {
                                                        debugPrint(
                                                          '[approve] tap ${d.id}',
                                                        );
                                                        await _approve(
                                                          context,
                                                          d,
                                                        );
                                                      }
                                                    : null,
                                                icon: const Icon(
                                                  Icons.check_circle_outline,
                                                ),
                                                label: const Text('اعتماد'),
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor:
                                                      AppColors.primary,
                                                  foregroundColor: Colors.white,
                                                  disabledBackgroundColor:
                                                      Colors.grey[300],
                                                  disabledForegroundColor:
                                                      Colors.grey[600],
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        vertical: 12,
                                                      ),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: OutlinedButton.icon(
                                                onPressed: _isAdmin
                                                    ? () => _reject(context, d)
                                                    : null,
                                                icon: const Icon(
                                                  Icons.cancel_outlined,
                                                ),
                                                label: const Text('رفض'),
                                                style: OutlinedButton.styleFrom(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        vertical: 12,
                                                      ),
                                                  side: const BorderSide(
                                                    color: AppColors.primary,
                                                    width: 2,
                                                  ),
                                                  foregroundColor: _isAdmin
                                                      ? AppColors.primary
                                                      : Colors.grey[600],
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        if (!_isAdmin)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              top: 8,
                                            ),
                                            child: Text(
                                              'ملاحظة: تحتاج صلاحية أدمن لاعتماد/رفض الطلبات.',
                                              style:
                                                  GoogleFonts.ibmPlexSansArabic(
                                                    fontSize: 12,
                                                    color: Colors.orange[800],
                                                  ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          // لا يوجد BottomNav هنا حاليًا
        ),
      ),
    );
  }

  // ========= اعتماد/رفض (نقلتها تحت build لتكون أوضح) =========

  Future<void> _approve(BuildContext context, DocumentSnapshot subDoc) async {
    await _ensureAdminClaims();
    if (!_isAdmin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يحتاج صلاحية أدمن لاعتماد الطلب')),
      );
      return;
    }

    final data = subDoc.data() as Map<String, dynamic>;
    final userTaskDocId = (data['userTaskDocId'] ?? '').toString();
    final userId = (data['userId'] ?? '').toString();
    if (userTaskDocId.isEmpty || userId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('الطلب ناقص userId/userTaskDocId')),
      );
      return;
    }

    final taskPoints = (data['taskPoints'] ?? 0) as int;
    final taskId = (data['taskId'] ?? '').toString();
    final taskTitle =
        (data['taskTitle'] ?? data['task_title'] ?? '(بدون عنوان)').toString();

    int _asInt(dynamic v) => (v is int) ? v : int.tryParse('${v ?? ''}') ?? 0;
    int itemCount = _asInt(
      data['itemCount'] ?? data['count'] ?? data['evidence']?['itemCount'],
    );

    final submittedDistanceKm = (data['distanceKm'] is num)
        ? (data['distanceKm'] as num).toDouble()
        : double.tryParse('${data['distanceKm'] ?? ''}') ?? 0.0;

    String? calcMode = (data['calcMode'] as String?);
    String? efRef = (data['emissionFactorRef'] as String?);
    String? baselineRef = (data['baselineFactorRef'] as String?);
    String direction = (data['direction'] as String?) ?? 'save';

    final usersRef = FirebaseFirestore.instance.collection('users').doc(userId);
    final utRef = FirebaseFirestore.instance
        .collection('userTasks')
        .doc(userTaskDocId);
    final subRef = subDoc.reference;
    final admin = FirebaseAuth.instance.currentUser;

    Map<String, dynamic> taskMapForCarbon = {};
    if (taskId.isNotEmpty) {
      final t = await FirebaseFirestore.instance
          .collection('tasks')
          .doc(taskId)
          .get();
      if (t.exists && t.data() != null) {
        taskMapForCarbon = {'id': t.id, ...t.data()!};
      }
    }
    if (taskMapForCarbon.isEmpty) {
      taskMapForCarbon = {
        'id': taskId,
        'title': taskTitle,
        'title_normalized': taskTitle
            .toLowerCase()
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim(),
        'description': (data['taskDescription'] ?? data['task_desc'] ?? ''),
        'category': (data['taskCategory'] ?? data['category'] ?? ''),
        if (data['emissionFactorRef'] != null)
          'emissionFactorRef': data['emissionFactorRef'],
        if (data['baselineFactorRef'] != null)
          'baselineFactorRef': data['baselineFactorRef'],
        if (data['calcMode'] != null) 'calcMode': data['calcMode'],
        if (data['direction'] != null) 'direction': data['direction'],
        if (data['minItems'] != null) 'minItems': data['minItems'],
        if (data['maxItems'] != null) 'maxItems': data['maxItems'],
        if (data['defaultItemsOnSubmit'] != null)
          'defaultItemsOnSubmit': data['defaultItemsOnSubmit'],
        if (data['defaultItems'] != null) 'defaultItems': data['defaultItems'],
      };
    }

    double _n(dynamic v) =>
        (v is num) ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0.0;
    double effectiveDistanceKm = submittedDistanceKm;
    if (effectiveDistanceKm <= 0) {
      final defKm = _n(taskMapForCarbon['defaultKmOnSubmit']);
      final minKm = _n(taskMapForCarbon['minKm']);
      effectiveDistanceKm = defKm > 0 ? defKm : 0.0;
      if (effectiveDistanceKm < minKm) effectiveDistanceKm = minKm;
    }

    final effectiveCalcMode =
        (calcMode ?? taskMapForCarbon['calcMode'] ?? 'perItem')
            .toString()
            .toLowerCase();

    if (effectiveCalcMode == 'peritem' && itemCount <= 0) {
      try {
        final utSnap = await utRef.get();
        if (utSnap.exists) {
          final ut = utSnap.data() as Map<String, dynamic>?;
          final fromUt = ut?['itemCount'] ?? ut?['count'];
          if (fromUt != null) itemCount = _asInt(fromUt);
        }
      } catch (_) {}
      if (itemCount <= 0) {
        final minItems = _asInt(taskMapForCarbon['minItems']);
        final maxItems = _asInt(taskMapForCarbon['maxItems']);
        final defItems = _asInt(taskMapForCarbon['defaultItemsOnSubmit']) > 0
            ? _asInt(taskMapForCarbon['defaultItemsOnSubmit'])
            : _asInt(taskMapForCarbon['defaultItems']);
        int v = defItems > 0 ? defItems : 1;
        if (minItems > 0 && v < minItems) v = minItems;
        if (maxItems > 0 && v > maxItems) v = maxItems;
        itemCount = v;
      }
    }

    double savedKgCO2 = 0.0;
    if (effectiveCalcMode == 'deltaperkm') {
      savedKgCO2 = await _computeAndPersistDeltaPerKm(
        task: {
          ...taskMapForCarbon,
          if (baselineRef != null) 'baselineFactorRef': baselineRef,
          if (efRef != null) 'emissionFactorRef': efRef,
        },
        userTaskDocId: userTaskDocId,
        uid: userId,
        distanceKm: effectiveDistanceKm,
      );
    } else {
      savedKgCO2 = await _computeSavedKgCO2(
        calcMode: calcMode,
        efRef: efRef,
        baselineRef: baselineRef,
        direction: direction,
        count: itemCount,
        distanceKm: effectiveDistanceKm,
        taskSnapshotOrMinimal: taskMapForCarbon,
      );
    }

    String _fmtKgLocal(double kg) {
      final v = ((kg * 100).roundToDouble() / 100.0);
      return v.toStringAsFixed(v.truncateToDouble() == v ? 0 : 2);
    }

    final todayId = _dayId(DateTime.now());
    final dayMarkRef = FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('dayMarks')
        .doc(todayId);

    try {
      await FirebaseFirestore.instance.runTransaction((trx) async {
        final subSnap = await trx.get(subRef);
        if (!subSnap.exists) throw 'الطلب غير موجود.';
        final sub = subSnap.data() as Map<String, dynamic>;
        if (sub['status'] != 'pending') throw 'تمت معالجة هذا الطلب مسبقاً.';

        final utSnap = await trx.get(utRef);
        if (!utSnap.exists) throw 'userTask غير موجود.';
        final ut = utSnap.data() as Map<String, dynamic>;
        final currentStatus = (ut['status'] as String?) ?? 'pending';
        final canComplete = currentStatus != 'completed';

        final subUpdate = <String, dynamic>{
          'status': 'approved',
          'processedAt': FieldValue.serverTimestamp(),
          'processedBy': admin?.uid,
        };
        if (savedKgCO2 > 0) subUpdate['savedKgCO2'] = savedKgCO2;
        if (effectiveDistanceKm > 0 && (submittedDistanceKm <= 0)) {
          subUpdate['distanceKm'] = effectiveDistanceKm;
        }
        if ((sub['itemCount'] == null || (sub['itemCount'] == 0)) &&
            itemCount > 0) {
          subUpdate['itemCount'] = itemCount;
        }
        trx.update(subRef, subUpdate);

        final utUpdate = <String, dynamic>{
          'status': 'completed',
          'completedAt': FieldValue.serverTimestamp(),
          'canRetry': false,
        };
        if (effectiveCalcMode != 'deltaperkm') {
          if (savedKgCO2 > 0) utUpdate['savedKgCO2'] = savedKgCO2;
          if (effectiveDistanceKm > 0 && (submittedDistanceKm <= 0)) {
            utUpdate['distanceKm'] = effectiveDistanceKm;
          }
          if (itemCount > 0) utUpdate['itemCount'] = itemCount;
        }
        trx.update(utRef, utUpdate);

        if (canComplete && taskPoints > 0) {
          trx.update(usersRef, {'points': FieldValue.increment(taskPoints)});
        }

        final historyRef = FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .collection('history')
            .doc();
        final histData = <String, dynamic>{
          'type': 'task_approved',
          'userTaskDocId': userTaskDocId,
          'submissionId': subRef.id,
          'points': taskPoints,
          'at': FieldValue.serverTimestamp(),
          'taskTitle': taskTitle,
        };
        if (savedKgCO2 > 0) histData['savedKgCO2'] = savedKgCO2;
        if (itemCount > 0) histData['itemCount'] = itemCount;
        trx.set(historyRef, histData);

        if (effectiveCalcMode != 'deltaperkm') {
          trx.set(usersRef, {
            'lastCarbonUpdateAt': FieldValue.serverTimestamp(),
            if (savedKgCO2 > 0)
              'totalCarbonSaved': FieldValue.increment(savedKgCO2),
          }, SetOptions(merge: true));
        } else {
          trx.set(usersRef, {
            'lastCarbonUpdateAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }

        trx.set(dayMarkRef, {
          'count': FieldValue.increment(1),
          'lastAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        final notifRef = FirebaseFirestore.instance
            .collection('notifications')
            .doc();
        final carbonText = _fmtKgLocal(
          savedKgCO2.isFinite && savedKgCO2 >= 0 ? savedKgCO2 : 0.0,
        );
        trx.set(notifRef, {
          'type': 'submission_approved',
          'userId': userId,
          'submissionId': subRef.id,
          'taskTitle': taskTitle,
          'points': taskPoints,
          'savedKgCO2': savedKgCO2.isFinite ? savedKgCO2 : 0.0,
          if (effectiveDistanceKm > 0) 'distanceKm': effectiveDistanceKm,
          if (itemCount > 0) 'itemCount': itemCount,
          'createdAt': FieldValue.serverTimestamp(),
          'seen': false,
          'title': 'تم الاعتماد 🎉',
          'body': 'أُضيفت $taskPoints نقطة • وفَّرت $carbonText كجم CO₂ 🌿',
          'message':
              'تم اعتماد طلبك لمهمة: $taskTitle — نقاط: $taskPoints • توفير: $carbonText كجم CO₂',
          'icon': 'check_circle',
          'iconColor': '#4CAF50',
          'accentColor': '#4BAA98',
        });
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('خطأ: $e')));
    }
  }

  Future<void> _reject(BuildContext context, DocumentSnapshot subDoc) async {
    await _ensureAdminClaims();
    if (!_isAdmin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يحتاج صلاحية أدمن لرفض الطلب')),
      );
      return;
    }

    final admin = FirebaseAuth.instance.currentUser;
    final data = subDoc.data() as Map<String, dynamic>;
    final userTaskDocId = (data['userTaskDocId'] ?? '').toString();
    final userId = (data['userId'] ?? '').toString();

    final subRef = subDoc.reference;
    final utRef = FirebaseFirestore.instance
        .collection('userTasks')
        .doc(userTaskDocId);

    try {
      await FirebaseFirestore.instance.runTransaction((trx) async {
        final subSnap = await trx.get(subRef);
        if (!subSnap.exists) throw 'الطلب غير موجود.';
        final sub = subSnap.data() as Map<String, dynamic>;
        if (sub['status'] != 'pending') throw 'تمت معالجة هذا الطلب مسبقاً.';

        trx.update(subRef, {
          'status': 'rejected',
          'processedAt': FieldValue.serverTimestamp(),
          'processedBy': admin?.uid,
        });

        trx.update(utRef, {
          'status': 'rejected',
          'rejectedAt': FieldValue.serverTimestamp(),
          'canRetry': true,
        });

        if (userId.isNotEmpty) {
          final historyRef = FirebaseFirestore.instance
              .collection('users')
              .doc(userId)
              .collection('history')
              .doc();
          trx.set(historyRef, {
            'type': 'task_rejected',
            'userTaskDocId': userTaskDocId,
            'submissionId': subRef.id,
            'points': 0,
            'at': FieldValue.serverTimestamp(),
          });

          final notifRef = FirebaseFirestore.instance
              .collection('notifications')
              .doc();
          trx.set(notifRef, {
            'type': 'submission_rejected',
            'userId': userId,
            'submissionId': subRef.id,
            'taskTitle': data['taskTitle'],
            'createdAt': FieldValue.serverTimestamp(),
            'seen': false,
            'message': 'تم رفض طلبك لمهمة: ${data['taskTitle'] ?? ''}',
          });
        }
      });

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تم رفض الطلب ❌')));
    } catch (e) {
      debugPrint('❌ خطأ في الرفض: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('خطأ: $e')));
    }
  }
}
