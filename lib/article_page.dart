import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;
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
  static const primary33 = Color(
    0x544BAA98,
  ); // شفافية خفيفة (نفس إحساس الحقول المقفولة)
  static const light = Color(0xFF79D0BE);
  static const background = Color(0xFFF3FAF7);
  static const mint = Color(0xFFB6E9C1);
  static const tealSoft = Color(0xFF75BCAF);
}

class ArticlePage extends StatefulWidget {
  final String userTaskDocId; // مثال: "{uid}_YYYYMMDD"
  final String? taskId; // ربط اختياري

  const ArticlePage({super.key, required this.userTaskDocId, this.taskId});

  @override
  State<ArticlePage> createState() => _ArticlePageState();
}

class _ArticlePageState extends State<ArticlePage> {
  Map<String, dynamic>? _article; // articleData المحفوظ/المعروض
  bool _loading = true;
  bool _error = false;
  bool _showReadButton = false; // يظهر فقط عند نهاية الصفحة
  bool _generatingTest = false;

  @override
  void initState() {
    super.initState();
    _loadOrFetchArticle();
  }

  // ========== الخطوة 1: قراءة/جلب المقال وتثبيته ==========
  Future<void> _loadOrFetchArticle() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('User not logged in');

      final userTaskRef = FirebaseFirestore.instance
          .collection('userTasks')
          .doc(widget.userTaskDocId);

      final snap = await userTaskRef.get();
      final data = snap.data() ?? {};

      // ✅ لو فيه مقال محفوظ نجيبه مباشرة
      if (data.containsKey('articleId') && data['articleId'] != null) {
        final artSnap = await FirebaseFirestore.instance
            .collection('articles')
            .doc(data['articleId'])
            .get();

        if (artSnap.exists) {
          setState(() {
            _article = artSnap.data();
            _loading = false;
          });
          return;
        }
      }

      // 🆕 مافيه مقال مرتبط، نجيب واحد جديد
      final art = await _fetchRandomArabicArticle();

      // 🟢 نخزّنه في Collection articles
      final articleDoc = await FirebaseFirestore.instance
          .collection('articles')
          .add({
        'taskId': widget.taskId,
        'userId': user.uid,
        'userTaskDocId': widget.userTaskDocId,
        'title': art['title'],
        'description': art['description'],
        'content': art['content'],
        'url': art['url'],
        'urlToImage': art['urlToImage'],
        'sourceName': art['sourceName'],
        'publishedAt': art['publishedAt'],
        'language': 'ar',
        'category': 'news',
        'createdAt': FieldValue.serverTimestamp(),
      });

      // 🔗 نحفظ الـ articleId في userTasks
      await userTaskRef.update({'articleId': articleDoc.id});

