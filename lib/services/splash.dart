import 'dart:async';
import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'dart:ui';
import '../main.dart'; // for AppColors and _GradientBackgroundPainter
import '../onboarding.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _bgCtrl;
  late final AnimationController _fadeCtrl;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();

    _bgCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 14),
    )..repeat();

    // fade-out controller
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
      value: 1.0, // start fully visible
    );

    // run fade out before navigating
    Future.delayed(const Duration(seconds: 3), () async {
      await _fadeCtrl.reverse(); // fade to invisible
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const OnboardingScreen()),
        );
      }
    });
  }

  @override
  @override
  void dispose() {
    _bgCtrl.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // 🔹 Moving gradient background
          AnimatedBuilder(
            animation: _bgCtrl,
            builder: (_, __) {
              return CustomPaint(
                painter: GradientBackgroundPainter(_bgCtrl.value),
                child: const SizedBox.expand(),
              );
            },
          ),

          // 🔹 Floating blobs
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

          // 🔹 Center logo
          Center(
            child: FadeTransition(
              opacity: _fadeCtrl,
              child: Hero(
                tag: 'logo',
                child: Image.asset(
                  'assets/img/logo.png',
                  width: 160,
                  height: 160,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

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
