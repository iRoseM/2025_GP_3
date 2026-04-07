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
    nameAr: 'نبتة',
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
    nameAr: 'حارس البيئة',
    requiredXp: 500,
    icon: '🌍',
    color: Color(0xFF00796B),
  ),
  LevelModel(
    index: 4,
    id: 'champion',
    nameAr: 'بطل الاستدامة',
    requiredXp: 900,
    icon: '🏆',
    color: Color(0xFFF9A825),
  ),
];

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
    if (xp >= level.requiredXp) {
      current = level;
    }
  }
  return current;
}

// ====================================================
// المرحلة التالية (null إذا كان في القمة)
// ====================================================
LevelModel? getNextLevel(int xp) {
  for (int i = kLevels.length - 1; i >= 0; i--) {
    if (xp >= kLevels[i].requiredXp) {
      if (i + 1 < kLevels.length) return kLevels[i + 1];
      return null; // وصل القمة
    }
  }
  return kLevels[1];
}

// ====================================================
// نسبة التقدم للمرحلة الحالية (0.0 → 1.0)
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
// XP service - إضافة XP وتحديث المرحلة في Firestore
// ====================================================
class XpService {
  static final _db = FirebaseFirestore.instance;
  static final _auth = FirebaseAuth.instance;

  /// أضف XP بعد إكمال مهمة
  static Future<void> addXpForTask({required String taskLevelId}) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    final xpToAdd = getXpForTask(taskLevelId);
    final userRef = _db.collection('users').doc(uid);

    await _db.runTransaction((tx) async {
      final snap = await tx.get(userRef);
      final currentXp = (snap.data()?['xp'] ?? 0) as int;
      final newXp = currentXp + xpToAdd;
      final newLevel = getCurrentLevel(newXp);

      tx.update(userRef, {
        'xp': newXp,
        'currentLevel': newLevel.id,
      });
    });
  }

  /// اقرأ بيانات اليوزر (XP + مستواه)
  static Stream<DocumentSnapshot> userStream() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw Exception('User not logged in');
    return _db.collection('users').doc(uid).snapshots();
  }
}