import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

//  استيراد الصفحات
import 'home.dart' show homePage;
import 'map.dart' show mapPage;
import 'task.dart' show taskPage;
import 'levels.dart' show levelsPage;
import 'services/background_container.dart';
import 'services/bottom_nav.dart';
import 'services/connection.dart';
import 'services/title_header.dart';

class AppColors {
  static const primary = Color(0xFF4BAA98);
  static const dark = Color(0xFF3C3C3B);
  static const accent = Color(0xFFF4A340);
  static const sea = Color(0xFF1F7A8C);
  static const primary60 = Color(0x994BAA98);
  static const primary33 = Color(0x544BAA98);
  static const light = Color(0xFF79D0BE);
  static const background = Color(0xFFF3FAF7);
  static const mint = Color(0xFFB6E9C1);
  static const tealSoft = Color(0xFF75BCAF);
}

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
  @override
  void initState() {
    super.initState();
    _checkConnection();
  }

  Future<void> _checkConnection() async {
    if (!await hasInternetConnection()) {
      if (mounted) showNoInternetDialog(context);
    }
  }

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
    final isKeyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        extendBody: true,
        extendBodyBehindAppBar: true,
        backgroundColor: Colors.transparent,

        // هيدر نمير العام (بدون عنوان داخله)
        appBar: const NameerAppBar(
          showTitleInBar: false,
          showBack: false, // كونها صفحة تبويب رئيسية
          height: 80,
        ),

        // الخلفية المتحركة الموحدة
        body: AnimatedBackgroundContainer(
          child: Builder(
            builder: (context) {
              final statusBar = MediaQuery.of(context).padding.top;
              const headerH = 20.0; // ارتفاع شريط الأدوات الفعلي
              const gap = 12.0; // مسافة بسيطة بعد الهيدر
              final topPadding = statusBar + headerH + gap;

              return Padding(
                padding: EdgeInsets.fromLTRB(16, topPadding, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // العنوان تحت الهيدر مباشرة
                    Text(
                      'الأصدقاء',
                      style: GoogleFonts.ibmPlexSansArabic(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: AppColors.dark,
                      ),
                    ),
                    const SizedBox(height: 15),

                    // محتوى الصفحة الحالي
                    Expanded(
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Image.asset(
                              'assets/img/nameerSleep.png',
                              width: 200,
                              height: 200,
                              fit: BoxFit.contain,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'هنا صفحة الأصدقاء 👥',
                              style: GoogleFonts.ibmPlexSansArabic(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: AppColors.dark,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),

        // شريط التنقل السفلي
        bottomNavigationBar: isKeyboardOpen
            ? null
            : BottomNavPage(currentIndex: _currentIndex, onTap: _onTap),
      ),
    );
  }
}
