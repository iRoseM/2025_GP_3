import 'dart:math' as math;
import 'dart:ui';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:Nameer/services/connection.dart';
import 'services/background_tracker.dart';

import 'services/launch_decider.dart';
import 'services/firebase_options.dart';
import 'services/splash.dart';
import 'home.dart';
import 'admin_home.dart';
import '../services/app_colors.dart';
import 'package:google_sign_in/google_sign_in.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

Future<void> setupFlutterNotifications() async {
  const AndroidInitializationSettings initSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  const InitializationSettings initSettings = InitializationSettings(
    android: initSettingsAndroid,
  );

  await flutterLocalNotificationsPlugin.initialize(initSettings);

  // قناة عرض الإشعار
  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'high_importance_channel', // id
    'إشعارات Nameer', // الاسم
    description: 'القناة المخصصة للإشعارات المهمة',
    importance: Importance.high,
  );

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >()
      ?.createNotificationChannel(channel);

  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    final notification = message.notification;
    if (notification != null) {
      flutterLocalNotificationsPlugin.show(
        notification.hashCode,
        notification.title,
        notification.body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'high_importance_channel',
            'إشعارات Nameer',
            importance: Importance.high,
            priority: Priority.high,
            icon: '@mipmap/ic_launcher',
          ),
        ),
      );
    }
  });
}

// 🔔 استقبال الإشعارات في الخلفية
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  FirebaseMessaging messaging = FirebaseMessaging.instance;

  NotificationSettings settings = await messaging.requestPermission(
    alert: true,
    badge: true,
    sound: true,
  );

  print('🔔 حالة الإذن: ${settings.authorizationStatus}');

  // انتظار استلام التوكن
  try {
    String? token = await messaging.getToken();
    if (token != null) {
      print('🔥 FCM Token (تم بنجاح): $token');
    } else {
      print('⚠️ لم يتم الحصول على التوكن بعد، أعد التشغيل.');
    }
  } catch (e) {
    print('❌ خطأ أثناء جلب التوكن: $e');
  }
}
/* ======================= تهيئة ======================= */

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  // تتبّع الخلفية (نفعّله قبل runApp)
  await BackgroundTracker.initialize();
  // الإشعارات المحلية + FCM
  await setupFlutterNotifications();
  // استقبال رسائل FCM بالخلفية
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(seedColor: appColors.primary);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Nameer Register',
      locale: const Locale('ar'),
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme.copyWith(
          primary: appColors.primary,
          secondary: appColors.light,
          onPrimary: Colors.white,
        ),
        fontFamily: GoogleFonts.ibmPlexSansArabic().fontFamily,
        textTheme: GoogleFonts.ibmPlexSansArabicTextTheme(),
        primaryTextTheme: GoogleFonts.ibmPlexSansArabicTextTheme(),
        scaffoldBackgroundColor: appColors.background,
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: appColors.primary,
            foregroundColor: Colors.white,
            textStyle: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(28),
            ),
            minimumSize: const Size.fromHeight(52),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(foregroundColor: appColors.dark),
        ),
        inputDecorationTheme: const InputDecorationTheme(
          prefixIconColor: appColors.primary,
          suffixIconColor: appColors.primary,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(14)),
          ),
          enabledBorder: OutlineInputBorder(
            borderSide: BorderSide(color: appColors.light, width: 1.2),
            borderRadius: BorderRadius.all(Radius.circular(14)),
          ),
          focusedBorder: OutlineInputBorder(
            borderSide: BorderSide(color: appColors.primary, width: 1.6),
            borderRadius: BorderRadius.all(Radius.circular(14)),
          ),
          errorBorder: OutlineInputBorder(
            borderSide: BorderSide(color: slackMesseges.red),
            borderRadius: BorderRadius.all(Radius.circular(14)),
          ),
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      ),
      home: const LaunchDecider(),
    );
  }
}

