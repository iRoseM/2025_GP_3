import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

// ====================================================
// نموذج المرحلة
// ====================================================
class LevelModel {
  final int index;
  final String id;
  final String nameAr;
  final int requiredXp;
  final String icon;
  final Color color;

  const LevelModel({
    required this.index,
    required this.id,
    required this.nameAr,
    required this.requiredXp,
    required this.icon,
    required this.color,
  });
}

// ====================================================
// تعريف جميع المراحل
// ====================================================
const List<LevelModel> kLevels = [
  LevelModel(
    index: 0,
    id: 'seedling',
    nameAr: 'بذرة',
    requiredXp: 0,
    icon: '🌱',
    color: Color(0xFF81C784),
  ),
  LevelModel(
    index: 1,
    id: 'sprout',
    nameAr: 'شجيرة',
    requiredXp: 100,
    icon: '🌿',
    color: Color(0xFF4CAF50),
  ),
  LevelModel(
    index: 2,
    id: 'tree',
    nameAr: 'شجرة',
    requiredXp: 250,
    icon: '🌳',
    color: Color(0xFF2E7D32),
  ),
  LevelModel(
    index: 3,
    id: 'guardian',
    nameAr: 'واحة',
    requiredXp: 500,
    icon: '🌍',
    color: Color(0xFF00796B),
  ),
  LevelModel(
    index: 4,
    id: 'champion',
    nameAr: 'بطل',
    requiredXp: 900,
    icon: '🏆',
    color: Color(0xFFF9A825),
  ),
];

// ====================================================
// فيقرز كل مستوى
// ====================================================
String? getLevelFigurePath(String levelId) {
  switch (levelId) {
    case 'sprout':
      return 'assets/img/bush.png';
    case 'tree':
      return 'assets/img/tree.png';
    case 'guardian':
      return 'assets/img/pond.png';
    case 'champion':
      return 'assets/img/palm.png';
    default:
      return null;
  }
}

// ====================================================
// XP لكل مستوى صعوبة
// ====================================================
int getXpForTask(String levelId) {
  switch (levelId) {
    case 'hard':
      return 35;
    case 'medium':
      return 20;
    case 'beginner':
    default:
      return 10;
  }
}

// ====================================================
// احسب المرحلة الحالية من XP
// ====================================================
LevelModel getCurrentLevel(int xp) {
  LevelModel current = kLevels.first;
  for (final level in kLevels) {
    if (xp >= level.requiredXp) current = level;
  }
  return current;
}

// ====================================================
// المرحلة التالية
// ====================================================
LevelModel? getNextLevel(int xp) {
  for (int i = kLevels.length - 1; i >= 0; i--) {
    if (xp >= kLevels[i].requiredXp) {
      if (i + 1 < kLevels.length) return kLevels[i + 1];
      return null;
    }
  }
  return kLevels[1];
}

// ====================================================
// نسبة التقدم
// ====================================================
double getLevelProgress(int xp) {
  final current = getCurrentLevel(xp);
  final next = getNextLevel(xp);
  if (next == null) return 1.0;
  final xpInLevel = xp - current.requiredXp;
  final xpNeeded = next.requiredXp - current.requiredXp;
  return (xpInLevel / xpNeeded).clamp(0.0, 1.0);
}

// ====================================================
// بوب اب ترقية المستوى
// ====================================================
Future<void> showLevelUpDialog(BuildContext context, LevelModel level) async {
  final figurePath = getLevelFigurePath(level.id);

  await showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => Directionality(
      textDirection: TextDirection.rtl,
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                'assets/img/nameerHappy.png',
                height: 150,
                fit: BoxFit.contain,
              ),
              const SizedBox(height: 16),
              Text(
                'تهانينا، حصلت على ترقية جديدة🎉!',
                textAlign: TextAlign.center,
                style: GoogleFonts.ibmPlexSansArabic(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: appColors.dark,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'وصلت لمستوى',
                textAlign: TextAlign.center,
                style: GoogleFonts.ibmPlexSansArabic(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: appColors.dark,
                ),
              ),
              Text(
                '${level.nameAr} ${level.icon}',
                textAlign: TextAlign.center,
                style: GoogleFonts.ibmPlexSansArabic(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: appColors.dark,
                ),
              ),
              if (figurePath != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        const Color(0xFFFBBF24).withOpacity(0.15),
                        const Color(0xFFF59E0B).withOpacity(0.05),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: const Color(0xFFF59E0B).withOpacity(0.4),
                    ),
                  ),
                  child: Column(
                    children: [
                      Text(
                        'مجسم جديد أضيف لك في EcoLand الخاصة بك!',
                        style: GoogleFonts.ibmPlexSansArabic(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF92400E),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Image.asset(figurePath, height: 70, fit: BoxFit.contain),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 24),
              Center(
                child: SizedBox(
                  width: 140,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: appColors.primary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 10,
                      ),
                    ),
                    onPressed: () => Navigator.pop(ctx),
                    child: Text(
                      'رائع!',
                      style: GoogleFonts.ibmPlexSansArabic(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

// ====================================================
// XP service
// ====================================================
class XpService {
  static final _db = FirebaseFirestore.instance;
  static final _auth = FirebaseAuth.instance;

  /// أضف XP وارجع المستوى الجديد إذا ترقّى
  static Future<LevelModel?> addXpForTask({required int taskPoints}) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return null;

    final xpToAdd = (taskPoints * 0.5).round();
    final userRef = _db.collection('users').doc(uid);

    LevelModel? levelUp;

    await _db.runTransaction((tx) async {
      final snap = await tx.get(userRef);
      final currentXp = (snap.data()?['xp'] ?? 0) as int;
      final newXp = currentXp + xpToAdd;

      final oldLevel = getCurrentLevel(currentXp);
      final newLevel = getCurrentLevel(newXp);

      // تحقق من الترقية
      if (newLevel.id != oldLevel.id) {
        levelUp = newLevel;
      }

      tx.update(userRef, {'xp': newXp, 'currentLevel': newLevel.id});
    });

    return levelUp;
  }

  static Stream<DocumentSnapshot> userStream() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw Exception('User not logged in');
    return _db.collection('users').doc(uid).snapshots();
  }
}
