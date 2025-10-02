import 'package:flutter/material.dart';

class communityPage extends StatelessWidget {
  const communityPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("الأصدقاء"),
        backgroundColor: const Color(0xFF4BAA98), // نفس لون الهوية
      ),
      body: const Center(
        child: Text(
          "هنا صفحة الأصدقاء 👥",
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: Color(0xFF3C3C3B),
          ),
        ),
      ),
    );
  }
}
