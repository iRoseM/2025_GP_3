import 'dart:math' as math;
import 'dart:async';
import 'package:flutter/material.dart';
import 'services/background_container.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/animation.dart';
import 'rewards.dart';
import 'package:showcaseview/showcaseview.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart'; // أضيفي هذا السطر
import 'dart:ui' as ui;

import 'task.dart';
import 'community.dart';
import 'profile.dart';
import 'levels.dart';
import 'map.dart';
import 'services/fcm_service.dart';
import 'services/bottom_nav.dart';
import 'services/connection.dart';
import 'services/title_header.dart';
import '../services/app_colors.dart';
import 'package:google_fonts/google_fonts.dart';
import 'article.dart';
import 'levels.dart';

class homePage extends StatefulWidget {
  const homePage({super.key});
  @override
  State<homePage> createState() => _homePageState();
}

class _homePageState extends State<homePage> with TickerProviderStateMixin {
  final ScrollController _scrollCtrl = ScrollController(); // << هنا بالضبط
  final int _currentIndex = 0;
  final GlobalKey _profileKey = GlobalKey();
  final GlobalKey _pointsKey = GlobalKey();
  final GlobalKey _summaryKey = GlobalKey(); // الكربون + الداشبورد
  final GlobalKey _ecoLandKey = GlobalKey();
  final GlobalKey _navKey = GlobalKey();
  final GlobalKey _ecoLandAnchorKey = GlobalKey(); // مرساة للسكرول
  final GlobalKey _bannerKey = GlobalKey();
  final GlobalKey _friendsKey = GlobalKey();
  final GlobalKey _carbonKey = GlobalKey(); // كرت "إجمالي خفض الكربون"
  final GlobalKey<_homePageState> _homePageKey = GlobalKey();

  OverlayEntry? _skipEntry;
  bool _tourRunning = false;
  bool _phase2Started = false; // علشان ما نكرر تشغيل المرحلة الثانية
  BuildContext? _scCtx; // نخزّن showcaseContext
  bool _ecoLandExpanded = false;
  DateTime _cursorDate = DateTime.now();
  bool _carbonExpanded = false;

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

  // إخفاء زر تخطي الجولة
  void _hideSkipOverlay() {
    _skipEntry?..remove();
    _skipEntry = null;
  }

  late final AnimationController _bgCtrl;
  AnimationController? _floatingCtrl;
  bool _didScheduleShowcase = false; // ✅ عشان ما نعيده كل build

