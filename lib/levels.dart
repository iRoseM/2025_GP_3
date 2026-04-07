import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'home.dart';
import 'task.dart';
import 'map.dart';
import 'community.dart';
import 'services/bottom_nav.dart';
import 'services/title_header.dart';
import '../services/app_colors.dart';
import 'services/xp_service.dart'; 

class levelsPage extends StatefulWidget {
  const levelsPage({super.key});

  @override
  State<levelsPage> createState() => _levelsPageState();
}

class _levelsPageState extends State<levelsPage> {
  final int _currentIndex = 2;

  void _onTap(int i) {
    if (i == _currentIndex) return;
    switch (i) {
      case 0:
        Navigator.pushReplacement(
            context, MaterialPageRoute(builder: (_) => const homePage()));
        break;
      case 1:
        Navigator.pushReplacement(
            context, MaterialPageRoute(builder: (_) => const taskPage()));
        break;
      case 2:
        Navigator.pushReplacement(
            context, MaterialPageRoute(builder: (_) => const levelsPage()));
        break;
      case 3:
        Navigator.pushReplacement(
            context, MaterialPageRoute(builder: (_) => const mapPage()));
        break;
      case 4:
        Navigator.pushReplacement(
            context, MaterialPageRoute(builder: (_) => const communityPage()));
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isKeyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        extendBody: true,
        extendBodyBehindAppBar: true,
        backgroundColor: Colors.transparent,
        appBar: const NameerAppBar(
          showTitleInBar: false,
          showBack: false,
          height: 80,
        ),
        body: Stack(
          children: [
            // ── الخلفية ──
            Positioned.fill(
              child: Image.asset(
                'assets/img/backgroundimg.png',
                fit: BoxFit.cover,
              ),
            ),

            // ── المحتوى ──
            StreamBuilder<DocumentSnapshot>(
              stream: XpService.userStream(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final data =
                    snapshot.data?.data() as Map<String, dynamic>? ?? {};
                final int xp = data['xp'] ?? 0;
                final currentLevel = getCurrentLevel(xp);
                final nextLevel = getNextLevel(xp);
                final progress = getLevelProgress(xp);

                return SafeArea(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // ── عنوان الصفحة ──
                        Text(
                          'مراحلي',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.ibmPlexSansArabic(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: appColors.dark,
                          ),
                        ),
                        const SizedBox(height: 20),

                        // ── بطاقة XP والتقدم ──
                        _XpProgressCard(
                          xp: xp,
                          currentLevel: currentLevel,
                          nextLevel: nextLevel,
                          progress: progress,
                        ),

                        const SizedBox(height: 24),

                        // ── عنوان قائمة المراحل ──
                        Text(
                          'جميع المراحل',
                          style: GoogleFonts.ibmPlexSansArabic(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: appColors.dark,
                          ),
                        ),
                        const SizedBox(height: 12),

                        // ── قائمة المراحل ──
                        ...kLevels.map((level) => _LevelCard(
                              level: level,
                              userXp: xp,
                              isCurrentLevel: level.id == currentLevel.id,
                            )),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ),
        bottomNavigationBar: isKeyboardOpen
            ? null
            : BottomNavPage(currentIndex: _currentIndex, onTap: _onTap),
      ),
    );
  }
}

// ====================================================
// بطاقة شريط XP
// ====================================================
class _XpProgressCard extends StatelessWidget {
  final int xp;
  final LevelModel currentLevel;
  final LevelModel? nextLevel;
  final double progress;

  const _XpProgressCard({
    required this.xp,
    required this.currentLevel,
    required this.nextLevel,
    required this.progress,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.92),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: currentLevel.color.withOpacity(0.25),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          // الأيقون والاسم
          Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: currentLevel.color.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    currentLevel.icon,
                    style: const TextStyle(fontSize: 28),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      currentLevel.nameAr,
                      style: GoogleFonts.ibmPlexSansArabic(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: currentLevel.color,
                      ),
                    ),
                    Text(
                      'مرحلتك الحالية',
                      style: GoogleFonts.ibmPlexSansArabic(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
              // إجمالي XP
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '$xp',
                    style: GoogleFonts.ibmPlexSansArabic(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      color: appColors.dark,
                    ),
                  ),
                  Text(
                    'XP',
                    style: GoogleFonts.ibmPlexSansArabic(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 18),

          // شريط التقدم
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 12,
              backgroundColor: Colors.grey[200],
              valueColor:
                  AlwaysStoppedAnimation<Color>(currentLevel.color),
            ),
          ),

          const SizedBox(height: 10),

          // نص الباقي
          if (nextLevel != null)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${(progress * 100).toInt()}%',
                  style: GoogleFonts.ibmPlexSansArabic(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: currentLevel.color,
                  ),
                ),
                Text(
                  'باقي ${nextLevel!.requiredXp - xp} XP للوصول لـ${nextLevel!.nameAr} ${nextLevel!.icon}',
                  style: GoogleFonts.ibmPlexSansArabic(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            )
          else
            Text(
              '🎉 وصلت لأعلى مرحلة!',
              style: GoogleFonts.ibmPlexSansArabic(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: currentLevel.color,
              ),
            ),
        ],
      ),
    );
  }
}

