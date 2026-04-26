import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import '/services/xp_service.dart'; 

enum IslandLevel { seedling, sprout, tree, guardian, champion }

IslandLevel islandLevelFromId(String id) {
  switch (id) {
    case 'seedling':  return IslandLevel.seedling;
    case 'sprout':    return IslandLevel.sprout;
    case 'tree':      return IslandLevel.tree;
    case 'guardian':  return IslandLevel.guardian;
    case 'champion':  return IslandLevel.champion;
    default:          return IslandLevel.seedling;
  }
}

class FriendIslandData {
  final String name;
  final IslandLevel level;
  const FriendIslandData({required this.name, required this.level});
}

// ── ثوابت الـ canvas ──
const _canvasW = 1400.0;
const _canvasH = 1100.0;

// ── مركز وحجم جزيرة المستخدم ──
const _ux = 700.0, _uy = 680.0;
const _iw = 460.0, _ih = 260.0;

// ── حجم جزر الأصدقاء ──
const _fw = 230.0, _fh = 160.0;

// ── مواقع جزر الأصدقاء ──
const _friendCenters = [
  Offset(310, 620),   // يسار
  Offset(1090, 620),  // يمين
  Offset(340, 460),   // يسار فوق
  Offset(1060, 460),  // يمين فوق
  Offset(340, 790),   // يسار أسفل
  Offset(1060, 790),  // يمين أسفل
];

// ════════════════════════════════════════════════════════
//  Widget الرئيسي
// ════════════════════════════════════════════════════════
class EcoLandIsland extends StatefulWidget {
  final IslandLevel level;
  final bool isReadOnly;
  final bool allowPan;
  final bool showFriends;
  final List<FriendIslandData>? friends;
  final Map<String, int> taskCounts; // ← جديد

  const EcoLandIsland({
    super.key,
    this.level = IslandLevel.tree,
    this.isReadOnly = false,
    this.allowPan = true,
    this.showFriends = false,
    this.friends,
    this.taskCounts = const {}, // ← جديد
  });

  @override
  State<EcoLandIsland> createState() => _EcoLandIslandState();
}

