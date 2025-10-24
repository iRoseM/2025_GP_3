import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:math';

import 'home.dart';
import 'map.dart';
import 'levels.dart';
import 'community.dart';
import 'services/bottom_nav.dart';
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

class taskPage extends StatefulWidget {
  const taskPage({super.key});

  @override
  State<taskPage> createState() => _taskPageState();
}

class _taskPageState extends State<taskPage> {
  final int _currentIndex = 1;

  void _onTap(int i) {
    if (i == _currentIndex) return;
    switch (i) {
      case 0:
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const homePage()));
        break;
      case 1:
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const taskPage()));
        break;
      case 2:
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const levelsPage()));
        break;
      case 3:
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const mapPage()));
        break;
      case 4:
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const communityPage()));
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

  DateTime _dayStart(DateTime d) => DateTime(d.year, d.month, d.day); // delete 
  DateTime _dayEnd(DateTime d) => _dayStart(d).add(const Duration(days: 1)).subtract(const Duration(seconds: 1)); //delete 
  String _yyyyMMdd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}'; // delete
   // 🟢 Temporary pool of remaining task IDs for refresh rotation
  List<String> _remainingTaskIds = [];


  // ============================================================
  // 🟢 Helper methods for monthly handling
  // ============================================================
  DateTime _monthStart(DateTime d) => DateTime(d.year, d.month, 1);
  DateTime _monthEnd(DateTime d)   => DateTime(d.year, d.month + 1, 0);

@override
void initState() {
  super.initState();
  Future.microtask(() async {
    if (!await hasInternetConnection()) {
      if (mounted) showNoInternetDialog(context);
      return;
    }
  });
  final user = _auth.currentUser;
  _uid = user?.uid;
  _selectedDay = _dayStart(DateTime.now());
  _focusedDay  = _selectedDay!;
  _bootstrapMonth(); // 👈 بدل الدالة القديمة
}

Future<void> _bootstrapMonth() async {
  final user = _auth.currentUser;
  if (user == null) return;

  DateTime fallback = user.metadata.creationTime?.toLocal() ?? DateTime.now();
  _joinDate = _dayStart(fallback);

  final udoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
  if (udoc.exists && (udoc.data()?['joinDate'] != null)) {
    _joinDate = _dayStart((udoc.data()!['joinDate'] as Timestamp).toDate());
  }

  // ✅ ولّدي مهام الشهر الحالي كاملة (حتى اليوم) + باكر
  await _ensureMonthBackfill(DateTime.now());

  _attachUserTaskStreamFor(_selectedDay!);
  if (mounted) setState(() {});
  }

//   // ✅ توليد/استرجاع مهام كل أيام الشهر (حتى اليوم) + الغد لو الشهر الحالي
// Future<void> _ensureMonthBackfill(DateTime anyDayInMonth) async {
//   if (_uid == null) return;

//   final ms = _monthStart(anyDayInMonth);
//   final me = _monthEnd(anyDayInMonth);
//   final today = _dayStart(DateTime.now());

//   // ✅ نولّد مهام الشهر كامل (حتى الأيام بعد اليوم)
//   for (DateTime d = ms; !d.isAfter(me); d = d.add(const Duration(days: 1))) {
//     // لا تنشئ مهمة قبل تاريخ انضمام المستخدم
//     if (_joinDate != null && d.isBefore(_joinDate!)) continue;
//     await _ensureUserTaskForDate(d);
//   }

