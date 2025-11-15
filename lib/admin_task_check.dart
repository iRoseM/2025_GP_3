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
const String _efValueField = 'ef_kgco2_per_unit'; // الحقل الأساسي للقيمة

/// ✅ baseline الافتراضي لوسائل النقل: سيارة بنزين لكل كيلومتر
/// تأكدي إن هذا هو الـ docId الفعلي في emissionFactors
const String kDefaultTransportBaselineRef = 'transportCarGasolinePerKm';

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

// ✅ قارئ مرن لقيمة العامل (يدعم valueField داخلي وأسماء شائعة)
double? _readEfValueFlexible(
  Map<String, dynamic> efDoc, {
  String? preferField,
}) {
  double? _asDouble(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v.trim());
    return null;
  }

  // 1) الحقل المفضّل (لو محدد)
  if (preferField != null && preferField.isNotEmpty) {
    final v = _asDouble(efDoc[preferField]);
    if (v != null) return v;
  }

  // 2) حقل valueField داخل الوثيقة (ديناميكي)
  final vfInDoc = efDoc['valueField'] ?? efDoc['efValueField'];
  if (vfInDoc is String && vfInDoc.isNotEmpty) {
    final v = _asDouble(efDoc[vfInDoc]);
    if (v != null) return v;
  }

  // 3) قائمة أسماء محتملة (معدّلة لدعم perItem و deltaPerItem)
  final candidates = <String>[
    // قيم عامة
    'ef_kgco2_per_unit',
    'ef_kgco2_per_item',
    'ef_kgco2',

    // per item
    'value',
    'kgPerItem',
    'perItem',

    // per km
    'kgPerKm',
    'perKm',
    'co2PerKm',
    'co2_per_km',

    // fallback عام
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

// 🔍 محاولـة ربط عامل انبعاث لمهمة معيّنة
Future<Map<String, dynamic>?> resolveEmissionFactorForTask(
  Map<String, dynamic> task,
) async {
  // 1) إن كان فيه ref مباشر في المهمة
  final directRef = (task['emissionFactorRef'] ?? task['emission_factor_ref'])
      ?.toString()
      .trim();

  if (directRef != null && directRef.isNotEmpty) {
    final doc = await _getEfDoc(directRef);
    if (doc != null) return doc;
  }

  // 2) محاولة by title/description/keywords
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

// 🧮 دالة عامة (غير مستخدمة مباشرة في الاعتماد، لكن مفيدة لو احتجتها في أماكن أخرى)
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
  } else if (calcMode == 'deltaperitem') {
    // ✅ deltaPerItem في الدالة العامة أيضًا (baseline - actual لكل قطعة)
    final baselineRef = (ef['baselineFactorRef'] ?? ef['baseline_factor_ref'])
        ?.toString();
    final actualRef = (ef['actualFactorRef'] ?? ef['actual_factor_ref'])
        ?.toString();
    if (baselineRef == null ||
        baselineRef.isEmpty ||
        actualRef == null ||
        actualRef.isEmpty ||
        count <= 0) {
      return null;
    }
    final base = await _efValByRef(baselineRef) ?? 0.0;
    final act = await _efValByRef(actualRef) ?? 0.0;
    final delta = base - act;
    kg = (delta > 0 ? delta : 0.0) * count.clamp(0, 1000000);
    meta.addAll({
      'count': count,
      'ef_baseline_id': baselineRef,
      'ef_actual_id': actualRef,
      'baseline_per_item': base,
      'actual_per_item': act,
      'delta_per_item': delta,
    });
  } else {
    // fallback → perItem
    final perItem = _readEfValueFlexible(ef, preferField: _efValueField) ?? 0.0;
    kg = perItem * count.clamp(0, 1000000);
    meta.addAll({'count': count, 'ef': perItem, 'fallback': true});
  }

  if (kg < 0) kg = 0;
  final finalKg = (direction.toLowerCase() == 'save') ? kg : 0.0;

  return CarbonCalcResult(kgCO2: finalKg, direction: direction, meta: meta);
}