class _EcoLandIslandState extends State<EcoLandIsland>
    with SingleTickerProviderStateMixin {

  late final AnimationController _waveCtrl;
  List<FriendIslandData> _friends = [];
  bool _loadingFriends = false;
  double? _lockedDy;
  // TransformationController للـ InteractiveViewer
  final _transformCtrl = TransformationController();

  @override
  void initState() {
    super.initState();
    _waveCtrl = AnimationController(
      vsync: this, duration: const Duration(seconds: 3))..repeat();

    if (widget.showFriends && widget.friends == null) _loadFriends();
    else if (widget.friends != null) _friends = widget.friends!;

    // نمركز على جزيرة المستخدم بعد أول frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 100), () {
        _centerOnUser();
        _lockedDy = _transformCtrl.value.getTranslation().y;

        _transformCtrl.addListener(() {
          if (_lockedDy == null) return;

          final m = _transformCtrl.value;
          final tx = m.getTranslation().x;
          final currentScale = m.getMaxScaleOnAxis();

          final fixed = Matrix4.identity()
            ..translate(tx, _lockedDy!)
            ..scale(currentScale);

          // عشان ما ندخل لوب لا نهائي
          if ((m.getTranslation().y - _lockedDy!).abs() > 0.1) {
            _transformCtrl.value = fixed;
          }
        });
      });
    });
  }

  void _centerOnUser() {
    if (!mounted) return;
    final size = context.size;
    if (size == null) return;

    final scale = 0.75;
    final dx = size.width / 2 - _ux * scale;
    final dy = size.height * 0.58 - _uy * scale;

    _transformCtrl.value = Matrix4.identity()
      ..translate(dx, dy)
      ..scale(scale);

    _lockedDy = dy;
  }
  void _zoomBy(double factor) {
    final current = _transformCtrl.value.clone();
    final currentScale = current.getMaxScaleOnAxis();
    final newScale = (currentScale * factor).clamp(0.55, 1.8);

    final tx = current.getTranslation().x;
    final dy = _lockedDy ?? current.getTranslation().y;

    _transformCtrl.value = Matrix4.identity()
      ..translate(tx, dy)
      ..scale(newScale);
  }

  void _resetView() {
    _centerOnUser();
  }

  @override
  void dispose() {
    _waveCtrl.dispose();
    _transformCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadFriends() async {
    if (_loadingFriends) return;
    setState(() => _loadingFriends = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      final myDoc = await FirebaseFirestore.instance
          .collection('users').doc(uid).get();
      final List<dynamic> following = myDoc.data()?['following'] ?? [];
      if (following.isEmpty) return;

      final futures = following.take(10).map((fid) =>
        FirebaseFirestore.instance.collection('users')
            .doc(fid as String).get());
      final docs = await Future.wait(futures);
      final raw = <Map<String, dynamic>>[];
      for (final doc in docs) {
        if (!doc.exists) continue;
        final d = doc.data()!;
        final int friendXp = (d['xp'] ?? 0) is int 
            ? d['xp'] ?? 0 
            : ((d['xp'] ?? 0) as num).toInt();
        final friendLevel = getCurrentLevel(friendXp);

        raw.add({
          'name': d['username'] ?? 'صديق',
          'levelId': friendLevel.id, // ← من XP مباشرة
          'lastActivity': d['lastActivityAt'],
        });
      }
      raw.sort((a, b) {
        final ta = a['lastActivity'] as Timestamp?;
        final tb = b['lastActivity'] as Timestamp?;
        if (ta == null && tb == null) return 0;
        if (ta == null) return 1;
        if (tb == null) return -1;
        return tb.compareTo(ta);
      });
      if (mounted) {
        setState(() => _friends = raw.take(6).map((f) => FriendIslandData(
          name: f['name'],
          level: islandLevelFromId(f['levelId']),
        )).toList());
      }
    } catch (e) { debugPrint('Error: $e'); }
    finally { if (mounted) setState(() => _loadingFriends = false); }
  }
@override
Widget build(BuildContext context) {
  final friends = (widget.friends ?? _friends).take(6).toList();

if (!widget.allowPan) {
  return LayoutBuilder(
    builder: (context, constraints) {
      final W = constraints.maxWidth;
      final H = constraints.maxHeight;

      final islandW = W * 1.4;
      final islandH = islandW * 0.70;

      return Stack(
        fit: StackFit.expand,
        children: [
          AnimatedBuilder(
            animation: _waveCtrl,
            builder: (_, __) => CustomPaint(
              painter: _BgPainter(wave: _waveCtrl.value, white: true),
            ),
          ),
          Positioned(
            left: (W - islandW) / 2,
            top: (H - islandH) / 2,
            child: _IslandWidget(
              level: widget.level,
              width: islandW,
              isUser: true,
              name: '',
              taskCounts: widget.taskCounts,
            ),
          ),
        ],
      );
    },
  );
}

  // Global EcoLand
  return Stack(
    fit: StackFit.expand,
    children: [
      // 1) الخلفية ثابتة كخلفية صفحة
      AnimatedBuilder(
        animation: _waveCtrl,
        builder: (_, __) => CustomPaint(
          painter: _BgPainter(wave: _waveCtrl.value),
        ),
      ),

      // 2) فقط الجزر والجسور داخل InteractiveViewer
      InteractiveViewer(
        transformationController: _transformCtrl,
        constrained: false,
        boundaryMargin: const EdgeInsets.symmetric(
          horizontal: 1300,
          vertical: 700,
        ),
        clipBehavior: Clip.none,
        minScale: 0.55,
        maxScale: 1.8,
        panEnabled: true,
        scaleEnabled: false,
        child: SizedBox(
          width: _canvasW,
          height: _canvasH,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // الجسور
              for (int i = 0; i < friends.length; i++)
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _BridgePainter(
                        from: const Offset(_ux, _uy + 10),
                        to: _friendCenters[i],
                      ),
                    ),
                  ),
                ),

              // جزر الأصدقاء
              for (int i = 0; i < friends.length; i++)
                Positioned(
                  left: _friendCenters[i].dx - (_fw / 2),
                  top: _friendCenters[i].dy - (_fh / 2) + 18,
                  child: _IslandWidget(
                    level: friends[i].level,
                    width: _fw,
                    isUser: false,
                    name: friends[i].name,
                    nameOnRight: _friendCenters[i].dx > _ux,
                  ),
                ),

              // جزيرة المستخدم
              Positioned(
                left: _ux - (_iw / 2),
                top: _uy - (_ih / 2) - 40,
                child: _IslandWidget(
                  level: widget.level,
                  width: _iw,
                  isUser: true,
                  name: '',
                  taskCounts: widget.taskCounts, // ← جديد
                ),
              ),
            ],
          ),
        ),
      ),

      // 3) أزرار التحكم ثابتة فوق الصفحة
      Positioned(
        right: 16,
        top: 20,
        child: Column(
          children: [
            // _CtrlBtn('+', () => setState(() => _zoomBy(1.2))),
            // const SizedBox(height: 8),
            // _CtrlBtn('−', () => setState(() => _zoomBy(1 / 1.2))),
            const SizedBox(height: 8),
            _CtrlBtn('⌂', () => setState(_resetView)),
          ],
        ),
      ),
    ],
  );
}

