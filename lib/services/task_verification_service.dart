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

  /// 🔹 MAIN METHOD (Vision + OCR fallback)
  static Future<TaskVerificationResult> verifyWithOCRFallback(
    File imageFile, {
    String? expectedTask,
    double visionThreshold = 0.6,
  }) async {
    try {
      _log('🚀 بدء عملية التحقق التلقائي');
      _log('📋 المهمة المتوقعة/المقترحة: $expectedTask');

      // 1️⃣ محاولة Vision API أولاً
      _log('👁️ جاري استدعاء Vision API...');
      final visionResult = await verifyFromFile(
        imageFile,
        expectedTask: expectedTask,
      );

      _log('✅ نتيجة Vision API:');
      _log('   - النجاح: ${visionResult.success}');
      _log('   - المهمة: ${visionResult.taskName}');
      _log('   - الثقة: ${visionResult.confidence}');
      _log('   - تم التحقق: ${visionResult.verified}');

      // إذا كانت نتيجة Vision جيدة بما يكفي، نقبلها
      if (visionResult.success &&
          visionResult.verified == true &&
          visionResult.confidence != null &&
          visionResult.confidence! >= visionThreshold) {
        _log('🎯 تم القبول من Vision API');
        return visionResult.copyWith(
          verificationSource: 'vision',
          extractedText: visionResult.extractedText,
        );
      }

      _log('⚠️  Vision API غير كافي، جاري محاولة OCR...');

      // 2️⃣ محاولة OCR
      _log('🔤 جاري استخراج النص من OCR...');
      final extractedText = await OCRService.extractTextFromFile(imageFile);
      _log('📝 النص المستخرج: "$extractedText"');

      if (extractedText.isEmpty) {
        _log('❌ لم يتم العثور على نص في الصورة');
        return TaskVerificationResult(
          success: false,
          error: 'لا يمكن قراءة النص في الصورة',
          verificationSource: 'ocr',
          extractedText: extractedText,
        );
      }

      // 3️⃣ محاولة التعرف على المهمة من النص
      final ocrTask = OCRTaskMapper.mapTextToCategory(
        extractedText,
      ); // ✅ صح      _log('🗂️ المهمة المقترحة من OCR: $ocrTask');

      // إذا لم يكن هناك مهمة متوقعة، نستخدم المهمة من OCR
      final taskToVerify = expectedTask ?? ocrTask;
      _log('🔍 المهمة للمقارنة: $taskToVerify');
      _log('🔤 النص الخام: "$extractedText"');

      if (taskToVerify == null) {
        _log('❌ لا يمكن تحديد المهمة');
        return TaskVerificationResult(
          success: false,
          error: 'لم يتم التعرف على المهمة',
          verificationSource: 'ocr',
          extractedText: extractedText,
        );
      }

      // 4️⃣ تحقق من تطابق المهمة
      final normalizedTask = _normalizeTaskName(taskToVerify);
      final normalizedOcrTask = _normalizeTaskName(ocrTask);

      _log('🔍 المقارنة:');
      _log('   - المهمة المقترحة: $normalizedOcrTask');
      _log('   - المهمة المتوقعة: $normalizedTask');

      final bool verified;
      if (expectedTask == null) {
        // إذا لم يكن هناك مهمة متوقعة، نقبل المهمة من OCR
        verified = ocrTask != null;
        _log('📌 لا توجد مهمة متوقعة، نقبل المهمة من OCR: $verified');
      } else {
        // إذا كانت هناك مهمة متوقعة، نقارن
        verified =
            normalizedOcrTask != null &&
            normalizedTask != null &&
            normalizedOcrTask == normalizedTask;
        _log('📌 مقارنة مع المهمة المتوقعة: $verified');
      }

      _log('🎯 النتيجة النهائية: $verified');

      return TaskVerificationResult(
        success: verified,
        taskName: ocrTask ?? taskToVerify,
        taskNameAr: _getArabicTaskName(ocrTask ?? taskToVerify),
        confidence: verified ? 0.85 : 0.4,
        confidencePercent: verified ? '85%' : '40%',
        verified: verified,
        matchesExpected: expectedTask != null ? verified : null,
        verificationSource: 'ocr',
        extractedText: extractedText,
      );
    } catch (e, stackTrace) {
      _log('💥 خطأ في verifyWithOCRFallback: $e');
      _log('📋 Stack Trace: $stackTrace');

      return TaskVerificationResult(
        success: false,
        error: 'فشل في عملية التحقق: $e',
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