/* ======================= صفحة تسجيل الدخول ======================= */

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage>
    with TickerProviderStateMixin {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  final _ageCtrl = TextEditingController();
  String _gender = 'male';

  final _formKey = GlobalKey<FormState>();
  bool _obscure = true;
  bool _googleNewUserMode = false;
  String? _googleUid;

  late final AnimationController _bgCtrl; // خلفية متحركة
  late final AnimationController _introCtrl; // دخول متدرج
  late final AnimationController _shakeCtrl; // اهتزاز خطأ
  late final AnimationController _pressCtrl; // ضغط الزر

  @override
  void initState() {
    super.initState();
    _bgCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 14),
    )..repeat();
    _introCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..forward();
    _shakeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _pressCtrl = AnimationController(
      vsync: this,
      lowerBound: 0.0,
      upperBound: 0.06,
      duration: const Duration(milliseconds: 140),
    );
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _usernameCtrl.dispose();
    _ageCtrl.dispose();
    _bgCtrl.dispose();
    _introCtrl.dispose();
    _shakeCtrl.dispose();
    _pressCtrl.dispose();
    super.dispose();
  }

  Future<void> _completeGoogleRegistration() async {
    if (!await hasInternetConnection()) {
      showNoInternetDialog(context);
      return;
    }

    // ✅ فعّل فاليديشن حق الفورم (اللي حطيته بالحقول)
    final ok = _formKey.currentState?.validate() ?? false;
    if (!ok) {
      _shakeCtrl
        ..reset()
        ..forward();
      return;
    }

    if (_googleUid == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('حدث خطأ، أعد المحاولة')));
      return;
    }

    final uid = _googleUid!;
    final email = _emailCtrl.text.trim().toLowerCase();
    final usernameRaw = _usernameCtrl.text.trim();
    final username = usernameRaw.toLowerCase();
    final age = int.tryParse(_ageCtrl.text.trim());
    final gender = _gender;

    // نفس ريجيكس حقك (يبدأ بحرف + طول 3-24)
    final re = RegExp(r'^[a-z][a-z0-9._-]{2,23}$');
    if (!re.hasMatch(username)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('اسم المستخدم غير صالح')));
      return;
    }
    if (age == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('أدخل عمر صحيح')));
      return;
    }

    try {
      final db = FirebaseFirestore.instance;
      final usernameRef = db.collection('usernames').doc(username);
      final userRef = db.collection('users').doc(uid);

      await db.runTransaction((tx) async {
        final snap = await tx.get(usernameRef);
        if (snap.exists) {
          throw 'USERNAME_TAKEN';
        }

        // ✅ نفس إنشاء الحساب: usernames/{username} = { uid }
        tx.set(usernameRef, {'uid': uid});

        // ✅ نفس إنشاء الحساب: users/{uid} كل نفس الحقول
        tx.set(userRef, {
          'email': email,
          'username': username,
          'age': age,
          'gender': gender,
          'role': 'regular',
          'isVerified': true,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      });

      if (!mounted) return;

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const homePage()),
        (_) => false,
      );
    } catch (e) {
      if (!mounted) return;

      if (e.toString().contains('USERNAME_TAKEN')) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: slackMesseges.red,
            content: Text(
              '❌ اسم المستخدم محجوز، جرّب اسمًا آخر',
              style: GoogleFonts.ibmPlexSansArabic(
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
        );
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: slackMesseges.red,
          content: Text(
            '❌ تعذر إكمال التسجيل',
            style: GoogleFonts.ibmPlexSansArabic(
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ),
      );
    }
  }

  // دخول متدرّج
  Widget _stagger({required double start, required Widget child}) {
    final anim = CurvedAnimation(
      parent: _introCtrl,
      curve: Interval(
        start,
        math.min(start + 0.25, 1.0),
        curve: Curves.easeOut,
      ),
    );
    return AnimatedBuilder(
      animation: anim,
      child: child,
      builder: (_, c) => Opacity(
        opacity: anim.value,
        child: Transform.translate(
          offset: Offset(0, (1 - anim.value) * 24),
          child: c,
        ),
      ),
    );
  }

  // اهتزاز عند الخطأ
  Widget _shakeOnError({required Widget child}) {
    return AnimatedBuilder(
      animation: _shakeCtrl,
      child: child,
      builder: (_, c) {
        final t = _shakeCtrl.value;
        final dx = math.sin(t * math.pi * 6) * (1 - t) * 10;
        return Transform.translate(offset: Offset(dx, 0), child: c);
      },
    );
  }

  // دالة "نسيت كلمة المرور"
  Future<void> _resetPassword() async {
    if (!await hasInternetConnection()) {
      showNoInternetDialog(context);
      return;
    }
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'أدخل البريد أولًا',
            style: GoogleFonts.ibmPlexSansArabic(
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ),
      );
      return;
    }
    try {
      await FirebaseAuth.instance.setLanguageCode('ar');
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: slackMesseges.primary,
          content: Text(
            '✅ تم إرسال رابط إعادة التعيين إلى بريدك',
            style: GoogleFonts.ibmPlexSansArabic(
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ),
      );
    } on FirebaseAuthException catch (e) {
      String msg;

      switch (e.code) {
        case 'invalid-email':
          msg =
              'البريد الإلكتروني الذي أدخلته غير صالح. تأكد من كتابته بشكل صحيح.';
          break;
        case 'user-not-found':
          msg = 'لا يوجد حساب مسجّل بهذا البريد الإلكتروني.';
          break;
        case 'network-request-failed':
          msg =
              'تعذّر الاتصال بالإنترنت، يرجى التحقق من الشبكة والمحاولة لاحقًا.';
          break;
        case 'too-many-requests':
          msg =
              'تم إجراء محاولات كثيرة خلال فترة قصيرة، الرجاء الانتظار قليلًا ثم المحاولة مجددًا.';
          break;
        default:
          msg = 'حدث خطأ غير متوقع أثناء إرسال الرابط. حاول مرة أخرى لاحقًا.';
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: slackMesseges.red,
          content: Text(
            '❌ $msg',
            style: GoogleFonts.ibmPlexSansArabic(
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: slackMesseges.red,
          content: Text(
            '❌ خطأ غير متوقع أثناء الإرسال',
            style: GoogleFonts.ibmPlexSansArabic(
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ),
      );
    }
  }

  Future<void> _signInWithGoogle() async {
    if (!await hasInternetConnection()) {
      showNoInternetDialog(context);
      return;
    }

    try {
      final googleSignIn = GoogleSignIn();

      // هذا يخلي Google كل مرة يعرض اختيار الحساب
      await googleSignIn.signOut();
      final googleUser = await googleSignIn.signIn();
      if (googleUser == null) return; // المستخدم كنسل

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final userCred = await FirebaseAuth.instance.signInWithCredential(
        credential,
      );

      final user = userCred.user;
      if (user == null) throw Exception('No user');

      // 🔹 هنا نجيب الرول من Firestore
      final role = await _fetchUserRole(user.uid);

      if (!mounted) return;

      // ✅ إذا أدمن → صفحة الأدمن
      if (role == 'admin') {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const AdminHomePage()),
          (r) => false,
        );
        return;
      }

      // 🔹 غير أدمن → نكمّل منطق اليوزر (جديد / قديم)
      final isNew = await _isNewUser(user.uid);

      if (isNew) {
        setState(() {
          _googleNewUserMode = true;
          _googleUid = user.uid;
          _emailCtrl.text = user.email ?? '';

          // نفضّي حقول إكمال التسجيل
          _usernameCtrl.clear();
          _ageCtrl.clear();
          _gender = 'male';
        });

        _passCtrl.clear(); // لأن Google ما يستخدم كلمة مرور
        return;
      }

      // مستخدم قديم عادي
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const homePage()),
        (r) => false,
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: slackMesseges.red,
          content: Directionality(
            textDirection: TextDirection.rtl,
            child: Text(
              '❌ تعذّر تسجيل الدخول بجوجل (${e.code})',
              textAlign: TextAlign.right,
              style: GoogleFonts.ibmPlexSansArabic(
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: slackMesseges.red,
          content: Directionality(
            textDirection: TextDirection.rtl,
            child: Text(
              '❌ خطأ غير متوقع أثناء تسجيل الدخول بجوجل',
              textAlign: TextAlign.right,
              style: GoogleFonts.ibmPlexSansArabic(
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
        ),
      );
    }
  }

  // ✅ تسجيل دخول + توجيه حسب الدور
  Future<void> _submit() async {
    if (!await hasInternetConnection()) {
      showNoInternetDialog(context);
      return;
    }
    final ok = _formKey.currentState?.validate() ?? false;
    if (!ok) {
      _shakeCtrl
        ..reset()
        ..forward();
      return;
    }

    try {
      final email = _emailCtrl.text.trim();
      final password = _passCtrl.text.trim();

      final cred = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      await cred.user?.reload();
      await cred.user?.getIdToken(true);

      final user = FirebaseAuth.instance.currentUser;

      if (user == null) {
        throw FirebaseAuthException(code: 'user-not-found');
      }

      if (user.emailVerified) {
        // ✅ المستخدم مفعّل، وجّهه حسب الدور
        final role = await _fetchUserRole(user.uid);
        if (!mounted) return;

        if (role == 'admin') {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const AdminHomePage()),
            (r) => false,
          );
        } else {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const homePage()),
            (r) => false,
          );
        }
      } else {
        // ⚠️ المستخدم لم يتحقق من بريده الإلكتروني
        await FirebaseAuth.instance.setLanguageCode('ar');

        try {
          await user.sendEmailVerification();

          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: slackMesseges.primary,
              behavior: SnackBarBehavior.floating,
              content: Directionality(
                textDirection: TextDirection.rtl,
                child: Text(
                  'تم إرسال رسالة التحقق إلى بريدك، يرجى التحقق قبل تسجيل الدخول.',
                  textAlign: TextAlign.right,
                  style: GoogleFonts.ibmPlexSansArabic(
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          );
        } on FirebaseAuthException catch (e) {
          String msg;
          switch (e.code) {
            case 'too-many-requests':
              msg =
                  'تم إجراء محاولات كثيرة خلال فترة قصيرة، الرجاء الانتظار قليلًا ثم المحاولة مجددًا.';
              break;
            case 'network-request-failed':
              msg =
                  'تعذّر الاتصال بالإنترنت، يرجى التحقق من الشبكة والمحاولة لاحقًا.';
              break;
            default:
              msg = 'حدث خطأ غير متوقع أثناء إرسال رسالة التحقق.';
          }

          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: slackMesseges.red,
              content: Directionality(
                textDirection: TextDirection.rtl,
                child: Text(
                  '❌ $msg',
                  textAlign: TextAlign.right,
                  style: GoogleFonts.ibmPlexSansArabic(
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          );
        }

        // ⏩ التوجيه لصفحة التحقق بعد الإشعار
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => VerifyEmailPage(email: email)),
        );
      }
    } on FirebaseAuthException catch (e) {
      String msg = 'تعذّر تسجيل الدخول (${e.code})';
      switch (e.code) {
        case 'invalid-credential':
          msg = 'بيانات الدخول غير صحيحة';
          break;
        case 'invalid-email':
          msg = 'بريد إلكتروني غير صالح';
          break;
        case 'user-disabled':
          msg = 'تم تعطيل هذا الحساب';
          break;
        case 'user-not-found':
        case 'wrong-password':
          msg = 'بيانات الدخول غير صحيحة';
          break;
        case 'network-request-failed':
          msg = 'تعذّر الاتصال — تأكد من الإنترنت';
          break;
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: slackMesseges.red,
          content: Directionality(
            textDirection: TextDirection.rtl,
            child: Text(
              '❌ $msg',
              textAlign: TextAlign.right,
              style: GoogleFonts.ibmPlexSansArabic(
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: slackMesseges.red,
          content: Directionality(
            textDirection: TextDirection.rtl,
            child: Text(
              '❌ خطأ غير متوقع أثناء تسجيل الدخول',
              textAlign: TextAlign.right,
              style: GoogleFonts.ibmPlexSansArabic(
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
        ),
      );
    }
  }

  Future<String?> _fetchUserRole(String uid) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      return (doc.data() ?? const {})['role'] as String?;
    } catch (_) {
      return null;
    }
  }

  Future<bool> _isNewUser(String uid) async {
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();
    return !doc.exists;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: Stack(
          children: [
            // الخلفية المتحركة
            AnimatedBuilder(
              animation: _bgCtrl,
              builder: (_, __) {
                final t = _bgCtrl.value;
                return CustomPaint(
                  painter: GradientBackgroundPainter(t),
                  child: const SizedBox.expand(),
                );
              },
            ),

            // Blobs شفافة
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _bgCtrl,
                builder: (_, __) {
                  final t = _bgCtrl.value;
                  return Stack(
                    children: [
                      _blob(
                        right: 20 + 10 * math.sin(2 * math.pi * t),
                        top: 80 + 20 * math.cos(2 * math.pi * t),
                        size: 180,
                        color: appColors.primary.withOpacity(.12),
                      ),
                      _blob(
                        left: -40 + 30 * math.cos(2 * math.pi * (t + .3)),
                        bottom: -10 + 25 * math.sin(2 * math.pi * (t + .3)),
                        size: 220,
                        color: appColors.light.withOpacity(.10),
                      ),
                    ],
                  );
                },
              ),
            ),

            // المحتوى
            SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 16,
                    ),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight,
                      ),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 440),
                          child: Form(
                            key: _formKey,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const SizedBox(height: 8),

                                // Logo
                                _stagger(
                                  start: 0.0,
                                  child: Column(
                                    children: [
                                      Hero(
                                        tag: 'logo',
                                        child: SizedBox(
                                          width: 200,
                                          height: 200,
                                          child: Image.asset(
                                            'assets/img/logo.png',
                                            fit: BoxFit.contain,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                const SizedBox(height: 20),

                                _stagger(
                                  start: .25,
                                  child: Align(
                                    alignment: Alignment.centerRight,
                                    child: Text(
                                      'البريد الإلكتروني',
                                      style: TextStyle(
                                        color: Colors.black.withOpacity(0.75),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),

                                _stagger(
                                  start: .3,
                                  child: _shakeOnError(
                                    child: TextFormField(
                                      controller: _emailCtrl,
                                      keyboardType: TextInputType.emailAddress,
                                      textInputAction: TextInputAction.next,
                                      decoration: const InputDecoration(
                                        prefixIcon: Icon(Icons.email_outlined),
                                        hintText: 'name@example.com',
                                      ),
                                      validator: (v) {
                                        if (v == null || v.trim().isEmpty) {
                                          return 'أدخل البريد الإلكتروني';
                                        }
                                        final emailReg = RegExp(
                                          r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                                        );
                                        if (!emailReg.hasMatch(v.trim())) {
                                          return 'بريد إلكتروني غير صالح';
                                        }
                                        return null;
                                      },
                                    ),
                                  ),
                                ),

                                const SizedBox(height: 18),

                                if (!_googleNewUserMode) ...[
                                  _stagger(
                                    start: .45,
                                    child: Align(
                                      alignment: Alignment.centerRight,
                                      child: Text(
                                        'كلمة المرور',
                                        style: TextStyle(
                                          color: Colors.black.withOpacity(0.75),
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 8),

                                  _stagger(
                                    start: .5,
                                    child: _shakeOnError(
                                      child: TextFormField(
                                        controller: _passCtrl,
                                        obscureText: _obscure,
                                        textInputAction: TextInputAction.done,
                                        onFieldSubmitted: (_) => _submit(),
                                        decoration: InputDecoration(
                                          prefixIcon: const Icon(
                                            Icons.lock_outline,
                                          ),
                                          hintText: '••••••••',
                                          errorMaxLines: 3,
                                          suffixIcon: IconButton(
                                            onPressed: () => setState(
                                              () => _obscure = !_obscure,
                                            ),
                                            icon: Icon(
                                              _obscure
                                                  ? Icons.visibility_outlined
                                                  : Icons
                                                        .visibility_off_outlined,
                                              color: _obscure
                                                  ? appColors.primary
                                                  : Colors.grey,
                                            ),
                                          ),
                                        ),
                                        validator: (v) {
                                          if (v == null || v.isEmpty) {
                                            return 'أدخل كلمة المرور';
                                          }

                                          final hasUpper = RegExp(
                                            r'[A-Z]',
                                          ).hasMatch(v);
                                          final hasLower = RegExp(
                                            r'[a-z]',
                                          ).hasMatch(v);
                                          final longEnough = v.length >= 8;

                                          if (!hasUpper ||
                                              !hasLower ||
                                              !longEnough) {
                                            return 'يجب أن تحتوي كلمة المرور على:\n'
                                                '• حرف كبير وحرف صغير على الأقل\n'
                                                '• ٨ أحرف على الأقل';
                                          }

                                          return null;
                                        },
                                      ),
                                    ),
                                  ),
                                ] else ...[
                                  _stagger(
                                    start: .45,
                                    child: Align(
                                      alignment: Alignment.centerRight,
                                      child: Text(
                                        'اسم المستخدم',
                                        style: TextStyle(
                                          color: Colors.black.withOpacity(0.75),
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 8),

                                  _stagger(
                                    start: .5,
                                    child: _shakeOnError(
                                      child: TextFormField(
                                        controller: _usernameCtrl,
                                        textInputAction: TextInputAction.next,
                                        decoration: const InputDecoration(
                                          prefixIcon: Icon(
                                            Icons.person_outline,
                                          ),
                                          hintText: 'nameer_user',
                                        ),
                                        validator: (v) {
                                          if (!_googleNewUserMode) return null;

                                          final val = (v ?? '')
                                              .trim()
                                              .toLowerCase();
                                          if (val.isEmpty)
                                            return 'أدخل اسم المستخدم';
                                          if (val.length < 3)
                                            return 'اسم المستخدم لازم يكون 3 أحرف على الأقل';
                                          if (val.length > 24)
                                            return 'اسم المستخدم طويل جدًا';

                                          // نفس SignUpPage بالضبط
                                          final re = RegExp(
                                            r'^[a-z][a-z0-9._-]{2,23}$',
                                          );
                                          if (!re.hasMatch(val))
                                            return 'اسم المستخدم غير صالح';

                                          return null;
                                        },
                                      ),
                                    ),
                                  ),

                                  const SizedBox(height: 16),

                                  _stagger(
                                    start: .55,
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: TextFormField(
                                            controller: _ageCtrl,
                                            keyboardType: TextInputType.number,
                                            inputFormatters: [
                                              FilteringTextInputFormatter
                                                  .digitsOnly,
                                            ],
                                            decoration: const InputDecoration(
                                              prefixIcon: Icon(
                                                Icons.cake_outlined,
                                              ),
                                              hintText: 'العمر (مثال: 18)',
                                            ),
                                            validator: (v) {
                                              if (!_googleNewUserMode)
                                                return null;
                                              if (v == null || v.trim().isEmpty)
                                                return 'أدخل العمر';
                                              final n = int.tryParse(v.trim());
                                              if (n == null)
                                                return 'أدخل رقمًا صحيحًا';
                                              if (n < 7 || n > 120)
                                                return 'العمر غير مناسب';
                                              return null;
                                            },
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: DecoratedBox(
                                            decoration: BoxDecoration(
                                              borderRadius:
                                                  BorderRadius.circular(14),
                                              border: Border.all(
                                                color: appColors.light,
                                                width: 1.2,
                                              ),
                                            ),
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 6,
                                                  ),
                                              child: Row(
                                                children: [
                                                  Expanded(
                                                    child: _GenderChip(
                                                      selected:
                                                          _gender == 'male',
                                                      icon: Icons.male,
                                                      label: 'ذكر',
                                                      onTap: () => setState(
                                                        () => _gender = 'male',
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Expanded(
                                                    child: _GenderChip(
                                                      selected:
                                                          _gender == 'female',
                                                      icon: Icons.female,
                                                      label: 'أنثى',
                                                      onTap: () => setState(
                                                        () =>
                                                            _gender = 'female',
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],

                                const SizedBox(height: 26),

                                // زر تسجيل دخول
                                _stagger(
                                  start: .7,
                                  child: SizedBox(
                                    width: double.infinity,
                                    height: 54,
                                    child: GestureDetector(
                                      onTapDown: (_) => _pressCtrl.forward(),
                                      onTapCancel: () => _pressCtrl.reverse(),
                                      onTapUp: (_) => _pressCtrl.reverse(),
                                      child: AnimatedBuilder(
                                        animation: _pressCtrl,
                                        builder: (_, __) {
                                          final scale = 1 - _pressCtrl.value;
                                          return Transform.scale(
                                            scale: scale,
                                            child: _AnimatedGradientButton(
                                              label: _googleNewUserMode
                                                  ? 'إكمال التسجيل'
                                                  : 'تسجيل دخول',
                                              onPressed: _googleNewUserMode
                                                  ? _completeGoogleRegistration
                                                  : _submit,
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                                ),

                                const SizedBox(height: 8),
                                // ✅ رابط الرجوع لتسجيل الدخول (يظهر فقط في وضع Google New User)
                                if (_googleNewUserMode) ...[
                                  _stagger(
                                    start: .78,
                                    child: _BouncyLink(
                                      label: 'لدي حساب بالفعل — تسجيل دخول',
                                      onTap: () async {
                                        // تسجيل خروج من Google عشان يعرض اختيار الحساب مرة ثانية
                                        try {
                                          await GoogleSignIn().signOut();
                                        } catch (_) {}

                                        // تسجيل خروج من Firebase
                                        try {
                                          await FirebaseAuth.instance.signOut();
                                        } catch (_) {}

                                        if (!mounted) return;

                                        setState(() {
                                          _googleNewUserMode = false;
                                          _googleUid = null;
                                          _emailCtrl.clear();
                                          _usernameCtrl.clear();
                                          _ageCtrl.clear();
                                          _gender = 'male';
                                        });
                                      },
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                ],

                                if (!_googleNewUserMode) ...[
                                  SizedBox(
                                    width: double.infinity,
                                    height: 54,
                                    child: OutlinedButton.icon(
                                      onPressed: _signInWithGoogle,
                                      // مؤقت
                                      icon: Image.asset(
                                        'assets/img/google.png',
                                        width: 22,
                                        height: 22,
                                      ),
                                      label: Text(
                                        'متابعة باستخدام Google',
                                        style: GoogleFonts.ibmPlexSansArabic(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 16,
                                          color: appColors.dark,
                                        ),
                                      ),
                                      style: OutlinedButton.styleFrom(
                                        backgroundColor: Colors.white,
                                        side: const BorderSide(
                                          color: appColors.light,
                                          width: 1.2,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            28,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                                // زر نسيت كلمة المرور
                                if (!_googleNewUserMode) ...[
                                  _stagger(
                                    start: .78,
                                    child: Align(
                                      alignment: Alignment.centerLeft,
                                      child: TextButton(
                                        onPressed: _resetPassword,
                                        child: const Text('نسيت كلمة المرور؟'),
                                      ),
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 8),
                                if (!_googleNewUserMode) ...[
                                  _stagger(
                                    start: .85,
                                    child: _BouncyLink(
                                      label: ' انشاء حساب جديد',
                                      onTap: () {
                                        Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) => const SignUpPage(),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 8),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Blob helper
  Widget _blob({
    double? left,
    double? right,
    double? top,
    double? bottom,
    required double size,
    required Color color,
  }) {
    return Positioned(
      left: left,
      right: right,
      top: top,
      bottom: bottom,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
      ),
    );
  }
}

/* ======================= خلفية متحركة ======================= */

class GradientBackgroundPainter extends CustomPainter {
  final double t;
  const GradientBackgroundPainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final g1 = LinearGradient(
      begin: Alignment.topRight,
      end: Alignment.bottomLeft,
      colors: [
        appColors.background,
        Color.lerp(appColors.background, Colors.white, .3)!,
      ],
    ).createShader(Offset.zero & size);
    final g2 = RadialGradient(
      center: Alignment(
        0.8 * math.cos(t * 2 * math.pi),
        0.8 * math.sin(t * 2 * math.pi),
      ),
      radius: 1.2,
      colors: const [Color(0x1A009688), Color(0x00009688)],
    ).createShader(Offset.zero & size);

    final p = Paint()..shader = g1;
    canvas.drawRect(Offset.zero & size, p);

    final p2 = Paint()..shader = g2;
    canvas.drawRect(Offset.zero & size, p2);

    // تموّج علوي بسيط
    final wave = Path()
      ..moveTo(0, size.height * .12)
      ..cubicTo(
        size.width * .25,
        size.height * (.10 + .02 * math.sin(t * 6)),
        size.width * .75,
        size.height * (.14 + .02 * math.cos(t * 6)),
        size.width,
        size.height * .12,
      )
      ..lineTo(size.width, 0)
      ..lineTo(0, 0)
      ..close();
    final pw = Paint()..color = const Color(0x11009688);
    canvas.drawPath(wave, pw);
  }

  @override
  bool shouldRepaint(covariant GradientBackgroundPainter oldDelegate) =>
      oldDelegate.t != t;
}

/* ======================= رابط بنبض ======================= */

class _BouncyLink extends StatefulWidget {
  final String label;
  final VoidCallback? onTap;
  const _BouncyLink({required this.label, this.onTap});

  @override
  State<_BouncyLink> createState() => _BouncyLinkState();
}

class _BouncyLinkState extends State<_BouncyLink>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      lowerBound: 0.0,
      upperBound: 0.04,
      duration: const Duration(milliseconds: 120),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTapDown: (_) => _ctrl.forward(),
        onTapUp: (_) {
          _ctrl.reverse();
          widget.onTap?.call();
        },
        onTapCancel: () => _ctrl.reverse(),
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (_, __) {
            final scale = 1 - _ctrl.value;
            return Transform.scale(
              scale: scale,
              child: Text(
                widget.label,
                style: const TextStyle(
                  decoration: TextDecoration.underline,
                  fontWeight: FontWeight.w600,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/* ======================= صفحة إنشاء حساب جديد ======================= */
enum _ActiveField { none, username, email, password }

enum _FieldStatus { idle, checking, valid, invalid }

class SignUpPage extends StatefulWidget {
  const SignUpPage({super.key});

  @override
  State<SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends State<SignUpPage> with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();

  final _usernameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _ageCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController(); // ✅ جديد

  // Focus
  final _fnUser = FocusNode();
  final _fnEmail = FocusNode();
  final _fnPass = FocusNode();
  final _fnConfirm = FocusNode(); // ✅ جديد

  // نظهر الفيدباك فقط بعد أول فقدان تركيز (blur)
  bool _touchedUser = false;
  bool _touchedEmail = false;
  bool _touchedPass = false;
  bool _touchedConfirm = false; // ✅ جديد

  // حالات الحقول (وتبقى بعد الـ blur)
  _FieldStatus _usernameStatus = _FieldStatus.idle;
  String? _usernameError;
  _FieldStatus _emailStatus = _FieldStatus.idle;
  String? _emailError;
  _FieldStatus _passStatus = _FieldStatus.idle;
  String? _passError;

  _FieldStatus _confirmStatus = _FieldStatus.idle; // ✅ جديد
  String? _confirmError; // ✅ جديد

  bool _obscure = true;
  bool _obscureConfirm = true;
  String _gender = 'male'; // 'male' or 'female'
  bool _reserving = false; // حالة الحجز/الإنشاء

  late final AnimationController _bgCtrl; // خلفية متحركة
  late final AnimationController _introCtrl; // دخول متدرج
  late final AnimationController _pressCtrl; // ضغط الزر

  @override
  void initState() {
    super.initState();
    _bgCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 14),
    )..repeat();
    _introCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..forward();
    _pressCtrl = AnimationController(
      vsync: this,
      lowerBound: 0.0,
      upperBound: 0.06,
      duration: const Duration(milliseconds: 140),
    );

    // مستمعي الـ blur
    _fnUser.addListener(() {
      if (!_fnUser.hasFocus) {
        _touchedUser = true;
        _validateUsername();
      }
    });
    _fnEmail.addListener(() {
      if (!_fnEmail.hasFocus) {
        _touchedEmail = true;
        _validateEmail(); // ← الآن تتحقق من الفورمات فقط
      }
    });
    _fnPass.addListener(() {
      if (!_fnPass.hasFocus) {
        _touchedPass = true;
        _validatePass();
      }
    });
    _fnConfirm.addListener(() {
      // ✅ جديد
      if (!_fnConfirm.hasFocus) {
        _touchedConfirm = true;
        _validateConfirm();
      }
    });
  }

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _ageCtrl.dispose();
    _confirmCtrl.dispose(); // ✅ جديد

    _fnUser.dispose();
    _fnEmail.dispose();
    _fnPass.dispose();
    _fnConfirm.dispose(); // ✅ جديد

    _bgCtrl.dispose();
    _introCtrl.dispose();
    _pressCtrl.dispose();
    super.dispose();
  }

  Widget _stagger({required double start, required Widget child}) {
    final anim = CurvedAnimation(
      parent: _introCtrl,
      curve: Interval(
        start,
        math.min(start + 0.25, 1.0),
        curve: Curves.easeOut,
      ),
    );
    return AnimatedBuilder(
      animation: anim,
      child: child,
      builder: (_, c) => Opacity(
        opacity: anim.value,
        child: Transform.translate(
          offset: Offset(0, (1 - anim.value) * 24),
          child: c,
        ),
      ),
    );
  }

  // ====== عرض متدرج وحدود ======
  OutlineInputBorder _borderFor(_FieldStatus s, {bool focused = false}) {
    Color color;
    double width = focused ? 1.6 : 1.2;
    switch (s) {
      case _FieldStatus.invalid:
        color = Colors.red;
        width = focused ? 1.8 : 1.4;
        break;
      case _FieldStatus.valid:
        color = Colors.green;
        width = focused ? 1.8 : 1.4;
        break;
      case _FieldStatus.checking:
        color = appColors.light;
        break;
      case _FieldStatus.idle:
      default:
        color = appColors.light;
    }
    return OutlineInputBorder(
      borderRadius: const BorderRadius.all(Radius.circular(14)),
      borderSide: BorderSide(color: color, width: width),
    );
  }

  Widget? _statusIcon(_FieldStatus s) {
    switch (s) {
      case _FieldStatus.checking:
        return const Padding(
          padding: EdgeInsetsDirectional.only(end: 6),
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        );
      case _FieldStatus.valid:
        return const Icon(Icons.check_circle, color: Colors.green, size: 22);
      case _FieldStatus.invalid:
        return const Icon(Icons.error_rounded, color: Colors.red, size: 22);
      case _FieldStatus.idle:
        return null;
    }
  }

  // ====== Username check (على الـ blur) ======
  Future<void> _validateUsername() async {
    setState(() {
      _usernameStatus = _FieldStatus.checking;
      _usernameError = null;
    });

    final v = _usernameCtrl.text.trim().toLowerCase(); // ✅ lowercase من البداية

    if (v.isEmpty) {
      setState(() {
        _usernameStatus = _FieldStatus.invalid;
        _usernameError = 'أدخل اسم المستخدم';
      });
      return;
    }

    if (v.length < 3) {
      setState(() {
        _usernameStatus = _FieldStatus.invalid;
        _usernameError = 'اسم المستخدم يجب أن لا يقل عن 3 أحرف';
      });
      return;
    }

    if (v.length > 24) {
      setState(() {
        _usernameStatus = _FieldStatus.invalid;
        _usernameError = 'اسم المستخدم طويل جدًا (الحد الأقصى 24 حرفًا)';
      });
      return;
    }

    // ✅ نفس الريجيكس اللي تستخدمينه بالحجز
    final re = RegExp(r'^[a-z][a-z0-9._-]{2,23}$');
    if (!re.hasMatch(v)) {
      setState(() {
        _usernameStatus = _FieldStatus.invalid;
        _usernameError = 'اسم المستخدم غير صالح (ابدأ بحرف، وبدون مسافات)';
      });
      return;
    }

    try {
      final doc = await FirebaseFirestore.instance
          .collection('usernames')
          .doc(v) // ✅ خلاص v أصلاً lowercase
          .get();

      final taken = doc.exists;
      setState(() {
        if (taken) {
          _usernameStatus = _FieldStatus.invalid;
          _usernameError = 'اسم المستخدم محجوز';
        } else {
          _usernameStatus = _FieldStatus.valid;
          _usernameError = null;
        }
      });
    } catch (_) {
      setState(() {
        _usernameStatus = _FieldStatus.invalid;
        _usernameError = 'تعذّر التحقق الآن';
      });
    }
  }

  // ====== Email: تحقّق ديناميكي للفورمات فقط عبر onChanged ======
  void _onEmailFormatChanged(String v) {
    _touchedEmail = true;
    final raw = v.trim();
    final emailReg = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

    setState(() {
      if (raw.isEmpty) {
        _emailStatus = _FieldStatus.invalid;
        _emailError = 'أدخل البريد الإلكتروني';
      } else if (!emailReg.hasMatch(raw)) {
        _emailStatus = _FieldStatus.invalid;
        _emailError = 'بريد إلكتروني غير صالح';
      } else {
        _emailStatus = _FieldStatus.valid;
        _emailError = null;
      }
    });
  }

  // (على الـ blur) — نفس منطق الفورمات فقط
  Future<void> _validateEmail() async {
    final raw = _emailCtrl.text.trim();
    final emailReg = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

    setState(() {
      if (raw.isEmpty) {
        _emailStatus = _FieldStatus.invalid;
        _emailError = 'أدخل البريد الإلكتروني';
      } else if (!emailReg.hasMatch(raw)) {
        _emailStatus = _FieldStatus.invalid;
        _emailError = 'بريد إلكتروني غير صالح';
      } else {
        _emailStatus = _FieldStatus.valid;
        _emailError = null;
      }
    });
  }

  // ====== Password check (على الـ blur) ======
  void _validatePass() {
    setState(() {
      _passStatus = _FieldStatus.checking;
      _passError = null;
    });

    final v = _passCtrl.text;
    if (v.isEmpty) {
      setState(() {
        _passStatus = _FieldStatus.invalid;
        _passError = 'أدخل كلمة المرور';
      });
      return;
    }
    final hasUpper = RegExp(r'[A-Z]').hasMatch(v);
    final hasLower = RegExp(r'[a-z]').hasMatch(v);
    final longEnough = v.length >= 8;

    if (hasUpper && hasLower && longEnough) {
      setState(() {
        _passStatus = _FieldStatus.valid;
        _passError = null;
      });
    } else {
      setState(() {
        _passStatus = _FieldStatus.invalid;
        _passError =
            'كلمة المرور يجب أن تكون 8 أحرف على الأقل وتحتوي على حرف كبير وصغير';
      });
    }

    // كل ما تغيّرت كلمة المرور نعيد تقييم التأكيد (لو مستخدم لمس خانته)
    if (_touchedConfirm) {
      _validateConfirm();
    }
  }

  // ====== Confirm password (على الـ blur / onChanged) ======  ✅ جديد
  void _validateConfirm() {
    setState(() {
      _confirmStatus = _FieldStatus.checking;
      _confirmError = null;
    });

    final v = _confirmCtrl.text;
    if (v.isEmpty) {
      setState(() {
        _confirmStatus = _FieldStatus.invalid;
        _confirmError = 'أدخل تأكيد كلمة المرور';
      });
      return;
    }
    if (v != _passCtrl.text) {
      setState(() {
        _confirmStatus = _FieldStatus.invalid;
        _confirmError = 'كلمتا المرور غير متطابقتين';
      });
      return;
    }

    setState(() {
      _confirmStatus = _FieldStatus.valid;
      _confirmError = null;
    });
  }

  // نفحص الكل قبل الإرسال (نحاكي blur للجميع)
  Future<void> _validateAllBeforeSubmit() async {
    if (!_touchedUser) {
      _touchedUser = true;
      await _validateUsername();
    }
    if (!_touchedEmail) {
      _touchedEmail = true;
      await _validateEmail(); // فورمات فقط
    }
    if (!_touchedPass) {
      _touchedPass = true;
      _validatePass();
    }
    if (!_touchedConfirm) {
      // ✅ جديد
      _touchedConfirm = true;
      _validateConfirm();
    }
  }

  // ====== إنشاء الحساب + إظهار "محجوز" داخل خانة الإيميل إن وجد ======
  Future<void> _submit() async {
    if (!await hasInternetConnection()) {
      showNoInternetDialog(context);
      return;
    }

    await _validateAllBeforeSubmit();

    // لو أي حقل غير صالح نوقف
    if (_usernameStatus == _FieldStatus.invalid ||
        _emailStatus == _FieldStatus.invalid ||
        _passStatus == _FieldStatus.invalid ||
        _confirmStatus == _FieldStatus.invalid) {
      return; // الأخطاء ظاهرة داخل الحقول
    }

    final ok = _formKey.currentState?.validate() ?? false;
    if (!ok) return;

    setState(() => _reserving = true);

    try {
      final email = _emailCtrl.text.trim();
      final password = _passCtrl.text.trim();
      final usernameRaw = _usernameCtrl.text.trim();
      final age = int.tryParse(_ageCtrl.text.trim());
      final gender = _gender;

      // 1) إنشاء مستخدم Auth — Firebase سيتأكد من تكرار الإيميل
      final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      final uid = cred.user!.uid;

      try {
        // 2) احجز الاسم واكتب وثيقة المستخدم داخل ترانزاكشن
        Future<void> _reserveUsernameAndCreateUserDoc({
          required String uid,
          required String usernameRaw,
          required String email,
          required int? age,
          required String gender,
        }) async {
          final db = FirebaseFirestore.instance;

          // لازم يكون lowercase ويبدأ بحرف (مطابق للـ rules)
          final username = usernameRaw.trim().toLowerCase();
          final re = RegExp(r'^[a-z][a-z0-9._-]{2,23}$');
          if (!re.hasMatch(username)) throw 'INVALID_USERNAME';

          final usernameRef = db.collection('usernames').doc(username);
          final userRef = db.collection('users').doc(uid);

          await db.runTransaction((tx) async {
            final snap = await tx.get(usernameRef);
            if (snap.exists) throw 'USERNAME_TAKEN';

            // 👈 مطابق للـ rules: فقط { uid } بدون أي حقول إضافية
            tx.set(usernameRef, {'uid': uid});

            // كتابة بيانات المستخدم
            tx.set(userRef, {
              'email': email.trim().toLowerCase(),
              'username': username,
              'age': age,
              'gender': gender,
              'role': 'regular',
              'isVerified': false,
              'createdAt': FieldValue.serverTimestamp(),
              'updatedAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
          });
        }

        // استدعاء الدالة
        await _reserveUsernameAndCreateUserDoc(
          uid: uid,
          usernameRaw: usernameRaw,
          email: email,
          age: age,
          gender: gender,
        );
      } catch (e) {
        // لو الاسم محجوز/غير صالح نحذف مستخدم Auth الذي تم إنشاؤه للتو
        final err = e.toString();
        if (err.contains('USERNAME_TAKEN') ||
            err.contains('INVALID_USERNAME')) {
          try {
            await cred.user?.delete();
          } catch (_) {}
          setState(() {
            _touchedUser = true;
            _usernameStatus = _FieldStatus.invalid;
            _usernameError = err.contains('USERNAME_TAKEN')
                ? 'اسم المستخدم محجوز، جرّب اسمًا آخر'
                : 'اسم المستخدم غير صالح';
          });
          FocusScope.of(context).requestFocus(_fnUser);
          return;
        }

        // أي خطأ صلاحيات (permissions) — احذف حساب Auth حتى ما يظل الإيميل محجوز
        if (err.contains('permission-denied')) {
          try {
            await cred.user?.delete();
          } catch (_) {}
        }
        rethrow; // يروح للـ catch الخارجي ويطلع Snackbar عام
      }

      // 3) أرسل بريد التحقق
      await FirebaseAuth.instance.setLanguageCode('ar');
      await FirebaseAuth.instance.currentUser?.sendEmailVerification();

      // 4) الانتقال لصفحة التحقق
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => VerifyEmailPage(email: email)),
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;

      if (e.code == 'email-already-in-use') {
        setState(() {
          _touchedEmail = true;
          _emailStatus = _FieldStatus.invalid;
          _emailError = 'البريد مستخدم مسبقًا';
        });
        FocusScope.of(context).requestFocus(_fnEmail);
        return;
      }
      if (e.code == 'invalid-email') {
        setState(() {
          _touchedEmail = true;
          _emailStatus = _FieldStatus.invalid;
          _emailError = 'البريد الإلكتروني غير صالح';
        });
        FocusScope.of(context).requestFocus(_fnEmail);
        return;
      }
      if (e.code == 'weak-password') {
        setState(() {
          _touchedPass = true;
          _passStatus = _FieldStatus.invalid;
          _passError =
              'يجب أن تحتوي كلمة المرور على حرف كبير وحرف صغير على الأقل، وأن تكون مكونة من 8 أحرف على الأقل.';
        });
        FocusScope.of(context).requestFocus(_fnPass);
        return;
      }
      if (e.code == 'network-request-failed') {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'تعذّر الاتصال — تأكد من الإنترنت',
              style: GoogleFonts.ibmPlexSansArabic(
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
        );
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: slackMesseges.red,
          content: Text(
            '❌ خطأ غير متوقع (${e.code})',
            style: GoogleFonts.ibmPlexSansArabic(
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      // يشمل permission-denied من Firestore وغيره
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: slackMesseges.red,
          content: Text(
            '❌ تعذّر إنشاء الحساب (${e.toString()})',
            style: GoogleFonts.ibmPlexSansArabic(
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _reserving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: Stack(
          children: [
            // الخلفية المتحركة
            AnimatedBuilder(
              animation: _bgCtrl,
              builder: (_, __) {
                final t = _bgCtrl.value;
                return CustomPaint(
                  painter: GradientBackgroundPainter(t),
                  child: const SizedBox.expand(),
                );
              },
            ),

            // Blobs شفافة
            PositionedFill(
              child: AnimatedBuilder(
                animation: _bgCtrl,
                builder: (_, __) {
                  final t = _bgCtrl.value;
                  return Stack(
                    children: [
                      _blob(
                        right: 24 + 10 * math.sin(2 * math.pi * t),
                        top: 64 + 16 * math.cos(2 * math.pi * t),
                        size: 160,
                        color: appColors.primary.withOpacity(.10),
                      ),
                      _blob(
                        left: -36 + 24 * math.cos(2 * math.pi * (t + .35)),
                        bottom: -8 + 20 * math.sin(2 * math.pi * (t + .35)),
                        size: 200,
                        color: appColors.light.withOpacity(.10),
                      ),
                    ],
                  );
                },
              ),
            ),

            SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 16,
                    ),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight,
                      ),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 520),
                          child: Form(
                            key: _formKey,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const SizedBox(height: 8),
                                _stagger(
                                  start: 0.0,
                                  child: Column(
                                    children: [
                                      Hero(
                                        tag: 'logo',
                                        child: SizedBox(
                                          width: 140,
                                          height: 140,
                                          child: Image.asset(
                                            'assets/img/logo.png',
                                            fit: BoxFit.contain,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        'إنشاء حساب جديد',
                                        style: TextStyle(
                                          color: appColors.dark.withOpacity(.9),
                                          fontSize: 20,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                const SizedBox(height: 18),

                                // اسم المستخدم
                                _stagger(
                                  start: .1,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      _label('اسم المستخدم'),
                                      const SizedBox(height: 8),
                                      TextFormField(
                                        focusNode: _fnUser,
                                        controller: _usernameCtrl,
                                        textInputAction: TextInputAction.next,
                                        onFieldSubmitted: (_) => FocusScope.of(
                                          context,
                                        ).requestFocus(_fnEmail),
                                        decoration: InputDecoration(
                                          prefixIcon: const Icon(
                                            Icons.person_outline,
                                          ),
                                          hintText: 'nameer_user',
                                          suffixIcon: _touchedUser
                                              ? _statusIcon(_usernameStatus)
                                              : null,
                                          errorText:
                                              _touchedUser &&
                                                  _usernameStatus ==
                                                      _FieldStatus.invalid
                                              ? _usernameError
                                              : null,
                                          enabledBorder: _borderFor(
                                            _touchedUser
                                                ? _usernameStatus
                                                : _FieldStatus.idle,
                                          ),
                                          focusedBorder: _borderFor(
                                            _touchedUser
                                                ? _usernameStatus
                                                : _FieldStatus.idle,
                                            focused: true,
                                          ),
                                          errorBorder: _borderFor(
                                            _FieldStatus.invalid,
                                          ),
                                          focusedErrorBorder: _borderFor(
                                            _FieldStatus.invalid,
                                            focused: true,
                                          ),
                                        ),
                                        validator: (v) {
                                          final val = (v ?? '')
                                              .trim()
                                              .toLowerCase();

                                          if (val.isEmpty) {
                                            return 'أدخل اسم المستخدم';
                                          }

                                          if (val.length < 3) {
                                            return 'اسم المستخدم يجب أن لا يقل عن 3 أحرف';
                                          }

                                          if (val.length > 24) {
                                            return 'اسم المستخدم طويل جدًا (الحد الأقصى 24 حرفًا)';
                                          }

                                          // نفس الريجيكس المستخدم في Google + Firestore
                                          final re = RegExp(
                                            r'^[a-z][a-z0-9._-]{2,23}$',
                                          );
                                          if (!re.hasMatch(val)) {
                                            return 'اسم المستخدم غير صالح (يجب أن يبدأ بحرف وبدون مسافات)';
                                          }

                                          return null; // ✅ صالح
                                        },
                                      ),
                                    ],
                                  ),
                                ),

                                const SizedBox(height: 16),

                                // الإيميل
                                _stagger(
                                  start: .2,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      _label('البريد الإلكتروني'),
                                      const SizedBox(height: 8),
                                      TextFormField(
                                        focusNode: _fnEmail,
                                        controller: _emailCtrl,
                                        keyboardType:
                                            TextInputType.emailAddress,
                                        textInputAction: TextInputAction.next,
                                        onChanged:
                                            _onEmailFormatChanged, // ← ديناميكي (فورمات فقط)
                                        onFieldSubmitted: (_) => FocusScope.of(
                                          context,
                                        ).requestFocus(_fnPass),
                                        decoration: InputDecoration(
                                          prefixIcon: const Icon(
                                            Icons.email_outlined,
                                          ),
                                          hintText: 'name@example.com',
                                          suffixIcon: _touchedEmail
                                              ? _statusIcon(_emailStatus)
                                              : null,
                                          errorText:
                                              _touchedEmail &&
                                                  _emailStatus ==
                                                      _FieldStatus.invalid
                                              ? _emailError
                                              : null,
                                          enabledBorder: _borderFor(
                                            _touchedEmail
                                                ? _emailStatus
                                                : _FieldStatus.idle,
                                          ),
                                          focusedBorder: _borderFor(
                                            _touchedEmail
                                                ? _emailStatus
                                                : _FieldStatus.idle,
                                            focused: true,
                                          ),
                                          errorBorder: _borderFor(
                                            _FieldStatus.invalid,
                                          ),
                                          focusedErrorBorder: _borderFor(
                                            _FieldStatus.invalid,
                                            focused: true,
                                          ),
                                        ),
                                        validator: (v) {
                                          if (v == null || v.trim().isEmpty)
                                            return 'أدخل البريد الإلكتروني';
                                          final emailReg = RegExp(
                                            r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                                          );
                                          if (!emailReg.hasMatch(v.trim()))
                                            return 'بريد إلكتروني غير صالح';
                                          return null;
                                        },
                                      ),
                                    ],
                                  ),
                                ),

                                const SizedBox(height: 16),

                                // كلمة المرور
                                _stagger(
                                  start: .3,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      _label('كلمة المرور'),
                                      const SizedBox(height: 8),
                                      TextFormField(
                                        focusNode: _fnPass,
                                        controller: _passCtrl,
                                        obscureText: _obscure,
                                        textInputAction: TextInputAction.next,
                                        onFieldSubmitted: (_) => FocusScope.of(
                                          context,
                                        ).requestFocus(_fnConfirm),
                                        decoration: InputDecoration(
                                          prefixIcon: const Icon(
                                            Icons.lock_outline,
                                          ),
                                          hintText: '••••••••',
                                          errorMaxLines: 3,
                                          suffixIcon: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              if (_touchedPass)
                                                _statusIcon(_passStatus) ??
                                                    const SizedBox.shrink(),
                                              IconButton(
                                                onPressed: () => setState(
                                                  () => _obscure = !_obscure,
                                                ),
                                                icon: Icon(
                                                  _obscure
                                                      ? Icons
                                                            .visibility_outlined
                                                      : Icons
                                                            .visibility_off_outlined,
                                                  color: _obscure
                                                      ? appColors.primary
                                                      : Colors.grey,
                                                ),
                                              ),
                                            ],
                                          ),

                                          errorText:
                                              _touchedPass &&
                                                  _passStatus ==
                                                      _FieldStatus.invalid
                                              ? _passError
                                              : null,
                                          enabledBorder: _borderFor(
                                            _touchedPass
                                                ? _passStatus
                                                : _FieldStatus.idle,
                                          ),
                                          focusedBorder: _borderFor(
                                            _touchedPass
                                                ? _passStatus
                                                : _FieldStatus.idle,
                                            focused: true,
                                          ),
                                          errorBorder: _borderFor(
                                            _FieldStatus.invalid,
                                          ),
                                          focusedErrorBorder: _borderFor(
                                            _FieldStatus.invalid,
                                            focused: true,
                                          ),
                                        ),
                                        validator: (v) {
                                          if (v == null || v.isEmpty)
                                            return 'أدخل كلمة المرور';
                                          if (v.length < 8)
                                            return 'كلمة المرور غير صحيحة';
                                          return null;
                                        },
                                      ),
                                    ],
                                  ),
                                ),

                                const SizedBox(height: 12),

                                // ✅ تأكيد كلمة المرور
                                _stagger(
                                  start: .35,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      _label('تأكيد كلمة المرور'),
                                      const SizedBox(height: 8),
                                      TextFormField(
                                        focusNode: _fnConfirm,
                                        controller: _confirmCtrl,
                                        obscureText: _obscureConfirm,
                                        textInputAction: TextInputAction.done,
                                        onChanged: (_) {
                                          if (_touchedConfirm) {
                                            _validateConfirm();
                                          }
                                        },
                                        onFieldSubmitted: (_) =>
                                            FocusScope.of(context).unfocus(),
                                        decoration: InputDecoration(
                                          prefixIcon: const Icon(
                                            Icons.check_circle_outline,
                                          ),
                                          hintText: 'أعد إدخال كلمة المرور',
                                          suffixIcon: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              if (_touchedConfirm)
                                                _statusIcon(_confirmStatus) ??
                                                    const SizedBox.shrink(),
                                              IconButton(
                                                onPressed: () => setState(
                                                  () => _obscureConfirm =
                                                      !_obscureConfirm,
                                                ),
                                                icon: Icon(
                                                  _obscureConfirm
                                                      ? Icons
                                                            .visibility_outlined
                                                      : Icons
                                                            .visibility_off_outlined,
                                                  color: _obscureConfirm
                                                      ? appColors.primary
                                                      : Colors.grey,
                                                ),
                                              ),
                                            ],
                                          ),
                                          errorText:
                                              _touchedConfirm &&
                                                  _confirmStatus ==
                                                      _FieldStatus.invalid
                                              ? _confirmError
                                              : null,
                                          enabledBorder: _borderFor(
                                            _touchedConfirm
                                                ? _confirmStatus
                                                : _FieldStatus.idle,
                                          ),
                                          focusedBorder: _borderFor(
                                            _touchedConfirm
                                                ? _confirmStatus
                                                : _FieldStatus.idle,
                                            focused: true,
                                          ),
                                          errorBorder: _borderFor(
                                            _FieldStatus.invalid,
                                          ),
                                          focusedErrorBorder: _borderFor(
                                            _FieldStatus.invalid,
                                            focused: true,
                                          ),
                                        ),
                                        validator: (v) {
                                          if (v == null || v.isEmpty) {
                                            return 'أدخل تأكيد كلمة المرور';
                                          }
                                          if (v != _passCtrl.text) {
                                            return 'كلمتا المرور غير متطابقتين';
                                          }
                                          return null;
                                        },
                                      ),
                                    ],
                                  ),
                                ),

                                const SizedBox(height: 16),

                                // العمر + الجنس
                                _stagger(
                                  start: .4,
                                  child: Row(
                                    children: [
                                      // العمر
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.stretch,
                                          children: [
                                            _label('العمر'),
                                            const SizedBox(height: 8),
                                            TextFormField(
                                              controller: _ageCtrl,
                                              keyboardType:
                                                  TextInputType.number,
                                              inputFormatters: [
                                                FilteringTextInputFormatter
                                                    .digitsOnly,
                                              ],
                                              textInputAction:
                                                  TextInputAction.done,
                                              decoration: const InputDecoration(
                                                prefixIcon: Icon(
                                                  Icons.cake_outlined,
                                                ),
                                                hintText: 'مثال: 18',
                                              ),
                                              validator: (v) {
                                                if (v == null ||
                                                    v.trim().isEmpty) {
                                                  return 'أدخل العمر';
                                                }
                                                final n = int.tryParse(
                                                  v.trim(),
                                                );
                                                if (n == null) {
                                                  return 'أدخل رقمًا صحيحًا';
                                                }
                                                if (n < 7 || n > 120) {
                                                  return 'الحد الأدنى للعمر 7 سنوات';
                                                }
                                                return null;
                                              },
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      // الجنس
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.stretch,
                                          children: [
                                            _label('الجنس'),
                                            const SizedBox(height: 8),
                                            DecoratedBox(
                                              decoration: BoxDecoration(
                                                borderRadius:
                                                    BorderRadius.circular(14),
                                                border: Border.all(
                                                  color: appColors.light,
                                                  width: 1.2,
                                                ),
                                              ),
                                              child: Padding(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 6,
                                                    ),
                                                child: Row(
                                                  children: [
                                                    Expanded(
                                                      child: _GenderChip(
                                                        selected:
                                                            _gender == 'male',
                                                        icon: Icons.male,
                                                        label: 'ذكر',
                                                        onTap: () => setState(
                                                          () =>
                                                              _gender = 'male',
                                                        ),
                                                      ),
                                                    ),
                                                    const SizedBox(width: 8),
                                                    Expanded(
                                                      child: _GenderChip(
                                                        selected:
                                                            _gender == 'female',
                                                        icon: Icons.female,
                                                        label: 'أنثى',
                                                        onTap: () => setState(
                                                          () => _gender =
                                                              'female',
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                const SizedBox(height: 24),

                                // زر الإنشاء
                                _stagger(
                                  start: .6,
                                  child: SizedBox(
                                    width: double.infinity,
                                    height: 54,
                                    child: GestureDetector(
                                      onTapDown: (_) => _pressCtrl.forward(),
                                      onTapCancel: () => _pressCtrl.reverse(),
                                      onTapUp: (_) => _pressCtrl.reverse(),
                                      child: AnimatedBuilder(
                                        animation: _pressCtrl,
                                        builder: (_, __) {
                                          final scale = 1 - _pressCtrl.value;
                                          return Transform.scale(
                                            scale: scale,
                                            child: _AnimatedGradientButton(
                                              label: _reserving
                                                  ? '... جارٍ إنشاء الحساب'
                                                  : 'إنشاء حساب',
                                              onPressed: _reserving
                                                  ? () {}
                                                  : _submit,
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                                ),

                                const SizedBox(height: 12),

                                // رجوع لتسجيل الدخول
                                _stagger(
                                  start: .75,
                                  child: _BouncyLink(
                                    label: ' لدي حساب بالفعل — تسجيل دخول',
                                    onTap: () => Navigator.of(context).pop(),
                                  ),
                                ),

                                const SizedBox(height: 8),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Label موحّد
  Widget _label(String text) => Align(
    alignment: Alignment.centerRight,
    child: Text(
      text,
      style: TextStyle(
        color: Colors.black.withOpacity(.75),
        fontWeight: FontWeight.w600,
      ),
    ),
  );

  // Blob helper محلي
  Widget _blob({
    double? left,
    double? right,
    double? top,
    double? bottom,
    required double size,
    required Color color,
  }) {
    return Positioned(
      left: left,
      right: right,
      top: top,
      bottom: bottom,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
      ),
    );
  }
}

/* ======================= صفحة إشعار التحقق من البريد ======================= */
class VerifyEmailPage extends StatefulWidget {
  final String email;
  const VerifyEmailPage({super.key, required this.email});

  @override
  State<VerifyEmailPage> createState() => _VerifyEmailPageState();
}

class _VerifyEmailPageState extends State<VerifyEmailPage> {
  bool _sending = false;
  bool _checking = false;

  Future<void> _resend() async {
    if (!await hasInternetConnection()) {
      showNoInternetDialog(context);
      return;
    }
    try {
      setState(() => _sending = true);
      await FirebaseAuth.instance.setLanguageCode('ar');
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw FirebaseAuthException(
          code: 'current-user-null',
          message: 'No current user',
        );
      }
      await user.sendEmailVerification();

      if (!mounted) return;
      // ✅ رسالة قصيرة بأسلوب Slack message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: slackMesseges.primary,
          content: Text(
            '✉️ تم إعادة إرسال رسالة التحقق',
            style: GoogleFonts.ibmPlexSansArabic(
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ),
      );
    } on FirebaseAuthException catch (e) {
      String msg = 'تعذّر الإرسال (${e.code})';
      switch (e.code) {
        case 'current-user-null':
          msg = 'لا يوجد مستخدم مسجّل — سجّل دخول ثم حاول';
          break;
        case 'network-request-failed':
          msg = 'تحقق من اتصال الإنترنت';
          break;
        case 'too-many-requests':
          msg =
              'لقد قمت بمحاولات متعددة خلال وقت قصير. يرجى الانتظار قليلًا ثم المحاولة مرة أخرى';
          break;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: slackMesseges.red,
          content: Text(
            '❌ $msg',
            style: GoogleFonts.ibmPlexSansArabic(
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// ✅ تحقق محلي: أعد تحميل المستخدم، إذا Verified حدّث users/{uid}.isVerified=true
  Future<void> _markVerified() async {
    if (!await hasInternetConnection()) {
      showNoInternetDialog(context);
      return;
    }
    try {
      setState(() => _checking = true);

      await FirebaseAuth.instance.currentUser?.reload();
      final user = FirebaseAuth.instance.currentUser;

      if (!mounted) return;

      if (user != null && user.emailVerified) {
        // حدّث علم التحقق في Firestore (القواعد أثناء التطوير تسمح)
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'isVerified': true,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        // ✅ رسالة قصيرة وواضحة
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: slackMesseges.primary,
            content: Text(
              '✅ تم تأكيد التحقق وتحديث الحساب',
              style: GoogleFonts.ibmPlexSansArabic(
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
        );

        // وجّه حسب الدور
        final role = await _fetchUserRole(user.uid);
        if (!mounted) return;
        if (role == 'admin') {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const AdminHomePage()),
            (r) => false,
          );
        } else {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const homePage()),
            (r) => false,
          );
        }
      } else {
        // ⚠️ مستخدم ضغط "تحققت الآن" لكن البريد لسه مو متحقق
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: slackMesseges.red,
            content: Text(
              '⚠️ لم يتم التحقق من البريد الإلكتروني بعد',
              style: GoogleFonts.ibmPlexSansArabic(
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: slackMesseges.red,
          content: Text(
            '❌ حدث خطأ أثناء التحقق',
            style: GoogleFonts.ibmPlexSansArabic(
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<String?> _fetchUserRole(String uid) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      return (doc.data() ?? const {})['role'] as String?;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // ✅ شريط علوي مع زر إغلاق يرجع للصفحة السابقة فقط
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        automaticallyImplyLeading: false,
        leading: IconButton(
          tooltip: 'إغلاق',
          icon: const Icon(Icons.close),
          color: appColors.dark,
          onPressed: () async {
            // 1) تسجيل خروج علشان ما يرجعك LaunchDecider لصفحة التحقق
            await FirebaseAuth.instance.signOut();

            if (!mounted) return;

            // 2) انتقال مباشر لصفحة تسجيل الدخول وتصفير الستاك
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const RegisterPage()),
              (route) => false,
            );
          },
        ),
      ),

      body: Directionality(
        textDirection: TextDirection.rtl,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  color: Colors.white,
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // أيقونة متدرجة
                        ShaderMask(
                          shaderCallback: (rect) => const LinearGradient(
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                            colors: [
                              appColors.primary,
                              appColors.primary,
                              appColors.mint,
                            ],
                            stops: [0.0, 0.5, 1.0],
                          ).createShader(rect),
                          child: const Icon(
                            Icons.mark_email_read_outlined,
                            size: 72,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'تم إرسال رسالة تحقق',
                          style: GoogleFonts.ibmPlexSansArabic(
                            fontWeight: FontWeight.w700,
                            fontSize: 20,
                            color: appColors.dark,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'أرسلنا رسالة إلى:\n${widget.email}\nافتح بريدك واضغط رابط التحقق لإكمال إنشاء الحساب.',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),

                        // زر "تحققت الآن"
                        Row(
                          children: [
                            Expanded(
                              child: _AnimatedGradientButton(
                                label: _checking
                                    ? '... جارٍ التحقق'
                                    : 'تحققت الآن',
                                onPressed: _checking ? () {} : _markVerified,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),

                        // زر "إعادة إرسال التحقق"
                        Row(
                          children: [
                            Expanded(
                              child: _AnimatedGradientOutlineButton(
                                label: _sending
                                    ? '... جارٍ الإرسال'
                                    : 'إعادة إرسال التحقق',
                                onPressed: _sending ? () {} : _resend,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/* ======================= أزرار التدرّج ======================= */

class _AnimatedGradientButton extends StatefulWidget {
  final String label;
  final VoidCallback onPressed;

  const _AnimatedGradientButton({required this.label, required this.onPressed});

  @override
  State<_AnimatedGradientButton> createState() =>
      _AnimatedGradientButtonState();
}

class _AnimatedGradientButtonState extends State<_AnimatedGradientButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _shift;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _shift = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => _ctrl.forward(),
      onExit: (_) => _ctrl.reverse(),
      child: AnimatedBuilder(
        animation: _shift,
        builder: (_, __) {
          return DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x33009688),
                  blurRadius: 18,
                  offset: Offset(0, 8),
                ),
              ],
              gradient: LinearGradient(
                begin: Alignment(-1 + _shift.value, 0),
                end: Alignment(1 + _shift.value, 0),
                colors: const [
                  appColors.primary,
                  appColors.primary,
                  appColors.mint,
                ],
                stops: const [0.0, 0.5, 1.0],
              ),
            ),
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(28),
                ),
                minimumSize: const Size.fromHeight(54),
              ),
              onPressed: widget.onPressed,
              child: Text(
                widget.label,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// زر بخلفية بيضاء وحدّ (إطار) متدرّج
class _AnimatedGradientOutlineButton extends StatefulWidget {
  final String label;
  final VoidCallback onPressed;

  const _AnimatedGradientOutlineButton({
    required this.label,
    required this.onPressed,
  });

  @override
  State<_AnimatedGradientOutlineButton> createState() =>
      _AnimatedGradientOutlineButtonState();
}

class _AnimatedGradientOutlineButtonState
    extends State<_AnimatedGradientOutlineButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _shift;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _shift = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const double borderRadius = 28;
    const double borderWidth = 2;

    final gradient = LinearGradient(
      begin: Alignment(-1 + _shift.value, 0),
      end: Alignment(1 + _shift.value, 0),
      colors: const [appColors.primary, appColors.primary, appColors.mint],
      stops: const [0.0, 0.5, 1.0],
    );

    return MouseRegion(
      onEnter: (_) => _ctrl.forward(),
      onExit: (_) => _ctrl.reverse(),
      child: AnimatedBuilder(
        animation: _shift,
        builder: (_, __) {
          return Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(borderRadius),
              gradient: gradient,
              boxShadow: const [
                BoxShadow(
                  color: Color(0x1A009688),
                  blurRadius: 14,
                  offset: Offset(0, 6),
                ),
              ],
            ),
            child: Container(
              // داخل الإطار (خلفية بيضاء)
              margin: const EdgeInsets.all(borderWidth),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(borderRadius - 1),
              ),
              child: TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: appColors.dark,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(borderRadius - 1),
                  ),
                  minimumSize: const Size.fromHeight(54),
                ),
                onPressed: widget.onPressed,
                child: Text(
                  widget.label,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/* ======================= ويدجت الجنس ======================= */

class _GenderChip extends StatelessWidget {
  final bool selected;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _GenderChip({
    required this.selected,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = selected
        ? appColors.primary.withOpacity(.12)
        : Colors.transparent;
    final border = selected ? appColors.primary : appColors.light;
    final fg = selected ? appColors.dark : Colors.black.withOpacity(.7);

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: border, width: 1.2),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 20, color: appColors.primary),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(fontWeight: FontWeight.w600, color: fg),
            ),
          ],
        ),
      ),
    );
  }
}

// لتصحيح Positioned.fill بعد النسخ (بعض المحررات قد لا تعرفها كـ Widget)
class PositionedFill extends StatelessWidget {
  final Widget child;
  const PositionedFill({super.key, required this.child});
  @override
  Widget build(BuildContext context) => Positioned.fill(child: child);
}