// Offset _getFriendPos(int i, double W, double H) {
//   final positions = [
//     Offset(W*0.10, H*0.48),  // يسار
//     Offset(W*0.90, H*0.48),  // يمين
//     Offset(W*0.12, H*0.28),  // يسار فوق
//     Offset(W*0.88, H*0.28),  // يمين فوق
//     Offset(W*0.12, H*0.70),  // يسار أسفل
//     Offset(W*0.88, H*0.70),  // يمين أسفل
//   ];
//   return positions[i];
// }
  // Widget _buildStaticIsland() {
  //   return AnimatedBuilder(
  //     animation: _waveCtrl,
  //     builder: (_, __) => CustomPaint(
  //       painter: _BgPainter(wave: _waveCtrl.value),
  //       child: Center(
  //         child: _IslandWidget(
  //           level: widget.level,
  //           width: 320,
  //           isUser: true,
  //           name: '',
  //         ),
  //       ),
  //     ),
  //   );
  // }
}

// ════════════════════════════════════════════════════════
//  جزيرة واحدة
// ════════════════════════════════════════════════════════
class _IslandWidget extends StatelessWidget {
  final IslandLevel level;
  final double width;
  final bool isUser;
  final String name;
  final bool nameOnRight;
  final double nameSideOffset;
  final Map<String, int> taskCounts; // ← جديد


  const _IslandWidget({
    required this.level,
    required this.width,
    required this.isUser,
    required this.name,
    this.nameOnRight = true,
    this.nameSideOffset = 8,
    this.taskCounts = const {}, // ← جديد
  });
  // فيقرز التاسكات — كلها يمين
  static const _categoryPositions = {
    // مواصلات — يمين فوق
    'metro':     ( 0.57,  -0.05),
    'bus':       ( 0.45,  0.45),
    'cycle':     ( 0.35,  0.12),
    'scooter':   ( 0.15,  -0.48),

    // تدوير وارتكل — يمين أسفل
    'article': ( 0.15,  0.40),
    'recycling':   ( 0.22,  0.66),

    // محلي — يمين وسط
    'local':     ( 0.32,  -0.17),
  };

  List<Widget> _buildTaskCountElements(double iw, double ih) {
    final cx = iw / 2;
    final cy = ih * 0.38;
    final results = <Widget>[];

    _categoryPositions.forEach((category, pos) {
      final count = taskCounts[category] ?? 0;
      final tier = _getTier(count);
      if (tier == 0) return;

      final asset = _getAsset(category, tier);
      if (asset.isEmpty) return;

      // ── الفيقر الأول (tier 1, 2, 3) ──
      if (tier < 4) {
        final ew = iw * 0.17; // ← حجم العادي
        final x = cx + pos.$1 * iw * 0.38 - ew/2;
        final y = cy + pos.$2 * ih * 0.38 - ew/2;

        results.add(Positioned(
          left: x, top: y,
          child: Image.asset('assets/img/$asset.png',
            width: ew, height: ew, fit: BoxFit.contain),
        ));

        // ── الفيقر الثاني (tier 2, 3) ──
        if (tier >= 2) {
          final ew2 = iw * 0.15; // ← حجم الثاني
          final dx2 = ew * 0.14;  // ← يمين/يسار من الأول
          final dy2 = ew * 0.24;  // ← فوق/تحت من الأول
          results.add(Positioned(
            left: x + dx2, top: y + dy2,
            child: Image.asset('assets/img/${_getAsset(category, 1)}.png',
              width: ew2, height: ew2, fit: BoxFit.contain),
          ));
        }

        // ── الفيقر الثالث (tier 3) ──
        if (tier >= 3) {
          final ew3 = iw * 0.17 ;
          final dx3 = ew * -0.14;   // ← يمين/يسار من الأول
          final dy3 = -ew * -0.14;  // ← فوق/تحت من الأول
          results.add(Positioned(
            left: x + dx3, top: y + dy3,
            child: Image.asset('assets/img/${_getAsset(category, 1)}.png',
              width: ew3, height: ew3, fit: BoxFit.contain),
          ));
        }
      }

      // ── الذهبي (tier 4) — مستقل كلياً ──
      if (tier == 4) {
        final ew4 = iw * 0.23;  // ← حجم الذهبي
        final x4 = cx + pos.$1 * iw * 0.38 - ew4/2 + ew4 * 0.0;  // ← تحكمي بالأفقي
        final y4 = cy + pos.$2 * ih * 0.38 - ew4/2 - ew4 * -0.1;  // ← تحكمي بالعمودي
        results.add(Positioned(
          left: x4, top: y4,
          child: Image.asset('assets/img/$asset.png',
            width: ew4, height: ew4, fit: BoxFit.contain),
        ));
      }
    });

    return results;
  }

