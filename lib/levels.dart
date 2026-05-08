import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'home.dart';
import 'task.dart';
import 'map.dart';
import 'community.dart';
import 'services/bottom_nav.dart';
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
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        extendBodyBehindAppBar: true,
        body: StreamBuilder<DocumentSnapshot>(
          stream: XpService.userStream(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFF1B5E20), Color(0xFF2E7D32)],
                  ),
                ),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        const SizedBox(height: 24),
                        _SkeletonBox(height: 180, borderRadius: 20),
                        const SizedBox(height: 16),
                        _SkeletonBox(height: 60, borderRadius: 12),
                        const SizedBox(height: 16),
                        ...List.generate(
                          3,
                          (i) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _SkeletonBox(height: 80, borderRadius: 16),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }

            final data =
                snapshot.data?.data() as Map<String, dynamic>? ?? {};

            final int xpInLevel = data['xp'] ?? 0;

            final String storedLevelId = data['currentLevel'] ?? 'seedling';
            final currentLevel = kLevels.firstWhere(
              (l) => l.id == storedLevelId,
              orElse: () => kLevels.first,
            );

            final nextLevel = getNextLevelFromCurrent(currentLevel);
            final double progress =
                getLevelProgressFromZero(currentLevel, xpInLevel);

            return Stack(
              children: [
                Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: [0.0, 0.32, 0.32, 1.0],
                      colors: [
                        Color.fromARGB(83, 30, 112, 97),
                        Color.fromARGB(255, 50, 105, 95),
                        Color(0xFFF0F7EC),
                        Color(0xFFF0F7EC),
                      ],
                    ),
                  ),
                ),

                SafeArea(
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _NavIconButton(
                              icon: Icons.arrow_back_ios_new_rounded,
                              onTap: () => Navigator.maybePop(context),
                            ),
                            const SizedBox(width: 36),
                          ],
                        ),
                      ),

                      const SizedBox(height: 14),
                      const _SeasonBanner(),
                      const SizedBox(height: 14),

                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: _XpProgressCard(
                          xpInLevel: xpInLevel,
                          currentLevel: currentLevel,
                          nextLevel: nextLevel,
                          progress: progress,
                        ),
                      ),

                      const SizedBox(height: 16),

                      Expanded(
                        child: _LevelsTimeline(
                          userLevelIndex: currentLevel.index,
                          xpInLevel: xpInLevel,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
        bottomNavigationBar: BottomNavPage(
          currentIndex: _currentIndex,
          onTap: _onTap,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────
// زر AppBar
// ─────────────────────────────────────────
class _NavIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _NavIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.15),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 18),
      ),
    );
  }
}

