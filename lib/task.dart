import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:math';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'dart:convert';

import 'home.dart';
import 'map.dart';
import 'levels.dart';
import 'community.dart';
import 'article.dart';
import 'services/bottom_nav.dart';
import 'services/background_container.dart';
import 'services/connection.dart';
import 'services/title_header.dart';
import 'complete_task.dart'; // يحتوي على CompleteTaskSheet

class AppColors {
  static const primary = Color(0xFF4BAA98);
  static const dark = Color(0xFF3C3C3B);
  static const accent = Color(0xFFF4A340);
  static const sea = Color(0xFF1F7A8C);
  static const primary60 = Color(0x994BAA98);
  static const primary33 = Color(0x544BAA98); // شفافية خفيفة
  static const light = Color(0xFF79D0BE);
  static const background = Color(0xFFF3FAF7);
  static const mint = Color(0xFFB6E9C1);
  static const tealSoft = Color(0xFF75BCAF);
}

class taskPage extends StatefulWidget {
  const taskPage({super.key});

  @override
  State<taskPage> createState() => _taskPageState();
}

class _taskPageState extends State<taskPage> {
  final int _currentIndex = 1;

  bool _isInitializing = true;

  // ✅ فحص تمهيدي لمنع الدوران اللانهائي
  bool _precheckDone = false;
  String? _precheckError;

  // ✅ تحميل الشهر المعروض (lazy)
  bool _isMonthLoading = false;

