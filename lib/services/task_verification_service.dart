// lib/services/task_verification_service.dart

import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

import 'ocr_service.dart';

class TaskVerificationResult {
  final bool success;
  final int? taskId;
  final String? taskName;
  final String? taskNameAr;
  final double? confidence;
  final String? confidencePercent;
  final bool? verified;
  final bool? matchesExpected;
  final String? verificationSource; // vision | ocr
  final String? extractedText;
  final String? error;
  final Map<String, double>? allPredictions;
  final String? countryOfOrigin;
  final bool? isLocalSaudi;
  final String? evidenceText;

  TaskVerificationResult({
    required this.success,
    this.taskId,
    this.taskName,
    this.taskNameAr,
    this.confidence,
    this.confidencePercent,
    this.verified,
    this.matchesExpected,
    this.verificationSource,
    this.extractedText,
    this.error,
    this.allPredictions,
    this.countryOfOrigin,
    this.isLocalSaudi,
    this.evidenceText,
  });

  factory TaskVerificationResult.fromJson(Map<String, dynamic> json) {
    Map<String, double>? predictions;

    if (json['all_predictions'] != null) {
      predictions = Map<String, double>.from(
        (json['all_predictions'] as Map).map(
          (key, value) => MapEntry(key.toString(), (value as num).toDouble()),
        ),
      );
    }

    return TaskVerificationResult(
      success: json['success'] ?? false,
      taskId: json['task_id'],
      taskName: json['task_name'],
      taskNameAr: json['task_name_ar'],
      confidence: (json['confidence'] is num)
          ? (json['confidence'] as num).toDouble()
          : null,
      confidencePercent: json['confidence_percent'],
      verified: json['verified'],
      matchesExpected: json['matches_expected'],
      verificationSource: 'vision',
      allPredictions: predictions,

      // ✅ جديد
      countryOfOrigin: json['country_of_origin']?.toString(),
      isLocalSaudi: json['is_local_saudi'] == true,
      evidenceText: json['evidence_text']?.toString(),
    );
  }

  TaskVerificationResult copyWith({
    bool? success,
    int? taskId,
    String? taskName,
    String? taskNameAr,
    double? confidence,
    String? confidencePercent,
    bool? verified,
    bool? matchesExpected,
    String? verificationSource,
    String? extractedText,
    String? error,
    Map<String, double>? allPredictions,
  }) {
    return TaskVerificationResult(
      success: success ?? this.success,
      taskId: taskId ?? this.taskId,
      taskName: taskName ?? this.taskName,
      taskNameAr: taskNameAr ?? this.taskNameAr,
      confidence: confidence ?? this.confidence,
      confidencePercent: confidencePercent ?? this.confidencePercent,
      verified: verified ?? this.verified,
      matchesExpected: matchesExpected ?? this.matchesExpected,
      verificationSource: verificationSource ?? this.verificationSource,
      extractedText: extractedText ?? this.extractedText,
      error: error ?? this.error,
      allPredictions: allPredictions ?? this.allPredictions,
      countryOfOrigin: countryOfOrigin ?? this.countryOfOrigin,
      isLocalSaudi: isLocalSaudi ?? this.isLocalSaudi,
      evidenceText: evidenceText ?? this.evidenceText,
    );
  }

  @override
  String toString() {
    if (!success) return 'Error: $error';
    return 'Task: $taskNameAr | Confidence: $confidencePercent | Source: $verificationSource';
  }
}

class TaskVerificationService {
  static const String _baseUrl =
      'https://verify-tasks-188455017517.us-central1.run.app';

  static bool _debugMode = true;

  static void _log(String message) {
    if (_debugMode) {
      print('🔍 [TaskVerification] $message');
    }
  }

  static Future<TaskVerificationResult> verifyOriginFromFile(
    File imageFile, {
    double threshold = 0.7,
  }) async {
    final bytes = await imageFile.readAsBytes();
    final base64Image = base64Encode(bytes);

    // نفس الاستدعاء لكن مع mode
    return await _sendVerificationRequest(
      imageBase64: base64Image,
      threshold: threshold,
      mode: 'origin_check',
    );
  }