// ====================================================
// بطاقة مرحلة واحدة
// ====================================================
class _LevelCard extends StatelessWidget {
  final LevelModel level;
  final int userXp;
  final bool isCurrentLevel;

  const _LevelCard({
    required this.level,
    required this.userXp,
    required this.isCurrentLevel,
  });

  @override
  Widget build(BuildContext context) {
    final bool isUnlocked = userXp >= level.requiredXp;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: isUnlocked
            ? Colors.white.withOpacity(0.92)
            : Colors.white.withOpacity(0.55),
        borderRadius: BorderRadius.circular(16),
        border: isCurrentLevel
            ? Border.all(color: level.color, width: 2.5)
            : Border.all(color: Colors.transparent),
        boxShadow: isUnlocked
            ? [
                BoxShadow(
                  color: level.color.withOpacity(0.15),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                )
              ]
            : [],
      ),
      child: Row(
        children: [
          // الأيقون
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: isUnlocked
                  ? level.color.withOpacity(0.15)
                  : Colors.grey[200],
              shape: BoxShape.circle,
            ),
            child: Center(
              child: isUnlocked
                  ? Text(level.icon, style: const TextStyle(fontSize: 24))
                  : const Icon(Icons.lock_rounded,
                      color: Colors.grey, size: 22),
            ),
          ),
          const SizedBox(width: 14),

          // الاسم والـ XP المطلوب
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  level.nameAr,
                  style: GoogleFonts.ibmPlexSansArabic(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: isUnlocked ? appColors.dark : Colors.grey,
                  ),
                ),
                Text(
                  level.requiredXp == 0
                      ? 'المرحلة الأولى'
                      : '${level.requiredXp} XP للفتح',
                  style: GoogleFonts.ibmPlexSansArabic(
                    fontSize: 12,
                    color: isUnlocked ? Colors.grey[600] : Colors.grey[400],
                  ),
                ),
              ],
            ),
          ),

          // Badge الحالية أو ✓
          if (isCurrentLevel)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: level.color,
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(
                'حالياً',
                style: GoogleFonts.ibmPlexSansArabic(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            )
          else if (isUnlocked)
            Icon(Icons.check_circle_rounded, color: level.color, size: 26)
          else
            Icon(Icons.lock_rounded, color: Colors.grey[300], size: 22),
        ],
      ),
    );
  }
}

// ====================================================
// دوال مساعدة (موجودة في xp_service.dart - أُعيد تصديرها)
// ====================================================
// getRequiredTasksPerDay و getLevelName كما هما في ملفك الأصلي
int getRequiredTasksPerDay(String levelId) {
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

String getLevelName(String levelId) {
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

String _yyyyMMdd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';

Future<int> getCompletedTasksForDay(String userId, DateTime day) async {
  final dayKey = '${userId}_${_yyyyMMdd(day)}';
  final bonusKey = '${userId}_${_yyyyMMdd(day)}_bonus';
  int count = 0;
  try {
    final mainTask = await FirebaseFirestore.instance
        .collection('userTasks')
        .doc(dayKey)
        .get();
    if (mainTask.exists && mainTask.data()?['status'] == 'completed') count++;

    final bonusTask = await FirebaseFirestore.instance
        .collection('userTasks')
        .doc(bonusKey)
        .get();
    if (bonusTask.exists && bonusTask.data()?['status'] == 'completed') count++;
  } catch (e) {
    debugPrint('⚠️ Error getting completed tasks: $e');
  }
  return count;
}