  void _onTap(int i) {
    if (i == _currentIndex) return;
    switch (i) {
      case 0:
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const homePage()),
        );
        break;
      case 1:
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const taskPage()),
        );
        break;
      case 2:
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const levelsPage()),
        );
        break;
      case 3:
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const mapPage()),
        );
        break;
      case 4:
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const communityPage()),
        );
        break;
    }
  }

  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  final _auth = FirebaseAuth.instance;
  String? _uid;
  DateTime? _joinDate;
  Stream<DocumentSnapshot>? _userTaskStream;
  Map<DateTime, String> _monthStatuses = {};

  DateTime _dayStart(DateTime d) => DateTime(d.year, d.month, d.day);
  DateTime _dayEnd(DateTime d) => _dayStart(
    d,
  ).add(const Duration(days: 1)).subtract(const Duration(seconds: 1));
  String _yyyyMMdd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
  bool _isCompletedDay(DateTime d) =>
      _monthStatuses[_dateOnly(d)] == 'completed';

  void _updateMonthStatusFor(DateTime day, String status) {
    final key = _dateOnly(day);
    if (_monthStatuses[key] == status) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _monthStatuses[key] = status;
      });
    });
  }

  List<String> _remainingTaskIds = [];

  DateTime _monthStart(DateTime d) => DateTime(d.year, d.month, 1);
  DateTime _monthEnd(DateTime d) => DateTime(d.year, d.month + 1, 0);

  // ====================
  // جلب خبر جديد للمستخدم (مقال ما قد انعرض له من قبل)
  // ====================
  // Future<Map<String, dynamic>?> getFreshNewsForUser(String uid) async {
  //   try {
  //     // 1) نجلب آخر 30 مقال من كولكشن المقالات (مصدر الأخبار)
  //     final snap = await FirebaseFirestore.instance
  //         .collection('articles')
  //         .orderBy('createdAt', descending: true)
  //         .limit(30)
  //         .get();

  //     if (snap.docs.isEmpty) return null;

  //     // 2) نجلب كل مهام الأخبار اللي سبق نُسبت لهذا المستخدم
  //     //    سواء كانت "pending" أو "completed" أو أي حالة
  //     final usedSnap = await FirebaseFirestore.instance
  //         .collection('userTasks')
  //         .where('userId', isEqualTo: uid)
  //         .where(
  //           'taskType',
  //           isEqualTo: 'news',
  //         ) // إحنا كنا نضبطها في إنشاء المهمة
  //         .get();

  //     // نكوّن set بكل الروابط اللي سبق استخدمناها
  //     final usedUrls = usedSnap.docs
  //         .map((d) => d.data()['articleUrl'])
  //         .where((u) => u != null && u.toString().isNotEmpty)
  //         .map((u) => u.toString())
  //         .toSet();

  //     // 3) نرجّع أول مقال جديد وصالح
  //     for (var doc in snap.docs) {
  //       final data = doc.data();
  //       final url = (data['url'] ?? '').toString();
  //       final contentRaw = (data['content'] ?? '').toString();
  //       final content = contentRaw.trim();
  //       final lower = content.toLowerCase();

  //       if (url.isEmpty) continue;

  //       // ⛔ لا نريد مقالات سبق ظهرت في userTasks لهذا المستخدم
  //       if (usedUrls.contains(url)) {
  //         continue;
  //       }

  //       // ⛔ استبعاد المقالات المدفوعة / paywalled
  //       if (lower.contains('only paid') ||
  //           lower.contains('paid subscribers') ||
  //           lower.contains('subscription required')) {
  //         continue;
  //       }
  //       // ⛔ استبعاد المقالات القصيرة جدًا (واضح إنها مو نص حقيقي)
  //       if (content.length < 80) {
  //         continue;
  //       }

  //       // ✅ أول مقال مناسب
  //       return {'docId': doc.id, ...data};
  //     }

  //     // لو ما لقينا أي مقال مناسب
  //     return null;
  //   } catch (e) {
  //     return null;
  //   }
  // }

  /// =======================================================
  /// 1) جلب مقال جديد للمستخدم (لا يُكرر + يسحب من API عند الحاجة)
  /// =======================================================
  Future<Map<String, dynamic>?> getFreshNewsForUser(String uid) async {
    final firestore = FirebaseFirestore.instance;

    // ========== 1) جلب المقالات من Firestore ==========
    Future<Map<String, dynamic>?> tryFromFirestore() async {
      final articlesSnap = await firestore
          .collection('articles')
          .orderBy('publishedAt', descending: true)
          .limit(50)
          .get();

      if (articlesSnap.docs.isEmpty) return null;

      // كل المقالات اللي سبق ظهرت للمستخدم
      final usedSnap = await firestore
          .collection('userTasks')
          .where('userId', isEqualTo: uid)
          .where('taskTitle', isEqualTo: 'قراءة خبر بيئي')
          .get();

      final usedIds = usedSnap.docs
          .map((d) => d.data()['articleId'])
          .where((x) => x != null)
          .toSet();

      // ابحث عن أول مقال جديد ما شافه المستخدم
      for (var doc in articlesSnap.docs) {
        if (!usedIds.contains(doc.id)) {
          return {'docId': doc.id, ...doc.data()};
        }
      }

      return null; // لا يوجد مقال جديد موجود أصلاً
    }

    // ========== 2) جلب مقال جديد من Firestore أولاً ==========
    final firstTry = await tryFromFirestore();
    if (firstTry != null) {
      return firstTry; // ممتاز — لقينا مقال جاهز
    }

    // ========== 3) لو ما فيه مقالات جديدة → نجيب من NewsData.io ==========
    const apiKey = "pub_c9084d601ff6465289bd682c942dec4c";
    const query =
        "البيئة OR المناخ OR الاستدامة OR الطاقة النظيفة OR تدوير OR نفايات OR تلوث OR انبعاثات OR تشجير";

    final apiUrl = Uri.parse(
      "https://newsdata.io/api/1/news?apikey=$apiKey&q=$query&language=ar&category=environment",
    );

    try {
      final res = await http.get(apiUrl);

      if (res.statusCode != 200) {
        print("❌ News API Error: ${res.statusCode}");
        return null;
      }

      final body = jsonDecode(res.body);
      final List results = body["results"] ?? [];

      if (results.isEmpty) return null;

      // الكلمات المفتاحية لمنع أي مقال غير بيئي
      final keywords = [
        'البيئة',
        'استدامة',
        'تدوير',
        'إعادة تدوير',
        'تلوث',
        'احتباس حراري',
        'كربون',
        'طاقة متجددة',
        'نفايات',
        'تشجير',
        'هواء نقي',
        'مناخ',
        'انبعاثات',
        'محميات',
        'تغير المناخ',
        'طاقة نظيفة',
        'مصادر طبيعية',
      ];

      // نجيب المقالات المخزنة سابقًا لمنع التكرار
      final existing = await firestore.collection('articles').get();
      final existingTitles = existing.docs
          .map((d) => (d.data()['title'] ?? '').toString().trim())
          .toSet();

      // فلترة نتائج الـ API
      final filtered = results.where((art) {
        final merged =
            ((art['title'] ?? '') +
                    ' ' +
                    (art['full_content'] ?? '') +
                    ' ' +
                    (art['description'] ?? ''))
                .toLowerCase();

        return keywords.any((k) => merged.contains(k));
      }).toList();

      if (filtered.isEmpty) {
        print("⚠️ No environmental articles matched filters");
        return null;
      }

      // تخزين مقالات جديدة فقط (بدون تكرار)
      for (final rawArt in filtered) {
        final title = (rawArt['title'] ?? '').toString().trim();
        if (title.isEmpty) continue;

        if (existingTitles.contains(title)) continue;

        final content =
            (rawArt['full_content'] ??
                    rawArt['content'] ??
                    rawArt['description'] ??
                    '')
                .toString();

        if (content.length < 80) continue; // محتوى غير صالح

        await firestore.collection('articles').add({
          'title': title,
          'description': rawArt['description'] ?? '',
          'content': content,
          'url': rawArt['link'] ?? '',
          'urlToImage': rawArt['image_url'] ?? '',
          'sourceName': rawArt['source_id'] ?? '',
          'publishedAt': rawArt['pubDate'] ?? '',
          //'language': 'ar',
          'category': 'environment',
          //'createdAt': FieldValue.serverTimestamp(),
        });

        existingTitles.add(title); // منع التكرار لاحقًا
      }

      // ========== 4) المحاولة الثانية بعد التخزين ==========
      return await tryFromFirestore();
    } catch (e) {
      print("❌ NewsData fetch failed: $e");
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  // =======================
  // ✅ تهيئة خفيفة: اليوم فقط + حالة الشهر الحالي
  // =======================
  Future<void> _initializeApp() async {
    try {
      final user = _auth.currentUser;
      _uid = user?.uid;
      _selectedDay = _dayStart(DateTime.now());
      _focusedDay = _selectedDay!;

      if (!await hasInternetConnection()) {
        if (mounted) showNoInternetDialog(context);
      }

      await _bootstrapTodayOnly();
      await _precheckTodayDoc();
    } catch (e, st) {
      debugPrint('❌ _initializeApp error: $e\n$st');
      if (mounted) {
        setState(() {
          _precheckError = e.toString();
          _precheckDone = true;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isInitializing = false;
        });
      }
    }
  }

  Future<void> _bootstrapTodayOnly() async {
    final user = _auth.currentUser;
    if (user == null) return;

    final today = _dayStart(DateTime.now());

    await Future.wait([
      _loadUserJoinDate(user, today),
      _ensureUserTaskForDate(today),
      _ensureUserTaskForDate(today.add(const Duration(days: 1))),
    ]);

    _getTaskStatusesForMonth(today).then((statuses) {
      if (mounted) {
        setState(() {
          _monthStatuses = statuses;
        });
      }
    });
  }

  Future<void> _precheckTodayDoc() async {
    if (_uid == null) {
      setState(() {
        _precheckDone = true;
        _precheckError = 'unauthenticated';
      });
      return;
    }

    try {
      final sel = _selectedDay ?? _dayStart(DateTime.now());
      final key = '${_uid!}_${_yyyyMMdd(sel)}';
      final ref = FirebaseFirestore.instance.collection('userTasks').doc(key);

      var snap = await ref.get().timeout(
        const Duration(seconds: 8),
        onTimeout: () => throw TimeoutException('timeout-get-userTask'),
      );

      if (!snap.exists) {
        await _ensureUserTaskForDate(sel);
        snap = await ref.get().timeout(
          const Duration(seconds: 8),
          onTimeout: () =>
              throw TimeoutException('timeout-get-userTask-after-create'),
        );
      }

      _attachUserTaskStreamFor(sel);

      if (mounted) {
        setState(() {
          _precheckDone = true;
          _precheckError = null;
        });
      }
    } on TimeoutException catch (e) {
      if (mounted) {
        setState(() {
          _precheckDone = true;
          _precheckError = e.message ?? 'timeout';
        });
      }
    } on FirebaseException catch (e) {
      if (mounted) {
        setState(() {
          _precheckDone = true;
          _precheckError = e.code;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _precheckDone = true;
          _precheckError = e.toString();
        });
      }
    }
  }

  Future<void> _loadUserJoinDate(User user, DateTime today) async {
    DateTime authCreated = user.metadata.creationTime?.toLocal() ?? today;
    DateTime? usersJoin;

    final udoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();

    if (udoc.exists && (udoc.data()?['joinDate'] != null)) {
      final v = udoc.data()!['joinDate'];
      if (v is Timestamp) {
        usersJoin = v.toDate();
      } else if (v is DateTime) {
        usersJoin = v;
      }
    }

    DateTime resolvedJoin = usersJoin == null
        ? authCreated
        : (authCreated.isBefore(usersJoin!) ? authCreated : usersJoin!);
    if (_dayStart(resolvedJoin).isAfter(today)) resolvedJoin = today;

    _joinDate = _dayStart(resolvedJoin);
  }

  // =======================
  // ✅ backfill لشهر واحد فقط (يُستدعى عند تغيير الشهر)
  // =======================
  Future<void> _ensureMonthBackfill(DateTime anyDayInMonth) async {
    if (_uid == null) return;
    final ms = _monthStart(anyDayInMonth);
    final me = _monthEnd(anyDayInMonth);

    for (DateTime d = ms; !d.isAfter(me); d = d.add(const Duration(days: 1))) {
      if (_joinDate != null && d.isBefore(_joinDate!)) continue;
      await _ensureUserTaskForDate(d);
    }

    final today = _dayStart(DateTime.now());
    _attachUserTaskStreamFor(_selectedDay ?? today);
  }

  // ✅ دالة خاصة لتحميل شهر معيّن بشكل جزئي/كسول
  Future<void> _loadMonth(DateTime month) async {
    if (_uid == null) return;
    setState(() {
      _isMonthLoading = true;
    });

    try {
      // إنشاء مهام الشهر (بدون الشهر السابق)
      await _ensureMonthBackfill(month);

      final statuses = await _getTaskStatusesForMonth(month);
      if (!mounted) return;
      setState(() {
        _monthStatuses = statuses;
      });
    } catch (e, st) {
      debugPrint('❌ _loadMonth error: $e\n$st');
    } finally {
      if (mounted) {
        setState(() {
          _isMonthLoading = false;
        });
      }
    }
  }

  Future<Map<DateTime, String>> _getTaskStatusesForMonth(DateTime month) async {
    if (_uid == null) return {};
    final ms = _monthStart(month);
    final me = _monthEnd(month);

    try {
      final qs = await FirebaseFirestore.instance
          .collection('userTasks')
          .where('userId', isEqualTo: _uid)
          .where('selectedAt', isGreaterThanOrEqualTo: Timestamp.fromDate(ms))
          .where('selectedAt', isLessThanOrEqualTo: Timestamp.fromDate(me))
          .get();

      final map = <DateTime, String>{};
      for (var doc in qs.docs) {
        final data = doc.data();
        final status = data['status'] as String? ?? 'pending';
        final day = (data['selectedAt'] as Timestamp).toDate();
        map[DateTime(day.year, day.month, day.day)] = status;
      }
      return map;
    } on FirebaseException catch (e) {
      if (e.code == 'failed-precondition') {
        final all = await FirebaseFirestore.instance
            .collection('userTasks')
            .where('userId', isEqualTo: _uid)
            .get();

        final map = <DateTime, String>{};
        for (final doc in all.docs) {
          final data = doc.data();
          final ts = data['selectedAt'];
          if (ts is! Timestamp) continue;
          final day = ts.toDate();
          if (day.isBefore(ms) || day.isAfter(me)) continue;
          final status = data['status'] as String? ?? 'pending';
          map[DateTime(day.year, day.month, day.day)] = status;
        }
        return map;
      }
      rethrow;
    }
  }

  // =============================================================
  // ✅ تحديث مهمة اليوم المختار (عند الضغط على "تجديد المهمة")
  // =============================================================
  Future<void> _refreshUserTask(Map<String, dynamic> currentTask) async {
    if (_uid == null || _selectedDay == null) return;

    final selected = _dayStart(_selectedDay!);
    final monthKey =
        "${selected.year}-${selected.month.toString().padLeft(2, '0')}";
    final utKey = '${_uid!}_${_yyyyMMdd(selected)}';
    final utRef = FirebaseFirestore.instance.collection('userTasks').doc(utKey);

    // 🟩 1) جلب المهام الفعالة من كولكشن tasks (يختار المهام الحالية فقط)
    final tasksSnap = await FirebaseFirestore.instance
        .collection('tasks')
        .where('status', isEqualTo: 'active')
        .get();

    final validTasks = tasksSnap.docs.where((doc) {
      final data = doc.data();
      dynamic vf = data['visible_from'];
      dynamic em = data['expiry_month'];
      String? visibleFrom, expiryMonth;

      if (vf is Timestamp) {
        final d = vf.toDate();
        visibleFrom = "${d.year}-${d.month.toString().padLeft(2, '0')}";
      } else if (vf is String) {
        visibleFrom = vf;
      }
      if (em is Timestamp) {
        final d = em.toDate();
        expiryMonth = "${d.year}-${d.month.toString().padLeft(2, '0')}";
      } else if (em is String) {
        expiryMonth = em;
      }

      final isVisible =
          (visibleFrom == null) || (visibleFrom.compareTo(monthKey) <= 0);
      final notExpired =
          (expiryMonth == null) || (expiryMonth.compareTo(monthKey) >= 0);
      return isVisible && notExpired;
    }).toList();

    if (validTasks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'لا توجد مهام مُتاحة لهذا الشهر.',
            style: GoogleFonts.ibmPlexSansArabic(color: Colors.white),
          ),
          backgroundColor: AppColors.primary,
        ),
      );
      return;
    }

    // 🟨 2) نتجنب تكرار مهمة الأمس أو الغد
    final yesterday = _dayStart(selected.subtract(const Duration(days: 1)));
    final tomorrow = _dayStart(selected.add(const Duration(days: 1)));

    final yKey = '${_uid!}_${_yyyyMMdd(yesterday)}';
    final tKey = '${_uid!}_${_yyyyMMdd(tomorrow)}';
    final ySnap = await FirebaseFirestore.instance
        .collection('userTasks')
        .doc(yKey)
        .get();
    final tSnap = await FirebaseFirestore.instance
        .collection('userTasks')
        .doc(tKey)
        .get();

    final yTaskId = (ySnap.exists)
        ? (ySnap.data()?['taskId'] as String?)
        : null;
    final tTaskId = (tSnap.exists)
        ? (tSnap.data()?['taskId'] as String?)
        : null;
    final currentTaskId =
        (currentTask['taskId'] ?? currentTask['id']) as String?;

    final excluded = <String?>{currentTaskId, yTaskId, tTaskId}
      ..removeWhere((e) => e == null);
    final pool = validTasks.where((doc) => !excluded.contains(doc.id)).toList();
    final finalPool = pool.isEmpty ? validTasks : pool;

    // 📰 3) نحاول نجيب خبر جديد (من الـ API أو من المقالات)
    final freshNews = await getFreshNewsForUser(_uid!);
    bool hasFreshNews = freshNews != null;

    // 🧩 4) نجمع المهام العادية + مهمة الخبر في قائمة واحدة
    List newPool = [];
    // نضيف مهمة الخبر فقط بنسبة 30٪ مثلاً
    if (hasFreshNews && Random().nextDouble() < 0.3) {
      newPool.add(null);
    }
    newPool.addAll(finalPool);

    // 🌀 5) اختيار مهمة عشوائية
    final rnd = Random(DateTime.now().millisecondsSinceEpoch);
    final picked = newPool[rnd.nextInt(newPool.length)];

    // 📰 6) لو اختير "مهمة خبر" → نربطها بمهمة الأدمن المحددة ID ونقرأ تفاصيلها من Firestore
    if (picked == null && hasFreshNews) {
      final news = freshNews!;
      const newsTaskId =
          "bJjITCm7ZWlmzEk2QNPr"; // ← ID مهمة "قراءة خبر بيئي" من الأدمن

      // 🔹 نحضر بيانات مهمة الأدمن كاملة
      final taskSnap = await FirebaseFirestore.instance
          .collection('tasks')
          .doc(newsTaskId)
          .get();

      if (!taskSnap.exists) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'تعذّر تحميل مهمة قراءة الخبر البيئي. يرجى المحاولة لاحقًا.',
              style: GoogleFonts.ibmPlexSansArabic(color: Colors.white),
            ),
            backgroundColor: Colors.redAccent,
          ),
        );
        return;
      }

      final taskData = taskSnap.data() ?? {};

      // 🔹 نكتبها داخل userTasks مع ربط المقال
      await utRef.update({
        'taskId': newsTaskId,
        'taskTitle': taskData['title'] ?? '(بدون عنوان)',
        'taskDescription': taskData['description'] ?? '',
        'taskPoints': taskData['points'] ?? 0,
        'taskValidation': taskData['validationStrategy'] ?? 'غير محددة',
        'articleId': news['docId'],
      });

      _attachUserTaskStreamFor(selected);
      return;
    }

    // 🟩 7) مهمة عادية (غير خبر)
    final pickedData = picked.data();
    final denorm = {
      'taskTitle': pickedData['title'] ?? '(بدون عنوان)',
      'taskDescription': pickedData['description'] ?? '',
      'taskPoints': pickedData['points'] ?? 0,
      'taskValidation': pickedData['validationStrategy'] ?? 'غير محددة',
    };

    await utRef.update({'taskId': picked.id, ...denorm});
    _attachUserTaskStreamFor(selected);
  }

  // =============================================================
  // ✅ إنشاء مهمة اليوم للمستخدم (لو ما عنده مهمة لهذا اليوم)
  // =============================================================
  Future<void> _ensureUserTaskForDate(DateTime day) async {
    if (_uid == null) return;

    final today = _dayStart(DateTime.now());
    if (_joinDate != null && day.isBefore(_joinDate!)) return;

    final key = '${_uid!}_${_yyyyMMdd(day)}';
    final ref = FirebaseFirestore.instance.collection('userTasks').doc(key);
    final snap = await ref.get();
    if (snap.exists) return;

    final monthKey = "${day.year}-${day.month.toString().padLeft(2, '0')}";

    // 🟩 1) نحضر المهام الفعالة حسب الشهر
    final tasksSnap = await FirebaseFirestore.instance
        .collection('tasks')
        .where('status', isEqualTo: 'active')
        .get();

    final validTasks = tasksSnap.docs.where((doc) {
      final data = doc.data();
      dynamic vf = data['visible_from'];
      dynamic em = data['expiry_month'];
      String? visibleFrom;
      String? expiryMonth;

      if (vf is Timestamp) {
        final d = vf.toDate();
        visibleFrom = "${d.year}-${d.month.toString().padLeft(2, '0')}";
      } else if (vf is String)
        visibleFrom = vf;
      if (em is Timestamp) {
        final d = em.toDate();
        expiryMonth = "${d.year}-${d.month.toString().padLeft(2, '0')}";
      } else if (em is String)
        expiryMonth = em;

      final isVisible =
          (visibleFrom == null) || (visibleFrom.compareTo(monthKey) <= 0);
      final notExpired =
          (expiryMonth == null) || (expiryMonth.compareTo(monthKey) >= 0);
      return isVisible && notExpired;
    }).toList();

    if (validTasks.isEmpty) return;

    // 🟨 2) نتجنب تكرار مهمة الأمس
    final yesterday = _dayStart(day.subtract(const Duration(days: 1)));
    final yKey = '${_uid!}_${_yyyyMMdd(yesterday)}';
    final ySnap = await FirebaseFirestore.instance
        .collection('userTasks')
        .doc(yKey)
        .get();
    final yTaskId = (ySnap.exists)
        ? (ySnap.data()?['taskId'] as String?)
        : null;

    final excludedIds = {yTaskId}..removeWhere((id) => id == null);
    final candidates = validTasks
        .where((doc) => !excludedIds.contains(doc.id))
        .toList();
    final filteredTasks = candidates.isEmpty ? validTasks : candidates;

    // 📰 3) جلب خبر جديد فقط إذا اليوم = اليوم الحالي
    final bool isToday = _dayStart(day) == today;
    final freshNews = isToday ? await getFreshNewsForUser(_uid!) : null;
    bool canShowNews = freshNews != null;

    // 🧩 4) بناء pool يشمل مهام + خبر
    List newPool = [];
    if (canShowNews) newPool.add(null); // null = مهمة خبر
    newPool.addAll(filteredTasks);

    // 🎲 5) اختيار مهمة عشوائية
    final rnd = Random(
      DateTime.now().millisecondsSinceEpoch ^ day.millisecondsSinceEpoch,
    );
    final picked = newPool[rnd.nextInt(newPool.length)];

    // ⏰ تجهيز الوقت والحالة
    final start = _dayStart(day);
    final end = _dayEnd(day);
    final String status = day.isBefore(today) ? 'uncompleted' : 'pending';

    // 📰 6) لو هي مهمة خبر → استخدم ID الأدمن المحدد
    if (picked == null && canShowNews) {
      final news = freshNews!;
      const newsTaskId =
          "bJjTCm7ZWlmzEk2QNPr"; // ← ID مهمة "قراءة خبر بيئي" من الأدمن

      await ref.set({
        'userId': _uid,
        'taskId': newsTaskId,
        'taskTitle': 'قراءة خبر بيئي',
        'taskDescription': 'اقرئي هذا الخبر البيئي ثم أجيبي على الاختبار.',
        'taskPoints': 10,
        'taskValidation': 'التحقق عبر اجراء اختبار قصير',
        'articleId': news['docId'],
        'selectedAt': Timestamp.fromDate(start),
        'windowStart': Timestamp.fromDate(start),
        'windowEnd': Timestamp.fromDate(end),
        'status': status,
        'completedAt': null,
      });
      return;
    }

    // 🟩 7) مهمة عادية
    final pickedData = picked.data();
    await ref.set({
      'userId': _uid,
      'taskId': picked.id,
      'selectedAt': Timestamp.fromDate(start),
      'status': status,
      'completedAt': null,
      'windowStart': Timestamp.fromDate(start),
      'windowEnd': Timestamp.fromDate(end),
      'taskTitle': pickedData['title'] ?? '(بدون عنوان)',
      'taskDescription': pickedData['description'] ?? '',
      'taskPoints': pickedData['points'] ?? 0,
      'taskValidation':
          pickedData['validationStrategy'] ??
          pickedData['validation'] ??
          pickedData['taskValidation'] ??
          'غير محددة',
    });
  }

  void _attachUserTaskStreamFor(DateTime day) {
    if (_uid == null) return;
    final key = '${_uid!}_${_yyyyMMdd(day)}';
    setState(() {
      _userTaskStream = FirebaseFirestore.instance
          .collection('userTasks')
          .doc(key)
          .snapshots();
    });
  }

  bool _isWithinDayWindow(DateTime day, DateTime now) {
    return now.isAfter(_dayStart(day).subtract(const Duration(seconds: 1))) &&
        now.isBefore(_dayEnd(day).add(const Duration(seconds: 1)));
  }

  @override
  Widget build(BuildContext context) {
    if (_isInitializing) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: AppColors.primary),
              const SizedBox(height: 20),
              Text(
                'جاري تحميل المهام...',
                style: GoogleFonts.ibmPlexSansArabic(
                  fontSize: 16,
                  color: AppColors.dark,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final isKeyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        extendBody: true,
        backgroundColor: Colors.transparent,
        extendBodyBehindAppBar: true,
        appBar: const NameerAppBar(showTitleInBar: false, showBack: false),
        body: AnimatedBackgroundContainer(
          child: Builder(
            builder: (context) {
              final statusBar = MediaQuery.of(context).padding.top;
              final topPadding = statusBar + 20 + 12;
              final viewInsets = MediaQuery.of(context).viewInsets.bottom;
              final bottomPad = viewInsets > 0
                  ? viewInsets + 16
                  : kBottomNavigationBarHeight + 24;

              return SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(16, topPadding, 16, bottomPad),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'مهامي',
                      style: GoogleFonts.ibmPlexSansArabic(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: AppColors.dark,
                      ),
                    ),
                    const SizedBox(height: 15),

                    _buildGrowthIndicator(
                      levelName: 'بذرة',
                      level: 1,
                      tasksPerDay: 1,
                      progressToNext: 0.45,
                    ),

                    const SizedBox(height: 15),
                    _buildCalendar(),
                    const SizedBox(height: 8),

                    (!_precheckDone)
                        ? const Center(
                            child: Padding(
                              padding: EdgeInsets.symmetric(vertical: 40),
                              child: CircularProgressIndicator(
                                color: AppColors.primary,
                              ),
                            ),
                          )
                        : (_precheckError != null)
                        ? _buildUnavailableCard(
                            title: 'تعذّر تحميل مهمة اليوم',
                            subtitle: (_precheckError == 'permission-denied')
                                ? 'صلاحيات غير كافية لقراءة مهامك. تأكدي أنك مسجّلة دخولًا وأن قواعد Firestore تسمح لصاحب الوثيقة بالقراءة.'
                                : (_precheckError!.contains('unavailable') ||
                                      _precheckError!.contains('network'))
                                ? 'مشكلة اتصال مؤقتة. تحقّقي من الإنترنت ثم جرّبي التحديث.'
                                : 'خطأ: $_precheckError',
                          )
                        : (_userTaskStream == null)
                        ? const Center(
                            child: Padding(
                              padding: EdgeInsets.symmetric(vertical: 40),
                              child: CircularProgressIndicator(
                                color: AppColors.primary,
                              ),
                            ),
                          )
                        : StreamBuilder<DocumentSnapshot>(
                            stream: _userTaskStream!,
                            builder: (context, snap) {
                              if (snap.connectionState ==
                                  ConnectionState.waiting) {
                                return const Center(
                                  child: Padding(
                                    padding: EdgeInsets.symmetric(vertical: 40),
                                    child: CircularProgressIndicator(
                                      color: AppColors.primary,
                                    ),
                                  ),
                                );
                              }

                              final sel = _dayStart(
                                _selectedDay ?? DateTime.now(),
                              );
                              final today = _dayStart(DateTime.now());
                              final nextMonthStart = DateTime(
                                today.year,
                                today.month + 1,
                                1,
                              );

                              if (_joinDate != null &&
                                  sel.isBefore(_joinDate!)) {
                                return _buildUnavailableCard(
                                  title: 'غير متاحة',
                                  subtitle: 'لم تكن ضمن نمير في هذا التاريخ.',
                                );
                              }

                              if (!snap.hasData || !snap.data!.exists) {
                                return _buildUnavailableCard(
                                  title: 'لا توجد مهام متاحة',
                                  subtitle: 'لا توجد مهمة لليوم المحدد.',
                                );
                              }

                              final ut =
                                  snap.data!.data() as Map<String, dynamic>;

                              final newStatus =
                                  (ut['status'] as String?) ?? 'pending';
                              _updateMonthStatusFor(sel, newStatus);

                              if (sel.isAfter(nextMonthStart)) {
                                return _buildUnavailableCard(
                                  title: 'غير متاحة',
                                  subtitle:
                                      'هذا الشهر لم يُفتح بعد. الرجاء العودة لاحقًا.',
                                );
                              }

                              // ✅ نمرّر taskId + id (نفس القيمة) + باقي الحقول
                              final data = <String, dynamic>{
                                'taskId': ut['taskId'] ?? '',
                                'title': ut['taskTitle'] ?? '(بدون عنوان)',
                                'description': ut['taskDescription'] ?? '',
                                'points': ut['taskPoints'] ?? 0,
                                'validationStrategy':
                                    ut['taskValidation'] ?? 'غير محددة',
                                'id': ut['taskId'] ?? '',
                                'status': ut['status'] ?? 'pending',

                                'taskType': ut['taskType'],
                                'articleContent': ut['articleContent'],
                              };

                              // ✅ السماح بالإكمال لليوم والماضي فقط
                              final canPerformDay = !sel.isAfter(today);

                              if ((ut['taskTitle'] == null ||
                                      ut['taskDescription'] == null) &&
                                  ut['taskId'] != null) {
                                return FutureBuilder<DocumentSnapshot>(
                                  future: FirebaseFirestore.instance
                                      .collection('tasks')
                                      .doc(ut['taskId'])
                                      .get(),
                                  builder: (context, tSnap) {
                                    if (tSnap.connectionState ==
                                        ConnectionState.waiting) {
                                      return const Center(
                                        child: Padding(
                                          padding: EdgeInsets.symmetric(
                                            vertical: 40,
                                          ),
                                          child: CircularProgressIndicator(
                                            color: AppColors.primary,
                                          ),
                                        ),
                                      );
                                    }
                                    if (!tSnap.hasData || !tSnap.data!.exists) {
                                      return _buildUnavailableCard(
                                        title: 'المهمة غير متاحة',
                                        subtitle: 'قد تكون حُذفت من النظام.',
                                      );
                                    }
                                    final td =
                                        tSnap.data!.data()
                                            as Map<String, dynamic>;
                                    final fData = {
                                      'taskId': ut['taskId'],
                                      'title': td['title'] ?? '(بدون عنوان)',
                                      'description': td['description'] ?? '',
                                      'points': td['points'] ?? 0,
                                      'validationStrategy':
                                          td['validationStrategy'] ??
                                          'غير محددة',
                                      'id': ut['taskId'],
                                      'status': ut['status'] ?? 'pending',

                                      'taskType': ut['taskType'],
                                      'articleContent': ut['articleContent'],
                                    };
                                    return _buildUserTaskCard(
                                      taskData: fData,
                                      canPerform: canPerformDay,
                                    );
                                  },
                                );
                              }

                              return _buildUserTaskCard(
                                taskData: data,
                                canPerform: canPerformDay,
                              );
                            },
                          ),
                  ],
                ),
              );
            },
          ),
        ),
        bottomNavigationBar: isKeyboardOpen
            ? null
            : BottomNavPage(currentIndex: _currentIndex, onTap: _onTap),
      ),
    );
  }

  // -------------------------------------------------------------
  // 🌱 Growth Progress Bar
  // -------------------------------------------------------------
  Widget _buildGrowthIndicator({
    required String levelName,
    required int level,
    required int tasksPerDay,
    required double progressToNext,
  }) {
    Color startColor = const Color(0xFFB6E9C1);
    Color endColor = const Color(0xFF4BAA98);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      color: Colors.transparent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.energy_savings_leaf_outlined,
                size: 18,
                color: Color(0xFF4BAA98),
              ),
              const SizedBox(width: 5),
              Text(
                '$levelName – المستوى $level',
                style: GoogleFonts.ibmPlexSansArabic(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.dark,
                ),
              ),
              const Spacer(),
              Text(
                '$tasksPerDay مهمة يوميًا',
                style: GoogleFonts.ibmPlexSansArabic(
                  fontSize: 12.5,
                  color: const Color(0xFF4BAA98),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Stack(
              children: [
                Container(
                  height: 4,
                  color: Colors.grey.shade200.withOpacity(0.5),
                ),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 900),
                  curve: Curves.easeOutCubic,
                  height: 4,
                  width:
                      MediaQuery.of(context).size.width *
                      progressToNext.clamp(0.0, 1.0),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [startColor, endColor],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 2),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              progressToNext >= 1
                  ? '🎉 جاهز للترقية!'
                  : '${(progressToNext * 100).toStringAsFixed(0)}٪ للمستوى التالي',
              style: GoogleFonts.ibmPlexSansArabic(
                fontSize: 11.2,
                color: Colors.grey.shade700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------
  // 🟩 Calendar & Card Builders
  // -------------------------------------------------------------
  Widget _buildCalendar() {
    return Stack(
      children: [
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.primary, width: 2),
            boxShadow: const [
              BoxShadow(
                color: Color(0x11000000),
                blurRadius: 8,
                offset: Offset(0, 3),
              ),
            ],
          ),
          child: TableCalendar(
            onPageChanged: (focused) {
              _focusedDay = focused;
              // ✅ تحميل الشهر المعروض فقط
              _loadMonth(focused);
            },
            focusedDay: _focusedDay,
            firstDay: DateTime.utc(2020),
            lastDay: DateTime.utc(2030),
            calendarFormat: CalendarFormat.month,
            headerStyle: HeaderStyle(
              formatButtonVisible: false,
              titleCentered: true,
              titleTextStyle: GoogleFonts.ibmPlexSansArabic(
                color: AppColors.dark,
                fontWeight: FontWeight.w800,
                fontSize: 18,
              ),
              leftChevronIcon: const Icon(
                Icons.chevron_left,
                color: AppColors.primary,
              ),
              rightChevronIcon: const Icon(
                Icons.chevron_right,
                color: AppColors.primary,
              ),
            ),
            selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
            onDaySelected: (selected, focused) async {
              setState(() {
                _selectedDay = selected;
                _focusedDay = focused;
              });
              await _ensureUserTaskForDate(_dayStart(selected));
              _precheckDone = false;
              _precheckError = null;
              setState(() {});
              await _precheckTodayDoc();
            },
            calendarStyle: CalendarStyle(
              todayDecoration: BoxDecoration(
                color: Colors.black.withOpacity(0.08),
                shape: BoxShape.circle,
              ),
              selectedDecoration: const BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
              ),
              selectedTextStyle: GoogleFonts.ibmPlexSansArabic(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
              todayTextStyle: GoogleFonts.ibmPlexSansArabic(
                color: AppColors.dark,
                fontWeight: FontWeight.w700,
              ),
            ),
            calendarBuilders: CalendarBuilders(
              defaultBuilder: (context, day, focusedDay) {
                final bool isSel = isSameDay(day, _selectedDay);
                final bool isToday = isSameDay(day, _dayStart(DateTime.now()));
                final bool showCompleted =
                    _isCompletedDay(day) && !isSel && !isToday;

                return SizedBox.expand(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (showCompleted)
                        Center(
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: const BoxDecoration(
                              color: AppColors.primary33,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      Center(
                        child: Text(
                          '${day.day}',
                          style: GoogleFonts.ibmPlexSansArabic(
                            color: AppColors.dark,
                            fontWeight: FontWeight.w600,
                            fontSize: 13.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),

        // مؤشر تحميل بسيط أعلى الكالندر عند تغيير الشهر
        if (_isMonthLoading)
          Positioned.fill(
            child: IgnorePointer(
              ignoring: true,
              child: Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildUnavailableCard({required String title, String? subtitle}) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 12,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.ibmPlexSansArabic(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppColors.dark,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: GoogleFonts.ibmPlexSansArabic(
                fontSize: 14,
                color: Colors.black87,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildUserTaskCard({
    required Map<String, dynamic> taskData,
    bool canPerform = false,
  }) {
    final title = taskData['title'] ?? 'مهمة غير محددة';
    final description = taskData['description'] ?? 'لا يوجد وصف متاح.';
    final points = taskData['points'] ?? 0;
    final validation = taskData['validationStrategy'] ?? 'غير محددة';
    final status = taskData['status'] ?? 'pending';
    final taskType = (taskData['taskType'] ?? '').toString();
    final articleContent = (taskData['articleContent'] ?? '').toString().trim();

    // 🔴 لو هي مهمة "خبر" لكن المقال فاضي → لا تعرض مهمة، اعرض كرت "لا توجد مهمة"
    if (taskType == 'news' && articleContent.isEmpty) {
      return _buildUnavailableCard(
        title: 'لا توجد مهمة لهذا اليوم',
        subtitle: 'خبر هذا اليوم لم يعد متوفرًا، وسيتم استبداله لاحقًا.',
      );
    }
    final sel = _dayStart(_selectedDay ?? DateTime.now());
    final uid = _uid ?? '';
    final userTaskDocId = uid.isEmpty ? '' : '${uid}_${_yyyyMMdd(sel)}';

    final isSubmitted = (status == 'submitted');
    final isCompleted = (status == 'completed');

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 12,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 🔁 زر تحديث صغير أعلى يسار الكرت
          if (canPerform && !isCompleted && !isSubmitted) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                icon: const Icon(
                  Icons.refresh,
                  color: AppColors.primary,
                  size: 18,
                ),
                label: Text(
                  'تغيير المهمة',
                  style: GoogleFonts.ibmPlexSansArabic(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    color: AppColors.primary,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.primary, width: 1.5),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  minimumSize: Size.zero,
                ),
                onPressed: () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('تأكيد التحديث'),
                      content: const Text(
                        'هل أنت متأكد من رغبتك في تغيير هذه المهمة؟',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('إلغاء'),
                        ),
                        ElevatedButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('تأكيد'),
                        ),
                      ],
                    ),
                  );
                  if (confirm == true) {
                    await _refreshUserTask(taskData);
                    _attachUserTaskStreamFor(sel);
                  }
                },
              ),
            ),
            const SizedBox(height: 8),
          ],

          Text(
            'مهمة اليوم',
            style: GoogleFonts.ibmPlexSansArabic(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppColors.dark,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            title,
            style: GoogleFonts.ibmPlexSansArabic(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            description,
            style: GoogleFonts.ibmPlexSansArabic(
              fontSize: 14,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.star_border, color: AppColors.primary, size: 20),
              const SizedBox(width: 6),
              Text(
                '$points نقطة',
                style: GoogleFonts.ibmPlexSansArabic(
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                  fontSize: 14,
                ),
              ),
              const Spacer(),
              Text(
                validation,
                style: GoogleFonts.ibmPlexSansArabic(
                  fontSize: 13,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // زر الإكمال — مفعّل لليوم والماضي فقط
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: (isCompleted || isSubmitted || !canPerform)
                  ? null
                  : () async {
                      if (validation == "التحقق عبر اجراء اختبار قصير") {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ArticlePage(
                              userTaskDocId: userTaskDocId,
                              taskId: taskData['id'],
                            ),
                          ),
                        );
                      } else {
                        final result = await showCompleteTaskSheet(
                          context,
                          taskData,
                          selectedDay: sel,
                          userTaskDocId: userTaskDocId,
                        );
                        if (result == true && mounted) {
                          _attachUserTaskStreamFor(sel);
                          setState(() {});
                        }
                      }
                    },
              style: ButtonStyle(
                elevation: MaterialStateProperty.all(0),
                shadowColor: MaterialStateProperty.all(Colors.transparent),
                backgroundColor: MaterialStateProperty.all(Colors.transparent),
                overlayColor: MaterialStateProperty.all(Colors.transparent),
                shape: MaterialStateProperty.all(
                  RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                padding: MaterialStateProperty.all(
                  const EdgeInsets.symmetric(vertical: 14),
                ),
                splashFactory: NoSplash.splashFactory,
              ),
              child: Ink(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  color: (isSubmitted || !canPerform)
                      ? Colors.grey.shade300
                      : (isCompleted ? AppColors.primary33 : null),
                  gradient: (!isCompleted && !isSubmitted && canPerform)
                      ? const LinearGradient(
                          colors: [AppColors.primary, AppColors.mint],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        )
                      : null,
                ),
                child: Container(
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Text(
                    isCompleted
                        ? 'تم الإنجاز ✅'
                        : (isSubmitted
                              ? 'بانتظار المراجعة ⏳'
                              : (canPerform
                                    ? 'بدء المهمة'
                                    : 'يومها لم يحن بعد ')),
                    style: GoogleFonts.ibmPlexSansArabic(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      color: (isCompleted || isSubmitted || !canPerform)
                          ? AppColors.dark
                          : Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// -------------------------------------------------------------
// ✅ دالة الفتح (تمرير selectedDay / userTaskDocId) + دمج بيانات tasks
// -------------------------------------------------------------
Future<bool?> showCompleteTaskSheet(
  BuildContext context,
  Map<String, dynamic> userTaskData, {
  required DateTime selectedDay,
  required String userTaskDocId,
}) async {
  // 1) taskId من userTasks أو من id
  final taskId = (userTaskData['taskId'] ?? userTaskData['id'])?.toString();

  Map<String, dynamic> mergedTask = {...userTaskData};

  if (taskId != null && taskId.isNotEmpty) {
    final tSnap = await FirebaseFirestore.instance
        .collection('tasks')
        .doc(taskId)
        .get();

    if (tSnap.exists && tSnap.data() != null) {
      final base = tSnap.data()!;
      mergedTask.addAll(
        base,
      ); // ← يضيف: emissionFactorRef, baselineFactorRef, calcMode, calc_requires, direction...
      mergedTask['id'] ??= tSnap.id;
      mergedTask['taskId'] ??= tSnap.id;
    }
  }

  return showModalBottomSheet<bool?>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => CompleteTaskSheet(
      taskData: mergedTask, // ← نرسل الميرج، مو userTaskData الخام
      selectedDay: selectedDay,
      userTaskDocId: userTaskDocId,
    ),
  );
}