  /// 🔹 MAIN METHOD (Vision + OCR fallback)
  /// ✅ الطريقة الجديدة - استبدلها كلها
  static Future<TaskVerificationResult> verifyTaskWithTitle({
    required File imageFile,
    required String taskTitle, // 🔴 من Firebase
    required String taskDescription, // 🔴 من Firebase
    double visionThreshold = 0.6,
  }) async {
    try {
      _log('🚀 بدء التحقق باستخدام عنوان التاسك: "$taskTitle"');

      // 1️⃣ محاولة Vision API
      final visionResult = await verifyFromFile(
        imageFile,
        expectedTask: taskTitle, // نرسله كامل
      );

      if (visionResult.success &&
          visionResult.verified == true &&
          visionResult.confidence != null &&
          visionResult.confidence! >= visionThreshold) {
        return visionResult.copyWith(verificationSource: 'vision');
      }

      // 2️⃣ OCR: أي كلمة من العنوان تطابق؟
      final extractedText = await OCRService.extractTextFromFile(imageFile);
      _log('📝 النص المستخرج: "$extractedText"');

      if (extractedText.isEmpty) {
        return TaskVerificationResult(
          success: false,
          error: 'لا يوجد نص في الصورة',
          verificationSource: 'ocr',
          extractedText: extractedText,
        );
      }

      // 3️⃣ البحث عن أي كلمة من عنوان المهمة
      final lowerExtracted = extractedText.toLowerCase();
      final lowerTitle = taskTitle.toLowerCase();
      final titleWords = lowerTitle.split(RegExp(r'\s+'));

      final matchedWords = <String>[];
      for (final word in titleWords) {
        if (word.length > 2 && lowerExtracted.contains(word)) {
          matchedWords.add(word);
        }
      }

      final isValid = matchedWords.isNotEmpty; // ✅ كلمة واحدة تكفي!

      _log('📊 النتيجة: ${isValid ? "✅ صح" : "❌ خطأ"}');
      _log('   - كلمات مطابقة: $matchedWords');

      return TaskVerificationResult(
        success: isValid,
        taskName: taskTitle, // نرسل العنوان الأصلي
        taskNameAr: taskTitle, // أو ممكن تستخرج أول كلمة
        confidence: isValid ? 0.85 : 0.4,
        confidencePercent: isValid ? '85%' : '40%',
        verified: isValid,
        matchesExpected: isValid,
        verificationSource: 'ocr',
        extractedText: extractedText,
      );
    } catch (e) {
      return TaskVerificationResult(
        success: false,
        error: 'فشل التحقق: $e',
        verificationSource: 'system',
      );
    }
  }

  /// دالة لتوحيد أسماء المهام - النسخة المحسنة
  static String? _normalizeTaskName(String? taskName) {
    if (taskName == null) return null;

    final t = taskName.toLowerCase().trim();

    // إزالة مسافات زائدة وتوحيد النص
    final cleaned = t.replaceAll(RegExp(r'\s+'), ' ');

    if (cleaned.contains('plastic') || cleaned.contains('بلاست'))
      return 'plastic';
    if (cleaned.contains('paper') || cleaned.contains('ورق')) return 'paper';
    if (cleaned.contains('food') ||
        cleaned.contains('طعام') ||
        cleaned.contains('عضوي') ||
        cleaned.contains('bread'))
      return 'food';
    if (cleaned.contains('cloth') ||
        cleaned.contains('ملابس') ||
        cleaned.contains('clothes'))
      return 'cloth';
    if (cleaned.contains('metro') || cleaned.contains('مترو')) return 'metro';
    if (cleaned.contains('bus') || cleaned.contains('باص')) return 'bus';
    if (cleaned.contains('bicycle') || cleaned.contains('دراجة'))
      return 'bicycle';
    if (cleaned.contains('scooter') || cleaned.contains('سكوتر'))
      return 'scooter';
    if (cleaned.contains('rvm') || cleaned.contains('تدوير')) return 'rvm';

    return cleaned;
  }

  /// دالة للحصول على الاسم العربي
  static String? _getArabicTaskName(String? taskName) {
    if (taskName == null) return null;

    final Map<String, String> arabicNames = {
      'plastic': 'بلاستيك',
      'paper': 'ورق',
      'food': 'نفايات عضوية',
      'cloth': 'ملابس',
      'metro': 'مترو',
      'bus': 'باص',
      'bicycle': 'دراجة هوائية',
      'scooter': 'سكوتر',
      'rvm': 'آلة التدوير',
    };

    return arabicNames[taskName] ?? taskName;
  }

  /// 🔹 Vision only (existing logic)
  static Future<TaskVerificationResult> verifyFromFile(
    File imageFile, {
    String? expectedTask,
    double threshold = 0.7,
    String mode = 'task_verify',
  }) async {
    try {
      final bytes = await imageFile.readAsBytes();
      final base64Image = base64Encode(bytes);

      return await _sendVerificationRequest(
        imageBase64: base64Image,
        expectedTask: expectedTask,
        threshold: threshold,
      );
    } catch (e) {
      return TaskVerificationResult(
        success: false,
        error: 'فشل في قراءة الصورة: $e',
      );
    }
  }

  static Future<TaskVerificationResult> _sendVerificationRequest({
    String? imageBase64,
    String? imageUrl,
    String? expectedTask,
    double threshold = 0.7,
    String mode = 'task_verify',
  }) async {
    try {
      final body = <String, dynamic>{'threshold': threshold, 'mode': mode};

      if (imageBase64 != null) {
        body['image_base64'] = imageBase64;
      } else if (imageUrl != null) {
        body['image_url'] = imageUrl;
      } else {
        return TaskVerificationResult(
          success: false,
          error: 'لم يتم توفير صورة',
        );
      }

      if (expectedTask != null) {
        body['expected_task'] = expectedTask;
      }
      body['mode'] = 'origin_check';
      _log('📤 request body: ${jsonEncode(body)}');
      final response = await http
          .post(
            Uri.parse(_baseUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 60));
      _log('📡 status: ${response.statusCode}');
      _log('📡 body: ${response.body}');

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        return TaskVerificationResult.fromJson(json);
      } else {
        final json = jsonDecode(response.body);
        return TaskVerificationResult(
          success: false,
          error: json['error'] ?? 'خطأ في الخادم: ${response.statusCode}',
        );
      }
    } catch (e) {
      return TaskVerificationResult(success: false, error: 'فشل الاتصال: $e');
    }
  }
}
