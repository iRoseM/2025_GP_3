import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';

// We reuse colors, painter, and pages that already live in main.dart
import 'main.dart'; // AppColors, GradientBackgroundPainter, RegisterPage, SignUpPage

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with TickerProviderStateMixin {
  late final AnimationController _bgCtrl;
  int _index = 0; // 0..2 = onboarding slides, 3 = welcome page

  static const _pages = <_OnbPageData>[
    _OnbPageData(
      image: 'assets/img/onboarding1.png',
      title: 'أهلاً بك في نمير',
      subtitle:
          'غيّر عاداتك اليومية، واجمّع النقاط لبناء مستقبلٍ أخضر مع السعودية!',
    ),
    _OnbPageData(
      image: 'assets/img/onboarding2.png',
      title: 'خطوات بسيطة بأثر كبير',
      subtitle:
          'أنجز مهام مستدامة يومية، اجمع نقاطًا واستبدلها بمكافآتٍ حقيقية.',
    ),
    _OnbPageData(
      image: 'assets/img/onboarding3.png',
      title: 'مستعد للتحدي؟',
      subtitle: 'كل خطوة تقرّبنا من مستقبل أكثر خضرة، جاهز؟',
    ),
  ];

  bool get _isWelcome => _index == _pages.length;

  @override
  void initState() {
    super.initState();
    _bgCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 14),
    )..repeat();
  }

  @override
  void dispose() {
    _bgCtrl.dispose();
    super.dispose();
  }

  void _next() {
    if (_index < _pages.length) {
      setState(() => _index++);
    }
  }

  void _prev() {
    if (_index > 0) setState(() => _index--);
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: Stack(
          children: [
            // ===== animated background (same as register/splash) =====
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
            // soft blobs
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

            // ===== content =====
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                child: Column(
                  children: [
                    // back arrow (hidden on first page)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: (_index == 0 || _isWelcome)
                          ? const SizedBox(
                              height: 40,
                            ) // ✅ hide on first & last (welcome) page
                          : IconButton(
                              tooltip: 'رجوع',
                              onPressed: _prev,
                              icon: const Icon(
                                Icons.arrow_forward_ios_rounded,
                                color: AppColors.dark,
                              ),
                            ),
                    ),
                    const SizedBox(height: 6),

                    Expanded(
                      child: Center(
                        child: _isWelcome
                            ? _WelcomeSlide(
                                onLogin: () {
                                  Navigator.of(context).pushReplacement(
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          const RegisterPage(), // لديك في main.dart (تسجيل الدخول)
                                    ),
                                  );
                                },
                                onRegister: () {
                                  Navigator.of(context).pushReplacement(
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          const SignUpPage(), // لديك في main.dart (إنشاء حساب)
                                    ),
                                  );
                                },
                              )
                            : _OnboardingSlide(data: _pages[_index]),
                      ),
                    ),
                    const SizedBox(height: 8),
                    // dots + next (hide dots on welcome)
                    if (!_isWelcome) ...[
                      // 🔹 Dots indicator (keep this)
                      _Dots(current: _index, total: _pages.length),
                      const SizedBox(height: 16),

                      // 🔸 Next button with animated orange ring
                      SizedBox(
                        height: 64, // 🔹 slightly smaller
                        width: 64,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            // Orange circular ring — tighter fit
                            TweenAnimationBuilder<double>(
                              tween: Tween<double>(
                                begin: 0,
                                end: (_index + 1) / _pages.length,
                              ),
                              duration: const Duration(milliseconds: 600),
                              curve: Curves.easeInOut,
                              builder: (context, value, _) {
                                return SizedBox(
                                  height: 66, // 🔹 just 2px larger than button
                                  width: 66,
                                  child: CircularProgressIndicator(
                                    value: value,
                                    strokeWidth: 3.0,
                                    valueColor:
                                        const AlwaysStoppedAnimation<Color>(
                                          AppColors.orange,
                                        ),
                                    backgroundColor: Colors.transparent,
                                  ),
                                );
                              },
                            ),
                            // Main green button
                            ElevatedButton(
                              onPressed: _next,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                shape: const CircleBorder(),
                                padding: const EdgeInsets.all(
                                  0,
                                ), // ✅ removes extra padding
                                minimumSize: const Size(
                                  60,
                                  60,
                                ), // ✅ keeps a perfect circle
                                elevation: 3,
                              ),
                              child: const Text(
                                'التالي',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // local blob helper (same style as your pages)
  static Widget _blob({
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

// ===== models & UI parts =====

class _OnbPageData {
  final String image;
  final String title;
  final String subtitle;
  const _OnbPageData({
    required this.image,
    required this.title,
    required this.subtitle,
  });
}

class _OnboardingSlide extends StatelessWidget {
  const _OnboardingSlide({required this.data});
  final _OnbPageData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // mascot
          Image.asset(data.image, fit: BoxFit.contain, width: 280, height: 280),
          const SizedBox(height: 8),
          Text(
            data.title,
            textAlign: TextAlign.center,
            style: theme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            data.subtitle,
            textAlign: TextAlign.center,
            style: theme.bodyMedium?.copyWith(
              color: Colors.black54,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}

class _WelcomeSlide extends StatelessWidget {
  const _WelcomeSlide({required this.onLogin, required this.onRegister});
  final VoidCallback onLogin;
  final VoidCallback onRegister;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Center(
        // ✅ centers everything vertically
        child: SingleChildScrollView(
          // ✅ allows scrolling if screen is small
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center, // ✅ center vertically
            children: [
              Image.asset(
                'assets/img/welcome.png',
                fit: BoxFit.contain,
                width: 280,
                height: 280,
              ),
              const SizedBox(height: 16),
              Text(
                'مرحباً!',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'سجّل الدخول لبدء رحلتك مع نمير',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.black54,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 32), // adds space before buttons
              // Login button
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: onLogin,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 2,
                  ),
                  child: const Text(
                    'تسجيل الدخول',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const Text('أو', style: TextStyle(color: Colors.black45)),
              const SizedBox(height: 14),

              // Register button
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: onRegister,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white, // ✅ white text
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    'إنشاء حساب',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.current, required this.total});

  final int current;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      // 👈 force left-to-right for the dots only
      textDirection: TextDirection.ltr,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(total, (i) {
          final isActive = i == current;

          return AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            margin: const EdgeInsets.symmetric(horizontal: 4),
            height: 8,
            width: isActive ? 22 : 8,
            decoration: BoxDecoration(
              color: isActive
                  ? AppColors
                        .orange // 🟧 orange for current page
                  : AppColors.primary.withOpacity(0.7),
              borderRadius: BorderRadius.circular(8),
            ),
          );
        }),
      ),
    );
  }
}
