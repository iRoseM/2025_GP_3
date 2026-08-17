import 'dart:io';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class OCRService {
  OCRService._(); // منع إنشاء object

  // =============================================
  // 1️⃣ 🗺️ خريطة الفئات والمرادفات
  // =============================================
  static const Map<String, List<String>> taskKeywords = {
    'plastic': [
      'بلاستيك',
      'بلاست',
      'plastic',
      'عبوة',
      'زجاجة',
      'ببسي',
      'قارورة',
      'كيس',
      'اكياس',
      'بلاستك',
    ],
    'paper': [
      'ورق',
      'paper',
      'كرتون',
      'كتب',
      'مجلات',
      'جرائد',
      'صحف',
      'دفاتر',
      'كشكول',
      'carton',
      'cardboard',
    ],
    'food': [
      'طعام',
      'food',
      'بقايا',
      'اكل',
      'خبز',
      'فاكهة',
      'خضار',
      'عضوي',
      'organic',
      'خضروات',
      'فواكه',
      'قمح',
      'ارز',
      'لحوم',
      'دجاج',
      'fish',
      'سمك',
    ],
    'cloth': [
      'ملابس',
      'cloth',
      'قماش',
      'clothes',
      'ثياب',
      'أقمشة',
      'نسيج',
      'fabric',
      'تيشيرت',
      'بنطلون',
      'جينز',
      'شورت',
    ],
    'metro': [
      'مترو',
      'metro',
      'قطار',
      'ميترو',
      'train',
      'subway',
      'محطة',
      'station',
      'الخط',
      'الاخضر',
      'الاحمر',
    ],
    'bus': [
      'باص',
      'bus',
      'حافلة',
      'نقل عام',
      'public transport',
      'اتوبيس',
      'باصات',
      'حافلات',
      'bus station',
      'موقف',
    ],
    'bicycle': [
      'دراجة',
      'bicycle',
      'bike',
      'هوائية',
      'دراجات',
      'cycling',
      'راكب',
      'دراج',
    ],
    'scooter': [
      'سكوتر',
      'scooter',
      'دراجة نارية',
      'motorcycle',
      'سكوت',
      'scoot',
      'electric scooter',
    ],
    'rvm': [
      'rvm',
      'تدوير',
      'recycle',
      'machine',
      'آلة',
      'recycling',
      'reverse vending',
      'recycle machine',
      'اعادة تدوير',
      'اعادة',
      'التدوير',
    ],
  };

  static const Map<String, String> arabicTaskNames = {
    'plastic': 'بلاستيك',
    'paper': 'ورق',
    'food': 'نفايات عضوية',
    'cloth': 'ملابس',
    'metro': 'مترو',
    'bus': 'باص',
    'bicycle': 'دراجة',
    'scooter': 'سكوتر',
    'rvm': 'آلة التدوير',
  };

  static const List<String> stopWords = [
    'في',
    'من',
    'إلى',
    'على',
    'مع',
    'هذا',
    'هذه',
    'ذلك',
    'تلك',
    'كان',
    'كانت',
    'و',
    'أو',
    'ثم',
    'عن',
    'إن',
    'أن',
    'لا',
    'استخدم',
    'استخدام',
    'الوصول',
    'وجهتك',
    'تقليل',
    'الازدحام',
    'الانبعاثات',
    'الناتجة',
    'السيارات',
    'الخاصة',
    'النقل',
    'العام',
    'اعادة',
    'تدوير',
    'جمع',
    'فرز',
    'تنظيف',
    'الحفاظ',
    'على',
    'من',
  ];

  // =============================================
  // 2️⃣ استخراج النص من الصورة
  // =============================================
  static Future<String> extractTextFromFile(File imageFile) async {
    try {
      final textRecognizer = TextRecognizer();
      final inputImage = InputImage.fromFile(imageFile);
      final RecognizedText recognizedText = await textRecognizer.processImage(
        inputImage,
      );

      final buffer = StringBuffer();
      for (final block in recognizedText.blocks) {
        for (final line in block.lines) {
          buffer.write('${line.text} ');
        }
      }

      textRecognizer.close();
      return buffer.toString().trim();
    } catch (e) {
      print('❌ خطأ في الـ OCR: $e');
      return '';
    }
  }

  // =============================================
  // 3️⃣ دوال المساعدة للكلمات المفتاحية
  // =============================================

  /// استخراج الفئة من النص (إذا وجدت)
  static String? extractCategoryFromText(String text) {
    final lowerText = text.toLowerCase();
    for (final entry in taskKeywords.entries) {
      for (final keyword in entry.value) {
        if (lowerText.contains(keyword.toLowerCase())) {
          return entry.key;
        }
      }
    }
    return null;
  }

  /// الحصول على الاسم العربي للفئة
  static String getArabicTaskName(String category) {
    return arabicTaskNames[category] ?? category;
  }

  /// استخراج اسم عربي ذكي من عنوان المهمة
  static String extractArabicTitle(String taskTitle) {
    final lowerTitle = taskTitle.toLowerCase();

    // 1️⃣ ابحث عن كلمة مفتاحية في العنوان
    for (final entry in taskKeywords.entries) {
      for (final keyword in entry.value) {
        if (lowerTitle.contains(keyword.toLowerCase())) {
          return arabicTaskNames[entry.key] ?? entry.key;
        }
      }
    }

    // 2️⃣ إذا ما لقينا، استخرج أول كلمة ذات معنى
    final words = taskTitle.split(RegExp(r'\s+'));
    for (final word in words) {
      if (word.length > 2 &&
          !stopWords.contains(word) &&
          !word.contains(RegExp(r'[a-zA-Z]'))) {
        return word;
      }
    }

    return words.isNotEmpty ? words.first : taskTitle;
  }

  /// التحقق من صحة نتيجة المودل
  static bool isModelResultValid(String? modelTask, String taskTitle) {
    if (modelTask == null) return false;

    final modelLower = modelTask.toLowerCase();
    final titleLower = taskTitle.toLowerCase();

    // هل العنوان يحتوي على أي كلمة من كلمات الفئة؟
    final keywords = taskKeywords[modelLower] ?? [];
    for (final keyword in keywords) {
      if (titleLower.contains(keyword.toLowerCase())) {
        print('✅ المودل منطقي: "$keyword" في العنوان ← $modelTask');
        return true;
      }
    }

    print('⚠️ المودل غير منطقي: قال $modelTask ولكن العنوان "$taskTitle"');
    return false;
  }

  /// هل الصورة تطابق عنوان المهمة؟ (باستخدام الكلمات المباشرة والمرادفات)
  static bool doesImageMatchTask(String extractedText, String taskTitle) {
    if (extractedText.isEmpty) return false;

    final lowerExtracted = extractedText.toLowerCase();
    final lowerTitle = taskTitle.toLowerCase();

    // 1️⃣ أولاً: جرب الكلمات المباشرة من العنوان
    final titleWords = lowerTitle.split(RegExp(r'\s+'));
    for (final word in titleWords) {
      if (word.length > 2 && lowerExtracted.contains(word)) {
        print('✅ تطابق مباشر: "$word"');
        return true;
      }
    }

    // 2️⃣ ثانياً: جرب المرادفات لكل فئة
    for (final entry in taskKeywords.entries) {
      for (final keyword in entry.value) {
        if (lowerTitle.contains(keyword.toLowerCase())) {
          // العنوان فيه كلمة من هذي الفئة
          for (final synonym in entry.value) {
            if (lowerExtracted.contains(synonym.toLowerCase())) {
              print('✅ تطابق مرادف: "$synonym" ← ${entry.key}');
              return true;
            }
          }
        }
      }
    }

    // 3️⃣ ثالثاً: جرب الكلمات الطويلة (أكثر من 3 حروف)
    for (final word in titleWords) {
      if (word.length > 3 && lowerExtracted.contains(word)) {
        print('✅ تطابق كلمة طويلة: "$word"');
        return true;
      }
    }

    return false;
  }

  // =============================================
  // 4️⃣ التحقق الرئيسي من الصورة
  // =============================================

  /// التحقق من الصورة: أي كلمة من العنوان تطابق النص = صح
  static Future<bool> isTaskValidated({
    required File imageFile,
    required String taskTitle,
  }) async {
    print('🔍 التحقق من الصورة...');
    print('📋 عنوان المهمة: "$taskTitle"');

    // 1. استخراج النص من الصورة
    final extractedText = await extractTextFromFile(imageFile);
    print('📸 النص المستخرج: "$extractedText"');

    if (extractedText.isEmpty) {
      print('❌ لا يوجد نص في الصورة');
      return false;
    }

    // 2. التحقق باستخدام الدالة الشاملة
    final isValid = doesImageMatchTask(extractedText, taskTitle);

    if (isValid) {
      print('✅ تم التحقق بنجاح: الصورة تطابق المهمة');
    } else {
      print('❌ فشل التحقق: الصورة لا تطابق المهمة');
    }

    return isValid;
  }

  /// نسخة متقدمة من التحقق مع تفاصيل أكثر
  static Future<Map<String, dynamic>> verifyTaskWithDetails({
    required File imageFile,
    required String taskTitle,
  }) async {
    final extractedText = await extractTextFromFile(imageFile);
    final isValid = doesImageMatchTask(extractedText, taskTitle);
    final matchedWords = <String>[];

    // البحث عن الكلمات المطابقة للعرض
    if (extractedText.isNotEmpty) {
      final lowerExtracted = extractedText.toLowerCase();
      final lowerTitle = taskTitle.toLowerCase();
      final titleWords = lowerTitle.split(RegExp(r'\s+'));

      for (final word in titleWords) {
        if (word.length > 2 && lowerExtracted.contains(word)) {
          matchedWords.add(word);
        }
      }
    }

    return {
      'isValid': isValid,
      'extractedText': extractedText,
      'matchedWords': matchedWords,
      'taskTitle': taskTitle,
      'taskTitleAr': extractArabicTitle(taskTitle),
      'timestamp': DateTime.now().toIso8601String(),
    };
  }
}

