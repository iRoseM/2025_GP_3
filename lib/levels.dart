import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

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
  bool _levelUpChecked = false;

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

  // ✅ تحقق من الترقية مرة وحدة فقط
  Future<void> _checkLevelUp(int xp) async {
    if (_levelUpChecked) return;
    _levelUpChecked = true;

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final userRef = FirebaseFirestore.instance.collection('users').doc(uid);
    final snap = await userRef.get();
    final data = snap.data() ?? {};

    final String lastSeenLevel = data['lastSeenLevel'] ?? 'seedling';
    final currentLevel = getCurrentLevel(xp);

    // إذا الليفل تغير
    if (currentLevel.id != lastSeenLevel) {
      // حدّث lastSeenLevel
      await userRef.update({'lastSeenLevel': currentLevel.id});

      // عرض البوب أب
      if (mounted) {
        await showLevelUpDialog(context, currentLevel);
      }
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

            final data = snapshot.data?.data() as Map<String, dynamic>? ?? {};
            final int xp = data['xp'] ?? 0;
            final currentLevel = getCurrentLevel(xp);
            final nextLevel = getNextLevel(xp);
            final double progress = getLevelProgress(xp);

            // ✅ تحقق من الترقية بعد أول بيانات
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _checkLevelUp(xp);
            });

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
                          xp: xp,
                          currentLevel: currentLevel,
                          nextLevel: nextLevel,
                          progress: progress,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Expanded(child: _LevelsTimeline(userXp: xp)),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
        bottomNavigationBar: BottomNavPage(currentIndex: _currentIndex, onTap: _onTap),
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
                  style: GoogleFonts.ibmPlexSansArabic(fontSize: 12, color: Colors.white60),
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
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.95),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 20, offset: const Offset(0, 6)),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [currentLevel.color.withOpacity(0.7), currentLevel.color],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(color: currentLevel.color.withOpacity(0.35), blurRadius: 10, offset: const Offset(0, 3)),
                  ],
                ),
                child: Center(child: Text(currentLevel.icon, style: const TextStyle(fontSize: 24))),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      currentLevel.nameAr,
                      style: GoogleFonts.ibmPlexSansArabic(fontSize: 16, fontWeight: FontWeight.w800, color: currentLevel.color),
                    ),
                    Text(
                      'مرحلتك الحالية',
                      style: GoogleFonts.ibmPlexSansArabic(fontSize: 12, color: Colors.grey[500]),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '$xp',
                    style: GoogleFonts.ibmPlexSansArabic(fontSize: 28, fontWeight: FontWeight.w900, color: const Color(0xFF1B5E20), height: 1),
                  ),
                  Text(
                    'XP',
                    style: GoogleFonts.ibmPlexSansArabic(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey[500], letterSpacing: 1),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final double dotPos = (constraints.maxWidth * progress).clamp(8.0, constraints.maxWidth - 8.0);
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    height: 10,
                    decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(99)),
                  ),
                  FractionallySizedBox(
                    widthFactor: progress,
                    child: Container(
                      height: 10,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: [currentLevel.color.withOpacity(0.6), currentLevel.color]),
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
                        border: Border.all(color: currentLevel.color, width: 3),
                        boxShadow: [BoxShadow(color: currentLevel.color.withOpacity(0.3), blurRadius: 6)],
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
                style: GoogleFonts.ibmPlexSansArabic(fontSize: 12, fontWeight: FontWeight.w700, color: currentLevel.color),
              ),
              if (nextLevel != null)
                Text(
                  'باقي ${nextLevel!.requiredXp - xp} XP للوصول لـ${nextLevel!.nameAr} ${nextLevel!.icon}',
                  style: GoogleFonts.ibmPlexSansArabic(fontSize: 12, color: Colors.grey[500]),
                )
              else
                Text(
                  '🎉 وصلت لأعلى مرحلة!',
                  style: GoogleFonts.ibmPlexSansArabic(fontSize: 12, fontWeight: FontWeight.w700, color: currentLevel.color),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────
// Timeline
// ─────────────────────────────────────────
class _LevelsTimeline extends StatelessWidget {
  final int userXp;
  const _LevelsTimeline({required this.userXp});

  @override
  Widget build(BuildContext context) {
    final levels = kLevels.reversed.toList();
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 30),
      itemCount: levels.length,
      itemBuilder: (context, index) {
        final level = levels[index];
        final bool isUnlocked = userXp >= level.requiredXp;
        final bool isCurrent = getCurrentLevel(userXp).id == level.id;
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
                    color: isUnlocked ? const Color(0xFF4CAF50).withOpacity(0.3) : const Color(0xFFBDBDBD).withOpacity(0.4),
                  ),
                ),
              ),
            _LevelRow(level: level, isUnlocked: isUnlocked, isCurrent: isCurrent),
            if (!isLast)
              Center(
                child: Container(
                  width: 3,
                  height: 28,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(99),
                    color: isUnlocked ? const Color(0xFF4CAF50).withOpacity(0.3) : const Color(0xFFBDBDBD).withOpacity(0.4),
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
// صف مستوى
// ─────────────────────────────────────────
class _LevelRow extends StatelessWidget {
  final LevelModel level;
  final bool isUnlocked;
  final bool isCurrent;

  const _LevelRow({required this.level, required this.isUnlocked, required this.isCurrent});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(child: _RewardCard(level: level, isUnlocked: isUnlocked, isVip: false)),
        const SizedBox(width: 8),
        _TimelineNode(level: level, isUnlocked: isUnlocked, isCurrent: isCurrent),
        const SizedBox(width: 8),
        Expanded(child: _RewardCard(level: level, isUnlocked: isUnlocked, isVip: true)),
      ],
    );
  }
}

