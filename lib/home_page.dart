// home_page.dart (نسخة محدّثة)
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'map.dart';


// إن كان لديك AppColors في ملف مشترك، استورده واحذف هذا التعريف.
class AppColors {
  static const primary = Color(0xFF009688);
  static const dark = Color(0xFF00695C);
  static const light = Color(0xFF4DB6AC);
  static const background = Color(0xFFFAFCFB);
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with TickerProviderStateMixin {
  int _currentIndex = 0;
  late final AnimationController _bgCtrl;

  @override
  void initState() {
    super.initState();
    _bgCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 14))..repeat();
  }

  @override
  void dispose() {
    _bgCtrl.dispose();
    super.dispose();
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
              builder: (_, __) => CustomPaint(
                painter: _BgPainter(_bgCtrl.value),
                child: const SizedBox.expand(),
              ),
            ),
            SafeArea(
              bottom: false,
              child: CustomScrollView(
                slivers: [
                  // Header
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 20,
                            backgroundColor: AppColors.primary.withOpacity(.12),
                            child: const Icon(Icons.person_outline, color: AppColors.primary),
                          ),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text('مرحبًا، Nameer', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                          ),
                          _PointsChip(points: 1500, onTap: () {}),
                        ],
                      ),
                    ),
                  ),

                  // Title
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        'ابدأ رحلتك الخضراء اليوم 🌿',
                        style: TextStyle(fontSize: 22, height: 1.2, fontWeight: FontWeight.w800, color: Colors.black.withOpacity(.85)),
                      ),
                    ),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 12)),

                  // Daily progress
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _DailyProgressCard(
                        percent: .62,
                        bullets: const [
                          'أنهيت مهمتين من قائمة اليوم',
                          'تبقّى: إعادة تدوير البلاستيك + قراءة مقال',
                          'سلسلة الاستدامة: 3 أيام متتالية 🔥',
                        ],
                        onTapDetails: () {},
                      ),
                    ),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 16)),

                  // === EcoLand (بدل سلسلة النظافة) ===
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _EcoLandCard(
                        title: 'EcoLand الخاصة بك',
                        subtitle: 'طوِّر أرضك بزراعة الأشجار وترقية العناصر عبر إنجاز المهام.',
                        onTap: () {
                          // TODO: افتح شاشة EcoLand كاملة
                        },
                      ),
                    ),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 12)),

                  // Banner
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: _InlineBanner(
                        label: 'إعلان: حملة “احفظ حيّك نظيفًا” بدأت اليوم — شارك الآن!',
                        onTap: () {},
                      ),
                    ),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 8)),

                  // Friends
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Row(
                        children: [
                          const Expanded(child: Text('أصدقائي', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
                          TextButton(onPressed: () {}, child: const Text('عرض الكل')),
                        ],
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: const [
                          Expanded(child: _FriendCard(name: 'سارة', points: 220, streak: 4)),
                          SizedBox(width: 12),
                          Expanded(child: _FriendCard(name: 'خالد', points: 180, streak: 2)),
                        ],
                      ),
                    ),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 120)),
                ],
              ),
            ),
          ],
        ),

        // === Bottom Nav: زر الوسط = الخريطة ===
        bottomNavigationBar: _BottomNav(
          currentIndex: _currentIndex,
          onTap: (i) => setState(() => _currentIndex = i),
          onCenterTap: () {
          Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const MapPage()),
  );
},
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.circular(100),
          boxShadow: const [BoxShadow(color: Color(0x33009688), blurRadius: 10, offset: Offset(0, 6))],
        ),
        child: Row(
          children: [
            const Icon(Icons.monetization_on_outlined, size: 18, color: Colors.white),
            const SizedBox(width: 6),
            Text('$points', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
          ],
        ),
      ),
    );
  }
}

class _DailyProgressCard extends StatelessWidget {
  final double percent;
  final List<String> bullets;
  final VoidCallback? onTapDetails;
  const _DailyProgressCard({required this.percent, required this.bullets, this.onTapDetails});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 18, offset: Offset(0, 8))],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('تقدّم اليوم', style: TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                ...bullets.take(3).map(
                  (b) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle_outline, size: 18, color: AppColors.primary),
                        const SizedBox(width: 6),
                        Expanded(child: Text(b)),
                      ],
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(onPressed: onTapDetails, child: const Text('التفاصيل')),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _AnimatedRing(percent: percent),
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
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOut,
      builder: (_, v, __) => SizedBox(
        width: 88,
        height: 88,
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 88,
              height: 88,
              child: CircularProgressIndicator(
                value: v,
                strokeWidth: 8,
                backgroundColor: AppColors.light.withOpacity(.2),
                valueColor: const AlwaysStoppedAnimation(AppColors.primary),
              ),
            ),
            Text('${(v * 100).round()}%', style: const TextStyle(fontWeight: FontWeight.w800)),
          ],
        ),
      ),
    );
  }
}

