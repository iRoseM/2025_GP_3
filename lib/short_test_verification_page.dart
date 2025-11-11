import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'task.dart'; // يحتوي على AppColors

class ShortTestVerificationPage extends StatefulWidget {
  final String articleId;
  const ShortTestVerificationPage({super.key, required this.articleId});

  @override
  State<ShortTestVerificationPage> createState() =>
      _ShortTestVerificationPageState();
}

class _ShortTestVerificationPageState extends State<ShortTestVerificationPage> {
  Map<String, dynamic>? _testData;
  bool _loading = true;
  String? _selectedOption;

  @override
  void initState() {
    super.initState();
    _loadTest();
  }

  Future<void> _loadTest() async {
    final doc = await FirebaseFirestore.instance
        .collection('articles')
        .doc(widget.articleId)
        .get();
    if (doc.exists && doc.data()?['shortTestVerification'] != null) {
      setState(() {
        _testData =
            Map<String, dynamic>.from(doc.data()!['shortTestVerification']);
        _loading = false;
      });
    } else {
      setState(() => _loading = false);
    }
  }

  void _checkAnswer(String selected) {
    final correct = _testData?['answer'];
    final isCorrect = selected == correct;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          isCorrect ? 'إجابة صحيحة 🎯' : 'إجابة خاطئة ❌',
          style: GoogleFonts.ibmPlexSansArabic(color: Colors.white),
        ),
        backgroundColor: isCorrect ? Colors.green : Colors.red,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.primary,
          title: Text(
            "التحقق عبر اختبار قصير",
            style: GoogleFonts.ibmPlexSansArabic(
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          centerTitle: true,
        ),
        body: _loading
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              )
            : _testData == null
                ? Center(
                    child: Text(
                      "لم يتم العثور على اختبار لهذا المقال.",
                      style: GoogleFonts.ibmPlexSansArabic(
                        fontSize: 16,
                        color: AppColors.dark,
                      ),
                    ),
                  )
                : Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _testData?['question'] ?? '',
                          style: GoogleFonts.ibmPlexSansArabic(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 25),
                        ...List.generate(
                          (_testData?['options'] ?? []).length,
                          (i) {
                            final option =
                                _testData?['options'][i] ?? 'خيار';
                            final isSelected = _selectedOption == option;

                            return Padding(
                              padding: const EdgeInsets.only(bottom: 14),
                              child: GestureDetector(
                                onTap: () {
                                  setState(() => _selectedOption = option);
                                  _checkAnswer(option);
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 14, horizontal: 18),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                                    gradient: isSelected
                                        ? const LinearGradient(
                                            colors: [
                                              AppColors.mint,
                                              AppColors.tealSoft,
                                              AppColors.primary,
                                            ],
                                            begin: Alignment.topLeft,
                                            end: Alignment.bottomRight,
                                          )
                                        : null,
                                    border: Border.all(
                                      color: AppColors.primary.withOpacity(0.3),
                                      width: 1.5,
                                    ),
                                  ),
                                  child: Text(
                                    option,
                                    style: GoogleFonts.ibmPlexSansArabic(
                                      fontSize: 16,
                                      color: isSelected
                                          ? Colors.white
                                          : AppColors.dark,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
      ),
    );
  }
}
