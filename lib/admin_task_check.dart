import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'services/admin_bottom_nav.dart';
import 'admin_home.dart';
import 'admin_task.dart';
import 'admin_map.dart';
import 'services/background_container.dart';
import 'services/connection.dart';
import 'services/title_header.dart';
import '../services/app_colors.dart';

final _fs = FirebaseFirestore.instance;

// ——— إعدادات موحّدة لمجموعة العوامل ———
const String _efCollection = 'emissionFactors';
const String _efValueField = 'ef_kgco2_per_unit';

const String kDefaultTransportBaselineRef = 'transportCarGasolinePerKm';

class CarbonCalcResult {
  final double kgCO2;
  final String direction;
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

// double _numOr0(dynamic v) =>
//     (v is num) ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0.0;

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
// double? _readEfValue(Map<String, dynamic> efDoc) =>
//     _readEfValueFlexible(efDoc, preferField: _efValueField);

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
    //'ef_name': ef['name'],
    //'direction': direction,
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
      'actual_per_item': act,
      'baseline_per_item': base,
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

  // 👤 جلب اسم المستخدم من وثيقة users/{userId}
  Future<String> _getUserName(String userId) async {
    if (userId.isEmpty) return '';
    final snap = await FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .get();
    if (!snap.exists) return userId;
    final data = snap.data() ?? {};
    return data['name'] ?? data['username'] ?? userId;
  }

  // =================== helpers لحساب الكربون ===================

  // Future<Map<String, dynamic>?> _getFactorByRef(String refId) async {
  //   if (refId.isEmpty) return null;
  //   final snap = await FirebaseFirestore.instance
  //       .collection(_efCollection)
  //       .doc(refId)
  //       .get();
  //   if (!snap.exists) return null;
  //   return snap.data() as Map<String, dynamic>?;
  // }

  // double _round2(double v) => (v * 100).roundToDouble() / 100.0;

  // =====================================================
  // 🧮 deltaPerKm: تحسب الفرق فقط (baseline - actual) * km
  //    بدون أي تحديث في Firestore (التحديث يتم في _approve)
  // =====================================================
  // Future<double> _computeDeltaPerKmValue({
  //   required Map<String, dynamic> task,
  //   required double distanceKm,
  // }) async {
  //   try {
  //     if (distanceKm <= 0) {
  //       throw Exception('distanceKm يجب أن تكون أكبر من صفر');
  //     }

  //     // 1) refs من المهمة لو موجودة
  //     String? baselineRef =
  //         (task['baselineFactorRef'] ?? task['baseline_factor_ref'])
  //             ?.toString();
  //     String? actualRef =
  //         (task['emissionFactorRef'] ??
  //                 task['actualFactorRef'] ??
  //                 task['emission_factor_ref'])
  //             ?.toString();

  //     // 2) لو ناقصة نحاول نجيب وثيقة EF ونقرأ منها
  //     Future<Map<String, dynamic>?> _loadEfFromTaskOrResolve() async {
  //       final taskEfId =
  //           (task['emissionFactorRef'] ?? task['emission_factor_ref'])
  //               ?.toString();
  //       if (taskEfId != null && taskEfId.isNotEmpty) {
  //         return await _getEfDoc(taskEfId);
  //       }
  //       return await resolveEmissionFactorForTask(task);
  //     }

  //     if ((baselineRef == null || baselineRef.isEmpty) ||
  //         (actualRef == null || actualRef.isEmpty)) {
  //       final efDoc = await _loadEfFromTaskOrResolve();
  //       if (efDoc != null) {
  //         baselineRef ??=
  //             (efDoc['baselineFactorRef'] ?? efDoc['baseline_factor_ref'])
  //                 ?.toString();
  //         actualRef ??=
  //             (efDoc['actualFactorRef'] ??
  //                     efDoc['emissionFactorRef'] ??
  //                     efDoc['actual_factor_ref'] ??
  //                     efDoc['emission_factor_ref'])
  //                 ?.toString();
  //       }
  //     }

  //     if (baselineRef == null ||
  //         baselineRef.isEmpty ||
  //         actualRef == null ||
  //         actualRef.isEmpty) {
  //       final idOrTitle = task['id'] ?? task['title'] ?? '(task?)';
  //       throw Exception(
  //         'baseline/actual factor refs مفقودة (task=$idOrTitle). تأكد من baselineFactorRef و actualFactorRef في EF.',
  //       );
  //     }

