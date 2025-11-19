import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart'; // 👈 مهم لتمييز الضغط على الجمل
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

  // 📚 إعدادات حجم الخط
  double _fontScale = 1.0; // بين 0.8 و 1.3 تقريباً
  double get _bodyFontSize => 15 * _fontScale;
  double get _titleFontSize => 22 * _fontScale;

  // 🔊 TTS
  late FlutterTts _tts;
  bool _isSpeaking = false;
  bool _ttsReady = false;

  // 🎚 سرعة القراءة (base * factor)
  final double _baseRate = 0.45;
  final List<double> _speedFactors = [1.0, 1.25, 1.5, 1.75, 2.0];
  int _speedIndex = 0;
  double _speechRate = 0.45;

  // 🧩 متابعة القراءة (تقسيم المقال إلى جمل)
  List<String> _sentences = [];
  int _currentSentenceIndex = -1;

  // 👆 علشان نقدر نضيف TapGestureRecognizer لكل جملة ونفضّيها في dispose
  final List<TapGestureRecognizer> _tapRecognizers = [];

  // ✅ NEW: نخزن ScaffoldMessenger مرة وحدة
  late ScaffoldMessengerState _scaffoldMessenger;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scaffoldMessenger = ScaffoldMessenger.of(context);
  }

  // ✅ NEW: دالة مساعدة لعرض الـ SnackBar
  void _showSnack(String message, {Color? background}) {
    _scaffoldMessenger.showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: GoogleFonts.ibmPlexSansArabic(color: Colors.white),
        ),
        backgroundColor: background ?? AppColors.accent,
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _speechRate = _baseRate * _speedFactors[_speedIndex];
    _initTts();
    _loadStoredArticle();
  }

  Future<void> _initTts() async {
    _tts = FlutterTts();

    try {
      await _tts.awaitSpeakCompletion(true);

      final voices = await _tts.getVoices;
      String? selectedLanguage;

      if (voices is List) {
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
          selectedLanguage = (saVoice['locale'] ?? 'ar-SA').toString();
        } else {
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

      selectedLanguage ??= 'ar-SA';

      await _tts.setLanguage(selectedLanguage);
      await _tts.setSpeechRate(_speechRate);
      await _tts.setPitch(1.0);

      _ttsReady = true;

      _tts.setErrorHandler((message) {
        if (!mounted) return;
        setState(() {
          _isSpeaking = false;
          _currentSentenceIndex = -1;
        });
        _showSnack(
          "حدث خطأ في خدمة قراءة المقال.",
          background: Colors.redAccent,
        );
      });

    } catch (e) {
      _ttsReady = false;
    }
  }

  @override
  void dispose() {
    _tts.stop();
    for (final r in _tapRecognizers) {
      r.dispose();
    }
    _tapRecognizers.clear();
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

        _prepareSentences();
        return;
      }

      setState(() {
        _error = true;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = true;
        _loading = false;
      });
    }
  }

  // ======================================================
  // 🧩 تجهيز الجمل للمتابعة
  // ======================================================
  void _prepareSentences() {
    final text = (_article?['content'] ?? '').toString().trim();
    _sentences = [];

    if (text.isEmpty) return;

    final regex = RegExp(r'([^\.!\؟\?\n]+[\.!\؟\?]?)', multiLine: true);
    for (final match in regex.allMatches(text)) {
      final s = match.group(0)?.trim();
      if (s != null && s.isNotEmpty) {
        _sentences.add(s);
      }
    }

    if (_sentences.isEmpty) {
      _sentences = [text];
    }
  }

  // ======================================================
  // 🔊 قراءة المقال من جملة معيّنة إلى النهاية
  // ======================================================
  Future<void> _speakFromIndex(int startIndex) async {
    if (_sentences.isEmpty) {
      _prepareSentences();
    }
    if (_sentences.isEmpty) return;

    if (startIndex < 0) startIndex = 0;
    if (startIndex >= _sentences.length) return;

    for (int i = startIndex; i < _sentences.length; i++) {
      if (!_isSpeaking) break;

      if (mounted) {
        setState(() {
          _currentSentenceIndex = i;
        });
      }

      await _tts.speak(_sentences[i]);
    }

    if (mounted) {
      setState(() {
        if (_isSpeaking) {
          _currentSentenceIndex = -1;
        }
        _isSpeaking = false;
      });
    }
  }

  // تشغيل/إيقاف مع الاستمرار من آخر جملة
  Future<void> _toggleSpeak() async {
    if (!_ttsReady) {
      _showSnack(
        "ميزة قراءة المقال غير مدعومة على هذا الجهاز.",
      );
      return;
    }

    if (_article == null) return;
    final text = (_article!['content'] ?? '').toString().trim();

    if (text.isEmpty) {
      _showSnack(
        "لا يوجد نص لقراءته.",
      );
      return;
    }

    if (_isSpeaking) {
      // إيقاف مؤقت مع الاحتفاظ بمكاننا
      await _tts.stop();
      if (mounted) {
        setState(() {
          _isSpeaking = false;
          // نحتفظ بـ _currentSentenceIndex عشان نكمل لاحقًا
        });
      }
    } else {
      await _tts.stop();
      if (!mounted) return;

      await _tts.setSpeechRate(_speechRate);

      int startIndex;
      if (_currentSentenceIndex < 0 ||
          _currentSentenceIndex >= _sentences.length - 1) {
        startIndex = 0;
      } else {
        startIndex = _currentSentenceIndex + 1;
      }

      setState(() {
        _isSpeaking = true;
      });

      await _speakFromIndex(startIndex);
    }
  }


  // ✅ تغيير سرعة القراءة بالضغط على زر x1/x1.25... بدون إيقاف الصوت
  Future<void> _cycleSpeed() async {
    setState(() {
      _speedIndex = (_speedIndex + 1) % _speedFactors.length;
      _speechRate = _baseRate * _speedFactors[_speedIndex];
    });

    if (!_ttsReady) return;

    // تحديث سرعة القراءة مباشرة، لو الصوت شغال يتغير تدريجيًا
    await _tts.setSpeechRate(_speechRate);
  }

  String _speedLabel() {
    final factor = _speedFactors[_speedIndex];
    String s;
    if (factor % 1 == 0) {
      s = factor.toStringAsFixed(0);
    } else {
      s = factor.toStringAsFixed(2);
      s = s.replaceFirst(RegExp(r'0+$'), '');
      s = s.replaceFirst(RegExp(r'\.$'), '');
    }
    return 'x$s';
  }Future<void> _startShortTest() async {
  final raw = (_article?['content'] ?? '').toString();
  final content = raw.trim();
  final length = content.length;

  if (length < 80) {
    _showSnack(
      "المقال قصير ولا يمكن إنشاء اختبار قصير له.",
    );
    return;
  }

  if (_isSpeaking) {
    await _tts.stop();
    if (!mounted) return;
    setState(() {
      _isSpeaking = false;
      _currentSentenceIndex = -1;
    });
  }

  if (!mounted) return;
  setState(() => _generatingTest = true);

  try {
    final functions =
        FirebaseFunctions.instanceFor(region: 'us-central1');
    final callable =
        functions.httpsCallable('generateShortTestVerification');

    final result = await callable.call({
      'articleText': content,
      'apiType': 'gemini',
    });

    Map<String, dynamic> data;

    if (result.data is Map) {
      data = Map<String, dynamic>.from(result.data as Map);
    } else {
      String raw = result.data.toString();
      raw = raw.replaceAll("```json", "").replaceAll("```", "").trim();

      if (!raw.contains('{') || !raw.contains('}')) {
        throw Exception('Invalid JSON from function');
      }

      raw = raw.substring(
        raw.indexOf("{"),
        raw.lastIndexOf("}") + 1,
      );

      data = jsonDecode(raw) as Map<String, dynamic>;
    }

    final quiz = {
      'question': data['question'] ?? '',
      'options': List<String>.from(data['options'] ?? const []),
      'answer': data['answer'] ?? '',
    };

    if (!mounted) return;
    setState(() => _generatingTest = false);

    if (!mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ShortTestVerificationPage(
          userTaskDocId: widget.userTaskDocId,
          quiz: quiz,
        ),
      ),
    );
  } on FirebaseFunctionsException catch (e) {
    if (!mounted) return;
    setState(() => _generatingTest = false);

    // 👇 طباعة الخطأ في الـ console
    print(
        '⚠️ generateShortTestVerification ERROR: code=${e.code}, message=${e.message}, details=${e.details}');

    _showSnack(
      "حدث خطأ في إنشاء الاختبار القصير. حاولي مرة أخرى لاحقًا.",
      background: Colors.redAccent,
    );
  } catch (e) {
    if (!mounted) return;
    setState(() => _generatingTest = false);

    // 👇 خطأ غير متوقع
    print('⚠️ generateShortTestVerification UNKNOWN ERROR: $e');

    _showSnack(
      "حدث خطأ أثناء إنشاء الاختبار القصير.",
      background: Colors.redAccent,
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
                _buildArticleText(),
                const SizedBox(height: 24),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    "المصدر: ${a['sourceName'] ?? ''}",
                    style: GoogleFonts.ibmPlexSansArabic(
                      fontSize: 13,
                      color: Colors.grey.shade600,
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

  // 🧠 نص المقال مع متابعة القراءة + إمكانية الضغط على الجملة
  Widget _buildArticleText() {
    final text = (_article?['content'] ?? '').toString();

    if (_sentences.isEmpty) {
      return Text(
        text,
        style: GoogleFonts.ibmPlexSansArabic(
          fontSize: _bodyFontSize,
          height: 1.7,
          color: Colors.black87,
        ),
      );
    }

    // فضي الـ recognizers القديمة
    for (final r in _tapRecognizers) {
      r.dispose();
    }
    _tapRecognizers.clear();

    final spans = <InlineSpan>[];

    for (int i = 0; i < _sentences.length; i++) {
      final s = _sentences[i] + ' ';

      Color color;
      if (!_isSpeaking || _currentSentenceIndex == -1) {
        // ما في قراءة → الكل أسود
        color = Colors.black87;
      } else if (i <= _currentSentenceIndex) {
        // انقرأت → أسود
        color = Colors.black87;
      } else {
        // لسه → رمادي أفتح
        color = Colors.grey.shade400;
      }

      final recognizer = TapGestureRecognizer()
        ..onTap = () async {
          if (!_ttsReady) return;
          final content = (_article?['content'] ?? '').toString().trim();
          if (content.isEmpty) return;

          await _tts.stop();
          if (!mounted) return;

          await _tts.setSpeechRate(_speechRate);

          setState(() {
            _isSpeaking = true;
            _currentSentenceIndex = i - 1;
          });

          _speakFromIndex(i);
        };

      _tapRecognizers.add(recognizer);

      spans.add(
        TextSpan(
          text: s,
          style: GoogleFonts.ibmPlexSansArabic(
            fontSize: _bodyFontSize,
            height: 1.7,
            color: color,
          ),
          recognizer: recognizer,
        ),
      );
    }

    return RichText(
      textDirection: TextDirection.rtl,
      text: TextSpan(children: spans),
    );
  }

  Widget _buildReadingControls() {
    final String speedLabel = _speedLabel();

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
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: _cycleSpeed,
                    borderRadius: BorderRadius.circular(999),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        speedLabel,
                        style: GoogleFonts.ibmPlexSansArabic(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.dark,
                        ),
                      ),
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

  // 🔤 التحكم في حجم الخط كـ Slider صغير
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
          Text(
            'أ',
            style: GoogleFonts.ibmPlexSansArabic(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(width: 4),
          SizedBox(
            width: 110,
            height: 24,
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 2,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: SliderComponentShape.noOverlay,
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
