import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:math';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:cloud_functions/cloud_functions.dart';
import 'home.dart';
import 'map.dart';
import 'levels.dart';
import 'community.dart';
import 'article.dart';
import 'services/bottom_nav.dart';
import 'services/background_container.dart';
import 'services/connection.dart';
import 'services/title_header.dart';
import 'complete_task.dart';
import 'levels.dart';

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
  bool _bonusLoading = false;
  Map<String, dynamic>? _suggestedBonusTask;

  String? _userLevel; // مستوى المستخدم (beginner, medium, hard)
  String _userLevelName = 'مبتدئ'; // اسم المستوى بالعربي
  int _completedTasksToday = 0; // المهام المكتملة اليوم
  int _requiredTasksToday = 1; // المهام المطلوبة اليوم
  bool _isLoadingProgress = true; // حالة تحميل البروقريس
  StreamSubscription<DocumentSnapshot>? _userTasksSubscription;

  final int _currentIndex = 1;

  bool _isInitializing = true;

  bool _precheckDone = false;
  String? _precheckError;

  bool _isMonthLoading = false;
  bool _scheduleMode = false;
  final Set<DateTime> _scheduledDays = {};
  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
  bool _isScheduledDay(DateTime d) => _scheduledDays.contains(_dateOnly(d));
  Widget _buildDayCell(
    DateTime day, {
    bool forceSelected = false,
    bool isTodayOverride = false,
  }) {
    final d = _dayStart(day);
    final bool isSel = forceSelected || isSameDay(d, _selectedDay);
    final bool isToday =
        isTodayOverride || isSameDay(d, _dayStart(DateTime.now()));
    final bool isScheduled = _isScheduledDay(d);

    final bool showCompleted = _isCompletedDay(d) && !isSel && !isToday;

    return SizedBox.expand(
      child: Stack(
        alignment: Alignment.center,
        children: [
          // ✅ خلفية "مكتمل"
          if (showCompleted)
            Container(
              width: 36,
              height: 36,
              decoration: const BoxDecoration(
                color: AppColors.primary33,
                shape: BoxShape.circle,
              ),
            ),

          // ✅ نفس لون "اليوم الحالي" اللي عندك في calendarStyle
          if (isToday && !isSel)
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.08),
                shape: BoxShape.circle,
              ),
            ),

          // ✅ نفس لون "التحديد" اللي عندك (أخضر)
          if (isSel)
            Container(
              width: 36,
              height: 36,
              decoration: const BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
              ),
            ),

          // ✅ رقم اليوم (نخليه نفس ستايلك)
          Text(
            '${d.day}',
            style: GoogleFonts.ibmPlexSansArabic(
              color: isSel
                  ? Colors.white
                  : AppColors.dark, // زي الطبيعي فوق الأخضر أبيض
              fontWeight: FontWeight.w600,
              fontSize: 13.5,
            ),
          ),

          // 🔔 الجرس — يطلع حتى لو اليوم محدد
          // إذا تبينه يطلع حتى في today بعد: شيل شرط !isToday
          if (isScheduled && !isToday)
            Positioned(
              top: 6,
              right: 10,
              child: Icon(
                Icons.notifications_active,
                size: 14,
                color: AppColors.accent,
              ),
            ),
        ],
      ),
    );
  }

  void _openScheduleTaskPicker(DateTime selectedDay) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        String q = '';

        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return Dialog(
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 24,
              ),
              backgroundColor: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x22000000),
                      blurRadius: 18,
                      offset: Offset(0, 10),
                    ),
                  ],
                  border: Border.all(
                    color: AppColors.primary.withOpacity(0.35),
                    width: 1.2,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ===== Header =====
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'اختر المهمة',
                            style: GoogleFonts.ibmPlexSansArabic(
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                              color: AppColors.dark,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(ctx),
                          icon: const Icon(Icons.close, color: AppColors.dark),
                          splashRadius: 18,
                        ),
                      ],
                    ),

                    const SizedBox(height: 8),

                    // ===== Search (اختياري بس يطلع شكل مرتب) =====
                    TextField(
                      onChanged: (v) => setLocal(() => q = v.trim()),
                      decoration: InputDecoration(
                        hintText: 'ابحث عن مهمة…',
                        hintStyle: GoogleFonts.ibmPlexSansArabic(
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.w600,
                        ),
                        prefixIcon: const Icon(
                          Icons.search,
                          color: AppColors.primary,
                        ),
                        filled: true,
                        fillColor: AppColors.background.withOpacity(0.7),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(
                            color: AppColors.primary,
                            width: 1.6,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),

                    // ===== Body =====
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.of(ctx).size.height * 0.55,
                      ),
                      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        stream: _activeTasksStream(),
                        builder: (context, snap) {
                          if (snap.connectionState == ConnectionState.waiting) {
                            return const Center(
                              child: Padding(
                                padding: EdgeInsets.all(18),
                                child: CircularProgressIndicator(
                                  color: AppColors.primary,
                                ),
                              ),
                            );
                          }

                          if (!snap.hasData || snap.data!.docs.isEmpty) {
                            return Padding(
                              padding: const EdgeInsets.all(12),
                              child: Text(
                                'لا توجد مهام متاحة لهذا الشهر',
                                style: GoogleFonts.ibmPlexSansArabic(
                                  color: Colors.grey.shade700,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            );
                          }

                          final docs = snap.data!.docs;

                          // فلترة بالبحث (عنوان + وصف)
                          final filtered = q.isEmpty
                              ? docs
                              : docs.where((d) {
                                  final m = d.data();
                                  final title = (m['title'] ?? '')
                                      .toString()
                                      .toLowerCase();
                                  final desc = (m['description'] ?? '')
                                      .toString()
                                      .toLowerCase();
                                  final qq = q.toLowerCase();
                                  return title.contains(qq) ||
                                      desc.contains(qq);
                                }).toList();

                          if (filtered.isEmpty) {
                            return Padding(
                              padding: const EdgeInsets.all(12),
                              child: Text(
                                'لا يوجد مهام مطابقة للبحث.',
                                style: GoogleFonts.ibmPlexSansArabic(
                                  color: Colors.grey.shade700,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            );
                          }

                          return ListView.separated(
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) =>
                                Divider(height: 1, color: Colors.grey.shade200),
                            itemBuilder: (context, i) {
                              final doc = filtered[i];
                              final t = doc.data();

                              return InkWell(
                                borderRadius: BorderRadius.circular(14),
                                onTap: () {
                                  Navigator.pop(ctx);
                                  _confirmSchedule(
                                    selectedDay: selectedDay,
                                    taskId: doc.id,
                                    taskTitle: (t['title'] ?? '').toString(),
                                  );
                                },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 10,
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 40,
                                        height: 40,
                                        decoration: BoxDecoration(
                                          color: AppColors.primary.withOpacity(
                                            0.12,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        child: const Icon(
                                          Icons.task_alt,
                                          color: AppColors.primary,
                                        ),
                                      ),
                                      const SizedBox(width: 10),

                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              (t['title'] ?? '').toString(),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style:
                                                  GoogleFonts.ibmPlexSansArabic(
                                                    fontWeight: FontWeight.w800,
                                                    color: AppColors.dark,
                                                    fontSize: 14.5,
                                                  ),
                                            ),
                                            const SizedBox(height: 3),
                                            Text(
                                              (t['description'] ?? '')
                                                  .toString(),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style:
                                                  GoogleFonts.ibmPlexSansArabic(
                                                    fontSize: 12.5,
                                                    color: Colors.grey.shade700,
                                                    height: 1.3,
                                                  ),
                                            ),
                                          ],
                                        ),
                                      ),

                                      const SizedBox(width: 8),
                                    ],
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),

                    const SizedBox(height: 10),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _loadScheduledDaysForMonth(DateTime anyDayInMonth) async {
    if (_uid == null) return;

    final ms = DateTime(anyDayInMonth.year, anyDayInMonth.month, 1);
    final me = DateTime(
      anyDayInMonth.year,
      anyDayInMonth.month + 1,
      1,
    ).subtract(const Duration(milliseconds: 1));

    final qs = await FirebaseFirestore.instance
        .collection('scheduledTasks')
        .where('userId', isEqualTo: _uid)
        .where('status', isEqualTo: 'scheduled')
        .where('scheduledFor', isGreaterThanOrEqualTo: Timestamp.fromDate(ms))
        .where('scheduledFor', isLessThanOrEqualTo: Timestamp.fromDate(me))
        .get();

    final newSet = <DateTime>{};
    for (final doc in qs.docs) {
      final ts = doc.data()['scheduledFor'];
      if (ts is Timestamp) {
        final d = ts.toDate();
        final today = _dayStart(DateTime.now());
        final onlyDate = DateTime(d.year, d.month, d.day);
        if (!onlyDate.isBefore(today)) {
          newSet.add(onlyDate);
        }
      }
    }

    if (!mounted) return;
    setState(() {
      _scheduledDays
        ..clear()
        ..addAll(newSet);
    });
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _activeTasksStream() {
    final now = DateTime.now();
    final nowKey = "${now.year}-${now.month.toString().padLeft(2, '0')}";

    return FirebaseFirestore.instance
        .collection('tasks')
        .where('status', isEqualTo: 'active')
        .where('visible_from', isLessThanOrEqualTo: nowKey)
        .orderBy('visible_from', descending: true)
        .snapshots();
  }

  Future<void> _confirmSchedule({
    required DateTime selectedDay,
    required String taskId,
    required String taskTitle,
  }) async {
    if (_uid == null) return;

    final startOfDay = DateTime(
      selectedDay.year,
      selectedDay.month,
      selectedDay.day,
    );
    final endOfDay = startOfDay
        .add(const Duration(days: 1))
        .subtract(const Duration(seconds: 1));

    try {
      // 1) تحقق هل فيه مهمة مجدولة لنفس اليوم
      final existing = await FirebaseFirestore.instance
          .collection('scheduledTasks')
          .where('userId', isEqualTo: _uid)
          .where('status', isEqualTo: 'scheduled')
          .where(
            'scheduledFor',
            isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay),
          )
          .where(
            'scheduledFor',
            isLessThanOrEqualTo: Timestamp.fromDate(endOfDay),
          )
          .limit(1)
          .get();

      String? existingScheduleDocId;
      if (existing.docs.isNotEmpty) {
        existingScheduleDocId = existing.docs.first.id;
      }

      final schedCol = FirebaseFirestore.instance.collection('scheduledTasks');

      if (existingScheduleDocId != null) {
        await schedCol.doc(existingScheduleDocId).update({
          'userId': _uid,
          'taskId': taskId,
          'taskTitle': taskTitle,
          'scheduledFor': Timestamp.fromDate(startOfDay),
          'updatedAt': FieldValue.serverTimestamp(),
          'status': 'scheduled',
        });
      } else {
        final added = await schedCol.add({
          'userId': _uid,
          'taskId': taskId,
          'taskTitle': taskTitle,
          'scheduledFor': Timestamp.fromDate(startOfDay),
          'createdAt': FieldValue.serverTimestamp(),
          'status': 'scheduled',
        });
        existingScheduleDocId = added.id; // ✅ هذا المهم
      }

      // ✅ 3) (المهم) تحديث userTasks لنفس اليوم عشان الكرت تحت يتغير
      final utKey = '${_uid!}_${_yyyyMMdd(selectedDay)}';
      final utRef = FirebaseFirestore.instance
          .collection('userTasks')
          .doc(utKey);

      // نجيب تفاصيل المهمة من tasks (نقاط/وصف/طريقة تحقق)
      final taskSnap = await FirebaseFirestore.instance
          .collection('tasks')
          .doc(taskId)
          .get();

      final taskData = taskSnap.data() ?? {};

      await utRef.set({
        'userId': _uid,
        'taskId': taskId,
        'taskTitle': taskData['title'] ?? taskTitle,
        'taskDescription': taskData['description'] ?? '',
        'taskPoints': taskData['points'] ?? 0,
        'taskValidation': taskData['validationStrategy'] ?? 'غير محددة',

        'selectedAt': Timestamp.fromDate(startOfDay),
        'windowStart': Timestamp.fromDate(startOfDay),
        'windowEnd': Timestamp.fromDate(endOfDay),

        'status': 'pending',
        'completedAt': null,
        'isScheduled': true,
        'scheduledDocId': existingScheduleDocId,

        'ignored': false,
        'ignoredAt': null,
      }, SetOptions(merge: true));

      // 4) علّم اليوم عشان تظهر الأيقونة
      if (!mounted) return;
      setState(() {
        _scheduledDays.add(_dateOnly(selectedDay));
      });

      // ✅ 5) لو اليوم اللي جدولتِه هو نفسه المحدد الآن في الكالندر
      // خلّي الكرت تحت يسمع له فورًا
      if (_selectedDay != null && isSameDay(_selectedDay, selectedDay)) {
        _attachUserTaskStreamFor(_dayStart(selectedDay));
      }

      // 6) Popup "تمت الجدولة"
      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(
            'تمت الجدولة ✅',
            style: GoogleFonts.ibmPlexSansArabic(fontWeight: FontWeight.w800),
          ),
          content: Text(
            'تمت جدولة المهمة ليوم ${selectedDay.day}/${selectedDay.month}/${selectedDay.year}',
            style: GoogleFonts.ibmPlexSansArabic(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'تم',
                style: GoogleFonts.ibmPlexSansArabic(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      );

      // 7) رجّعه للوضع العادي
      if (!mounted) return;
      setState(() => _scheduleMode = false);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'صار خطأ أثناء الجدولة: $e',
            style: GoogleFonts.ibmPlexSansArabic(color: Colors.white),
          ),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

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

  // ====================================================
  // دالة تحول levelId إلى اسم عربي
  // ====================================================
  String _getLevelName(String levelId) {
    switch (levelId) {
      case 'beginner':
        return 'مبتدئ';
      case 'medium':
        return 'متوسط';
      case 'hard':
        return 'متقدم';
      default:
        return 'مبتدئ';
    }
  }

  // ====================================================
  // دالة تحسب عدد المهام المطلوبة حسب مستوى المستخدم
  // ====================================================
  int _getRequiredTasksPerDay(String levelId) {
    switch (levelId) {
      case 'hard':
        return 2;
      case 'medium':
        return 2;
      case 'beginner':
      default:
        return 1;
    }
  }

  // ====================================================
  // دالة تحسب المهام المكتملة لليوم
  // ====================================================
  Future<int> _getCompletedTasksForDay(String userId, DateTime day) async {
    final dayKey = '${userId}_${_yyyyMMdd(day)}';
    final bonusKey = '${userId}_${_yyyyMMdd(day)}_bonus';
    final dailyTaskDate = _dayId(day);

    int count = 0;

    try {
      // 1️⃣ المهمة الرئيسية من userTasks
      final mainTask = await FirebaseFirestore.instance
          .collection('userTasks')
          .doc(dayKey)
          .get();

      if (mainTask.exists && mainTask.data()?['status'] == 'completed') {
        count++;
      }

      // 2️⃣ المهمة الإضافية من userTasks
      final bonusTask = await FirebaseFirestore.instance
          .collection('userTasks')
          .doc(bonusKey)
          .get();

      if (bonusTask.exists && bonusTask.data()?['status'] == 'completed') {
        count++;
      }

      // 🔥🔥🔥 3️⃣ المهمة من dailyTasks (الهوم بيج) 🔥🔥🔥
      final dailyTask = await FirebaseFirestore.instance
          .collection('dailyTasks')
          .doc(userId)
          .collection('tasks')
          .doc(dailyTaskDate)
          .get();

      // ✅ dailyTasks تستخدم حقل completed من نوع boolean
      if (dailyTask.exists && dailyTask.data()?['completed'] == true) {
        count++;
        print('✅ Found completed daily task in home page');
      }
    } catch (e) {
      debugPrint('⚠️ Error getting completed tasks: $e');
    }

    return count;
  }

  // ====================================================
  // جلب مستوى المستخدم والمهام المكتملة لليوم
  // ====================================================
  String _dayId(DateTime dt) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)}';
  }

  void _watchUserProgress() {
    if (_uid == null || _selectedDay == null) return;

    final dayKey = '${_uid}_${_yyyyMMdd(_selectedDay!)}';
    final bonusKey = '${_uid}_${_yyyyMMdd(_selectedDay!)}_bonus';
    final dailyTaskDate = _dayId(_selectedDay!);

    print('👀 Watching all progress sources for: $dayKey');

    // إلغاء الاشتراكات السابقة
    _userTasksSubscription?.cancel();

    int updateCount = 0;

    // دالة لحساب المهام المكتملة من جميع المصادر
    Future<int> _calculateCompletedTasks() async {
      int completed = 0;

      try {
        // 1️⃣ التحقق من userTasks (المهمة الرئيسية)
        final mainSnapshot = await FirebaseFirestore.instance
            .collection('userTasks')
            .doc(dayKey)
            .get(GetOptions(source: Source.server));

        if (mainSnapshot.exists) {
          final status = mainSnapshot.data()?['status'] as String?;
          print('📄 Main userTask status (server): $status');
          if (status == 'completed') completed++;
        }

        // 2️⃣ التحقق من userTasks (المهمة الإضافية)
        final bonusSnapshot = await FirebaseFirestore.instance
            .collection('userTasks')
            .doc(bonusKey)
            .get(GetOptions(source: Source.server));

        if (bonusSnapshot.exists) {
          final status = bonusSnapshot.data()?['status'] as String?;
          print('📄 Bonus userTask status (server): $status');
          if (status == 'completed') completed++;
        }

        // 🔥🔥🔥 التصحيح هنا 🔥🔥🔥
        // 3️⃣ التحقق من dailyTasks - استخدام completed بدلاً من status
        final dailySnapshot = await FirebaseFirestore.instance
            .collection('dailyTasks')
            .doc(_uid)
            .collection('tasks')
            .doc(dailyTaskDate)
            .get(GetOptions(source: Source.server));

        if (dailySnapshot.exists) {
          // dailyTasks تستخدم حقل 'completed' (boolean) وليس 'status'
          final isCompleted = dailySnapshot.data()?['completed'] == true;
          print('📄 Daily task completed: $isCompleted');
          if (isCompleted) completed++;
        }
      } catch (e) {
        print('❌ Error calculating tasks: $e');
      }

      return completed;
    }

    // 🔥 راقب التغييرات في المهمة الرئيسية
    FirebaseFirestore.instance
        .collection('userTasks')
        .doc(dayKey)
        .snapshots(includeMetadataChanges: true)
        .listen((_) async {
          if (!mounted) return;
          int completed = await _calculateCompletedTasks();
          updateCount++;
          setState(() => _completedTasksToday = completed);
          print(
            '✅ Progress update #$updateCount (from main): $completed/$_requiredTasksToday',
          );
        });

    // 🔥 راقب التغييرات في المهمة الإضافية
    FirebaseFirestore.instance
        .collection('userTasks')
        .doc(bonusKey)
        .snapshots(includeMetadataChanges: true)
        .listen((_) async {
          if (!mounted) return;
          int completed = await _calculateCompletedTasks();
          updateCount++;
          setState(() => _completedTasksToday = completed);
          print(
            '✅ Progress update #$updateCount (from bonus): $completed/$_requiredTasksToday',
          );
        });

    // 🔥 راقب التغييرات في dailyTasks
    FirebaseFirestore.instance
        .collection('dailyTasks')
        .doc(_uid)
        .collection('tasks')
        .doc(dailyTaskDate)
        .snapshots(includeMetadataChanges: true)
        .listen((snapshot) async {
          if (!mounted) return;

          // نجيب القيمة المحدثة مباشرة
          int completed = 0;

          // تحقق من userTasks
          final mainSnap = await FirebaseFirestore.instance
              .collection('userTasks')
              .doc(dayKey)
              .get(GetOptions(source: Source.server));
          if (mainSnap.exists && mainSnap.data()?['status'] == 'completed') {
            completed++;
          }

          final bonusSnap = await FirebaseFirestore.instance
              .collection('userTasks')
              .doc(bonusKey)
              .get(GetOptions(source: Source.server));
          if (bonusSnap.exists && bonusSnap.data()?['status'] == 'completed') {
            completed++;
          }

          // 🔥 تحقق من dailyTasks باستخدام completed
          if (snapshot.exists && snapshot.data()?['completed'] == true) {
            completed++;
          }

          updateCount++;
          setState(() => _completedTasksToday = completed);
          print(
            '✅ Progress update #$updateCount (from daily): $completed/$_requiredTasksToday',
          );
        });
  }

  Future<void> _loadUserProgress() async {
    if (_uid == null || _selectedDay == null) return;

    setState(() => _isLoadingProgress = true);

    try {
      // جلب مستوى المستخدم من users collection
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(_uid)
          .get();

      _userLevel = userDoc.data()?['userLevel'] ?? 'beginner';
      _userLevelName = _getLevelName(_userLevel!);
      _requiredTasksToday = _getRequiredTasksPerDay(_userLevel!);

      // جلب المهام المكتملة لليوم المحدد - استخدم get مباشرة
      _completedTasksToday = await _getCompletedTasksForDay(
        _uid!,
        _selectedDay!,
      );

      print(
        '📊 User progress loaded - Level: $_userLevel, Completed: $_completedTasksToday/$_requiredTasksToday',
      );

      // بدء مراقبة التغييرات
      _watchUserProgress();
    } catch (e) {
      debugPrint('❌ Error loading progress: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoadingProgress = false);
      }
    }
  }

  DateTime _monthStart(DateTime d) => DateTime(d.year, d.month, 1);
  DateTime _monthEnd(DateTime d) => DateTime(d.year, d.month + 1, 0);

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
    _loadUserProgress();
  }

  @override
  void dispose() {
    _userTasksSubscription?.cancel();
    super.dispose();
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
      await _loadScheduledDaysForMonth(_selectedDay!);

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
    final today = _dayStart(DateTime.now());

    // ❌ منع تحديث المهام للأيام الماضية
    if (!selected.isAtSameMomentAs(today)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'يمكنك تغيير مهمة اليوم الحالي فقط',
              style: GoogleFonts.ibmPlexSansArabic(color: Colors.white),
            ),
            backgroundColor: AppColors.primary,
          ),
        );
      }
      return;
    }

    final monthKey =
        "${selected.year}-${selected.month.toString().padLeft(2, '0')}";
    final utKey = '${_uid!}_${_yyyyMMdd(selected)}';
    final utRef = FirebaseFirestore.instance.collection('userTasks').doc(utKey);

    try {
      await utRef.update({
        'ignored': true,
        'ignoredAt': FieldValue.serverTimestamp(),
        'status': 'ignored', // غيري الحالة عشان تختفي من الشاشة
      });
      print('✅ تم تسجيل المهمة كمتجاهلة (تحديث)');
    } catch (e) {
      print('⚠️ فشل تسجيل التجاهل: $e');
      // نكمل عادي حتى لو فشل
    }

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

    //     1) إذا ما فيه مقال جديد فعليًا → hasFreshNews = false → ما تنعرض مهمة القراءة إطلاقًا

    // حتى لو راح للـ API وما لقى شيء جديد.

    // 2) حتى لو فيه مقال جديد → تظهر مهمة القراءة فقط بنسبة 20% من المرات

    // 3) ما عاد يضيف مهمة القراءة دايمًا إلى قائمة المهام

    // فما فيه تكرار ولا ظهور "قراءة خبر" بشكل مزعج.

    // 4) الـ API الآن لن يسبب ظهور مهمة خبر إلا إذا فعلاً أعطى مقال جديد لم يظهر من قبل.

    // نضيف مهمة الخبر فقط بنسبة 20٪ مثلاً
    final shouldOfferNewsTask = hasFreshNews && Random().nextDouble() < 0.2;

    if (shouldOfferNewsTask) {
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

        'ignored': false,
        'ignoredAt': null,
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
      //'windowStart': Timestamp.fromDate(start),
      //'windowEnd': Timestamp.fromDate(end),
      'taskTitle': pickedData['title'] ?? '(بدون عنوان)',
      'taskDescription': pickedData['description'] ?? '',
      'taskPoints': pickedData['points'] ?? 0,
      'taskValidation':
          pickedData['validationStrategy'] ??
          pickedData['validation'] ??
          pickedData['taskValidation'] ??
          'غير محددة',

      'ignored': false,
      'ignoredAt': null,
    });
  }

  // -------------------------------------------------------------
  // 1) اختيار مهمة إضافية عشوائية (مختلفة عن مهمة اليوم)
  // -------------------------------------------------------------
  Future<Map<String, dynamic>?> _suggestBonusTask() async {
    if (_uid == null) return null;

    try {
      // ✅ جلب آخر موقع معروف من Firestore
      GeoPoint? lastLocation;
      try {
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(_uid)
            .get();

        if (userDoc.exists &&
            userDoc.data()?.containsKey('lastLocation') == true) {
          lastLocation = userDoc.data()!['lastLocation'] as GeoPoint?;
          print('📍 Using last known location: $lastLocation');
        }
      } catch (e) {
        print('⚠️ Could not fetch location: $e');
      }

      final callable = FirebaseFunctions.instance.httpsCallable(
        'suggestBonusTask',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 30)),
      );

      // ✅ إرسال الموقع إذا كان موجوداً
      final Map<String, dynamic> data = {
        'pressedAt': DateTime.now().toIso8601String(),
      };

      if (lastLocation != null) {
        data['userLocation'] = {
          'latitude': lastLocation.latitude,
          'longitude': lastLocation.longitude,
        };
      }

      final result = await callable.call(data);

      // ✅ النتيجة تحتوي على taskId فقط أو بيانات كاملة؟
      // إذا كانت تحتوي على taskId فقط، نحتاج لجلب بيانات المهمة
      final Map<String, dynamic> response = Map<String, dynamic>.from(
        result.data as Map,
      );

      if (response.containsKey('taskId')) {
        // جلب بيانات المهمة كاملة من Firestore
        final taskDoc = await FirebaseFirestore.instance
            .collection('tasks')
            .doc(response['taskId'])
            .get();

        if (taskDoc.exists) {
          return {'id': taskDoc.id, ...taskDoc.data()!};
        }
      }

      return response;
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'not-found' && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'لا توجد مهام إضافية متاحة الآن.',
              style: GoogleFonts.ibmPlexSansArabic(color: Colors.white),
            ),
            backgroundColor: AppColors.primary,
          ),
        );
      }
      return null;
    } catch (e) {
      print('❌ Error in _suggestBonusTask: $e');
      return null;
    }
  }

  // -------------------------------------------------------------
  // 2) حفظ المهمة الإضافية وفتح شيت الإتمام
  // -------------------------------------------------------------
  Future<void> _saveBonusTaskAndOpen(Map<String, dynamic> bonusTask) async {
    if (_uid == null || _selectedDay == null) return;

    final sel = _dayStart(_selectedDay!);
    final bonusDocId = '${_uid!}_${_yyyyMMdd(sel)}_bonus';

    final today = _dayStart(DateTime.now());

    // ❌ منع حفظ المهام الإضافية للأيام الماضية
    if (!sel.isAtSameMomentAs(today)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'يمكنك إضافة مهام إضافية لليوم الحالي فقط',
              style: GoogleFonts.ibmPlexSansArabic(color: Colors.white),
            ),
            backgroundColor: AppColors.primary,
          ),
        );
      }
      return;
    }
    if (!mounted) return;

    // ✅ التحقق من نوع المهمة
    final validationStrategy =
        bonusTask['validationStrategy']?.toString() ?? '';

    if (validationStrategy == "التحقق عبر اجراء اختبار قصير") {
      // 📖 مهمة قراءة مقال - نفتح ArticlePage
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ArticlePage(
            userTaskDocId: bonusDocId,
            taskId: bonusTask['taskId'] ?? bonusTask['id'],
          ),
        ),
      );
    } else {
      // 📸 مهمة تصوير - نفتح CompleteTaskSheet
      final result = await showCompleteTaskSheet(
        context,
        bonusTask,
        selectedDay: sel,
        userTaskDocId: bonusDocId,
      );

      // ✅ لو أكمل المهمة (result == true) → نحفظ في Firestore
      if (result == true && mounted) {
        final start = _dayStart(sel);
        final end = _dayEnd(sel);

        final utRef = FirebaseFirestore.instance
            .collection('userTasks')
            .doc(bonusDocId);

        final dailyTaskRef = FirebaseFirestore.instance
            .collection('dailyTasks')
            .doc(_uid!)
            .collection('tasks')
            .doc('${_yyyyMMdd(sel)}_bonus');

        await utRef.set({
          'userId': _uid,
          'taskId': bonusTask['taskId'] ?? bonusTask['id'],
          'taskTitle': bonusTask['title'] ?? '(بدون عنوان)',
          'taskDescription': bonusTask['description'] ?? '',
          'taskPoints': bonusTask['points'] ?? 0,
          'taskValidation': bonusTask['validationStrategy'] ?? 'غير محددة',
          'selectedAt': Timestamp.fromDate(start),
          'windowStart': Timestamp.fromDate(start),
          'windowEnd': Timestamp.fromDate(end),
          'status': 'completed',
          'completedAt': FieldValue.serverTimestamp(),
          'isExtra': true,
          'ignored': false,
          'ignoredAt': null,
        }, SetOptions(merge: true));

        await StreakService.updateStreakOnTaskCompletion();

        await dailyTaskRef.set({
          'userId': _uid,
          'taskId': bonusTask['taskId'] ?? bonusTask['id'],
          'title': bonusTask['title'] ?? '(بدون عنوان)',
          'description': bonusTask['description'] ?? '',
          'category': bonusTask['category'] ?? '',
          'estimatedCarbonSaving': bonusTask['estimatedCarbonSaving'] ?? 0,
          'type': bonusTask['type'] ?? 'ecoAction',
          'isExtra': true,
          'completed': true,
          'createdAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        // تحديث البروقريس
        await _loadUserProgress();

        // أخفي كرت الاقتراح
        setState(() => _suggestedBonusTask = null);
      }
    }
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

  // bool _isWithinDayWindow(DateTime day, DateTime now) {
  //   return now.isAfter(_dayStart(day).subtract(const Duration(seconds: 1))) &&
  //       now.isBefore(_dayEnd(day).add(const Duration(seconds: 1)));
  // }

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
                    Row(
                      children: [
                        // 🟢 عنوان مهامي (يبقى على اليمين)
                        Text(
                          'مهامي',
                          style: GoogleFonts.ibmPlexSansArabic(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            color: AppColors.dark,
                          ),
                        ),

                        // ⬅️ هذا السطر هو المفتاح
                        const Spacer(),

                        // 🟢 زر الجدولة (ينتقل لليسار)
                        InkWell(
                          borderRadius: BorderRadius.circular(999),
                          onTap: () =>
                              setState(() => _scheduleMode = !_scheduleMode),

                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: AppColors.primary,
                                width: 1.5,
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.calendar_month,
                                  color: AppColors.primary,
                                  size: 22,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'جدولة',
                                  style: GoogleFonts.ibmPlexSansArabic(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.primary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),

                    _buildGrowthIndicator(
                      levelName: 'بذرة',
                      level: 1,
                      tasksPerDay: 1,
                      progressToNext: 0.45,
                    ),

                    const SizedBox(height: 15),

                    // ✅ هنا حطي كود رسالة وضع الجدولة
                    if (_scheduleMode) ...[
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(top: 10, bottom: 12),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.10),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: AppColors.primary,
                            width: 1.2,
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.info_outline,
                              color: AppColors.primary,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'تم تفعيل وضع الجدولة: الرجاء اختيار يوم يناسبك من التقويم👇',
                                style: GoogleFonts.ibmPlexSansArabic(
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.dark,
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: () =>
                                  setState(() => _scheduleMode = false),
                              child: Text(
                                'إلغاء',
                                style: GoogleFonts.ibmPlexSansArabic(
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.primary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    _buildCalendar(),
                    const SizedBox(height: 8),
                    // ✅ البروقريس بار هنا - فوق كرت المهمة
                    if (!_scheduleMode &&
                        _selectedDay != null &&
                        _uid != null) ...[
                      _isLoadingProgress
                          ? const Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 20,
                              ),
                              child: Center(
                                child: CircularProgressIndicator(
                                  color: AppColors.primary,
                                ),
                              ),
                            )
                          : DailyProgressBar(
                              completed: _completedTasksToday,
                              required: _requiredTasksToday,
                            ),
                    ],

                    if (!_scheduleMode) ...[
                      Builder(
                        builder: (context) {
                          if (!_precheckDone) {
                            return const Center(
                              child: Padding(
                                padding: EdgeInsets.symmetric(vertical: 40),
                                child: CircularProgressIndicator(
                                  color: AppColors.primary,
                                ),
                              ),
                            );
                          }

                          if (_precheckError != null) {
                            return _buildUnavailableCard(
                              title: 'تعذّر تحميل مهمة اليوم',
                              subtitle: (_precheckError == 'permission-denied')
                                  ? 'صلاحيات غير كافية لقراءة مهامك. تأكدي أنك مسجّلة دخولًا وأن قواعد Firestore تسمح لصاحب الوثيقة بالقراءة.'
                                  : (_precheckError!.contains('unavailable') ||
                                        _precheckError!.contains('network'))
                                  ? 'مشكلة اتصال مؤقتة. تحقّقي من الإنترنت ثم جرّبي التحديث.'
                                  : 'خطأ: $_precheckError',
                            );
                          }

                          if (_userTaskStream == null) {
                            return const Center(
                              child: Padding(
                                padding: EdgeInsets.symmetric(vertical: 40),
                                child: CircularProgressIndicator(
                                  color: AppColors.primary,
                                ),
                              ),
                            );
                          }

                          return StreamBuilder<DocumentSnapshot>(
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

                              final data = <String, dynamic>{
                                'taskId': ut['taskId'] ?? '',
                                'title': ut['taskTitle'] ?? '(بدون عنوان)',
                                'description': ut['taskDescription'] ?? '',
                                'points': ut['taskPoints'] ?? 0,
                                'validationStrategy':
                                    ut['taskValidation'] ?? 'غير محددة',
                                'id': ut['taskId'] ?? '',
                                'status': ut['status'] ?? 'pending',
                              };

                              final canPerformDay = sel.isAtSameMomentAs(today);

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
                          );
                        },
                      ),
                    ],
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

              const SizedBox(width: 6),

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
            enabledDayPredicate: (day) {
              if (!_scheduleMode) return true;

              final today = _dayStart(DateTime.now());
              final d = _dayStart(day);

              // بداية الشهر القادم = “الشهر الجاي ما انفتح”
              final nextMonthStart = DateTime(today.year, today.month + 1, 1);

              // وضع الجدولة: فقط الأيام القادمة داخل الشهر الحالي
              return d.isAfter(today) && d.isBefore(nextMonthStart);
            },

            onPageChanged: (focused) {
              _focusedDay = focused;
              // ✅ تحميل الشهر المعروض فقط
              _loadMonth(focused);
              _loadScheduledDaysForMonth(focused);
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

              final sel = _dayStart(selected);
              final today = _dayStart(DateTime.now());

              // 2) لو وضع الجدولة شغال واختار يوم مستقبلي
              if (_scheduleMode && sel.isAfter(today)) {
                // ✅ 1) نفحص هل فيه جدولة مسبقاً لهذا اليوم
                final startOfDay = DateTime(sel.year, sel.month, sel.day);
                final endOfDay = startOfDay
                    .add(const Duration(days: 1))
                    .subtract(const Duration(seconds: 1));

                final existing = await FirebaseFirestore.instance
                    .collection('scheduledTasks')
                    .where('userId', isEqualTo: _uid)
                    .where('status', isEqualTo: 'scheduled')
                    .where(
                      'scheduledFor',
                      isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay),
                    )
                    .where(
                      'scheduledFor',
                      isLessThanOrEqualTo: Timestamp.fromDate(endOfDay),
                    )
                    .limit(1)
                    .get();

                // ✅ 2) إذا ما فيه جدولة → افتح اختيار المهمة مباشرة بدون رسالة
                if (existing.docs.isEmpty) {
                  _openScheduleTaskPicker(sel);
                  return;
                }

                // ✅ 3) إذا فيه جدولة → اعرض رسالة الاستبدال
                final proceed = await showDialog<bool>(
                  context: context,
                  builder: (_) => Dialog(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 18,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'تنبيه',
                            style: GoogleFonts.ibmPlexSansArabic(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: AppColors.dark,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'يوجد بالفعل مهمة مجدولة لهذا اليوم.\n'
                            'المتابعة ستؤدي إلى استبدال المهمة الحالية. هل ترغب بالاستمرار؟',
                            style: GoogleFonts.ibmPlexSansArabic(
                              fontSize: 14.5,
                              height: 1.6,
                              color: Colors.grey.shade800,
                            ),
                          ),
                          const SizedBox(height: 18),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: Text(
                                  'إلغاء',
                                  style: GoogleFonts.ibmPlexSansArabic(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.grey.shade700,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton(
                                onPressed: () => Navigator.pop(context, true),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.primary,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 20,
                                    vertical: 10,
                                  ),
                                  elevation: 0,
                                ),
                                child: Text(
                                  'المتابعة',
                                  style: GoogleFonts.ibmPlexSansArabic(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );

                if (proceed == true) {
                  _openScheduleTaskPicker(sel);
                }
                return;
              }

              // ✅ منطقك الحالي لليوم والماضي
              await _ensureUserTaskForDate(sel);
              _userTasksSubscription?.cancel();
              await _loadUserProgress();
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
              disabledBuilder: (context, day, focusedDay) {
                return Center(
                  child: Text(
                    '${day.day}',
                    style: GoogleFonts.ibmPlexSansArabic(
                      color: Colors.grey.shade400,
                      fontWeight: FontWeight.w600,
                      fontSize: 13.5,
                    ),
                  ),
                );
              },

              // ✅ الأيام العادية
              defaultBuilder: (context, day, focusedDay) {
                return _buildDayCell(day);
              },

              selectedBuilder: (context, day, focusedDay) {
                return _buildDayCell(day, forceSelected: true);
              },

              todayBuilder: (context, day, focusedDay) {
                final isSel = isSameDay(day, _selectedDay);
                return _buildDayCell(
                  day,
                  forceSelected: isSel,
                  isTodayOverride: true,
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
    final today = _dayStart(DateTime.now());

    // final taskType = (taskData['taskType'] ?? '').toString();
    // final articleContent = (taskData['articleContent'] ?? '').toString().trim();

    // 🔴 لو هي مهمة "خبر" لكن المقال فاضي → لا تعرض مهمة، اعرض كرت "لا توجد مهمة"
    // if (taskType == 'news' && articleContent.isEmpty) {
    //   return _buildUnavailableCard(
    //     title: 'لا توجد مهمة لهذا اليوم',
    //     subtitle: 'خبر هذا اليوم لم يعد متوفرًا، وسيتم استبداله لاحقًا.',
    //   );
    // }
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
                                    : (sel.isBefore(today)
                                          ? 'انتهى موعد المهمة '
                                          : 'يومها لم يحن بعد'))),
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
          // ✅ أضيفي هذا هنا
          if (isCompleted) ...[
            const SizedBox(height: 16),
            _buildBonusTaskSection(),
          ],
        ],
      ),
    );
  }
  // =====================================================================
  // ✅ الدوال الجديدة — أضيفيها بعد _buildUserTaskCard
  // =====================================================================

  Widget _buildBonusTaskSection() {
    final sel = _dayStart(_selectedDay ?? DateTime.now());
    final bonusDocId = '${_uid ?? ''}_${_yyyyMMdd(sel)}_bonus';
    final today = _dayStart(DateTime.now());

    //  منع ظهور المهام الإضافية للأيام الماضية
    if (!sel.isAtSameMomentAs(today)) {
      return const SizedBox.shrink();
    }

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('userTasks')
          .doc(bonusDocId)
          .snapshots(),
      builder: (context, snap) {
        // المهمة الإضافية موجودة في Firestore
        if (snap.hasData && snap.data!.exists) {
          final bonusData = snap.data!.data() as Map<String, dynamic>;
          final bonusStatus = bonusData['status'] as String? ?? 'pending';

          if (bonusStatus == 'completed') {
            return Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.primary33,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.primary, width: 1.2),
              ),
              child: Row(
                children: [
                  const Icon(Icons.star, color: AppColors.primary, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'أحسنت! أكملتِ المهمة الإضافية اليوم 🌱',
                      style: GoogleFonts.ibmPlexSansArabic(
                        fontWeight: FontWeight.w700,
                        color: AppColors.dark,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }

          // المهمة موجودة لكن لم تكتمل بعد
          return _buildActiveBonusCard(bonusData, bonusDocId, bonusStatus);
        }

        // لا توجد مهمة إضافية في Firestore بعد
        // لو عندنا مهمة مقترحة في الذاكرة — اعرضها
        if (_suggestedBonusTask != null) {
          return _buildProposedBonusCard(
            task: _suggestedBonusTask!,
            onAccept: () => _saveBonusTaskAndOpen(_suggestedBonusTask!),
            onReject: () =>
                setState(() => _suggestedBonusTask = null), // ← يرجع للزر
            onAlternative: () async {
              setState(() => _bonusLoading = true);
              final next = await _suggestBonusTask();
              if (mounted && next != null) {
                setState(() {
                  _suggestedBonusTask = next;
                  _bonusLoading = false;
                });
              } else if (mounted) {
                setState(() => _bonusLoading = false);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'لا توجد مهام بديلة متاحة',
                      style: GoogleFonts.ibmPlexSansArabic(color: Colors.white),
                    ),
                    backgroundColor: AppColors.primary,
                  ),
                );
              }
            },
            isLoading: _bonusLoading,
          );
        }

        // الحالة الافتراضية — زر "اقتراح مهمة إضافية"
        return _bonusLoading
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(
                  child: CircularProgressIndicator(color: AppColors.primary),
                ),
              )
            : SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.add_task, color: AppColors.primary),
                  label: Text(
                    'اقتراح مهمة إضافية ✨',
                    style: GoogleFonts.ibmPlexSansArabic(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: AppColors.primary,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(
                      color: AppColors.primary,
                      width: 1.5,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: () async {
                    setState(() => _bonusLoading = true);
                    final task = await _suggestBonusTask();
                    if (mounted)
                      setState(() {
                        _suggestedBonusTask = task;
                        _bonusLoading = false;
                      });
                  },
                ),
              );
      },
    );
  }

  Widget _buildProposedBonusCard({
    required Map<String, dynamic> task,
    required VoidCallback onAccept,
    required VoidCallback onReject,
    required VoidCallback onAlternative,
    bool isLoading = false,
  }) {
    final title = task['title'] ?? '(بدون عنوان)';
    final description = task['description'] ?? '';
    final points = task['points'] ?? 0;

    // ✅ إظهار معلومات الموقع إذا كانت موجودة
    final bool hasLocation =
        task['location'] != null ||
        (task['latitude'] != null && task['longitude'] != null);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.accent, width: 1.5),
        boxShadow: const [
          BoxShadow(
            color: Color(0x18000000),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome, color: AppColors.accent, size: 20),
              const SizedBox(width: 8),
              Text(
                'مهمة إضافية مقترحة ✨',
                style: GoogleFonts.ibmPlexSansArabic(
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                  color: AppColors.accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            title,
            style: GoogleFonts.ibmPlexSansArabic(
              fontWeight: FontWeight.w700,
              fontSize: 15,
              color: AppColors.dark,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            description,
            style: GoogleFonts.ibmPlexSansArabic(
              fontSize: 13.5,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 8),

          // ✅ إظهار الموقع إذا كان موجوداً
          if (hasLocation) ...[
            Row(
              children: [
                Icon(Icons.location_on, size: 14, color: AppColors.primary),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    task['location'] ?? 'موقع قريب منك',
                    style: GoogleFonts.ibmPlexSansArabic(
                      fontSize: 12,
                      color: AppColors.primary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
          ],

          Row(
            children: [
              const Icon(Icons.star_border, color: AppColors.primary, size: 18),
              const SizedBox(width: 4),
              Text(
                '$points نقطة',
                style: GoogleFonts.ibmPlexSansArabic(
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          if (isLoading)
            const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            )
          else
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: onReject,
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: Colors.grey.shade400),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    child: Text(
                      'لا شكراً',
                      style: GoogleFonts.ibmPlexSansArabic(
                        fontWeight: FontWeight.w700,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: onAlternative,
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.primary),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    child: Text(
                      'بديل 🔄',
                      style: GoogleFonts.ibmPlexSansArabic(
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: onAccept,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      elevation: 0,
                    ),
                    child: Text(
                      'قبول ✅',
                      style: GoogleFonts.ibmPlexSansArabic(
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildActiveBonusCard(
    Map<String, dynamic> bonusData,
    String bonusDocId,
    String status,
  ) {
    final sel = _dayStart(_selectedDay ?? DateTime.now());
    final title = bonusData['taskTitle'] ?? '(بدون عنوان)';
    final description = bonusData['taskDescription'] ?? '';
    final points = bonusData['taskPoints'] ?? 0;
    final validation = bonusData['taskValidation'] ?? 'غير محددة';
    final isSubmitted = status == 'submitted';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.accent, width: 1.5),
        boxShadow: const [
          BoxShadow(
            color: Color(0x18000000),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome, color: AppColors.accent, size: 20),
              const SizedBox(width: 8),
              Text(
                'مهمتك الإضافية ✨',
                style: GoogleFonts.ibmPlexSansArabic(
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                  color: AppColors.accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            title,
            style: GoogleFonts.ibmPlexSansArabic(
              fontWeight: FontWeight.w700,
              fontSize: 15,
              color: AppColors.dark,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            description,
            style: GoogleFonts.ibmPlexSansArabic(
              fontSize: 13.5,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.star_border, color: AppColors.primary, size: 18),
              const SizedBox(width: 4),
              Text(
                '$points نقطة',
                style: GoogleFonts.ibmPlexSansArabic(
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                  fontSize: 13,
                ),
              ),
              const Spacer(),
              Text(
                validation,
                style: GoogleFonts.ibmPlexSansArabic(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: isSubmitted
                  ? null
                  : () async {
                      final taskId = bonusData['taskId'] as String?;
                      final fullTask = {
                        ...bonusData,
                        'title': title,
                        'description': description,
                        'points': points,
                        'validationStrategy': validation,
                        'id': taskId,
                        'taskId': taskId,
                        'status': status,
                      };

                      final result = await showCompleteTaskSheet(
                        context,
                        fullTask,
                        selectedDay: sel,
                        userTaskDocId: bonusDocId,
                      );
                      await _loadUserProgress();
                      if (result == true && mounted) setState(() {});
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: isSubmitted
                    ? Colors.grey.shade300
                    : AppColors.primary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: Text(
                isSubmitted ? 'بانتظار المراجعة ⏳' : 'بدء المهمة الإضافية',
                style: GoogleFonts.ibmPlexSansArabic(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: isSubmitted ? AppColors.dark : Colors.white,
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

// ====================================================
// DailyProgressBar Widget
// ====================================================
class DailyProgressBar extends StatelessWidget {
  final int completed;
  final int required;

  const DailyProgressBar({
    super.key,
    required this.completed,
    required this.required,
  });

  @override
  Widget build(BuildContext context) {
    final progress = completed / required;
    final isComplete = completed >= required;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isComplete ? Icons.check_circle : Icons.eco,
                color: isComplete ? Colors.green : AppColors.primary,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'تقدمك اليوم',
                style: GoogleFonts.ibmPlexSansArabic(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.dark,
                ),
              ),
              const Spacer(),
              Text(
                '$completed / $required مهام',
                style: GoogleFonts.ibmPlexSansArabic(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isComplete ? Colors.green : AppColors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              backgroundColor: Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation<Color>(
                isComplete ? Colors.green : AppColors.primary,
              ),
              minHeight: 8,
            ),
          ),
          if (isComplete) ...[
            const SizedBox(height: 8),
            Text(
              '🎉 أحسنت! أكملت كل مهام اليوم',
              style: GoogleFonts.ibmPlexSansArabic(
                fontSize: 13,
                color: Colors.green,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
