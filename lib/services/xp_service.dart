import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

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
  final String figurePath;
  final String figureName;

  const LevelModel({
    required this.index,
    required this.id,
    required this.nameAr,
    required this.requiredXp,
    required this.icon,
    required this.color,
    required this.figurePath,
    required this.figureName,
  });
}

// ====================================================
// تعريف المراحل
// ====================================================
const List<LevelModel> kLevels = [
  LevelModel(
    index: 0,
    id: 'seedling',
    nameAr: 'بذرة',
    requiredXp: 0,
    icon: '🌱',
    color: Color(0xFF81C784),
    figurePath: 'assets/img/فيقر بذرة.png',
    figureName: 'كيس البذور',
  ),
  LevelModel(
    index: 1,
    id: 'sprout',
    nameAr: 'نبتة',
    requiredXp: 100,
    icon: '🌿',
    color: Color(0xFF4CAF50),
    figurePath: 'assets/img/فيقر نبتة.png',
    figureName: 'مرشة الماء',
  ),
  LevelModel(
    index: 2,
    id: 'tree',
    nameAr: 'شجرة',
    requiredXp: 250,
    icon: '🌳',
    color: Color(0xFF2E7D32),
    figurePath: 'assets/img/فيقر شجرة.png',
    figureName: 'شجرة الاستدامة',
  ),
  LevelModel(
    index: 3,
    id: 'guardian',
    nameAr: 'حارس البيئة',
    requiredXp: 500,
    icon: '🌍',
    color: Color(0xFF00796B),
    figurePath: 'assets/img/فيقر حارس.png',
    figureName: 'كأس حارس البيئة',
  ),
  LevelModel(
    index: 4,
    id: 'champion',
    nameAr: 'بطل الاستدامة',
    requiredXp: 900,
    icon: '🏆',
    color: Color(0xFFF9A825),
    figurePath: 'assets/img/فيقر بطل.png',
    figureName: 'بطل الاستدامة',
  ),
];

// ====================================================
// XP لكل مستوى مهمة
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
// احسب المرحلة الحالية من total XP
// ====================================================
LevelModel getCurrentLevel(int xp) {
  LevelModel current = kLevels.first;

  for (final level in kLevels) {
    if (xp >= level.requiredXp) {
      current = level;
    }
  }

  return current;
}

// ====================================================
// المرحلة التالية
// ====================================================
LevelModel? getNextLevelFromCurrent(LevelModel current) {
  final idx = kLevels.indexWhere(
    (l) => l.id == current.id,
  );

  if (idx == -1 || idx + 1 >= kLevels.length) {
    return null;
  }

  return kLevels[idx + 1];
}

// ====================================================
// نسبة التقدم داخل المرحلة الحالية
// ====================================================
double getLevelProgressFromZero(
  LevelModel current,
  int xpInLevel,
) {
  final next = getNextLevelFromCurrent(current);

  if (next == null) {
    return 1.0;
  }

  final xpNeeded =
      next.requiredXp - current.requiredXp;

  return (xpInLevel / xpNeeded)
      .clamp(0.0, 1.0);
}

// ====================================================
// XP المتبقي
// ====================================================
int xpRemainingForNext(
  LevelModel current,
  LevelModel next,
  int xpInLevel,
) {
  final xpNeeded =
      next.requiredXp - current.requiredXp;

  return (xpNeeded - xpInLevel)
      .clamp(0, xpNeeded);
}

// ====================================================
// XP Service
// ====================================================
class XpService {
  static final _db = FirebaseFirestore.instance;
  static final _auth = FirebaseAuth.instance;

