import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'services/background_container.dart';
import 'services/title_header.dart';
import '../services/app_colors.dart';
import 'home.dart' show IsoLand;
import 'services/xp_service.dart';

/* ======================= صفحة بروفايل الصديق ======================= */

class FriendProfilePage extends StatefulWidget {
  final String friendId;
  final String friendUsername;
  final int? pfpIndex;

  const FriendProfilePage({
    super.key,
    required this.friendId,
    required this.friendUsername,
    this.pfpIndex,
  });

  @override
  State<FriendProfilePage> createState() => _FriendProfilePageState();
}

class _FriendProfilePageState extends State<FriendProfilePage> {
  bool _isLoading = true;
  Map<String, dynamic>? _friendData;
  bool _isFollowing = false;

  @override
  void initState() {
    super.initState();
    _loadFriendData();
  }

  // حساب المستوى من النقاط
  int _calculateLevel(int points) {
    if (points < 100) return 1;
    if (points < 300) return 2;
    if (points < 600) return 3;
    if (points < 1000) return 4;
    if (points < 1500) return 5;
    return 6;
  }

  // النقاط المطلوبة للمستوى التالي
  int _nextLevelPoints(int level) {
    switch (level) {
      case 1: return 100;
      case 2: return 300;
      case 3: return 600;
      case 4: return 1000;
      case 5: return 1500;
      default: return 1500;
    }
  }

  // نقاط بداية المستوى الحالي
  int _currentLevelStartPoints(int level) {
    switch (level) {
      case 1: return 0;
      case 2: return 100;
      case 3: return 300;
      case 4: return 600;
      case 5: return 1000;
      default: return 1000;
    }
  }

  Future<void> _loadFriendData() async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;

