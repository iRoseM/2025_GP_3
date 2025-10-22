import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../home.dart'; // صفحة الهوم (عندك: homePage)
import '../onboarding.dart'; // شاشة الـ Onboarding
import '../main.dart'; // يحتوي RegisterPage عندك

class LaunchDecider extends StatefulWidget {
  const LaunchDecider({super.key});

  @override
  State<LaunchDecider> createState() => _LaunchDeciderState();
}

class _LaunchDeciderState extends State<LaunchDecider> {
  @override
  void initState() {
    super.initState();
    _decide();
  }

  Future<void> _decide() async {
    final prefs = await SharedPreferences.getInstance();
    final seenOnboarding = prefs.getBool('seen_onboarding') ?? false;
    final user = FirebaseAuth.instance.currentUser;

    // مهلة خفيفة اختيارية
    await Future.delayed(const Duration(milliseconds: 250));

    if (!mounted) return;

    if (user != null) {
      // ✅ مسجل دخول → الهوم
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const homePage()),
      );
    } else if (seenOnboarding) {
      // ✅ شاف الـ Onboarding قبل → صفحة التسجيل/الدخول
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const RegisterPage()),
      );
    } else {
      // ✅ أول مرة → Onboarding
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const OnboardingScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // شاشة انتظار بسيطة أثناء القرار
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
