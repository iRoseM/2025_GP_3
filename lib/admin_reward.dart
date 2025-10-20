import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'widgets/admin_bottom_nav.dart';
import 'admin_home.dart';
import 'admin_task.dart';
import 'admin_map.dart';
import 'widgets/background_container.dart';

class AdminRewardsPage extends StatefulWidget {
  const AdminRewardsPage({super.key});

  @override
  State<AdminRewardsPage> createState() => _AdminRewardsPageState();
}

class _AdminRewardsPageState extends State<AdminRewardsPage> {
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
          appBarTheme: AppBarTheme(
            elevation: 0,
            backgroundColor: Colors.transparent,
            titleTextStyle: GoogleFonts.ibmPlexSansArabic(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
            iconTheme: const IconThemeData(color: Colors.white),
          ),
        ),

        // ✅ Scaffold changes below
        child: Scaffold(
          extendBody: true, // ✅ allows background under bottom nav bar
          backgroundColor: Colors.transparent, // ✅ no black background

          appBar: AppBar(
            centerTitle: true,
            title: const Text("صفحة الجوائز"),
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

          // ✅ Wrap your body in the background container
          body: AnimatedBackgroundContainer(
            child: const Center(
              child: Text(
                "هنا صفحة الجوائز 🏆",
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF3C3C3B),
                ),
              ),
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
