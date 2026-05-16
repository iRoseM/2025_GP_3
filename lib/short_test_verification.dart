import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'task.dart';
import 'services/title_header.dart';
import 'services/background_container.dart';
import '../services/app_colors.dart';
import 'dart:async';
import 'home.dart';

class ShortTestVerificationPage extends StatefulWidget {
  final String userTaskDocId;
  final Map<String, dynamic> quiz;

  const ShortTestVerificationPage({
    super.key,
    required this.userTaskDocId,
    required this.quiz,
  });

  @override
  State<ShortTestVerificationPage> createState() =>
      _ShortTestVerificationPageState();
}

class _ShortTestVerificationPageState extends State<ShortTestVerificationPage> {
  String? selected;
  bool sending = false;

  @override
  Widget build(BuildContext context) {
    final question = widget.quiz['question'];
    final List options = widget.quiz['options'];

    final statusBar = MediaQuery.of(context).padding.top;
    final topPadding = statusBar + 20;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: appColors.background,
        appBar: const NameerAppBar(showBack: true, showTitleInBar: false),
        body: Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            (topPadding - 55).clamp(0, double.infinity),
            16,
            16,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "التحقق عبر اختبار قصير",
                style: GoogleFonts.ibmPlexSansArabic(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: appColors.dark,
                ),
              ),
              const SizedBox(height: 24),

              Text(
                question,
                style: GoogleFonts.ibmPlexSansArabic(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: appColors.primary,
                ),
              ),

              const SizedBox(height: 25),

