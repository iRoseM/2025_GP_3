import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// نستخدم الألوان والبنتر من main.dart
import 'main.dart'; // AppColors, GradientBackgroundPainter, RegisterPage

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with TickerProviderStateMixin {
  late final AnimationController _bgCtrl;
  int _index = 0; // 0..2 = onboarding slides

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

  Future<void> _next() async {
    // ✅ إذا كنا في آخر صفحة خزّن فلاج المشاهدة وانتقل لتسجيل الدخول
    if (_index >= _pages.length - 1) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('seen_onboarding', true); // ما ترجع تظهر

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const RegisterPage()),
      );
      return;
    }
    setState(() => _index++);
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

            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                child: Column(
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: (_index == 0)
                          ? const SizedBox(height: 40)
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
                        child: _OnboardingSlide(data: _pages[_index]),
                      ),
                    ),
                    const SizedBox(height: 8),
                    _Dots(current: _index, total: _pages.length),
                    const SizedBox(height: 16),

                    // 🔸 زر متدرّج الألوان
                    SizedBox(
                      height: 64,
                      width: 64,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          TweenAnimationBuilder<double>(
                            tween: Tween<double>(
                              begin: 0,
                              end: (_index + 1) / _pages.length,
                            ),
                            duration: const Duration(milliseconds: 600),
                            curve: Curves.easeInOut,
                            builder: (context, value, _) {
                              return SizedBox(
                                height: 66,
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
                          Container(
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                colors: [AppColors.mint, AppColors.primary],
                                begin: Alignment.topRight,
                                end: Alignment.bottomLeft,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black26,
                                  blurRadius: 6,
                                  offset: Offset(2, 3),
                                ),
                              ],
                            ),
                            child: Material(
                              color: Colors.transparent,
                              shape: const CircleBorder(),
                              child: InkWell(
                                customBorder: const CircleBorder(),
                                onTap: _next,
                                child: Center(
                                  child: Text(
                                    _index == _pages.length - 1
                                        ? 'ابدأ'
                                        : 'التالي',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

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

class _Dots extends StatelessWidget {
  const _Dots({required this.current, required this.total});
  final int current;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Directionality(
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
                  ? AppColors.orange
                  : AppColors.primary.withOpacity(0.7),
              borderRadius: BorderRadius.circular(8),
            ),
          );
        }),
      ),
    );
  }
}
