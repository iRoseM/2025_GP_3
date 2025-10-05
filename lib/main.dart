import 'dart:math' as math;
import 'dart:ui';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:flutter/services.dart';
import 'splash.dart';
import 'home.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  runApp(const MyApp());
}

class AppColors {
  static const primary = Color(0xFF009688);
  static const dark = Color(0xFF00695C);
  static const light = Color(0xFF4DB6AC);
  static const background = Color(0xFFFAFCFB);
  // ✅ لجراديانت النقاط والزر
  static const mint = Color(0xFFB6E9C1);
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(seedColor: AppColors.primary);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Nameer Register',
      locale: const Locale('ar'),
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme.copyWith(
          primary: AppColors.primary,
          secondary: AppColors.light,
          onPrimary: Colors.white,
        ),

        // ✅ تطبيق IBM Plex Sans Arabic
        fontFamily: GoogleFonts.ibmPlexSansArabic().fontFamily,
        textTheme: GoogleFonts.ibmPlexSansArabicTextTheme(),
        primaryTextTheme: GoogleFonts.ibmPlexSansArabicTextTheme(),

        scaffoldBackgroundColor: AppColors.background,

        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
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
          style: TextButton.styleFrom(foregroundColor: AppColors.dark),
        ),
        inputDecorationTheme: const InputDecorationTheme(
          prefixIconColor: AppColors.primary,
          suffixIconColor: AppColors.primary,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(14)),
          ),
          enabledBorder: OutlineInputBorder(
            borderSide: BorderSide(color: AppColors.light, width: 1.2),
            borderRadius: BorderRadius.all(Radius.circular(14)),
          ),
          focusedBorder: OutlineInputBorder(
            borderSide: BorderSide(color: AppColors.primary, width: 1.6),
            borderRadius: BorderRadius.all(Radius.circular(14)),
          ),
          errorBorder: OutlineInputBorder(
            borderSide: BorderSide(color: Colors.red),
            borderRadius: BorderRadius.all(Radius.circular(14)),
          ),
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      ),
      home: const SplashScreen(),
    );
  }
}

/* ======================= صفحة تسجيل الدخول (الموجودة لديك) ======================= */

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage>
    with TickerProviderStateMixin {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _obscure = true;

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
    _bgCtrl.dispose();
    _introCtrl.dispose();
    _shakeCtrl.dispose();
    _pressCtrl.dispose();
    super.dispose();
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

  void _submit(BuildContext context) {
    final ok = _formKey.currentState?.validate() ?? false;
    if (!ok) {
      _shakeCtrl
        ..reset()
        ..forward();
      return;
    }

    // التنقّل إلى الهوم بيج بعد نجاح التحقق
    Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute(builder: (_) => const homePage()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: Stack(
          children: [
            // ===== الخلفية المتحركة =====
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
                        color: AppColors.primary.withOpacity(.12),
                      ),
                      _blob(
                        left: -40 + 30 * math.cos(2 * math.pi * (t + .3)),
                        bottom: -10 + 25 * math.sin(2 * math.pi * (t + .3)),
                        size: 220,
                        color: AppColors.light.withOpacity(.10),
                      ),
                    ],
                  );
                },
              ),
            ),

            // ===== المحتوى =====
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
                                  ),
                                ),

                                const SizedBox(height: 18),

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
                                      decoration: InputDecoration(
                                        prefixIcon: const Icon(
                                          Icons.lock_outline,
                                        ),
                                        hintText: '••••••••',
                                        suffixIcon: AnimatedRotation(
                                          turns: _obscure ? 0 : .25,
                                          duration: const Duration(
                                            milliseconds: 220,
                                          ),
                                          child: IconButton(
                                            onPressed: () => setState(
                                              () => _obscure = !_obscure,
                                            ),
                                            icon: Icon(
                                              _obscure
                                                  ? Icons.visibility
                                                  : Icons.visibility_off,
                                            ),
                                          ),
                                        ),
                                      ),
                                      validator: (v) {
                                        if (v == null || v.isEmpty)
                                          return 'أدخل كلمة المرور';
                                        if (v.length < 6)
                                          return 'كلمة المرور يجب أن تكون 6 أحرف على الأقل';
                                        return null;
                                      },
                                    ),
                                  ),
                                ),

                                const SizedBox(height: 26),

                                // ===== زر متدرّج + حركة hover + ضغط (scale) =====
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
                                              label: 'تسجيل دخول',
                                              onPressed: () => _submit(context),
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                                ),

                                const SizedBox(height: 12),

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