              // 🟩 الخيارات
              ...options.map((opt) {
                final bool isSelected = selected == opt;

                return GestureDetector(
                  onTap: () {
                    setState(() => selected = opt);
                  },
                  child: Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.symmetric(
                      vertical: 14,
                      horizontal: 16,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: appColors.primary.withOpacity(0.3),
                        width: 1.5,
                      ),
                      gradient: isSelected
                          ? const LinearGradient(
                              colors: [
                                appColors.mint,
                                appColors.tealSoft,
                                appColors.primary,
                              ],
                              begin: Alignment.centerRight,
                              end: Alignment.centerLeft,
                            )
                          : null,
                      color: isSelected ? null : Colors.white,
                    ),
                    child: Text(
                      opt,
                      style: GoogleFonts.ibmPlexSansArabic(
                        fontSize: 16,
                        color: isSelected ? Colors.white : appColors.dark,
                      ),
                    ),
                  ),
                );
              }).toList(),

              const Spacer(),

              // 🟧 زر تأكيد الإجابة
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: selected == null || sending ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    elevation: 0,
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    padding: EdgeInsets.zero,
                  ),
                  child: Ink(
                    decoration: BoxDecoration(
                      gradient: selected == null
                          ? null
                          : const LinearGradient(
                              colors: [appColors.primary, appColors.tealSoft],
                              begin: Alignment.centerRight,
                              end: Alignment.centerLeft,
                            ),
                      color: selected == null ? Colors.grey.shade300 : null,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Container(
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: sending
                          ? const SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              "تأكيد الإجابة",
                              style: GoogleFonts.ibmPlexSansArabic(
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                                color: selected == null
                                    ? appColors.dark
                                    : Colors.white,
                              ),
                            ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ✅ بوب-اب عند الإجابة الصحيحة
  Future<void> _showSuccessPopup() async {
    if (!mounted) return;

    await showDialog(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (dialogContext) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          insetPadding: const EdgeInsets.symmetric(horizontal: 24),
          child: SizedBox(
            width: 340,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset(
                    'assets/img/nameerHappy.png',
                    height: 120,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '!إجابة صحيحة',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.ibmPlexSansArabic(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: appColors.dark,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    "عمل رائع! قراءة المقال ساهمت في إثراء معرفتك.",
                    textAlign: TextAlign.center,
                    style: GoogleFonts.ibmPlexSansArabic(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: appColors.dark,
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: 140,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: appColors.primary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 10,
                        ),
                      ),
                      onPressed: () => Navigator.of(dialogContext).pop(true),
                      child: Text(
                        'تم',
                        style: GoogleFonts.ibmPlexSansArabic(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _submit() async {
    setState(() => sending = true);

    // 🔍 حوّل الكل لستـرنج + قص المسافات
    final correct = (widget.quiz['answer'] ?? '').toString().trim();
    final selectedValue = (selected ?? '').toString().trim();

    final bool isCorrect = selectedValue == correct;

    if (!isCorrect) {
      setState(() => sending = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "إجابة خاطئة — يرجى إعادة قراءة المقال ثم المحاولة مرة أخرى",
            style: GoogleFonts.ibmPlexSansArabic(color: Colors.white),
          ),
          backgroundColor: slackMesseges.red,
        ),
      );

      Navigator.pop(context); // رجوع لصفحة المقال
      return;
    }
    try {
      final docRef = FirebaseFirestore.instance
          .collection("userTasks")
          .doc(widget.userTaskDocId);

      // 🟢 جلب بيانات المهمة لأخذ taskPoints من قاعدة البيانات
      // For perrfoemance, we add a timeout here in case the network is bad, so we don't wait indefinitely.
      // If it times out, we throw an error that will be caught in the catch block below, and show a generic error message to the user.
      final taskSnap = await docRef.get().timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw TimeoutException('انتهت مهلة جلب بيانات المهمة'),
      );
      final int taskPoints = taskSnap.data()?['taskPoints'] ?? 0;

      // 🟢 تحديث مهمة المستخدم
      await docRef
          .update({
            "taskValidation": "التحقق عبر اجراء اختبار قصير",
            "status": "completed",
            "completedAt": FieldValue.serverTimestamp(),
          })
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () => throw TimeoutException('انتهت مهلة تحديث المهمة'),
          );

      // 🟢 تحديث بيانات المستخدم
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final userRef = FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid);

        await userRef.update({
          'completedTask': FieldValue.increment(1),
          'points': FieldValue.increment(taskPoints),
          'xp': FieldValue.increment(taskPoints), // ← أضيفي هذا
          'lastCompletedTaskType': "quiz",
          'lastQuizAnswer': selected,
        });
        try {
          final uid = user.uid;
          final today = DateTime.now();
          final dayKey =
              '${today.year.toString().padLeft(4, '0')}${today.month.toString().padLeft(2, '0')}${today.day.toString().padLeft(2, '0')}';

          // معرفة كم مهمة مطلوبة حسب الـ XP الجديد
          final updatedDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(uid)
              .get();
          final newXp = (updatedDoc.data()?['xp'] ?? 0) as int;

          int requiredTasks = 1;
          if (newXp >= 900) requiredTasks = 4;
          else if (newXp >= 500) requiredTasks = 3;
          else if (newXp >= 100) requiredTasks = 2;

          // عد المهام المكتملة اليوم
          int completedToday = 0;

          final mainSnap = await FirebaseFirestore.instance
              .collection('userTasks')
              .doc('${uid}_$dayKey')
              .get();
          if (mainSnap.exists && mainSnap.data()?['status'] == 'completed') {
            completedToday++;
          }

          for (int i = 2; i <= requiredTasks; i++) {
            final snap = await FirebaseFirestore.instance
                .collection('userTasks')
                .doc('${uid}_${dayKey}_task$i')
                .get();
            if (snap.exists && snap.data()?['status'] == 'completed') {
              completedToday++;
            }
          }

          // ✅ نحدث الستريك بس لو اكتملت كل المهام
          if (completedToday >= requiredTasks) {
            await StreakService.updateStreakOnTaskCompletion();
          }
        } catch (_) {}
      }

      // 🎉 بوب-اب
      await _showSuccessPopup();

      Navigator.pop(context);
      Navigator.pop(context);
    } on TimeoutException {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "انتهت مهلة الاتصال. يرجى التحقق من الاتصال ثم المحاولة مرة أخرى.",
            style: GoogleFonts.ibmPlexSansArabic(color: Colors.white),
          ),
          backgroundColor: slackMesseges.red,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "حدث خطأ غير متوقع. يرجى المحاولة مرة أخرى.",
            style: GoogleFonts.ibmPlexSansArabic(color: Colors.white),
          ),
          backgroundColor: slackMesseges.red,
        ),
      );
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }
}
