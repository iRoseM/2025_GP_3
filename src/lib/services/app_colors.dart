import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class appColors {
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
  static const red = const Color.fromARGB(255, 220, 92, 83);
  static const orangeWarm = Color(0xFFE68A2E);
}

class slackMesseges {
  // static const red = Color(0xFFE60000);
  static const red = const Color.fromARGB(255, 220, 92, 83);
  static const primary = Color(0xFF4BAA98);
  static const sea = Color(0xFF1F7A8C);
}

/// 🎨 الثيم العام لتطبيق Nameer
class AppTheme {
  static ThemeData lightTheme = ThemeData(
    // ✅ اللون الأساسي والخلفية
    primaryColor: appColors.primary,
    scaffoldBackgroundColor: appColors.background,

    // // ✅ ألوان الأزرار
    // colorScheme: ColorScheme.fromSeed(
    //   seedColor: appColors.primary,
    //   primary: appColors.primary,
    //   secondary: appColors.accent,
    //   background: appColors.background,
    //   error: appColors.redDark,
    // ),

    // ✅ الخطوط (IBM Plex Sans Arabic)
    textTheme: GoogleFonts.ibmPlexSansArabicTextTheme().apply(
      bodyColor: appColors.dark,
      displayColor: appColors.dark,
    ),
    // // ✅ الأزرار
    // filledButtonTheme: FilledButtonThemeData(
    //   style: FilledButton.styleFrom(
    //     backgroundColor: appColors.primary,
    //     shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    //     padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
    //   ),
    // ),

    // ✅ مربعات النصوص (TextField)
    // inputDecorationTheme: InputDecorationTheme(
    //   filled: true,
    //   fillColor: Colors.white,
    //   hintStyle: TextStyle(color: appColors.dark.withOpacity(0.5)),
    //   border: OutlineInputBorder(
    //     borderRadius: BorderRadius.circular(12),
    //     borderSide: BorderSide(color: appColors.light.withOpacity(0.6)),
    //   ),
    //   focusedBorder: OutlineInputBorder(
    //     borderRadius: BorderRadius.circular(12),
    //     borderSide: const BorderSide(color: appColors.primary, width: 1.6),
    //   ),
    // ),
  );
}