// =============================================
// 5️⃣ كلاس للتعامل مع مهام المستخدم من Firestore
// =============================================

/// كلاس للتعامل مع مهام المستخدم من Firestore
class UserTaskValidator {
  /// التحقق من صورة مهمة المستخدم
  static Future<bool> validateUserTaskImage({
    required File imageFile,
    required Map<String, dynamic> userTaskData,
  }) async {
    try {
      // استخراج عنوان المهمة فقط
      final taskTitle = userTaskData['taskTitle']?.toString() ?? '';

      if (taskTitle.isEmpty) {
        print('❌ خطأ: عنوان المهمة غير موجود');
        return false;
      }

      print('✅ التحقق من المهمة: "$taskTitle"');

      // التحقق باستخدام OCR
      return await OCRService.isTaskValidated(
        imageFile: imageFile,
        taskTitle: taskTitle,
      );
    } catch (e) {
      print('❌ خطأ في validateUserTaskImage: $e');
      return false;
    }
  }

  /// نسخة متقدمة مع تفاصيل التحقق
  static Future<Map<String, dynamic>> validateUserTaskWithDetails({
    required File imageFile,
    required Map<String, dynamic> userTaskData,
  }) async {
    try {
      final taskTitle = userTaskData['taskTitle']?.toString() ?? '';
      final taskDescription = userTaskData['taskDescription']?.toString() ?? '';

      final verificationDetails = await OCRService.verifyTaskWithDetails(
        imageFile: imageFile,
        taskTitle: taskTitle,
      );

      return {
        ...verificationDetails,
        'taskDescription': taskDescription,
        'userTaskDocId': userTaskData['userTaskDocId'] ?? '',
        'taskPoints': userTaskData['taskPoints'] ?? 0,
      };
    } catch (e) {
      return {
        'isValid': false,
        'error': e.toString(),
        'timestamp': DateTime.now().toIso8601String(),
      };
    }
  }
}
