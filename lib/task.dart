import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:math';

// Navigation pages
import 'home.dart';
import 'map.dart';
import 'levels.dart';
import 'community.dart';
import 'services/bottom_nav.dart';
import 'services/background_container.dart';
import 'services/connection.dart';
import 'services/title_header.dart';

// Shared colors
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

  DateTime _dayStart(DateTime d) => DateTime(d.year, d.month, d.day);
  DateTime _dayEnd(DateTime d) => _dayStart(
    d,
  ).add(const Duration(days: 1)).subtract(const Duration(seconds: 1));
  String _yyyyMMdd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';

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
    _bootstrapTodayAndTomorrow();
  }

  Future<void> _bootstrapTodayAndTomorrow() async {
    final user = _auth.currentUser;
    if (user == null) return;

    DateTime fallback = user.metadata.creationTime?.toLocal() ?? DateTime.now();
    _joinDate = _dayStart(fallback);

    final udoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
    if (udoc.exists && (udoc.data()?['joinDate'] != null)) {
      _joinDate = _dayStart((udoc.data()!['joinDate'] as Timestamp).toDate());
    }

    final today = _dayStart(DateTime.now());
    final tomorrow = _dayStart(today.add(const Duration(days: 1)));

    await _ensureUserTaskForDate(today);
    await _ensureUserTaskForDate(tomorrow);

    _attachUserTaskStreamFor(_selectedDay!);
    if (mounted) setState(() {});
  }

  // ============================================================
  // CORE: Ensure userTask exists with ACTIVE & VALID tasks only
  // ============================================================
  Future<void> _ensureUserTaskForDate(DateTime day) async {
    if (_uid == null) return;
    final today = _dayStart(DateTime.now());
    final tomorrow = _dayStart(today.add(const Duration(days: 1)));

    if (_joinDate != null && day.isBefore(_joinDate!)) return;
    if (day.isAfter(tomorrow)) return;

    final key = '${_uid!}_${_yyyyMMdd(day)}';
    final ref = FirebaseFirestore.instance.collection('userTasks').doc(key);
    final snap = await ref.get();
    if (snap.exists) return;

    // 🔹 UPDATED LOGIC FOR VALID TASKS
    final now = DateTime.now();
    final tasksSnap = await FirebaseFirestore.instance
        .collection('tasks')
        .where('isActive', isEqualTo: true)
        .get();

    // Filter out invalid (scheduled or expired)
    final validTasks = tasksSnap.docs.where((doc) {
      final data = doc.data();
      final hasSchedule = data['hasSchedule'] == true;
      final scheduleDate = (data['scheduleDate'] as Timestamp?)?.toDate();
      final hasExpiry = data['hasExpiry'] == true;
      final expiryDate = (data['expiryDate'] as Timestamp?)?.toDate();

      if (hasSchedule && scheduleDate != null && scheduleDate.isAfter(now)) {
        return false;
      }
      if (hasExpiry && expiryDate != null && expiryDate.isBefore(now)) {
        return false;
      }
      return true;
    }).toList();

    if (validTasks.isEmpty) return;

    // Avoid same task as yesterday
    String? yTaskId;
    final yesterday = _dayStart(day.subtract(const Duration(days: 1)));
    final yKey = '${_uid!}_${_yyyyMMdd(yesterday)}';
    final ySnap = await FirebaseFirestore.instance
        .collection('userTasks')
        .doc(yKey)
        .get();
    if (ySnap.exists) yTaskId = ySnap.data()?['taskId'] as String?;

    final candidates = validTasks.where((d) => d.id != yTaskId).toList();
    final pool = candidates.isEmpty ? validTasks : candidates;

    final rnd = Random(
      DateTime.now().millisecondsSinceEpoch ^ day.millisecondsSinceEpoch,
    );
    final picked = pool[rnd.nextInt(pool.length)];

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

  // ============================================================
  // Attach stream for selected day
  // ============================================================
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

  Future<void> _startTask(String taskId) async {
    if (_uid == null || _selectedDay == null) return;

    final key = '${_uid!}_${_yyyyMMdd(_selectedDay!)}';
    final ref = FirebaseFirestore.instance.collection('userTasks').doc(key);
    final snap = await ref.get();
    if (!snap.exists) return;

    final data = snap.data()!;
    final DateTime now = DateTime.now();
    final DateTime ws = (data['windowStart'] as Timestamp).toDate().toLocal();
    final DateTime we = (data['windowEnd'] as Timestamp).toDate().toLocal();

    if (!(now.isAfter(ws.subtract(const Duration(seconds: 1))) &&
        now.isBefore(we.add(const Duration(seconds: 1))))) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'انتهت مدة المهمة لهذا اليوم.',
            style: GoogleFonts.ibmPlexSansArabic(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'بدأت المهمة ✅ بالتوفيق!',
          style: GoogleFonts.ibmPlexSansArabic(
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        backgroundColor: AppColors.primary,
      ),
    );
  }

  Future<void> _markTaskCompleted() async {
    if (_uid == null || _selectedDay == null) return;
    final key = '${_uid!}_${_yyyyMMdd(_selectedDay!)}';
    final ref = FirebaseFirestore.instance.collection('userTasks').doc(key);

    await ref.update({
      'status': 'completed',
      'completedAt': Timestamp.fromDate(DateTime.now()),
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'تم إكمال المهمة 🎉 أحسنتِ!',
            style: GoogleFonts.ibmPlexSansArabic(
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          backgroundColor: AppColors.primary,
        ),
      );
    }
  }

  Future<void> _autoMarkExpiredIfNeeded(DocumentSnapshot snap) async {
    if (!snap.exists) return;
    final data = snap.data() as Map<String, dynamic>;
    final status = (data['status'] as String?) ?? 'pending';
    if (status != 'pending') return;

    final DateTime we = (data['windowEnd'] as Timestamp).toDate().toLocal();
    if (DateTime.now().isAfter(we)) {
      await snap.reference.update({'status': 'uncompleted'});
    }
  }

  @override
  Widget build(BuildContext context) {
    final isKeyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;
    final baseTheme = Theme.of(context);
    final textTheme = GoogleFonts.ibmPlexSansArabicTextTheme(
      baseTheme.textTheme,
    );

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Theme(
        data: baseTheme.copyWith(
          textTheme: textTheme,
          appBarTheme: AppBarTheme(
            elevation: 0,
            backgroundColor: Colors.transparent,
            titleTextStyle: GoogleFonts.ibmPlexSansArabic(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ),
        child: Scaffold(
          extendBody: true,
          backgroundColor: Colors.transparent,
          extendBodyBehindAppBar: true,

          // ✅ الهيدر العام (بدون عنوان داخله)
          appBar: const NameerAppBar(
            showTitleInBar: false,
            showBack: false, // زر الرجوع موجود
          ),

          body: AnimatedBackgroundContainer(
            child: Builder(
              builder: (context) {
                // المسافة تحت الهيدر
                final statusBar = MediaQuery.of(context).padding.top;
                const headerH = 20.0;
                const gap = 12.0;
                final topPadding = statusBar + headerH + gap;

                // حشوة سفلية ديناميكية (ناف بار / كيبورد)
                final viewInsets = MediaQuery.of(context).viewInsets.bottom;
                final isKeyboardOpen = viewInsets > 0;
                final bottomPad = isKeyboardOpen
                    ? viewInsets +
                          16 // لو الكيبورد مفتوح
                    : kBottomNavigationBarHeight +
                          24; // لو مقفول: مساحة للناف بار

                return SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(16, topPadding, 16, bottomPad),
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // العنوان تحت الهيدر مباشرة
                      Text(
                        'مهامي',
                        style: GoogleFonts.ibmPlexSansArabic(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: AppColors.dark,
                        ),
                      ),
                      const SizedBox(height: 15),

                      // التقويم
                      _buildCalendar(),
                      const SizedBox(height: 8),

                      // المحتوى (ستريم) — غير قابل للسكرول منفصل
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
                                      padding: EdgeInsets.symmetric(
                                        vertical: 40,
                                      ),
                                      child: CircularProgressIndicator(
                                        color: AppColors.primary,
                                      ),
                                    ),
                                  );
                                }

                                if (snap.hasError) {
                                  WidgetsBinding.instance.addPostFrameCallback((
                                    _,
                                  ) {
                                    if (context.mounted)
                                      showNoInternetDialog(context);
                                  });
                                  return const SizedBox.shrink();
                                }

                                if (!snap.hasData || !snap.data!.exists) {
                                  _ensureUserTaskForDate(
                                    _selectedDay ?? DateTime.now(),
                                  );
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

                                _autoMarkExpiredIfNeeded(snap.data!);
                                final sel =
                                    _selectedDay ?? _dayStart(DateTime.now());
                                final today = _dayStart(DateTime.now());
                                final tomorrow = _dayStart(
                                  today.add(const Duration(days: 1)),
                                );

                                if (_joinDate != null &&
                                    sel.isBefore(_joinDate!)) {
                                  return _buildUnavailableCard(
                                    title: 'غير متاحة',
                                    subtitle: 'لم تكن ضمن نمير في هذا التاريخ.',
                                  );
                                }

                                if (sel.isAfter(tomorrow)) {
                                  return _buildUnavailableCard(
                                    title: 'غير متاحة',
                                    subtitle:
                                        'هذا اليوم لم يُفتح بعد. الرجاء العودة لاحقًا.',
                                  );
                                }

                                final ut =
                                    snap.data!.data() as Map<String, dynamic>;
                                final taskId = ut['taskId'] as String?;
                                final status =
                                    (ut['status'] as String?) ?? 'pending';
                                final DateTime now = DateTime.now();

                                final isToday = sel.isAtSameMomentAs(today);
                                final isTomorrow = sel.isAtSameMomentAs(
                                  tomorrow,
                                );
                                final isPast = sel.isBefore(today);
                                final inWindow = _isWithinDayWindow(sel, now);

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
                                          padding: EdgeInsets.symmetric(
                                            vertical: 40,
                                          ),
                                          child: CircularProgressIndicator(
                                            color: AppColors.primary,
                                          ),
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

                                    final data =
                                        taskSnap.data!.data()
                                            as Map<String, dynamic>;

                                    final isActive = data['isActive'] == true;
                                    final hasSchedule =
                                        data['hasSchedule'] == true;
                                    final scheduleDate =
                                        (data['scheduleDate'] as Timestamp?)
                                            ?.toDate();
                                    final hasExpiry = data['hasExpiry'] == true;
                                    final expiryDate =
                                        (data['expiryDate'] as Timestamp?)
                                            ?.toDate();

                                    if (!isActive ||
                                        (hasSchedule &&
                                            scheduleDate != null &&
                                            scheduleDate.isAfter(now)) ||
                                        (hasExpiry &&
                                            expiryDate != null &&
                                            expiryDate.isBefore(now))) {
                                      return _buildUnavailableCard(
                                        title: 'المهمة غير متاحة',
                                        subtitle:
                                            'قد تم إيقافها أو لم تبدأ بعد أو انتهت صلاحيتها.',
                                      );
                                    }

                                    final bool canPerform = isToday && inWindow;

                                    // كارد واحد يتمرر مع الصفحة
                                    return _buildUserTaskCard(
                                      taskDocId: taskSnap.data!.id,
                                      taskData: data,
                                      status: status,
                                      isToday: isToday,
                                      isTomorrow: isTomorrow,
                                      isPast: isPast,
                                      canPerform: canPerform,
                                    );
                                  },
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
      ),
    );
  }

  // 🔹 Calendar Widget
  // 🔹 Calendar Widget (خلايا مربّعة ومتناسقة)
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
      child: LayoutBuilder(
        builder: (context, constraints) {
          // نحسب عرض الخلية = (العرض المتاح - padding الأفقي) / 7
          const horizPad = 4.0;
          const vertPad = 2.0;
          final availableW = constraints.maxWidth - (horizPad * 2);
          final cellSize = (availableW / 7)
              .floorToDouble(); // نخليه عدد صحيح عشان لا يصير blur
          final dotSize = cellSize * 0.72; // قطر دائرة اليوم (مريح بصريًا)
          final dayFont = cellSize * 0.36; // مقاس خط رقم اليوم
          final dowFont = cellSize * 0.28; // مقاس خط حروف الأيام

          return Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: horizPad,
              vertical: vertPad,
            ),
            child: TableCalendar(
              focusedDay: _focusedDay,
              firstDay: DateTime.utc(2020),
              lastDay: DateTime.utc(2030),
              calendarFormat: CalendarFormat.month,

              // ✅ نخلي ارتفاع الصف مساوي لعرض الخلية → مربّع
              rowHeight: cellSize,
              // صف عناوين الأيام أصغر شوي
              daysOfWeekHeight: (cellSize * 0.6).clamp(20, 28),

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

              daysOfWeekStyle: DaysOfWeekStyle(
                weekdayStyle: GoogleFonts.ibmPlexSansArabic(
                  color: AppColors.dark,
                  fontWeight: FontWeight.w700,
                  fontSize: dowFont,
                  height: 1.1,
                ),
                weekendStyle: GoogleFonts.ibmPlexSansArabic(
                  color: AppColors.dark.withOpacity(0.7),
                  fontWeight: FontWeight.w700,
                  fontSize: dowFont,
                  height: 1.1,
                ),
              ),

              calendarStyle: CalendarStyle(
                outsideDaysVisible: false,
                defaultTextStyle: GoogleFonts.ibmPlexSansArabic(
                  color: AppColors.dark,
                  fontWeight: FontWeight.w600,
                  fontSize: dayFont,
                ),
                weekendTextStyle: GoogleFonts.ibmPlexSansArabic(
                  color: AppColors.dark.withOpacity(0.7),
                  fontWeight: FontWeight.w600,
                  fontSize: dayFont,
                ),
                todayDecoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.mint.withOpacity(0.35),
                ),
                selectedDecoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [AppColors.mint, AppColors.primary],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                selectedTextStyle: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
                todayTextStyle: GoogleFonts.ibmPlexSansArabic(
                  color: AppColors.dark,
                  fontWeight: FontWeight.w700,
                  fontSize: dayFont,
                ),
              ),

              calendarBuilders: CalendarBuilders(
                defaultBuilder: (context, day, focusedDay) {
                  return _gridCell(
                    child: Text(
                      '${day.day}',
                      style: GoogleFonts.ibmPlexSansArabic(
                        color: AppColors.dark,
                        fontWeight: FontWeight.w600,
                        fontSize: dayFont,
                      ),
                    ),
                  );
                },
                outsideBuilder: (context, day, focusedDay) {
                  return _gridCell(
                    borderOpacity: 0.06,
                    child: Text(
                      '${day.day}',
                      style: GoogleFonts.ibmPlexSansArabic(
                        color: AppColors.dark.withOpacity(0.35),
                        fontWeight: FontWeight.w600,
                        fontSize: dayFont,
                      ),
                    ),
                  );
                },
                todayBuilder: (context, day, focusedDay) {
                  return _gridCell(
                    child: Container(
                      width: dotSize,
                      height: dotSize,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.mint.withOpacity(0.35),
                        border: Border.all(
                          color: AppColors.primary.withOpacity(0.10),
                          width: 1.5,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '${day.day}',
                        style: GoogleFonts.ibmPlexSansArabic(
                          color: AppColors.dark,
                          fontWeight: FontWeight.w700,
                          fontSize: dayFont,
                        ),
                      ),
                    ),
                  );
                },
                selectedBuilder: (context, day, focusedDay) {
                  return _gridCell(
                    child: Container(
                      width: dotSize,
                      height: dotSize,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [AppColors.mint, AppColors.primary],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '${day.day}',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: dayFont,
                        ),
                      ),
                    ),
                  );
                },
                dowBuilder: (context, day) {
                  final labels = ['ح', 'ن', 'ث', 'ر', 'خ', 'ج', 'س'];
                  return _gridCell(
                    child: Text(
                      labels[day.weekday % 7],
                      style: GoogleFonts.ibmPlexSansArabic(
                        color: AppColors.dark.withOpacity(0.7),
                        fontWeight: FontWeight.w700,
                        fontSize: dowFont,
                        height: 1.1,
                      ),
                    ),
                  );
                },
              ),

              selectedDayPredicate: (day) =>
                  isSameDay(_selectedDay ?? DateTime.now(), day),
              onDaySelected: (selected, focused) async {
                if (!await hasInternetConnection()) {
                  if (context.mounted) showNoInternetDialog(context);
                  return;
                }
                final sel = _dayStart(selected);
                final today = _dayStart(DateTime.now());
                final tomorrow = _dayStart(today.add(const Duration(days: 1)));
                if (sel.isAfter(tomorrow)) {
                  setState(() {
                    _selectedDay = sel;
                    _focusedDay = focused;
                  });
                  _attachUserTaskStreamFor(sel);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'هذا اليوم غير متاح بعد. الرجاء اختيار اليوم أو الغد.',
                      ),
                    ),
                  );
                  return;
                }
                if (_joinDate != null && sel.isBefore(_joinDate!)) {
                  setState(() {
                    _selectedDay = sel;
                    _focusedDay = focused;
                  });
                  _attachUserTaskStreamFor(sel);
                  return;
                }
                await _ensureUserTaskForDate(sel);
                setState(() {
                  _selectedDay = sel;
                  _focusedDay = focused;
                });
                _attachUserTaskStreamFor(sel);
              },
            ),
          );
        },
      ),
    );
  }

  /// مربع خلية مع شبكة خضراء خفيفة
  Widget _gridCell({required Widget child, double borderOpacity = 0.08}) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(
            color: AppColors.primary.withOpacity(borderOpacity),
            width: 1,
          ),
          bottom: BorderSide(
            color: AppColors.primary.withOpacity(borderOpacity),
            width: 1,
          ),
        ),
      ),
      alignment: Alignment.center,
      child: child,
    );
  }

  // 🔹 Unavailable Card Builder
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

  // 🔹 User Task Card Builder
  Widget _buildUserTaskCard({
    required String taskDocId,
    required Map<String, dynamic> taskData,
    required String status,
    required bool isToday,
    required bool isTomorrow,
    required bool isPast,
    required bool canPerform,
  }) {
    final title = taskData['title'] ?? 'مهمة غير محددة';
    final description = taskData['description'] ?? 'لا يوجد وصف متاح.';
    final points = taskData['points'] ?? 0;
    final validation = taskData['validationStrategy'] ?? 'غير محددة';

    String banner = 'مهمة اليوم';
    if (isTomorrow) banner = 'مهمة الغد (استعراض فقط)';
    if (isPast) banner = status == 'completed' ? 'مهمة مكتملة' : 'مهمة فائتة';

    final btnText = isTomorrow
        ? 'استعراض فقط'
        : isPast
        ? (status == 'completed' ? 'مكتملة' : 'انتهى الوقت')
        : (canPerform ? 'ابدأ المهمة' : 'غير متاحة الآن');

    final btnEnabled = canPerform;

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
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Text(
            banner,
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
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: InkWell(
              onTap: btnEnabled ? () {} : null,
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  vertical: 14,
                  horizontal: 20,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  gradient: btnEnabled
                      ? const LinearGradient(
                          colors: [AppColors.primary, AppColors.mint],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        )
                      : const LinearGradient(
                          colors: [Colors.grey, Colors.grey],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        ),
                  boxShadow: [
                    if (btnEnabled)
                      const BoxShadow(
                        color: Color(0x33000000),
                        blurRadius: 8,
                        offset: Offset(0, 4),
                      ),
                  ],
                ),
                alignment: Alignment.center,
                child: Text(
                  btnText,
                  style: GoogleFonts.ibmPlexSansArabic(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
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
