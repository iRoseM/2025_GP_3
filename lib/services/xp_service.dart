import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

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
Future<void> showLevelUpDialog(
  BuildContext context,
  LevelModel newLevel,
) async {
  final figurePath = getLevelFigurePath(newLevel.id);

  await showDialog(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withOpacity(0.7),
    builder: (ctx) => Directionality(
      textDirection: TextDirection.rtl,
      child: Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: newLevel.color.withOpacity(0.3),
                blurRadius: 30,
                spreadRadius: 5,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ✨ نجوم فوق
              Text('✨ ✨ ✨', style: TextStyle(fontSize: 22)),
              const SizedBox(height: 12),

              // أيقونة المستوى
              Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [newLevel.color.withOpacity(0.7), newLevel.color],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: newLevel.color.withOpacity(0.4),
                      blurRadius: 20,
                      spreadRadius: 3,
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    newLevel.icon,
                    style: const TextStyle(fontSize: 42),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // مبروك
              Text(
                '🎉 مبروك!',
                style: GoogleFonts.ibmPlexSansArabic(
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  color: newLevel.color,
                ),
              ),

              const SizedBox(height: 6),

              Text(
                'وصلت لمستوى',
                style: GoogleFonts.ibmPlexSansArabic(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
              ),

              Text(
                newLevel.nameAr,
                style: GoogleFonts.ibmPlexSansArabic(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: newLevel.color,
                ),
              ),

              const SizedBox(height: 20),

              // الفيقر الجديد
              if (figurePath != null) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        const Color(0xFFFBBF24).withOpacity(0.15),
                        const Color(0xFFF59E0B).withOpacity(0.05),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: const Color(0xFFF59E0B).withOpacity(0.4),
                    ),
                  ),
                  child: Column(
                    children: [
                      Text(
                        'فيقر جديد في EcoLand! 🌍',
                        style: GoogleFonts.ibmPlexSansArabic(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF92400E),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Image.asset(figurePath, height: 80, fit: BoxFit.contain),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
              ],

              // زر تأكيد
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: newLevel.color,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                  ),
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text(
                    'رائع! 🚀',
                    style: GoogleFonts.ibmPlexSansArabic(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
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
