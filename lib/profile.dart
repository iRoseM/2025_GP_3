import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'home.dart'; // عشان تستفيد من AppColors لو تحب

class profilePage extends StatelessWidget {
  const profilePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      // عشان النصوص بالعربي تكون RTL
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            "الملف الشخصي",
            style: GoogleFonts.ibmPlexSansArabic(
              textStyle: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          backgroundColor: AppColors.primary,
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircleAvatar(
                radius: 50,
                backgroundColor: AppColors.primary,
                child: Icon(Icons.person, color: Colors.white, size: 50),
              ),
              const SizedBox(height: 20),
              Text(
                "مرحبا بك في ملفك الشخصي 👤",
                style: GoogleFonts.ibmPlexSansArabic(
                  textStyle: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: AppColors.dark,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
