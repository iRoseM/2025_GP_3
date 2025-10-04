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
          centerTitle: true,
          title: Text(
            "الأصدقاء",
            style: GoogleFonts.ibmPlexSansArabic(
              fontWeight: FontWeight.w700,
              fontSize: 20,
              color: Colors.white, // العنوان أبيض فوق الجراديانت
            ),
          ),
          // 👇 التدرّج على “الديف” العلوي (AppBar)
          flexibleSpace: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Color(0xFF009688), // primary
                  Color(0xFF009688),
                  Color(0xFFB6E9C1), // mint
                ],
                stops: [0.0, 0.5, 1.0],
                begin: Alignment.bottomLeft,
                end: Alignment.topRight,
              ),
            ),
          ),
          elevation: 0,
          backgroundColor: Colors.transparent, // مهم لإظهار التدرّج
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

  static const Color _primary = Color(0xFF009688);

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
          color: Colors.white, // 👈 رجعناه أبيض مثل القديم
          child: Row(
            children: List.generate(items.length, (i) {
              final it = items[i];
              final selected = i == currentIndex;

              // زر الوسط (المراحل) — دائرة خضراء وأيقونة بيضاء
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
                          color: _primary,
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

              // العناصر الجانبية: المختار = معبّأ ولونه أخضر، غير المختار = مفرّغ ورمادي
              final iconData = selected ? it.filled : it.outlined;
              final color = selected ? _primary : Colors.black54;

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
