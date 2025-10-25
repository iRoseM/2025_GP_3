import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'home.dart';
import 'task.dart';
import 'map.dart';
import 'community.dart';
import 'services/background_container.dart';
import 'services/bottom_nav.dart';
import 'services/title_header.dart';

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
  final int _currentIndex = 2;

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

  @override
  Widget build(BuildContext context) {
    final isKeyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        // ✅ مهم: خلّي الجسم يمتد خلف الـ bottomNavigationBar
        extendBody: true,
        // ولو تحب يبقى الهيدر شفاف فوق الجسم
        extendBodyBehindAppBar: true,
        backgroundColor: Colors.transparent,

        // ✅ الهيدر الموحد
        appBar: const NameerAppBar(
          showTitleInBar: false,
          showBack: false,
          height: 80,
        ),

        // ✅ الخلفية + النص فوقها
        body: Stack(
          children: [
            // الخلفية تملأ الصفحة بالكامل (بما فيها منطقة تحت الناف بار)
            Positioned.fill(
              child: Image.asset(
                'assets/img/backgroundimg.png',
                fit: BoxFit.cover,
              ),
            ),

            // النص فوق الخلفية
            Builder(
              builder: (context) {
                final statusBar = MediaQuery.of(context).padding.top;
                const headerH = 20.0; // ارتفاع الهيدر الفعلي
                const gap = 12.0;
                final topPadding = statusBar + headerH + gap;

                return Padding(
                  padding: EdgeInsets.only(top: topPadding),
                  child: Center(
                    child: Text(
                      'صفحة المراحل والتحديات',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.ibmPlexSansArabic(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppColors.dark,
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),

        // ✅ شريط التنقل السفلي
        bottomNavigationBar: isKeyboardOpen
            ? null
            : BottomNavPage(currentIndex: _currentIndex, onTap: _onTap),
      ),
    );
  }
}
