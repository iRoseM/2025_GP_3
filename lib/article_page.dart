import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'services/title_header.dart';

import 'task.dart'; // فيه AppColors + NameerAppBar
import 'services/background_container.dart';

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

  @override
  void initState() {
    super.initState();
    _loadOrFetchArticle();
  }

  // ========== الخطوة 1: قراءة/جلب المقال وتثبيته ==========
  Future<void> _loadOrFetchArticle() async {
    try {
      final userTaskRef = FirebaseFirestore.instance
          .collection('userTasks')
          .doc(widget.userTaskDocId);

      final snap = await userTaskRef.get();
      final data = snap.data() ?? {};

      // ✅ لو عنده articleId، نجيب المقال من articles مباشرة
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

      // 🆕 أول مرة: نجلب مقال جديد ونخزّنه في Collection articles
      final art = await _fetchRandomArticle();
      // 🔍 جلب النص الكامل من المصدر (بديل عن الـ content المقطوع)
      String fullText = '';
      if ((art['url'] ?? '').toString().isNotEmpty) {
        fullText = await _fetchFullText(art['url']);
      }

      // إذا النص اللي رجع ناقص، نستخدم النص المدمج
      if (fullText.isEmpty || fullText.length < 400) {
        fullText = art['content'] ?? art['description'] ?? '';
      }

      // أضيفي هنا userId من FirebaseAuth لو متاح عندك
      final auth = FirebaseAuth.instance;
      User? user = auth.currentUser;
      if (user == null) {
        final cred = await auth.signInAnonymously();
        user = cred.user;
        debugPrint('👤 Signed in anonymously: ${user?.uid}');
      }
      final articleDoc = await FirebaseFirestore.instance
          .collection('articles')
          .add({
            'taskId': widget.taskId,
            'userId': user!.uid, // ✅ ضروري
            'userTaskDocId': widget.userTaskDocId,
            'title': art['title'],
            'description': art['description'],
            // 'content': art['content'],
            'content': fullText,
            'url': art['url'],
            'urlToImage': art['urlToImage'],
            'sourceName': art['sourceName'],
            'publishedAt': art['publishedAt'],
            'language': 'ar',
            'category': 'environment',
            'createdAt': FieldValue.serverTimestamp(),
          });

      // 🔗 نحفظ فقط الـ articleId في userTasks
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

  // ========== الخطوة 2: NewsAPI -> مقال عشوائي عربي ==========
  // Future<Map<String, dynamic>> _fetchRandomArticle() async {
  //   const apiKey = '2a2d935013454a568f3c8301982a275c';
  //   // ✅ استخدم كلمات مفتاحية أوسع + ترميز صحيح
  //   const query =
  //       'البيئة OR الطبيعة OR إعادة التدوير OR الطاقة المتجددةOR الاستدامة';
  //   final url = Uri.parse(
  //     'https://newsapi.org/v2/everything?q=${Uri.encodeComponent(query)}&language=ar&pageSize=20&sortBy=publishedAt&apiKey=$apiKey',
  //   );

  //   debugPrint('🔍 Fetching from: $url');

  //   final res = await http.get(url, headers: {'User-Agent': 'NameerApp/1.0'});
  //   if (res.statusCode != 200) {
  //     throw Exception('❌ NewsAPI returned ${res.statusCode}');
  //   }

  //   final jsonBody = json.decode(res.body);
  //   final List arts = jsonBody['articles'] ?? [];

  //   if (arts.isEmpty) {
  //     debugPrint(
  //       '⚠️ No Arabic articles returned. totalResults=${jsonBody['totalResults']}',
  //     );
  //     throw Exception('No articles');
  //   }

  //   final rnd = Random();
  //   final art = arts[rnd.nextInt(arts.length)] as Map<String, dynamic>;

  //   // ✅ تنظيف المحتوى
  //   String content = (art['content'] ?? '').toString();
  //   content = content
  //       .replaceAll(RegExp(r'\[.*?\]'), '')
  //       .replaceAll(RegExp(r'http\S+'), '')
  //       .replaceAll(RegExp(r'pic\.twitter\.com/\S+'), '')
  //       .replaceAll(RegExp(r'[@#]'), '')
  //       .replaceAll(RegExp(r'[^\u0600-\u06FFa-zA-Z0-9\s،.!؟:؛-]'), ' ')
  //       .replaceAll(RegExp(r'\s+'), ' ')
  //       .trim();

  //   if (content.isEmpty || content.length < 100) {
  //     content = (art['description'] ?? '').toString();
  //   }

  //   return {
  //     'title': art['title'] ?? '',
  //     'description': art['description'] ?? '',
  //     'content': content,
  //     'url': art['url'] ?? '',
  //     'urlToImage': art['urlToImage'] ?? '',
  //     'sourceName': art['source']?['name'] ?? '',
  //     'publishedAt': art['publishedAt'] ?? '',
  //   };
  // }

  Future<Map<String, dynamic>> _fetchRandomArticle() async {
    const apiKey = '2a2d935013454a568f3c8301982a275c';
    // 🔓 مؤقتًا نفتح الشروط عشان نتاكد من الاتصال
    const query = 'Saudi OR السعودية OR بيئة OR environment OR world';
    final url = Uri.parse(
      'https://newsapi.org/v2/everything?q=${Uri.encodeComponent(query)}&pageSize=20&sortBy=publishedAt&apiKey=$apiKey',
    );

    debugPrint('🌍 Fetching from: $url');

    final res = await http.get(url, headers: {'User-Agent': 'NameerApp/1.0'});
    if (res.statusCode != 200) {
      throw Exception('❌ NewsAPI returned ${res.statusCode}');
    }

    final jsonBody = json.decode(res.body);
    final List arts = jsonBody['articles'] ?? [];

    if (arts.isEmpty) {
      debugPrint(
        '⚠️ No articles found at all (totalResults=${jsonBody['totalResults']})',
      );
      throw Exception('No articles');
    }

    final rnd = Random();
    final art = arts[rnd.nextInt(arts.length)] as Map<String, dynamic>;

    String content = (art['content'] ?? '').toString();
    content = content
        .replaceAll(RegExp(r'\[.*?\]'), '')
        .replaceAll(RegExp(r'http\S+'), '')
        .replaceAll(RegExp(r'pic\.twitter\.com/\S+'), '')
        .replaceAll(RegExp(r'[@#]'), '')
        .replaceAll(RegExp(r'[^\u0600-\u06FFa-zA-Z0-9\s،.!؟:؛-]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    if (content.isEmpty || content.length < 100) {
      content = (art['description'] ?? '').toString();
    }

    return {
      'title': art['title'] ?? '',
      'description': art['description'] ?? '',
      'content': content,
      'url': art['url'] ?? '',
      'urlToImage': art['urlToImage'] ?? '',
      'sourceName': art['source']?['name'] ?? '',
      'publishedAt': art['publishedAt'] ?? '',
    };
  }

  // ========== الخطوة 3: جلب النص الكامل من المصدر ==========
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

      // محاولات لعناصر شائعة
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

      // Fallback: دمج كل الفقرات
      final ps = doc.getElementsByTagName('p');
      final merged = ps
          .map((e) => e.text.trim())
          .where((t) => t.isNotEmpty)
          .join('\n\n');
      return _clean(merged);
    } catch (e) {
      debugPrint('⚠️ _fetchFullText error: $e');
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

  bool _isPartial(String? content) {
    if (content == null) return true;
    final c = content.trim();
    if (c.isEmpty) return true;
    if (c.contains(RegExp(r'\[\+\d+\s*chars\]'))) return true; // نمط NewsAPI
    if (c.length < 400) return true; // قصير على مقال كامل
    return false;
  }

  String _mergePreview(dynamic content, dynamic description) {
    final c = (content ?? '').toString();
    final d = (description ?? '').toString();
    final merged = ('$d\n\n$c').trim();
    return _clean(merged);
  }

  // ========== الخطوة 5: حفظ المقال في articles طبقًا لقواعدك ==========
  Future<void> _saveArticleToCollection({
    required String userId,
    required String? taskId,
    required Map<String, dynamic> art,
    required String fullContent,
  }) async {
    try {
      await FirebaseFirestore.instance.collection('articles').add({
        'userId': userId,
        'taskId': taskId ?? '',
        'title': art['title'] ?? '',
        'description': art['description'] ?? '',
        'content': fullContent, // النص الكامل
        'url': art['url'] ?? '',
        'urlToImage': art['urlToImage'] ?? '',
        'sourceName': art['sourceName'] ?? '',
        'language': 'ar',
        'category': 'environment', // مطابقة لقواعدك
        'createdAt': FieldValue.serverTimestamp(), // مطابقة لقواعدك
        // ملاحظـة: قواعدك لا تشترط publishedAt، لذا تركناه.
      });
    } catch (e) {
      debugPrint('⚠️ save to articles error: $e');
    }
  }

  // ========== UI ==========
  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        extendBodyBehindAppBar: true,
        backgroundColor: Colors.transparent,
        appBar: const NameerAppBar(
          title: "مقال اليوم",
          showBack: true,
          showTitleInBar: true,
        ),
        body: AnimatedBackgroundContainer(
          child: _loading
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
              : _buildBodyWithRevealButton(),
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
            padding: const EdgeInsets.fromLTRB(16, 110, 16, 120),
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
                const SizedBox(height: 14),
                if ((a['description'] ?? '').toString().isNotEmpty)
                  Text(
                    a['description'],
                    style: GoogleFonts.ibmPlexSansArabic(
                      fontSize: 16,
                      height: 1.6,
                      color: AppColors.dark,
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
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        "تمت القراءة — قريبًا بنفتح صفحة الكويز 🎯",
                        style: GoogleFonts.ibmPlexSansArabic(
                          color: Colors.white,
                        ),
                      ),
                      backgroundColor: AppColors.primary,
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 0,
                ),
                child: Text(
                  "تمت القراءة",
                  style: GoogleFonts.ibmPlexSansArabic(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
