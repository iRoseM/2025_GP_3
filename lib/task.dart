import 'package:flutter/material.dart';

class taskPage extends StatelessWidget {
  const taskPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("مهامي"),
        backgroundColor: const Color(0xFF4BAA98), // لون من الهوية
      ),
      body: const Center(
        child: Text(
          "هنا صفحة المهام 📝",
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
