import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../home.dart';
import '../admin_home.dart';
import '../onboarding.dart'; 
import '../main.dart'; 

enum _Target { onboarding, register, verifyEmail, adminHome, userHome, maintenance }

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
        // ✅ I-42: تحقق من الصيانة أول شي — قبل أي توجيه
        final isMaintenance = await _checkMaintenance();
        if (isMaintenance) return;

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
              _Target.maintenance => const MaintenancePage(),
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
  Future<bool> _checkMaintenance() async {
  try {
    final doc = await FirebaseFirestore.instance
        .collection('config')
        .doc('maintenance')
        .get();

    if (!doc.exists) return false;

    final data = doc.data();
    final isActive = data?['isActive'] == true;
    if (!isActive) return false;

if (!mounted) return true;
    _go(_Target.maintenance);
    return true;
    
  } catch (_) {
    return false; // لو فيه خطأ في جلب البيانات نكمل طبيعي
  }
}
}
class MaintenancePage extends StatelessWidget {
  const MaintenancePage({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('config')
          .doc('maintenance')
          .snapshots(),
      builder: (context, snap) {
        final data = snap.data?.data() as Map<String, dynamic>?;
        final isActive = data?['isActive'] == true;

        // لو انتهت الصيانة → أعد التشغيل
        if (!isActive && snap.hasData) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => const LaunchDecider()),
            );
          });
        }

        final message = (data?['message'] ?? 'التطبيق تحت الصيانة حالياً').toString();
        final expectedEnd = (data?['expectedEnd'] ?? 'قريباً').toString();

        return Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            backgroundColor: Colors.white,
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Image.asset('assets/img/nameerThink.png', height: 160),
                    const SizedBox(height: 24),
                    const Text(
                      'التطبيق تحت الصيانة 🔧',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: Colors.black87,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      message,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 15, color: Colors.grey[700]),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'الوقت المتوقع للعودة: $expectedEnd',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: Colors.grey[500]),
                    ),
                    const SizedBox(height: 32),
                    const CircularProgressIndicator(color: Color(0xFF4BAA98)),
                    const SizedBox(height: 12),
                    Text(
                      'سيتم تحديث الصفحة تلقائياً عند انتهاء الصيانة',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: Colors.grey[400]),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
