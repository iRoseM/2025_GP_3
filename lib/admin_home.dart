import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'services/connection.dart';
import 'services/fcm_service.dart';
import 'services/admin_bottom_nav.dart';
import 'admin_task.dart';
import 'admin_reward.dart' as reward;
import 'admin_map.dart';
import 'profile.dart';
import 'services/background_container.dart';
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

class AdminHomePage extends StatefulWidget {
  const AdminHomePage({super.key});
  @override
  State<AdminHomePage> createState() => _AdminHomePageState();
}

class _AdminHomePageState extends State<AdminHomePage> {
  @override
  void initState() {
    super.initState();

    // ✅ تحقق أولاً من وجود اتصال بالإنترنت
    Future.microtask(() async {
      if (!await hasInternetConnection()) {
        if (mounted) {
          showNoInternetDialog(context);
          return;
        }
      } else {
        // ✅ فقط إذا في إنترنت: فعّل إشعارات FCM
        FCMService.requestPermissionAndSaveToken();
        FCMService.listenToForegroundMessages();
      }
    });
  }

  int _currentIndex = 3;

  void _onTap(int i) {
    if (i == _currentIndex) return;
    switch (i) {
      case 0:
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => reward.AdminRewardsPage()),
        );
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

    // ✅ المستخدم الحالي
    final user = FirebaseAuth.instance.currentUser;

    // ✅ ستريم لقراءة users/{uid}
    final Stream<DocumentSnapshot<Map<String, dynamic>>>? userStream =
        (user == null)
        ? null
        : FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .snapshots();

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Theme(
        data: baseTheme.copyWith(
          textTheme: textTheme,
          scaffoldBackgroundColor: Colors.transparent,
        ),
        child: Scaffold(
          extendBody: true,
          backgroundColor: AppColors.background,
          // appBar: const NameerAppBar(
          //   showTitleInBar: false, // 👈 عشان ما يطلع عنوان داخل الهيدر
          // ),
          body: AnimatedBackgroundContainer(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 4),

                  // 🌿 Profile Row — ✅ يقرأ الاسم والأفاتار من الداتابيس
                  StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    stream: userStream,
                    builder: (context, snap) {
                      final isLoading =
                          snap.connectionState == ConnectionState.waiting;
                      final data = snap.data?.data();

                      // الاسم المعروض: username أو displayName أو البريد
                      final String displayName = isLoading
                          ? '...'
                          : (data?['username']?.toString().trim().isNotEmpty ==
                                    true
                                ? data!['username'].toString()
                                : (user?.displayName?.trim().isNotEmpty == true
                                      ? user!.displayName!
                                      : (user?.email ?? 'مستخدم')));

                      // ✅ الأفاتارات
                      int? pfpIndex;
                      if (data?['pfpIndex'] is int) {
                        pfpIndex = data!['pfpIndex'] as int;
                      } else if (data?['pfpIndex'] != null) {
                        pfpIndex = int.tryParse(data!['pfpIndex'].toString());
                      }
                      String? avatarPath;
                      if (pfpIndex != null && pfpIndex >= 0 && pfpIndex < 8) {
                        avatarPath = 'assets/pfp/pfp${pfpIndex + 1}.png';
                      }

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              // Profile icon / avatar
                              Container(
                                width: 46,
                                height: 46,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: LinearGradient(
                                    colors: [
                                      AppColors.primary.withOpacity(.2),
                                      AppColors.sea.withOpacity(.1),
                                    ],
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppColors.primary.withOpacity(.2),
                                      blurRadius: 12,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(999),
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => const profilePage(),
                                      ),
                                    );
                                  },
                                  child: CircleAvatar(
                                    backgroundColor: Colors.transparent,
                                    radius: 23,
                                    backgroundImage:
                                        (avatarPath != null && !isLoading)
                                        ? AssetImage(avatarPath)
                                        : null,
                                    child: (avatarPath == null || isLoading)
                                        ? const Icon(
                                            Icons.person_outline,
                                            color: AppColors.primary,
                                            size: 26,
                                          )
                                        : null,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),

                              // Text beside the icon
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  RichText(
                                    text: TextSpan(
                                      children: [
                                        TextSpan(
                                          text: "مرحباً، ",
                                          style: GoogleFonts.ibmPlexSansArabic(
                                            fontSize: 20,
                                            fontWeight: FontWeight.w800,
                                            color: AppColors.dark,
                                          ),
                                        ),
                                        TextSpan(
                                          text: displayName,
                                          style: GoogleFonts.ibmPlexSansArabic(
                                            fontSize: 20,
                                            fontWeight: FontWeight.w800,
                                            color: AppColors.dark,
                                          ),
                                        ),
                                        const TextSpan(text: " 👋"),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    "لنجعل اليوم مميزاً!",
                                    style: GoogleFonts.ibmPlexSansArabic(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.sea,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      );
                    },
                  ),

                  const SizedBox(height: 26),

                  // 📊 Dashboard Container (كما هو)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 20,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.grey.withOpacity(0.15),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "📊 نظرة عامة على النظام",
                          style: GoogleFonts.ibmPlexSansArabic(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: AppColors.dark,
                          ),
                        ),
                        const SizedBox(height: 12),

                        _buildStat("إجمالي المستخدمين المسجلين", "121"),
                        _divider(),
                        _buildStat("إجمالي المهام المستدامة المكتملة", "2,344"),
                        _divider(),
                        _buildStat("إجمالي النقاط الموزعة", "148,900"),
                        _divider(),
                        _buildStat("الأثر الكربوني الإجمالي", "122.42 كجم"),
                      ],
                    ),
                  ),
                ],
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

  Widget _buildStat(String title, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: GoogleFonts.ibmPlexSansArabic(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: AppColors.dark,
          ),
        ),
        Text(
          value,
          style: GoogleFonts.ibmPlexSansArabic(
            fontSize: 15,
            fontWeight: FontWeight.w400,
            color: AppColors.sea,
          ),
        ),
      ],
    );
  }

  Widget _divider() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: Divider(color: Color(0xFFE8F3EF), thickness: 1),
    );
  }
}
