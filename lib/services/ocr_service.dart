import 'dart:io';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class OCRService {
  OCRService._(); // منع إنشاء object

  /// Extract all readable text from an image file
  /// Returns cleaned lowercase text for easier matching
  static Future<String> extractTextFromFile(File imageFile) async {
    try {
      // استخدام TextRecognizer بدون script - يعمل مع جميع اللغات
      final textRecognizer = TextRecognizer();
      final inputImage = InputImage.fromFile(imageFile);

      final RecognizedText recognizedText = await textRecognizer.processImage(
        inputImage,
      );

      // دمج كل النصوص في String واحد
      final buffer = StringBuffer();

      for (final block in recognizedText.blocks) {
        for (final line in block.lines) {
          buffer.write('${line.text} ');
        }
      }

      textRecognizer.close();

      final text = buffer.toString().trim();

      // تنظيف النص وتحويله لحروف صغيرة
      return text
          .replaceAll(RegExp(r'\s+'), ' ') // إزالة المسافات الزائدة
          .toLowerCase();
    } catch (e) {
      print('❌ خطأ في الـ OCR: $e');
      return '';
    }
  }

  /// Check if extracted text contains any keyword from a list
  static bool containsAnyKeyword(String text, List<String> keywords) {
    for (final keyword in keywords) {
      if (text.contains(keyword.toLowerCase())) {
        return true;
      }
    }
    return false;
  }

  /// Debug helper (useful during testing)
  static Future<void> debugPrintExtractedText(File imageFile) async {
    final text = await extractTextFromFile(imageFile);
    // ignore: avoid_print
    print('🧠 OCR TEXT:\n$text');
  }

  static double calculateOCRConfidence({
    required String ocrText,
    required String detectedTask,
    required String? expectedTask,
  }) {
    print('🧮 حساب دقة OCR...');

    // 1. تطابق المهام
    final matches = expectedTask != null && detectedTask == expectedTask;
    final matchScore = matches ? 1.0 : 0.4;

    // 2. طول النص
    final lengthScore = ocrText.length <= 10
        ? 1.0
        : ocrText.length <= 20
        ? 0.9
        : ocrText.length <= 30
        ? 0.8
        : 0.7;

    // 3. كلمات مفتاحية محددة لكل مهمة
    final Map<String, List<String>> taskKeywords = {
      'plastic': [
        'plastic',
        'plast',
        'bottle',
        'bottles',
        'recycl',
        'عبوة',
        'زجاجة',
        'بلاست',
      ],
      'paper': ['paper', 'cardboard', 'ورق', 'كرتون'],
      'food': ['food', 'bread', 'fruit', 'طعام', 'خبز', 'فاكهة'],
      'cloth': ['cloth', 'clothes', 'shirt', 'pants', 'ملابس', 'قميص'],
      'metro': ['metro', 'subway', 'مترو', 'قطار'],
      'bus': ['bus', 'autobus', 'باص', 'حافلة'],
      'bicycle': ['bicycle', 'bike', 'دراجة', 'عجلة'],
      'scooter': ['scooter', 'سكوتر', 'دراجة نارية'],
      'rvm': ['rvm', 'recycling', 'machine', 'آلة', 'تدوير'],
    };

    double keywordScore = 0.3; // الحد الأدنى
    final keywords = taskKeywords[detectedTask] ?? [];
    final lowerText = ocrText.toLowerCase();

    for (final keyword in keywords) {
      if (lowerText.contains(keyword.toLowerCase())) {
        keywordScore = 0.9; // وجدنا كلمة مفتاحية
        break;
      }
    }

    // حساب النتيجة النهائية
    final finalScore =
        (matchScore * 0.6) + (lengthScore * 0.2) + (keywordScore * 0.2);
    final confidence = finalScore.clamp(0.0, 1.0);

    print('   - تطابق المهام: ${matches ? "نعم" : "لا"}');
    print('   - طول النص: ${ocrText.length} حرف');
    print('   - كلمات مفتاحية: ${keywordScore > 0.3 ? "وجدت" : "لم توجد"}');
    print('   - النتيجة النهائية: ${(confidence * 100).toInt()}%');

    return confidence;
  }
}

class OCRTaskMapper {
  /// Map task name to expected category
  static String? mapTaskToCategory(dynamic taskData) {
    try {
      // تحويل taskData إلى Map إذا لم يكن كذلك
      Map<String, dynamic> data;

      if (taskData is Map) {
        // إذا كان Map، نقوم بالتحويل إلى Map<String, dynamic>
        data = taskData.map<String, dynamic>(
          (key, value) => MapEntry(key.toString(), value),
        );
      } else if (taskData is String) {
        // إذا كان String فقط، نستخدمه مباشرة
        final task = taskData.toLowerCase();
        if (task.contains('بلاستيك') || task.contains('plastic'))
          return 'plastic';
        if (task.contains('ورق') || task.contains('paper')) return 'paper';
        if (task.contains('طعام') || task.contains('food')) return 'food';
        if (task.contains('ملابس') || task.contains('cloth')) return 'cloth';
        if (task.contains('مترو') || task.contains('metro')) return 'metro';
        if (task.contains('باص') || task.contains('bus')) return 'bus';
        if (task.contains('دراجة') || task.contains('bicycle'))
          return 'bicycle';
        if (task.contains('سكوتر') || task.contains('scooter'))
          return 'scooter';
        if (task.contains('تدوير') || task.contains('rvm')) return 'rvm';
        return null;
      } else {
        // إذا كان نوع آخر، نعيد null
        return null;
      }

      final title = (data['title'] ?? '').toString().toLowerCase();
      final category = (data['category'] ?? '').toString().toLowerCase();
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
      if (combined.contains('ملابس') ||
          combined.contains('قماش') ||
          combined.contains('cloth')) {
        return 'cloth';
      }
      if (combined.contains('طعام') ||
          combined.contains('food') ||
          combined.contains('كومبوست')) {
        return 'food';
      }

      // RVM
      if (combined.contains('rvm') ||
          combined.contains('إعادة') ||
          combined.contains('تدوير')) {
        return 'rvm';
      }

      return null; // Unknown task type
    } catch (e) {
      print('❌ خطأ في mapTaskToCategory: $e');
      return null;
    }
  }

