import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:math';
import 'package:camera/camera.dart';

import 'home.dart';
import 'map.dart';
import 'levels.dart';
import 'community.dart';
import 'services/bottom_nav.dart';
import 'services/background_container.dart';
import 'services/connection.dart';
import 'services/title_header.dart';
import 'complete_task.dart';

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

  // ✅ قفل تفاؤلي بعد الإكمال مباشرةً
  bool _localJustCompleted = false;

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
  List<String> _remainingTaskIds = [];

  DateTime _monthStart(DateTime d) => DateTime(d.year, d.month, 1);
  DateTime _monthEnd(DateTime d) => DateTime(d.year, d.month + 1, 0);

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
    _focusedDay = _selectedDay!;
    _bootstrapTodayOnly(); // سريع
  }

  Future<void> _bootstrapTodayOnly() async {
    final user = _auth.currentUser;
    if (user == null) return;

    final today = _dayStart(DateTime.now());

    DateTime authCreated = user.metadata.creationTime?.toLocal() ?? today;
    DateTime? usersJoin;
    final udoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
    if (udoc.exists && (udoc.data()?['joinDate'] != null)) {
      final v = udoc.data()!['joinDate'];
      if (v is Timestamp)
        usersJoin = v.toDate();
      else if (v is DateTime)
        usersJoin = v;
    }
    DateTime resolvedJoin = usersJoin == null
        ? authCreated
        : (authCreated.isBefore(usersJoin!) ? authCreated : usersJoin!);
    if (_dayStart(resolvedJoin).isAfter(today)) resolvedJoin = today; // clamp
    _joinDate = _dayStart(resolvedJoin);

    await _ensureUserTaskForDate(today);
    await _ensureUserTaskForDate(today.add(const Duration(days: 1)));

    _monthStatuses = await _getTaskStatusesForMonth(today);

    _attachUserTaskStreamFor(_selectedDay!);
    if (mounted) setState(() {});
  }

  Future<void> _ensureMonthBackfill(DateTime anyDayInMonth) async {
    if (_uid == null) return;
    final ms = _monthStart(anyDayInMonth);
    final me = _monthEnd(anyDayInMonth);

    final prevMonthStart = DateTime(ms.year, ms.month - 1, 1);
    final prevMonthEnd = DateTime(ms.year, ms.month, 0);

    for (
      DateTime d = prevMonthStart;
      !d.isAfter(prevMonthEnd);
      d = d.add(const Duration(days: 1))
    ) {
      if (_joinDate != null && d.isBefore(_joinDate!)) continue;
      await _ensureUserTaskForDate(d);
    }
    final today = _dayStart(DateTime.now());
    for (DateTime d = ms; !d.isAfter(me); d = d.add(const Duration(days: 1))) {
      if (_joinDate != null && d.isBefore(_joinDate!)) continue;
      await _ensureUserTaskForDate(d);
    }

    _attachUserTaskStreamFor(_selectedDay ?? today);
    if (mounted) setState(() {});
  }

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

  Future<void> _refreshUserTask(Map<String, dynamic> currentTask) async {
    if (_uid == null || _selectedDay == null) return;

    final key = '${_uid!}_${_yyyyMMdd(_selectedDay!)}';
    final ref = FirebaseFirestore.instance.collection('userTasks').doc(key);
    final now = DateTime.now();

    final tasksSnap = await FirebaseFirestore.instance
        .collection('tasks')
        .where('status', isEqualTo: 'active')
        .get();

    final currentMonthKey =
        "${now.year}-${now.month.toString().padLeft(2, '0')}";

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
          (visibleFrom == null) ||
          (visibleFrom.compareTo(currentMonthKey) <= 0);
      final notExpired =
          (expiryMonth == null) ||
          (expiryMonth.compareTo(currentMonthKey) >= 0);
      return isVisible && notExpired;
    }).toList();

    if (validTasks.isEmpty) return;

    if (_remainingTaskIds.isEmpty) {
      _remainingTaskIds = validTasks.map((doc) => doc.id).toList();
      print(
        "🔁 Refilled remaining task pool with ${_remainingTaskIds.length} tasks",
      );
    }

    _remainingTaskIds.remove(currentTask['id']);

    String? yTaskId, tTaskId;
    final yesterday = _dayStart(
      _selectedDay!.subtract(const Duration(days: 1)),
    );
    final tomorrow = _dayStart(_selectedDay!.add(const Duration(days: 1)));

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

    if (ySnap.exists) yTaskId = ySnap.data()?['taskId'] as String?;
    if (tSnap.exists) tTaskId = tSnap.data()?['taskId'] as String?;
    _remainingTaskIds.remove(yTaskId);
    _remainingTaskIds.remove(tTaskId);

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
      _remainingTaskIds = validTasks.map((doc) => doc.id).toList();
      print("🔄 Task pool refilled for looping again");
    }

    final rnd = Random(DateTime.now().millisecondsSinceEpoch);
    final newTaskId = _remainingTaskIds[rnd.nextInt(_remainingTaskIds.length)];
    _remainingTaskIds.remove(newTaskId);

    await ref.update({'taskId': newTaskId});

    print(
      '✅ New task assigned: $newTaskId (Remaining: ${_remainingTaskIds.length})',
    );
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

  Future<void> _ensureUserTaskForDate(DateTime day) async {
    if (_uid == null) return;

    final today = _dayStart(DateTime.now());
    if (_joinDate != null && day.isBefore(_joinDate!)) return;

    final now = DateTime.now();
    if (day.year > now.year ||
        (day.year == now.year && day.month > now.month + 1))
      return;

    final key = '${_uid!}_${_yyyyMMdd(day)}';
    final ref = FirebaseFirestore.instance.collection('userTasks').doc(key);
    final snap = await ref.get();
    if (snap.exists) return;

    final monthKey = "${day.year}-${day.month.toString().padLeft(2, '0')}";

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
          (visibleFrom == null) || (visibleFrom.compareTo(monthKey) <= 0);
      final notExpired =
          (expiryMonth == null) || (expiryMonth.compareTo(monthKey) >= 0);
      return isVisible && notExpired;
    }).toList();

    if (validTasks.isEmpty) return;

    String? yTaskId;
    final yesterday = _dayStart(day.subtract(const Duration(days: 1)));
    final yKey = '${_uid!}_${_yyyyMMdd(yesterday)}';
    final ySnap = await FirebaseFirestore.instance
        .collection('userTasks')
        .doc(yKey)
        .get();
    if (ySnap.exists) yTaskId = ySnap.data()?['taskId'] as String?;

    final excludedIds = {yTaskId}..removeWhere((id) => id == null);
    final candidates = validTasks
        .where((doc) => !excludedIds.contains(doc.id))
        .toList();
    final pool = candidates.isEmpty ? validTasks : candidates;

    final rnd = Random(
      DateTime.now().millisecondsSinceEpoch ^ day.millisecondsSinceEpoch,
    );
    final picked = pool[rnd.nextInt(pool.length)];
    final pickedData = picked.data();
    final pickedTitle = pickedData['title'] ?? '(بدون عنوان)';
    final pickedDesc = pickedData['description'] ?? '';
    final pickedPoints = pickedData['points'] ?? 0;
    final pickedValidation = pickedData['validationStrategy'] ?? 'غير محددة';

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

      // de-normalized
      'taskTitle': pickedTitle,
      'taskDescription': pickedDesc,
      'taskPoints': pickedPoints,
      'taskValidation': pickedValidation,
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

                    _userTaskStream == null
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

                              final sel =
                                  _selectedDay ?? _dayStart(DateTime.now());
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

                              if (sel.isAfter(nextMonthStart)) {
                                return _buildUnavailableCard(
                                  title: 'غير متاحة',
                                  subtitle:
                                      'هذا الشهر لم يُفتح بعد. الرجاء العودة لاحقًا.',
                                );
                              }

                              final data = <String, dynamic>{
                                'title': ut['taskTitle'] ?? '(بدون عنوان)',
                                'description': ut['taskDescription'] ?? '',
                                'points': ut['taskPoints'] ?? 0,
                                'validationStrategy':
                                    ut['taskValidation'] ?? 'غير محددة',
                                'id': ut['taskId'] ?? '',
                                'status': ut['status'] ?? 'pending',
                              };

                              // لو الوثيقة قديمة
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
                                      'title': td['title'] ?? '(بدون عنوان)',
                                      'description': td['description'] ?? '',
                                      'points': td['points'] ?? 0,
                                      'validationStrategy':
                                          td['validationStrategy'] ??
                                          'غير محددة',
                                      'id': ut['taskId'],
                                      'status': ut['status'] ?? 'pending',
                                    };
                                    return _buildUserTaskCard(
                                      taskData: fData,
                                      canPerform: isSameDay(sel, today),
                                    );
                                  },
                                );
                              }

                              return _buildUserTaskCard(
                                taskData: data,
                                canPerform: isSameDay(sel, today),
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
                  color: Color(0xFF4BAA98),
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
    return Container(
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
        onPageChanged: (focused) async {
          _focusedDay = focused;
          _localJustCompleted = false; // ✅ صفّر عند تغيير الشهر/الصفحة
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
            _localJustCompleted = false; // ✅ صفّر عند تغيير اليوم
          });
          await _ensureUserTaskForDate(_dayStart(selected));
          _attachUserTaskStreamFor(selected);
        },
        calendarStyle: CalendarStyle(
          todayDecoration: BoxDecoration(
            color: AppColors.primary33,
            shape: BoxShape.circle,
          ),
          selectedDecoration: BoxDecoration(
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

    // ✅ اقفل إذا الحالة مكتملة أو إذا أكملنا للتو (قبل وصول الـStream)
    final isCompleted = (status == 'completed') || _localJustCompleted;

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

          // ✅ الزر: يتغير حسب الحالة
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: isCompleted
                  ? null // 🔒 غير قابل للنقر إذا مكتملة
                  : () async {
                      final result = await showCompleteTaskSheet(
                        context,
                        taskData,
                      );
                      if (result == true && mounted) {
                        // ✅ اقفل الزر فورًا، وبعدين خلي الـStream يحدث الحالة
                        _localJustCompleted = true;
                        _attachUserTaskStreamFor(_selectedDay!);
                        setState(() {});
                      }
                    },
              style: ButtonStyle(
                elevation: WidgetStateProperty.all(0),
                shadowColor: WidgetStateProperty.all(Colors.transparent),
                backgroundColor: WidgetStateProperty.all(Colors.transparent),
                overlayColor: WidgetStateProperty.all(Colors.transparent),
                shape: WidgetStateProperty.all(
                  RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                padding: WidgetStateProperty.all(
                  const EdgeInsets.symmetric(vertical: 14),
                ),
                splashFactory: NoSplash.splashFactory,
              ),
              child: Ink(
                decoration: BoxDecoration(
                  gradient: isCompleted
                      ? LinearGradient(
                          colors: [Colors.grey.shade400, Colors.grey.shade300],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        )
                      : const LinearGradient(
                          colors: [AppColors.primary, AppColors.mint],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Container(
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Text(
                    isCompleted ? 'تم الإنجاز ✅' : 'تمم المهمة',
                    style: GoogleFonts.ibmPlexSansArabic(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ),

          if (canPerform && !isCompleted) ...[
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
                    _attachUserTaskStreamFor(_selectedDay!);
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

// تعديل دالة showCompleteTaskSheet في نفس الملف أو في ملف complete_task.dart
Future<bool?> showCompleteTaskSheet(
  BuildContext context,
  Map<String, dynamic> taskData,
) {
  return showModalBottomSheet<bool?>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => CompleteTaskSheet(taskData: taskData),
  );
}