// =====================================================
// 📄 صفحة مراجعة المهام (أدمن / حساب عادي)
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
    return snap.data() as Map<String, dynamic>?;
  }

  double _round2(double v) => (v * 100).roundToDouble() / 100.0;

  /// 🧮 منطق حساب savedKgCO2 للمستخدم عند الاعتماد:
  /// - perItem      → factor * count
  /// - perKm        → (baseline - actual) * distanceKm (baseline افتراضي سيارة بنزين)
  /// - deltaPerKm   → (baseline - actual) * distanceKm
  /// - deltaPerItem → (baseline - actual) * count
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

    // نظامنا يحسب "توفير" فقط، فلو المهمة emit ما نضيف شيء للبصمة المحفوظة
    if (direction.toLowerCase() != 'save') return 0.0;

    // perItem → يعتمد فقط على عدد الوحدات
    if (mode == 'peritem') {
      if ((efRef ?? '').isEmpty || count <= 0) return 0.0;
      final f = await _getFactorByRef(efRef!);
      if (f == null) return 0.0;
      final factor = _readEfValueFlexible(f, preferField: _efValueField) ?? 0.0;
      return _round2(count * factor);
    }

    // ✅ perKm → نحسب التوفير مقابل سيارة بنزين (transportCarGasolinePerKm)
    if (mode == 'perkm') {
      if (distanceKm <= 0) return 0.0;

      // actual = العامل المستدام (حافلة/مترو/غيره)
      String? actualRef =
          efRef ?? taskSnapshotOrMinimal['emissionFactorRef'] as String?;
      if (actualRef == null || actualRef.isEmpty) return 0.0;

      // baseline = من المهمة لو محدد، وإلا القيمة الافتراضية transportCarGasolinePerKm
      String baselineId =
          baselineRef ??
          (taskSnapshotOrMinimal['baselineFactorRef'] as String?) ??
          kDefaultTransportBaselineRef;

      if (baselineId.isEmpty) {
        // لو حتى الافتراضي مو موجود لأي سبب → نرجع للسلوك القديم (perKm * factor)
        final fAct = await _getFactorByRef(actualRef);
        if (fAct == null) return 0.0;
        final factor =
            _readEfValueFlexible(fAct, preferField: _efValueField) ?? 0.0;
        return _round2(distanceKm * factor);
      }

      final baseF = await _getFactorByRef(baselineId);
      final actF = await _getFactorByRef(actualRef);

      if (baseF == null || actF == null) return 0.0;

      final base =
          _readEfValueFlexible(baseF, preferField: _efValueField) ?? 0.0;
      final act = _readEfValueFlexible(actF, preferField: _efValueField) ?? 0.0;
      final delta = base - act;

      if (delta <= 0) return 0.0;
      return _round2(delta * distanceKm);
    }

    // deltaPerKm → baseline-actual لكل كم
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

    // ✅ deltaPerItem → (baseline - actual) لكل قطعة
    if (mode == 'deltaperitem') {
      if ((baselineRef ?? '').isEmpty || (efRef ?? '').isEmpty || count <= 0) {
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
      return _round2(delta * count);
    }

    // fallback perItem
    if ((efRef ?? '').isEmpty || count <= 0) return 0.0;
    final f = await _getFactorByRef(efRef!);
    if (f == null) return 0.0;
    final factor = _readEfValueFlexible(f, preferField: _efValueField) ?? 0.0;
    return _round2(count * factor);
  }

  // =====================================================
  // 🧮 deltaPerKm: تحسب الفرق فقط (baseline - actual) * km
  //    بدون أي تحديث في Firestore (التحديث يتم في _approve)
  // =====================================================
  Future<double> _computeDeltaPerKmValue({
    required Map<String, dynamic> task,
    required double distanceKm,
  }) async {
    try {
      if (distanceKm <= 0) {
        throw Exception('distanceKm يجب أن تكون أكبر من صفر');
      }

      // 1) refs من المهمة لو موجودة
      String? baselineRef =
          (task['baselineFactorRef'] ?? task['baseline_factor_ref'])
              ?.toString();
      String? actualRef =
          (task['emissionFactorRef'] ??
                  task['actualFactorRef'] ??
                  task['emission_factor_ref'])
              ?.toString();

      // 2) لو ناقصة نحاول نجيب وثيقة EF ونقرأ منها
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
      if (delta <= 0) {
        return 0.0;
      }

      final savedKg = delta * distanceKm;
      return savedKg;
    } catch (e) {
      return 0.0;
    }
  }

  // =================== الدالة الرئيسية (UI + اعتماد/رفض) ===================

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
                              if (v is Timestamp) {
                                return v.millisecondsSinceEpoch;
                              }
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
                                                        await _approve(d);
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
                                                    ? () => _reject(d)
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
          // ممكن تضيفين BottomNav لو حبيتي بعدين
        ),
      ),
    );
  }

  // ========= اعتماد/رفض =========
  Future<void> _approve(DocumentSnapshot subDoc) async {
    await _ensureAdminClaims();

    if (!_isAdmin) {
      if (!mounted) return;
      final messenger = ScaffoldMessenger.maybeOf(context);
      messenger?.showSnackBar(
        const SnackBar(content: Text('يحتاج صلاحية أدمن لاعتماد الطلب')),
      );
      return;
    }

    final data = subDoc.data() as Map<String, dynamic>;
    final userTaskDocId = (data['userTaskDocId'] ?? '').toString();
    final userId = (data['userId'] ?? '').toString();

    if (userTaskDocId.isEmpty || userId.isEmpty) {
      if (!mounted) return;
      final messenger = ScaffoldMessenger.maybeOf(context);
      messenger?.showSnackBar(
        const SnackBar(content: Text('الطلب ناقص userId/userTaskDocId')),
      );
      return;
    }

    final taskPoints = (data['taskPoints'] ?? 0) as int;
    final taskId = (data['taskId'] ?? '').toString();
    final taskTitle =
        (data['taskTitle'] ?? data['task_title'] ?? '(بدون عنوان)').toString();

    int _asInt(dynamic v) => (v is int) ? v : int.tryParse('${v ?? ''}') ?? 0;
    double _asDouble(dynamic v) =>
        (v is num) ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0.0;

    int itemCount = _asInt(
      data['itemCount'] ?? data['count'] ?? data['evidence']?['itemCount'],
    );

    final distanceKm = _asDouble(data['distanceKm']);
    double savedKgCO2 = _asDouble(data['carbonSaved']);

    final usersRef = FirebaseFirestore.instance.collection('users').doc(userId);
    final utRef = FirebaseFirestore.instance
        .collection('userTasks')
        .doc(userTaskDocId);
    final subRef = subDoc.reference;
    final admin = FirebaseAuth.instance.currentUser;

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
        if (sub['status'] != 'pending') {
          throw 'تمت معالجة هذا الطلب مسبقاً.';
        }

        final utSnap = await trx.get(utRef);
        if (!utSnap.exists) throw 'userTask غير موجود.';
        final ut = utSnap.data() as Map<String, dynamic>;
        final currentStatus = (ut['status'] as String?) ?? 'pending';
        final canComplete = currentStatus != 'completed';

        // ⚙️ لو savedKgCO2 <= 0 نحاول نعيد حسابه من عوامل الكربون
        if (savedKgCO2 <= 0) {
          // 👇 عدّلي أسماء الفيلدز حسب تركيب الـ task عندك لو مختلفة
          final baseKgCO2 = _asDouble(
            ut['baseKgCO2'] ??
                sub['baseKgCO2'] ??
                ut['factors']?['baseKgCO2'] ??
                sub['factors']?['baseKgCO2'],
          );
          final perItemKgCO2 = _asDouble(
            ut['perItemKgCO2'] ??
                sub['perItemKgCO2'] ??
                ut['factors']?['perItemKgCO2'] ??
                sub['factors']?['perItemKgCO2'],
          );
          final perKmKgCO2 = _asDouble(
            ut['perKmKgCO2'] ??
                sub['perKmKgCO2'] ??
                ut['factors']?['perKmKgCO2'] ??
                sub['factors']?['perKmKgCO2'],
          );

          final usedItemCount = itemCount > 0
              ? itemCount
              : _asInt(sub['itemCount'] ?? ut['itemCount']);

          final usedDistanceKm = distanceKm > 0
              ? distanceKm
              : _asDouble(sub['distanceKm'] ?? ut['distanceKm']);

          final recalculated =
              baseKgCO2 +
              perItemKgCO2 * usedItemCount +
              perKmKgCO2 * usedDistanceKm;
          if (recalculated > 0) {
            savedKgCO2 = recalculated;
          }
        }

        // 🔁 تحديث وثيقة submission
        final subUpdate = <String, dynamic>{
          'status': 'approved',
          'processedAt': FieldValue.serverTimestamp(),
          'processedBy': admin?.uid,
        };
        if (savedKgCO2 > 0) subUpdate['savedKgCO2'] = savedKgCO2;
        if (distanceKm > 0 && (sub['distanceKm'] == null)) {
          subUpdate['distanceKm'] = distanceKm;
        }
        if ((sub['itemCount'] == null || (sub['itemCount'] == 0)) &&
            itemCount > 0) {
          subUpdate['itemCount'] = itemCount;
        }
        trx.update(subRef, subUpdate);

        // 🔁 تحديث وثيقة userTask
        final utUpdate = <String, dynamic>{
          'status': 'completed',
          'completedAt': FieldValue.serverTimestamp(),
          'canRetry': false,
        };
        if (savedKgCO2 > 0) utUpdate['savedKgCO2'] = savedKgCO2;
        if (distanceKm > 0 && (ut['distanceKm'] == null)) {
          utUpdate['distanceKm'] = distanceKm;
        }
        if (itemCount > 0) utUpdate['itemCount'] = itemCount;
        trx.update(utRef, utUpdate);

        // 🪙 إضافة النقاط للمستخدم مرة واحدة فقط
        if (canComplete && taskPoints > 0) {
          trx.update(usersRef, {'points': FieldValue.increment(taskPoints)});
        }

        // 🕒 history log
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

        // 🔁 تحديث totalCarbonSaved + lastCarbonUpdateAt
        trx.set(usersRef, {
          'lastCarbonUpdateAt': FieldValue.serverTimestamp(),
          if (savedKgCO2 > 0)
            'totalCarbonSaved': FieldValue.increment(savedKgCO2),
        }, SetOptions(merge: true));

        // 📅 dayMarks
        trx.set(dayMarkRef, {
          'count': FieldValue.increment(1),
          'lastAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        // 🔔 إشعار للمستخدم
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
          if (distanceKm > 0) 'distanceKm': distanceKm,
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

      if (!mounted) return;
      final messenger = ScaffoldMessenger.maybeOf(context);
      messenger?.showSnackBar(
        const SnackBar(content: Text('تم اعتماد الطلب ✅')),
      );
    } catch (e) {
      if (!mounted) return;
      final messenger = ScaffoldMessenger.maybeOf(context);
      messenger?.showSnackBar(SnackBar(content: Text('خطأ: $e')));
    }
  }

  Future<void> _reject(DocumentSnapshot subDoc) async {
    await _ensureAdminClaims();

    if (!_isAdmin) {
      if (!mounted) return;
      final messenger = ScaffoldMessenger.maybeOf(context);
      messenger?.showSnackBar(
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
        if (sub['status'] != 'pending') {
          throw 'تمت معالجة هذا الطلب مسبقاً.';
        }

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
      final messenger = ScaffoldMessenger.maybeOf(context);
      messenger?.showSnackBar(const SnackBar(content: Text('تم رفض الطلب ❌')));
    } catch (e) {
      if (!mounted) return;
      final messenger = ScaffoldMessenger.maybeOf(context);
      messenger?.showSnackBar(SnackBar(content: Text('خطأ: $e')));
    }
  }
}
