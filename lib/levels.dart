// levels.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'home.dart'; // homePage
import 'task.dart'; // taskPage
import 'map.dart'; // mapPage
import 'community.dart'; // communityPage

/// ملاحظة: أضف الحزمة في pubspec.yaml
/// dependencies:
///   google_fonts: ^6.2.1

/// نسخة مبسطة من ألوان الهوية لتجنّب الاستيراد الدائري
class AppColors {
  static const primary = Color(0xFF4BAA98);
  static const dark = Color(0xFF3C3C3B);
  static const accent = Color(0xFFF4A340);
  static const sea = Color(0xFF1F7A8C);
  static const light = Color(0xFF79D0BE);
  static const background = Color(0xFFF3FAF7);
  static const mint = Color(0xFFB6E9C1);
  static const tealSoft = Color(0xFF75BCAF);
}

class levelsPage extends StatefulWidget {
  const levelsPage({super.key});

  @override
  State<levelsPage> createState() => _levelsPageState();
}

class _levelsPageState extends State<levelsPage> {
  // مثال: فتح أول 5 مراحل فقط
  final int unlockedUntil = 5;

  @override
  Widget build(BuildContext context) {
    final isKeyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;

    // === تطبيق خط IBM Plex Sans Arabic على الثيم لهذا الصفحة فقط ===
    final base = Theme.of(context);
    final arabicTextTheme = GoogleFonts.ibmPlexSansArabicTextTheme(
      base.textTheme,
    );
    final appTheme = base.copyWith(
      textTheme: arabicTextTheme,
      primaryTextTheme: arabicTextTheme,
      appBarTheme: base.appBarTheme.copyWith(
        titleTextStyle: GoogleFonts.ibmPlexSansArabic(
          fontSize: 20,
          fontWeight: FontWeight.w800,
          color: AppColors.dark,
        ),
        toolbarTextStyle: arabicTextTheme.bodyMedium,
        iconTheme: const IconThemeData(color: AppColors.dark),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      snackBarTheme: base.snackBarTheme.copyWith(
        contentTextStyle: GoogleFonts.ibmPlexSansArabic(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
    );

    return Theme(
      data: appTheme,
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          // ✅ الخلفية خضراء من هوية التطبيق — لا نغيّرها
          backgroundColor: AppColors.primary,
          appBar: AppBar(
            titleSpacing: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: AppColors.dark),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            title: const Text('المراحل'),
            actions: const [SizedBox(width: 8)],
          ),
          body: Column(
            children: [
              // بانر بسيط فوق
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Colors.white, Color(0xFFF8FCFA)],
                    ),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: const Color(0xFFE6F1EC),
                      width: 1.5,
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x14000000),
                        blurRadius: 14,
                        offset: Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.flag_rounded,
                          color: AppColors.primary,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'تقدّم خطوة بخطوة! أكمل المراحل لفتح عناصر جديدة في EcoLand.',
                          style: TextStyle(
                            color: AppColors.dark,
                            fontWeight: FontWeight.w600,
                            height: 1.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // الشبكة
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                  child: GridView.builder(
                    itemCount: 12, // عدّلها حسب عدد المراحل عندك
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          childAspectRatio: .88,
                        ),
                    itemBuilder: (context, index) {
                      final levelNumber = index + 1;
                      final isUnlocked = levelNumber <= unlockedUntil;
                      final progress = isUnlocked
                          ? (levelNumber == unlockedUntil ? 0.45 : 1.0)
                          : 0.0;

                      return _LevelCard(
                        level: levelNumber,
                        unlocked: isUnlocked,
                        progress: progress,
                        onTap: () {
                          if (!isUnlocked) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'المرحلة $levelNumber مقفلة، أكمل المراحل السابقة أولاً ✅',
                                  textDirection: TextDirection.rtl,
                                ),
                              ),
                            );
                            return;
                          }
                          // TODO: اربطها بصفحة المرحلة/اللعبة الخاصة بك
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'تم اختيار المرحلة $levelNumber 🎯',
                                textDirection: TextDirection.rtl,
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ),
            ],
          ),

          // === BottomNav (مطابق لـ map page) + ربط الصفحات ===
          bottomNavigationBar: isKeyboardOpen
              ? null
              : BottomNav(
                  currentIndex: 2, // تبويب "المراحل"
                  onTap: (i) {
                    if (i == 2) return; // أنت أصلاً على "المراحل"
                    switch (i) {
                      case 0: // الرئيسية
                        Navigator.of(context).pushAndRemoveUntil(
                          MaterialPageRoute(builder: (_) => const homePage()),
                          (route) => false,
                        );
                        break;

                      case 1: // مهامي
                        Navigator.of(context).pushReplacement(
                          MaterialPageRoute(builder: (_) => const taskPage()),
                        );
                        break;

                      case 3: // الخريطة
                        Navigator.of(context).pushAndRemoveUntil(
                          MaterialPageRoute(builder: (_) => const mapPage()),
                          (route) => false,
                        );
                        break;

                      case 4: // الأصدقاء / المجتمع
                        Navigator.of(context).pushReplacement(
                          MaterialPageRoute(
                            builder: (_) => const communityPage(),
                          ),
                        );
                        break;

                      default:
                        break;
                    }
                  },
                  onCenterTap: () {
                    // زر "المراحل" (هنا نفتح نفس الصفحة أو تفاصيل آخر مرحلة)
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const levelsPage()),
                    );
                  },
                ),
        ),
      ),
    );
  }
}

class _LevelCard extends StatelessWidget {
  final int level;
  final bool unlocked;
  final double progress; // 0..1
  final VoidCallback onTap;

  const _LevelCard({
    required this.level,
    required this.unlocked,
    required this.progress,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = unlocked ? Colors.white : const Color(0xFFF4F7F6);
    final border = unlocked ? const Color(0xFFE3EFEA) : const Color(0xFFDFE8E5);
    final iconBg = unlocked
        ? AppColors.primary.withOpacity(.12)
        : AppColors.sea.withOpacity(.10);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: unlocked ? onTap : null,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: border, width: 1.4),
            boxShadow: unlocked
                ? const [
                    BoxShadow(
                      color: Color(0x12000000),
                      blurRadius: 10,
                      offset: Offset(0, 6),
                    ),
                  ]
                : const [],
          ),
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // رأس البطاقة (قفل/علم)
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: iconBg,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      unlocked ? Icons.flag_rounded : Icons.lock_rounded,
                      size: 18,
                      color: unlocked ? AppColors.primary : Colors.black45,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '#$level',
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      color: AppColors.dark,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // عنوان
              Text(
                unlocked ? 'مرحلة $level' : 'مقفلة',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: unlocked ? AppColors.dark : Colors.black54,
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
              const Spacer(),

              // تقدّم
              if (unlocked)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: progress.clamp(0, 1),
                        minHeight: 8,
                        backgroundColor: AppColors.light.withOpacity(.25),
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          AppColors.accent,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${(progress * 100).round()}%',
                      textAlign: TextAlign.start,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.dark,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                )
              else
                const Text(
                  'أكمل السابق أولاً',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.black54,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/* ======================= BottomNav (مطابق لـ map page) ======================= */

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
                // ✅ نفس زر المراحل الموجود في map page تمامًا
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
                        ),
                        child: const Icon(
                          Icons.flag_rounded,
                          color: Colors.white,
                          size: 28,
                        ),
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
                          fontWeight: selected
                              ? FontWeight.w800
                              : FontWeight.w500,
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