/* =============== EcoLand Card (جديد) =============== */

class _EcoLandCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _EcoLandCard({required this.title, required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onTap,
      child: Container(
        height: 180,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 18, offset: Offset(0, 8))],
          border: Border.all(color: AppColors.light.withOpacity(.5)),
        ),
        child: Row(
          children: [
            // نص وتعليمات
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  Text(subtitle, style: TextStyle(color: Colors.black.withOpacity(.7))),
                  const Spacer(),
                  FilledButton(onPressed: onTap, style: FilledButton.styleFrom(minimumSize: const Size(0, 40)), child: const Text('ادخل إلى EcoLand')),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // رسم 2D تمثيلي للأرض
            Expanded(child: _EcoLandIllustration()),
          ],
        ),
      ),
    );
  }
}

class _EcoLandIllustration extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _EcoLandPainter(),
      child: const SizedBox.expand(),
    );
  }
}

class _EcoLandPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()..color = const Color(0xFFEFF7F6);
    final ground = Paint()..color = const Color(0xFFD8F0EA);
    final grid = Paint()
      ..color = const Color(0x33009688)
      ..strokeWidth = 1;

    // أرضية عامة
    final r = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(18));
    canvas.drawRRect(r, bg);

    // قطعة أرض مركزية
    final land = RRect.fromRectAndRadius(
      Rect.fromLTWH(size.width * .05, size.height * .15, size.width * .9, size.height * .7),
      const Radius.circular(16),
    );
    canvas.drawRRect(land, ground);

    // شبكة مربعات بسيطة
    final cols = 5, rows = 3;
    final cellW = (size.width * .9) / cols;
    final cellH = (size.height * .7) / rows;
    final left = size.width * .05;
    final top = size.height * .15;
    for (int c = 1; c < cols; c++) {
      final x = left + c * cellW;
      canvas.drawLine(Offset(x, top), Offset(x, top + rows * cellH), grid);
    }
    for (int r = 1; r < rows; r++) {
      final y = top + r * cellH;
      canvas.drawLine(Offset(left, y), Offset(left + cols * cellW, y), grid);
    }

    // عناصر: شجرة، منزل، سلة إعادة تدوير، بحيرة صغيرة
    final tree = Paint()..color = AppColors.primary;
    final trunk = Paint()..color = const Color(0xFF6D4C41);
    final house = Paint()..color = const Color(0xFFFFF3E0);
    final roof = Paint()..color = const Color(0xFFFFB74D);
    final bin = Paint()..color = const Color(0xFF26A69A);
    final water = Paint()..color = const Color(0xFFB3E5FC);

    // منزل
    final hx = left + cellW * 0.4;
    final hy = top + cellH * 0.4;
    final houseRect = Rect.fromLTWH(hx, hy, cellW * 1.2, cellH * 1.1);
    canvas.drawRRect(RRect.fromRectAndRadius(houseRect, const Radius.circular(6)), house);
    final roofPath = Path()
      ..moveTo(hx - 4, hy)
      ..lineTo(hx + houseRect.width / 2, hy - cellH * .5)
      ..lineTo(hx + houseRect.width + 4, hy)
      ..close();
    canvas.drawPath(roofPath, roof);

    // شجرة
    final tx = left + cellW * 3.6;
    final ty = top + cellH * 0.7;
    canvas.drawRect(Rect.fromLTWH(tx + 10, ty + 20, 10, 28), trunk);
    canvas.drawCircle(Offset(tx + 15, ty + 10), 18, tree);
    canvas.drawCircle(Offset(tx + 5, ty + 24), 16, tree);
    canvas.drawCircle(Offset(tx + 25, ty + 24), 16, tree);

    // سلة تدوير
    final bx = left + cellW * 3.8;
    final by = top + cellH * 1.9;
    final binRect = RRect.fromRectAndRadius(Rect.fromLTWH(bx, by, 28, 28), const Radius.circular(4));
    canvas.drawRRect(binRect, bin);

    // بحيرة صغيرة
    final lake = RRect.fromRectAndRadius(Rect.fromLTWH(left + cellW * 1.8, top + cellH * 1.8, cellW, cellH * .6), const Radius.circular(12));
    canvas.drawRRect(lake, water);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/* ======================= Banner + Friends ======================= */