      setState(() {
        _article = art;
        _loading = false;
      });
    } catch (e) {
      debugPrint("❌ Article fetch/save error: $e");
      setState(() {
        _error = true;
        _loading = false;
      });
    }
  }

  // ========== الخطوة 2 (محدثة): جلب مقال بيئي عشوائي من NewsData.io ==========
  Future<Map<String, dynamic>> _fetchRandomArabicArticle() async {
    const apiKey = 'pub_1eff8ffbdb284bc7883f1d8b90bedbc0';
    const query = 'البيئة OR المناخ OR الاستدامة OR الطاقة النظيفة OR تدوير';

    final url = Uri.parse(
        'https://newsdata.io/api/1/news?apikey=$apiKey&q=$query&language=ar&category=environment');

    debugPrint('🌿 Fetching from NewsData.io: $url');

    final res = await http.get(url);
    if (res.statusCode != 200) {
      throw Exception('NewsData API returned ${res.statusCode}');
    }

    final data = json.decode(res.body);
    final List results = data['results'] ?? [];
    if (results.isEmpty) throw Exception('No environmental articles found');
    // بعد استلام النتائج:
    final List filtered = results.where((art) {
      final text = ((art['title'] ?? '') + ' ' + (art['full_content'] ?? '')).toLowerCase();
      final keywords = [
        'البيئة',
        'استدامة',
        'تدوير',
        'إعادة تدوير',
        'تلوث',
        'احتباس حراري',
        'كربون',
        'طاقة متجددة',
        'نفايات',
        'تشجير',
        'هواء نقي',
        'مناخ',
        'انبعاثات',
        'محميات طبيعية',
        'حفاظ على الطبيعة',
        'تنوع بيولوجي',
        'تغير المناخ',
        'طاقة نظيفة',
        'مصادر طبيعية' 
      ];

      // ✅ لازم يحتوي على أي من الكلمات المفتاحية
      return keywords.any((k) => text.contains(k));
    }).toList();

    if (filtered.isEmpty) throw Exception('No relevant environmental articles found');

    // نختار مقال عشوائي من المصفاة
    final art = filtered[Random().nextInt(filtered.length)] as Map<String, dynamic>;

    // نختار مقال عشوائي
    // final art = results[Random().nextInt(results.length)] as Map<String, dynamic>;

    // نجيب النص من الـ API
    String content = (art['full_content'] ?? art['content'] ?? art['description'] ?? '').toString();


    // ✅ دايمًا نحاول نقرأ النص الحقيقي من الموقع مباشرة (أدق وأوضح)
    final urlStr = art['link'] ?? '';
    if (urlStr.isNotEmpty) {
      debugPrint('🔍 Always fetching full text from original link...');
      final fullText = await _fetchFullText(urlStr);
      if (fullText.isNotEmpty && fullText.length > 300) {
        content = fullText;
      }
    }
    return {
      'title': art['title'] ?? '',
      'description': art['description'] ?? '',
      'content': content,
      'url': art['link'] ?? '',
      'urlToImage': art['image_url'] ?? '',
      'sourceName': art['source_id'] ?? (art['creator']?.join(', ') ?? ''),
      'publishedAt': art['pubDate'] ?? '',
    };
  }

  // ========== الخطوة 3 (محدّثة): جلب النص الكامل من المصدر ==========
  Future<String> _fetchFullText(String url) async {
    try {
      final resp = await http.get(
        Uri.parse(url),
        headers: {
          "User-Agent": "NameerBot/1.0 (+app)",
          "Accept-Language": "ar,en;q=0.7",
        },
      );
      if (resp.statusCode != 200) return '';

      final doc = html_parser.parse(resp.body);

      // حذف العناصر غير المفيدة
      for (final sel in [
        'script',
        'style',
        'noscript',
        'header',
        'footer',
        'nav',
        'form',
        'iframe',
        'svg',
      ]) {
        doc.querySelectorAll(sel).forEach((e) => e.remove());
      }

      // نحاول إيجاد عنصر يحتوي النص الأساسي للمقال
      final candidates = [
        'article',
        "[itemprop='articleBody']",
        '.article-body',
        '.post-content',
        '.entry-content',
        '.content__article-body',
        '.story-body',
        '.content',
        'main',
      ];

      for (final sel in candidates) {
        final el = doc.querySelector(sel);
        if (el != null) {
          final text = _clean(el.text);
          if (text.length > 400) return text;
        }
      }

      // 🪄 Fallback محسّن: دمج الفقرات بدون تكرار وبترتيب جميل
      final ps = doc.getElementsByTagName('p');

      final seen = <String>{};
      final paragraphs = <String>[];

      for (final e in ps) {
        var text = _clean(e.text);
        if (text.isEmpty || text.length < 30) continue;

        // منع التكرار أو الفقرات شبه المتطابقة
        final normalized = text.replaceAll(RegExp(r'\s+'), ' ').trim();
        if (seen.contains(normalized)) continue;
        seen.add(normalized);

        paragraphs.add(text);
      }

      // نرتب الفقرات ونضيف فواصل مرتبة
      final merged = paragraphs.join('\n\n');
      final cleaned = merged
          .replaceAll(RegExp(r'\n{3,}'), '\n\n')
          .replaceAll(RegExp(r'\s{2,}'), ' ')
          .trim();

      return cleaned;
    } catch (e) {
      debugPrint('❌ Full text fetch error: $e');
      return '';
    }
  }

  // ========== الخطوة 4: تنظيف نص ==========
  String _clean(String? t) {
    final s = (t ?? '')
        .replaceAll(RegExp(r'\[.*?\]'), '') // [+123 chars]
        .replaceAll(RegExp(r'http\S+'), '') // روابط
        .replaceAll(RegExp(r'pic\.twitter\.com/\S+'), '')
        .replaceAll(RegExp(r'[@#]'), '')
        .replaceAll(RegExp(r'[^\u0600-\u06FFa-zA-Z0-9\s،.!؟:؛-]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return s;
  }

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

    setState(() {
      _generatingTest = true;
    });

    try {
      final callable = FirebaseFunctions.instance.httpsCallable(
        'generateShortTestVerification',
      );

      final result = await callable.call({
        'articleText': content,
        'apiType': 'gemini', // أو openai
      });

      debugPrint("RAW RESPONSE: ${result.data}");

      // ============================
      // 🔥 تنظيف واستخرج JSON بأمان
      // ============================

      String raw = result.data.toString();
      debugPrint("RAW BEFORE CLEAN = $raw");

      // إذا كانت البيانات أصلاً Map (من الـ Cloud Function)
      if (result.data is Map) {
        debugPrint("🔥 Parsed directly as MAP");
        final data = result.data as Map;

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
        return;
      }

      // إذا كانت String فيها JSON → نكمّل التنظيف
      // 1) Remove Markdown
      raw = raw.replaceAll("```json", "").replaceAll("```", "").trim();

      // 2) Extract only JSON
      int first = raw.indexOf('{');
      int last = raw.lastIndexOf('}');
      if (first == -1 || last == -1 || last <= first) {
        throw FormatException("NO_VALID_JSON_FOUND");
      }

      raw = raw.substring(first, last + 1).trim();
      debugPrint("RAW AFTER CLEAN = $raw");

      // 3) Decode
      final data = jsonDecode(raw);

      final quiz = {
        'question': data['question'] ?? '',
        'options': List<String>.from(data['options'] ?? const []),
        'answer': data['answer'] ?? '',
      };

      if (!mounted) return;
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

      if (!mounted) return;
      setState(() => _generatingTest = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "حدث خطأ أثناء إنشاء الاختبار القصير. حاول مرة أخرى لاحقًا.",
            style: GoogleFonts.ibmPlexSansArabic(color: Colors.white),
          ),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  // ========== UI ==========
  @override
  Widget build(BuildContext context) {
    final statusBar = MediaQuery.of(context).padding.top;
    final topPadding = statusBar + 20; // نفس AdminTasksPage بالضبط

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
                        "حدث خطأ أثناء جلب المقال. حاول لاحقًا.",
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

  // زر "تمت القراءة" ما يظهر إلا عند نهاية السكول
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
                
                // الصورة
                if ((a['urlToImage'] ?? '').toString().isNotEmpty)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: Image.network(a['urlToImage'], fit: BoxFit.cover),
                  ),

                const SizedBox(height: 20),

                // العنوان
                Text(
                  a['title'] ?? '',
                  style: GoogleFonts.ibmPlexSansArabic(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary,
                  ),
                ),

                const SizedBox(height: 20),

                // النص
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