// ─────────────────────────────────────────
// بانر الموسم
// ─────────────────────────────────────────
class _SeasonBanner extends StatelessWidget {
  const _SeasonBanner();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.12),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.2)),
        ),
        child: Row(
          children: [
            const Text('🌸', style: TextStyle(fontSize: 26)),
            const SizedBox(width: 14),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'مهرجان الربيع ',
                  style: GoogleFonts.ibmPlexSansArabic(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'الموسم ١ · ينتهي بعد ١٨ يوماً',
                  style: GoogleFonts.ibmPlexSansArabic(
                    fontSize: 12,
                    color: Colors.white60,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────
// بطاقة XP
// ─────────────────────────────────────────
class _XpProgressCard extends StatelessWidget {
  final int xpInLevel;
  final LevelModel currentLevel;
  final LevelModel? nextLevel;
  final double progress;

  const _XpProgressCard({
    required this.xpInLevel,
    required this.currentLevel,
    required this.nextLevel,
    required this.progress,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.95),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: currentLevel.color.withOpacity(0.1),
                  border: Border.all(
                    color: currentLevel.color.withOpacity(0.3),
                    width: 2,
                  ),
                ),
                child: ClipOval(
                  child: Image.asset(
                    currentLevel.figurePath,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Center(
                      child: Text(currentLevel.icon,
                          style: const TextStyle(fontSize: 24)),
                    ),
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
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: currentLevel.color,
                      ),
                    ),
                    Text(
                      'مرحلتك الحالية',
                      style: GoogleFonts.ibmPlexSansArabic(
                        fontSize: 12,
                        color: Colors.grey[500],
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '$xpInLevel',
                    style: GoogleFonts.ibmPlexSansArabic(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      color: const Color(0xFF1B5E20),
                      height: 1,
                    ),
                  ),
                  Text(
                    'XP',
                    style: GoogleFonts.ibmPlexSansArabic(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[500],
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 16),

          LayoutBuilder(
            builder: (context, constraints) {
              final double dotPos = (constraints.maxWidth * progress)
                  .clamp(8.0, constraints.maxWidth - 8.0);
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    height: 10,
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  FractionallySizedBox(
                    widthFactor: progress,
                    child: Container(
                      height: 10,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            currentLevel.color.withOpacity(0.6),
                            currentLevel.color,
                          ],
                        ),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                  Positioned(
                    left: dotPos - 8,
                    top: -3,
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: currentLevel.color, width: 3),
                        boxShadow: [
                          BoxShadow(
                            color: currentLevel.color.withOpacity(0.3),
                            blurRadius: 6,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),

          const SizedBox(height: 10),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${(progress * 100).toInt()}%',
                style: GoogleFonts.ibmPlexSansArabic(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: currentLevel.color,
                ),
              ),
              if (nextLevel != null)
                Text(
                  'باقي ${xpRemainingForNext(currentLevel, nextLevel!, xpInLevel)} XP للوصول لـ${nextLevel!.nameAr} ${nextLevel!.icon}',
                  style: GoogleFonts.ibmPlexSansArabic(
                      fontSize: 12, color: Colors.grey[500]),
                )
              else
                Text(
                  '🎉 وصلت لأعلى مرحلة!',
                  style: GoogleFonts.ibmPlexSansArabic(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: currentLevel.color,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────
// Timeline المستويات
// ─────────────────────────────────────────
class _LevelsTimeline extends StatelessWidget {
  final int userLevelIndex;
  final int xpInLevel;

  const _LevelsTimeline({
    required this.userLevelIndex,
    required this.xpInLevel,
  });

  @override
  Widget build(BuildContext context) {
    final levels = kLevels.reversed.toList();

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 30),
      itemCount: levels.length,
      itemBuilder: (context, index) {
        final level = levels[index];
        final bool isUnlocked = userLevelIndex >= level.index;
        final bool isCurrent = userLevelIndex == level.index;
        final bool isFirst = index == 0;
        final bool isLast = index == levels.length - 1;

        return Column(
          children: [
            if (!isFirst)
              Center(
                child: Container(
                  width: 3,
                  height: 28,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(99),
                    color: isUnlocked
                        ? const Color(0xFF4CAF50).withOpacity(0.3)
                        : const Color(0xFFBDBDBD).withOpacity(0.4),
                  ),
                ),
              ),

            _LevelRow(
              level: level,
              isUnlocked: isUnlocked,
              isCurrent: isCurrent,
              xpInLevel: xpInLevel,
            ),

            if (!isLast)
              Center(
                child: Container(
                  width: 3,
                  height: 28,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(99),
                    color: isUnlocked
                        ? const Color(0xFF4CAF50).withOpacity(0.3)
                        : const Color(0xFFBDBDBD).withOpacity(0.4),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

// ─────────────────────────────────────────
// صف مستوى واحد
// Layout:
//   يمين  = الفيقر (الجائزة VIP) — مفتوح/مقفول
//   وسط   = عقدة التايملاين
//   يسار  = اسم المرحلة + أيقونتها — مفتوح/مقفول
// ─────────────────────────────────────────
class _LevelRow extends StatelessWidget {
  final LevelModel level;
  final bool isUnlocked;
  final bool isCurrent;
  final int xpInLevel;

  const _LevelRow({
    required this.level,
    required this.isUnlocked,
    required this.isCurrent,
    required this.xpInLevel,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // ── يمين: الفيقر (جائزة VIP) ──
        Expanded(
          child: _FigureCard(
            level: level,
            isUnlocked: isUnlocked,
          ),
        ),
        const SizedBox(width: 8),

        // ── وسط: عقدة التايملاين ──
        _TimelineNode(
          level: level,
          isUnlocked: isUnlocked,
          isCurrent: isCurrent,
        ),
        const SizedBox(width: 8),

        // ── يسار: اسم المرحلة وأيقونتها ──
        Expanded(
          child: _LevelInfoCard(
            level: level,
            isUnlocked: isUnlocked,
            isCurrent: isCurrent,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────
// يمين — بطاقة الفيقر (الجائزة)
// مفتوحة: صورة الفيقر بألوانها
// مقفولة: صورة رمادية
// ─────────────────────────────────────────
class _FigureCard extends StatelessWidget {
  final LevelModel level;
  final bool isUnlocked;

  const _FigureCard({
    required this.level,
    required this.isUnlocked,
  });

  @override
  Widget build(BuildContext context) {
    if (!isUnlocked) {
      return Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE0E0E0)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ColorFiltered(
              colorFilter: const ColorFilter.matrix([
                0.2126, 0.7152, 0.0722, 0, 0,
                0.2126, 0.7152, 0.0722, 0, 0,
                0.2126, 0.7152, 0.0722, 0, 0,
                0, 0, 0, 0.4, 0,
              ]),
              child: Image.asset(
                level.figurePath,
                height: 48,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Icon(
                  Icons.lock_outline,
                  size: 32,
                  color: Color(0xFFBDBDBD),
                ),
              ),
            ),
            const SizedBox(height: 5),
            Text(
              level.figureName,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.ibmPlexSansArabic(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                color: const Color(0xFFBDBDBD),
              ),
            ),
            const SizedBox(height: 3),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFEEEEEE),
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(
                'مقفول 🔒',
                style: GoogleFonts.ibmPlexSansArabic(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFFBDBDBD),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // مفتوح
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: level.color.withOpacity(0.25)),
        boxShadow: [
          BoxShadow(
            color: level.color.withOpacity(0.08),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset(
            level.figurePath,
            height: 48,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => Text(
              level.icon,
              style: const TextStyle(fontSize: 32),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            level.figureName,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.ibmPlexSansArabic(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF1a2e1a),
            ),
          ),
          const SizedBox(height: 3),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFFE8F5E9),
              borderRadius: BorderRadius.circular(99),
            ),
            child: Text(
              'مفتوح ✓',
              style: GoogleFonts.ibmPlexSansArabic(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF2E7D32),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────
// يسار — بطاقة معلومات المرحلة
// مفتوحة: ملونة
// مقفولة: رمادية
// ─────────────────────────────────────────
class _LevelInfoCard extends StatelessWidget {
  final LevelModel level;
  final bool isUnlocked;
  final bool isCurrent;

  const _LevelInfoCard({
    required this.level,
    required this.isUnlocked,
    required this.isCurrent,
  });

  @override
  Widget build(BuildContext context) {
    final Color textColor =
        isUnlocked ? level.color : const Color(0xFFBDBDBD);
    final Color bgColor = isUnlocked
        ? level.color.withOpacity(0.06)
        : const Color(0xFFF5F5F5);
    final Color borderColor = isUnlocked
        ? level.color.withOpacity(0.2)
        : const Color(0xFFE0E0E0);

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
        boxShadow: isUnlocked
            ? [
                BoxShadow(
                  color: level.color.withOpacity(0.06),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // أيقونة المرحلة
          ColorFiltered(
            colorFilter: isUnlocked
                ? const ColorFilter.mode(
                    Colors.transparent, BlendMode.saturation)
                : const ColorFilter.matrix([
                    0.2126, 0.7152, 0.0722, 0, 0,
                    0.2126, 0.7152, 0.0722, 0, 0,
                    0.2126, 0.7152, 0.0722, 0, 0,
                    0, 0, 0, 0.5, 0,
                  ]),
            child: Text(
              level.icon,
              style: const TextStyle(fontSize: 26),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            level.nameAr,
            textAlign: TextAlign.center,
            style: GoogleFonts.ibmPlexSansArabic(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: textColor,
            ),
          ),
          const SizedBox(height: 3),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: isUnlocked
                  ? level.color.withOpacity(0.1)
                  : const Color(0xFFEEEEEE),
              borderRadius: BorderRadius.circular(99),
            ),
            child: Text(
              isUnlocked
                  ? (isCurrent ? 'حالياً ' : 'مكتمل ✓')
                  : '${level.requiredXp} XP',
              style: GoogleFonts.ibmPlexSansArabic(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                color: isUnlocked ? level.color : const Color(0xFFBDBDBD),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────
// عقدة التايملاين (وسط)
// ─────────────────────────────────────────
class _TimelineNode extends StatelessWidget {
  final LevelModel level;
  final bool isUnlocked;
  final bool isCurrent;

  const _TimelineNode({
    required this.level,
    required this.isUnlocked,
    required this.isCurrent,
  });

  @override
  Widget build(BuildContext context) {
    final Color bgColor = isCurrent
        ? level.color
        : isUnlocked
            ? Colors.white
            : const Color(0xFFEEEEEE);

    final Color borderColor = isCurrent
        ? Colors.white
        : isUnlocked
            ? level.color
            : const Color(0xFFBDBDBD);

    final List<BoxShadow> shadows = isCurrent
        ? [
            BoxShadow(
                color: level.color.withOpacity(0.4),
                blurRadius: 16,
                spreadRadius: 2),
            BoxShadow(
                color: level.color.withOpacity(0.15),
                blurRadius: 6,
                spreadRadius: 8),
          ]
        : isUnlocked
            ? [
                BoxShadow(
                    color: level.color.withOpacity(0.15),
                    blurRadius: 10,
                    offset: const Offset(0, 3))
              ]
            : [];

    return Stack(
      alignment: Alignment.topCenter,
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 58,
          height: 58,
          decoration: BoxDecoration(
            color: bgColor,
            shape: BoxShape.circle,
            border:
                Border.all(color: borderColor, width: isCurrent ? 3 : 2),
            boxShadow: shadows,
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ColorFiltered(
                  colorFilter: isUnlocked
                      ? const ColorFilter.mode(
                          Colors.transparent, BlendMode.saturation)
                      : const ColorFilter.matrix([
                          0.2126, 0.7152, 0.0722, 0, 0,
                          0.2126, 0.7152, 0.0722, 0, 0,
                          0.2126, 0.7152, 0.0722, 0, 0,
                          0, 0, 0, 1, 0,
                        ]),
                  child: Text(
                    level.icon,
                    style: const TextStyle(fontSize: 22),
                  ),
                ),
                Text(
                  '${level.requiredXp}',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: isCurrent
                        ? Colors.white70
                        : isUnlocked
                            ? level.color
                            : const Color(0xFFBDBDBD),
                  ),
                ),
              ],
            ),
          ),
        ),

        if (isCurrent)
          Positioned(
            top: -11,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: level.color,
                borderRadius: BorderRadius.circular(99),
                boxShadow: [
                  BoxShadow(
                      color: level.color.withOpacity(0.4), blurRadius: 6),
                ],
              ),
              child: Text(
                'حالياً',
                style: GoogleFonts.ibmPlexSansArabic(
                  fontSize: 8,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),

        if (!isUnlocked)
          Positioned(
            bottom: 0,
            right: 0,
            child: Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: const Color(0xFFBDBDBD),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.5),
              ),
              child: const Icon(Icons.lock_rounded,
                  color: Colors.white, size: 10),
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────
// Skeleton
// ─────────────────────────────────────────
class _SkeletonBox extends StatefulWidget {
  final double height;
  final double borderRadius;
  const _SkeletonBox({required this.height, required this.borderRadius});

  @override
  State<_SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<_SkeletonBox>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _anim = Tween(begin: 0.3, end: 0.7).animate(_ctrl);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Container(
        height: widget.height,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(_anim.value),
          borderRadius: BorderRadius.circular(widget.borderRadius),
        ),
      ),
    );
  }
}