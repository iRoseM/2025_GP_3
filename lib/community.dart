import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ⬇️ استورد صفحاتك الفعلية
import 'home.dart' show homePage;
import 'map.dart' show mapPage;
import 'task.dart' show taskPage;
import 'levels.dart' show levelsPage;

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        textTheme:
            GoogleFonts.ibmPlexSansArabicTextTheme(), // 👈 خط التطبيق كامل
        primaryColor: const Color(0xFF4BAA98),
      ),
      home: const communityPage(),
    );
  }
}

class communityPage extends StatelessWidget {
  const communityPage({super.key});

  void _navigateReplace(BuildContext context, Widget page) {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => page),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            "الأصدقاء",
            style: GoogleFonts.ibmPlexSansArabic(
              fontWeight: FontWeight.w700,
              fontSize: 20,
            ),
          ),
          backgroundColor: const Color(0xFF4BAA98),
        ),
        body: Center(
          child: Text(
            "هنا صفحة الأصدقاء 👥",
            style: GoogleFonts.ibmPlexSansArabic(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF3C3C3B),
            ),
          ),
        ),
        bottomNavigationBar: BottomNav(
          currentIndex: 4, // تبويب الأصدقاء
          onTap: (i) {
            if (i == 4) return;
            switch (i) {
              case 0: // الرئيسية
                _navigateReplace(context, const homePage());
                break;
              case 1: // مهامي
                _navigateReplace(context, const taskPage());
                break;
              case 3: // الخريطة
                _navigateReplace(context, const mapPage());
                break;
              default:
                break;
            }
          },
          onCenterTap: () {
            _navigateReplace(context, const levelsPage());
          },
        ),
      ),
    );
  }
}

/* ======================= BottomNav ======================= */

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
                          color: Color(0xFF009688),
                          shape: BoxShape.circle,
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
              final color = selected ? const Color(0xFF009688) : Colors.black54;

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
                        style: GoogleFonts.ibmPlexSansArabic(
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