  static String? mapTextToCategory(String text) {
    print('🔍 تحليل النص: "$text"');

    final t = text.toLowerCase();

    // قائمة الكلمات المفتاحية مع أوزان
    final keywords = [
      {'word': 'plastic', 'category': 'plastic', 'weight': 10},
      {'word': 'بلاستيك', 'category': 'plastic', 'weight': 10},
      {'word': 'بلاست', 'category': 'plastic', 'weight': 8},
      {'word': 'paper', 'category': 'paper', 'weight': 10},
      {'word': 'ورق', 'category': 'paper', 'weight': 10},
      {'word': 'food', 'category': 'food', 'weight': 10},
      {'word': 'طعام', 'category': 'food', 'weight': 10},
      {'word': 'خبز', 'category': 'food', 'weight': 8},
      {'word': 'bread', 'category': 'food', 'weight': 8},
      {'word': 'cloth', 'category': 'cloth', 'weight': 10},
      {'word': 'ملابس', 'category': 'cloth', 'weight': 10},
      {'word': 'قماش', 'category': 'cloth', 'weight': 7},
      {'word': 'metro', 'category': 'metro', 'weight': 10},
      {'word': 'مترو', 'category': 'metro', 'weight': 10},
      {'word': 'bus', 'category': 'bus', 'weight': 10},
      {'word': 'باص', 'category': 'bus', 'weight': 10},
      {'word': 'bicycle', 'category': 'bicycle', 'weight': 10},
      {'word': 'دراجة', 'category': 'bicycle', 'weight': 10},
      {'word': 'scooter', 'category': 'scooter', 'weight': 10},
      {'word': 'سكوتر', 'category': 'scooter', 'weight': 10},
      {'word': 'rvm', 'category': 'rvm', 'weight': 10},
      {'word': 'تدوير', 'category': 'rvm', 'weight': 10},
    ];

    String? bestCategory;
    int highestScore = 0;

    for (final keyword in keywords) {
      final word = keyword['word'] as String;
      final category = keyword['category'] as String;
      final weight = keyword['weight'] as int;

      if (t.contains(word)) {
        print('🎯 وجدت "$word" → $category (+$weight)');

        if (weight > highestScore) {
          highestScore = weight;
          bestCategory = category;
        }
      }
    }

    if (bestCategory != null) {
      print('✅ الفئة المختارة: $bestCategory (نقاط: $highestScore)');
      return bestCategory;
    }

    print('❌ لم أجد أي كلمة مفتاحية');
    return null;
  }

  double _calculateOCRConfidence(
    String ocrText,
    String detectedTask,
    String? expectedTask,
  ) {
    print('🧮 حساب دقة OCR...');

    // 1. تطابق المهام
    final matches = expectedTask != null && detectedTask == expectedTask;
    final matchScore = matches ? 1.0 : 0.4;

    // 2. طول النص (نص أطول يعني ثقة أقل لأنه قد يكون فيه أخطاء)
    final lengthScore = ocrText.length <= 10
        ? 1.0
        : ocrText.length <= 20
        ? 0.9
        : ocrText.length <= 30
        ? 0.8
        : 0.7;

    // 3. كلمات مفتاحية محددة لكل مهمة
    final Map<String, List<String>> taskKeywords = {
      'plastic': [
        'plastic',
        'plast',
        'bottle',
        'bottles',
        'recycl',
        'عبوة',
        'زجاجة',
        'بلاست',
      ],
      'paper': ['paper', 'cardboard', 'ورق', 'كرتون'],
      'food': ['food', 'bread', 'fruit', 'طعام', 'خبز', 'فاكهة'],
      'cloth': ['cloth', 'clothes', 'shirt', 'pants', 'ملابس', 'قميص'],
    };

    double keywordScore = 0.3; // الحد الأدنى
    final keywords = taskKeywords[detectedTask] ?? [];
    final lowerText = ocrText.toLowerCase();

    for (final keyword in keywords) {
      if (lowerText.contains(keyword.toLowerCase())) {
        keywordScore = 0.9; // وجدنا كلمة مفتاحية
        break;
      }
    }

    // حساب النتيجة النهائية
    final finalScore =
        (matchScore * 0.6) + (lengthScore * 0.2) + (keywordScore * 0.2);
    print('   - النتيجة النهائية: ${(finalScore * 100).toInt()}%');

    return finalScore.clamp(0.0, 1.0);
  }
}