  //     Future<double?> _getVal(String id) async {
  //       final snap = await FirebaseFirestore.instance
  //           .collection(_efCollection)
  //           .doc(id)
  //           .get();
  //       if (!snap.exists) return null;
  //       final m = snap.data() as Map<String, dynamic>?;
  //       if (m == null) return null;
  //       return _readEfValueFlexible(m, preferField: _efValueField);
  //     }

  //     final base = await _getVal(baselineRef) ?? 0.0;
  //     final act = await _getVal(actualRef) ?? 0.0;
  //     final delta = base - act;
  //     if (delta <= 0) {
  //       return 0.0;
  //     }

  //     final savedKg = delta * distanceKm;
  //     return savedKg;
  //   } catch (e) {
  //     return 0.0;
  //   }
  // }

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
                              color: appColors.dark,
                            ),
                          ),
                          const SizedBox(width: 10),
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
                                        color: appColors.dark,
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
                                          : 'لا توجد طلبات قيد الانتظار خاصة بالحساب.',
                                      style: GoogleFonts.ibmPlexSansArabic(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: appColors.dark,
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

                                final countStr =
                                    (m['itemCount'] ?? m['count'])
                                        ?.toString() ??
                                    '';
                                final km = (m['distanceKm']?.toString() ?? '');

                                final userId = (m['userId'] ?? '').toString();

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
                                            color: appColors.dark,
                                          ),
                                        ),
                                        const SizedBox(height: 4),

                                        FutureBuilder<String>(
                                          future: _getUserName(userId),
                                          builder: (context, snapName) {
                                            final userName =
                                                snapName.data ?? userId;
                                            return Text(
                                              'المستخدم: $userName • النقاط: ${m['taskPoints'] ?? 0}',
                                              style:
                                                  GoogleFonts.ibmPlexSansArabic(
                                                    fontSize: 13,
                                                    color: Colors.grey[700],
                                                  ),
                                            );
                                          },
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

                                        // 🔘 أزرار الاعتماد / الرفض — أخضر / أحمر وتعطيل رمادي
                                        Row(
                                          children: [
                                            Expanded(
                                              child: FilledButton.icon(
                                                style: FilledButton.styleFrom(
                                                  backgroundColor: Color(
                                                    0xFF009688,
                                                  ), // أخضر
                                                  disabledBackgroundColor:
                                                      Colors.grey[300],
                                                  foregroundColor: Colors.white,
                                                  disabledForegroundColor:
                                                      Colors.grey[600],
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        vertical: 12,
                                                      ),
                                                ),
                                                onPressed: _isAdmin
                                                    ? () async {
                                                        await _approve(d);
                                                      }
                                                    : null,
                                                icon: const Icon(
                                                  Icons.check_circle_outline,
                                                ),
                                                label: const Text('اعتماد'),
                                              ),
                                            ),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: FilledButton.icon(
                                                style: FilledButton.styleFrom(
                                                  backgroundColor:
                                                      slackMesseges.red, // أحمر
                                                  disabledBackgroundColor:
                                                      Colors.grey[300],
                                                  foregroundColor: Colors.white,
                                                  disabledForegroundColor:
                                                      Colors.grey[600],
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        vertical: 12,
                                                      ),
                                                ),
                                                onPressed: _isAdmin
                                                    ? () => _reject(d)
                                                    : null,
                                                icon: const Icon(
                                                  Icons.cancel_outlined,
                                                ),
                                                label: const Text('رفض'),
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
        SnackBar(
          backgroundColor: slackMesseges.red,
          content: Text(
            'يحتاج صلاحية أدمن لاعتماد الطلب',
            style: GoogleFonts.ibmPlexSansArabic(
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ),
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
        SnackBar(
          backgroundColor: slackMesseges.red,
          content: Text(
            'تعذّر تنفيذ الطلب — بيانات أساسية مفقودة',
            style: GoogleFonts.ibmPlexSansArabic(
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ),
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

        // ✅ نقرأ قيمة الكربون المحفوظة من complete_task.dart
        final carbonSaved = _asDouble(
          ut['carbonSaved'] ??
              sub['carbonSaved'] ??
              ut['savedKgCO2'] ?? // للتوافق مع البيانات القديمة لو موجودة
              sub['savedKgCO2'] ?? // للتوافق مع البيانات القديمة لو موجودة
              data['carbonSaved'],
        );

        // 🔁 تحديث وثيقة submission
        final subUpdate = <String, dynamic>{
          'status': 'approved',
          //'processedAt': FieldValue.serverTimestamp(),
          //'processedBy': admin?.uid,
        };
        if (carbonSaved > 0) subUpdate['carbonSaved'] = carbonSaved;
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
        if (carbonSaved > 0) utUpdate['carbonSaved'] = carbonSaved;
        if (distanceKm > 0 && (ut['distanceKm'] == null)) {
          utUpdate['distanceKm'] = distanceKm;
        }
        if (itemCount > 0) utUpdate['itemCount'] = itemCount;
        trx.update(utRef, utUpdate);

        // 🪙 إضافة النقاط + عدد المهام المكتملة للمستخدم مرة واحدة فقط
        if (canComplete && taskPoints > 0) {
          trx.update(usersRef, {
            'points': FieldValue.increment(taskPoints),
            'completedTask': FieldValue.increment(
              1,
            ), // 🔢 يزيد 1 (حتى لو الحقل مو موجود، Firestore ينشئه)
          });
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
        if (carbonSaved > 0) histData['carbonSaved'] = carbonSaved;
        if (itemCount > 0) histData['itemCount'] = itemCount;
        trx.set(historyRef, histData);

        // 🔁 تحديث totalCarbonSaved + lastCarbonUpdateAt
        trx.set(usersRef, {
          'lastCarbonUpdateAt': FieldValue.serverTimestamp(),
          if (carbonSaved > 0)
            'totalCarbonSaved': FieldValue.increment(carbonSaved),
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
          carbonSaved.isFinite && carbonSaved >= 0 ? carbonSaved : 0.0,
        );
        trx.set(notifRef, {
          'type': 'submission_approved',
          'userId': userId,
          'submissionId': subRef.id,
          'taskTitle': taskTitle,
          'points': taskPoints,
          //'carbonSaved': carbonSaved.isFinite ? carbonSaved : 0.0,
          if (distanceKm > 0) 'distanceKm': distanceKm,
          if (itemCount > 0) 'itemCount': itemCount,
          'createdAt': FieldValue.serverTimestamp(),
          'seen': false,
          'title': 'تم اعتماد المهمة 🎉',
          'body': 'أُضيفت $taskPoints نقطة • وفَّرت $carbonText كجم CO₂ 🌿',
          'message':
              'تم اعتماد طلبك لمهمة: $taskTitle — نقاط: $taskPoints • توفير: $carbonText كجم CO₂',
        });
      });

      if (!mounted) return;
      final messenger = ScaffoldMessenger.maybeOf(context);
      messenger?.showSnackBar(
        SnackBar(
          backgroundColor: slackMesseges.primary,
          content: Text(
            'تم اعتماد الطلب بنجاح ✅',
            style: GoogleFonts.ibmPlexSansArabic(
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      final messenger = ScaffoldMessenger.maybeOf(context);
      messenger?.showSnackBar(
        SnackBar(
          backgroundColor: slackMesseges.red,
          content: Text(
            'خطأ: $e',
            style: GoogleFonts.ibmPlexSansArabic(
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ),
      );
    }
  }

  Future<void> _reject(DocumentSnapshot subDoc) async {
    await _ensureAdminClaims();

    if (!_isAdmin) {
      if (!mounted) return;
      final messenger = ScaffoldMessenger.maybeOf(context);
      messenger?.showSnackBar(
        SnackBar(
          backgroundColor: slackMesseges.red,
          content: Text(
            'يحتاج صلاحية أدمن لرفض الطلب',
            style: GoogleFonts.ibmPlexSansArabic(
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ),
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
          //'processedAt': FieldValue.serverTimestamp(),
          //'processedBy': admin?.uid,
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
          final taskTitle = (data['taskTitle'] ?? '').toString();
          trx.set(notifRef, {
            'type': 'submission_rejected',
            'userId': userId,
            'submissionId': subRef.id,
            'taskTitle': taskTitle,
            'createdAt': FieldValue.serverTimestamp(),
            'seen': false,
            'title': 'تم رفض الطلب ❌',
            'body':
                'تم رفض طلبك لمهمة: $taskTitle. يمكنك إعادة المحاولة بعد التعديل.',
            'message': 'تم رفض طلبك لمهمة: $taskTitle',
          });
        }
      });

      if (!mounted) return;
      final messenger = ScaffoldMessenger.maybeOf(context);
      messenger?.showSnackBar(
        SnackBar(
          backgroundColor: slackMesseges.primary,
          content: Text(
            'تم رفض الطلب ✅',
            style: GoogleFonts.ibmPlexSansArabic(
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      final messenger = ScaffoldMessenger.maybeOf(context);
      messenger?.showSnackBar(
        SnackBar(
          backgroundColor: slackMesseges.red,
          content: Text(
            'خطأ: $e',
            style: GoogleFonts.ibmPlexSansArabic(
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ),
      );
    }
  }
}
