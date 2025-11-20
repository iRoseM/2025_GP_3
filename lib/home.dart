import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'services/background_container.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/animation.dart';
import 'rewards.dart';
import 'package:showcaseview/showcaseview.dart';

import 'task.dart';
import 'community.dart';
import 'profile.dart';
import 'levels.dart';
import 'map.dart';
import 'services/fcm_service.dart';
import 'services/bottom_nav.dart';
import 'services/connection.dart';
import 'services/title_header.dart';

// لوحة الألوان (هوية Nameer)
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
  BuildContext? _scCtx;  // نخزّن showcaseContext


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
    // عرض زر تخطي الجولة 
  void _showSkipOverlay() {
    if (_skipEntry != null) return;

    _skipEntry = OverlayEntry(
      builder: (ctx) {
        return Positioned(
          bottom: 80,  // ← أفضل منطقة، فوق الـNavbar مباشرة
          left: 16,
          child: Material(
            color: Colors.transparent,
            child: _SkipTourButton(
              onSkip: () {
                final ctrl = (_scCtx != null)
                    ? ShowCaseWidget.of(_scCtx!)
                    : null;

                ctrl?.dismiss();
                _hideSkipOverlay();
                setState(() => _tourRunning = false);
              },
            ),
          ),
        );

      },
    );

  Navigator.of(context, rootNavigator: true).overlay!.insert(_skipEntry!);
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

    if (data != null && data['seenHomeOnboardingV2'] == true) return;
    await ref.set({'seenHomeOnboardingV2': true}, SetOptions(merge: true));
    _tourRunning = true;
    // _showSkipOverlay();
    ShowCaseWidget.of(showcaseContext)?.startShowCase([
      _profileKey,
      _pointsKey,
      _carbonKey,
      _summaryKey,
    ]);
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
          controller?.startShowCase([_ecoLandKey, _bannerKey, _friendsKey, _navKey]);
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
                                    final uid = FirebaseAuth.instance.currentUser?.uid;

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
                                                borderRadius: BorderRadius.circular(999),
                                                onTap: () {
                                                  Navigator.of(context).push(
                                                    MaterialPageRoute(
                                                      builder: (_) => const profilePage(),
                                                    ),
                                                  );
                                                },
                                                child: Container(
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
                                                        color: AppColors.primary
                                                            .withOpacity(.2),
                                                        blurRadius: 12,
                                                        offset: const Offset(0, 4),
                                                      ),
                                                    ],
                                                  ),
                                                  child: const CircleAvatar(
                                                    radius: 24,
                                                    backgroundColor: Colors.transparent,
                                                    child: Icon(
                                                      Icons.person_outline,
                                                      color: AppColors.primary,
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
                                                      color: AppColors.dark,
                                                    ),
                                                  ),
                                                  Text(
                                                    'لنجعل اليوم مميزاً!',
                                                    style: TextStyle(
                                                      fontSize: 13,
                                                      color: AppColors.sea,
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
                                                  color: AppColors.primary,
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
                                                          color: AppColors.dark,
                                                        ),
                                                      ),
                                                      Text(
                                                        'تحقق من اتصالك بالإنترنت',
                                                        style: TextStyle(
                                                          fontSize: 13,
                                                          color: AppColors.sea,
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
                                            padding: EdgeInsets.fromLTRB(16, 16, 16, 12),
                                            child: Row(
                                              children: [
                                                CircularProgressIndicator(
                                                  color: AppColors.primary,
                                                ),
                                                SizedBox(width: 16),
                                                Text(
                                                  'جاري التحميل...',
                                                  style: TextStyle(
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.w600,
                                                    color: AppColors.dark,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          );
                                        }

                                        // 🔸 لو البيانات جاهزة نعرضها
                                        final data = snap.data?.data();
                                        final username = (data?['username'] ?? 'مستخدم')
                                            .toString();

                                        int _asInt(dynamic v) {
                                          if (v is int) return v;
                                          if (v is double) return v.toInt();
                                          if (v == null) return 0;
                                          return int.tryParse('$v') ?? 0;
                                        }

                                        final int points = _asInt(
                                          data?['points'] ?? data?['wallet'],
                                        );

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
                                                    FirebaseAuth.instance.currentUser ==
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
                                                    overlayColor: Colors.black.withOpacity(0.35), // غامق — يخلي التور واضح
                                                    overlayOpacity: 0.35,
                                                    blurValue: 0,
                                                    container: Builder(
                                                      builder: (ctx) => Container(
                                                        padding: const EdgeInsets.all(12),
                                                        decoration: BoxDecoration(
                                                          color: Colors.white,
                                                          borderRadius:
                                                              BorderRadius.circular(16),
                                                          boxShadow: [
                                                            BoxShadow(
                                                              color: Colors.black
                                                                  .withOpacity(0.12),
                                                              blurRadius: 12,
                                                              offset: const Offset(0, 6),
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
                                                                CrossAxisAlignment.start,
                                                            children: [
                                                              const Text(
                                                                "هنا ملفك الشخصي",
                                                                style: TextStyle(
                                                                  fontWeight:
                                                                      FontWeight.w800,
                                                                  fontSize: 16,
                                                                  color: Color.fromARGB(255, 60, 59, 59),
                                                                ),
                                                              ),
                                                              const SizedBox(height: 8),
                                                              const Text(
                                                                'من هنا يمكن متابعة الملف، تعديل الصورة واسم المستخدم، والاطلاع على الإنجازات.',
                                                                textDirection: TextDirection.rtl,   // 👈 أضف هذا
                                                                style: TextStyle(
                                                                  fontSize: 13,
                                                                  height: 1.6,
                                                                  color: Colors.black87,
                                                                ),
                                                              ),
                                                              const SizedBox(height: 8),
                                                              const Align(
                                                                alignment: Alignment.centerRight,
                                                                child: Text(
                                                                  'للتنقل اضغط خارج البالون، ويمكن استخدام زر «تخطي الجولة» أدناه.',
                                                                  style: TextStyle(
                                                                    fontSize: 11,
                                                                    color: Colors.black54,
                                                                  ),
                                                                ),
                                                              ),
                                                              // ⭐ Skip Button (Inside Bubble)
                                                              Align(
                                                                alignment: Alignment.centerLeft,
                                                                child: TextButton(
                                                                onPressed: () {
                                                                  final ctrl = ShowCaseWidget.of(_scCtx!);
                                                                  ctrl?.dismiss();
                                                                },
                                                                child: const Text(
                                                                  'تخطي الجولة',
                                                                  style: TextStyle(
                                                                    color: AppColors.primary,
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

                                                    child: Material(
                                                      color: Colors.transparent,
                                                      child: InkWell(
                                                        borderRadius:
                                                            BorderRadius.circular(999),
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
                                                                AppColors.primary
                                                                    .withOpacity(.2),
                                                                AppColors.mint
                                                                    .withOpacity(.1),
                                                              ],
                                                            ),
                                                            boxShadow: [
                                                              BoxShadow(
                                                                color: AppColors.primary
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
                                                                ? AssetImage(avatarPath)
                                                                : null,
                                                            child: (avatarPath == null)
                                                                ? const Icon(
                                                                    Icons.person_outline,
                                                                    color:
                                                                        AppColors.primary,
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
                                                          color: AppColors.dark,
                                                        ),
                                                      )
                                                    else
                                                      Text(
                                                        'مرحبًا، $username 👋',
                                                        overflow: TextOverflow.ellipsis,
                                                        style: const TextStyle(
                                                          fontSize: 20,
                                                          fontWeight: FontWeight.w800,
                                                          color: AppColors.dark,
                                                        ),
                                                      ),
                                                    const Text(
                                                      'لنجعل اليوم مميزاً!',
                                                      style: TextStyle(
                                                        fontSize: 13,
                                                        color: AppColors.sea,
                                                        fontWeight: FontWeight.w600,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              Showcase.withWidget(
                                                key: _pointsKey,
                                                overlayColor: Colors.black.withOpacity(0.35), // غامق — يخلي التور واضح
                                                overlayOpacity: 0.35,
                                                blurValue: 0,
                                                container: Builder(
                                                  builder: (ctx) {
                                                    final size = MediaQuery.of(ctx).size;

                                                    // مقاس ديناميكي للصورة (أكبر) مع حد أقصى
                                                    final double imgH = math.min(size.width * 0.65, 300);

                                                    return SizedBox(
                                                      width: size.width,
                                                      height: 320, // رفعنا الارتفاع عشان يسمح للنزلة
                                                      child: Stack(
                                                        clipBehavior: Clip.none,
                                                        children: [
                                                          // البالون الأبيض
                                                          Positioned(
                                                            top: 40,
                                                            left: 20,
                                                            child: Container(
                                                              width: 260,
                                                              padding: const EdgeInsets.all(14),
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
                                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                                  children: [
                                                                    Text("هنا نقاطك ",
                                                                        style: TextStyle(
                                                                          fontWeight: FontWeight.w800,
                                                                          fontSize: 16,
                                                                          color: AppColors.dark,
                                                                        )),
                                                                    SizedBox(height: 8),
                                                                    Text(
                                                                      'كل مهمة تُنجَز تضيف نقاطًا إلى رصيدك هنا، ويمكن استبدالها في صفحة الجوائز.',
                                                                      style: TextStyle(fontSize: 13, height: 1.5, color: Colors.black87),
                                                                    ),
                                                                    Align(
                                                                      alignment: Alignment.centerLeft,
                                                                      child: TextButton(
                                                                        onPressed: () {
                                                                          ShowCaseWidget.of(_scCtx!).dismiss();
                                                                        },
                                                                        child: const Text(
                                                                          'تخطي الجولة',
                                                                          style: TextStyle(
                                                                            color: AppColors.primary,
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

                                                          // صورة Nameer — أكبر ولأسفل
                                                          Positioned(
                                                            right: -14,      // أقرب للحافة
                                                            bottom: -60,     // نزّلناها لتحت
                                                            child: Image.asset(
                                                              'assets/img/nameerLeft.png',
                                                              height: imgH,   // أكبر بشكل متناسب
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
                                                  onTap: () {},
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
                              // === إجمالي خفض الكربون ===
                              SliverToBoxAdapter(
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                                  child: Showcase.withWidget(
                                    key: _carbonKey,
                                    overlayColor: Colors.black.withOpacity(0.35),
                                    overlayOpacity: 0.35,
                                    blurValue: 0,

                                    // 👇 مهم: إضافة Builder للحصول على ctx
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
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Text(
                                                'إجمالي خفض الكربون',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w800,
                                                  fontSize: 16,
                                                  color: AppColors.dark,
                                                ),
                                              ),

                                              const SizedBox(height: 8),

                                              const Text(
                                                'هذا المؤشر يوضح مجموع الأثر البيئي الذي حققته من كل مهامك (كجم CO₂e). كلما زاد الرقم زاد تأثيرك الإيجابي.',
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  height: 1.6,
                                                  color: Colors.black87,
                                                ),
                                              ),

                                              const SizedBox(height: 16),

                                              // ⭐ زر تخطي الجولة داخل البالون
                                              Align(
                                                alignment: Alignment.centerLeft,
                                                child: TextButton(
                                                  onPressed: () {
                                                    ShowCaseWidget.of(_scCtx!).dismiss();
                                                  },
                                                  child: const Text(
                                                    'تخطي الجولة',
                                                    style: TextStyle(
                                                      color: AppColors.primary,
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

                                    child: const _CarbonFootprintCard(),
                                  ),
                                ),
                              ),

                              const SliverToBoxAdapter(child: SizedBox(height: 16)),

                              // === Daily progress الداشبورد ===
                              SliverToBoxAdapter(
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                                  child: Showcase.withWidget(
                                    overlayColor: Colors.black.withOpacity(0.35),
                                    overlayOpacity: 0.35,
                                    blurValue: 0,
                                    key: _summaryKey,

                                    // 👇 نضيف Builder للحصول على ctx
                                    container: Builder(
                                      builder: (ctx) => Container(
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(16),
                                          boxShadow: [
                                            BoxShadow(
                                              color: AppColors.primary.withOpacity(.20),
                                              blurRadius: 12,
                                              offset: Offset(0, 4),
                                            ),
                                          ],
                                        ),
                                        child: Directionality(
                                          textDirection: TextDirection.rtl,
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              const Text(
                                                'لوحة التحكم اليومية',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w800,
                                                  fontSize: 16,
                                                  color: AppColors.dark,
                                                ),
                                              ),
                                              const SizedBox(height: 8),
                                              const Text(
                                                'هنا متابعة إنجازات اليوم: نسبة التقدّم، المهام المنجزة والمتبقية، وسلسلة الأيام المتتالية. استخدمها لمعرفة ما يلزمك اليوم.',
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
                                                    ShowCaseWidget.of(_scCtx!).dismiss();
                                                  },
                                                  child: const Text(
                                                    'تخطي الجولة',
                                                    style: TextStyle(
                                                      color: AppColors.primary,
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

                                    child: _DailyProgressCard(
                                      percent: .62,
                                      bullets: const [
                                        'أنهيت مهمتين من قائمة اليوم',
                                        'تبقّى: إعادة تدوير البلاستيك + قراءة مقال',
                                        'سلسلة الاستدامة: 3 أيام متتالية!',
                                      ],
                                      onTapDetails: () {},
                                      colored: false,
                                    ),
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

                                      // 👇 لازم Builder للحصول على ctx
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
                                                    color: AppColors.dark,
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

                                                // ⭐ زر تخطي الجولة
                                                Align(
                                                  alignment: Alignment.centerLeft,
                                                  child: TextButton(
                                                    onPressed: () {
                                                      ShowCaseWidget.of(_scCtx!).dismiss();
                                                    },
                                                    child: const Text(
                                                      'تخطي الجولة',
                                                      style: TextStyle(
                                                        color: AppColors.primary,
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

                                      // 👇 البلوك القديم (بدون تعديل)
                                      child: Container(
                                        padding: const EdgeInsets.all(16),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(24),
                                          boxShadow: const [
                                            BoxShadow(
                                              color: Color(0x14000000),
                                              blurRadius: 18,
                                              offset: Offset(0, 8),
                                            ),
                                          ],
                                          border: Border.all(
                                            color: Color(0xFFE8F1EE),
                                            width: 1.5,
                                          ),
                                        ),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Container(
                                                  padding: const EdgeInsets.all(8),
                                                  decoration: BoxDecoration(
                                                    color: AppColors.primary.withOpacity(.1),
                                                    borderRadius: BorderRadius.circular(12),
                                                  ),
                                                  child: const Icon(
                                                    Icons.terrain_rounded,
                                                    color: AppColors.primary,
                                                    size: 24,
                                                  ),
                                                ),
                                                const SizedBox(width: 10),
                                                const Expanded(
                                                  child: Text(
                                                    'أرضي في EcoLand',
                                                    style: TextStyle(
                                                      fontSize: 18,
                                                      fontWeight: FontWeight.w900,
                                                      color: AppColors.dark,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 14),

                                            SizedBox(
                                              width: double.infinity,
                                              height: 170,
                                              child: IsoLand(
                                                rows: 6,
                                                cols: 6,
                                                height: 150,
                                                topColor: AppColors.mint,
                                                sideColor: AppColors.tealSoft,
                                                gridColor: AppColors.sea,
                                                gridOpacity: .08,
                                              ),
                                            ),
                                          ],
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
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              const Text(
                                                'إعلانات وتحديات سريعة',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w800,
                                                  fontSize: 16,
                                                  color: AppColors.dark,
                                                ),
                                              ),
                                              const SizedBox(height: 8),
                                              const Text(
                                                'ستجد هنا حملات ومهام موسمية تمنح نقاطًا مضاعفة أو جوائز خاصة. اضغط على الإعلان للمشاركة.',
                                                style: TextStyle(fontSize: 13, height: 1.6, color: Colors.black87),
                                              ),

                                              const SizedBox(height: 16),

                                              // ⭐ زر تخطي الجولة
                                              Align(
                                                alignment: Alignment.centerLeft,
                                                child: TextButton(
                                                  onPressed: () {
                                                    ShowCaseWidget.of(_scCtx!).dismiss();
                                                  },
                                                  child: const Text(
                                                    'تخطي الجولة',
                                                    style: TextStyle(
                                                      color: AppColors.primary,
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
                                      label: 'احفظ حيّك نظيفًا - شارك الآن واربح نقاطاً مضاعفة!',
                                      onTap: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(builder: (_) => const RewardsPage()),
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
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              const Text(
                                                'أصدقاؤك ونشاطهم',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w800,
                                                  fontSize: 16,
                                                  color: AppColors.dark,
                                                ),
                                              ),
                                              const SizedBox(height: 8),
                                              const Text(
                                                'تابع سلسلة إنجازات أصدقائك ونقاطهم، وقارِن تقدمك معهم. من هنا يمكنك استعراض الجميع أو إضافة أصدقاء.',
                                                style: TextStyle(fontSize: 13, height: 1.6, color: Colors.black87),
                                              ),

                                              const SizedBox(height: 16),

                                              // ⭐ زر تخطي الجولة
                                              Align(
                                                alignment: Alignment.centerLeft,
                                                child: TextButton(
                                                  onPressed: () {
                                                    ShowCaseWidget.of(_scCtx!).dismiss();
                                                  },
                                                  child: const Text(
                                                    'تخطي الجولة',
                                                    style: TextStyle(
                                                      color: AppColors.primary,
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
                                            color: AppColors.primary.withOpacity(.1),
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: const Icon(
                                            Icons.group,
                                            color: AppColors.primary,
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
                                              color: AppColors.dark,
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
                                          icon: const Icon(Icons.arrow_back, size: 16),
                                          label: const Text('عرض الكل'),
                                          style: TextButton.styleFrom(
                                            foregroundColor: AppColors.primary,
                                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                      bottomNavigationBar: isKeyboardOpen ? null : Showcase.withWidget(
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
                )
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
                color: AppColors.dark,
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
              colors: [AppColors.primary, AppColors.primary, AppColors.mint],
              stops: [0.0, 0.5, 1.0],
              begin: Alignment.bottomLeft,
              end: Alignment.topRight,
            ),
            borderRadius: BorderRadius.circular(100),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withOpacity(.25),
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
          colors: [AppColors.primary, AppColors.primary, AppColors.mint],
          stops: [0.0, 0.5, 1.0],
          begin: Alignment.bottomLeft,
          end: Alignment.topRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(.20),
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
                    vertical: 6,
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
                          color: AppColors.accent,
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

class _CarbonFootprintCard extends StatelessWidget {
  const _CarbonFootprintCard({super.key});

  // ✅ دالة عرض رقم الكربون بدقة ذكية
  String _fmtKg(num? v) {
    final d = (v ?? 0).toDouble();
    if (d == 0) return '0';

    // أرقام صغيرة جدًا: أظهر 3 منازل (مثل 0.037 -> 0.037)
    if (d < 0.1) return d.toStringAsFixed(3);

    // أقل من 1: منزلتين (0.04 -> 0.04، 0.25 -> 0.25)
    if (d < 1) return d.toStringAsFixed(2);

    // من 1 إلى أقل من 10: منزلة واحدة إذا لم يكن عددًا صحيحًا
    if (d < 10) {
      return (d == d.roundToDouble())
          ? d.toStringAsFixed(0)
          : d.toStringAsFixed(1);
    }

    // 10 أو أكثر: بدون كسور إذا كان عددًا صحيحًا، وإلا منزل واحدة
    return (d == d.roundToDouble())
        ? d.toStringAsFixed(0)
        : d.toStringAsFixed(1);
  }

  num _safeToNum(dynamic x) {
    if (x is num) return x;
    if (x == null) return 0;
    return num.tryParse(x.toString()) ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return Container(
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
      child: uid == null
          ? _buildRow(
              context,
              title: 'إجمالي خفض الكربون',
              valueText: '0',
              unit: 'كجم CO₂e',
              loading: false,
            )
          : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(uid)
                  .snapshots(),
              builder: (context, snap) {
                // 🔸 حالة التحميل
                if (snap.connectionState == ConnectionState.waiting) {
                  return _buildRow(
                    context,
                    title: 'إجمالي خفض الكربون',
                    valueText: '—',
                    unit: 'كجم CO₂e',
                    loading: true,
                  );
                }

                // 🔸 خطأ أو لا توجد بيانات
                if (snap.hasError || !snap.hasData || !snap.data!.exists) {
                  return _buildRow(
                    context,
                    title: 'إجمالي خفض الكربون',
                    valueText: '0',
                    unit: 'كجم CO₂e',
                    loading: false,
                  );
                }

                final data = snap.data!.data();

                // نقرأ الحقل الموحّد
                num totalKg = 0;
                if (data != null) {
                  final vNew = data['totalCarbonSaved'];
                  totalKg = _safeToNum(vNew);
                }

                // حماية من NaN أو القيم السالبة
                if (totalKg.isNaN) totalKg = 0;
                if (totalKg < 0) totalKg = 0;

                return _buildRow(
                  context,
                  title: 'إجمالي خفض الكربون',
                  valueText: _fmtKg(totalKg),
                  unit: 'كجم CO₂e',
                  loading: false,
                );
              },
            ),
    );
  }

  Widget _buildRow(
    BuildContext context, {
    required String title,
    required String valueText,
    required String unit,
    required bool loading,
  }) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Row(
        children: [
          // النصوص
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // العنوان
                Text(
                  title,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.dark,
                  ),
                ),
                const SizedBox(height: 8),

                // القيمة والوحدة
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (loading)
                      const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.primary,
                        ),
                      )
                    else
                      Text(
                        valueText,
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          color: AppColors.primary,
                          height: 1.0,
                        ),
                      ),
                    const SizedBox(width: 8),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(
                        unit,
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
          const SizedBox(width: 12),

          // الأيقونة
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.primary, AppColors.mint],
                begin: Alignment.bottomLeft,
                end: Alignment.topRight,
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withOpacity(.25),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: const Icon(Icons.eco_rounded, color: Colors.white, size: 28),
          ),
        ],
      ),
    );
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
      'lastCarbonUpdateAt': null,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    return;
  }

  final data = snap.data()!;
  final updates = <String, dynamic>{};

  if (!data.containsKey('points')) updates['points'] = 0;
  if (!data.containsKey('totalCarbonSaved')) updates['totalCarbonSaved'] = 0;
  if (!data.containsKey('lastCarbonUpdateAt')) {
    updates['lastCarbonUpdateAt'] = null;
  }

  if (updates.isNotEmpty) {
    updates['updatedAt'] = FieldValue.serverTimestamp();
    await ref.set(updates, SetOptions(merge: true));
  }
}

class _DailyProgressCard extends StatelessWidget {
  final double percent;
  final List<String> bullets;
  final VoidCallback? onTapDetails;
  final bool colored;

  const _DailyProgressCard({
    required this.percent,
    required this.bullets,
    this.onTapDetails,
    this.colored = false,
  });

  @override
  Widget build(BuildContext context) {
    final decoration = colored
        ? BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.primary, AppColors.sea],
            ),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withOpacity(.3),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
            ],
          )
        : BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: const [
              BoxShadow(
                color: Color(0x14000000),
                blurRadius: 18,
                offset: Offset(0, 8),
              ),
            ],
          );

    final baseTextColor = colored ? Colors.white : AppColors.dark;
    final iconColor = colored ? Colors.white : AppColors.primary;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: decoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: colored
                      ? Colors.white.withOpacity(.2)
                      : AppColors.primary.withOpacity(.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.dashboard_customize_rounded,
                  color: iconColor,
                  size: 24,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'لوحة التحكم اليومية 🎯',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: baseTextColor,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: _AnimatedRing(percent: percent),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...bullets
              .take(3)
              .map(
                (b) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.check_circle,
                        size: 20,
                        color: colored ? AppColors.accent : AppColors.primary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          b,
                          style: TextStyle(
                            color: baseTextColor,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: onTapDetails,
              icon: Icon(
                Icons.arrow_back,
                size: 16,
                color: colored ? Colors.white : AppColors.primary,
              ),
              label: Text(
                'عرض التفاصيل',
                style: TextStyle(
                  color: colored ? Colors.white : AppColors.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AnimatedRing extends StatelessWidget {
  final double percent;
  const _AnimatedRing({required this.percent});
  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: percent.clamp(0, 1)),
      duration: const Duration(milliseconds: 1200),
      curve: Curves.easeOutBack,
      builder: (_, v, __) => SizedBox(
        width: 70,
        height: 70,
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 70,
              height: 70,
              child: CircularProgressIndicator(
                value: v,
                strokeWidth: 7,
                strokeCap: StrokeCap.round,
                backgroundColor: AppColors.light.withOpacity(.25),
                valueColor: const AlwaysStoppedAnimation<Color>(
                  AppColors.accent,
                ),
              ),
            ),
            Text(
              '${(v * 100).round()}%',
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 16,
                color: AppColors.dark,
              ),
            ),
          ],
        ),
      ),
    );
  }
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
                  child: Icon(Icons.person, color: AppColors.dark, size: 24),
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
                    color: AppColors.dark,
                  ),
                ),
              ),
            ],
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.accent.withOpacity(.12),
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
                    color: AppColors.accent,
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
                color: AppColors.primary,
              ),
              const SizedBox(width: 6),
              Text(
                '$points نقطة',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppColors.dark,
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
              Icon(Icons.close, size: 18, color: AppColors.dark),
              SizedBox(width: 6),
              Text(
                'تخطي الجولة',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: AppColors.dark,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}