  @override
  Widget build(BuildContext context) {
    final h = width * 0.70;

    return SizedBox(
      width: width,
      height: h + 52,
      child: Stack(clipBehavior: Clip.none, children: [

        // الجزيرة الأساسية
        Positioned(top:0, left:0, right:0, height:h,
          child: Image.asset('assets/img/level1.png', fit: BoxFit.contain)),

        // العناصر
        if (isUser)
          ..._buildUserElements(width, h)
        else
          ..._buildFriendElements(width, h, level),

        // فيقرز التاسكات
        if (isUser)
          ..._buildTaskCountElements(width, h),

        // اسم الصديق
        if (!isUser && name.isNotEmpty)
          Positioned(
            top: -5,
            left: 0, right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.92),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: const Color(0xFF2E7D32),
                    width: 1.5,
                  ),
                ),
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: width * 0.07,
                    fontWeight: FontWeight.w600,
                    color: const Color.fromARGB(255, 0, 0, 0),
                  ),
                ),
              ),
            ),
          ),
      ]),
    );
  }
  int _getTier(int count) {
    if (count >= 30) return 4; // ذهبي
    if (count >= 20) return 3;
    if (count >= 10) return 2;
    if (count >= 3)  return 1;
    return 0;
  }

  // اسم الصورة حسب الـ tier
  String _getAsset(String category, int tier) {
    final gold = tier == 4;
    final suffix = gold ? '_gold' : '';
    switch (category) {
      case 'metro':     return 'metro$suffix';
      case 'bus':       return 'bus$suffix';
      case 'cycle':     return 'bicycle$suffix';
      case 'scooter':   return 'scooter$suffix';
      case 'recycling': return 'can$suffix';
      case 'article':   return 'article$suffix';
      case 'local':     return 'items$suffix';
      default:          return '';
    }
  }

  List<Widget> _buildUserElements(double iw, double ih) {
    final cx = iw / 2;
    final cy = ih * 0.38;

    // عناصر اللفل — كلها يسار
    final els = [
      // L1: شجيرتين يسار
      ('bush',         -0.32,  0.05, 0.13, 1),
      // ('bush',          0.24,  0.05, 0.12, 1),

      // L2: أشجار يسار
      ('tree',         -0.10, -0.28, 0.18, 2),
      ('tree',         -0.40, -0.12, 0.17, 2),
      ('bush',         -0.40,  0.30, 0.17, 2),

      // // L3: بركة وسط + زهور يسار
      ('pond',         -0.05,  0.08, 0.24, 3),
      ('flower_pink',  -0.22, -0.04, 0.07, 3),
      ('flower_pink',   0.10, -0.13, 0.07, 3),
      ('flower_purple', 0.00,  0.36, 0.07, 3),
      ('flower_purple', 0.10,  0.20, 0.07, 3),

      // // L4: نخلة + طاحونة يسار
      // ('palm',         -0.38,  -0.25, 0.22, 4),
      // ('palm',          0.15,  -0.48, 0.17, 4),
      // ('windmill',     -0.12, -0.32, 0.20, 4),
      ('flower_purple',-0.25,  0.12, 0.07, 3),
      ('flower_pink',-0.20, -0.12, 0.07, 3),
      ('flower_purple',   0.06, -0.15, 0.07, 3),
      ('flower_pink',   0.00, -0.15, 0.07, 3),

    ];

    return els.where((e) {
      if (e.$1 == 'sprout') return false; 
      return e.$5 <= level.index;
    }).map((e) {
      final ew = iw * e.$4;
      final x  = cx + e.$2 * iw * 0.44 - ew/2;
      final y  = cy + e.$3 * ih * 0.44 - ew/2;
      return Positioned(left:x, top:y,
        child: Image.asset('assets/img/${e.$1}.png',
          width:ew, height:ew, fit:BoxFit.contain));
    }).toList();
  }

  List<Widget> _buildFriendElements(double iw, double ih, IslandLevel lv) {
    final cx = iw / 2;
    final cy = ih * 0.38;

    final els = [
      ('bush',         -0.32,  0.05, 0.13, 1),
      ('tree',         -0.10, -0.28, 0.18, 2),
      ('tree',         -0.40, -0.12, 0.17, 2),
      ('bush',         -0.40,  0.30, 0.17, 2),
      ('pond',         -0.05,  0.08, 0.24, 3),
      ('flower_pink',  -0.22, -0.04, 0.07, 3),
      ('flower_pink',   0.10, -0.13, 0.07, 3),
      ('flower_purple', 0.00,  0.36, 0.07, 3),
      ('flower_purple', 0.10,  0.20, 0.07, 3),
      ('flower_purple',-0.25,  0.12, 0.07, 3),
      ('flower_pink',  -0.20, -0.12, 0.07, 3),
      ('flower_purple', 0.06, -0.15, 0.07, 3),
      ('flower_pink',   0.00, -0.15, 0.07, 3),
    ];

    return els.where((e) {
      if (e.$1 == 'sprout') return false;
      return e.$5 <= lv.index;
    }).map((e) {
      final ew = iw * e.$4;
      final x  = cx + e.$2 * iw * 0.44 - ew/2;
      final y  = cy + e.$3 * ih * 0.44 - ew/2;
      return Positioned(left:x, top:y,
        child: Image.asset('assets/img/${e.$1}.png',
          width:ew, height:ew, fit:BoxFit.contain));
    }).toList();
  }
}

