import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'admin_bottom_nav.dart';
import 'admin_home.dart';
import 'admin_task.dart';
import 'admin_reward.dart';


class AdminMapPage extends StatefulWidget {
  const AdminMapPage({super.key});

  @override
  State<AdminMapPage> createState() => _AdminMapPageState();
}

class _AdminMapPageState extends State<AdminMapPage> {
  int _currentIndex = 1;

  void _onTap(int i) {
    if (i == _currentIndex) return;
    switch (i) {
      case 0:
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const AdminRewardsPage()),
        );
        break;
      case 1:
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
    final textTheme = GoogleFonts.ibmPlexSansArabicTextTheme(baseTheme.textTheme);

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
        child: Scaffold(
          appBar: AppBar(
            centerTitle: true,
            title: const Text("صفحة الخريطة"),
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
          body: const Center(
            child: Text(
              "هنا صفحة الخريطة 🗺️",
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: Color(0xFF3C3C3B),
              ),
            ),
          ),
          bottomNavigationBar: isKeyboardOpen
              ? null
              : AdminBottomNav(
                  currentIndex: _currentIndex,
                  onTap: _onTap,
                ),
        ),
      ),
    );
  }
}
