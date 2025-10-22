import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../main.dart'; // للوصول إلى AppColors مثلاً

/// ✅ دالة فحص الاتصال بالإنترنت
Future<bool> hasInternetConnection() async {
  try {
    final result = await InternetAddress.lookup('google.com');
    return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
  } on SocketException {
    return false;
  }
}

/// ✅ دالة عرض الـ Popup عند انقطاع الاتصال
void showNoInternetDialog(BuildContext context) {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) {
      return Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ✅ الصورة العلوية
              Image.asset(
                'assets/img/nameerThink.png',
                height: 120,
                fit: BoxFit.contain,
              ),
              const SizedBox(height: 16),

              // ✅ النص
              Text(
                'تعذّر الاتصال بالإنترنت',
                textAlign: TextAlign.center,
                style: GoogleFonts.ibmPlexSansArabic(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.dark,
                ),
              ),
              const SizedBox(height: 8),

              // ✅ النص الفرعي
              Text(
                'يرجى التحقق من اتصال الشبكة والمحاولة مرة أخرى.',
                textAlign: TextAlign.center,
                style: GoogleFonts.ibmPlexSansArabic(
                  fontSize: 15,
                  color: AppColors.dark.withOpacity(0.7),
                ),
              ),
              const SizedBox(height: 16),

              // ✅ مؤشّر تحميل فقط (بدون أزرار)
              const CircularProgressIndicator(
                color: AppColors.primary,
                strokeWidth: 3,
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
    },
  );
}
