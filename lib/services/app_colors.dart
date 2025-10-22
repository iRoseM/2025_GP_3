import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// 🌿 ألوان الهوية البصرية لتطبيق Nameer
class AppColors {
  static const primary = Color(0xFF4BAA98);
  static const dark = Color(0xFF3C3C3B);
  static const accent = Color(0xFFF4A340);
  static const sea = Color(0xFF1F7A8C);
  static const primary60 = Color(0x994BAA98);
  static const primary33 = Color(0x544BAA98);
  static const light = Color(0xFF79D0BE);
  static const background = Color(0xFFF3FAF7);
  static const mint = Color(0xFFB6E9C1);
  static const tealSoft = Color(0xFF75BCAF);

  // ❤️ أحمر للتحذيرات والأخطاء
  static const redDark = Color.fromARGB(255, 139, 16, 16);

  // 💚 أخضر للنجاح أو الإشعارات الإيجابية
  static const success = Color(0xFF66BB6A);
  static const successLight = Color(0xFFA5D6A7);
}

/// 🎨 الثيم العام لتطبيق Nameer
class AppTheme {
  static ThemeData lightTheme = ThemeData(
    // ✅ اللون الأساسي والخلفية
    primaryColor: AppColors.primary,
    scaffoldBackgroundColor: AppColors.background,

    // // ✅ ألوان الأزرار
    // colorScheme: ColorScheme.fromSeed(
    //   seedColor: AppColors.primary,
    //   primary: AppColors.primary,
    //   secondary: AppColors.accent,
    //   background: AppColors.background,
    //   error: AppColors.redDark,
    // ),

    // ✅ الخطوط (IBM Plex Sans Arabic)
    textTheme: GoogleFonts.ibmPlexSansArabicTextTheme().apply(
      bodyColor: AppColors.dark,
      displayColor: AppColors.dark,
    ),

    // ✅ إعداد شريط التطبيق AppBar
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      iconTheme: IconThemeData(color: AppColors.dark),
      titleTextStyle: TextStyle(
        color: AppColors.dark,
        fontSize: 20,
        fontWeight: FontWeight.bold,
      ),
    ),

    // // ✅ الأزرار
    // filledButtonTheme: FilledButtonThemeData(
    //   style: FilledButton.styleFrom(
    //     backgroundColor: AppColors.primary,
    //     shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    //     padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
    //   ),
    // ),

    // ✅ مربعات النصوص (TextField)
    // inputDecorationTheme: InputDecorationTheme(
    //   filled: true,
    //   fillColor: Colors.white,
    //   hintStyle: TextStyle(color: AppColors.dark.withOpacity(0.5)),
    //   border: OutlineInputBorder(
    //     borderRadius: BorderRadius.circular(12),
    //     borderSide: BorderSide(color: AppColors.light.withOpacity(0.6)),
    //   ),
    //   focusedBorder: OutlineInputBorder(
    //     borderRadius: BorderRadius.circular(12),
    //     borderSide: const BorderSide(color: AppColors.primary, width: 1.6),
    //   ),
    // ),
  );
}
