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
import 'admin_task_check.dart';
import '../services/app_colors.dart';

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
          backgroundColor: appColors.background,
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
                                      appColors.primary.withOpacity(.2),
                                      appColors.sea.withOpacity(.1),
                                    ],
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: appColors.primary.withOpacity(.2),
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
                                            color: appColors.primary,
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
                                            color: appColors.dark,
                                          ),
                                        ),
                                        TextSpan(
                                          text: displayName,
                                          style: GoogleFonts.ibmPlexSansArabic(
                                            fontSize: 20,
                                            fontWeight: FontWeight.w800,
                                            color: appColors.dark,
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
                                      color: appColors.sea,
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

                  // 📊 Dashboard Container — تسحب القيم من Firestore (فقط المستخدمين الموثقين)
                  StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: FirebaseFirestore.instance
                        .collection('users')
                        .where('isVerified', isEqualTo: true) // ✅ فقط الموثقين
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return Container(
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
                          child: Text(
                            "جاري تحميل الإحصائيات...",
                            style: GoogleFonts.ibmPlexSansArabic(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: appColors.dark,
                            ),
                          ),
                        );
                      }

                      if (snapshot.hasError) {
                        return Container(
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
                          child: Text(
                            "حدث خطأ أثناء تحميل الإحصائيات.",
                            style: GoogleFonts.ibmPlexSansArabic(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: Colors.red,
                            ),
                          ),
                        );
                      }

                      final docs = snapshot.data?.docs ?? [];
                      final totalUsers = docs.length;

                      num totalPoints = 0;
                      num totalCarbon = 0;
                      num totalCompletedTasks = 0; // ✅ مجموع completedTask

                      for (final doc in docs) {
                        final data = doc.data();

                        // points
                        final p = data['points'];
                        if (p is num) {
                          totalPoints += p;
                        } else if (p != null) {
                          totalPoints += num.tryParse(p.toString()) ?? 0;
                        }

                        // totalCarbonSaved
                        final c = data['totalCarbonSaved'];
                        if (c is num) {
                          totalCarbon += c;
                        } else if (c != null) {
                          totalCarbon += num.tryParse(c.toString()) ?? 0;
                        }

                        // ✅ completedTask
                        final ct = data['completedTask'];
                        if (ct is num) {
                          totalCompletedTasks += ct;
                        } else if (ct != null) {
                          totalCompletedTasks +=
                              num.tryParse(ct.toString()) ?? 0;
                        }
                      }

                      return Container(
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
                                color: appColors.dark,
                              ),
                            ),
                            const SizedBox(height: 12),

                            // إجمالي المستخدمين (الموثقين فقط)
                            _buildStat(
                              "إجمالي المستخدمين الموثقين",
                              totalUsers.toString(),
                            ),
                            _divider(),

                            // ✅ إجمالي المهام المكتملة (من حقل completedTask في users)
                            _buildStat(
                              "إجمالي المهام المستدامة المكتملة",
                              totalCompletedTasks.toStringAsFixed(0),
                            ),
                            _divider(),

                            // مجموع النقاط
                            _buildStat(
                              "إجمالي النقاط الموزعة",
                              totalPoints.toStringAsFixed(0),
                            ),
                            _divider(),

                            // مجموع الكربون
                            _buildStat(
                              "الأثر الكربوني الإجمالي",
                              "${totalCarbon.toStringAsFixed(2)} كجم",
                            ),
                          ],
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 16),

                  // 📨 خانة الطلبات الجديدة — تضغطها تروح لـ admin_task_check
                  StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: FirebaseFirestore.instance
                        .collection('submissions')
                        .where('status', isEqualTo: 'pending')
                        .snapshots(),
                    builder: (context, snap) {
                      final isLoading =
                          snap.connectionState == ConnectionState.waiting;
                      final count = (snap.data?.docs.length ?? 0);

                      return InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const AdminTaskCheckPage(),
                            ),
                          );
                        },
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 16,
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
                            border: Border.all(
                              color: appColors.primary.withOpacity(0.2),
                              width: 1.5,
                            ),
                          ),
                          child: Row(
                            children: [
                              // أيقونة
                              Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  color: appColors.primary.withOpacity(.12),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.fact_check_outlined,
                                  color: appColors.primary,
                                ),
                              ),
                              const SizedBox(width: 12),

                              // النصوص
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'طلبات مهام جديدة للمراجعة',
                                      style: GoogleFonts.ibmPlexSansArabic(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                        color: appColors.dark,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      isLoading
                                          ? 'جاري التحميل...'
                                          : (count == 0
                                                ? 'لا توجد طلبات جديدة حالياً'
                                                : 'لديك $count طلب${count == 1 ? '' : 'ات'} بانتظار الاعتماد'),
                                      style: GoogleFonts.ibmPlexSansArabic(
                                        fontSize: 13.5,
                                        color: Colors.grey[700],
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              // شارة العدد + سهم
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: appColors.primary.withOpacity(.12),
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Text(
                                      isLoading ? '—' : '$count',
                                      style: GoogleFonts.ibmPlexSansArabic(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w700,
                                        color: appColors.primary,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  const Icon(
                                    Icons.chevron_left,
                                    color: appColors.primary,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
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
            color: appColors.dark,
          ),
        ),
        Text(
          value,
          style: GoogleFonts.ibmPlexSansArabic(
            fontSize: 15,
            fontWeight: FontWeight.w400,
            color: appColors.sea,
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
