import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'services/title_header.dart';
import 'services/background_container.dart';
import 'short_test_verification.dart';

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

  // 📚 إعدادات حجم الخط (نستخدمها مع الـ Slider)
  double _fontScale = 1.0; // بين 0.8 و 1.3 تقريباً

  double get _bodyFontSize => 15 * _fontScale;
  double get _titleFontSize => 22 * _fontScale;

  // 🔊 TTS
  late FlutterTts _tts;
  bool _isSpeaking = false;
  bool _ttsReady = false;

  @override
  void initState() {
    super.initState();
    _initTts();
    _loadStoredArticle();
  }

  Future<void> _initTts() async {
    _tts = FlutterTts();

    try {
      // نفعّل الانتظار إلى أن يخلص speak
      await _tts.awaitSpeakCompletion(true);

      // نحاول نختار صوت سعودي/عربي مدعوم على الجهاز
      final voices = await _tts.getVoices;
      String? selectedLanguage;

      if (voices is List) {
        // نحاول نلقى ar-SA أولاً
        final saVoice = voices.firstWhere(
          (v) =>
              (v is Map &&
                  ((v['locale'] ?? '').toString().toLowerCase() == 'ar-sa' ||
                      (v['name'] ?? '').toString().toLowerCase().contains(
                        'saudi',
                      ))) ||
              (v is Map &&
                  (v['locale'] ?? '').toString().toLowerCase().contains(
                    'ar_sa',
                  )),
          orElse: () => null,
        );

        if (saVoice != null && saVoice is Map) {
          selectedLanguage = (saVoice['locale'] ?? 'ar-SA')
              .toString(); // لو لقينا صوت سعودي
        } else {
          // لو ما لقينا سعودي، نحاول أي عربي
          final anyArabic = voices.firstWhere(
            (v) =>
                v is Map &&
                (v['locale'] ?? '').toString().toLowerCase().startsWith('ar'),
            orElse: () => null,
          );
          if (anyArabic != null && anyArabic is Map) {
            selectedLanguage = (anyArabic['locale'] ?? 'ar').toString();
          }
        }
      }

      // لو ما قدر يجيب voices، نحاول مباشرة ar-SA ثم ar
      selectedLanguage ??= 'ar-SA';

      // إذا setLanguage رجع error، ممكن يرمي Exception
      await _tts.setLanguage(selectedLanguage);
      await _tts.setSpeechRate(0.45);
      await _tts.setPitch(1.0);

      _ttsReady = true;

      // التعامل مع انتهاء/إلغاء/خطأ القراءة
      _tts.setCompletionHandler(() {
        if (!mounted) return;
        setState(() => _isSpeaking = false);
      });

      _tts.setCancelHandler(() {
        if (!mounted) return;
        setState(() => _isSpeaking = false);
      });

      _tts.setErrorHandler((message) {
        debugPrint("TTS error: $message");
        if (!mounted) return;
        setState(() {
          _isSpeaking = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "خدمة قراءة المقال غير متاحة أو حدث خطأ في الصوت.",
              style: GoogleFonts.ibmPlexSansArabic(color: Colors.white),
            ),
            backgroundColor: Colors.redAccent,
          ),
        );
      });
    } catch (e) {
      debugPrint("TTS init error: $e");
      _ttsReady = false;
    }
  }

  @override
  void dispose() {
    _tts.stop();
    super.dispose();
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
  // 🔊 تقسيم النص لقطع صغيرة وقراءته
  // ======================================================
  Future<void> _speakLongText(String text) async {
    // Android TTS غالباً له حد حول 4000 حرف
    const int maxLen = 3000;
    final List<String> parts = [];

    String clean = text.replaceAll('\n', ' ').replaceAll(RegExp(r'\s+'), ' ');

    for (int i = 0; i < clean.length; i += maxLen) {
      final end = (i + maxLen < clean.length) ? i + maxLen : clean.length;
      parts.add(clean.substring(i, end));
    }

    for (final part in parts) {
      // لو اليوزر وقف القراءة، نطلع من اللوب
      if (!_isSpeaking) break;
      await _tts.speak(part);
      // بفضل awaitSpeakCompletion(true) هي تنتظر لين يخلص الجزء
    }
  }

  Future<void> _toggleSpeak() async {
    if (!_ttsReady) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "ميزة قراءة المقال غير مدعومة على هذا الجهاز.",
            style: GoogleFonts.ibmPlexSansArabic(color: Colors.white),
          ),
          backgroundColor: AppColors.accent,
        ),
      );
      return;
    }

    if (_article == null) return;
    final text = (_article!['content'] ?? '').toString().trim();

    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "لا يوجد نص لقراءته.",
            style: GoogleFonts.ibmPlexSansArabic(color: Colors.white),
          ),
          backgroundColor: AppColors.accent,
        ),
      );
      return;
    }

    if (_isSpeaking) {
      await _tts.stop();
      if (mounted) setState(() => _isSpeaking = false);
    } else {
      await _tts.stop();
      if (!mounted) return;
      setState(() => _isSpeaking = true);
      await _speakLongText(text);
      // لو خلص كل الأجزاء بدون Error أو Cancel، نوقف الفلاغ
      if (mounted) setState(() => _isSpeaking = false);
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
        appBar: const NameerAppBar(showBack: true, showTitleInBar: false),
        body: AnimatedBackgroundContainer(
          child: _loading
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
                const SizedBox(height: 12),
                _buildReadingControls(),
                const SizedBox(height: 16),
                Text(
                  a['title'] ?? '',
                  style: GoogleFonts.ibmPlexSansArabic(
                    fontSize: _titleFontSize,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  a['content'] ?? '',
                  style: GoogleFonts.ibmPlexSansArabic(
                    fontSize: _bodyFontSize,
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
                      colors: [AppColors.primary, AppColors.tealSoft],
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

  Widget _buildReadingControls() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.92),
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          _buildFontSizeControl(),
          const Spacer(),
          InkWell(
            onTap: _toggleSpeak,
            borderRadius: BorderRadius.circular(999),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: _isSpeaking
                    ? AppColors.primary.withOpacity(0.12)
                    : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _isSpeaking ? Icons.volume_up : Icons.volume_down,
                    size: 20,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _isSpeaking ? 'إيقاف القراءة' : 'قراءة المقال',
                    style: GoogleFonts.ibmPlexSansArabic(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 🔤 التحكم في حجم الخط كـ Slider
  Widget _buildFontSizeControl() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.grey.shade300, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // أ- (صغير)
          Text(
            'أ',
            style: GoogleFonts.ibmPlexSansArabic(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(width: 4),

          // الـ Slider بارتفاع صغير
          SizedBox(
            width: 110,
            height: 24, // 🔹 هذا أهم شيء يقلل الارتفاع
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 2, // أنحف
                thumbShape: const RoundSliderThumbShape(
                  enabledThumbRadius: 6,
                ), // أصغر
                overlayShape: SliderComponentShape.noOverlay, // بدون هالة كبيرة
              ),
              child: Slider(
                min: 0.8,
                max: 1.3,
                divisions: 5,
                value: _fontScale.clamp(0.8, 1.3),
                onChanged: (v) {
                  setState(() {
                    _fontScale = v;
                  });
                },
              ),
            ),
          ),

          const SizedBox(width: 4),

          // أ+ (كبير)
          Text(
            'أ',
            style: GoogleFonts.ibmPlexSansArabic(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.dark,
            ),
          ),
        ],
      ),
    );
  }
}