  // ====================================================
  // إضافة XP بعد المهمة
  // ====================================================
  static Future<void> addXpForTask({
    required String taskLevelId,
  }) async {
    final uid = _auth.currentUser?.uid;

    if (uid == null) return;

    final xpToAdd = getXpForTask(taskLevelId);

    final userRef =
        _db.collection('users').doc(uid);

    String? leveledUpTo;

    await _db.runTransaction((tx) async {
      final snap = await tx.get(userRef);

      final data = snap.data() ?? {};

      final int currentXpInLevel =
          (data['xp'] ?? 0) as int;

      final String currentLevelId =
          (data['currentLevel'] ?? 'seedling')
              as String;

      final currentLevel = kLevels.firstWhere(
        (l) => l.id == currentLevelId,
        orElse: () => kLevels.first,
      );

      final nextLevel =
          getNextLevelFromCurrent(currentLevel);

      final int newXpInLevel =
          currentXpInLevel + xpToAdd;

      if (nextLevel != null) {
        final int xpNeeded =
            nextLevel.requiredXp -
                currentLevel.requiredXp;

        if (newXpInLevel >= xpNeeded) {
          leveledUpTo = nextLevel.id;

          tx.update(userRef, {
            'xp': 0,
            'currentLevel': nextLevel.id,
            'totalXp':
                FieldValue.increment(xpToAdd),
          });
        } else {
          tx.update(userRef, {
            'xp': newXpInLevel,
            'currentLevel': currentLevel.id,
            'totalXp':
                FieldValue.increment(xpToAdd),
          });
        }
      } else {
        // أعلى مرحلة
        tx.update(userRef, {
          'xp': newXpInLevel,
          'currentLevel': currentLevel.id,
          'totalXp':
              FieldValue.increment(xpToAdd),
        });
      }
    });

    // منح الفيقر بعد الترقية
    if (leveledUpTo != null) {
      await _grantFigure(
        uid: uid,
        levelId: leveledUpTo!,
      );
    }
  }

  // ====================================================
  // منح الفيقر
  // ====================================================
  static Future<void> _grantFigure({
    required String uid,
    required String levelId,
  }) async {
    final existing = await _db
        .collection('users')
        .doc(uid)
        .collection('figures')
        .where('levelId', isEqualTo: levelId)
        .limit(1)
        .get();

    if (existing.docs.isNotEmpty) {
      return;
    }

    final level = kLevels.firstWhere(
      (l) => l.id == levelId,
      orElse: () => kLevels.first,
    );

    await _db
        .collection('users')
        .doc(uid)
        .collection('figures')
        .add({
      'levelId': level.id,
      'name': level.figureName,
      'imagePath': level.figurePath,
      'earnedAt': FieldValue.serverTimestamp(),
    });

    print(
      '🎖️ تم منح الفيقر: ${level.figureName}',
    );
  }

  // ====================================================
  // مزامنة الفيقرز القديمة
  // ====================================================
  static Future<void> syncMissingFigures() async {
    final uid = _auth.currentUser?.uid;

    if (uid == null) return;

    final userDoc =
        await _db.collection('users').doc(uid).get();

    final data = userDoc.data() ?? {};

    final currentLevelId =
        data['currentLevel'] ?? 'seedling';

    final currentLevel = kLevels.firstWhere(
      (l) => l.id == currentLevelId,
      orElse: () => kLevels.first,
    );

    final unlockedLevels = kLevels.where(
      (l) => l.index <= currentLevel.index,
    );

    for (final level in unlockedLevels) {
      await _grantFigure(
        uid: uid,
        levelId: level.id,
      );
    }

    print('✅ تمت مزامنة الفيقرز');
  }

  // ====================================================
  // stream بيانات اليوزر
  // ====================================================
  static Stream<DocumentSnapshot> userStream() {
    final uid = _auth.currentUser?.uid;

    if (uid == null) {
      throw Exception('User not logged in');
    }

    return _db
        .collection('users')
        .doc(uid)
        .snapshots();
  }

  // ====================================================
  // stream الفيقرز
  // ====================================================
  static Stream<QuerySnapshot> figuresStream() {
    final uid = _auth.currentUser?.uid;

    if (uid == null) {
      throw Exception('User not logged in');
    }

    return _db
        .collection('users')
        .doc(uid)
        .collection('figures')
        .orderBy(
          'earnedAt',
          descending: false,
        )
        .snapshots();
  }
}