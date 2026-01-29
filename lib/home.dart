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
  }

  Future<void> _initHome() async {
    // 🔔 طلب الإذن + حفظ التوكن + الاستماع
    FCMService.requestPermissionAndSaveToken();
    FCMService.listenToForegroundMessages();
    saveFcmToken();

    // _bgCtrl = AnimationController(
    //   vsync: this,
    //   duration: const Duration(seconds: 14),
    // )..repeat();
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
          textDirection: TextDirection.rtl,
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
                                                        TextDirection.rtl,
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
                                                          textDirection:
                                                              TextDirection
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
                                                          textDirection:
                                                              TextDirection.rtl,
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
                                    textDirection: TextDirection.rtl,
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
                                                fontWeight: FontWeight.w800,
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
                              key: _ecoLandAnchorKey, // ← مرساة السكرول
                              child: Showcase.withWidget(
                                key: _ecoLandKey,
                                overlayColor: Colors.black.withOpacity(0.35),
                                overlayOpacity: 0.35,
                                blurValue: 0,

                                // 👇 محتوى البالون (الشرح)
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
                                      textDirection: TextDirection.rtl,
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

                                // 👇 الكرت الأساسي
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
                                    textDirection: TextDirection.rtl,
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
                                    textDirection: TextDirection.rtl,
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
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Row(
                              children: [
                                Expanded(
                                  child: _FriendCard(
                                    name: 'سارة',
                                    points: 220,
                                    streak: 4,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _FriendCard(
                                    name: 'خالد',
                                    points: 180,
                                    streak: 2,
                                  ),
                                ),
                              ],
                            ),
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

    // جلب آخر نشاط من user document
    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();

    final lastActivity = userDoc.data()?['lastActivityAt'] as Timestamp?;
    if (lastActivity == null) return 0;

    final lastActivityDate = lastActivity.toDate();
    final now = DateTime.now();

    // إذا مرت أكثر من 24 ساعة
    if (now.difference(lastActivityDate).inHours >= 24) {
      return 0;
    }

    // حساب الستريك العادي
    final activeDays = <DateTime>{};
    for (final doc in docs) {
      final ts =
          (doc.data()['completedAt'] ?? doc.data()['createdAt']) as Timestamp;

      if (ts == null) continue;
      final date = ts.toDate();
      final dayOnly = DateTime(date.year, date.month, date.day);
      activeDays.add(dayOnly);
    }

    int streak = 0;
    DateTime cursor = DateTime.now();
    cursor = DateTime(cursor.year, cursor.month, cursor.day);

    while (activeDays.contains(cursor)) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }

    return streak;
  }

  void _showTaskProgressSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return DraggableScrollableSheet(
          initialChildSize: 0.65,
          minChildSize: 0.5,
          maxChildSize: 0.9,
          builder: (_, controller) {
            return Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: const _UserTaskProgressCard(),
            );
          },
        );
      },
    );
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
        textDirection: TextDirection.rtl,
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
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('submissions')
          .where('userId', isEqualTo: widget.userId)
          .where('status', isEqualTo: 'approved')
          .orderBy('createdAt', descending: true)
          .limit(30) // 30 يوم كافية
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return _StreakBadge(days: 0);
        }

        final docs = snap.data!.docs;
        if (docs.isEmpty) {
          return _StreakBadge(days: 0);
        }

        // أخذ آخر إنجاز
        final latestSubmission = docs.first;
        final latestTimestamp =
            latestSubmission.data()['createdAt'] as Timestamp;
        final latestDate = latestTimestamp.toDate();

        final now = DateTime.now();
        final hoursSinceLast = now.difference(latestDate).inHours;

        // إذا مر أكثر من 48 ساعة منذ آخر إنجاز
        if (hoursSinceLast > 48) {
          return _StreakBadge(days: 0);
        }

        // استخراج الأيام الفريدة
        final uniqueDays = <DateTime>{};
        for (final doc in docs) {
          final ts = doc.data()['createdAt'] as Timestamp;
          final date = ts.toDate();
          final dayOnly = DateTime(date.year, date.month, date.day);
          uniqueDays.add(dayOnly);
        }

        // حساب الستريك بسيط
        int streak = 0;
        final today = DateTime(now.year, now.month, now.day);
        DateTime currentDay = today;

        while (uniqueDays.contains(currentDay)) {
          streak++;
          currentDay = currentDay.subtract(const Duration(days: 1));
        }

        return _StreakBadge(days: streak);
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

      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      final data = userDoc.data() ?? {};
      final lastUpdate = data['lastStreakUpdate'] as Timestamp?;
      int currentStreak = (data['currentStreak'] as int?) ?? 0;

      if (lastUpdate == null) {
        // أول مرة
        await userRef.update({
          'currentStreak': 1,
          'lastStreakUpdate': FieldValue.serverTimestamp(),
        });
        return;
      }

      final lastUpdateDay = lastUpdate.toDate();
      final lastUpdateDayOnly = DateTime(
        lastUpdateDay.year,
        lastUpdateDay.month,
        lastUpdateDay.day,
      );

      final difference = today.difference(lastUpdateDayOnly).inDays;

      if (difference == 0) {
        // نفس اليوم - لا تغيير
        return;
      } else if (difference == 1) {
        // اليوم التالي - زيادة الستريك
        await userRef.update({
          'currentStreak': currentStreak + 1,
          'lastStreakUpdate': FieldValue.serverTimestamp(),
        });
      } else {
        // فجوة أكثر من يوم - إعادة إلى 1
        await userRef.update({
          'currentStreak': 1,
          'lastStreakUpdate': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      print('Error updating streak: $e');
    }
  }

  static Future<int> getCurrentStreak() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return 0;

    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();

    final data = doc.data() ?? {};
    return data['currentStreak'] as int? ?? 0;
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
                                        textDirection: TextDirection.rtl,
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

  String get _rangeLabel {
    switch (_range) {
      case 'سنة':
        return 'سنة ${_cursorDate.year}';
      case 'شهر':
        return '${_cursorDate.month}/${_cursorDate.year}';
      case 'أسبوع':
        // 🔧 حساب صحيح للأسبوع يبدأ من الأحد
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

  Stream<QuerySnapshot<Map<String, dynamic>>> _getTasksStream(String uid) {
    return FirebaseFirestore.instance
        .collection('submissions')
        .where('userId', isEqualTo: uid)
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
          /// العنوان + الفلتر
          Row(
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
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: appColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: appColors.primary.withOpacity(0.3)),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _range,
                    icon: const Icon(
                      Icons.arrow_drop_down,
                      size: 20,
                      color: appColors.primary,
                    ),
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() {
                        _range = v;
                        _cursorDate = DateTime.now(); // نرجع للفترة الحالية
                      });
                    },
                    items: ranges
                        .map(
                          (e) => DropdownMenuItem(
                            value: e,
                            child: Text(
                              e,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: appColors.dark,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          /// ---------- DATA ----------
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _getTasksStream(uid),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const SizedBox(
                  height: 175,
                  child: Center(
                    child: CircularProgressIndicator(color: appColors.primary),
                  ),
                );
              }

              final bars = _buildSpots(snap.data?.docs ?? []);

              final maxY = bars
                  .map((e) => e.barRods.first.toY)
                  .reduce((a, b) => a > b ? a : b);

              final average =
                  bars.map((e) => e.barRods.first.toY).reduce((a, b) => a + b) /
                  bars.length;

              return Column(
                children: [
                  SizedBox(
                    height: 160,
                    child: BarChart(
                      BarChartData(
                        minY: 0,
                        maxY: maxY == 0 ? 3 : null, // حد أدنى للمحور Y
                        gridData: FlGridData(
                          show: true,
                          drawVerticalLine: false,
                          horizontalInterval: maxY == 0
                              ? 1
                              : math.max(1, (maxY / 3).ceilToDouble()),
                        ),
                        titlesData: _buildTitles(),
                        borderData: FlBorderData(
                          show: true,
                          border: Border.all(
                            color: Colors.grey[300]!,
                            width: 1,
                          ),
                        ),
                        barGroups: bars,
                        barTouchData: BarTouchData(
                          enabled: true,
                          touchTooltipData: BarTouchTooltipData(
                            tooltipBgColor: appColors.primary,
                            getTooltipItem: (group, _, rod, __) {
                              return BarTooltipItem(
                                '${rod.toY.toInt()} مهمة',
                                const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.chevron_left),
                        onPressed: _goPrev,
                      ),
                      Text(
                        _rangeLabel,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.chevron_right),
                        onPressed: _canGoNext ? _goNext : null,
                      ),
                    ],
                  ),

                  /// ---------- MINI STATS ----------
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildCompactMiniStat(
                          'الأعلى',
                          maxY.toInt().toString(),
                        ),
                        _buildCompactMiniStat(
                          'المتوسط',
                          average.toStringAsFixed(1),
                        ),
                        _buildCompactMiniStat('الفترة', _range),
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

  /// ---------- Titles ----------
  FlTitlesData _buildTitles() {
    return FlTitlesData(
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 36,
          interval: _getInterval(), // 🔹 إضافة تباعد
          getTitlesWidget: (value, _) {
            final index = value.toInt();

            if (_range == 'اليوم') {
              // 🔹 عرض ساعات مختارة فقط
              final showHours = [0, 3, 6, 9, 12, 15, 18, 21, 23];
              if (showHours.contains(index)) {
                return Text('$index', style: const TextStyle(fontSize: 10));
              }
              return const SizedBox();
            }

            if (_range == 'أسبوع') {
              const days = ['أحد', 'إثن', 'ثلا', 'أرب', 'خم', 'جم', 'سبت'];
              if (index >= 0 && index < 7) {
                return Text(days[index], style: const TextStyle(fontSize: 10));
              }
              return const SizedBox();
            }

            if (_range == 'شهر') {
              final day = index + 1; // تحويل من 0-based إلى 1-based
              // 🔹 عرض أيام مختارة فقط
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

            // 🔹 السنة
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
          reservedSize: 28,
          interval: 1,
          getTitlesWidget: (value, _) {
            return Text(
              value.toInt().toString(),
              style: const TextStyle(fontSize: 10),
            );
          },
        ),
      ),
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
    );
  }

  // 🔹 دالة تحدد التباعد المناسب لكل فترة
  double _getInterval() {
    switch (_range) {
      case 'اليوم':
        return 3.0; // كل 3 وحدات
      case 'أسبوع':
        return 1.0;
      case 'شهر':
        return 5.0; // كل 5 وحدات
      case 'سنة':
        return 1.0;
      default:
        return 1.0;
    }
  }

  /// ---------- Empty ----------
  Widget _buildNoData(String text) {
    return SizedBox(
      height: 175,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.bar_chart_outlined, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 12),
            Text(text, style: TextStyle(color: Colors.grey[600], fontSize: 14)),
          ],
        ),
      ),
    );
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
    final Map<int, int> buckets = {};

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
      totalBars = 24; // ساعات اليوم
      startDate = DateTime(
        _cursorDate.year,
        _cursorDate.month,
        _cursorDate.day,
      );
      endDate = startDate.add(const Duration(days: 1));
    }

    // 🔹 تهيئة جميع الأشرطة بصفر
    for (int i = 0; i < totalBars; i++) {
      buckets[i] = 0;
    }

    // 🔹 ملء البيانات الفعلية
    for (final doc in docs) {
      final data = doc.data();
      final Timestamp? ts = data['completedAt'] ?? data['createdAt'];
      if (ts == null) continue;

      final date = ts.toDate();

      // ✅ تأكد من التاريخ ضمن النطاق
      if (date.isBefore(startDate) || date.isAfter(endDate)) continue;

      int key;
      if (_range == 'اليوم') {
        key = date.hour; // 0-23
      } else if (_range == 'أسبوع') {
        // 🔹 نحتاج لمعرفة اليوم بالنسبة لبداية الأسبوع
        final diff = date.difference(startDate).inDays;
        key = diff; // 0-6
      } else if (_range == 'شهر') {
        key = date.day - 1; // 0-30 (لأن days من 1-31)
      } else {
        key = date.month - 1; // 0-11
      }

      // 🔹 تحقق من صحة الفهرس
      if (key >= 0 && key < totalBars) {
        buckets[key] = (buckets[key] ?? 0) + 1;
      }
    }

    // 🔹 إنشاء الأشرطة مع إصلاح الخطأ
    return List.generate(totalBars, (index) {
      return BarChartGroupData(
        x: index, // 🔹 تأكد من أن x هو double
        barRods: [
          BarChartRodData(
            toY: (buckets[index] ?? 0).toDouble(),
            width: _getBarWidth(), // 🔹 عرض شريط ديناميكي
            borderRadius: BorderRadius.circular(4),
            color: (buckets[index] ?? 0) > 0
                ? appColors.primary
                : Colors.grey[300]!,
            backDrawRodData: BackgroundBarChartRodData(
              show: true,
              toY: (buckets[index] ?? 0).toDouble() + 0.5,
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
        return 8.0; // 24 شريط → أضيق
      case 'أسبوع':
        return 14.0; // 7 أشرطة → أوسع
      case 'شهر':
        return 4.0; // 31 شريط → أضيق جداً
      case 'سنة':
        return 10.0; // 12 شريط → متوسط
      default:
        return 10.0;
    }
  }

  // 🔧 دالة لتحويل اليوم إلى فهرس يبدأ من الأحد = 0
  int _getDayIndex(DateTime date) {
    // تحويل: الأحد = 0, الإثنين = 1, ..., السبت = 6
    return date.weekday % 7;
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
        // 🔧 حساب صحيح للأسبوع يبدأ من الأحد
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
          /// العنوان + الفلتر
          Row(
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
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: appColors.tealSoft.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: appColors.tealSoft.withOpacity(0.3),
                  ),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _range,
                    icon: Icon(
                      Icons.arrow_drop_down,
                      size: 20,
                      color: appColors.tealSoft,
                    ),
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() {
                        _range = v;
                        _cursorDate = DateTime.now();
                      });
                    },
                    items: ranges
                        .map(
                          (e) => DropdownMenuItem(
                            value: e,
                            child: Text(
                              e,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: appColors.dark,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

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

              final maxY = bars.isNotEmpty
                  ? bars
                        .map((e) => e.barRods.first.toY)
                        .reduce((a, b) => a > b ? a : b)
                  : 0;

              final average = bars.isNotEmpty
                  ? bars
                            .map((e) => e.barRods.first.toY)
                            .reduce((a, b) => a + b) /
                        bars.length
                  : 0;

              return Column(
                children: [
                  SizedBox(
                    height: 160,
                    child: BarChart(
                      BarChartData(
                        minY: 0,
                        maxY: maxY == 0 ? 3 : null,
                        gridData: FlGridData(
                          show: true,
                          drawVerticalLine: false,
                          horizontalInterval: maxY == 0
                              ? 1
                              : math.max(1, (maxY / 3).ceilToDouble()),
                        ),
                        titlesData: _buildTitles(),
                        borderData: FlBorderData(
                          show: true,
                          border: Border.all(
                            color: Colors.grey[300]!,
                            width: 1,
                          ),
                        ),
                        barGroups: bars,
                        barTouchData: BarTouchData(
                          enabled: true,
                          touchTooltipData: BarTouchTooltipData(
                            tooltipBgColor: appColors.tealSoft,
                            getTooltipItem: (group, _, rod, __) {
                              return BarTooltipItem(
                                '${rod.toY.toStringAsFixed(1)} كجم',
                                const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.chevron_left),
                        onPressed: _goPrev,
                      ),
                      Text(
                        _rangeLabel,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.chevron_right),
                        onPressed: _canGoNext ? _goNext : null,
                      ),
                    ],
                  ),

                  /// ---------- MINI STATS ----------
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildCompactMiniStat(
                          'الأعلى',
                          maxY.toStringAsFixed(1),
                        ),
                        _buildCompactMiniStat(
                          'المتوسط',
                          average.toStringAsFixed(1),
                        ),
                        _buildCompactMiniStat('الفترة', _range),
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

  /// ---------- Titles ----------
  FlTitlesData _buildTitles() {
    return FlTitlesData(
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 36,
          interval: _getInterval(),
          getTitlesWidget: (value, _) {
            final index = value.toInt();

            if (_range == 'اليوم') {
              // 🔹 عرض ساعات مختارة فقط
              final showHours = [0, 3, 6, 9, 12, 15, 18, 21, 23];
              if (showHours.contains(index)) {
                return Text('$index', style: const TextStyle(fontSize: 10));
              }
              return const SizedBox();
            }

            if (_range == 'أسبوع') {
              const days = ['أحد', 'إثن', 'ثلا', 'أرب', 'خم', 'جم', 'سبت'];
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

            // 🔹 السنة
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
          reservedSize: 28,
          interval: 1,
          getTitlesWidget: (value, _) {
            return Text(
              value.toInt().toString(),
              style: const TextStyle(fontSize: 10),
            );
          },
        ),
      ),
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
    );
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
      totalBars = 24; // ساعات اليوم
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
        key = date.hour; // 0-23
      } else if (_range == 'أسبوع') {
        final diff = date.difference(startDate).inDays;
        key = diff; // 0-6
      } else if (_range == 'شهر') {
        key = date.day - 1; // 0-30 (لأن days من 1-31)
      } else {
        key = date.month - 1; // 0-11
      }

      // 🔹 تحقق من صحة الفهرس
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
