import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'services/title_header.dart';
import 'services/background_container.dart';
import 'short_test_verification_page.dart';
import 'package:cloud_functions/cloud_functions.dart';

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
}

class ArticlePage extends StatefulWidget {
  final String userTaskDocId;
  final String? taskId;

  const ArticlePage({super.key, required this.userTaskDocId, this.taskId});

  @override
  State<ArticlePage> createState() => _ArticlePageState();
}

class _ArticlePageState extends State<ArticlePage> {
  Map<String, dynamic>? _article;
  bool _loading = true;
  bool _error = false;
  bool _showReadButton = false;
  bool _generatingTest = false;

  @override
  void initState() {
    super.initState();
    _loadStoredArticle();
  }

  // ======================================================
  // 🔥 قراءة المقال من userTasks فقط (بدون API)
  // ======================================================
  Future<void> _loadStoredArticle() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('User not logged in');

      final userTaskRef = FirebaseFirestore.instance
          .collection('userTasks')
          .doc(widget.userTaskDocId);

      final snap = await userTaskRef.get();
      final data = snap.data() ?? {};

      if (data['taskType'] == 'news') {
        setState(() {
          _article = {
            'title': data['articleTitle'] ?? '',
            'content': data['articleContent'] ?? '',
            'urlToImage': data['articleImage'] ?? '',
            'sourceName': data['articleSource'] ?? '',
            'url': data['articleUrl'] ?? '',
            'publishedAt': data['articlePublishedAt'] ?? '',
          };
          _loading = false;
        });
        return;
      }

      // fallback
      setState(() {
        _error = true;
        _loading = false;
      });

    } catch (e) {
      debugPrint("❌ Article load error: $e");
      setState(() {
        _error = true;
        _loading = false;
      });
    }
  }

  // ======================================================
  // 🔥 إنشاء اختبار قصير من الـ Cloud Function
  // ======================================================
  Future<void> _startShortTest() async {
    final content = (_article?['content'] ?? '').toString();

    if (content.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "لا يمكن إنشاء اختبار قصير لأن نص المقال غير متوفر.",
            style: GoogleFonts.ibmPlexSansArabic(color: Colors.white),
          ),
          backgroundColor: AppColors.accent,
        ),
      );
      return;
    }

    setState(() => _generatingTest = true);

    try {
      final callable = FirebaseFunctions.instance.httpsCallable(
        'generateShortTestVerification',
      );

      final result = await callable.call({
        'articleText': content,
        'apiType': 'gemini',
      });

      Map data;
      if (result.data is Map) {
        data = result.data as Map;
      } else {
        // clean json string
        String raw = result.data.toString();
        raw = raw.replaceAll("```json", "").replaceAll("```", "").trim();
        raw = raw.substring(raw.indexOf("{"), raw.lastIndexOf("}") + 1);
        data = jsonDecode(raw);
      }

      final quiz = {
        'question': data['question'] ?? '',
        'options': List<String>.from(data['options'] ?? const []),
        'answer': data['answer'] ?? '',
      };

      setState(() => _generatingTest = false);

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ShortTestVerificationPage(
            userTaskDocId: widget.userTaskDocId,
            quiz: quiz,
          ),
        ),
      );

    } catch (e) {
      debugPrint("❌ generateShortTestVerification error: $e");
      setState(() => _generatingTest = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "حدث خطأ أثناء إنشاء الاختبار القصير.",
            style: GoogleFonts.ibmPlexSansArabic(color: Colors.white),
          ),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  // ======================================================
  // UI
  // ======================================================
  @override
  Widget build(BuildContext context) {
    final statusBar = MediaQuery.of(context).padding.top;
    final topPadding = statusBar + 20;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        extendBodyBehindAppBar: true,
        backgroundColor: Colors.transparent,
        appBar: const NameerAppBar(
          showBack: true,
          showTitleInBar: false,
        ),
        body: AnimatedBackgroundContainer(
          child: (_loading)
              ? const Center(
                  child: CircularProgressIndicator(color: AppColors.primary),
                )
              : _error
                  ? Center(
                      child: Text(
                        "لا يمكن تحميل المقال.",
                        style: GoogleFonts.ibmPlexSansArabic(
                          color: AppColors.dark,
                          fontSize: 16,
                        ),
                      ),
                    )
                  : Padding(
                      padding: EdgeInsets.fromLTRB(16, topPadding - 55, 16, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "مقال اليوم",
                            style: GoogleFonts.ibmPlexSansArabic(
                              fontSize: 24,
                              fontWeight: FontWeight.w700,
                              color: AppColors.dark,
                            ),
                          ),
                          const SizedBox(height: 16),

                          Expanded(child: _buildBodyWithRevealButton()),
                        ],
                      ),
                    ),
        ),
      ),
    );
  }

  Widget _buildBodyWithRevealButton() {
    final a = _article!;

    return NotificationListener<ScrollNotification>(
      onNotification: (scroll) {
        final atEnd =
            scroll.metrics.pixels >= scroll.metrics.maxScrollExtent - 60;

        if (atEnd && !_showReadButton) {
          setState(() => _showReadButton = true);
        }
        return false;
      },
      child: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.only(top: 16, bottom: 120),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if ((a['urlToImage'] ?? '').toString().isNotEmpty)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: Image.network(a['urlToImage'], fit: BoxFit.cover),
                  ),

                const SizedBox(height: 20),

                Text(
                  a['title'] ?? '',
                  style: GoogleFonts.ibmPlexSansArabic(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary,
                  ),
                ),

                const SizedBox(height: 20),

                Text(
                  a['content'] ?? '',
                  style: GoogleFonts.ibmPlexSansArabic(
                    fontSize: 15,
                    height: 1.7,
                    color: Colors.black87,
                  ),
                ),

                const SizedBox(height: 24),

                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    "المصدر: ${a['sourceName'] ?? ''}",
                    style: GoogleFonts.ibmPlexSansArabic(
                      fontSize: 13,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ),
              ],
            ),
          ),

          if (_showReadButton)
            Positioned(
              left: 16,
              right: 16,
              bottom: 20,
              child: ElevatedButton(
                onPressed: _generatingTest ? null : _startShortTest,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 0,
                  backgroundColor: Colors.transparent,
                ),
                child: Ink(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    gradient: const LinearGradient(
                      colors: [
                        AppColors.primary,
                        AppColors.tealSoft,
                      ],
                      begin: Alignment.centerRight,
                      end: Alignment.centerLeft,
                    ),
                  ),
                  child: Container(
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: _generatingTest
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            "تمت القراءة - ابدأ الاختبار القصير",
                            style: GoogleFonts.ibmPlexSansArabic(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                              color: Colors.white,
                            ),
                          ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