//   // ✅ لو الشهر السابق ما تولّد بعد، ولّده برضو
//   final prevMonthStart = DateTime(ms.year, ms.month - 1, 1);
//   final prevMonthEnd = DateTime(ms.year, ms.month, 0);
//   for (DateTime d = prevMonthStart; !d.isAfter(prevMonthEnd); d = d.add(const Duration(days: 1))) {
//     if (_joinDate != null && d.isBefore(_joinDate!)) continue;
//     await _ensureUserTaskForDate(d);
//   }
// }

  // ✅ توليد/استرجاع مهام كل أيام الشهر (مع منع التكرار المتتالي)
  Future<void> _ensureMonthBackfill(DateTime anyDayInMonth) async {
    if (_uid == null) return;

    final ms = _monthStart(anyDayInMonth);
    final me = _monthEnd(anyDayInMonth);

    // نحدد الشهر السابق (حتى نضمن تسلسل صحيح)
    final prevMonthStart = DateTime(ms.year, ms.month - 1, 1);
    final prevMonthEnd = DateTime(ms.year, ms.month, 0);

    // ✅ 1. ولّدي الشهر السابق أولاً
    for (DateTime d = prevMonthStart;
        !d.isAfter(prevMonthEnd);
        d = d.add(const Duration(days: 1))) {
      if (_joinDate != null && d.isBefore(_joinDate!)) continue; // قبل الانضمام
      await _ensureUserTaskForDate(d);
      await Future.delayed(const Duration(milliseconds: 100)); // ⏳ تأخير بسيط لضمان الكتابة في فايربيز
    }

    // ✅ 2. ثم الشهر الحالي (من بدايته إلى نهايته)
    final today = _dayStart(DateTime.now());
    for (DateTime d = ms; !d.isAfter(me); d = d.add(const Duration(days: 1))) {
      if (_joinDate != null && d.isBefore(_joinDate!)) continue; // قبل الانضمام
      await _ensureUserTaskForDate(d);
      await Future.delayed(const Duration(milliseconds: 100)); // ⏳ نفس التأخير
    }

    // ✅ بعد ما نخلص، نحدث المهام لليوم الحالي في الواجهة
    _attachUserTaskStreamFor(_selectedDay ?? today);
    if (mounted) setState(() {});
  }



  // ============================================================
  // 🟢 Get daily markers (completed / uncompleted / pending)
  // ============================================================
  Future<Map<DateTime, String>> _getTaskStatusesForMonth(DateTime month) async {
    if (_uid == null) return {};
    final ms = _monthStart(month);
    final me = _monthEnd(month);

    final qs = await FirebaseFirestore.instance
        .collection('userTasks')
        .where('userId', isEqualTo: _uid)
        .where('selectedAt', isGreaterThanOrEqualTo: Timestamp.fromDate(ms))
        .where('selectedAt', isLessThanOrEqualTo: Timestamp.fromDate(me))
        .get();

    Map<DateTime, String> map = {};
    for (var doc in qs.docs) {
      final data = doc.data();
      final status = data['status'] as String? ?? 'pending';
      final day = (data['selectedAt'] as Timestamp).toDate();
      map[DateTime(day.year, day.month, day.day)] = status;
    }
    return map;
  }

  // ============================================================
  // 🔄 Refresh current task (change user's daily task manually)
  // ============================================================
  Future<void> _refreshUserTask(Map<String, dynamic> currentTask) async {
    if (_uid == null || _selectedDay == null) return;

    final key = '${_uid!}_${_yyyyMMdd(_selectedDay!)}';
    final ref = FirebaseFirestore.instance.collection('userTasks').doc(key);
    final now = DateTime.now();

    // جلب المهام النشطة + مهام الشهر القادم
    final tasksSnap = await FirebaseFirestore.instance
        .collection('tasks')
        .where('status', isEqualTo: 'active')
        .get();

    final currentMonthKey = "${now.year}-${now.month.toString().padLeft(2, '0')}";

    // تصفية المهام
    final validTasks = tasksSnap.docs.where((doc) {
      final data = doc.data();
      dynamic vf = data['visible_from'];
      dynamic em = data['expiry_month'];

      String? visibleFrom;
      String? expiryMonth;

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

      final isVisible = visibleFrom == null || visibleFrom.compareTo(currentMonthKey) <= 1;
      final notExpired = expiryMonth == null || expiryMonth.compareTo(currentMonthKey) >= 0;
      return isVisible && notExpired;
    }).toList();

    if (validTasks.isEmpty) return;

    // إذا كانت القائمة المؤقتة فارغة، املأها بجميع المهام المتاحة
    if (_remainingTaskIds.isEmpty) {
      _remainingTaskIds = validTasks.map((doc) => doc.id).toList();
      print("🔁 Refilled remaining task pool with ${_remainingTaskIds.length} tasks");
    }

    // حذف المهمة الحالية من القائمة
    _remainingTaskIds.remove(currentTask['id']);

    // إزالة مهمة الأمس والغد من القائمة (منع التكرار)
    String? yTaskId, tTaskId;
    final yesterday = _dayStart(_selectedDay!.subtract(const Duration(days: 1)));
    final tomorrow = _dayStart(_selectedDay!.add(const Duration(days: 1)));

    final yKey = '${_uid!}_${_yyyyMMdd(yesterday)}';
    final tKey = '${_uid!}_${_yyyyMMdd(tomorrow)}';
    final ySnap = await FirebaseFirestore.instance.collection('userTasks').doc(yKey).get();
    final tSnap = await FirebaseFirestore.instance.collection('userTasks').doc(tKey).get();

    if (ySnap.exists) yTaskId = ySnap.data()?['taskId'] as String?;
    if (tSnap.exists) tTaskId = tSnap.data()?['taskId'] as String?;
    _remainingTaskIds.remove(yTaskId);
    _remainingTaskIds.remove(tTaskId);

    // 🔍 إذا انتهت كل المهام
    if (_remainingTaskIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'لقد عرضنا لك جميع المهام! سيتم إعادة التدوير من البداية.',
            style: GoogleFonts.ibmPlexSansArabic(color: Colors.white),
          ),
          backgroundColor: AppColors.primary,
        ),
      );

      // إعادة تعبئة القائمة بالمهام الأصلية
      _remainingTaskIds = validTasks.map((doc) => doc.id).toList();
      print("🔄 Task pool refilled for looping again");
    }

    // اختيار مهمة جديدة عشوائية من القائمة
    final rnd = Random(DateTime.now().millisecondsSinceEpoch);
    final newTaskId = _remainingTaskIds[rnd.nextInt(_remainingTaskIds.length)];
    _remainingTaskIds.remove(newTaskId); // حذفها من القائمة حتى لا تتكرر فورًا

    await ref.update({'taskId': newTaskId});

    // 🧾 طباعة ومؤشر نجاح
    print('✅ New task assigned: $newTaskId (Remaining: ${_remainingTaskIds.length})');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'تم تحديث المهمة بنجاح 🎯',
          style: GoogleFonts.ibmPlexSansArabic(color: Colors.white),
        ),
        backgroundColor: AppColors.primary,
      ),
    );
  }

  // ============================================================
  // Ensure userTask exists with ACTIVE tasks (monthly visibility)
  // ============================================================
  Future<void> _ensureUserTaskForDate(DateTime day) async {
  if (_uid == null) return;

  final today = _dayStart(DateTime.now());
  if (_joinDate != null && day.isBefore(_joinDate!)) return;

  // ❌ لا نمنع الأيام المستقبلية داخل نفس الشهر
  final now = DateTime.now();
  if (day.year > now.year ||
      (day.year == now.year && day.month > now.month + 1)) {
    return; // بس نمنع الأشهر الجاية أو السنوات الجاية
  }

  final key = '${_uid!}_${_yyyyMMdd(day)}';
  final ref = FirebaseFirestore.instance.collection('userTasks').doc(key);
  final snap = await ref.get();
  if (snap.exists) return;

  final currentMonthKey = "${now.year}-${now.month.toString().padLeft(2, '0')}";

  // 🟢 جلب المهام النشطة فقط
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
        visibleFrom == null || visibleFrom.compareTo(currentMonthKey) <= 0;
    final notExpired =
        expiryMonth == null || expiryMonth.compareTo(currentMonthKey) >= 0;
    return isVisible && notExpired;
  }).toList();

  if (validTasks.isEmpty) return;

  // ============================================================
  // 🟢 منع تكرار المهمة مع اليوم السابق فقط
  // ============================================================
  String? yTaskId;
  final yesterday = _dayStart(day.subtract(const Duration(days: 1)));
  final yKey = '${_uid!}_${_yyyyMMdd(yesterday)}';
  final ySnap = await FirebaseFirestore.instance
      .collection('userTasks')
      .doc(yKey)
      .get();
  if (ySnap.exists) yTaskId = ySnap.data()?['taskId'] as String?;

  final excludedIds = {yTaskId}..removeWhere((id) => id == null);
  final candidates =
      validTasks.where((doc) => !excludedIds.contains(doc.id)).toList();
  final pool = candidates.isEmpty ? validTasks : candidates;

  // 🧩 Debug prints (للتجربة)
  print('📅 [${_yyyyMMdd(day)}]');
  print(' ├─ مهمة الأمس: ${yTaskId ?? "لا يوجد"}');
  print(' ├─ عدد المهام الأصلية: ${validTasks.length}');
  print(' ├─ عدد المهام بعد الاستبعاد: ${candidates.length}');
  if (candidates.isEmpty) {
    print(' ⚠️ لا توجد مهام بديلة كافية، تم استخدام القائمة الأصلية.');
  }

  // 🔹 اختيار عشوائي من المتبقي
  final rnd = Random(DateTime.now().millisecondsSinceEpoch ^ day.millisecondsSinceEpoch);
  final picked = pool[rnd.nextInt(pool.length)];

  // 🟢 اطبع عنوان المهمة المختارة
  final pickedTitle = picked.data()['title'] ?? '(بدون عنوان)';
  print(' ✅ المهمة المختارة لليوم: $pickedTitle (${picked.id})');

  // ============================================================
  // 🟢 إنشاء وثيقة userTask
  // ============================================================
  final String status = day.isBefore(today) ? 'uncompleted' : 'pending';
  final start = _dayStart(day);
  final end = _dayEnd(day);
  final double carbon = (rnd.nextDouble() * 0.42 + 0.08);

  await ref.set({
    'userId': _uid,
    'taskId': picked.id,
    'selectedAt': Timestamp.fromDate(start),
    'status': status,
    'completedAt': null,
    'carbonFootPrint': carbon,
    'windowStart': Timestamp.fromDate(start),
    'windowEnd': Timestamp.fromDate(end),
  });
}

  void _attachUserTaskStreamFor(DateTime day) {
    if (_uid == null) return;
    final key = '${_uid!}_${_yyyyMMdd(day)}';
    setState(() {
      _userTaskStream = FirebaseFirestore.instance.collection('userTasks').doc(key).snapshots();
    });
  }

  bool _isWithinDayWindow(DateTime day, DateTime now) {
    return now.isAfter(_dayStart(day).subtract(const Duration(seconds: 1))) &&
        now.isBefore(_dayEnd(day).add(const Duration(seconds: 1)));
  }


  // ============================================================
  // 🟢 توليد مهام الشهر الحالي واللي قبله كاملة
  // ============================================================
  Future<void> _bootstrapFullMonth() async {
    final user = _auth.currentUser;
    if (user == null) return;

    // نحدد تاريخ انضمام المستخدم
    DateTime fallback = user.metadata.creationTime?.toLocal() ?? DateTime.now();
    _joinDate = _dayStart(fallback);

    final udoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    if (udoc.exists && (udoc.data()?['joinDate'] != null)) {
      _joinDate = _dayStart((udoc.data()!['joinDate'] as Timestamp).toDate());
    }

    // نحدد الشهر الحالي واللي قبله
    final now = DateTime.now();
    // final currentMonthStart = DateTime(now.year, now.month, 1);
    final prevMonthStart = DateTime(now.year, now.month - 1, 1);

    // ✅ نولّد مهام من أول يوم بالشهر السابق حتى اليوم الحالي
    for (DateTime d = prevMonthStart;
        !d.isAfter(now);
        d = d.add(const Duration(days: 1))) {
      if (_joinDate != null && d.isBefore(_joinDate!)) continue; // ما كان جزء من نمير بعد
      await _ensureUserTaskForDate(d);
    }

    // تحديث الواجهة
    _attachUserTaskStreamFor(_selectedDay!);
    if (mounted) setState(() {});
  }