// ════════════════════════════════════════════════════════
//  جسر خشبي
// ════════════════════════════════════════════════════════
class _BridgePainter extends CustomPainter {
  final Offset from, to;
  const _BridgePainter({required this.from, required this.to});

  @override
  void paint(Canvas canvas, Size size) {
    final dir  = to - from;
    final dist = dir.distance;
    if (dist < 1) return;
    final n    = dir / dist;
    final perp = Offset(-n.dy, n.dx);
    const bw   = 14.0;

    final start = from + n * 80;
    final end   = to   - n * 20;
    if ((end-start).distance < 10) return;

    Offset sag(double t) {
      final p = start + (end-start)*t;
      final s = math.sin(t*math.pi)*12;
      return Offset(p.dx - n.dy*s*0.2, p.dy + s*0.5);
    }

    final cnt = ((end-start).distance/13).floor().clamp(3, 28);

    // ألواح
    for (int i=0; i<=cnt; i++) {
      final p = sag(i/cnt);
      canvas.drawLine(p+perp*bw, p-perp*bw, Paint()
        ..color=const Color(0xFF8D6E63)
        ..strokeWidth=3.5..strokeCap=StrokeCap.round);
    }

    // حبال
    for (final side in [-1.0, 1.0]) {
      final path = Path();
      final p0 = sag(0)+perp*bw*side;
      path.moveTo(p0.dx, p0.dy);
      for (int i=1; i<=22; i++) {
        final p = sag(i/22)+perp*bw*side;
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(path, Paint()
        ..color=const Color(0xFF5D4037)
        ..style=PaintingStyle.stroke
        ..strokeWidth=2.0..strokeCap=StrokeCap.round);
    }

    // أعمدة
    for (final t in [0.25, 0.5, 0.75]) {
      final p = sag(t);
      for (final side in [-1.0, 1.0]) {
        final base = p+perp*bw*side;
        canvas.drawLine(base, base.translate(0,-16), Paint()
          ..color=const Color(0xFF6D4C41)
          ..strokeWidth=2.2..strokeCap=StrokeCap.round);
      }
    }
  }

  @override
  bool shouldRepaint(_BridgePainter o) => o.from!=from || o.to!=to;
}

// ════════════════════════════════════════════════════════
//  خلفية
// ════════════════════════════════════════════════════════
class _BgPainter extends CustomPainter {
  final double wave;
    final bool white; // جديد
  const _BgPainter({required this.wave, this.white = false});

