import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../home.dart'; // واجهة المستخدم العادي
import '../admin_home.dart'; // واجهة الأدمن
import '../onboarding.dart'; // شاشة Onboarding
import '../main.dart'; // تحتوي RegisterPage و VerifyEmailPage

enum _Target { onboarding, register, verifyEmail, adminHome, userHome }

class LaunchDecider extends StatefulWidget {
  const LaunchDecider({super.key});
  @override
  State<LaunchDecider> createState() => _LaunchDeciderState();
}

class _LaunchDeciderState extends State<LaunchDecider> {
  StreamSubscription<User?>? _authSub;
  _Target? _lastTarget; // ✅ بدل _navigated

  @override
  void initState() {
    super.initState();

    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) async {
      if (!mounted) return;

      try {
        if (user == null) {
          final seen = await _seenOnboarding();
          _go(seen ? _Target.register : _Target.onboarding);
          return;
        }

        await user.reload();
        if (!user.emailVerified) {
          _go(_Target.verifyEmail);
          return;
        }

        final role = await _getUserRole(user.uid);
        _go(role == 'admin' ? _Target.adminHome : _Target.userHome);
      } catch (_) {
        _go(_Target.userHome);
      }
    });
  }

  Future<bool> _seenOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('seen_onboarding') ?? false;
  }

  Future<String> _getUserRole(String uid) async {
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();
    final data = doc.data();
    return (data?['role'] ?? 'regular').toString().toLowerCase();
  }

  void _go(_Target t) {
    if (!mounted) return;
    if (_lastTarget == t) return; // ✅ لا تكرّر نفس الوجهة
    _lastTarget = t;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      final email = FirebaseAuth.instance.currentUser?.email ?? '';
      final page = switch (t) {
        _Target.onboarding => const OnboardingScreen(),
        _Target.register => const RegisterPage(),
        _Target.verifyEmail => VerifyEmailPage(email: email),
        _Target.adminHome => const AdminHomePage(),
        _Target.userHome => const homePage(),
      };

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
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
