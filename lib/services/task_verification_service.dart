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
      confidence: json['confidence']?.toDouble(),
      confidencePercent: json['confidence_percent'],
      verified: json['verified'],
      matchesExpected: json['matches_expected'],
      verificationSource: 'vision',
      allPredictions: predictions,
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

  /// 🔹 MAIN METHOD (Vision + OCR fallback)
  static Future<TaskVerificationResult> verifyWithOCRFallback(
    File imageFile, {
    String? expectedTask,
    double visionThreshold = 0.7,
  }) async {
    // 1️⃣ Vision first
    final visionResult = await verifyFromFile(
      imageFile,
      expectedTask: expectedTask,
    );

    // 2️⃣ If vision confidence is good → accept
    if (visionResult.success &&
        visionResult.confidence != null &&
        visionResult.confidence! >= visionThreshold) {
      return visionResult;
    }

    // 3️⃣ OCR fallback
    final extractedText = await OCRService.extractTextFromFile(imageFile);

    // Debug: طباعة النص المستخرج
    print('📝 النص المستخرج: $extractedText');

    if (extractedText.isEmpty) {
      return TaskVerificationResult(
        success: false,
        error: 'فشل التحقق: لا يوجد نص واضح في الصورة',
        verificationSource: 'ocr',
      );
    }

    final ocrTask = OCRTaskMapper.mapTaskToCategory(extractedText);

    // تحويل التوقعات المتوقعة إلى تنسيق قياسي للمقارنة
    final normalizedExpected = _normalizeTaskName(expectedTask);
    final normalizedOcrTask = _normalizeTaskName(ocrTask);

    final verified = ocrTask != null && normalizedOcrTask == normalizedExpected;

    print('🔍 المقارنة: $normalizedOcrTask == $normalizedExpected → $verified');

    return TaskVerificationResult(
      success: verified,
      taskName: ocrTask,
      taskNameAr: _getArabicTaskName(ocrTask), // ترجمة للعربية للعرض
      confidence: verified ? 0.8 : 0.3,
      confidencePercent: verified ? '80%' : '30%',
      verified: verified,
      matchesExpected: verified,
      verificationSource: 'ocr',
      extractedText: extractedText,
    );
  }

  /// دالة لتوحيد أسماء المهام
  static String? _normalizeTaskName(String? taskName) {
    if (taskName == null) return null;

    final t = taskName.toLowerCase();

    if (t.contains('plastic') || t.contains('بلاست')) return 'plastic';
    if (t.contains('paper') || t.contains('ورق')) return 'paper';
    if (t.contains('food') || t.contains('طعام') || t.contains('عضوي'))
      return 'food';
    if (t.contains('cloth') || t.contains('ملابس')) return 'cloth';
    if (t.contains('metro') || t.contains('مترو')) return 'metro';
    if (t.contains('bus') || t.contains('باص')) return 'bus';
    if (t.contains('bicycle') || t.contains('دراجة')) return 'bicycle';
    if (t.contains('scooter') || t.contains('سكوتر')) return 'scooter';
    if (t.contains('rvm') || t.contains('تدوير')) return 'rvm';

    return taskName;
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
  }) async {
    try {
      final body = <String, dynamic>{'threshold': threshold};

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

      final response = await http
          .post(
            Uri.parse(_baseUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 60));

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