/// رسام للخلفية المتدرجة المتحركة + تموّج خفيف
class GradientBackgroundPainter extends CustomPainter {
  final double t;
  const GradientBackgroundPainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final g1 = LinearGradient(
      begin: Alignment.topRight,
      end: Alignment.bottomLeft,
      colors: [
        AppColors.background,
        Color.lerp(AppColors.background, Colors.white, .3)!,
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

/// رابط بنبض خفيف
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

  bool _obscure = true;
  String _gender = 'male'; // 'male' or 'female'

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
  }

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _ageCtrl.dispose();
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

  void _submit() {
    final ok = _formKey.currentState?.validate() ?? false;
    if (!ok) return;

    Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute(builder: (_) => const homePage()));
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
                        right: 24 + 10 * math.sin(2 * math.pi * t),
                        top: 64 + 16 * math.cos(2 * math.pi * t),
                        size: 160,
                        color: AppColors.primary.withOpacity(.10),
                      ),
                      _blob(
                        left: -36 + 24 * math.cos(2 * math.pi * (t + .35)),
                        bottom: -8 + 20 * math.sin(2 * math.pi * (t + .35)),
                        size: 200,
                        color: AppColors.light.withOpacity(.10),
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
                                          color: AppColors.dark.withOpacity(.9),
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
                                        controller: _usernameCtrl,
                                        textInputAction: TextInputAction.next,
                                        decoration: const InputDecoration(
                                          prefixIcon: Icon(
                                            Icons.person_outline,
                                          ),
                                          hintText: 'nameer_user',
                                        ),
                                        validator: (v) {
                                          if (v == null || v.trim().isEmpty)
                                            return 'أدخل اسم المستخدم';
                                          if (v.trim().length < 3)
                                            return 'اسم المستخدم قصير جداً';
                                          return null;
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
                                        controller: _emailCtrl,
                                        keyboardType:
                                            TextInputType.emailAddress,
                                        textInputAction: TextInputAction.next,
                                        decoration: const InputDecoration(
                                          prefixIcon: Icon(
                                            Icons.email_outlined,
                                          ),
                                          hintText: 'name@example.com',
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
                                        controller: _passCtrl,
                                        obscureText: _obscure,
                                        textInputAction: TextInputAction.next,
                                        decoration: InputDecoration(
                                          prefixIcon: const Icon(
                                            Icons.lock_outline,
                                          ),
                                          hintText: '••••••••',
                                          suffixIcon: AnimatedRotation(
                                            turns: _obscure ? 0 : .25,
                                            duration: const Duration(
                                              milliseconds: 220,
                                            ),
                                            child: IconButton(
                                              onPressed: () => setState(
                                                () => _obscure = !_obscure,
                                              ),
                                              icon: Icon(
                                                _obscure
                                                    ? Icons.visibility
                                                    : Icons.visibility_off,
                                              ),
                                            ),
                                          ),
                                        ),
                                        validator: (v) {
                                          if (v == null || v.isEmpty)
                                            return 'أدخل كلمة المرور';
                                          if (v.length < 6)
                                            return 'كلمة المرور يجب أن تكون 6 أحرف على الأقل';
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
                                                    v.trim().isEmpty)
                                                  return 'أدخل العمر';
                                                final n = int.tryParse(
                                                  v.trim(),
                                                );
                                                if (n == null)
                                                  return 'أدخل رقمًا صحيحًا';
                                                if (n < 10 || n > 120)
                                                  return 'العمر غير منطقي';
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
                                                  color: AppColors.light,
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

                                // ===== زر الإنشاء بنفس تدرّج النقاط + حركة hover + ضغط =====
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
                                              label: 'إنشاء حساب',
                                              onPressed: _submit,
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
        color: Colors.black.withOpacity(0.75),
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

/* ======================= زر متدرّج مع أنيميشن Hover ======================= */

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
              // ✅ نفس تدرّج النقاط مع انزياح أفقي عند الـ hover
              gradient: LinearGradient(
                begin: Alignment(-1 + _shift.value, 0),
                end: Alignment(1 + _shift.value, 0),
                colors: const [
                  AppColors.primary,
                  AppColors.primary,
                  AppColors.mint,
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
        ? AppColors.primary.withOpacity(.12)
        : Colors.transparent;
    final border = selected ? AppColors.primary : AppColors.light;
    final fg = selected ? AppColors.dark : Colors.black.withOpacity(.7);

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
            Icon(icon, size: 20, color: AppColors.primary),
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
