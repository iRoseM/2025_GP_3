import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:table_calendar/table_calendar.dart';
import 'background_container.dart';
import 'dart:math';

// Navigation pages
import 'home.dart';
import 'map.dart';
import 'levels.dart';
import 'community.dart';

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
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  @override
  Widget build(BuildContext context) {
    final isKeyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;
    final baseTheme = Theme.of(context);
    final textTheme = GoogleFonts.ibmPlexSansArabicTextTheme(baseTheme.textTheme);

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

          // =============== BODY ===============
          body: AnimatedBackgroundContainer(
            child: Column(
              children: [
                const SizedBox(height: 12),

                // 🔹 Calendar Section
                _buildCalendar(),

                const SizedBox(height: 8),

                // 🔹 Task Stream
                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('tasks')
                        .where('isActive', isEqualTo: true)
                        .snapshots(),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState == ConnectionState.waiting) {
                            return const Center(
                              child: CircularProgressIndicator(color: AppColors.primary),
                            );
                          }

                          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                            return const Center(
                              child: Text(
                                'لا توجد مهام متاحة اليوم 🌱',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey,
                                ),
                              ),
                            );
                          }

                          final docs = snapshot.data!.docs;

                          // ✅ Get today's date boundaries
                          final now = DateTime.now();
                          final todayStart = DateTime(now.year, now.month, now.day);
                          final todayEnd = todayStart.add(const Duration(days: 1));

                          // ✅ Filter: keep only active and valid (unexpired or no expiry)
                          final validTasks = docs.where((doc) {
                            final data = doc.data() as Map<String, dynamic>;
                            final expiry = (data['expiryDate'] as Timestamp?)?.toDate();
                            final isActive = data['isActive'] == true;
                            return isActive && (expiry == null || expiry.isAfter(todayStart));
                          }).toList();

                          if (validTasks.isEmpty) {
                            return const Center(
                              child: Text(
                                'لا توجد مهمة متاحة لهذا اليوم ⏳',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey,
                                ),
                              ),
                            );
                          }

                          // ✅ Daily shuffle logic — consistent per day
                          final seed = now.year * 10000 + now.month * 100 + now.day;
                          validTasks.shuffle(Random(seed));

                          // ✅ Pick one task per day (changes daily)
                          final task = validTasks.first;

                          // ✅ Determine if selected date is today
                          final isToday = _selectedDay == null
                              ? true
                              : _selectedDay!.year == now.year &&
                                  _selectedDay!.month == now.month &&
                                  _selectedDay!.day == now.day;

                          return Column(
                            children: [
                              _buildTodayTaskCard(task, isToday),
                              if (!isToday)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(
                                    'يمكنك تنفيذ المهام اليومية فقط في يومها المحدد ⏳',
                                    style: GoogleFonts.ibmPlexSansArabic(
                                      fontSize: 13,
                                      color: Colors.grey.shade600,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                            ],
                          );
                        },

                  ),
                ),

              ],
            ),
          ),

          // =============== Bottom Navigation ===============
          bottomNavigationBar: isKeyboardOpen
              ? null
              : BottomNav(
                  currentIndex: 1,
                  onTap: (i) {
                    if (i == 1) return;
                    switch (i) {
                      case 0:
                        Navigator.of(context).pushAndRemoveUntil(
                          MaterialPageRoute(builder: (_) => const homePage()),
                          (route) => false,
                        );
                        break;
                      case 3:
                        Navigator.of(context).pushReplacement(
                          MaterialPageRoute(builder: (_) => const mapPage()),
                        );
                        break;
                      case 4:
                        Navigator.of(context).pushReplacement(
                          MaterialPageRoute(
                              builder: (_) => const communityPage()),
                        );
                        break;
                    }
                  },
                  onCenterTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const levelsPage()),
                    );
                  },
                ),
        ),
      ),
    );
  }

  // ============================================================
  // 🔹 Calendar Widget
  Widget _buildCalendar() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFF4BAA98), // start
            Color(0xFF6BBAA2), // middle
            Color(0xFFAFDBB8), // end
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
          // locale: 'ar',
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
            leftChevronIcon:
                const Icon(Icons.chevron_left, color: Colors.white),
            rightChevronIcon:
                const Icon(Icons.chevron_right, color: Colors.white),
          ),
          daysOfWeekStyle: DaysOfWeekStyle(
            weekdayStyle:
                GoogleFonts.ibmPlexSansArabic(color: Colors.white70),
            weekendStyle:
                GoogleFonts.ibmPlexSansArabic(color: Colors.white70),
          ),
          calendarStyle: CalendarStyle(
            defaultTextStyle:
                GoogleFonts.ibmPlexSansArabic(color: Colors.white),
            weekendTextStyle:
                GoogleFonts.ibmPlexSansArabic(color: Colors.white70),
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
          onDaySelected: (selected, focused) {
            setState(() {
              _selectedDay = selected;
              _focusedDay = focused;
            });
          },
        ),
      ),
    );
  }

  // ============================================================
  // 🔹 Daily Task Card
  Widget _buildTodayTaskCard(QueryDocumentSnapshot task, bool isToday) {
    final data = task.data() as Map<String, dynamic>;

    final title = data['title'] ?? 'مهمة غير محددة';
    final description = data['description'] ?? 'لا يوجد وصف متاح.';
    final points = data['points'] ?? 0;
    final validation = data['validationStrategy'] ?? 'غير محددة';

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
            "مهمة اليوم",
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
              Icon(Icons.star_border, color: AppColors.primary, size: 20),
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
              onTap: isToday
                  ? () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'بدأت المهمة ✅',
                            style: GoogleFonts.ibmPlexSansArabic(
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                          backgroundColor: AppColors.primary,
                        ),
                      );
                    }
                  : null, // 🔹 Disable tap if not today
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  gradient: isToday
                      ? const LinearGradient(
                          colors: [AppColors.primary, AppColors.mint],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        )
                      : LinearGradient(
                          colors: [Colors.grey.shade400, Colors.grey.shade300],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        ),
                  boxShadow: [
                    if (isToday)
                      const BoxShadow(
                        color: Color(0x33000000),
                        blurRadius: 8,
                        offset: Offset(0, 4),
                      ),
                  ],
                ),
                alignment: Alignment.center,
                child: Text(
                  isToday ? "ابدأ المهمة" : "غير متاحة الآن",
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

/* ======================= BottomNav (same structure) ======================= */
class NavItem {
  final IconData outlined;
  final IconData filled;
  final String label;
  final bool isCenter;
  const NavItem({
    required this.outlined,
    required this.filled,
    required this.label,
    this.isCenter = false,
  });
}

class BottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final VoidCallback onCenterTap;

  const BottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.onCenterTap,
  });

  @override
  Widget build(BuildContext context) {
    final items = const [
      NavItem(
        outlined: Icons.home_outlined,
        filled: Icons.home,
        label: 'الرئيسية',
      ),
      NavItem(
        outlined: Icons.fact_check_outlined,
        filled: Icons.fact_check,
        label: 'مهامي',
      ),
      NavItem(
        outlined: Icons.flag_outlined,
        filled: Icons.flag,
        label: 'المراحل',
        isCenter: true,
      ),
      NavItem(
        outlined: Icons.map_outlined,
        filled: Icons.map,
        label: 'الخريطة',
      ),
      NavItem(
        outlined: Icons.group_outlined,
        filled: Icons.group,
        label: 'الأصدقاء',
      ),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: Container(
          height: 70,
          color: Colors.white,
          child: Row(
            children: List.generate(items.length, (i) {
              final it = items[i];
              final selected = i == currentIndex;

              if (it.isCenter) {
                return Expanded(
                  child: Center(
                    child: InkResponse(
                      onTap: onCenterTap,
                      radius: 40,
                      child: Container(
                        width: 58,
                        height: 58,
                        decoration: const BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Color(0x22000000),
                              blurRadius: 12,
                              offset: Offset(0, 6),
                            ),
                          ],
                        ),
                        child: const Icon(Icons.flag_outlined,
                            color: Colors.white, size: 28),
                      ),
                    ),
                  ),
                );
              }

              final iconData = selected ? it.filled : it.outlined;
              final color = selected ? AppColors.primary : Colors.black54;

              return Expanded(
                child: InkWell(
                  onTap: () => onTap(i),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(iconData, color: color, size: 26),
                      const SizedBox(height: 2),
                      Text(
                        it.label,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight:
                              selected ? FontWeight.w800 : FontWeight.w500,
                          color: color,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}
