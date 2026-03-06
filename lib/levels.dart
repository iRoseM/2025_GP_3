import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:developer' as developer;

import 'home.dart';
import 'task.dart';
import 'map.dart';
import 'community.dart';
import 'services/background_container.dart';
import 'services/bottom_nav.dart';
import 'services/title_header.dart';
import '../services/app_colors.dart';

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
                        color: appColors.dark,
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

// ====================================================
// دالة تحسب عدد المهام المطلوبة حسب مستوى المستخدم
// ====================================================
int getRequiredTasksPerDay(String levelId) {
  switch (levelId) {
    case 'hard':
      return 2;
    case 'medium':
      return 2;
    case 'beginner':
    default:
      return 1;
  }
}

// ====================================================
// دالة تحول levelId إلى اسم عربي
// ====================================================
String getLevelName(String levelId) {
  switch (levelId) {
    case 'beginner':
      return 'مبتدئ';
    case 'medium':
      return 'متوسط';
    case 'hard':
      return 'متقدم';
    default:
      return 'مبتدئ';
  }
}

String _yyyyMMdd(DateTime d) {
  return '${d.year.toString().padLeft(4, '0')}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';
}

// ====================================================
// دالة تحسب المهام المكتملة لليوم
// ====================================================
Future<int> getCompletedTasksForDay(String userId, DateTime day) async {
  final dayKey = '${userId}_${_yyyyMMdd(day)}';
  final bonusKey = '${userId}_${_yyyyMMdd(day)}_bonus';

  int count = 0;

  try {
    // المهمة الرئيسية
    final mainTask = await FirebaseFirestore.instance
        .collection('userTasks')
        .doc(dayKey)
        .get();

    if (mainTask.exists && mainTask.data()?['status'] == 'completed') {
      count++;
    }

    // المهمة الإضافية (إذا كانت موجودة)
    final bonusTask = await FirebaseFirestore.instance
        .collection('userTasks')
        .doc(bonusKey)
        .get();

    if (bonusTask.exists && bonusTask.data()?['status'] == 'completed') {
      count++;
    }
  } catch (e) {
    debugPrint('⚠️ Error getting completed tasks: $e');
  }

  return count;
}
