import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'widgets/background_container.dart';
import 'widgets/bottom_nav.dart'; // ✅ شريط التنقل الموحد

// ⬇️ استيراد الصفحات
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
        textTheme: GoogleFonts.ibmPlexSansArabicTextTheme(),
        primaryColor: const Color(0xFF4BAA98),
      ),
      home: const communityPage(),
    );
  }
}

/* ======================= صفحة الأصدقاء ======================= */

class communityPage extends StatefulWidget {
  const communityPage({super.key});

  @override
  State<communityPage> createState() => _communityPageState();
}

class _communityPageState extends State<communityPage> {
  // ✅ تبويب الأصدقاء = index رقم 4
  final int _currentIndex = 4;

  // ✅ دالة التنقل الموحدة بين الصفحات
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
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    // ✅ إخفاء الناف بار عند ظهور الكيبورد
    final isKeyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        extendBody: true,
        backgroundColor: Colors.transparent,

        appBar: AppBar(
          centerTitle: true,
          title: Text(
            "الأصدقاء",
            style: GoogleFonts.ibmPlexSansArabic(
              fontWeight: FontWeight.w700,
              fontSize: 20,
              color: Colors.white,
            ),
          ),
          // ✅ تدرج الألوان من الهوية
          flexibleSpace: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Color(0xFF009688),
                  Color(0xFF009688),
                  Color(0xFFB6E9C1),
                ],
                stops: [0.0, 0.5, 1.0],
                begin: Alignment.bottomLeft,
                end: Alignment.topRight,
              ),
            ),
          ),
          elevation: 0,
          backgroundColor: Colors.transparent,
        ),

        // ✅ الخلفية المتحركة الموحدة
        body: AnimatedBackgroundContainer(
          child: Center(
            child: Text(
              "هنا صفحة الأصدقاء 👥",
              style: GoogleFonts.ibmPlexSansArabic(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF3C3C3B),
              ),
            ),
          ),
        ),

        // ✅ شريط التنقل السفلي
        bottomNavigationBar: isKeyboardOpen
            ? null
            : BottomNavPage(currentIndex: _currentIndex, onTap: _onTap),
      ),
    );
  }
}