// ─────────────────────────────────────────
// عقدة المستوى
// ─────────────────────────────────────────
class _TimelineNode extends StatelessWidget {
  final LevelModel level;
  final bool isUnlocked;
  final bool isCurrent;

  const _TimelineNode({required this.level, required this.isUnlocked, required this.isCurrent});

  @override
  Widget build(BuildContext context) {
    final Color bgColor = isCurrent ? level.color : isUnlocked ? Colors.white : const Color(0xFFEEEEEE);
    final Color borderColor = isCurrent ? Colors.white : isUnlocked ? level.color : const Color(0xFFBDBDBD);
    final List<BoxShadow> shadows = isCurrent
        ? [
            BoxShadow(color: level.color.withOpacity(0.4), blurRadius: 16, spreadRadius: 2),
            BoxShadow(color: level.color.withOpacity(0.15), blurRadius: 6, spreadRadius: 8),
          ]
        : isUnlocked
            ? [BoxShadow(color: level.color.withOpacity(0.15), blurRadius: 10, offset: const Offset(0, 3))]
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
            border: Border.all(color: borderColor, width: isCurrent ? 3 : 2),
            boxShadow: shadows,
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ColorFiltered(
                  colorFilter: isUnlocked
                      ? const ColorFilter.mode(Colors.transparent, BlendMode.saturation)
                      : const ColorFilter.matrix([
                          0.2126, 0.7152, 0.0722, 0, 0,
                          0.2126, 0.7152, 0.0722, 0, 0,
                          0.2126, 0.7152, 0.0722, 0, 0,
                          0, 0, 0, 1, 0,
                        ]),
                  child: level.id == 'seedling'
                      ? Image.asset('assets/img/seedling.png', height: 22, fit: BoxFit.contain)
                      : Text(level.icon, style: TextStyle(fontSize: 22, color: isUnlocked ? null : Colors.grey)),
                ),
                Text(
                  '${level.requiredXp}',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: isCurrent ? Colors.white70 : isUnlocked ? level.color : const Color(0xFFBDBDBD),
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
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: level.color,
                borderRadius: BorderRadius.circular(99),
                boxShadow: [BoxShadow(color: level.color.withOpacity(0.4), blurRadius: 6)],
              ),
              child: Text(
                'حالياً',
                style: GoogleFonts.ibmPlexSansArabic(fontSize: 8, fontWeight: FontWeight.w700, color: Colors.white, letterSpacing: 0.5),
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
              child: const Icon(Icons.lock_rounded, color: Colors.white, size: 10),
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────
// بطاقة الجائزة
// ─────────────────────────────────────────
class _RewardCard extends StatelessWidget {
  final LevelModel level;
  final bool isUnlocked;
  final bool isVip;

  const _RewardCard({required this.level, required this.isUnlocked, required this.isVip});

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
                0, 0, 0, 0.5, 0,
              ]),
              child: Text(isVip ? '🏅' : level.icon, style: const TextStyle(fontSize: 22)),
            ),
            const SizedBox(height: 5),
            Text(
              isVip ? 'جائزة VIP' : level.nameAr,
              textAlign: TextAlign.center,
              style: GoogleFonts.ibmPlexSansArabic(fontSize: 10, fontWeight: FontWeight.w600, color: const Color(0xFFBDBDBD)),
            ),
            const SizedBox(height: 3),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: const Color(0xFFEEEEEE), borderRadius: BorderRadius.circular(99)),
              child: Text(
                '${level.requiredXp} XP',
                style: GoogleFonts.ibmPlexSansArabic(fontSize: 9, fontWeight: FontWeight.w600, color: const Color(0xFFBDBDBD)),
              ),
            ),
          ],
        ),
      );
    }

    if (isVip) {
      String? figurePath;
      switch (level.id) {
        case 'sprout':   figurePath = 'assets/img/bush.png'; break;
        case 'tree':     figurePath = 'assets/img/tree.png'; break;
        case 'guardian': figurePath = 'assets/img/pond.png'; break;
        case 'champion': figurePath = 'assets/img/palm.png'; break;
      }

      return Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [const Color(0xFFFBBF24).withOpacity(0.18), const Color(0xFFF59E0B).withOpacity(0.06)],
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFF59E0B).withOpacity(0.45)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (figurePath != null)
              Image.asset(figurePath, height: 32, fit: BoxFit.contain)
            else
              Text(level.icon, style: const TextStyle(fontSize: 22)),
            const SizedBox(height: 5),
            Text(
              'جائزة ذهبية',
              textAlign: TextAlign.center,
              style: GoogleFonts.ibmPlexSansArabic(fontSize: 10, fontWeight: FontWeight.w700, color: const Color(0xFF92400E)),
            ),
            const SizedBox(height: 3),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: const Color(0xFFFEF3C7), borderRadius: BorderRadius.circular(99)),
              child: Text(
                'VIP ✨',
                style: GoogleFonts.ibmPlexSansArabic(fontSize: 9, fontWeight: FontWeight.w600, color: const Color(0xFFB45309)),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: level.color.withOpacity(0.2)),
        boxShadow: [BoxShadow(color: level.color.withOpacity(0.08), blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (level.id == 'seedling')
            Image.asset('assets/img/seedling.png', height: 32, fit: BoxFit.contain)
          else
            Text(level.icon, style: const TextStyle(fontSize: 22)),
          const SizedBox(height: 5),
          Text(
            level.nameAr,
            textAlign: TextAlign.center,
            style: GoogleFonts.ibmPlexSansArabic(fontSize: 10, fontWeight: FontWeight.w700, color: const Color(0xFF1a2e1a)),
          ),
          const SizedBox(height: 3),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(color: const Color(0xFFE8F5E9), borderRadius: BorderRadius.circular(99)),
            child: Text(
              'مفتوح ✓',
              style: GoogleFonts.ibmPlexSansArabic(fontSize: 9, fontWeight: FontWeight.w600, color: const Color(0xFF2E7D32)),
            ),
          ),
        ],
      ),
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

class _SkeletonBoxState extends State<_SkeletonBox> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);
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