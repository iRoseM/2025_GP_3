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

  /// Map text to category (لتحويل النص المقروء إلى فئة)
  static String? mapTextToCategory(String text) {
    final t = text.toLowerCase();

    if (t.contains('plastic') ||
        t.contains('بلاستيك') ||
        t.contains('بلاستك') ||
        t.contains('زجاجة')) {
      return 'plastic';
    }
    if (t.contains('paper') ||
        t.contains('ورق') ||
        t.contains('كرتون') ||
        t.contains('صحيفة')) {
      return 'paper';
    }
    if (t.contains('food') ||
        t.contains('طعام') ||
        t.contains('عضوي') ||
        t.contains('بقايا')) {
      return 'food';
    }
    if (t.contains('cloth') ||
        t.contains('clothes') ||
        t.contains('ملابس') ||
        t.contains('قماش')) {
      return 'cloth';
    }
    if (t.contains('metro') ||
        t.contains('مترو') ||
        t.contains('قطار') ||
        t.contains('أنفاق')) {
      return 'metro';
    }
    if (t.contains('bus') ||
        t.contains('باص') ||
        t.contains('حافلة') ||
        t.contains('اتوبيس')) {
      return 'bus';
    }
    if (t.contains('bicycle') ||
        t.contains('bike') ||
        t.contains('دراجة') ||
        t.contains('عجلة')) {
      return 'bicycle';
    }
    if (t.contains('scooter') ||
        t.contains('سكوتر') ||
        t.contains('دراجة نارية')) {
      return 'scooter';
    }
    if (t.contains('rvm') ||
        t.contains('recycle') ||
        t.contains('تدوير') ||
        t.contains('إعادة')) {
      return 'rvm';
    }

    return null;
  }
}