  @override
  void initState() {
    super.initState();

    // أنيميشن الخلفية
    _bgCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 14),
    )..repeat();

    // أنيميشن الكرت الطاير
    _floatingCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat(reverse: true);

    // FCM + توكن
    _initHome();

    // تأكد من وجود حقول الكربون في user
    ensureUserCarbonFields();
    StreakService.initializeStreakFields();
  }

  Future<void> _initHome() async {
    // 🔔 طلب الإذن + حفظ التوكن + الاستماع
    FCMService.requestPermissionAndSaveToken();
    FCMService.listenToForegroundMessages();
    saveFcmToken();
    StreakService.initializeStreakFields();
  }

  Future<void> _startShowcaseIfNeeded(BuildContext showcaseContext) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final ref = FirebaseFirestore.instance.collection('users').doc(user.uid);
    final snap = await ref.get();
    final data = snap.data();

    if (data != null && data['isOnboardingSeen'] == true) return;
    await ref.set({'isOnboardingSeen': true}, SetOptions(merge: true));
    _tourRunning = true;
    // _showSkipOverlay();
    ShowCaseWidget.of(
      showcaseContext,
    )?.startShowCase([_profileKey, _pointsKey, _carbonKey, _summaryKey]);
  }

  Future<void> _scrollToAnchor(GlobalKey key) async {
    final ctx = key.currentContext;
    if (ctx == null) return;
    await Scrollable.ensureVisible(
      ctx,
      alignment: 0.1,
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeInOut,
    );
    await Future.delayed(const Duration(milliseconds: 100));
  }

  @override
  void dispose() {
    _bgCtrl.dispose();
    _floatingCtrl?.dispose();
    _scrollCtrl.dispose(); // ← ضروري
    super.dispose();
    _hideSkipOverlay();
  }

  Future<void> saveFcmToken() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    if (!await hasInternetConnection()) {
      if (context.mounted) showNoInternetDialog(context);
      return;
    }

    final token = await FirebaseMessaging.instance.getToken();
    if (token != null) {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).update(
        {'fcmToken': token},
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isKeyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;

    return ShowCaseWidget(
      onFinish: () async {
        if (!_phase2Started && _scCtx != null) {
          _phase2Started = true;
          await _scrollToAnchor(_ecoLandAnchorKey);
          final controller = ShowCaseWidget.of(_scCtx!);
          controller?.startShowCase([
            _ecoLandKey,
            _bannerKey,
            _friendsKey,
            _navKey,
          ]);
          // لا نُخفي زر التخطي هنا — ما زلنا في الجولة
        } else {
          // انتهت المرحلة الثانية = نهاية الجولة بالكامل
          _hideSkipOverlay();
          setState(() => _tourRunning = false);
        }
      },
      builder: (showcaseContext) {
        // خزّني الكونتكست حق الـ Showcase عشان نستخدمه في onFinish
        _scCtx ??= showcaseContext;

        // نشغّل الجولة أول مرة بس
        if (!_didScheduleShowcase) {
          _didScheduleShowcase = true;
          _startShowcaseIfNeeded(showcaseContext);
        }
        return Directionality(
          textDirection: ui.TextDirection.rtl,
          child: Stack(
            children: [
              Scaffold(
                extendBody: true,
                backgroundColor: Colors.transparent,
                body: AnimatedBackgroundContainer(
                  child: SafeArea(
                    bottom: false,
                    child: CustomScrollView(
                      controller: _scrollCtrl,
                      slivers: [
                        // ====================== Header ======================
                        SliverToBoxAdapter(
                          child: Builder(
                            builder: (context) {
                              final uid =
                                  FirebaseAuth.instance.currentUser?.uid;

                              // لو ما فيه مستخدم مسجل
                              if (uid == null) {
                                return Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    16,
                                    16,
                                    12,
                                  ),
                                  child: Row(
                                    children: [
                                      // صورة البروفايل → تودّي لصفحة البروفايل
                                      Material(
                                        color: Colors.transparent,
                                        child: InkWell(
                                          borderRadius: BorderRadius.circular(
                                            999,
                                          ),
                                          onTap: () {
                                            Navigator.of(context).push(
                                              MaterialPageRoute(
                                                builder: (_) =>
                                                    const profilePage(),
                                              ),
                                            );
                                          },
                                          child: Container(
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              gradient: LinearGradient(
                                                colors: [
                                                  appColors.primary.withOpacity(
                                                    .2,
                                                  ),
                                                  appColors.sea.withOpacity(.1),
                                                ],
                                              ),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: appColors.primary
                                                      .withOpacity(.2),
                                                  blurRadius: 12,
                                                  offset: const Offset(0, 4),
                                                ),
                                              ],
                                            ),
                                            child: const CircleAvatar(
                                              radius: 24,
                                              backgroundColor:
                                                  Colors.transparent,
                                              child: Icon(
                                                Icons.person_outline,
                                                color: appColors.primary,
                                                size: 28,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),

                                      const SizedBox(width: 12),

                                      const Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'مرحبًا 👋',
                                              style: TextStyle(
                                                fontSize: 20,
                                                fontWeight: FontWeight.w800,
                                                color: appColors.dark,
                                              ),
                                            ),
                                            Text(
                                              'لنجعل اليوم مميزاً!',
                                              style: TextStyle(
                                                fontSize: 13,
                                                color: appColors.sea,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      _PointsChip(points: 0, onTap: () {}),
                                    ],
                                  ),
                                );
                              }

                              // لو فيه مستخدم، نجلب بياناته من Firestore
                              return StreamBuilder<
                                DocumentSnapshot<Map<String, dynamic>>
                              >(
                                stream: FirebaseFirestore.instance
                                    .collection('users')
                                    .doc(uid)
                                    .snapshots(),
                                builder: (context, snap) {
                                  // 🔸 لو صار خطأ (غالباً انقطاع نت أو صلاحيات)
                                  if (snap.hasError) {
                                    return Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        16,
                                        16,
                                        16,
                                        12,
                                      ),
                                      child: Row(
                                        children: const [
                                          Icon(
                                            Icons.person_outline,
                                            color: appColors.primary,
                                            size: 48,
                                          ),
                                          SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  'مرحبًا 👋',
                                                  style: TextStyle(
                                                    fontSize: 20,
                                                    fontWeight: FontWeight.w800,
                                                    color: appColors.dark,
                                                  ),
                                                ),
                                                Text(
                                                  'تحقق من اتصالك بالإنترنت',
                                                  style: TextStyle(
                                                    fontSize: 13,
                                                    color: appColors.sea,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }

                                  // 🔸 لو البيانات ما وصلت بعد
                                  if (snap.connectionState ==
                                      ConnectionState.waiting) {
                                    return const Padding(
                                      padding: EdgeInsets.fromLTRB(
                                        16,
                                        16,
                                        16,
                                        12,
                                      ),
                                      child: Row(
                                        children: [
                                          CircularProgressIndicator(
                                            color: appColors.primary,
                                          ),
                                          SizedBox(width: 16),
                                          Text(
                                            'جاري التحميل...',
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w600,
                                              color: appColors.dark,
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }

                                  // 🔸 لو البيانات جاهزة نعرضها
                                  final data = snap.data?.data();
                                  final username =
                                      (data?['username'] ?? 'مستخدم')
                                          .toString();

                                  int _asInt(dynamic v) {
                                    if (v is int) return v;
                                    if (v is double) return v.toInt();
                                    if (v == null) return 0;
                                    return int.tryParse('$v') ?? 0;
                                  }

                                  final int points = _asInt(data?['points']);

                                  return Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      16,
                                      16,
                                      16,
                                      12,
                                    ),
                                    child: Row(
                                      children: [
                                        // صورة البروفايل → Showcase + شرح + تخطي
                                        StreamBuilder<
                                          DocumentSnapshot<Map<String, dynamic>>
                                        >(
                                          stream:
                                              FirebaseAuth
                                                      .instance
                                                      .currentUser ==
                                                  null
                                              ? const Stream.empty()
                                              : FirebaseFirestore.instance
                                                    .collection('users')
                                                    .doc(
                                                      FirebaseAuth
                                                          .instance
                                                          .currentUser!
                                                          .uid,
                                                    )
                                                    .snapshots(),
                                          builder: (context, snapshot) {
                                            final data = snapshot.data?.data();
                                            final int? pfpIndex =
                                                (data?['pfpIndex'] is int)
                                                ? (data?['pfpIndex'] as int)
                                                : int.tryParse(
                                                    '${data?['pfpIndex'] ?? ''}',
                                                  );
                                            String? avatarPath;
                                            if (pfpIndex != null &&
                                                pfpIndex >= 0 &&
                                                pfpIndex < 8) {
                                              avatarPath =
                                                  'assets/pfp/pfp${pfpIndex + 1}.png';
                                            }

                                            return Showcase.withWidget(
                                              key: _profileKey,
                                              overlayColor: Colors.black
                                                  .withOpacity(
                                                    0.35,
                                                  ), // غامق — يخلي التور واضح
                                              overlayOpacity: 0.35,
                                              blurValue: 0,
                                              container: Builder(
                                                builder: (ctx) => Container(
                                                  padding: const EdgeInsets.all(
                                                    12,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: Colors.white,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          16,
                                                        ),
                                                    boxShadow: [
                                                      BoxShadow(
                                                        color: Colors.black
                                                            .withOpacity(0.12),
                                                        blurRadius: 12,
                                                        offset: const Offset(
                                                          0,
                                                          6,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  child: Directionality(
                                                    textDirection:
                                                        ui.TextDirection.rtl,
                                                    child: Column(
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        const Text(
                                                          "هنا ملفك الشخصي",
                                                          style: TextStyle(
                                                            fontWeight:
                                                                FontWeight.w800,
                                                            fontSize: 16,
                                                            color:
                                                                Color.fromARGB(
                                                                  255,
                                                                  60,
                                                                  59,
                                                                  59,
                                                                ),
                                                          ),
                                                        ),
                                                        const SizedBox(
                                                          height: 8,
                                                        ),
                                                        const Text(
                                                          'من هنا يمكن متابعة الملف، تعديل الصورة واسم المستخدم، والاطلاع على الإنجازات.',
                                                          textDirection: ui
                                                              .TextDirection
                                                              .rtl, // 👈 أضف هذا
                                                          style: TextStyle(
                                                            fontSize: 13,
                                                            height: 1.6,
                                                            color:
                                                                Colors.black87,
                                                          ),
                                                        ),
                                                        const SizedBox(
                                                          height: 8,
                                                        ),
                                                        const Align(
                                                          alignment: Alignment
                                                              .centerRight,
                                                          child: Text(
                                                            'للتنقل اضغط خارج البالون، ويمكن استخدام زر «تخطي الجولة» أدناه.',
                                                            style: TextStyle(
                                                              fontSize: 11,
                                                              color: Colors
                                                                  .black54,
                                                            ),
                                                          ),
                                                        ),
                                                        // ⭐ Skip Button (Inside Bubble)
                                                        Align(
                                                          alignment: Alignment
                                                              .centerLeft,
                                                          child: TextButton(
                                                            onPressed: () {
                                                              final ctrl =
                                                                  ShowCaseWidget.of(
                                                                    _scCtx!,
                                                                  );
                                                              ctrl?.dismiss();
                                                            },
                                                            child: const Text(
                                                              'تخطي الجولة',
                                                              style: TextStyle(
                                                                color: appColors
                                                                    .primary,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w800,
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              ),

                                              child: Material(
                                                color: Colors.transparent,
                                                child: InkWell(
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                        999,
                                                      ),
                                                  onTap: () {
                                                    Navigator.of(context).push(
                                                      MaterialPageRoute(
                                                        builder: (_) =>
                                                            const profilePage(),
                                                      ),
                                                    );
                                                  },
                                                  child: Container(
                                                    decoration: BoxDecoration(
                                                      shape: BoxShape.circle,
                                                      gradient: LinearGradient(
                                                        colors: [
                                                          appColors.primary
                                                              .withOpacity(.2),
                                                          appColors.mint
                                                              .withOpacity(.1),
                                                        ],
                                                      ),
                                                      boxShadow: [
                                                        BoxShadow(
                                                          color: appColors
                                                              .primary
                                                              .withOpacity(.2),
                                                          blurRadius: 12,
                                                          offset: const Offset(
                                                            0,
                                                            4,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                    child: CircleAvatar(
                                                      radius: 24,
                                                      backgroundColor:
                                                          Colors.transparent,
                                                      backgroundImage:
                                                          (avatarPath != null)
                                                          ? AssetImage(
                                                              avatarPath,
                                                            )
                                                          : null,
                                                      child:
                                                          (avatarPath == null)
                                                          ? const Icon(
                                                              Icons
                                                                  .person_outline,
                                                              color: appColors
                                                                  .primary,
                                                              size: 28,
                                                            )
                                                          : null,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            );
                                          },
                                        ),

                                        const SizedBox(width: 12),

                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              if (snap.connectionState ==
                                                  ConnectionState.waiting)
                                                const Text(
                                                  'مرحبًا 👋',
                                                  style: TextStyle(
                                                    fontSize: 20,
                                                    fontWeight: FontWeight.w800,
                                                    color: appColors.dark,
                                                  ),
                                                )
                                              else
                                                Text(
                                                  'مرحبًا، $username 👋',
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    fontSize: 20,
                                                    fontWeight: FontWeight.w800,
                                                    color: appColors.dark,
                                                  ),
                                                ),
                                              const Text(
                                                'لنجعل اليوم مميزاً!',
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  color: appColors.sea,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Showcase.withWidget(
                                          key: _pointsKey,
                                          overlayColor: Colors.black
                                              .withOpacity(
                                                0.35,
                                              ), // غامق — يخلي التور واضح
                                          overlayOpacity: 0.35,
                                          blurValue: 0,
                                          container: Builder(
                                            builder: (ctx) {
                                              final size = MediaQuery.of(
                                                ctx,
                                              ).size;

                                              // مقاس ديناميكي للصورة (أكبر) مع حد أقصى
                                              final double imgH = math.min(
                                                size.width * 0.65,
                                                300,
                                              );

                                              return SizedBox(
                                                width: size.width,
                                                height:
                                                    300, // رفعنا الارتفاع عشان يسمح للنزلة
                                                child: Stack(
                                                  clipBehavior: Clip.none,
                                                  children: [
                                                    // البالون الأبيض
                                                    Positioned(
                                                      top: 40,
                                                      left: 20,
                                                      child: Container(
                                                        width: 260,
                                                        padding:
                                                            const EdgeInsets.all(
                                                              14,
                                                            ),
                                                        decoration: BoxDecoration(
                                                          color: Colors.white,
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                16,
                                                              ),
                                                          boxShadow: [
                                                            BoxShadow(
                                                              color: Colors
                                                                  .black
                                                                  .withOpacity(
                                                                    0.12,
                                                                  ),
                                                              blurRadius: 12,
                                                              offset:
                                                                  const Offset(
                                                                    0,
                                                                    6,
                                                                  ),
                                                            ),
                                                          ],
                                                        ),
                                                        child: Directionality(
                                                          textDirection: ui
                                                              .TextDirection
                                                              .rtl,
                                                          child: Column(
                                                            mainAxisSize:
                                                                MainAxisSize
                                                                    .min,
                                                            crossAxisAlignment:
                                                                CrossAxisAlignment
                                                                    .start,
                                                            children: [
                                                              Text(
                                                                "هنا نقاطك ",
                                                                style: TextStyle(
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w800,
                                                                  fontSize: 16,
                                                                  color:
                                                                      appColors
                                                                          .dark,
                                                                ),
                                                              ),
                                                              SizedBox(
                                                                height: 8,
                                                              ),
                                                              Text(
                                                                'كل مهمة تُنجَز تضيف نقاطًا إلى رصيدك هنا، ويمكن استبدالها في صفحة الجوائز.',
                                                                style: TextStyle(
                                                                  fontSize: 13,
                                                                  height: 1.5,
                                                                  color: Colors
                                                                      .black87,
                                                                ),
                                                              ),
                                                              Align(
                                                                alignment: Alignment
                                                                    .centerLeft,
                                                                child: TextButton(
                                                                  onPressed: () {
                                                                    ShowCaseWidget.of(
                                                                      _scCtx!,
                                                                    ).dismiss();
                                                                  },
                                                                  child: const Text(
                                                                    'تخطي الجولة',
                                                                    style: TextStyle(
                                                                      color: appColors
                                                                          .primary,
                                                                      fontWeight:
                                                                          FontWeight
                                                                              .w800,
                                                                    ),
                                                                  ),
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                      ),
                                                    ),

                                                    // صورة Nameer — أكبر ولأسفل
                                                    Positioned(
                                                      right: -14, // أقرب للحافة
                                                      bottom:
                                                          -60, // نزّلناها لتحت
                                                      child: Image.asset(
                                                        'assets/img/nameerLeft.png',
                                                        height:
                                                            imgH, // أكبر بشكل متناسب
                                                        fit: BoxFit.contain,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              );
                                            },
                                          ),
                                          child: _PointsChip(
                                            points: points,
                                            onTap: () {
                                              Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                  builder: (_) =>
                                                      const RewardsPage(),
                                                ),
                                              );
                                            },
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                        ),
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                            child: Align(
                              alignment: Alignment.centerRight, // أو centerLeft
                              child: Builder(
                                builder: (context) {
                                  final uid =
                                      FirebaseAuth.instance.currentUser?.uid;
                                  if (uid == null) return const SizedBox();
                                  return StreakTracker(userId: uid);
                                },
                              ),
                            ),
                          ),
                        ),

                        // === إجمالي خفض الكربون ===
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                            child: Showcase.withWidget(
                              key: _carbonKey,
                              overlayColor: Colors.black.withOpacity(0.35),
                              overlayOpacity: 0.35,
                              blurValue: 0,

                              container: Builder(
                                builder: (ctx) => Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(20),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.15),
                                        blurRadius: 16,
                                        offset: const Offset(0, 8),
                                      ),
                                    ],
                                    border: Border.all(
                                      color: appColors.primary.withOpacity(
                                        0.15,
                                      ),
                                      width: 1.5,
                                    ),
                                  ),
                                  child: Directionality(
                                    textDirection: ui.TextDirection.rtl,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.all(6),
                                              decoration: BoxDecoration(
                                                color: appColors.primary
                                                    .withOpacity(0.1),
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                              ),
                                              child: const Icon(
                                                Icons.info_outline,
                                                color: appColors.primary,
                                                size: 20,
                                              ),
                                            ),
                                            const SizedBox(width: 10),
                                            const Text(
                                              'إجمالي خفض الكربون',
                                              style: TextStyle(
                                                fontWeight: FontWeight.w900,
                                                fontSize: 18,
                                                color: appColors.dark,
                                              ),
                                            ),
                                          ],
                                        ),

                                        const SizedBox(height: 12),

                                        const Text(
                                          'هذا المؤشر يوضح مجموع الأثر البيئي الذي حققته من كل مهامك، '
                                          'مقاسة بالكيلوغرام من مكافئ ثاني أكسيد الكربون (kg CO₂e). '
                                          'كلما زاد الرقم، كان تأثيرك الإيجابي على البيئة أكبر 🌿🌍.\n\n'
                                          '💡 اضغط على الكارد لعرض التطور التفصيلي للكربون.',
                                          style: TextStyle(
                                            fontSize: 14,
                                            height: 1.6,
                                            color: Colors.black87,
                                          ),
                                        ),

                                        const SizedBox(height: 16),

                                        Align(
                                          alignment: Alignment.centerLeft,
                                          child: TextButton.icon(
                                            onPressed: () {
                                              ShowCaseWidget.of(
                                                _scCtx!,
                                              ).dismiss();
                                            },
                                            icon: const Icon(
                                              Icons.close,
                                              size: 16,
                                            ),
                                            label: const Text(
                                              'تخطي الجولة',
                                              style: TextStyle(
                                                color: appColors.primary,
                                                fontWeight: FontWeight.w800,
                                                fontSize: 14,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),

                              // ⬇️ بس هذا الكود فقط
                              child: const _CarbonFootprintCard(),
                            ),
                          ),
                        ),

                        const SliverToBoxAdapter(child: SizedBox(height: 16)),

                        // === بلوك الأرض مع العنوان داخل نفس الحاوية ===
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: RepaintBoundary(
                              key: _ecoLandAnchorKey,
                              child: Showcase.withWidget(
                                key: _ecoLandKey,
                                overlayColor: Colors.black.withOpacity(0.35),
                                overlayOpacity: 0.35,
                                blurValue: 0,

                                container: Builder(
                                  builder: (ctx) => Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(16),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.12),
                                          blurRadius: 12,
                                          offset: const Offset(0, 6),
                                        ),
                                      ],
                                    ),
                                    child: Directionality(
                                      textDirection: ui.TextDirection.rtl,
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Text(
                                            'EcoLand الخاصة بك',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w800,
                                              fontSize: 16,
                                              color: appColors.dark,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          const Text(
                                            'ابنِ عالمك الخاص: كل مهمة تُنجَز تضيف عنصرًا جديدًا لأرضك وتفتح ترقيات ممتعة.',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              fontSize: 13,
                                              height: 1.6,
                                              color: Colors.black87,
                                            ),
                                          ),
                                          const SizedBox(height: 16),
                                          Align(
                                            alignment: Alignment.centerLeft,
                                            child: TextButton(
                                              onPressed: () {
                                                ShowCaseWidget.of(
                                                  _scCtx!,
                                                )?.dismiss();
                                              },
                                              child: const Text(
                                                'تخطي الجولة',
                                                style: TextStyle(
                                                  color: appColors.primary,
                                                  fontWeight: FontWeight.w800,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),

                                child: InkWell(
                                  borderRadius: BorderRadius.circular(20),
                                  onTap: () {
                                    setState(() {
                                      _ecoLandExpanded = !_ecoLandExpanded;
                                    });
                                  },
                                  child: Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(20),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.grey.withOpacity(0.12),
                                          blurRadius: 10,
                                          offset: const Offset(0, 4),
                                        ),
                                      ],
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        // 🔹 الهيدر
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(
                                              'EcoLand',
                                              style:
                                                  GoogleFonts.ibmPlexSansArabic(
                                                    fontSize: 18,
                                                    fontWeight: FontWeight.w800,
                                                    color: appColors.dark,
                                                  ),
                                            ),
                                            Icon(
                                              _ecoLandExpanded
                                                  ? Icons.keyboard_arrow_up
                                                  : Icons.keyboard_arrow_down,
                                              color: appColors.primary,
                                            ),
                                          ],
                                        ),

                                        const SizedBox(height: 6),

                                        Text(
                                          'تابع تقدمك في إكمال المهام',
                                          style: GoogleFonts.ibmPlexSansArabic(
                                            fontSize: 13,
                                            color: Colors.grey[600],
                                          ),
                                        ),

                                        const SizedBox(height: 14),

                                        // 🌍 EcoLand — ظاهرة دايم
                                        const SizedBox(
                                          width: double.infinity,
                                          height: 170,
                                          child: IsoLand(
                                            rows: 6,
                                            cols: 6,
                                            height: 150,
                                            thickness: 14,
                                            topColor: appColors.mint,
                                            sideColor: appColors.tealSoft,
                                            gridColor: appColors.sea,
                                            gridOpacity: .08,
                                          ),
                                        ),

                                        // 👇 الاكسباند (التشارت فقط)
                                        AnimatedSize(
                                          duration: const Duration(
                                            milliseconds: 320,
                                          ),
                                          curve: Curves.easeInOut,
                                          child: _ecoLandExpanded
                                              ? const Padding(
                                                  padding: EdgeInsets.only(
                                                    top: 16,
                                                  ),
                                                  child: SizedBox(
                                                    height: 400,
                                                    child:
                                                        _UserTaskProgressCard(),
                                                  ),
                                                )
                                              : const SizedBox.shrink(),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SliverToBoxAdapter(child: SizedBox(height: 16)),
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Builder(
                              builder: (context) {
                                final now = DateTime.now();
                                final today =
                                    "${now.year.toString().padLeft(4, '0')}-"
                                    "${now.month.toString().padLeft(2, '0')}-"
                                    "${now.day.toString().padLeft(2, '0')}";

                                return StreamBuilder<DocumentSnapshot>(
                                  stream: FirebaseFirestore.instance
                                      .collection('dailyTasks')
                                      .doc(
                                        FirebaseAuth.instance.currentUser?.uid,
                                      ) // ← document المستخدم
                                      .collection(
                                        'tasks',
                                      ) // ← sub-collection tasks
                                      .doc(today) // ← document id = التاريخ
                                      .snapshots(),
                                  builder: (context, snapshot) {
                                    // ===== Loading =====
                                    if (snapshot.connectionState ==
                                        ConnectionState.waiting) {
                                      return Container(
                                        height: 100,
                                        decoration: BoxDecoration(
                                          color: Colors.grey[100],
                                          borderRadius: BorderRadius.circular(
                                            20,
                                          ),
                                        ),
                                        child: const Center(
                                          child: CircularProgressIndicator(
                                            color: appColors.primary,
                                          ),
                                        ),
                                      );
                                    }

                                    // ===== No Task =====
                                    if (!snapshot.hasData ||
                                        !snapshot.data!.exists) {
                                      return Container(
                                        height: 100,
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            colors: [
                                              appColors.primary.withOpacity(
                                                0.1,
                                              ),
                                              appColors.mint.withOpacity(0.1),
                                            ],
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            20,
                                          ),
                                          border: Border.all(
                                            color: appColors.primary
                                                .withOpacity(0.2),
                                          ),
                                        ),
                                        child: Center(
                                          child: Text(
                                            'لا توجد مهمة حتى الآن',
                                            style:
                                                GoogleFonts.ibmPlexSansArabic(
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w600,
                                                  color: appColors.dark
                                                      .withOpacity(0.6),
                                                ),
                                          ),
                                        ),
                                      );
                                    }

                                    final taskData =
                                        snapshot.data!.data()
                                            as Map<String, dynamic>;

                                    final taskTitle =
                                        taskData['title'] ?? 'مهمة بيئية';
                                    final taskDescription =
                                        taskData['description'] ?? '';
                                    final taskCategory =
                                        taskData['category'] ?? '';
                                    final taskPoints =
                                        (taskData['points'] ?? 10) as int;
                                    final validationStrategy =
                                        taskData['validationStrategy'] ??
                                        'photo';

                                    final status =
                                        taskData['status'] ?? 'pending';
                                    final isCompleted = status == 'completed';

                                    return Container(
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: isCompleted
                                              ? [
                                                  Colors.green.withOpacity(
                                                    0.12,
                                                  ),
                                                  Colors.green.withOpacity(
                                                    0.06,
                                                  ),
                                                ]
                                              : [
                                                  Colors.white.withOpacity(
                                                    0.95,
                                                  ),
                                                  Colors.white.withOpacity(
                                                    0.85,
                                                  ),
                                                ],
                                        ),
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(
                                          color: isCompleted
                                              ? Colors.green
                                              : appColors.primary.withOpacity(
                                                  0.2,
                                                ),
                                        ),
                                      ),
                                      child: Material(
                                        color: Colors.transparent,
                                        child: InkWell(
                                          borderRadius: BorderRadius.circular(
                                            20,
                                          ),
                                          onTap: isCompleted
                                              ? null
                                              : () async {
                                                  final uid =
                                                      FirebaseAuth
                                                          .instance
                                                          .currentUser
                                                          ?.uid ??
                                                      '';

                                                  final userTaskDocId =
                                                      uid.isEmpty
                                                      ? ''
                                                      : '${uid}_$today';

                                                  final taskDataForSheet = {
                                                    'taskId':
                                                        taskData['taskId'] ??
                                                        snapshot.data!.id,
                                                    'title': taskTitle,
                                                    'description':
                                                        taskDescription,
                                                    'points': taskPoints,
                                                    'validationStrategy':
                                                        validationStrategy,
                                                    'category': taskCategory,
                                                    'id':
                                                        taskData['taskId'] ??
                                                        snapshot.data!.id,
                                                    'status': status,
                                                  };

                                                  // ✅ التفريق بين المقال والتصوير
                                                  if (validationStrategy ==
                                                      "التحقق عبر اجراء اختبار قصير") {
                                                    Navigator.push(
                                                      context,
                                                      MaterialPageRoute(
                                                        builder: (_) => ArticlePage(
                                                          userTaskDocId:
                                                              userTaskDocId,
                                                          taskId:
                                                              taskDataForSheet['id'],
                                                        ),
                                                      ),
                                                    );
                                                  } else {
                                                    final result =
                                                        await showCompleteTaskSheet(
                                                          context,
                                                          taskDataForSheet,
                                                          selectedDay:
                                                              DateTime.now(),
                                                          userTaskDocId:
                                                              userTaskDocId,
                                                        );

                                                    if (result == true &&
                                                        mounted) {
                                                      try {
                                                        final uid =
                                                            FirebaseAuth
                                                                .instance
                                                                .currentUser
                                                                ?.uid ??
                                                            '';
                                                        final today =
                                                            DateFormat(
                                                              'yyyy-MM-dd',
                                                            ).format(
                                                              DateTime.now(),
                                                            );
                                                        final todayKey = today
                                                            .replaceAll(
                                                              '-',
                                                              '',
                                                            );

                                                        // ✅ 1. تحديث dailyTasks
                                                        await FirebaseFirestore
                                                            .instance
                                                            .collection(
                                                              'dailyTasks',
                                                            )
                                                            .doc(uid)
                                                            .collection('tasks')
                                                            .doc(today)
                                                            .set(
                                                              {
                                                                'completed':
                                                                    true,
                                                                'completedAt':
                                                                    FieldValue.serverTimestamp(),
                                                                'status':
                                                                    'completed',
                                                              },
                                                              SetOptions(
                                                                merge: true,
                                                              ),
                                                            );

                                                        // ✅ 2. تحديث userTasks (باستخدام نفس بيانات taskDataForSheet)
                                                        await FirebaseFirestore
                                                            .instance
                                                            .collection(
                                                              'userTasks',
                                                            )
                                                            .doc(
                                                              '${uid}_$todayKey',
                                                            )
                                                            .set(
                                                              {
                                                                'userId': uid,
                                                                'taskId':
                                                                    taskDataForSheet['taskId'] ??
                                                                    taskDataForSheet['id'],
                                                                'taskTitle':
                                                                    taskDataForSheet['title'] ??
                                                                    'مهمة بيئية',
                                                                'taskDescription':
                                                                    taskDataForSheet['description'] ??
                                                                    '',
                                                                'taskPoints':
                                                                    taskDataForSheet['points'] ??
                                                                    10,
                                                                'taskValidation':
                                                                    taskDataForSheet['validationStrategy'] ??
                                                                    'photo',
                                                                'category':
                                                                    taskDataForSheet['category'] ??
                                                                    '',
                                                                'selectedAt':
                                                                    Timestamp.fromDate(
                                                                      DateTime.now(),
                                                                    ),
                                                                'status':
                                                                    'completed',
                                                                'completedAt':
                                                                    FieldValue.serverTimestamp(),
                                                                'ignored':
                                                                    false,
                                                                'ignoredAt':
                                                                    null,
                                                              },
                                                              SetOptions(
                                                                merge: true,
                                                              ),
                                                            );

                                                        print(
                                                          '✅ Tasks updated successfully',
                                                        );
                                                      } catch (e) {
                                                        print(
                                                          '❌ Error updating tasks: $e',
                                                        );
                                                      }
                                                    }
                                                  }
                                                },
                                          child: Padding(
                                            padding: const EdgeInsets.all(16),
                                            child: Row(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.center,
                                              children: [
                                                // Icon
                                                Container(
                                                  padding: const EdgeInsets.all(
                                                    10,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: isCompleted
                                                        ? Colors.green
                                                              .withOpacity(0.15)
                                                        : appColors.primary
                                                              .withOpacity(0.1),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          14,
                                                        ),
                                                  ),
                                                  child: Icon(
                                                    isCompleted
                                                        ? Icons.check_circle
                                                        : _getCategoryIcon(
                                                            taskCategory,
                                                          ),
                                                    color: isCompleted
                                                        ? Colors.green
                                                        : appColors.primary,
                                                    size: 24,
                                                  ),
                                                ),

                                                const SizedBox(width: 12),

                                                // Text
                                                Expanded(
                                                  child: Text(
                                                    isCompleted
                                                        ? 'أحسنت 👏 تم إنجاز مهمة اليوم'
                                                        : taskDescription,
                                                    style:
                                                        GoogleFonts.ibmPlexSansArabic(
                                                          fontSize: 13,
                                                          height: 1.5,
                                                          fontWeight:
                                                              isCompleted
                                                              ? FontWeight.w600
                                                              : FontWeight
                                                                    .normal,
                                                        ),
                                                  ),
                                                ),

                                                const SizedBox(width: 8),

                                                // Points
                                                Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 10,
                                                        vertical: 4,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color: isCompleted
                                                        ? Colors.green
                                                              .withOpacity(0.15)
                                                        : appColors.primary
                                                              .withOpacity(0.1),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          999,
                                                        ),
                                                  ),
                                                  child: Row(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      Icon(
                                                        isCompleted
                                                            ? Icons.check
                                                            : Icons
                                                                  .stars_rounded,
                                                        color: isCompleted
                                                            ? Colors.green
                                                            : appColors.primary,
                                                        size: 16,
                                                      ),
                                                      const SizedBox(width: 4),
                                                      Text(
                                                        isCompleted
                                                            ? 'تم'
                                                            : '$taskPoints',
                                                        style:
                                                            GoogleFonts.ibmPlexSansArabic(
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w700,
                                                            ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                );
                              },
                            ),
                          ),
                        ),

                        const SliverToBoxAdapter(child: SizedBox(height: 16)),
                        // قائمة المتصدرين
                        SliverToBoxAdapter(child: const TopLeaderboardCard()),
                        const SliverToBoxAdapter(child: SizedBox(height: 16)),

                        // Banner
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Showcase.withWidget(
                              key: _bannerKey,
                              overlayColor: Colors.black.withOpacity(0.35),
                              overlayOpacity: 0.35,
                              blurValue: 0,

                              // 👇 مهم جداً لإضافة ctx
                              container: Builder(
                                builder: (ctx) => Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(16),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(.12),
                                        blurRadius: 12,
                                        offset: const Offset(0, 6),
                                      ),
                                    ],
                                  ),

                                  child: Directionality(
                                    textDirection: ui.TextDirection.rtl,
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'إعلانات وتحديات سريعة',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 16,
                                            color: appColors.dark,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        const Text(
                                          'ستجد هنا حملات ومهام موسمية تمنح نقاطًا مضاعفة أو جوائز خاصة. اضغط على الإعلان للمشاركة.',
                                          style: TextStyle(
                                            fontSize: 13,
                                            height: 1.6,
                                            color: Colors.black87,
                                          ),
                                        ),

                                        const SizedBox(height: 16),

                                        // ⭐ زر تخطي الجولة
                                        Align(
                                          alignment: Alignment.centerLeft,
                                          child: TextButton(
                                            onPressed: () {
                                              ShowCaseWidget.of(
                                                _scCtx!,
                                              ).dismiss();
                                            },
                                            child: const Text(
                                              'تخطي الجولة',
                                              style: TextStyle(
                                                color: appColors.primary,
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),

                              child: _InlineBanner(
                                label:
                                    'احفظ حيّك نظيفًا - شارك الآن واربح نقاطاً مضاعفة!',
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => const RewardsPage(),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                        const SliverToBoxAdapter(child: SizedBox(height: 16)),

                        // Friends (Title Row)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Showcase.withWidget(
                              key: _friendsKey,
                              overlayColor: Colors.black.withOpacity(0.35),
                              overlayOpacity: 0.35,
                              blurValue: 0,

                              // 👇 نضيف Builder للحصول على ctx
                              container: Builder(
                                builder: (ctx) => Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(16),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(.12),
                                        blurRadius: 12,
                                        offset: const Offset(0, 6),
                                      ),
                                    ],
                                  ),

                                  child: Directionality(
                                    textDirection: ui.TextDirection.rtl,
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'أصدقاؤك ونشاطهم',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 16,
                                            color: appColors.dark,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        const Text(
                                          'تابع سلسلة إنجازات أصدقائك ونقاطهم، وقارِن تقدمك معهم. من هنا يمكنك استعراض الجميع أو إضافة أصدقاء.',
                                          style: TextStyle(
                                            fontSize: 13,
                                            height: 1.6,
                                            color: Colors.black87,
                                          ),
                                        ),

                                        const SizedBox(height: 16),

                                        // ⭐ زر تخطي الجولة
                                        Align(
                                          alignment: Alignment.centerLeft,
                                          child: TextButton(
                                            onPressed: () {
                                              ShowCaseWidget.of(
                                                _scCtx!,
                                              ).dismiss();
                                            },
                                            child: const Text(
                                              'تخطي الجولة',
                                              style: TextStyle(
                                                color: appColors.primary,
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),

                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: appColors.primary.withOpacity(.1),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Icon(
                                      Icons.group,
                                      color: appColors.primary,
                                      size: 20,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  const Expanded(
                                    child: Text(
                                      'أصدقائي',
                                      style: TextStyle(
                                        fontSize: 19,
                                        fontWeight: FontWeight.w800,
                                        color: appColors.dark,
                                      ),
                                    ),
                                  ),

                                  TextButton.icon(
                                    onPressed: () {
                                      hasInternetConnection().then((online) {
                                        if (!online) {
                                          if (!context.mounted) return;
                                          showNoInternetDialog(context);
                                          return;
                                        }
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                const communityPage(),
                                          ),
                                        );
                                      });
                                    },
                                    icon: const Icon(
                                      Icons.arrow_back,
                                      size: 16,
                                    ),
                                    label: const Text('عرض الكل'),
                                    style: TextButton.styleFrom(
                                      foregroundColor: appColors.primary,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 8,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SliverToBoxAdapter(child: SizedBox(height: 12)),
                        // ✅ قسم الأصدقاء الديناميكي
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: _DynamicFriendsSection(),
                          ),
                        ),
                        const SliverToBoxAdapter(child: SizedBox(height: 120)),
                      ],
                    ),
                  ),
                ),
                bottomNavigationBar: isKeyboardOpen
                    ? null
                    : Showcase.withWidget(
                        key: _navKey,
                        overlayColor: Colors.black,
                        overlayOpacity: 0.35,
                        blurValue: 4,
                        container: _buildNavBarHelpBubble(),
                        child: BottomNavPage(
                          currentIndex: _currentIndex,
                          onTap: _onTap,
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  // 🔹 أضيفي هذا في نهاية الملف (قبل آخر قوسين)
  IconData _getCategoryIcon(String category) {
    if (category.contains('تدوير') || category.contains('recycling')) {
      return Icons.recycling_rounded;
    } else if (category.contains('نقل') || category.contains('transport')) {
      return Icons.directions_bus_rounded;
    } else if (category.contains('طاقة') || category.contains('electricity')) {
      return Icons.bolt_rounded;
    } else if (category.contains('ماء') || category.contains('water')) {
      return Icons.water_drop_rounded;
    } else if (category.contains('وعي') || category.contains('awareness')) {
      return Icons.auto_stories_rounded;
    } else {
      return Icons.eco_rounded;
    }
  }

  int calculateStreak(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    final Set<DateTime> activeDays = {};
    DateTime lastActivityDate = DateTime(1970); // تاريخ افتراضي قديم

    for (final doc in docs) {
      final data = doc.data();
      final Timestamp? ts = data['createdAt'];
      if (ts == null) continue;

      final d = ts.toDate();
      final dayOnly = DateTime(d.year, d.month, d.day);
      activeDays.add(dayOnly);

      // تحديث آخر تاريخ نشاط
      if (d.isAfter(lastActivityDate)) {
        lastActivityDate = d;
      }
    }

    // إذا لم يكن هناك أي إنجازات، الستريك = 0
    if (activeDays.isEmpty) return 0;

    // حساب 24 ساعة من آخر نشاط
    final now = DateTime.now();
    final hoursSinceLastActivity = now.difference(lastActivityDate).inHours;

    // إذا مرت أكثر من 24 ساعة منذ آخر نشاط، نعيد الستريك إلى الصفر
    if (hoursSinceLastActivity > 24) {
      return 0;
    }

    // حساب الستريك بشكل عادي
    int streak = 0;
    DateTime cursor = DateTime.now();
    cursor = DateTime(cursor.year, cursor.month, cursor.day);

    while (activeDays.contains(cursor)) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }

    return streak;
  }

  Future<int> calculateStreakWithLastActivity(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return 0;

    // جلب بيانات المستخدم بما فيها lastActivityAt
    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();

    final lastActivity = userDoc.data()?['lastActivityAt'] as Timestamp?;
    if (lastActivity == null) return 0;

    final lastActivityDate = lastActivity.toDate();
    final now = DateTime.now();

    // 🔹 التصحيح: إذا مرت أكثر من 24 ساعة (وليس 24 ساعة بالضبط)
    if (now.difference(lastActivityDate).inHours > 24) {
      return 0;
    }

    // حساب الستريك العادي (حساب الأيام المتتالية)
    final activeDays = <DateTime>{};
    for (final doc in docs) {
      final ts =
          (doc.data()['completedAt'] ?? doc.data()['createdAt']) as Timestamp?;
      if (ts == null) continue;

      final date = ts.toDate();
      final dayOnly = DateTime(date.year, date.month, date.day);
      activeDays.add(dayOnly);
    }

    int streak = 0;
    DateTime cursor = DateTime.now();
    cursor = DateTime(cursor.year, cursor.month, cursor.day);

    // حساب الأيام المتتالية
    while (activeDays.contains(cursor)) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }

    return streak;
  }

  // 💬 بالون شرح شريط التنقل
  Widget _buildNavBarHelpBubble() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.12),
            blurRadius: 12,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: const Directionality(
        textDirection: ui.TextDirection.rtl,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'التنقّل بين صفحات التطبيق',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 16,
                color: appColors.dark,
              ),
            ),
            SizedBox(height: 8),
            Text(
              '• الرئيسية: عرض ملخّص التقدّم والإنجازات.\n'
              '• المهام: قائمة مهام الاستدامة اليومية.\n'
              '• المراحل: متابعة المستويات والإنجازات.\n'
              '• الخريطة: مواقع حاويات ومراكز إعادة التدوير.\n'
              '• الأصدقاء: إضافة الأصدقاء والتفاعل معهم.',
              style: TextStyle(
                fontSize: 13,
                height: 1.6,
                color: Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class StreakTracker extends StatefulWidget {
  final String userId;
  const StreakTracker({super.key, required this.userId});

  @override
  State<StreakTracker> createState() => _StreakTrackerState();
}

class _StreakTrackerState extends State<StreakTracker> {
  @override
  void initState() {
    super.initState();
    // تهيئة حقول الستريك عند التحميل
    StreakService.initializeStreakFields();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return _StreakBadge(days: 0);
        }

        final data = snap.data?.data() ?? {};

        // التحقق من آخر نشاط
        final lastActivity = data['lastActivityAt'] as Timestamp?;
        final int currentStreak = (data['currentStreak'] as int?) ?? 0;

        // إذا لم يكن هناك نشاط مطلقاً
        if (lastActivity == null) {
          return _StreakBadge(days: 0);
        }

        final now = DateTime.now();
        final lastActivityDate = lastActivity.toDate();
        final hoursSinceLastActivity = now.difference(lastActivityDate).inHours;

        // 🔹 التصحيح: إذا مرت أكثر من 24 ساعة (وليس 24 ساعة بالضبط)
        final int displayedStreak = (hoursSinceLastActivity > 24)
            ? 0
            : currentStreak;

        return _StreakBadge(days: displayedStreak);
      },
    );
  }
}

class StreakService {
  static Future<void> updateStreakOnTaskCompletion() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final userRef = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid);

      final userDoc = await userRef.get();
      final data = userDoc.data() ?? {};

      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      final lastActivity = data['lastActivityAt'] as Timestamp?;
      int currentStreak = (data['currentStreak'] as int?) ?? 0;

      print('📊 Streak Debug:');
      print('   - Current streak: $currentStreak');
      print('   - Last activity: $lastActivity');

      // 🔹 أول مرة
      if (lastActivity == null) {
        print('   - First time ever → set streak to 1');
        await userRef.update({
          'currentStreak': 1,
          'lastActivityAt': FieldValue.serverTimestamp(),
        });
        return;
      }

      final lastDate = lastActivity.toDate();
      final lastDay = DateTime(lastDate.year, lastDate.month, lastDate.day);

      final difference = today.difference(lastDay).inDays;

      print('   - Last day: $lastDay');
      print('   - Today: $today');
      print('   - Difference: $difference days');

      if (difference == 0) {
        // نفس اليوم → لا نزيد
        print('   - Same day → keep streak: $currentStreak');
        await userRef.update({'lastActivityAt': FieldValue.serverTimestamp()});
      } else if (difference == 1) {
        // أمس → نزيد الستريك
        final newStreak = currentStreak + 1;
        print('   - Yesterday → increase streak: $newStreak');
        await userRef.update({
          'currentStreak': newStreak,
          'lastActivityAt': FieldValue.serverTimestamp(),
        });
      } else {
        // انقطع أكثر من يوم → نبدأ streak جديد من 1
        print('   - Gap of $difference days → start new streak at 1');
        await userRef.update({
          'currentStreak': 1, // ✅ هنا التصحيح
          'lastActivityAt': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      print('❌ Error updating streak: $e');
    }
  }

  static Future<int> getCurrentStreak() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return 0;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      final data = doc.data() ?? {};
      final lastActivity = data['lastActivityAt'] as Timestamp?;

      if (lastActivity == null) return 0;

      final now = DateTime.now();
      final lastActivityDate = lastActivity.toDate();
      final hoursSinceLastActivity = now.difference(lastActivityDate).inHours;

      // 🔹 التصحيح: إذا مرت أكثر من 24 ساعة (وليس 24 ساعة بالضبط)
      if (hoursSinceLastActivity > 24) {
        // نحدث الحقل في Firebase ليكون متزامناً
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .update({
              'currentStreak': 0,
              'lastActivityAt': lastActivity, // نحافظ على نفس lastActivity
            });
        return 0;
      }

      // إذا مرت أقل من 24 ساعة → نعود القيمة المخزنة
      return data['currentStreak'] as int? ?? 0;
    } catch (e) {
      debugPrint('Error getting streak: $e');
      return 0;
    }
  }

  static Future<void> initializeStreakFields() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final ref = FirebaseFirestore.instance.collection('users').doc(user.uid);
    final snap = await ref.get();

    if (!snap.exists) return;

    final data = snap.data() ?? {};
    final updates = <String, dynamic>{};

    // التأكد من وجود حقول الستريك
    if (!data.containsKey('currentStreak')) {
      updates['currentStreak'] = 0;
    }
    if (!data.containsKey('lastActivityAt')) {
      updates['lastActivityAt'] = null;
    }

    if (updates.isNotEmpty) {
      await ref.set(updates, SetOptions(merge: true));
    }
  }
}

/* ======================= Widgets ======================= */

class _PointsChip extends StatelessWidget {
  final int points;
  final VoidCallback? onTap;
  const _PointsChip({required this.points, this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(100),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          // ✅ gradient حقك (نفس ستايل البانر)
          gradient: const LinearGradient(
            colors: [appColors.primary, appColors.primary, appColors.mint],
            stops: [0.0, 0.5, 1.0],
            begin: Alignment.bottomLeft,
            end: Alignment.topRight,
          ),
          borderRadius: BorderRadius.circular(100),
          boxShadow: [
            BoxShadow(
              color: appColors.primary.withOpacity(.25),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.stars_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 6),
            Text(
              '$points',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 15,
              ),
            ),
            const SizedBox(width: 4),
            const Text(
              'نقطة',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InlineBanner extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _InlineBanner({required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [appColors.primary, appColors.primary, appColors.mint],
          stops: [0.0, 0.5, 1.0],
          begin: Alignment.bottomLeft,
          end: Alignment.topRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: appColors.primary.withOpacity(.20),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(.25),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.campaign_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('🎉', style: TextStyle(fontSize: 14)),
                      SizedBox(width: 4),
                      Text(
                        'جديد',
                        style: TextStyle(
                          color: appColors.accent,
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

DateTime getStartDateForRange(String range) {
  final now = DateTime.now();

  switch (range) {
    case 'اليوم':
      return DateTime(now.year, now.month, now.day);
    case 'أسبوع':
      return now.subtract(const Duration(days: 7));
    case 'شهر':
      return now.subtract(const Duration(days: 30));
    case 'سنة':
      return DateTime(now.year - 1, now.month, 1);
    default:
      return now.subtract(const Duration(days: 7));
  }
}

List<FlSpot> buildSpotsFromDocs(
  List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  String range,
) {
  final start = getStartDateForRange(range);
  final Map<int, int> buckets = {};

  for (final doc in docs) {
    final ts = doc.data()['createdAt'];
    if (ts is! Timestamp) continue;

    final date = ts.toDate();
    if (date.isBefore(start)) continue;

    int key;
    if (range == 'اليوم') {
      key = date.hour;
    } else if (range == 'سنة') {
      key = date.month - 1;
    } else {
      key = date.difference(start).inDays;
    }

    buckets[key] = (buckets[key] ?? 0) + 1;
  }

  final keys = buckets.keys.toList()..sort();

  return keys.map((k) => FlSpot(k.toDouble(), buckets[k]!.toDouble())).toList();
}

class _CarbonFootprintCard extends StatefulWidget {
  const _CarbonFootprintCard();

  @override
  State<_CarbonFootprintCard> createState() => _CarbonFootprintCardState();
}

class _CarbonFootprintCardState extends State<_CarbonFootprintCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return Column(
      children: [
        // 🔹 الجزء العلوي (الظاهر دائماً)
        GestureDetector(
          onTap: () {
            setState(() {
              _expanded = !_expanded;
            });
          },
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x14000000),
                  blurRadius: 18,
                  offset: Offset(0, 8),
                ),
              ],
              border: Border.all(color: Color(0xFFE8F1EE), width: 1.5),
            ),
            child: Row(
              children: [
                // النصوص والقيمة
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              'إجمالي خفض الكربون',
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: appColors.dark,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          GestureDetector(
                            onTap: () {
                              showDialog(
                                context: context,
                                builder: (ctx) {
                                  return Dialog(
                                    backgroundColor: Colors.white,
                                    insetPadding: const EdgeInsets.symmetric(
                                      horizontal: 24,
                                      vertical: 24,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(18),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.all(18),
                                      child: Directionality(
                                        textDirection: ui.TextDirection.rtl,
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            const Text(
                                              "ما هو إجمالي خفض الكربون؟",
                                              style: TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w800,
                                                color: appColors.dark,
                                              ),
                                            ),
                                            const SizedBox(height: 12),

                                            const Text(
                                              "يوضّح هذا الرقم مقدار الانبعاثات التي تجنّبتها بإنجاز مهامك، "
                                              "مقاسة بالكيلوغرام من مكافئ ثاني أكسيد الكربون (kg CO₂e). "
                                              "كلما زاد الرقم، كان تأثيرك الإيجابي على البيئة أكبر 🌿🌍.",
                                              style: TextStyle(
                                                fontSize: 13.5,
                                                height: 1.6,
                                                color: Colors.black87,
                                              ),
                                            ),

                                            const SizedBox(height: 20),

                                            Align(
                                              alignment: Alignment.centerLeft,
                                              child: TextButton(
                                                onPressed: () =>
                                                    Navigator.pop(ctx),
                                                child: const Text(
                                                  "حسنًا",
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.w700,
                                                    color: appColors.primary,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              );
                            },
                            child: const Icon(
                              Icons.info_outline,
                              size: 18,
                              color: appColors.sea,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (uid == null)
                            Text(
                              '0',
                              style: const TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.w900,
                                color: appColors.primary,
                                height: 1.0,
                              ),
                            )
                          else
                            StreamBuilder<
                              DocumentSnapshot<Map<String, dynamic>>
                            >(
                              stream: FirebaseFirestore.instance
                                  .collection('users')
                                  .doc(uid)
                                  .snapshots(),
                              builder: (context, snap) {
                                if (snap.connectionState ==
                                    ConnectionState.waiting) {
                                  return const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: appColors.primary,
                                    ),
                                  );
                                }

                                if (snap.hasError ||
                                    !snap.hasData ||
                                    !snap.data!.exists) {
                                  return Text(
                                    '0',
                                    style: const TextStyle(
                                      fontSize: 26,
                                      fontWeight: FontWeight.w900,
                                      color: appColors.primary,
                                      height: 1.0,
                                    ),
                                  );
                                }

                                final data = snap.data!.data();
                                num totalKg = 0;
                                if (data != null) {
                                  final vNew = data['totalCarbonSaved'];
                                  totalKg = _safeToNum(vNew);
                                }

                                if (totalKg.isNaN) totalKg = 0;
                                if (totalKg < 0) totalKg = 0;

                                return Text(
                                  _fmtKg(totalKg),
                                  style: const TextStyle(
                                    fontSize: 26,
                                    fontWeight: FontWeight.w900,
                                    color: appColors.primary,
                                    height: 1.0,
                                  ),
                                );
                              },
                            ),
                          const SizedBox(width: 8),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 2),
                            child: Text(
                              'كجم CO₂e',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: Colors.black.withOpacity(.6),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // 🔹 أيقونة الكرت + السهم
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [appColors.primary, appColors.mint],
                          begin: Alignment.bottomLeft,
                          end: Alignment.topRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: appColors.primary.withOpacity(.25),
                            blurRadius: 14,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.eco_rounded,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),

                    const SizedBox(width: 12),

                    // السهم بداخل نفس الصف
                    Icon(
                      _expanded
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      color: appColors.primary,
                      size: 24,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        // 🔹 الجزء السفلي (يظهر عند التوسيع)
        AnimatedSize(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          child: _expanded
              ? const Padding(
                  padding: EdgeInsets.only(top: 16),
                  child: _UserCarbonProgressCard(),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }

  // دالتين المساعدتين
  String _fmtKg(num? v) {
    final d = (v ?? 0).toDouble();
    if (d == 0) return '0';
    if (d < 0.1) return d.toStringAsFixed(3);
    if (d < 1) return d.toStringAsFixed(2);
    if (d < 10) {
      return (d == d.roundToDouble())
          ? d.toStringAsFixed(0)
          : d.toStringAsFixed(1);
    }
    return (d == d.roundToDouble())
        ? d.toStringAsFixed(0)
        : d.toStringAsFixed(1);
  }

  num _safeToNum(dynamic x) {
    if (x is num) return x;
    if (x == null) return 0;
    return num.tryParse(x.toString()) ?? 0;
  }
}

/// 🟢 تستدعى مثلاً داخل homePage.initState()
Future<void> ensureUserCarbonFields() async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return;

  final ref = FirebaseFirestore.instance.collection('users').doc(uid);
  final snap = await ref.get();

  if (!snap.exists) {
    await ref.set({
      'uid': uid,
      'role': 'regular',
      'points': 0,
      'totalCarbonSaved': 0,
      //'lastCarbonUpdateAt': null,
      'createdAt': FieldValue.serverTimestamp(),
      //'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    return;
  }

  final data = snap.data()!;
  final updates = <String, dynamic>{};

  if (!data.containsKey('points')) updates['points'] = 0;
  if (!data.containsKey('totalCarbonSaved')) updates['totalCarbonSaved'] = 0;
  // if (!data.containsKey('lastCarbonUpdateAt')) {
  //   updates['lastCarbonUpdateAt'] = null;
  // }

  // if (updates.isNotEmpty) {
  //   updates['updatedAt'] = FieldValue.serverTimestamp();
  //   await ref.set(updates, SetOptions(merge: true));
  // }
}

class _FriendCard extends StatelessWidget {
  final String name;
  final int points;
  final int streak;
  const _FriendCard({
    required this.name,
    required this.points,
    required this.streak,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 140,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.white, Color(0xFFF9FBFC)],
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
        border: Border.all(color: const Color(0xFFE6EDF1), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [Color(0xFFEFF4F6), Color(0xFFFDFEFE)],
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x11000000),
                      blurRadius: 8,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: const CircleAvatar(
                  radius: 22,
                  backgroundColor: Colors.transparent,
                  child: Icon(Icons.person, color: appColors.dark, size: 24),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: appColors.dark,
                  ),
                ),
              ),
            ],
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: appColors.accent.withOpacity(.12),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('🔥', style: TextStyle(fontSize: 14)),
                const SizedBox(width: 4),
                Text(
                  '$streak يوم',
                  style: const TextStyle(
                    color: appColors.accent,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(
                Icons.stars_rounded,
                size: 18,
                color: appColors.primary,
              ),
              const SizedBox(width: 6),
              Text(
                '$points نقطة',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: appColors.dark,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/* ======================= IsoLand 2.5D Platform ======================= */

class IsoItem {
  final int row;
  final int col;
  final Widget child;
  const IsoItem({required this.row, required this.col, required this.child});
}

class IsoLand extends StatelessWidget {
  final int rows;
  final int cols;
  final double height;
  final double thickness;
  final Color topColor;
  final Color sideColor;
  final Color gridColor;
  final double gridOpacity;
  final List<IsoItem> items;

  const IsoLand({
    super.key,
    this.rows = 6,
    this.cols = 6,
    this.height = 260,
    this.thickness = 14,
    this.topColor = const Color(0xFFBFE6C0),
    this.sideColor = const Color(0xFFA1C9A3),
    this.gridColor = const Color(0xFF1F7A8C),
    this.gridOpacity = .08,
    this.items = const [],
  });

  @override
  Widget build(BuildContext context) {
    final double width = height * 1.45;

    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // ظل أسفل المنصّة
          Positioned.fill(
            top: thickness,
            child: CustomPaint(painter: _IsoShadowPainter()),
          ),

          // جسم المنصّة + الشبكة (تمرير السمك)
          Positioned.fill(
            child: CustomPaint(
              painter: _IsoPlatformPainter(
                rows: rows,
                cols: cols,
                topColor: topColor,
                sideColor: sideColor,
                gridColor: gridColor.withOpacity(gridOpacity),
                depth: thickness, // << جديد
              ),
            ),
          ),

          // العناصر فوق الشبكة
          ...items.map(
            (it) => _IsoPositioned(
              rows: rows,
              cols: cols,
              row: it.row,
              col: it.col,
              child: it.child,
            ),
          ),
        ],
      ),
    );
  }
}

class _IsoPlatformPainter extends CustomPainter {
  final int rows, cols;
  final Color topColor, sideColor, gridColor;
  final double depth; // << جديد

  _IsoPlatformPainter({
    required this.rows,
    required this.cols,
    required this.topColor,
    required this.sideColor,
    required this.gridColor,
    required this.depth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // رؤوس الرومبوس العلوي
    final top = Offset(w * .50, h * .16);
    final right = Offset(w * .86, h * .50);
    final bottom = Offset(w * .50, h * .84);
    final left = Offset(w * .14, h * .50);

    // نسخ مُزاحة لأسفل بمقدار العمق
    final top2 = top.translate(0, depth);
    final right2 = right.translate(0, depth);
    final bottom2 = bottom.translate(0, depth);
    final left2 = left.translate(0, depth);

    // === وجوه السمك (تكملة الفراغ) ===
    final leftFace = Path()
      ..moveTo(left.dx, left.dy)
      ..lineTo(bottom.dx, bottom.dy)
      ..lineTo(bottom2.dx, bottom2.dy)
      ..lineTo(left2.dx, left2.dy)
      ..close();

    final rightFace = Path()
      ..moveTo(bottom.dx, bottom.dy)
      ..lineTo(right.dx, right.dy)
      ..lineTo(right2.dx, right2.dy)
      ..lineTo(bottom2.dx, bottom2.dy)
      ..close();

    final leftPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [sideColor.withOpacity(.95), sideColor.withOpacity(.8)],
      ).createShader(Rect.fromPoints(left, bottom2));

    final rightPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topRight,
        end: Alignment.bottomLeft,
        colors: [sideColor.withOpacity(.95), sideColor.withOpacity(.8)],
      ).createShader(Rect.fromPoints(bottom, right2));

    canvas.drawPath(leftFace, leftPaint);
    canvas.drawPath(rightFace, rightPaint);

    // سطح الرومبوس العلوي
    final topPath = Path()
      ..moveTo(top.dx, top.dy)
      ..lineTo(right.dx, right.dy)
      ..lineTo(bottom.dx, bottom.dy)
      ..lineTo(left.dx, left.dy)
      ..close();

    canvas.drawPath(
      topPath,
      Paint()
        ..shader = LinearGradient(
          colors: [topColor.withOpacity(.95), topColor.withOpacity(.85)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ).createShader(Offset.zero & size),
    );

    // شبكة خفيفة على السطح
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;

    Offset lerp(Offset a, Offset b, double t) =>
        Offset(a.dx + (b.dx - a.dx) * t, a.dy + (b.dy - a.dy) * t);

    for (int r = 1; r < rows; r++) {
      final t = r / rows;
      final a = lerp(top, right, t);
      final b = lerp(left, bottom, t);
      canvas.drawLine(a, b, gridPaint);
    }
    for (int c = 1; c < cols; c++) {
      final t = c / cols;
      final a = lerp(top, left, t);
      final b = lerp(right, bottom, t);
      canvas.drawLine(a, b, gridPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _IsoPlatformPainter old) =>
      old.rows != rows ||
      old.cols != cols ||
      old.topColor != topColor ||
      old.sideColor != sideColor ||
      old.gridColor != gridColor ||
      old.depth != depth;
}

class _IsoShadowPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final shadow = Path()
      ..moveTo(w * .18, h * .60)
      ..lineTo(w * .86, h * .60)
      ..lineTo(w * .92, h * .72)
      ..lineTo(w * .12, h * .72)
      ..close();

    final paint = Paint()
      ..color = Colors.black.withOpacity(.08)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawPath(shadow, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _IsoPositioned extends StatelessWidget {
  final int rows, cols, row, col;
  final Widget child;

  const _IsoPositioned({
    required this.rows,
    required this.cols,
    required this.row,
    required this.col,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (_, c) {
        final w = c.maxWidth;
        final h = c.maxHeight;

        final top = Offset(w * .50, h * .16);
        final right = Offset(w * .86, h * .50);
        final bottom = Offset(w * .50, h * .84);
        final left = Offset(w * .14, h * .50);

        Offset lerp(Offset a, Offset b, double t) =>
            Offset(a.dx + (b.dx - a.dx) * t, a.dy + (b.dy - a.dy) * t);

        final u = (col + .5) / cols; // يسار ↔ يمين
        final v = (row + .5) / rows; // أعلى ↔ أسفل

        final edgeA = lerp(left, top, 1 - v);
        final edgeB = lerp(bottom, right, 1 - v);
        final p = lerp(edgeA, edgeB, u);

        return Positioned(
          left: p.dx,
          top: p.dy,
          child: Transform.translate(
            offset: const Offset(-16, -28),
            child: child,
          ),
        );
      },
    );
  }
}

class _SkipTourButton extends StatelessWidget {
  final VoidCallback onSkip;
  const _SkipTourButton({required this.onSkip});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 8,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        onTap: onSkip,
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.close, size: 18, color: appColors.dark),
              SizedBox(width: 6),
              Text(
                'تخطي الجولة',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: appColors.dark,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StreakBadge extends StatelessWidget {
  final int days;
  const _StreakBadge({required this.days});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFF9800), Color(0xFFFF5722)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: Colors.orange.withOpacity(.4),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('🔥', style: TextStyle(fontSize: 16)),
          const SizedBox(width: 6),
          Text(
            '$days يوم متتالي',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

class _UserTaskProgressCard extends StatefulWidget {
  const _UserTaskProgressCard();

  @override
  State<_UserTaskProgressCard> createState() => _UserTaskProgressCardState();
}

class _UserTaskProgressCardState extends State<_UserTaskProgressCard> {
  String _range = 'اليوم';
  final ranges = ['اليوم', 'أسبوع', 'شهر', 'سنة'];
  DateTime _cursorDate = DateTime.now();

  // البيانات المطلوبة للتشارت
  List<BarChartGroupData> _taskBarGroups = [];
  Map<int, Map<String, dynamic>> _barCategoriesInfo = {};
  Map<String, Color> _categoryColors = {};
  Map<String, String> _categoryNames = {};
  List<FlSpot> _taskCompletionSpots = [];

  @override
  void initState() {
    super.initState();
    _loadTaskCompletionData();
  }

  String get _rangeLabel {
    switch (_range) {
      case 'سنة':
        return 'سنة ${_cursorDate.year}';
      case 'شهر':
        return '${_cursorDate.month}/${_cursorDate.year}';
      case 'أسبوع':
        final weekday = _cursorDate.weekday;
        final weekStart = _cursorDate.subtract(Duration(days: weekday % 7));
        final weekEnd = weekStart.add(const Duration(days: 6));
        return '${weekStart.day}/${weekStart.month} - ${weekEnd.day}/${weekEnd.month}';
      case 'اليوم':
        return '${_cursorDate.day}/${_cursorDate.month}/${_cursorDate.year}';
      default:
        return '';
    }
  }

  // دوال المساعدة للتاريخ
  DateTime _getStartDateForRange() {
    final d = _cursorDate;

    switch (_range) {
      case 'اليوم':
        return DateTime(d.year, d.month, d.day);
      case 'أسبوع':
        final weekday = d.weekday % 7;
        return DateTime(
          d.year,
          d.month,
          d.day,
        ).subtract(Duration(days: weekday));
      case 'شهر':
        return DateTime(d.year, d.month, 1);
      case 'سنة':
        return DateTime(d.year, 1, 1);
      default:
        return d;
    }
  }

  DateTime _getEndDateForRange() {
    final d = _cursorDate;

    switch (_range) {
      case 'اليوم':
        return DateTime(d.year, d.month, d.day, 23, 59, 59);
      case 'أسبوع':
        return d.add(const Duration(days: 7));
      case 'شهر':
        return DateTime(d.year, d.month + 1, d.day);
      case 'سنة':
        return DateTime(d.year + 1, d.month, d.day);
      default:
        return d;
    }
  }

  List<String> _generatePeriodKeys(DateTime start, DateTime end) {
    final List<String> keys = [];
    DateTime current = start;

    switch (_range) {
      case 'اليوم':
        for (int i = 0; i < 24; i++) {
          keys.add(i.toString());
        }
        break;
      case 'أسبوع':
        for (int i = 0; i < 7; i++) {
          keys.add(DateFormat('E').format(current));
          current = current.add(const Duration(days: 1));
        }
        break;
      case 'شهر':
        for (int i = 0; i < 30; i++) {
          keys.add(DateFormat('dd').format(current));
          current = current.add(const Duration(days: 1));
        }
        break;
      case 'سنة':
        for (int i = 0; i < 12; i++) {
          keys.add(DateFormat('MMM').format(DateTime(start.year, i + 1)));
        }
        break;
    }
    return keys;
  }

  String _getPeriodKey(DateTime date) {
    switch (_range) {
      case 'اليوم':
        return date.hour.toString();
      case 'أسبوع':
        return DateFormat('E').format(date);
      case 'شهر':
        return DateFormat('dd').format(date);
      case 'سنة':
        return DateFormat('MMM').format(date);
      default:
        return date.toString();
    }
  }

  double _getBarWidth() {
    switch (_range) {
      case 'اليوم':
        return 8.0;
      case 'أسبوع':
        return 14.0;
      case 'شهر':
        return 4.0;
      case 'سنة':
        return 10.0;
      default:
        return 10.0;
    }
  }

  Future<void> _loadTaskCompletionData() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;

      final startDate = _getStartDateForRange();
      final endDate = _getEndDateForRange();

      debugPrint('📅 Loading tasks from $startDate to $endDate');

      // احصل على جميع التقديمات المعتمدة في الفترة
      final submissionsSnapshot = await FirebaseFirestore.instance
          .collection('submissions')
          .where('userId', isEqualTo: uid)
          .where('status', isEqualTo: 'approved')
          .where(
            'createdAt',
            isGreaterThanOrEqualTo: Timestamp.fromDate(startDate),
          )
          .where('createdAt', isLessThanOrEqualTo: Timestamp.fromDate(endDate))
          .get();

      // أنشئ قائمة الفترات
      final periodKeys = _generatePeriodKeys(startDate, endDate);

      // خريطة لتخزين البيانات حسب الفترة والـ emissionFactorRef
      final Map<String, Map<String, int>> categoryCounts = {};
      final Set<String> allCategories = {};

      // تهيئة العدادات
      for (final key in periodKeys) {
        categoryCounts[key] = {};
      }

      // أولاً: جمع كل التصنيفات الفريدة وأسمائها من جميع المستندات
      final Map<String, String> tempCategoryNames = {};
      for (final doc in submissionsSnapshot.docs) {
        final data = doc.data();
        final emissionFactorRef =
            data['emissionFactorRef']?.toString() ?? 'غير محدد';
        final taskTitle = data['taskTitle']?.toString() ?? emissionFactorRef;

        allCategories.add(emissionFactorRef);
        tempCategoryNames[emissionFactorRef] = taskTitle;
      }

      // توليد ألوان ديناميكية لكل تصنيف
      final Map<String, Color> tempCategoryColors = {};
      final colorPalette = [
        Colors.green,
        Colors.blue,
        Colors.orange,
        Colors.purple,
        Colors.teal,
        Colors.pink,
        Colors.indigo,
        Colors.amber,
        Colors.brown,
        Colors.cyan,
        Colors.lime,
        Colors.deepOrange,
        Colors.red,
        Colors.yellow,
        Colors.lightBlue,
        Colors.lightGreen,
      ];

      int colorIndex = 0;
      for (final category in allCategories) {
        tempCategoryColors[category] =
            colorPalette[colorIndex % colorPalette.length];
        colorIndex++;
      }

      // عد المهام حسب emissionFactorRef لكل فترة
      for (final doc in submissionsSnapshot.docs) {
        final data = doc.data();
        final createdAt = data['createdAt'];
        final emissionFactorRef =
            data['emissionFactorRef']?.toString() ?? 'غير محدد';

        if (createdAt is Timestamp) {
          final taskDate = createdAt.toDate();
          final periodKey = _getPeriodKey(taskDate);

          if (categoryCounts.containsKey(periodKey)) {
            final periodData = categoryCounts[periodKey]!;
            periodData[emissionFactorRef] =
                (periodData[emissionFactorRef] ?? 0) + 1;
          }
        }
      }

      // تحويل إلى BarChartGroupData مع أشرطة متعددة
      final List<BarChartGroupData> barGroups = [];
      int index = 0;

      // حساب القيمة القصوى للمحور Y
      double maxCount = 0;
      for (final key in periodKeys) {
        final periodData = categoryCounts[key] ?? {};
        double periodTotal = 0;
        for (final entry in periodData.entries) {
          periodTotal += entry.value;
        }
        if (periodTotal > maxCount) {
          maxCount = periodTotal;
        }
      }

      // تحديث _taskCompletionSpots للاستخدام في الإحصائيات
      final List<FlSpot> spots = [];
      for (final key in periodKeys) {
        final periodData = categoryCounts[key] ?? {};
        double periodTotal = 0;
        for (final entry in periodData.entries) {
          periodTotal += entry.value;
        }
        spots.add(FlSpot(index.toDouble(), periodTotal));
        index++;
      }

      // إعادة تعيين index
      index = 0;
      final Map<int, Map<String, dynamic>> tempBarInfo = {};

      for (final key in periodKeys) {
        final periodData = categoryCounts[key] ?? {};

        // إنشاء أشرطة لكل تصنيف في نفس المجموعة
        final List<BarChartRodData> rods = [];
        final Map<String, dynamic> groupInfo = {};

        // ترتيب التصنيفات حسب العدد (تنازلياً)
        final sortedCategories = periodData.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));

        double currentStack = 0;
        int rodIndex = 0;
        for (final entry in sortedCategories) {
          final category = entry.key;
          final count = entry.value.toDouble();
          final displayName = tempCategoryNames[category] ?? category;

          if (count > 0) {
            // تخزين معلومات هذا الشريط
            groupInfo['rod_$rodIndex'] = {
              'category': category,
              'name': displayName,
              'count': count,
              'color': tempCategoryColors[category] ?? Colors.grey,
              'startY': currentStack,
              'endY': currentStack + count,
            };

            rods.add(
              BarChartRodData(
                toY: currentStack + count,
                width: _getBarWidth(),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(4),
                  topRight: Radius.circular(4),
                ),
                color: tempCategoryColors[category] ?? Colors.grey,
              ),
            );
            currentStack += count;
            rodIndex++;
          }
        }

        // تخزين معلومات المجموعة
        tempBarInfo[index] = groupInfo;

        // إذا كانت rods فارغة، أضف شريطاً فارغاً
        if (rods.isEmpty) {
          rods.add(
            BarChartRodData(
              toY: 0,
              width: _getBarWidth(),
              color: Colors.transparent,
            ),
          );
        }

        barGroups.add(BarChartGroupData(x: index, barRods: rods, barsSpace: 0));
        index++;
      }

      setState(() {
        _taskBarGroups = barGroups;
        _taskCompletionSpots = spots;
        _barCategoriesInfo = tempBarInfo;
        _categoryColors = tempCategoryColors;
        _categoryNames = tempCategoryNames;
      });
    } catch (e) {
      debugPrint('❌ Task completion error: $e');
    }
  }

  void _goPrev() {
    setState(() {
      if (_range == 'سنة') {
        _cursorDate = DateTime(_cursorDate.year - 1);
      } else if (_range == 'شهر') {
        _cursorDate = DateTime(_cursorDate.year, _cursorDate.month - 1);
      } else if (_range == 'أسبوع') {
        _cursorDate = _cursorDate.subtract(const Duration(days: 7));
      } else {
        _cursorDate = _cursorDate.subtract(const Duration(days: 1));
      }
    });
    _loadTaskCompletionData();
  }

  void _goNext() {
    setState(() {
      if (_range == 'سنة') {
        _cursorDate = DateTime(_cursorDate.year + 1);
      } else if (_range == 'شهر') {
        _cursorDate = DateTime(_cursorDate.year, _cursorDate.month + 1);
      } else if (_range == 'أسبوع') {
        _cursorDate = _cursorDate.add(const Duration(days: 7));
      } else {
        _cursorDate = _cursorDate.add(const Duration(days: 1));
      }
    });
    _loadTaskCompletionData();
  }

  bool get _canGoNext {
    final now = DateTime.now();
    final todayWeekStart = now.subtract(Duration(days: now.weekday % 7));

    if (_range == 'سنة') return _cursorDate.year < now.year;
    if (_range == 'شهر') {
      return _cursorDate.year < now.year || _cursorDate.month < now.month;
    }
    if (_range == 'أسبوع') {
      final cursorWeekStart = _cursorDate.subtract(
        Duration(days: _cursorDate.weekday % 7),
      );
      return cursorWeekStart.isBefore(todayWeekStart);
    }
    return _cursorDate.isBefore(now);
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const Center(child: Text('غير مسجل'));
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          /// العنوان + الفلتر
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'تقدم إنجاز المهام',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: appColors.dark,
                  ),
                ),
                _buildTimeRangeSelector(),
              ],
            ),
          ),

          const SizedBox(height: 8),

          /// الرسم البياني
          SizedBox(
            height: 200,
            child: Row(
              children: [
                Expanded(
                  child: _taskBarGroups.isEmpty
                      ? const Center(child: Text('لا توجد بيانات'))
                      : BarChart(
                          BarChartData(
                            minY: 0,
                            maxY: _getMaxYValueFromGroups(_taskBarGroups) == 0
                                ? 10
                                : _getMaxYValueFromGroups(_taskBarGroups) * 1.1,
                            gridData: FlGridData(
                              show: true,
                              drawVerticalLine: false,
                              horizontalInterval:
                                  _getMaxYValueFromGroups(_taskBarGroups) == 0
                                  ? 1
                                  : (_getMaxYValueFromGroups(_taskBarGroups) /
                                            3)
                                        .ceilToDouble(),
                            ),
                            titlesData: _buildTitles(
                              _getMaxYValueFromGroups(_taskBarGroups),
                            ),
                            borderData: FlBorderData(
                              show: true,
                              border: Border.all(
                                color: Colors.grey[300]!,
                                width: 1,
                              ),
                            ),
                            barGroups: _taskBarGroups,
                            barTouchData: BarTouchData(
                              enabled: true,
                              touchTooltipData: BarTouchTooltipData(
                                tooltipBgColor: appColors.primary,
                                getTooltipItem:
                                    (group, groupIndex, rod, rodIndex) {
                                      if (_barCategoriesInfo.containsKey(
                                        group.x,
                                      )) {
                                        final groupInfo =
                                            _barCategoriesInfo[group.x]!;
                                        final rodKey = 'rod_$rodIndex';

                                        if (groupInfo.containsKey(rodKey)) {
                                          final rodInfo = groupInfo[rodKey];
                                          final categoryName = rodInfo['name'];
                                          final count = rodInfo['count']
                                              .toInt();

                                          return BarTooltipItem(
                                            '$categoryName\n$count مهمة',
                                            const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 10,
                                            ),
                                          );
                                        }
                                      }

                                      return BarTooltipItem(
                                        '${rod.toY.toInt()} مهمة',
                                        const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 10,
                                        ),
                                      );
                                    },
                              ),
                            ),
                          ),
                        ),
                ),
                const SizedBox(width: 1),
                Center(
                  child: RotatedBox(
                    quarterTurns: 3,
                    child: Text(
                      'القيمة',
                      style: GoogleFonts.ibmPlexSansArabic(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[700],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),
          _buildRangeNavigator(),

          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildCompactMiniStat(
                  'الإجمالي',
                  _getTotalValueFromGroups(_taskBarGroups).toStringAsFixed(1),
                ),
                _buildCompactMiniStat(
                  'المتوسط',
                  _getAverageValueFromGroups(_taskBarGroups).toStringAsFixed(1),
                ),
                _buildCompactMiniStat(
                  'الأعلى',
                  _getMaxYValueFromGroups(_taskBarGroups).toInt().toString(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeRangeSelector() {
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: appColors.primary.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
      ),
      alignment: Alignment.center,
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _range,
          isDense: true,
          icon: Icon(Icons.arrow_drop_down, color: appColors.primary, size: 20),
          dropdownColor: Colors.white,
          borderRadius: BorderRadius.circular(12),
          style: GoogleFonts.ibmPlexSansArabic(
            color: appColors.dark,
            fontWeight: FontWeight.w600,
            fontSize: 12,
          ),
          onChanged: (String? newValue) {
            if (newValue != null) {
              setState(() {
                _range = newValue;
                _cursorDate = DateTime.now();
              });
              _loadTaskCompletionData();
            }
          },
          items: ranges.map<DropdownMenuItem<String>>((String value) {
            return DropdownMenuItem<String>(value: value, child: Text(value));
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildRangeNavigator() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(icon: const Icon(Icons.chevron_left), onPressed: _goPrev),
        Text(
          _rangeLabel,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right),
          onPressed: _canGoNext ? _goNext : null,
        ),
      ],
    );
  }

  FlTitlesData _buildTitles(double maxY) {
    return FlTitlesData(
      bottomTitles: AxisTitles(
        axisNameWidget: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            _getXAxisLabel(),
            style: GoogleFonts.ibmPlexSansArabic(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: Colors.grey[700],
            ),
          ),
        ),
        axisNameSize: 25,
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 25,
          interval: _getInterval(),
          getTitlesWidget: (value, meta) {
            return Padding(
              padding: const EdgeInsets.only(top: 4),
              child: _buildXAxisTitle(value, meta),
            );
          },
        ),
      ),
      leftTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 30,
          interval: maxY == 0 ? 1 : (maxY / 3),
          getTitlesWidget: (value, meta) {
            if (value.abs() < 0.0001) {
              return const SizedBox.shrink();
            }

            final third = maxY / 3;
            final twoThird = maxY * 2 / 3;

            bool isMatch(double a, double b) => (a - b).abs() < 0.0001;

            if (isMatch(value, maxY) ||
                isMatch(value, twoThird) ||
                isMatch(value, third)) {
              return Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Text(
                  value < 1
                      ? value.toStringAsFixed(1)
                      : value.toInt().toString(),
                  style: const TextStyle(
                    fontSize: 9,
                    color: Colors.grey,
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.right,
                ),
              );
            }

            return const SizedBox.shrink();
          },
        ),
      ),
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
    );
  }

  Widget _buildXAxisTitle(double value, TitleMeta meta) {
    int index = value.toInt();
    String text = '';

    if (_range == 'اليوم') {
      if (index % 3 == 0) {
        text = index.toString();
      }
    } else if (_range == 'أسبوع') {
      if (index < 7 && index % 2 == 0) {
        const days = ['أحد', 'اثن', 'ثلث', 'أرب', 'خم', 'جم', 'سبت'];
        text = days[index];
      }
    } else if (_range == 'شهر') {
      if (index % 5 == 0 && index < 30) {
        text = (index + 1).toString();
      }
    } else if (_range == 'سنة') {
      if (index < 12 && index % 2 == 0) {
        const months = [
          'ينا',
          'فبر',
          'مار',
          'أبر',
          'ماي',
          'يون',
          'يول',
          'أغس',
          'سبت',
          'أكت',
          'نوف',
          'ديس',
        ];
        text = months[index];
      }
    }

    if (text.isEmpty) return const SizedBox.shrink();

    return Text(
      text,
      style: const TextStyle(fontSize: 8, color: Colors.grey),
      textAlign: TextAlign.center,
    );
  }

  String _getXAxisLabel() {
    switch (_range) {
      case 'اليوم':
        return 'الساعة';
      case 'أسبوع':
        return 'اليوم';
      case 'شهر':
        return 'اليوم';
      case 'سنة':
        return 'الشهر';
      default:
        return 'الفترة';
    }
  }

  double _getInterval() {
    switch (_range) {
      case 'اليوم':
        return 3.0;
      case 'أسبوع':
        return 1.0;
      case 'شهر':
        return 5.0;
      case 'سنة':
        return 1.0;
      default:
        return 1.0;
    }
  }

  // دوال مساعدة لحساب القيم من BarChartGroupData
  double _getMaxYValueFromGroups(List<BarChartGroupData> groups) {
    if (groups.isEmpty) return 0;

    double maxY = 0;
    for (final group in groups) {
      double groupTotal = 0;
      for (final rod in group.barRods) {
        groupTotal += rod.toY;
      }
      if (groupTotal > maxY) {
        maxY = groupTotal;
      }
    }
    return maxY;
  }

  double _getTotalValueFromGroups(List<BarChartGroupData> groups) {
    if (groups.isEmpty) return 0;

    double total = 0;
    for (final group in groups) {
      for (final rod in group.barRods) {
        total += rod.toY;
      }
    }
    return total;
  }

  double _getAverageValueFromGroups(List<BarChartGroupData> groups) {
    if (groups.isEmpty) return 0;

    double total = _getTotalValueFromGroups(groups);
    return total / groups.length;
  }

  Widget _buildCompactMiniStat(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: appColors.dark,
          ),
        ),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
      ],
    );
  }
}

class _UserCarbonProgressCard extends StatefulWidget {
  const _UserCarbonProgressCard();

  @override
  State<_UserCarbonProgressCard> createState() =>
      _UserCarbonProgressCardState();
}

class _UserCarbonProgressCardState extends State<_UserCarbonProgressCard> {
  String _range = 'اليوم';
  final ranges = ['اليوم', 'أسبوع', 'شهر', 'سنة'];
  DateTime _cursorDate = DateTime.now();

  String get _rangeLabel {
    switch (_range) {
      case 'سنة':
        return 'سنة ${_cursorDate.year}';
      case 'شهر':
        return '${_cursorDate.month}/${_cursorDate.year}';
      case 'أسبوع':
        final weekday = _cursorDate.weekday;
        final weekStart = _cursorDate.subtract(Duration(days: weekday % 7));
        final weekEnd = weekStart.add(const Duration(days: 6));
        return '${weekStart.day}/${weekStart.month} - ${weekEnd.day}/${weekEnd.month}';
      case 'اليوم':
        return '${_cursorDate.day}/${_cursorDate.month}/${_cursorDate.year}';
      default:
        return '';
    }
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _getCarbonStream(String uid) {
    return FirebaseFirestore.instance
        .collection('submissions')
        .where('userId', isEqualTo: uid)
        .where('status', isEqualTo: 'approved')
        .snapshots();
  }

  void _goPrev() {
    setState(() {
      if (_range == 'سنة') {
        _cursorDate = DateTime(_cursorDate.year - 1);
      } else if (_range == 'شهر') {
        _cursorDate = DateTime(_cursorDate.year, _cursorDate.month - 1);
      } else if (_range == 'أسبوع') {
        _cursorDate = _cursorDate.subtract(const Duration(days: 7));
      } else {
        _cursorDate = _cursorDate.subtract(const Duration(days: 1));
      }
    });
  }

  void _goNext() {
    setState(() {
      if (_range == 'سنة') {
        _cursorDate = DateTime(_cursorDate.year + 1);
      } else if (_range == 'شهر') {
        _cursorDate = DateTime(_cursorDate.year, _cursorDate.month + 1);
      } else if (_range == 'أسبوع') {
        _cursorDate = _cursorDate.add(const Duration(days: 7));
      } else {
        _cursorDate = _cursorDate.add(const Duration(days: 1));
      }
    });
  }

  bool get _canGoNext {
    final now = DateTime.now();
    final todayWeekStart = now.subtract(Duration(days: now.weekday % 7));

    if (_range == 'سنة') return _cursorDate.year < now.year;
    if (_range == 'شهر') {
      return _cursorDate.year < now.year || _cursorDate.month < now.month;
    }
    if (_range == 'أسبوع') {
      final cursorWeekStart = _cursorDate.subtract(
        Duration(days: _cursorDate.weekday % 7),
      );
      return cursorWeekStart.isBefore(todayWeekStart);
    }
    return _cursorDate.isBefore(now);
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const Center(child: Text('غير مسجل'));
    }

    return Container(
      padding: const EdgeInsets.all(12), // تغيير من 16 إلى 12
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          /// العنوان + الفلتر
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'تطور خفض الكربون',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: appColors.dark,
                  ),
                ),
                _buildTimeRangeSelector(), // استخدام الدالة الموحدة
              ],
            ),
          ),

          const SizedBox(height: 8),

          /// ---------- DATA ----------
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _getCarbonStream(uid),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const SizedBox(
                  height: 175,
                  child: Center(
                    child: CircularProgressIndicator(color: appColors.tealSoft),
                  ),
                );
              }

              final bars = _buildSpots(snap.data?.docs ?? []);
              final double maxY = _getMaxYValue(bars);
              final double total = _getTotalValue(bars);
              final double average = _getAverageValue(bars);

              return Column(
                children: [
                  /// الرسم البياني مع Label Y
                  SizedBox(
                    height: 170,
                    child: Row(
                      children: [
                        /// الرسم البياني أولاً
                        Expanded(
                          child: BarChart(
                            BarChartData(
                              minY: 0,
                              maxY: maxY == 0 ? 10 : maxY * 1.1,
                              gridData: FlGridData(
                                show: true,
                                drawVerticalLine: false,
                                horizontalInterval: maxY == 0
                                    ? 1
                                    : (maxY / 3).ceilToDouble(),
                              ),
                              titlesData: _buildTitles(maxY),
                              borderData: FlBorderData(
                                show: true,
                                border: Border.all(
                                  color: Colors.grey[300]!,
                                  width: 0.5,
                                ),
                              ),
                              barGroups: bars,
                              barTouchData: BarTouchData(
                                enabled: true,
                                touchTooltipData: BarTouchTooltipData(
                                  tooltipBgColor: appColors.tealSoft,
                                  getTooltipItem:
                                      (group, groupIndex, rod, rodIndex) {
                                        return BarTooltipItem(
                                          '${rod.toY.toStringAsFixed(1)} كجم',
                                          const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 10,
                                          ),
                                        );
                                      },
                                ),
                              ),
                            ),
                          ),
                        ),

                        /// مسافة بين الرسم والـ Label
                        const SizedBox(width: 1),

                        /// 🏷️ Label Y على اليمين
                        Center(
                          child: RotatedBox(
                            quarterTurns: 3,
                            child: Text(
                              'القيمة',
                              style: GoogleFonts.ibmPlexSansArabic(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey[700],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 8),

                  /// متصفح التاريخ
                  _buildRangeNavigator(),

                  const SizedBox(height: 8),

                  /// الإحصائيات
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildCompactMiniStat(
                          'الإجمالي',
                          '${total.toStringAsFixed(1)} كجم',
                        ),
                        _buildCompactMiniStat(
                          'المتوسط',
                          '${average.toStringAsFixed(1)} كجم',
                        ),
                        _buildCompactMiniStat(
                          'الأعلى',
                          '${maxY.toStringAsFixed(1)} كجم',
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  // أضف هذه الدوال داخل الكلاس
  Widget _buildTimeRangeSelector() {
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: appColors.tealSoft.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
      ),
      alignment: Alignment.center,
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _range,
          isDense: true,
          icon: Icon(
            Icons.arrow_drop_down,
            color: appColors.tealSoft,
            size: 20,
          ),
          dropdownColor: Colors.white,
          borderRadius: BorderRadius.circular(12),
          style: GoogleFonts.ibmPlexSansArabic(
            color: appColors.dark,
            fontWeight: FontWeight.w600,
            fontSize: 12,
          ),
          onChanged: (String? newValue) {
            if (newValue != null) {
              setState(() {
                _range = newValue;
                _cursorDate = DateTime.now();
              });
            }
          },
          items: ranges.map<DropdownMenuItem<String>>((String value) {
            return DropdownMenuItem<String>(value: value, child: Text(value));
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildRangeNavigator() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(icon: const Icon(Icons.chevron_left), onPressed: _goPrev),
        Text(
          _rangeLabel,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right),
          onPressed: _canGoNext ? _goNext : null,
        ),
      ],
    );
  }

  // 🔹 دالة لحساب القيمة الإجمالية
  double _getTotalValue(List<BarChartGroupData> bars) {
    if (bars.isEmpty) return 0;
    double total = 0;
    for (final bar in bars) {
      total += bar.barRods.first.toY;
    }
    return total;
  }

  // 🔹 دالة لحساب القيمة المتوسطة
  double _getAverageValue(List<BarChartGroupData> bars) {
    if (bars.isEmpty) return 0;
    double total = 0;
    int count = 0;
    for (final bar in bars) {
      total += bar.barRods.first.toY;
      count++;
    }
    return count > 0 ? total / count : 0;
  }

  // 🔹 دالة لحساب القيمة القصوى
  double _getMaxYValue(List<BarChartGroupData> bars) {
    if (bars.isEmpty) return 1;

    double maxY = 0;
    for (final bar in bars) {
      if (bar.barRods.first.toY > maxY) {
        maxY = bar.barRods.first.toY;
      }
    }

    if (maxY <= 0) return 1;

    // 🔥 لو القيمة صغيرة جدًا نخليها 1 عشان الرسم يكون منطقي
    if (maxY < 1) return 1;

    if (maxY < 5) return 5;
    if (maxY < 10) return 10;

    return maxY;
  }

  /// ---------- Titles ----------
  FlTitlesData _buildTitles(double maxY) {
    return FlTitlesData(
      bottomTitles: AxisTitles(
        axisNameWidget: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            _getXAxisLabel(),
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: Colors.grey,
            ),
          ),
        ),
        axisNameSize: 18,
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 36,
          interval: _getInterval(),
          getTitlesWidget: (value, _) {
            final index = value.toInt();

            if (_range == 'اليوم') {
              final showHours = [0, 3, 6, 9, 12, 15, 18, 21, 23];
              if (showHours.contains(index)) {
                return Text('$index', style: const TextStyle(fontSize: 10));
              }
              return const SizedBox();
            }

            if (_range == 'أسبوع') {
              const days = ['أحد', 'إثن', 'ثلث', 'أرب', 'خم', 'جم', 'سبت'];
              if (index >= 0 && index < 7) {
                return Text(days[index], style: const TextStyle(fontSize: 10));
              }
              return const SizedBox();
            }

            if (_range == 'شهر') {
              final day = index + 1;
              final lastDay = DateTime(
                _cursorDate.year,
                _cursorDate.month,
                0,
              ).day;
              final showDays = [1, 5, 10, 15, 20, 25, lastDay];
              if (showDays.contains(day)) {
                return Text(
                  day.toString(),
                  style: const TextStyle(fontSize: 10),
                );
              }
              return const SizedBox();
            }

            const months = [
              'ينا',
              'فبر',
              'مار',
              'أبر',
              'ماي',
              'يون',
              'يول',
              'أغس',
              'سبت',
              'أكت',
              'نوف',
              'ديس',
            ];
            if (index >= 0 && index < 12) {
              return Text(months[index], style: const TextStyle(fontSize: 10));
            }
            return const SizedBox();
          },
        ),
      ),
      leftTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 30,
          interval: maxY == 0 ? 1 : (maxY / 3),
          getTitlesWidget: (value, meta) {
            // 🔥 لا تعرض الصفر
            if (value.abs() < 0.0001) {
              return const SizedBox.shrink();
            }

            return Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Text(
                value.toStringAsFixed(1), // أو toInt() حسب احتياجك
                style: const TextStyle(
                  fontSize: 9,
                  color: Colors.grey,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.right,
              ),
            );
          },
        ),
      ),
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
    );
  }

  String _getXAxisLabel() {
    switch (_range) {
      case 'اليوم':
        return 'الساعة';
      case 'أسبوع':
        return 'اليوم';
      case 'شهر':
        return 'اليوم';
      case 'سنة':
        return 'الشهر';
      default:
        return 'الفترة';
    }
  }

  // 🔹 دالة تحدد التباعد المناسب لكل فترة
  double _getInterval() {
    switch (_range) {
      case 'اليوم':
        return 3.0;
      case 'أسبوع':
        return 1.0;
      case 'شهر':
        return 5.0;
      case 'سنة':
        return 1.0;
      default:
        return 1.0;
    }
  }

  /// ---------- Mini stat ----------
  Widget _buildCompactMiniStat(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: appColors.dark,
          ),
        ),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
      ],
    );
  }

  /// ---------- Chart logic ----------
  List<BarChartGroupData> _buildSpots(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final Map<int, double> buckets = {};

    DateTime startDate;
    DateTime endDate;
    int totalBars;

    // 🔹 تحديد عدد الأشرطة لكل فترة
    if (_range == 'سنة') {
      totalBars = 12;
      startDate = DateTime(_cursorDate.year, 1, 1);
      endDate = DateTime(_cursorDate.year + 1, 1, 1);
    } else if (_range == 'شهر') {
      totalBars = DateTime(_cursorDate.year, _cursorDate.month + 1, 0).day;
      startDate = DateTime(_cursorDate.year, _cursorDate.month, 1);
      endDate = DateTime(_cursorDate.year, _cursorDate.month + 1, 1);
    } else if (_range == 'أسبوع') {
      totalBars = 7;
      final weekday = _cursorDate.weekday;
      final startOfWeek = _cursorDate.subtract(Duration(days: weekday % 7));
      startDate = DateTime(
        startOfWeek.year,
        startOfWeek.month,
        startOfWeek.day,
      );
      endDate = startDate.add(const Duration(days: 7));
    } else {
      totalBars = 24;
      startDate = DateTime(
        _cursorDate.year,
        _cursorDate.month,
        _cursorDate.day,
      );
      endDate = startDate.add(const Duration(days: 1));
    }

    // 🔹 تهيئة جميع الأشرطة بصفر
    for (int i = 0; i < totalBars; i++) {
      buckets[i] = 0.0;
    }

    // 🔹 ملء البيانات الفعلية
    for (final doc in docs) {
      final data = doc.data();
      final Timestamp? ts = data['completedAt'] ?? data['createdAt'];
      final carbon = data['carbonSaved'] ?? 0;

      if (ts == null || carbon == 0) continue;

      final date = ts.toDate();

      // ✅ تأكد من التاريخ ضمن النطاق
      if (date.isBefore(startDate) || date.isAfter(endDate)) continue;

      int key;
      if (_range == 'اليوم') {
        key = date.hour;
      } else if (_range == 'أسبوع') {
        final diff = date.difference(startDate).inDays;
        key = diff;
      } else if (_range == 'شهر') {
        key = date.day - 1;
      } else {
        key = date.month - 1;
      }

      if (key >= 0 && key < totalBars) {
        final current = buckets[key] ?? 0.0;
        final carbonValue = (carbon is num) ? carbon.toDouble() : 0.0;
        buckets[key] = current + carbonValue;
      }
    }

    // 🔹 إنشاء الأشرطة
    return List.generate(totalBars, (index) {
      final carbonValue = buckets[index] ?? 0.0;
      return BarChartGroupData(
        x: index,
        barRods: [
          BarChartRodData(
            toY: carbonValue,
            width: _getBarWidth(),
            borderRadius: BorderRadius.circular(4),
            color: carbonValue > 0 ? appColors.tealSoft : Colors.grey[300]!,
            backDrawRodData: BackgroundBarChartRodData(
              show: true,
              toY: carbonValue + 0.5,
              color: Colors.grey[100]!,
            ),
          ),
        ],
      );
    });
  }

  // 🔹 تحديد عرض الشريط بناءً على الفترة
  double _getBarWidth() {
    switch (_range) {
      case 'اليوم':
        return 8.0;
      case 'أسبوع':
        return 14.0;
      case 'شهر':
        return 4.0;
      case 'سنة':
        return 10.0;
      default:
        return 10.0;
    }
  }
}

/* ======================= TopLeaderboardCard Widget ======================= */
class TopLeaderboardCard extends StatefulWidget {
  const TopLeaderboardCard({super.key});

  @override
  State<TopLeaderboardCard> createState() => _TopLeaderboardCardState();
}

class _TopLeaderboardCardState extends State<TopLeaderboardCard> {
  bool _isLoading = false;
  List<Map<String, dynamic>> _topUsers = [];
  Map<String, dynamic>? _currentUserRank;

  @override
  void initState() {
    super.initState();
    _loadTopUsers();
  }

  Future<void> _loadTopUsers() async {
    setState(() => _isLoading = true);
    try {
      final usersSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('isVerified', isEqualTo: true)
          .get();

      final List<Map<String, dynamic>> usersData = [];
      final String currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';

      for (final doc in usersSnapshot.docs) {
        final data = doc.data();
        final completedTasks = data['completedTask'] ?? 0;
        final points = data['points'] ?? 0;
        final username = data['username'] ?? 'مستخدم';
        final pfpIndex = data['pfpIndex'] ?? 0;

        usersData.add({
          'id': doc.id,
          'username': username,
          'completedTasks': completedTasks is num ? completedTasks.toInt() : 0,
          'points': points is num ? points.toInt() : 0,
          'pfpIndex': pfpIndex,
          'isCurrentUser': doc.id == currentUserId,
        });
      }

      usersData.sort(
        (a, b) => b['completedTasks'].compareTo(a['completedTasks']),
      );

      for (int i = 0; i < usersData.length; i++) {
        usersData[i]['rank'] = i + 1;

        if (usersData[i]['isCurrentUser'] == true) {
          _currentUserRank = usersData[i];
        }
      }

      setState(() {
        _topUsers = usersData.take(3).toList();
      });
    } catch (e) {
      debugPrint('❌ Leaderboard error: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Widget _buildCurrentUserRankCard() {
    if (_currentUserRank == null) {
      return const SizedBox.shrink();
    }

    final rank = _currentUserRank!['rank'] ?? 0;
    final username = _currentUserRank!['username'] ?? 'أنت';
    final completedTasks = _currentUserRank!['completedTasks'] ?? 0;
    final points = _currentUserRank!['points'] ?? 0;
    final pfpIndex = _currentUserRank!['pfpIndex'] ?? 0;

    // ✅ إذا كان المستخدم ضمن أول 3، لا نعرضه مرتين
    if (rank <= 3) return const SizedBox.shrink();

    return Column(
      children: [
        // ✅ 3 نقاط فوق المستخدم الحالي
        Container(
          margin: const EdgeInsets.only(bottom: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: appColors.primary.withOpacity(0.4),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 4),
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: appColors.primary.withOpacity(0.6),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 4),
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: appColors.primary,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
        ),

        // ✅ كارد المستخدم الحالي
        Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.grey[50],
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: appColors.primary.withOpacity(0.3),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: appColors.primary.withOpacity(0.05),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            children: [
              // الرتبة - بنفس حجم أول 3
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: appColors.primary.withOpacity(0.12),
                  shape: BoxShape.circle,
                  border: Border.all(color: appColors.primary, width: 1.5),
                ),
                child: Center(
                  child: Text(
                    '$rank',
                    style: GoogleFonts.ibmPlexSansArabic(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      color: appColors.primary,
                    ),
                  ),
                ),
              ),

              const SizedBox(width: 12),

              // الصورة الشخصية - بنفس حجم أول 3
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [
                      appColors.primary.withOpacity(.1),
                      appColors.sea.withOpacity(.05),
                    ],
                  ),
                ),
                child: CircleAvatar(
                  backgroundColor: Colors.transparent,
                  backgroundImage: AssetImage(
                    'assets/pfp/pfp${pfpIndex + 1}.png',
                  ),
                  child: pfpIndex >= 0 && pfpIndex < 8
                      ? null
                      : const Icon(
                          Icons.person,
                          size: 20,
                          color: appColors.primary,
                        ),
                ),
              ),

              const SizedBox(width: 12),

              // الاسم والإحصائيات - بنفس تصميم أول 3
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          username,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.ibmPlexSansArabic(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: appColors.dark,
                          ),
                        ),
                        const SizedBox(width: 6),
                        // علامة "مركزك" صغيرة
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: appColors.primary.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'مركزك',
                            style: GoogleFonts.ibmPlexSansArabic(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: appColors.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        // المهام المكتملة
                        Row(
                          children: [
                            Icon(Icons.task_alt, size: 12, color: Colors.green),
                            const SizedBox(width: 4),
                            Text(
                              '$completedTasks',
                              style: GoogleFonts.ibmPlexSansArabic(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Colors.green,
                              ),
                            ),
                            Text(
                              ' مهام',
                              style: GoogleFonts.ibmPlexSansArabic(
                                fontSize: 11,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(width: 12),

                        // النقاط
                        Row(
                          children: [
                            Icon(Icons.star, size: 12, color: Colors.amber),
                            const SizedBox(width: 4),
                            Text(
                              '$points',
                              style: GoogleFonts.ibmPlexSansArabic(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Colors.amber,
                              ),
                            ),
                            Text(
                              ' نقطة',
                              style: GoogleFonts.ibmPlexSansArabic(
                                fontSize: 11,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLeaderItem({
    required int index,
    required String username,
    required int completedTasks,
    required int points,
    required int pfpIndex,
    int? rank,
  }) {
    final actualRank = rank ?? (index + 1);

    final Color rankColor;
    final IconData? rankIcon;

    switch (actualRank) {
      case 1:
        rankColor = const Color(0xFFFFD700);
        rankIcon = Icons.emoji_events;
        break;
      case 2:
        rankColor = const Color(0xFFC0C0C0);
        rankIcon = Icons.emoji_events;
        break;
      case 3:
        rankColor = const Color(0xFFCD7F32);
        rankIcon = Icons.emoji_events;
        break;
      default:
        rankColor = Colors.grey[400]!;
        rankIcon = null;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: actualRank <= 3
            ? rankColor.withOpacity(0.05)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        border: actualRank <= 3
            ? Border.all(color: rankColor.withOpacity(0.3), width: 1.5)
            : null,
      ),
      child: Row(
        children: [
          // الرتبة
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: rankColor.withOpacity(actualRank <= 3 ? 0.2 : 0.1),
              shape: BoxShape.circle,
              border: Border.all(color: rankColor.withOpacity(0.3), width: 1),
            ),
            child: Center(
              child: rankIcon != null && actualRank <= 3
                  ? Icon(rankIcon, size: 16, color: rankColor)
                  : Text(
                      '$actualRank',
                      style: GoogleFonts.ibmPlexSansArabic(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: rankColor,
                      ),
                    ),
            ),
          ),

          const SizedBox(width: 12),

          // الصورة الشخصية
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [
                  appColors.primary.withOpacity(.1),
                  appColors.sea.withOpacity(.05),
                ],
              ),
            ),
            child: CircleAvatar(
              backgroundColor: Colors.transparent,
              backgroundImage: AssetImage('assets/pfp/pfp${pfpIndex + 1}.png'),
              child: pfpIndex >= 0 && pfpIndex < 8
                  ? null
                  : const Icon(
                      Icons.person,
                      size: 20,
                      color: appColors.primary,
                    ),
            ),
          ),

          const SizedBox(width: 12),

          // الاسم والإحصائيات
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  username,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.ibmPlexSansArabic(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: actualRank <= 3 ? appColors.dark : Colors.grey[800],
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    // المهام المكتملة
                    Row(
                      children: [
                        Icon(Icons.task_alt, size: 12, color: Colors.green),
                        const SizedBox(width: 4),
                        Text(
                          '$completedTasks',
                          style: GoogleFonts.ibmPlexSansArabic(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Colors.green,
                          ),
                        ),
                        Text(
                          ' مهام',
                          style: GoogleFonts.ibmPlexSansArabic(
                            fontSize: 11,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(width: 12),

                    // النقاط
                    Row(
                      children: [
                        Icon(Icons.star, size: 12, color: Colors.amber),
                        const SizedBox(width: 4),
                        Text(
                          '$points',
                          style: GoogleFonts.ibmPlexSansArabic(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Colors.amber,
                          ),
                        ),
                        Text(
                          ' نقطة',
                          style: GoogleFonts.ibmPlexSansArabic(
                            fontSize: 11,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),

          // مؤشر التقدم للأول فقط
          if (actualRank == 1)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: rankColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'الأول',
                style: GoogleFonts.ibmPlexSansArabic(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: rankColor,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<List<Map<String, dynamic>>> _fetchFullLeaderboard() async {
    try {
      final usersSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('isVerified', isEqualTo: true)
          .get();

      final List<Map<String, dynamic>> usersData = [];
      final String currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';

      for (final doc in usersSnapshot.docs) {
        final data = doc.data();
        final completedTasks = data['completedTask'] ?? 0;
        final points = data['points'] ?? 0;
        final username = data['username'] ?? 'مستخدم';
        final pfpIndex = data['pfpIndex'] ?? 0;

        usersData.add({
          'id': doc.id,
          'username': username,
          'completedTasks': completedTasks is num ? completedTasks.toInt() : 0,
          'points': points is num ? points.toInt() : 0,
          'pfpIndex': pfpIndex,
          'isCurrentUser': doc.id == currentUserId,
        });
      }

      usersData.sort(
        (a, b) => b['completedTasks'].compareTo(a['completedTasks']),
      );

      for (int i = 0; i < usersData.length; i++) {
        usersData[i]['rank'] = i + 1;
      }

      return usersData;
    } catch (e) {
      debugPrint('❌ Full leaderboard error: $e');
      return [];
    }
  }

  void _showFullLeaderboard() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.85,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(24),
              topRight: Radius.circular(24),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 20,
                offset: const Offset(0, -5),
              ),
            ],
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'قائمة المتصدرين الكاملة',
                      style: GoogleFonts.ibmPlexSansArabic(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: appColors.dark,
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(Icons.close, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: FutureBuilder<List<Map<String, dynamic>>>(
                  future: _fetchFullLeaderboard(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    if (!snapshot.hasData || snapshot.data!.isEmpty) {
                      return Center(
                        child: Text(
                          'لا توجد بيانات',
                          style: GoogleFonts.ibmPlexSansArabic(
                            color: Colors.grey[600],
                          ),
                        ),
                      );
                    }

                    final allUsers = snapshot.data!;

                    return ListView.builder(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      itemCount: allUsers.length,
                      itemBuilder: (context, index) {
                        final user = allUsers[index];
                        return _buildLeaderItem(
                          index: index,
                          username: user['username'],
                          completedTasks: user['completedTasks'],
                          points: user['points'],
                          pfpIndex: user['pfpIndex'],
                          rank: user['rank'],
                        );
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [
            BoxShadow(
              color: Color(0x14000000),
              blurRadius: 14,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'أعلى 3 مستخدمين إنجازًا',
                  style: GoogleFonts.ibmPlexSansArabic(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: appColors.dark,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: appColors.accent.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.leaderboard,
                        size: 14,
                        color: appColors.accent,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'قائمة المتصدرين',
                        style: GoogleFonts.ibmPlexSansArabic(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: appColors.accent,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            if (_isLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(color: appColors.primary),
                ),
              )
            else if (_topUsers.isEmpty)
              Center(
                child: Text(
                  'لا توجد بيانات متاحة',
                  style: GoogleFonts.ibmPlexSansArabic(
                    color: Colors.grey[600],
                    fontSize: 13,
                  ),
                ),
              )
            else
              Column(
                children: [
                  ..._topUsers.asMap().entries.map((entry) {
                    final index = entry.key;
                    final user = entry.value;

                    return _buildLeaderItem(
                      index: index,
                      username: user['username'],
                      completedTasks: user['completedTasks'],
                      points: user['points'],
                      pfpIndex: user['pfpIndex'],
                      rank: user['rank'],
                    );
                  }).toList(),

                  // ✅ إضافة المستخدم الحالي مع 3 نقاط فوقه
                  if (_currentUserRank != null &&
                      (_currentUserRank!['rank'] ?? 0) > 3)
                    _buildCurrentUserRankCard(),
                ],
              ),

            if (_topUsers.isNotEmpty)
              Column(
                children: [
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: GestureDetector(
                      onTap: _showFullLeaderboard,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'عرض القائمة الكاملة',
                            style: GoogleFonts.ibmPlexSansArabic(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: appColors.primary,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.chevron_left,
                            size: 16,
                            color: appColors.primary,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _DynamicFriendsSection extends StatefulWidget {
  const _DynamicFriendsSection();

  @override
  State<_DynamicFriendsSection> createState() => _DynamicFriendsSectionState();
}

class _DynamicFriendsSectionState extends State<_DynamicFriendsSection> {
  List<Map<String, dynamic>> _friends = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadFriends();
  }

  Future<void> _loadFriends() async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        setState(() => _isLoading = false);
        return;
      }

      // جلب قائمة الأصدقاء من المستخدم الحالي
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .get();

      if (!userDoc.exists) {
        setState(() => _isLoading = false);
        return;
      }

      final List<dynamic> followingIds = userDoc.data()?['following'] ?? [];

      if (followingIds.isEmpty) {
        setState(() {
          _friends = [];
          _isLoading = false;
        });
        return;
      }

      List<Map<String, dynamic>> friends = [];

      // جلب بيانات أول صديقين فقط للعرض في الصفحة الرئيسية
      final idsToFetch = followingIds.take(2).toList();

      for (String friendId in idsToFetch) {
        try {
          final friendDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(friendId)
              .get();

          if (friendDoc.exists) {
            final data = friendDoc.data()!;
            friends.add({
              'id': friendId,
              'username': data['username'] ?? 'صديق',
              'points': data['points'] ?? 0,
              'currentStreak': data['currentStreak'] ?? 0,
              'pfpIndex': data['pfpIndex'],
            });
          }
        } catch (e) {
          debugPrint('خطأ في جلب بيانات الصديق: $e');
        }
      }

      // ترتيب حسب النقاط
      friends.sort(
        (a, b) => (b['points'] as int).compareTo(a['points'] as int),
      );

      setState(() {
        _friends = friends;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('خطأ في تحميل الأصدقاء: $e');
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const SizedBox(
        height: 140,
        child: Center(
          child: CircularProgressIndicator(color: appColors.primary),
        ),
      );
    }

    if (_friends.isEmpty) {
      return _buildEmptyState();
    }

    return Row(
      children: [
        // الصديق الأول
        Expanded(
          child: _DynamicFriendCard(
            name: _friends[0]['username'],
            points: _friends[0]['points'],
            streak: _friends[0]['currentStreak'],
            pfpIndex: _friends[0]['pfpIndex'],
          ),
        ),
        const SizedBox(width: 12),
        // الصديق الثاني أو placeholder
        Expanded(
          child: _friends.length > 1
              ? _DynamicFriendCard(
                  name: _friends[1]['username'],
                  points: _friends[1]['points'],
                  streak: _friends[1]['currentStreak'],
                  pfpIndex: _friends[1]['pfpIndex'],
                )
              : _buildAddFriendCard(),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const communityPage()),
        );
      },
      child: Container(
        height: 160,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              appColors.primary.withOpacity(0.05),
              appColors.mint.withOpacity(0.1),
            ],
          ),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: appColors.primary.withOpacity(0.2),
            width: 1.5,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: appColors.primary.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.person_add_rounded,
                color: appColors.primary,
                size: 28,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'أضف أصدقاءك الآن!',
              style: GoogleFonts.ibmPlexSansArabic(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: appColors.dark,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'تابع تقدمهم وتنافس معهم',
              style: GoogleFonts.ibmPlexSansArabic(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAddFriendCard() {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const communityPage()),
        );
      },
      child: Container(
        height: 140,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.white, Color(0xFFF9FBFC)],
          ),
          borderRadius: BorderRadius.circular(22),
          boxShadow: const [
            BoxShadow(
              color: Color(0x14000000),
              blurRadius: 16,
              offset: Offset(0, 6),
            ),
          ],
          border: Border.all(
            color: appColors.primary.withOpacity(0.15),
            width: 1.5,
            style: BorderStyle.solid,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: appColors.primary.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.add_rounded,
                color: appColors.primary,
                size: 24,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'إضافة صديق',
              style: GoogleFonts.ibmPlexSansArabic(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: appColors.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ✅ بطاقة الصديق الديناميكية مع صورة البروفايل
class _DynamicFriendCard extends StatelessWidget {
  final String name;
  final int points;
  final int streak;
  final dynamic pfpIndex;

  const _DynamicFriendCard({
    required this.name,
    required this.points,
    required this.streak,
    this.pfpIndex,
  });

  @override
  Widget build(BuildContext context) {
    // تحديد صورة الأفاتار
    String? avatarPath;
    if (pfpIndex != null && pfpIndex is int && pfpIndex >= 0 && pfpIndex < 8) {
      avatarPath = 'assets/pfp/pfp${pfpIndex + 1}.png';
    }

    return Container(
      height: 140,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.white, Color(0xFFF9FBFC)],
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
        border: Border.all(color: const Color(0xFFE6EDF1), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // صورة البروفايل
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [
                      appColors.primary.withOpacity(0.15),
                      appColors.mint.withOpacity(0.1),
                    ],
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x11000000),
                      blurRadius: 8,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: CircleAvatar(
                  radius: 22,
                  backgroundColor: Colors.transparent,
                  backgroundImage: avatarPath != null
                      ? AssetImage(avatarPath)
                      : null,
                  child: avatarPath == null
                      ? const Icon(
                          Icons.person,
                          color: appColors.primary,
                          size: 24,
                        )
                      : null,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: appColors.dark,
                  ),
                ),
              ),
            ],
          ),
          const Spacer(),

          // شارة الـ Streak
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: streak > 0
                  ? appColors.accent.withOpacity(.12)
                  : Colors.grey.withOpacity(0.1),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  streak > 0 ? '🔥' : '💤',
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(width: 4),
                Text(
                  streak > 0 ? '$streak يوم' : 'لا يوجد',
                  style: TextStyle(
                    color: streak > 0 ? appColors.accent : Colors.grey,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // النقاط
          Row(
            children: [
              const Icon(
                Icons.stars_rounded,
                size: 18,
                color: appColors.primary,
              ),
              const SizedBox(width: 6),
              Text(
                '$points نقطة',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: appColors.dark,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
