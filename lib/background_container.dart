import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'home.dart'; // for AppColors and BgPainter

class AnimatedBackgroundContainer extends StatefulWidget {
  final Widget child;
  const AnimatedBackgroundContainer({super.key, required this.child});

  @override
  State<AnimatedBackgroundContainer> createState() => _AnimatedBackgroundContainerState();
}

class _AnimatedBackgroundContainerState extends State<AnimatedBackgroundContainer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _bgCtrl;

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

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand, // ✅ makes background fill under everything
      children: [
        AnimatedBuilder(
          animation: _bgCtrl,
          builder: (_, __) => CustomPaint(
            painter: _BgPainter(_bgCtrl.value),
            child: const SizedBox.expand(),
          ),
        ),
        SafeArea(
          top: true,
          bottom: false, // ✅ allow background under nav bar
          child: widget.child,
        ),
      ],
    );
  }
}


/* ======================= Background Painter ======================= */
class _BgPainter extends CustomPainter {
  final double t;
  _BgPainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    // خلفية مبسّطة واحترافية
    final base = const LinearGradient(
      begin: Alignment.topRight,
      end: Alignment.bottomLeft,
      colors: [AppColors.background, Color(0xFFF6FBF9), Color(0xFFFFFFFF)],
      stops: [0.0, 0.6, 1.0],
    ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, Paint()..shader = base);

    // تأثير خفيف جداً: بقعتان ناعمتان شبه شفافتين تتحركان ببطء
    final blob1 = Paint()..color = AppColors.primary.withOpacity(0.06);
    final blob2 = Paint()..color = AppColors.accent.withOpacity(0.04);

    final cx1 = size.width * (0.18 + 0.02 * math.sin(t * 2 * math.pi));
    final cy1 = size.height * (0.22 + 0.02 * math.cos(t * 2 * math.pi));
    canvas.drawCircle(Offset(cx1, cy1), 90, blob1);

    final cx2 = size.width * (0.82 + 0.015 * math.cos(t * 2 * math.pi));
    final cy2 = size.height * (0.78 + 0.018 * math.sin(t * 2 * math.pi));
    canvas.drawCircle(Offset(cx2, cy2), 110, blob2);

    // طبقة "فوج" خفيفة جداً أعلى الشاشة
    final topFog = const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.center,
      colors: [Color(0x22FFFFFF), Color(0x00FFFFFF)],
    ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, Paint()..shader = topFog);

    // فينييت رقيق في الزاوية
    final vignette = const RadialGradient(
      center: Alignment(-0.85, -0.9),
      radius: 0.8,
      colors: [Color(0x0A003659), Colors.transparent],
      stops: [0.0, 1.0],
    ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, Paint()..shader = vignette);
  }

  @override
  bool shouldRepaint(covariant _BgPainter oldDelegate) => oldDelegate.t != t;
}