@override
Widget build(BuildContext context) {
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
            final bottomPad =
                viewInsets > 0 ? viewInsets + 16 : kBottomNavigationBarHeight + 24;

            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(16, topPadding, 16, bottomPad),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('مهامي',
                      style: GoogleFonts.ibmPlexSansArabic(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: AppColors.dark)),
                  const SizedBox(height: 15),
                  _buildCalendar(),
                  const SizedBox(height: 8),
                  _userTaskStream == null
                      ? const Center(
                          child: Padding(
                              padding: EdgeInsets.symmetric(vertical: 40),
                              child: CircularProgressIndicator(
                                  color: AppColors.primary)))
                      : StreamBuilder<DocumentSnapshot>(
                          stream: _userTaskStream!,
                          builder: (context, snap) {
                            if (snap.connectionState ==
                                ConnectionState.waiting) {
                              return const Center(
                                  child: Padding(
                                      padding:
                                          EdgeInsets.symmetric(vertical: 40),
                                      child: CircularProgressIndicator(
                                          color: AppColors.primary)));
                            }
                            // ✅ نتحقق أولاً من اليوم المختار
                            final sel = _selectedDay ?? _dayStart(DateTime.now());
                            final today = _dayStart(DateTime.now());

                            // ✅ الشهر القادم فقط نعتبره "لم يُفتح بعد"
                            final nextMonthStart = DateTime(today.year, today.month + 1, 1);

                            // 🔴 أولاً: قبل الانضمام
                            if (_joinDate != null && sel.isBefore(_joinDate!)) {
                              return _buildUnavailableCard(
                                title: 'غير متاحة',
                                subtitle: 'لم تكن ضمن نمير في هذا التاريخ.',
                              );
                            }

                            // 🟡 بعد التحقق من الانضمام، نتحقق من وجود المهمة
                            if (!snap.hasData || !snap.data!.exists) {
                              return _buildUnavailableCard(
                                title: 'لا توجد مهام متاحة لهذا الشهر',
                                subtitle: 'يبدو أنه لم تُحدّد مهام بعد، تفقّد لاحقًا.',
                              );
                            }

                            final ut = snap.data!.data() as Map<String, dynamic>;
                            final taskId = ut['taskId'] as String?;

                            // 🔴 بعد نهاية الشهر الحالي (الشهر القادم)
                            if (sel.isAfter(nextMonthStart)) {
                              return _buildUnavailableCard(
                                title: 'غير متاحة',
                                subtitle: 'هذا الشهر لم يُفتح بعد. الرجاء العودة لاحقًا.',
                              );
                            }
                            // ✅ المهمة اليومية
                            return FutureBuilder<DocumentSnapshot>(
                              future: FirebaseFirestore.instance
                                  .collection('tasks')
                                  .doc(taskId)
                                  .get(),
                              builder: (context, taskSnap) {
                                if (taskSnap.connectionState ==
                                    ConnectionState.waiting) {
                                  return const Center(
                                    child: Padding(
                                      padding:
                                          EdgeInsets.symmetric(vertical: 40),
                                      child: CircularProgressIndicator(
                                          color: AppColors.primary),
                                    ),
                                  );
                                }

                                if (!taskSnap.hasData ||
                                    !taskSnap.data!.exists) {
                                  return _buildUnavailableCard(
                                    title: 'المهمة غير متاحة',
                                    subtitle: 'قد تكون حُذفت من النظام.',
                                  );
                                }

                                final data = taskSnap.data!.data()
                                    as Map<String, dynamic>;

                                // 🟢 اليوم الحالي
                                if (isSameDay(sel, today)) {
                                  return _buildUserTaskCard(
                                      taskData: data, canPerform: true);
                                }

                                // 🟡 أي يوم سابق من نفس الشهر أو الشهر الماضي
                                return _buildUserTaskCard(
                                    taskData: data, canPerform: false);
                              },
                            );
                          }),
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
  // 🟩 Calendar & Card Builders
  // -------------------------------------------------------------
  Widget _buildCalendar() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.primary, width: 2),
        boxShadow: const [
          BoxShadow(color: Color(0x11000000), blurRadius: 8, offset: Offset(0, 3))
        ],
      ),
      child: TableCalendar(
        onPageChanged: (focused) async {
          _focusedDay = focused;
          await _ensureMonthBackfill(focused);
          _monthStatuses = await _getTaskStatusesForMonth(focused);
          if (mounted) setState(() {});
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
          leftChevronIcon: const Icon(Icons.chevron_left, color: AppColors.primary),
          rightChevronIcon: const Icon(Icons.chevron_right, color: AppColors.primary),
        ),
        selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
        onDaySelected: (selected, focused) {
          setState(() {
            _selectedDay = selected;
            _focusedDay = focused;
          });
          _attachUserTaskStreamFor(selected);
        },

        // 🎨 هنا نتحكم بألوان الأيام والدائرة المحددة
        calendarStyle: CalendarStyle(
          todayDecoration: BoxDecoration(
            color: AppColors.primary33, // لون اليوم الحقيقي (مثلاً لون باهت)
            shape: BoxShape.circle,
          ),
          selectedDecoration: BoxDecoration(
            color: AppColors.primary, // 🎨 هذا لون الدائرة لليوم المحدد
            shape: BoxShape.circle,
          ),
          selectedTextStyle: GoogleFonts.ibmPlexSansArabic(
            color: Colors.white, // لون رقم اليوم داخل الدائرة
            fontWeight: FontWeight.w700,
          ),
          todayTextStyle: GoogleFonts.ibmPlexSansArabic(
            color: AppColors.dark, // لون رقم اليوم الحالي
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
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
        boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 12, offset: Offset(0, 6))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title,
            style: GoogleFonts.ibmPlexSansArabic(
                fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.dark)),
        if (subtitle != null) ...[
          const SizedBox(height: 8),
          Text(subtitle,
              style: GoogleFonts.ibmPlexSansArabic(fontSize: 14, color: Colors.black87)),
        ],
      ]),
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

          // 🟢 زر تنفيذ المهمة (ظاهر دائماً)