      // جلب بيانات الصديق
      final friendDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.friendId)
          .get();

      if (!friendDoc.exists) {
        setState(() => _isLoading = false);
        return;
      }

      final data = friendDoc.data()!;

      // التحقق هل أتابع هذا الشخص
      bool isFollowing = false;
      if (currentUser != null) {
        final myDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(currentUser.uid)
            .get();
        final List<dynamic> following = myDoc.data()?['following'] ?? [];
        isFollowing = following.contains(widget.friendId);
      }

      setState(() {
        _friendData = data;
        _isFollowing = isFollowing;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('خطأ في تحميل بيانات الصديق: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _toggleFollow() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    try {
      if (_isFollowing) {
        // إلغاء المتابعة
        final confirm = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => Directionality(
            textDirection: TextDirection.rtl,
            child: Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              insetPadding: const EdgeInsets.symmetric(horizontal: 24),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset(
                      'assets/img/nameerThink.png',
                      height: 120,
                      fit: BoxFit.contain,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'هل أنت متأكد أنك تريد إلغاء متابعة ${widget.friendUsername}؟',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.ibmPlexSansArabic(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: appColors.dark,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: appColors.primary),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            onPressed: () => Navigator.of(ctx).pop(false),
                            child: Text(
                              'إلغاء',
                              style: GoogleFonts.ibmPlexSansArabic(
                                color: appColors.primary,
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: appColors.primary,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            onPressed: () => Navigator.of(ctx).pop(true),
                            child: Text(
                              'تأكيد',
                              style: GoogleFonts.ibmPlexSansArabic(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        if (confirm != true) return;

        await FirebaseFirestore.instance.collection('users').doc(currentUser.uid).update({
          'following': FieldValue.arrayRemove([widget.friendId]),
        });
        setState(() => _isFollowing = false);
      } else {
        // متابعة
        await FirebaseFirestore.instance.collection('users').doc(currentUser.uid).set({
          'following': FieldValue.arrayUnion([widget.friendId]),
        }, SetOptions(merge: true));
        setState(() => _isFollowing = true);
      }
    } catch (e) {
      debugPrint('خطأ في المتابعة: $e');
    }
  }

  Widget _buildAvatar(double radius) {
    final pfp = widget.pfpIndex ?? _friendData?['pfpIndex'];
    String? avatarPath;
    if (pfp != null && pfp is int && pfp >= 0 && pfp < 8) {
      avatarPath = 'assets/pfp/pfp${pfp + 1}.png';
    }

    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [appColors.primary.withOpacity(0.2), appColors.mint.withOpacity(0.3)],
        ),
        boxShadow: [BoxShadow(color: appColors.primary.withOpacity(0.2), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: CircleAvatar(
        radius: radius,
        backgroundColor: Colors.transparent,
        backgroundImage: avatarPath != null ? AssetImage(avatarPath) : null,
        child: avatarPath == null
            ? Icon(Icons.person_rounded, color: appColors.primary, size: radius)
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        extendBody: true,
        extendBodyBehindAppBar: true,
        backgroundColor: Colors.transparent,
        appBar: const NameerAppBar(showTitleInBar: false, showBack: true, height: 80),
        body: AnimatedBackgroundContainer(
          child: Builder(
            builder: (context) {
              final statusBar = MediaQuery.of(context).padding.top;
              const headerH = 20.0;
              const gap = 12.0;
              final topPadding = statusBar + headerH + gap;

              if (_isLoading) {
                return Center(
                  child: CircularProgressIndicator(color: appColors.primary),
                );
              }

              if (_friendData == null) {
                return Center(
                  child: Text(
                    'تعذّر تحميل البيانات',
                    style: GoogleFonts.ibmPlexSansArabic(color: appColors.dark),
                  ),
                );
              }

              final int points = (_friendData!['points'] ?? 0) is int
                  ? _friendData!['points']
                  : ((_friendData!['points'] ?? 0) as num).toInt();
              final int completedTasks = (_friendData!['completedTask'] ?? 0) is int
                  ? _friendData!['completedTask']
                  : ((_friendData!['completedTask'] ?? 0) as num).toInt();
              final int level = _calculateLevel(points);
              final int nextLevel = _nextLevelPoints(level);
              final int startLevel = _currentLevelStartPoints(level);
              final double progress = level >= 6
                  ? 1.0
                  : (points - startLevel) / (nextLevel - startLevel);

              return SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(16, topPadding, 16, 100),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── الهيدر: صورة + اسم + زر متابعة ──
                    _buildProfileHeader(points, level, completedTasks),

                    const SizedBox(height: 16),

                    // ── شريط التقدم للمستوى ──
                    _buildLevelProgress(level, points, nextLevel, startLevel, progress),

                    const SizedBox(height: 16),

                    // ── إحصائيات سريعة ──
                    _buildStatsRow(points, completedTasks, level),

                    const SizedBox(height: 16),

                    // ── EcoLand ──
                    _buildEcoLandSection(),

                    const SizedBox(height: 16),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  // ── هيدر البروفايل ──
  Widget _buildProfileHeader(int points, int level, int completedTasks) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 14, offset: const Offset(0, 4))],
      ),
      child: Row(
        children: [
          // الأفاتار
          _buildAvatar(38),
          const SizedBox(width: 16),

          // الاسم والمعلومات
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.friendUsername,
                  style: GoogleFonts.ibmPlexSansArabic(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: appColors.dark,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    _buildMiniChip('المستوى $level', Icons.stars_rounded, Colors.amber),
                    const SizedBox(width: 8),
                    _buildMiniChip('$points نقطة', Icons.eco_rounded, appColors.primary),
                  ],
                ),
              ],
            ),
          ),

          // زر المتابعة
          _buildFollowButton(),
        ],
      ),
    );
  }

  Widget _buildFollowButton() {
    return GestureDetector(
      onTap: _toggleFollow,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          gradient: _isFollowing
              ? null
              : LinearGradient(colors: [appColors.primary, appColors.tealSoft]),
          color: _isFollowing ? Colors.grey.shade100 : null,
          borderRadius: BorderRadius.circular(14),
          border: _isFollowing ? Border.all(color: Colors.grey.shade300) : null,
          boxShadow: _isFollowing
              ? null
              : [BoxShadow(color: appColors.primary.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 3))],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _isFollowing ? Icons.check_rounded : Icons.person_add_rounded,
              size: 16,
              color: _isFollowing ? Colors.grey.shade600 : Colors.white,
            ),
            const SizedBox(width: 6),
            Text(
              _isFollowing ? 'متابَع' : 'متابعة',
              style: GoogleFonts.ibmPlexSansArabic(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: _isFollowing ? Colors.grey.shade600 : Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── شريط تقدم المستوى ──
  Widget _buildLevelProgress(int level, int points, int nextLevel, int startLevel, double progress) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'تقدم المستوى',
                style: GoogleFonts.ibmPlexSansArabic(fontSize: 14, fontWeight: FontWeight.w700, color: appColors.dark),
              ),
              Text(
                level >= 6 ? 'المستوى الأقصى 🏆' : 'المستوى $level ← ${level + 1}',
                style: GoogleFonts.ibmPlexSansArabic(fontSize: 12, fontWeight: FontWeight.w600, color: appColors.primary),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              minHeight: 10,
              backgroundColor: Colors.grey.shade100,
              valueColor: AlwaysStoppedAnimation<Color>(appColors.primary),
            ),
          ),
          const SizedBox(height: 8),
          if (level < 6)
            Text(
              '${points - startLevel} / ${nextLevel - startLevel} نقطة',
              style: GoogleFonts.ibmPlexSansArabic(fontSize: 11, color: Colors.grey.shade600),
            ),
        ],
      ),
    );
  }

  // ── الإحصائيات السريعة ──
  Widget _buildStatsRow(int points, int completedTasks, int level) {
    final int xp = (_friendData!['xp'] ?? 0) is int
        ? _friendData!['xp'] ?? 0
        : ((_friendData!['xp'] ?? 0) as num).toInt();
    final String currentLevelId = _friendData!['currentLevel'] ?? 'seedling';
    final int friendXp = (_friendData!['xp'] ?? 0) is int
        ? _friendData!['xp'] ?? 0
        : ((_friendData!['xp'] ?? 0) as num).toInt();
    final LevelModel friendLevel = getCurrentLevel(friendXp);

    return Column(
      children: [
        // الصف الأول
        Row(
          children: [
            Expanded(child: _buildStatCard('النقاط', '$points', Icons.stars_rounded, Colors.amber)),
            const SizedBox(width: 10),
            Expanded(child: _buildStatCard('المهام المكتملة', '$completedTasks', Icons.task_alt_rounded, Colors.green)),
            const SizedBox(width: 10),
            Expanded(child: _buildStatCard('المستوى', '$level', Icons.flag_rounded, appColors.primary)),
          ],
        ),
        const SizedBox(height: 10),
        // الصف الثاني
        Row(
          children: [
            Expanded(child: _buildStatCard('XP', '$xp', Icons.bolt_rounded, Colors.deepPurple)),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: _buildStatCard('المرحلة', '${friendLevel.icon} ${friendLevel.nameAr}', Icons.eco_rounded, friendLevel.color),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: color.withOpacity(0.12), shape: BoxShape.circle),
            child: Icon(icon, size: 20, color: color),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: GoogleFonts.ibmPlexSansArabic(fontSize: 18, fontWeight: FontWeight.w900, color: appColors.dark),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: GoogleFonts.ibmPlexSansArabic(fontSize: 11, color: Colors.grey.shade600),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // ── قسم EcoLand ──
  Widget _buildEcoLandSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // العنوان
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: appColors.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.landscape_rounded, color: appColors.primary, size: 20),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'EcoLand',
                    style: GoogleFonts.ibmPlexSansArabic(fontSize: 17, fontWeight: FontWeight.w800, color: appColors.dark),
                  ),
                  Text(
                    'أرض ${widget.friendUsername}',
                    style: GoogleFonts.ibmPlexSansArabic(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ],
              ),
              const Spacer(),
              // شارة "للعرض فقط"
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: appColors.mint.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '👁 للعرض فقط',
                  style: GoogleFonts.ibmPlexSansArabic(fontSize: 11, fontWeight: FontWeight.w600, color: appColors.primary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // الـ IsoLand
          const SizedBox(
            width: double.infinity,
            height: 180,
            child: IsoLand(
              rows: 6,
              cols: 6,
              height: 160,
              thickness: 14,
              topColor: appColors.mint,
              sideColor: appColors.tealSoft,
              gridColor: appColors.sea,
              gridOpacity: .08,
            ),
          ),

          const SizedBox(height: 12),

          // نص توضيحي
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: appColors.primary.withOpacity(0.05),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, size: 16, color: appColors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'أرض صديقك تنمو كلما أنجز مهام استدامة أكثر!',
                    style: GoogleFonts.ibmPlexSansArabic(fontSize: 12, color: appColors.dark.withOpacity(0.7)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniChip(String text, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(
            text,
            style: GoogleFonts.ibmPlexSansArabic(fontSize: 11, fontWeight: FontWeight.w600, color: appColors.dark),
          ),
        ],
      ),
    );
  }
}