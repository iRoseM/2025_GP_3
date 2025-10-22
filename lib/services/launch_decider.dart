import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../home.dart'; // واجهة المستخدم العادي
import '../admin_home.dart'; // واجهة الأدمن
import '../onboarding.dart'; // شاشة Onboarding
import '../main.dart'; // تحتوي RegisterPage

enum _Target { splash, onboarding, register, adminHome, userHome }

class LaunchDecider extends StatefulWidget {
  const LaunchDecider({super.key});
  @override
  State<LaunchDecider> createState() => _LaunchDeciderState();
}

class _LaunchDeciderState extends State<LaunchDecider> {
  StreamSubscription<User?>? _authSub;
  bool _navigated = false; // يمنع التوجيه المتكرر

  @override
  void initState() {
    super.initState();
    // نبدأ بسبلاش، وبعدين نسمع التغيّرات ونقرّر
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) async {
      // لو الصفحة اتقفلت
      if (!mounted) return;

      try {
        if (user == null) {
          // مو مسجّل دخول → قرر بين Onboarding و Register
          final seen = await _seenOnboarding();
          _go(seen ? _Target.register : _Target.onboarding);
        } else {
          // مسجّل دخول → جيب الدور وقرر الصفحة
          final role = await _getUserRole(user.uid);
          _go(role == 'admin' ? _Target.adminHome : _Target.userHome);
        }
      } catch (e) {
        // أي خطأ في القرار → رجّع لواجهة اليوزر (أأمن خيار) بدون شاشة خطأ
        _go(_Target.userHome);
      }
    });
  }

  Future<bool> _seenOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('seen_onboarding') ?? false;
    // ملاحظة: لو ودك تمنع الومضة أكثر، تقدّر تحفظ هذا في الذاكرة مبكرًا.
  }

  Future<String> _getUserRole(String uid) async {
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();
    final data = doc.data();
    return (data?['role'] ?? 'regular')
        .toString()
        .toLowerCase(); // "admin" أو "regular"
  }

  void _go(_Target t) {
    if (!mounted || _navigated) return;
    _navigated = true;

    // نؤجّل التوجيه لما بعد هذا الفريم لمنع أي بناء متداخل/ومضات
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Widget page;
      switch (t) {
        case _Target.onboarding:
          page = const OnboardingScreen();
          break;
        case _Target.register:
          page = const RegisterPage();
          break;
        case _Target.adminHome:
          page = const AdminHomePage();
          break;
        case _Target.userHome:
        default:
          page = const homePage();
          break;
      }

      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => page));
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // دايمًا سبلاش إلى أن نقرّر ونتنقّل (بدون أي بناء لصفحات الهدف هنا)
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