// 🟢 زر تنفيذ المهمة (ظاهر دائماً)
SizedBox(
  width: double.infinity,
  child: ElevatedButton(
    onPressed: canPerform
        ? () {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'تم إكمال المهمة 🎉 (واجهة فقط)',
                  style: GoogleFonts.ibmPlexSansArabic(
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            );
          }
        : null, // مقفول إن ما كانت لليوم الحالي
    style: ElevatedButton.styleFrom(
      elevation: 0,
      padding: const EdgeInsets.symmetric(vertical: 14),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
      backgroundColor:
          canPerform ? AppColors.primary : Colors.grey.shade400,
    ),
    child: Text(
      'تمم المهمة',
      style: GoogleFonts.ibmPlexSansArabic(
        fontWeight: FontWeight.w700,
        fontSize: 16,
        color: Colors.white,
      ),
    ),
  ),
),

// 🔄 زر تحديث المهمة — يظهر فقط في حال canPerform == true
if (canPerform) ...[
  const SizedBox(height: 10),
  SizedBox(
    width: double.infinity,
    child: OutlinedButton.icon(
      icon: const Icon(Icons.refresh, color: AppColors.primary),
      label: Text(
        'تحديث المهمة',
        style: GoogleFonts.ibmPlexSansArabic(
          fontWeight: FontWeight.w700,
          fontSize: 15,
          color: AppColors.primary,
        ),
      ),
      style: OutlinedButton.styleFrom(
        side: const BorderSide(color: AppColors.primary, width: 2),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        padding: const EdgeInsets.symmetric(vertical: 12),
      ),
      onPressed: () async {
        final confirm = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('تأكيد التحديث'),
            content: const Text('هل أنت متأكد من رغبتك في تغيير هذه المهمة؟'),
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
        }
      },
    ),
  ),
],

        ],
      ),
    );
  }

}
