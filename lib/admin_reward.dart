import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'services/admin_bottom_nav.dart';
import 'admin_home.dart';
import 'admin_task.dart';
import 'admin_map.dart';
import 'services/background_container.dart';
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

class AdminRewardsPage extends StatefulWidget {
  const AdminRewardsPage({super.key});

  @override
  State<AdminRewardsPage> createState() => _AdminRewardsPageState();
}

class _AdminRewardsPageState extends State<AdminRewardsPage> {
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

  int _currentIndex = 0;

  void _onTap(int i) {
    if (i == _currentIndex) return;
    switch (i) {
      case 0:
        break;
      case 1:
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const AdminMapPage()),
        );
        break;
      case 2:
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const AdminTasksPage()),
        );
        break;
      case 3:
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const AdminHomePage()),
        );
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isKeyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;
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
          appBarTheme: const AppBarTheme(
            backgroundColor: Colors.transparent,
            elevation: 0,
            iconTheme: IconThemeData(color: Colors.white),
          ),
        ),
        child: Scaffold(
          extendBody: true,
          extendBodyBehindAppBar: true,
          backgroundColor: Colors.transparent,

          // لو عندك NameerHeader، استخدميه بدون عنوان داخل الهيدر:
          // appBar: const NameerHeader(title: '', centerTitle: true),
          appBar: const NameerAppBar(
            showTitleInBar: false, // 👈 عشان ما يطلع عنوان داخل الهيدر
          ),

          body: AnimatedBackgroundContainer(
            child: Builder(
              builder: (context) {
                // نفس حساب البادينغ المستخدم في صفحة المهام
                final statusBar = MediaQuery.of(context).padding.top;
                const headerH = 20; // ارتفاع التولبار الحقيقي
                const fadeH = 0.0; // ما عندنا PreferredSize إضافي هنا
                const gap = 12.0; // مسافة بسيطة بعد الهيدر
                final topPadding = statusBar + headerH + fadeH + gap;

                return Padding(
                  padding: EdgeInsets.fromLTRB(16, topPadding, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ✅ العنوان هنا تحت الهيدر مباشرة (نفس H1 في صفحة المهام)
                      Text(
                        'صفحة الجوائز',
                        style: GoogleFonts.ibmPlexSansArabic(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: AppColors.dark,
                        ),
                      ),
                      const SizedBox(height: 15),

                      // محتوى الصفحة
                      const Expanded(
                        child: Center(
                          child: Text(
                            "هنا صفحة الجوائز 🏆",
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: AppColors.dark,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),

          bottomNavigationBar: isKeyboardOpen
              ? null
              : AdminBottomNav(currentIndex: _currentIndex, onTap: _onTap),
        ),
      ),
    );
  }
}
