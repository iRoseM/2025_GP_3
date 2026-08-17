import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/app_colors.dart';

// Changes in connection.dart:
// - Converted showNoInternetDialog to use a StatefulWidget (_NoInternetDialog) to support automatic retry logic.
// - Added a 5-second countdown timer that automatically checks internet connectivity when it reaches zero.
// - If the connection is restored, the dialog closes itself automatically.
// - If still offline, the countdown resets and retries again.
// - Added a manual "Retry Now" button so the user doesn't have to wait.
// - No changes needed in other files — they all call the same showNoInternetDialog().

Future<bool> hasInternetConnection() async {
  try {
    final result = await InternetAddress.lookup('google.com');
    return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
  } on SocketException {
    return false;
  }
}

void showNoInternetDialog(BuildContext context) {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) => const _NoInternetDialog(),
  );
}

class _NoInternetDialog extends StatefulWidget {
  const _NoInternetDialog();

  @override
  State<_NoInternetDialog> createState() => _NoInternetDialogState();
}

class _NoInternetDialogState extends State<_NoInternetDialog> {
  Timer? _retryTimer;
  int _secondsLeft = 5;
  bool _isChecking = false;

  @override
  void initState() {
    super.initState();
    _startRetryCountdown();
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    super.dispose();
  }

  void _startRetryCountdown() {
    _secondsLeft = 5;
    _retryTimer?.cancel();
    _retryTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }

      setState(() => _secondsLeft--);

      if (_secondsLeft <= 0) {
        timer.cancel();
        await _checkConnection();
      }
    });
  }

  Future<void> _checkConnection() async {
    if (!mounted) return;
    setState(() => _isChecking = true);

    final hasNet = await hasInternetConnection();

    if (!mounted) return;

    if (hasNet) {
      // ✅ عاد الإنترنت — أغلق الـ dialog
      Navigator.of(context).pop();
    } else {
      // ❌ لسا مقطوع — أعد العد التنازلي
      setState(() => _isChecking = false);
      _startRetryCountdown();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/img/nameerThink.png',
              height: 120,
              fit: BoxFit.contain,
            ),
            const SizedBox(height: 16),

            Text(
              'تعذّر الاتصال بالإنترنت',
              textAlign: TextAlign.center,
              style: GoogleFonts.ibmPlexSansArabic(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: appColors.dark,
              ),
            ),
            const SizedBox(height: 8),

            Text(
              'يرجى التحقق من اتصال الشبكة.',
              textAlign: TextAlign.center,
              style: GoogleFonts.ibmPlexSansArabic(
                fontSize: 15,
                color: appColors.dark.withOpacity(0.7),
              ),
            ),
            const SizedBox(height: 16),

            // مؤشر الحالة
            _isChecking
                ? const CircularProgressIndicator(
                    color: appColors.primary,
                    strokeWidth: 3,
                  )
                : Column(
                    children: [
                      const CircularProgressIndicator(
                        color: appColors.primary,
                        strokeWidth: 3,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'إعادة المحاولة خلال $_secondsLeft ثوانٍ...',
                        style: GoogleFonts.ibmPlexSansArabic(
                          fontSize: 13,
                          color: appColors.dark.withOpacity(0.5),
                        ),
                      ),
                    ],
                  ),

            const SizedBox(height: 12),

            // زر إعادة المحاولة الفورية
            TextButton(
              onPressed: _isChecking
                  ? null
                  : () {
                      _retryTimer?.cancel();
                      _checkConnection();
                    },
              child: Text(
                'إعادة المحاولة الآن',
                style: GoogleFonts.ibmPlexSansArabic(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: _isChecking
                      ? appColors.primary.withOpacity(0.4)
                      : appColors.primary,
                ),
              ),
            ),

            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }
}