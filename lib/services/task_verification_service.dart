// task_verification_service.dart
// Add this file to your Flutter project: lib/services/task_verification_service.dart

import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

class TaskVerificationResult {
  final bool success;
  final int? taskId;
  final String? taskName;
  final String? taskNameAr;
  final double? confidence;
  final String? confidencePercent;
  final bool? verified;
  final bool? matchesExpected;
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
      error: json['error'],
      allPredictions: predictions,
    );
  }

  @override
  String toString() {
    if (!success) return 'Error: $error';
    return 'Task: $taskNameAr, Confidence: $confidencePercent, Verified: $verified';
  }
}

class TaskVerificationService {
static const String _baseUrl = 'https://verify-tasks-188455017517.us-central1.run.app';  
  // أو إذا تستخدمين Firebase Functions:
  // static const String _baseUrl = 'https://us-central1-YOUR_PROJECT.cloudfunctions.net/verifyTask';

  /// Verify task from image file
  /// 
  /// [imageFile] - The captured image file
  /// [expectedTask] - Optional: The expected task name (e.g., 'plastic', 'metro')
  /// [threshold] - Confidence threshold (default 0.7 = 70%)
  static Future<TaskVerificationResult> verifyFromFile(
    File imageFile, {
    String? expectedTask,
    double threshold = 0.7,
  }) async {
    try {
      // Read and encode image
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

  /// Verify task from image URL (Firebase Storage)
  /// 
  /// [imageUrl] - URL to the image in Cloud Storage
  /// [expectedTask] - Optional: The expected task name
  /// [threshold] - Confidence threshold (default 0.7 = 70%)
  static Future<TaskVerificationResult> verifyFromUrl(
    String imageUrl, {
    String? expectedTask,
    double threshold = 0.7,
  }) async {
    return await _sendVerificationRequest(
      imageUrl: imageUrl,
      expectedTask: expectedTask,
      threshold: threshold,
    );
  }

  /// Verify task from base64 encoded image
  static Future<TaskVerificationResult> verifyFromBase64(
    String base64Image, {
    String? expectedTask,
    double threshold = 0.7,
  }) async {
    return await _sendVerificationRequest(
      imageBase64: base64Image,
      expectedTask: expectedTask,
      threshold: threshold,
    );
  }

  static Future<TaskVerificationResult> _sendVerificationRequest({
    String? imageBase64,
    String? imageUrl,
    String? expectedTask,
    double threshold = 0.7,
  }) async {
    try {
      final body = <String, dynamic>{
        'threshold': threshold,
      };

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
          .timeout(const Duration(seconds: 30));

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
      return TaskVerificationResult(
        success: false,
        error: 'فشل الاتصال: $e',
      );
    }
  }

  /// Map task name to expected category
  /// Use this to match your Firebase task data with model predictions
  static String? mapTaskToCategory(Map<String, dynamic> taskData) {
    final title = (taskData['title'] ?? '').toString().toLowerCase();
    final category = (taskData['category'] ?? '').toString().toLowerCase();
    final combined = '$title $category';

    // Transportation tasks
    if (combined.contains('مترو') || combined.contains('قطار')) {
      return 'metro';
    }
    if (combined.contains('باص') || combined.contains('حافلة')) {
      return 'bus';
    }
    if (combined.contains('دراجة') || combined.contains('bicycle')) {
      return 'bicycle';
    }
    if (combined.contains('سكوتر') || combined.contains('scooter')) {
      return 'scooter';
    }

    // Recycling tasks
    if (combined.contains('بلاستيك') || combined.contains('plastic')) {
      return 'plastic';
    }
    if (combined.contains('ورق') || combined.contains('paper')) {
      return 'paper';
    }
    if (combined.contains('ملابس') || combined.contains('قماش') || combined.contains('cloth')) {
      return 'cloth';
    }
    if (combined.contains('طعام') || combined.contains('food') || combined.contains('كومبوست')) {
      return 'food';
    }

    // RVM
    if (combined.contains('rvm') || combined.contains('إعادة') || combined.contains('تدوير')) {
      return 'rvm';
    }

    return null; // Unknown task type
  }
}
