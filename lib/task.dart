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

// Shared colors
class AppColors {
  static const primary = Color(0xFF009688);
  static const dark = Color(0xFF00695C);
  static const light = Color(0xFF4DB6AC);
  static const background = Color(0xFFFAFCFB);
  static const mint = Color(0xFFB6E9C1);
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
  DateTime _dayEnd(DateTime d) =>
      _dayStart(d).add(const Duration(days: 1)).subtract(const Duration(seconds: 1));
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

    final udoc =
        await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
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

    final rnd =
        Random(DateTime.now().millisecondsSinceEpoch ^ day.millisecondsSinceEpoch);
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
      _userTaskStream =
          FirebaseFirestore.instance.collection('userTasks').doc(key).snapshots();
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          'انتهت مدة المهمة لهذا اليوم.',
          style: GoogleFonts.ibmPlexSansArabic(
              color: Colors.white, fontWeight: FontWeight.w700),
        ),
        backgroundColor: Colors.redAccent,
      ));
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
        'بدأت المهمة ✅ بالتوفيق!',
        style: GoogleFonts.ibmPlexSansArabic(
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
      backgroundColor: AppColors.primary,
    ));
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          'تم إكمال المهمة 🎉 أحسنتِ!',
          style: GoogleFonts.ibmPlexSansArabic(
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        backgroundColor: AppColors.primary,
      ));
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
    final textTheme =
        GoogleFonts.ibmPlexSansArabicTextTheme(baseTheme.textTheme);

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
          appBar: AppBar(
            centerTitle: true,
            title: const Text("مهامي"),
            flexibleSpace: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.primary,
                    AppColors.primary,
                    AppColors.mint,
                  ],
                  begin: Alignment.bottomLeft,
                  end: Alignment.topRight,
                ),
              ),
            ),
          ),
          body: AnimatedBackgroundContainer(
            child: Column(
              children: [
                const SizedBox(height: 12),
                _buildCalendar(),
                const SizedBox(height: 8),
                Expanded(
                  child: _userTaskStream == null
                      ? const Center(
                          child: CircularProgressIndicator(
                            color: AppColors.primary,
                          ),
                        )
                      : StreamBuilder<DocumentSnapshot>(
                          stream: _userTaskStream!,
                          builder: (context, snap) {
                            if (snap.connectionState ==
                                ConnectionState.waiting) {
                              return const Center(
                                child: CircularProgressIndicator(
                                  color: AppColors.primary,
                                ),
                              );
                            }

                            if (snap.hasError) {
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (context.mounted)
                                  showNoInternetDialog(context);
                              });
                              return const SizedBox.shrink();
                            }

                            if (!snap.hasData || !snap.data!.exists) {
                              _ensureUserTaskForDate(
                                  _selectedDay ?? DateTime.now());
                              return const Center(
                                child: CircularProgressIndicator(
                                  color: AppColors.primary,
                                ),
                              );
                            }

                            _autoMarkExpiredIfNeeded(snap.data!);
                            final sel = _selectedDay ?? _dayStart(DateTime.now());
                            final today = _dayStart(DateTime.now());
                            final tomorrow =
                                _dayStart(today.add(const Duration(days: 1)));

                            if (_joinDate != null && sel.isBefore(_joinDate!)) {
                              return _buildUnavailableCard(
                                title: 'غير متاحة',
                                subtitle: 'لم تكن ضمن نمير في هذا التاريخ.',
                              );
                            }

                            if (sel.isAfter(tomorrow)) {
                              return _buildUnavailableCard(
                                title: 'غير متاحة',
                                subtitle: 'هذا اليوم لم يُفتح بعد. الرجاء العودة لاحقًا.',
                              );
                            }

                            final ut = snap.data!.data() as Map<String, dynamic>;
                            final taskId = ut['taskId'] as String?;
                            final status = (ut['status'] as String?) ?? 'pending';
                            final DateTime now = DateTime.now();

                            final isToday = sel.isAtSameMomentAs(today);
                            final isTomorrow = sel.isAtSameMomentAs(tomorrow);
                            final isPast = sel.isBefore(today);
                            final inWindow = _isWithinDayWindow(sel, now);

                            // Load referenced task
                            return FutureBuilder<DocumentSnapshot>(
                              future: FirebaseFirestore.instance
                                  .collection('tasks')
                                  .doc(taskId)
                                  .get(),
                              builder: (context, taskSnap) {
                                if (taskSnap.connectionState ==
                                    ConnectionState.waiting) {
                                  return const Center(
                                    child: CircularProgressIndicator(
                                      color: AppColors.primary,
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

                                // 🔹 UPDATED LOGIC FOR VALID TASKS
                                final isActive = data['isActive'] == true;
                                final hasSchedule = data['hasSchedule'] == true;
                                final scheduleDate =
                                    (data['scheduleDate'] as Timestamp?)
                                        ?.toDate();
                                final hasExpiry = data['hasExpiry'] == true;
                                final expiryDate =
                                    (data['expiryDate'] as Timestamp?)
                                        ?.toDate();

                                // If not active, scheduled in future, or expired → unavailable
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
                ),
              ],
            ),
          ),
          bottomNavigationBar: isKeyboardOpen
              ? null
              : BottomNavPage(currentIndex: _currentIndex, onTap: _onTap),
        ),
      ),
    );
  }

  // 🔹 Calendar Widget — unchanged
  Widget _buildCalendar() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFF4BAA98),
            Color(0xFF6BBAA2),
            Color(0xFFAFDBB8),
          ],
          begin: Alignment.bottomLeft,
          end: Alignment.topRight,
          stops: [0.0, 0.63, 1.0],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: TableCalendar(
          focusedDay: _focusedDay,
          firstDay: DateTime.utc(2020),
          lastDay: DateTime.utc(2030),
          calendarFormat: CalendarFormat.month,
          headerStyle: HeaderStyle(
            formatButtonVisible: false,
            titleCentered: true,
            titleTextStyle: GoogleFonts.ibmPlexSansArabic(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 18,
            ),
            leftChevronIcon: const Icon(Icons.chevron_left, color: Colors.white),
            rightChevronIcon: const Icon(Icons.chevron_right, color: Colors.white),
          ),
          daysOfWeekStyle: DaysOfWeekStyle(
            weekdayStyle: GoogleFonts.ibmPlexSansArabic(color: Colors.white70),
            weekendStyle: GoogleFonts.ibmPlexSansArabic(color: Colors.white70),
          ),
          calendarStyle: CalendarStyle(
            defaultTextStyle: GoogleFonts.ibmPlexSansArabic(color: Colors.white),
            weekendTextStyle: GoogleFonts.ibmPlexSansArabic(color: Colors.white70),
            outsideDaysVisible: false,
            todayDecoration: BoxDecoration(
              color: AppColors.mint.withOpacity(0.8),
              shape: BoxShape.circle,
            ),
            selectedDecoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            selectedTextStyle: const TextStyle(color: AppColors.primary),
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
                SnackBar(
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
      ),
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
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
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