class _InlineBanner extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _InlineBanner({required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.dark,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              const Icon(Icons.campaign_outlined, color: Colors.white),
              const SizedBox(width: 10),
              Expanded(child: Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600))),
              const Icon(Icons.chevron_left, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }
}

class _FriendCard extends StatelessWidget {
  final String name;
  final int points;
  final int streak;
  const _FriendCard({required this.name, required this.points, required this.streak});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 130,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 14, offset: Offset(0, 6))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(backgroundColor: AppColors.primary.withOpacity(.12), child: const Icon(Icons.person, color: AppColors.primary)),
              const SizedBox(width: 8),
              Expanded(child: Text(name, style: const TextStyle(fontWeight: FontWeight.w700))),
              Row(children: [const Icon(Icons.local_fire_department_outlined, size: 18, color: AppColors.primary), const SizedBox(width: 4), Text('$streak')]),
            ],
          ),
          const Spacer(),
          Row(children: [const Icon(Icons.monetization_on_outlined, size: 18, color: AppColors.primary), const SizedBox(width: 6), Text('$points نقطة', style: const TextStyle(fontWeight: FontWeight.w600))]),
        ],
      ),
    );
  }
}

/* ======================= Bottom Navigation (زر الوسط = الخريطة) ======================= */

class _BottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final VoidCallback onCenterTap;
  const _BottomNav({required this.currentIndex, required this.onTap, required this.onCenterTap});

  @override
  Widget build(BuildContext context) {
    final items = [
      _NavItem(icon: Icons.home_outlined, label: 'الرئيسية'),
      _NavItem(icon: Icons.checklist_outlined, label: 'مهامي'),
      _NavItem(icon: Icons.map_outlined, label: 'الخريطة', isCenter: true), // <— تغيّر هنا
      _NavItem(icon: Icons.notifications_none, label: 'الإشعارات'),
      _NavItem(icon: Icons.group_outlined, label: 'الأصدقاء'),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: Container(
          height: 70,
          color: Colors.white,
          child: Row(
            children: List.generate(items.length, (i) {
              final it = items[i];
              final selected = i == currentIndex;
              if (it.isCenter) {
                return Expanded(
                  child: Center(
                    child: InkResponse(
                      onTap: onCenterTap,
                      radius: 40,
                      child: Container(
                        width: 58,
                        height: 58,
                        decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                        child: const Icon(Icons.map_outlined, color: Colors.white), // <— أيقونة الخريطة
                      ),
                    ),
                  ),
                );
              }
              return Expanded(
                child: InkWell(
                  onTap: () => onTap(i),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(it.icon, color: selected ? AppColors.primary : Colors.black54),
                      const SizedBox(height: 2),
                      Text(
                        it.label,
                        style: TextStyle(fontSize: 12, fontWeight: selected ? FontWeight.w800 : FontWeight.w500, color: selected ? AppColors.primary : Colors.black54),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final String label;
  final bool isCenter;
  _NavItem({required this.icon, required this.label, this.isCenter = false});
}

/* ======================= Background Painter ======================= */

class _BgPainter extends CustomPainter {
  final double t;
  _BgPainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final g1 = LinearGradient(
      begin: Alignment.topRight,
      end: Alignment.bottomLeft,
      colors: [AppColors.background, Color.lerp(AppColors.background, Colors.white, .25)!],
    ).createShader(Offset.zero & size);

    final g2 = RadialGradient(
      center: Alignment(.9 * math.cos(t * 2 * math.pi), .8 * math.sin(t * 2 * math.pi)),
      radius: 1.2,
      colors: const [Color(0x11009688), Color(0x00009688)],
    ).createShader(Offset.zero & size);

    canvas.drawRect(Offset.zero & size, Paint()..shader = g1);
    canvas.drawRect(Offset.zero & size, Paint()..shader = g2);
  }

  @override
  bool shouldRepaint(covariant _BgPainter oldDelegate) => oldDelegate.t != t;
}