  @override
  void paint(Canvas canvas, Size size) {
      if (white) {
        canvas.drawRect(
          Rect.fromLTWH(0, 0, size.width, size.height),
          Paint()..color = Colors.white,
        );
        return;
      }
    final W = size.width, H = size.height;

    // سماء
    canvas.drawRect(Rect.fromLTWH(0,0,W,H*0.42), Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter, end: Alignment.center,
        colors: [Color(0xFF87CEEB), Color(0xFFB8E4F5)],
      ).createShader(Rect.fromLTWH(0,0,W,H*0.42)));

    // ماء
    canvas.drawRect(Rect.fromLTWH(0,H*0.32,W,H*0.68), Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: [Color(0xFF26C6DA), Color(0xFF00838F)],
      ).createShader(Rect.fromLTWH(0,H*0.32,W,H*0.68)));

    // موجات
    final wp = Paint()
      ..color=Colors.white.withOpacity(0.13)
      ..style=PaintingStyle.stroke..strokeWidth=1.5;
    for (int i=0; i<5; i++) {
      final path = Path();
      final y = H*0.40 + i*26 + math.sin(wave*math.pi*2+i)*4;
      path.moveTo(0, y);
      for (double x=0; x<W; x+=3)
        path.lineTo(x, y+math.sin(x/45+wave*math.pi*2+i)*3.5);
      canvas.drawPath(path, wp);
    }

    // سحب
    _cloud(canvas, W*0.10, H*0.07, 0.72);
    _cloud(canvas, W*0.78, H*0.05, 0.88);
    _cloud(canvas, W*0.44, H*0.03, 0.60);
  }

  void _cloud(Canvas canvas, double x, double y, double s) {
    final p = Paint()..color=Colors.white.withOpacity(0.88);
    for (final (dx,dy,r) in [
      (0.0,0.0,20.0),(20.0,-8.0,15.0),(38.0,0.0,18.0),
      (54.0,-5.0,13.0),(-15.0,-4.0,12.0),
    ]) canvas.drawCircle(Offset(x+dx*s,y+dy*s), r*s, p);
  }

  @override
  bool shouldRepaint(_BgPainter o) => o.wave != wave;
}

// ════════════════════════════════════════════════════════
//  زر التحكم
// ════════════════════════════════════════════════════════
class _CtrlBtn extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _CtrlBtn(this.label, this.onTap);

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width:32, height:32,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.9),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [BoxShadow(
          color: Colors.black.withOpacity(0.12), blurRadius:4)],
      ),
      child: Center(child: Text(label,
        style: const TextStyle(fontSize:16, fontWeight:FontWeight.w600,
          color: Color(0xFF2E7D32))))));
}

// ════════════════════════════════════════════════════════
//  صفحة Global EcoLand
// ════════════════════════════════════════════════════════
class GlobalEcoLandPage extends StatelessWidget {
  const GlobalEcoLandPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFF87CEEB),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          flexibleSpace: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF5BA3C9), Color(0xFF87CEEB)],
              ),
            ),
          ),
          title: Text('واحة الأصدقاء',
            style: GoogleFonts.ibmPlexSansArabic(
              color: Colors.white, fontWeight: FontWeight.w700)),
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .doc(FirebaseAuth.instance.currentUser?.uid ?? '')
              .snapshots(),
          builder: (context, snap) {
            final data = snap.data?.data() ?? {};
            final int xp = data['xp'] ?? 0;
            final currentLevel = getCurrentLevel(xp);
            final islandLevel = islandLevelFromId(currentLevel.id);
            
            final taskCounts = <String, int>{};
            final counts = data['taskCounts'] as Map<String, dynamic>? ?? {};
            counts.forEach((k, v) {
              if (v is int) taskCounts[k] = v;
            });

            return EcoLandIsland(
              level: islandLevel,
              allowPan: true,
              showFriends: true,
              taskCounts: taskCounts, // ← جديد
            );
          },
        ),
      ),
    );
  }
}
