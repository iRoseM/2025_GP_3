// lib/pages/task_page.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'background_container.dart';


// صفحات التنقل
import 'home.dart'; // homePage
import 'map.dart'; // mapPage
import 'levels.dart'; // levelsPage
import 'community.dart'; // communityPage

// إذا عندك ملف ألوان مشترك، استورده بدله
class AppColors {
  static const primary = Color(0xFF009688);
  static const dark = Color(0xFF00695C);
  static const light = Color(0xFF4DB6AC);
  static const background = Color(0xFFFAFCFB);

  static const mint = Color(0xFFB6E9C1);
}

class taskPage extends StatelessWidget {
  const taskPage({super.key});

  @override
  Widget build(BuildContext context) {
    final isKeyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;

    // طبّق خط IBM Plex Sans Arabic على ثيم الصفحة بالكامل
    final baseTheme = Theme.of(context);
    final textTheme = GoogleFonts.ibmPlexSansArabicTextTheme(
      baseTheme.textTheme,
    );

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Theme(
        data: baseTheme.copyWith(
          textTheme: textTheme,
          primaryTextTheme: textTheme,
          appBarTheme: AppBarTheme(
            elevation: 0,
            backgroundColor: Colors.transparent, // شفاف لإظهار التدرّج
            titleTextStyle: GoogleFonts.ibmPlexSansArabic(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
            iconTheme: const IconThemeData(color: Colors.white),
          ),
        ),
        child: Scaffold(
          extendBody: true, // ✅ allows background to extend under the nav bar
          backgroundColor: Colors.transparent, // ✅ prevents black area
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
                  stops: [0.0, 0.5, 1.0],
                  begin: Alignment.bottomLeft,
                  end: Alignment.topRight,
                ),
              ),
            ),
          ),
          // ✅ Wrap your body with AnimatedBackgroundContainer
          body: AnimatedBackgroundContainer(
            child: const Center(
              child: Text(
                "هنا صفحة المهام 📝",
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF3C3C3B),
                ),
              ),
            ),
          ),

          // === BottomNav القديم (أبيض) ويختفي مع الكيبورد ===
          bottomNavigationBar: isKeyboardOpen
              ? null
              : BottomNav(
                  currentIndex: 1,
                  onTap: (i) {
                    if (i == 1) return; // أنت بالفعل على "مهامي"
                    switch (i) {
                      case 0: // الرئيسية
                        Navigator.of(context).pushAndRemoveUntil(
                          MaterialPageRoute(builder: (_) => const homePage()),
                          (route) => false,
                        );
                        break;
                      case 3: // الخريطة
                        Navigator.of(context).pushReplacement(
                          MaterialPageRoute(builder: (_) => const mapPage()),
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

/* ======================= BottomNav (القديم الأبيض) ======================= */

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
          color: Colors.white, // 👈 نفس القديم
          child: Row(
            children: List.generate(items.length, (i) {
              final it = items[i];
              final selected = i == currentIndex;

              // زر الوسط (المراحل)
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
                        child: const Icon(
                          Icons.flag_outlined,
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
                        // يَرث الخط من الثيم (IBM Plex Sans Arabic)
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
