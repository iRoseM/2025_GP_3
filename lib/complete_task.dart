import 'dart:io';
import 'dart:math' as math;
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:camera/camera.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'services/map_pick_route.dart';
import 'services/task_verification_service.dart'; // ✅ أضيفي هذا
import '../services/app_colors.dart';
import '../../home.dart';
import 'services/ocr_service.dart';
import 'task.dart';

class CompleteTaskSheet extends StatefulWidget {
  final Map<String, dynamic> taskData;
  final DateTime selectedDay;
  final String userTaskDocId;

  const CompleteTaskSheet({
    super.key,
    required this.taskData,
    required this.selectedDay,
    required this.userTaskDocId,
  });

  @override
  State<CompleteTaskSheet> createState() => _CompleteTaskSheetState();
}

class _CompleteTaskSheetState extends State<CompleteTaskSheet> {
  static const String _localProductTaskId = 'z5MNCTfrWZBkXFHVL9aS';

  bool get _isLocalProductTask {
    final id = (widget.taskData['id'] ?? '').toString().trim().toLowerCase();
    final taskId = (widget.taskData['taskId'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    return id == _localProductTaskId.toLowerCase() ||
        taskId == _localProductTaskId.toLowerCase();
  }

  CameraController? _controller;
  List<CameraDescription>? _cameras;
  final TextEditingController _itemCountCtrl = TextEditingController();

  bool _ready = false;
  bool _openingCamera = false;
  bool _isCapturing = false;
  bool _isUploading = false;
  bool _isCompleted = false;
  bool _isAiApproved(TaskVerificationResult? r) {
    if (r == null) return false;
    if (r.success != true) return false;
    if (r.verified != true) return false;

    final conf = r.confidence ?? 0.0;
    if (conf < 0.70) return false;

    // ✅ استثناء مهمة شراء منتجات محلية (origin_check)
    if (_isLocalProductTask && r.taskName == 'origin_check') {
      // إذا السيرفر قال local ✅ خلاص نعتمده
      return true;
    }

    if (r.verificationSource == 'ocr_smart') {
      return true;
    }

    if (r.verificationSource == 'vision' || r.verificationSource == null) {
      final isLogical = OCRService.isModelResultValid(
        r.taskName,
        widget.taskData['title']?.toString() ?? '',
      );
      return isLogical;
    }

    return false;
  }

  String _dayId(DateTime dt) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)}';
  }

  String _fmtKgLocal(double kg) {
    final v = ((kg * 100).roundToDouble() / 100.0);
    return v.toStringAsFixed(v.truncateToDouble() == v ? 0 : 2);
  }

  String? _inlineError;
  String? _capturedPath;
  double _flashOpacity = 0.0;

  int _currentCameraIndex = 0;
  FlashMode _flashMode = FlashMode.off;

  double _minZoom = 1.0, _maxZoom = 1.0, _zoom = 1.0;
  double _minExposure = 0.0, _maxExposure = 0.0, _exposure = 0.0;

  Position? _startPos;
  GeoPoint? _geoStart, _geoEnd;
  double? _autoDistanceKmComputed;

  LatLng? _manualStart;
  LatLng? _manualEnd;
  double? _manualDistanceKm;

  int? _itemCount;

  // ✅ متغيرات التحقق بالـ AI
  TaskVerificationResult? _verificationResult;
  bool _isVerifying = false;

  Map<String, dynamic> get _calcRequires {
    final v = widget.taskData['calc_requires'];
    return (v is Map)
        ? v.map((k, v) => MapEntry(k.toString(), v))
        : <String, dynamic>{};
  }

  bool get _autoDistance =>
      (_calcRequires['autoDistance'] == true) ||
      (widget.taskData['autoDistance'] == true);

  bool get _isTransportTask {
    final s =
        '${widget.taskData['category'] ?? ''} ${widget.taskData['title'] ?? ''}';
    final kws = [
      'نقل',
      'المواصلات',
      'مترو',
      'ميترو',
      'قطار',
      'باص',
      'حافلة',
      'دراجة',
      'سكوتر',
      'مشياً',
      'مشيا',
    ];
    return kws.any((k) => s.contains(k));
  }

  bool get _requiresItemDialog {
    final mode = (widget.taskData['calcMode'] ?? '')
        .toString()
        .toLowerCase()
        .trim();
    return mode == 'deltaperitem';
  }

  String _yyyyMMdd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';

  double _deg2rad(double deg) => deg * math.pi / 180.0;

  double _haversineKm(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371.0;
    final dLat = _deg2rad(lat2 - lat1);
    final dLon = _deg2rad(lon2 - lon1);
    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_deg2rad(lat1)) *
            math.cos(_deg2rad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return R * c;
  }

  String _friendlyError(Object e) {
    if (e is CameraException) {
      switch (e.code) {
        case 'cameraAccessDenied':
        case 'CameraAccessDenied':
          return 'السماح للكاميرا مرفوض.';
        case 'cameraDisconnected':
          return 'تم فصل الكاميرا.';
        default:
          return 'خطأ في الكاميرا.';
      }
    }
    if (e is FirebaseException) {
      final code = e.code.toLowerCase();
      if (code.contains('permission-denied')) return 'صلاحيات غير كافية.';
      if (code.contains('unauthorized')) return 'غير مُخوّل.';
      if (code.contains('object-not-found')) return 'المسار غير موجود.';
      if (code.contains('not-found')) return 'المورد غير موجود.';
      if (code.contains('quota-exceeded')) return 'تم تجاوز الحصة.';
      if (code.contains('retry-limit-exceeded')) return 'انقطع الاتصال.';
      if (code.contains('unavailable')) return 'الخدمة غير متاحة مؤقتًا.';
      return 'خطأ (${e.code}).';
    }
    final s = e.toString();
    if (s.contains('socket') || s.contains('host')) return 'تحقق من الإنترنت.';
    return 'حدث خطأ غير متوقع.';
  }

  void _showInlineError(String msg) {
    if (!mounted) return;
    setState(() => _inlineError = msg);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _inlineError = null);
    });
  }

  Future<void> showTaskCompletedDialogAndRedirect(BuildContext context) async {
    // تأخير بسيط للتأكد من أن جميع العمليات قد اكتملت
    await Future.delayed(const Duration(milliseconds: 300));

    // عرض الديالوج
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          insetPadding: const EdgeInsets.symmetric(horizontal: 24),
          child: SizedBox(
            width: 340,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset(
                    'assets/img/nameerLove.png',
                    height: 120,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'تم إنجاز المهمة',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.ibmPlexSansArabic(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: appColors.dark,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'أحسنتِ! تم تسجيل إنجازك بنجاح\nوتمت إضافة نقاطك مباشرة',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.ibmPlexSansArabic(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: appColors.dark,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Center(
                    child: SizedBox(
                      width: 140,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: appColors.primary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 10,
                          ),
                        ),
                        onPressed: () async {
                          // 1. إغلاق الديالوج أولاً
                          Navigator.of(dialogContext).pop();

                          // 2. تأخير بسيط قبل الإغلاق والتوجيه
                          await Future.delayed(
                            const Duration(milliseconds: 200),
                          );

                          // 3. التحقق من أن context لا يزال active
                          if (!mounted) return;

                          // 4. إغلاق الـ BottomSheet
                          Navigator.of(context).pop(true);

                          // 5. التوجيه لصفحة المهام باستبدال كل الـ stack
                          Navigator.of(context).pushAndRemoveUntil(
                            MaterialPageRoute(builder: (_) => const taskPage()),
                            (route) => false,
                          );
                        },
                        child: Text(
                          'تم',
                          style: GoogleFonts.ibmPlexSansArabic(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<TaskVerificationResult?> _verifyTaskImage(String imagePath) async {
    if (!mounted) return null;

    setState(() {
      _isVerifying = true;
      _verificationResult = null;
    });

    try {
      // استخراج عنوان المهمة
      final taskTitle = widget.taskData['title']?.toString() ?? '';
      print('🔍 التحقق باستخدام العنوان: "$taskTitle"');
      print('🧾 taskData keys: ${widget.taskData.keys.toList()}');
      print(
        '🧾 id: ${widget.taskData['id']} | taskId: ${widget.taskData['taskId']} | task_id: ${widget.taskData['task_id']}',
      );
      print('🧾 local? $_isLocalProductTask');
      if (_isLocalProductTask) {
        print('🟩 Local product task detected. Calling origin_check...');

        final result = await TaskVerificationService.verifyFromFile(
          File(imagePath),
          threshold: 0.7,
          mode: 'origin_check', // ✅ هذا أهم شي
        );

        if (mounted) {
          setState(() {
            _verificationResult = result;
            _isVerifying = false;
          });
        }

        if (result.verified == true) {
          WidgetsBinding.instance.endOfFrame.then((_) {
            if (mounted) _uploadAndComplete();
          });
        } else {
          _showInlineError('❌ المنتج ليس محلي / لم يتم التأكد');
          WidgetsBinding.instance.endOfFrame.then((_) {
            if (mounted) showTaskFailedDialogAndRedirect(context);
          });
        }

        return result;
      }
      // 1️⃣ ✅ جرب المودل أولاً
      final cloudResult = await _tryCloudModelFirst(imagePath, taskTitle);

      // 2️⃣ استخرج النص من الصورة (للـ OCR)
      final extractedText = await OCRService.extractTextFromFile(
        File(imagePath),
      );
      print('📝 النص المستخرج: "$extractedText"');

      // 3️⃣ تحقق من صحة المودل باستخدام OCRService
      final isModelLogical = OCRService.isModelResultValid(
        cloudResult?.taskName,
        taskTitle,
      );

      final doesImageMatch = OCRService.doesImageMatchTask(
        extractedText,
        taskTitle,
      );
      print('📌 doesImageMatch: $doesImageMatch');

      TaskVerificationResult finalResult;

      // 4️⃣ القرار الذكي
      if (cloudResult != null &&
          cloudResult.success == true &&
          isModelLogical) {
        // ✅ المودل منطقي → نثق فيه
        finalResult = cloudResult.copyWith(
          verificationSource: 'vision', // 👈 أضف هذا!
        );
        print('✅ المودل منطقي، نعتمد نتيجته');
      } else {
        // ⚠️ المودل غير منطقي → نعتمد OCR
        print('⚠️ المودل غير منطقي، نعتمد OCR');
        finalResult = TaskVerificationResult(
          success: doesImageMatch,
          taskName: taskTitle,
          taskNameAr: OCRService.extractArabicTitle(
            taskTitle,
          ), // ✅ استخدام OCRService
          confidence: doesImageMatch ? 0.85 : 0.0,
          confidencePercent: doesImageMatch ? '85%' : '0%',
          verified: doesImageMatch,
          matchesExpected: doesImageMatch,
          verificationSource: 'ocr_smart',
          extractedText: extractedText,
        );
      }

      // 5️⃣ تحديث الحالة
      if (mounted) {
        setState(() {
          _verificationResult = finalResult;
          _isVerifying = false;
        });
      }

      // 6️⃣ إذا كان صحيح، ابدأ الرفع
      if (finalResult.verified == true) {
        print('✅ تم التحقق بنجاح');
        WidgetsBinding.instance.endOfFrame.then((_) {
          if (mounted) _uploadAndComplete();
        });
      } else {
        _showInlineError('❌ الصورة غير مطابقة للمهمة');

        // ✅ أضيفي هذا - يظهر popup نمّر زعلان
        WidgetsBinding.instance.endOfFrame.then((_) {
          if (mounted) showTaskFailedDialogAndRedirect(context);
        });
      }

      return finalResult;
    } catch (e) {
      print('❌ خطأ: $e');
      if (mounted) {
        setState(() => _isVerifying = false);
        _showInlineError('❌ فشل التحقق من الصورة');
      }
      return TaskVerificationResult(
        success: false,
        error: 'فشل التحقق: $e',
        verificationSource: 'system',
      );
    }
  }

  // دالة مساعدة لعرض جزء من العنوان في رسالة الخطأ
  // ✅ استخدم هذا بدل _extractMeaningfulTitle
  String _getDisplayTaskName(TaskVerificationResult? result, String taskTitle) {
    if (result?.taskNameAr != null && result!.taskNameAr!.isNotEmpty) {
      return result.taskNameAr!;
    }
    // استخدام دالة OCRService الذكية
    return OCRService.extractArabicTitle(taskTitle);
  }

  // 🗑️ احذف _extractMeaningfulTitle بالكامل
  // 🗑️ احذف _stopWords (موجودة في OCRService)
  // 🗑️ احذف _getArabicTaskName (موجودة في OCRService)
  Future<TaskVerificationResult?> _tryCloudModelFirst(
    String imagePath,
    String taskTitle,
  ) async {
    print('🔵 === استدعاء مودل Cloud Run ===');

    try {
      final modelResult = await TaskVerificationService.verifyFromFile(
        File(imagePath),
        expectedTask: taskTitle,
        threshold: 0.7,
      );

      // 🔴 أضف هذا - لازم تشوف النتيجة!
      print('📥 نتيجة Cloud Run:');
      print('   - Success: ${modelResult.success}');
      print('   - Verified: ${modelResult.verified}');
      print('   - Confidence: ${modelResult.confidence}');
      print('   - Task: ${modelResult.taskName}');
      print('   - Error: ${modelResult.error}');

      return modelResult;
    } catch (e, stack) {
      print('❌ خطأ في Cloud Run: $e');
      print('📋 Stack: $stack');
      return null;
    }
  }

  Future<void> _uploadAndComplete() async {
    print('🚨🚨🚨 دخلنا _uploadAndComplete 🚨🚨🚨');

    // 1) التحقق من حالة الرفع والتحقق
    print('📌 _isUploading: $_isUploading, _isVerifying: $_isVerifying');
    if (_isUploading || _isVerifying) {
      print('⚠️ العملية جارية بالفعل');
      return;
    }

    // 2) التأكد من وجود صورة
    print('📌 _capturedPath: $_capturedPath');
    if (_capturedPath == null) {
      _showInlineError('لم يتم التقاط صورة');
      print('❌ لا توجد صورة');
      return;
    }

    // 3) التحقق من صحة نتيجة الـ AI
    print('📌 _verificationResult?.verified: ${_verificationResult?.verified}');
    print('📌 _isAiApproved: ${_isAiApproved(_verificationResult)}');
    if (!_isAiApproved(_verificationResult)) {
      _showInlineError('لم يتم اعتماد الصورة. أعد الالتقاط.');
      print('❌ الصورة غير معتمدة');
      if (mounted) {
        WidgetsBinding.instance.endOfFrame.then((_) {
          if (mounted) showTaskFailedDialogAndRedirect(context);
        });
      }
      return;
    }

    print('🚀 بدء عملية الرفع التلقائي...');

    // 4) الحصول على بيانات المهمة
    final task = widget.taskData;
    final pts = (task['points'] ?? 0) as int;
    final taskId = task['id'] as String?;

    // 5) التحقق من عدد العناصر إذا كانت المهمة deltaperitem
    int? safeItems = _itemCount;
    final mode = (task['calcMode'] ?? '').toString().toLowerCase();

    if (mode == 'deltaperitem' && (safeItems == null || safeItems <= 0)) {
      print('📦 طلب عدد العناصر...');
      await _promptForItemCountIfNeeded();
      safeItems = _itemCount;
      if (safeItems == null || safeItems <= 0) {
        _showInlineError('يرجى إدخال عدد العناصر.');
        return;
      }
    }

    // 6) بدء عملية الرفع
    if (!mounted) return;
    setState(() {
      _isUploading = true;
      _isVerifying = false;
    });

    try {
      print('📐 حساب البيانات الإضافية...');

      // 7) حساب المسافة إذا كانت المهمة تتطلب ذلك
      final isDistanceMode = mode == 'perkm' || mode == 'deltaperkm';
      double? pickedKm;

      if (isDistanceMode) {
        print('📍 حساب المسافة...');
        final manualKm = _manualDistanceKm;
        await _captureEndAndComputeDistance();
        double? straightKm;
        if (_autoDistanceKmComputed != null &&
            _autoDistanceKmComputed!.isFinite &&
            _autoDistanceKmComputed! > 0) {
          straightKm = double.parse(
            _autoDistanceKmComputed!.toStringAsFixed(3),
          );
        }
        if (manualKm != null && manualKm > 0) {
          pickedKm = manualKm;
        } else if (straightKm != null && straightKm > 0) {
          pickedKm = straightKm;
        }

        final askDistanceKm = task['askDistanceKm'] == true;
        final defaultKmOnSubmit = (task['defaultKmOnSubmit'] is num)
            ? (task['defaultKmOnSubmit'] as num).toDouble()
            : null;
        if (pickedKm == null && askDistanceKm && defaultKmOnSubmit != null) {
          pickedKm = defaultKmOnSubmit;
        }

        double? minKm, maxKm;
        final mk = task['minKm'];
        final xk = task['maxKm'];
        if (mk is num) minKm = mk.toDouble();
        if (xk is num) maxKm = xk.toDouble();
        if (pickedKm != null && pickedKm > 0) {
          final clamped = pickedKm.clamp(minKm ?? 0.2, maxKm ?? 50.0) as num;
          pickedKm = double.parse(clamped.toStringAsFixed(3));
        }

        if (_manualStart != null && _manualEnd != null) {
          _geoStart = GeoPoint(_manualStart!.latitude, _manualStart!.longitude);
          _geoEnd = GeoPoint(_manualEnd!.latitude, _manualEnd!.longitude);
        }
      }

      // 8) حساب الكربون المُوفر
      print('🌿 حساب الكربون الموفر...');
      double? carbonSaved;
      final efId =
          (task['ef_ref'] ??
                  task['efRef'] ??
                  task['emissionFactorRef'] ??
                  task['emission_factor_ref'])
              ?.toString();
      final valueFieldFromTask = (task['ef_valueField'] ?? task['valueField'])
          ?.toString();
      if (efId != null && efId.isNotEmpty) {
        final saved = await _computeCarbonSavedFlexible(
          efIdFromTask: efId,
          km: pickedKm,
          items: safeItems,
          valueFieldFromTask: valueFieldFromTask,
        );
        if (saved.isFinite) {
          carbonSaved = double.parse(saved.toStringAsFixed(3));
        }
      }

      print('☁️ بدء رفع الملف...');

      // 9) رفع الملف وإكمال المهمة
      await _createSubmissionAndAutoApprove(
        localPath: _capturedPath!,
        taskPoints: pts,
        taskId: taskId,
        distanceKm: pickedKm,
        carbonSaved: carbonSaved,
        itemCount: safeItems,
      );

      print('✅ الرفع والإنجاز تم بنجاح!');

      setState(() {
        _isCompleted = true;
      });

      // 10) عرض شاشة النجاح والتوجيه
      if (!mounted) return;
      await showTaskCompletedDialogAndRedirect(context);

      // 11) تنظيف وحذف الصورة المؤقتة
      try {
        if (_capturedPath != null) {
          final f = File(_capturedPath!);
          if (await f.exists()) await f.delete();
        }
      } catch (_) {}

      // 12) إغلاق البوتوم شيت
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e, stackTrace) {
      print('❌ خطأ في _uploadAndComplete: $e');
      print('📋 Stack trace: $stackTrace');

      if (!mounted) return;

      String errorMessage = 'حدث خطأ أثناء إكمال المهمة';

      if (e.toString().contains('FirebaseException') &&
          e.toString().contains('403')) {
        errorMessage = 'خطأ في صلاحيات التطبيق. حاول مرة أخرى.';
      } else if (e.toString().contains('Too many attempts')) {
        errorMessage = 'محاولات كثيرة جداً. انتظر قليلاً وحاول مرة أخرى.';
      } else if (e.toString().contains('App attestation failed')) {
        errorMessage = 'خطأ في التحقق من التطبيق. تأكد من إعدادات Firebase.';
      } else if (e.toString().contains('network') ||
          e.toString().contains('اتصال')) {
        errorMessage = 'مشكلة في الاتصال بالإنترنت. تحقق من اتصالك.';
      } else if (e.toString().contains('timeout') ||
          e.toString().contains('مهلة')) {
        errorMessage = 'انتهت مهلة الاتصال. حاول مرة أخرى.';
      }

      _showInlineError(errorMessage);

      if (mounted) {
        setState(() {
          _isUploading = false;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
        });
      }
    }
  }

  /// دالة للحصول على الاسم العربي للمهمة
  String? _getArabicTaskName(String? taskName) {
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

  Future<void> _ensureLocationPermission() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        perm = await Geolocator.requestPermission();
      }
    } catch (_) {}
  }

  Future<void> _captureStartIfNeeded() async {
    if (!(_autoDistance || _isTransportTask)) return;
    try {
      await _ensureLocationPermission();
      final p = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      _startPos = p;
      _geoStart = GeoPoint(p.latitude, p.longitude);
    } catch (_) {}
  }

  Future<void> _captureEndAndComputeDistance() async {
    if (!(_autoDistance || _isTransportTask)) return;
    try {
      await _ensureLocationPermission();
      final end = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      _geoEnd = GeoPoint(end.latitude, end.longitude);
      final start = _startPos ?? end;
      final km = _haversineKm(
        start.latitude,
        start.longitude,
        end.latitude,
        end.longitude,
      );
      _autoDistanceKmComputed = km;
      if (mounted) setState(() {});
    } catch (_) {}
  }

  static const String _kEfCollection = 'emissionFactors';

  double? _asDouble(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v.trim());
    return null;
  }

  int? _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v.trim());
    return null;
  }

  Future<Map<String, dynamic>?> _getEfDoc(String id) async {
    if (id.isEmpty) return null;
    final doc = await FirebaseFirestore.instance
        .collection(_kEfCollection)
        .doc(id)
        .get();
    return doc.data();
  }

  Future<double?> _getEfPerUnit(String id, {String? valueFieldFromTask}) async {
    final d = await _getEfDoc(id);
    if (d == null) return null;

    if (valueFieldFromTask != null && valueFieldFromTask.isNotEmpty) {
      final v = _asDouble(d[valueFieldFromTask]);
      if (v != null) return v;
    }
    final vfInDoc = d['valueField'] ?? d['efValueField'];
    if (vfInDoc is String && vfInDoc.isNotEmpty) {
      final v = _asDouble(d[vfInDoc]);
      if (v != null) return v;
    }
    final candidates = [
      'ef_kgco2_per_unit',
      'ef_kgco2_per_item',
      'value',
      'kgPerItem',
      'perItem',
      'kgPerKm',
      'perKm',
      'co2PerKm',
      'co2_per_km',
      'factor',
    ];
    for (final k in candidates) {
      final v = _asDouble(d[k]);
      if (v != null) return v;
    }
    return null;
  }

  Future<double> _computeCarbonSavedFlexible({
    required String efIdFromTask,
    double? km,
    int? items,
    String? valueFieldFromTask,
  }) async {
    final efDoc = await _getEfDoc(efIdFromTask) ?? {};
    final taskCalcMode = (widget.taskData['calcMode'] ?? '').toString().trim();
    final efCalcMode = (efDoc['calcMode'] ?? '').toString().trim();
    final rawMode = (taskCalcMode.isNotEmpty ? taskCalcMode : efCalcMode);
    final calcMode = rawMode.toLowerCase();

    final baseRef =
        (widget.taskData['baselineFactorRef'] ?? efDoc['baselineFactorRef'])
            ?.toString();
    final actRef =
        (widget.taskData['actualFactorRef'] ?? efDoc['actualFactorRef'])
            ?.toString();

    if (calcMode == 'deltaperkm' && km != null && km > 0) {
      final baseline = baseRef != null
          ? await _getEfPerUnit(baseRef, valueFieldFromTask: valueFieldFromTask)
          : null;
      double? actual = await _getEfPerUnit(
        efIdFromTask,
        valueFieldFromTask: valueFieldFromTask,
      );
      if ((actual == null || actual == 0.0) && actRef != null) {
        actual = await _getEfPerUnit(
          actRef,
          valueFieldFromTask: valueFieldFromTask,
        );
      }
      final delta = ((baseline ?? 0.0) - (actual ?? 0.0));
      final res = (delta > 0 ? delta : 0.0) * km;
      return res;
    }

    if (calcMode == 'deltaperitem' && items != null && items > 0) {
      const defaultField = 'ef_kgco2_per_unit';

      final baseline = baseRef != null
          ? await _getEfPerUnit(
              baseRef,
              valueFieldFromTask: valueFieldFromTask ?? defaultField,
            )
          : null;

      double? actual = await _getEfPerUnit(
        efIdFromTask,
        valueFieldFromTask: valueFieldFromTask ?? defaultField,
      );

      if ((actual == null || actual == 0.0) && actRef != null) {
        actual = await _getEfPerUnit(
          actRef,
          valueFieldFromTask: valueFieldFromTask ?? defaultField,
        );
      }

      if (baseline == null && actual == null) return 0.0;

      final delta = ((baseline ?? 0.0) - (actual ?? 0.0));
      final perItem = delta > 0 ? delta : 0.0;
      final res = perItem * items;
      return res;
    }

    return 0.0;
  }

  Future<XFile?> _safeTakePicture() async {
    if (_controller == null || !_controller!.value.isInitialized) {
      _showInlineError('الكاميرا غير جاهزة.');
      return null;
    }
    if (_controller!.value.isTakingPicture) return null;

    try {
      return await _controller!.takePicture();
    } on CameraException catch (e) {
      try {
        await Future.delayed(const Duration(milliseconds: 150));
        if (!_controller!.value.isInitialized ||
            _controller!.value.isTakingPicture) {
          return null;
        }
        return await _controller!.takePicture();
      } catch (_) {
        _showInlineError(_friendlyError(e));
        return null;
      }
    } catch (e) {
      _showInlineError(_friendlyError(e));
      return null;
    }
  }

  Future<void> _createSubmissionAndAutoApprove({
    required String localPath,
    required int taskPoints,
    String? taskId,
    double? distanceKm,
    double? carbonSaved,
    int? itemCount,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('يرجى تسجيل الدخول.');

    print('👤 المستخدم: ${user.uid}');
    print('📦 بدء عملية الإنجاز...');

    try {
      final file = File(localPath);
      final uid = user.uid;
      final dayKey = _yyyyMMdd(widget.selectedDay);
      final basePath = 'submissions/$uid/${dayKey}_${widget.userTaskDocId}';
      final name = DateTime.now().millisecondsSinceEpoch.toString();

      final storage = FirebaseStorage.instance;
      final storageRef = storage.ref('$basePath/$name.jpg');

      print('🔼 رفع الصورة إلى: $basePath/$name.jpg');

      await storageRef.putFile(
        file,
        SettableMetadata(contentType: 'image/jpeg'),
      );

      final downloadUrl = await storageRef.getDownloadURL();
      print('🔗 رابط الصورة: $downloadUrl');

      final double carbonForStore =
          (carbonSaved != null && carbonSaved.isFinite)
          ? double.parse(carbonSaved.toStringAsFixed(3))
          : 0.0;

      final firestore = FirebaseFirestore.instance;

      final usersRef = firestore.collection('users').doc(uid);
      final utRef = firestore.collection('userTasks').doc(widget.userTaskDocId);
      final subRef = firestore.collection('submissions').doc();

      final todayId = _dayId(DateTime.now());
      final dayMarkRef = firestore
          .collection('users')
          .doc(uid)
          .collection('dayMarks')
          .doc(todayId);
      final dailyTaskRef = firestore
          .collection('dailyTasks')
          .doc(uid)
          .collection('tasks')
          .doc(_dayId(widget.selectedDay));
      final taskTitle = (widget.taskData['title'] ?? '').toString();

      print('📝 تجهيز بيانات Firestore...');

      /// ⭐ تأكد من وجود user doc
      await usersRef.set({
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // ========== أولاً: قراءة userTask خارج الترانزاكشن ==========
      print('📖 قراءة userTask...');
      final utSnapshot = await utRef.get();

      String currentStatus = 'pending';

      if (utSnapshot.exists) {
        final ut = utSnapshot.data() as Map<String, dynamic>;
        currentStatus = (ut['status'] as String?) ?? 'pending';
      }
      print('📊 حالة المهمة الحالية: $currentStatus');

      // ========== ثانياً: الترانزاكشن للكتابة فقط ==========
      await firestore.runTransaction((trx) async {
        print('🔄 بدء ترانزاكشن الكتابة...');

        /// submission
        trx.set(subRef, {
          'userId': uid,
          'userTaskDocId': widget.userTaskDocId,
          'taskId': taskId ?? '',
          'taskTitle': taskTitle,
          'taskPoints': taskPoints,
          'status': 'approved',
          'imageUrls': [downloadUrl],
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          'carbonSaved': carbonForStore,
          if (distanceKm != null) 'distanceKm': distanceKm,
          if (itemCount != null) 'itemCount': itemCount,
          if (_geoStart != null) 'geoStart': _geoStart,
          if (_geoEnd != null) 'geoEnd': _geoEnd,
        }, SetOptions(merge: true));

        /// update userTask
        trx.set(utRef, {
          'userId': uid,
          'status': 'completed',
          'completedAt': FieldValue.serverTimestamp(),
          'taskPoints': taskPoints,
          'taskTitle': taskTitle,
          'carbonSaved': carbonForStore,
          'evidence': {
            'type': 'photo',
            'url': downloadUrl,
            'storagePath': storageRef.fullPath,
          },
          if (distanceKm != null) 'distanceKm': distanceKm,
          if (itemCount != null) 'itemCount': itemCount,
          if (_geoStart != null) 'geoStart': _geoStart,
          if (_geoEnd != null) 'geoEnd': _geoEnd,
        }, SetOptions(merge: true));

        /// تحديث نقاط المستخدم
        if (currentStatus != 'completed' && taskPoints > 0) {
          trx.set(usersRef, {
            'points': FieldValue.increment(taskPoints),
            'completedTask': FieldValue.increment(1),
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }

        /// history
        final historyRef = firestore
            .collection('users')
            .doc(uid)
            .collection('history')
            .doc();

        trx.set(historyRef, {
          'type': 'task_approved',
          'submissionId': subRef.id,
          'points': taskPoints,
          'taskTitle': taskTitle,
          'carbonSaved': carbonForStore,
          'at': FieldValue.serverTimestamp(),
        });

        /// تحديث الكربون
        trx.set(usersRef, {
          'lastCarbonUpdateAt': FieldValue.serverTimestamp(),
          if (carbonForStore > 0)
            'totalCarbonSaved': FieldValue.increment(carbonForStore),
        }, SetOptions(merge: true));
        trx.set(dailyTaskRef, {
          'status': 'completed',
          'completedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        /// day marks
        trx.set(dayMarkRef, {
          'count': FieldValue.increment(1),
          'lastAt': FieldValue.serverTimestamp(),
          'userId': uid,
        }, SetOptions(merge: true));

        print('✅ ترانزاكشن الكتابة تم');
      });

      try {
        await StreakService.updateStreakOnTaskCompletion();
      } catch (_) {}

      print('🎉 المهمة اكتملت بنجاح');
    } catch (e, s) {
      print('❌ خطأ في _createSubmissionAndAutoApprove: $e');
      print('📋 Stack trace: $s');
      rethrow;
    }
  }

  Future<void> _openCamera({int? index}) async {
    if (_openingCamera) return;
    if (!mounted) return;

    setState(() {
      _openingCamera = true;
      _capturedPath = null;
      _ready = false;
      _verificationResult = null; // ✅ إعادة تعيين نتيجة التحقق
      _isCompleted = false;
    });

    try {
      try {
        await _controller?.dispose();
      } catch (_) {}
      _controller = null;

      await Future.delayed(const Duration(milliseconds: 50));

      _cameras ??= await availableCameras();
      if (_cameras == null || _cameras!.isEmpty) {
        throw CameraException('NoCamera', 'لا توجد كاميرا متاحة.');
      }

      if (index != null) {
        _currentCameraIndex = index.clamp(0, _cameras!.length - 1);
      }

      final description = _cameras![_currentCameraIndex];
      final controller = CameraController(
        description,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await controller.initialize();

      final minZoom = await controller.getMinZoomLevel();
      final maxZoom = await controller.getMaxZoomLevel();
      final minExposure = await controller.getMinExposureOffset();
      final maxExposure = await controller.getMaxExposureOffset();

      _minZoom = minZoom;
      _maxZoom = maxZoom;
      _zoom = _zoom.clamp(_minZoom, _maxZoom);
      _minExposure = minExposure;
      _maxExposure = maxExposure;
      _exposure = _exposure.clamp(_minExposure, _maxExposure);

      await controller.setFlashMode(_flashMode);
      await controller.setZoomLevel(_zoom);
      await controller.setExposureOffset(_exposure);

      if (!mounted) {
        await controller.dispose();
        return;
      }

      _controller = controller;
      setState(() => _ready = true);
    } catch (e) {
      _showInlineError(_friendlyError(e));
    } finally {
      if (mounted) setState(() => _openingCamera = false);
    }
  }

  Future<void> _switchCamera() async {
    if ((_cameras?.length ?? 0) < 2) {
      _showInlineError('لا توجد كاميرا أخرى.');
      return;
    }
    final next = (_currentCameraIndex + 1) % _cameras!.length;
    await _openCamera(index: next);
  }

  Future<void> _cycleFlash() async {
    if (!(_controller?.value.isInitialized ?? false)) return;
    switch (_flashMode) {
      case FlashMode.off:
        _flashMode = FlashMode.auto;
        break;
      case FlashMode.auto:
        _flashMode = FlashMode.always;
        break;
      case FlashMode.always:
        _flashMode = FlashMode.torch;
        break;
      case FlashMode.torch:
        _flashMode = FlashMode.off;
        break;
    }
    try {
      await _controller!.setFlashMode(_flashMode);
      if (mounted) setState(() {});
    } catch (e) {
      _showInlineError(_friendlyError(e));
    }
  }

  Future<void> _setZoom(double value) async {
    if (!(_controller?.value.isInitialized ?? false)) return;
    _zoom = value.clamp(_minZoom, _maxZoom);
    try {
      await _controller!.setZoomLevel(_zoom);
      if (mounted) setState(() {});
    } catch (_) {
      _showInlineError('تعذر ضبط التقريب.');
    }
  }

  Future<void> _setExposure(double value) async {
    if (!(_controller?.value.isInitialized ?? false)) return;
    _exposure = value.clamp(_minExposure, _maxExposure);
    try {
      await _controller!.setExposureOffset(_exposure);
      if (mounted) setState(() {});
    } catch (_) {
      _showInlineError('تعذر ضبط التعريض.');
    }
  }

  Future<void> _setFocusAndExposurePoint(
    TapDownDetails d,
    Size previewSize,
  ) async {
    if (!(_controller?.value.isInitialized ?? false)) return;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final localPos = box.globalToLocal(d.globalPosition);

    final nx = (localPos.dx / previewSize.width).clamp(0.0, 1.0);
    final ny = (localPos.dy / previewSize.height).clamp(0.0, 1.0);
    try {
      await _controller!.setFocusPoint(Offset(nx, ny));
      await _controller!.setExposurePoint(Offset(nx, ny));
      _showInlineError('تم التركيز.');
    } catch (_) {
      _showInlineError('تعذر التركيز هنا.');
    }
  }

  @override
  void initState() {
    super.initState();
    if (_autoDistance || _isTransportTask) {
      _captureStartIfNeeded();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    _itemCountCtrl.dispose();
    super.dispose();
  }

  Future<void> _startFlowForTransportTask() async {
    final MapRoutePickResult? res =
        await Navigator.of(
          context,
          rootNavigator: true,
        ).push<MapRoutePickResult>(
          MaterialPageRoute(
            builder: (_) => MapPickRoutePage(
              initialStart: _manualStart,
              initialEnd: _manualEnd,
            ),
            fullscreenDialog: true,
          ),
        );

    if (!mounted || res == null) return;

    setState(() {
      _manualStart = res.start;
      _manualEnd = res.end;
      _manualDistanceKm = _haversineKm(
        res.start.latitude,
        res.start.longitude,
        res.end.latitude,
        res.end.longitude,
      );
      _geoStart = GeoPoint(_manualStart!.latitude, _manualStart!.longitude);
      _geoEnd = GeoPoint(_manualEnd!.latitude, _manualEnd!.longitude);
    });
    await Future.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _openCamera();
      }
    });
  }

  Future<void> _promptForItemCountIfNeeded() async {
    if (!_requiresItemDialog) return;

    final minItems = _asInt(widget.taskData['minItems']) ?? 1;
    final maxItems = _asInt(widget.taskData['maxItems']) ?? 999;

    int clamp(int v) => v.clamp(minItems, maxItems);

    final def = (_itemCount != null && _itemCount! > 0)
        ? _itemCount!
        : (_asInt(widget.taskData['defaultItems']) ?? minItems);

    _itemCountCtrl.text = def.toString();

    final result = await showGeneralDialog<int>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'items',
      barrierColor: Colors.black54,
      useRootNavigator: true,
      pageBuilder: (_, __, ___) => const SizedBox.shrink(),
      transitionDuration: const Duration(milliseconds: 180),
      transitionBuilder: (ctx, anim, _, __child) {
        return Transform.scale(
          scale: 0.95 + 0.05 * anim.value,
          child: Opacity(
            opacity: anim.value,
            child: Center(
              child: Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.format_list_numbered,
                              color: appColors.primary,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'عدد العناصر المنجزة',
                              style: GoogleFonts.ibmPlexSansArabic(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: appColors.dark,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            _counterButton(
                              icon: Icons.remove_rounded,
                              onTap: () {
                                final cur = _asInt(_itemCountCtrl.text) ?? def;
                                final next = clamp(cur - 1);
                                _itemCountCtrl.text = next.toString();
                                setState(() {});
                              },
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextField(
                                controller: _itemCountCtrl,
                                keyboardType:
                                    const TextInputType.numberWithOptions(),
                                textAlign: TextAlign.center,
                                decoration: InputDecoration(
                                  contentPadding: const EdgeInsets.symmetric(
                                    vertical: 10,
                                    horizontal: 12,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  hintText: '$def',
                                ),
                                onChanged: (_) => setState(() {}),
                              ),
                            ),
                            const SizedBox(width: 12),
                            _counterButton(
                              icon: Icons.add_rounded,
                              onTap: () {
                                final cur = _asInt(_itemCountCtrl.text) ?? def;
                                final next = clamp(cur + 1);
                                _itemCountCtrl.text = next.toString();
                                setState(() {});
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'الحد الأدنى: $minItems  •  الأقصى: $maxItems',
                            style: GoogleFonts.ibmPlexSansArabic(
                              fontSize: 12.5,
                              color: Colors.black54,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => Navigator.of(ctx).pop(null),
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(
                                    color: appColors.primary,
                                    width: 2,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 10,
                                  ),
                                ),
                                child: Text(
                                  'إلغاء',
                                  style: GoogleFonts.ibmPlexSansArabic(
                                    color: appColors.primary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: () {
                                  final raw = _asInt(_itemCountCtrl.text);
                                  if (raw == null || raw <= 0) {
                                    _showInlineError('أدخل عددًا صحيحًا.');
                                    return;
                                  }
                                  final safe = clamp(raw);
                                  _itemCountCtrl.text = safe.toString();
                                  Navigator.of(ctx).pop(safe);
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: appColors.primary,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                ),
                                child: Text(
                                  'حفظ',
                                  style: GoogleFonts.ibmPlexSansArabic(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    if (!mounted) return;

    if (result != null && result > 0) {
      setState(() {
        _itemCount = clamp(result);
      });
    }
  }

  // ✅ ودجت عرض نتيجة التحقق بالـ AI
  Widget _buildVerificationResult() {
    if (_verificationResult == null && !_isVerifying) {
      return const SizedBox.shrink();
    }

    if (_isVerifying) {
      return Container(
        padding: const EdgeInsets.all(12),
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.blue.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.blue.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Text(
              'جاري التحقق من الصورة...',
              style: GoogleFonts.ibmPlexSansArabic(
                fontWeight: FontWeight.w600,
                color: Colors.blue,
              ),
            ),
          ],
        ),
      );
    }

    // ✅ إذا كان صحيح → ما نعرض شيء (خلاص)
    if (_verificationResult!.verified == true) {
      return const SizedBox.shrink();
    }

    // ❌ إذا كان خطأ → نعرض المربع البرتقالي فقط
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning, color: Colors.orange, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'الصورة غير مطابقة',
                  style: GoogleFonts.ibmPlexSansArabic(
                    fontWeight: FontWeight.w600,
                    color: Colors.orange,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'يرجى إعادة التقاط صورة أوضح للمهمة',
                  style: GoogleFonts.ibmPlexSansArabic(
                    fontSize: 13,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final task = widget.taskData;
    final title = task['title'] ?? 'مهمة غير معروفة';
    final desc = task['description'] ?? '';
    final pts = (task['points'] ?? 0) as int;
    final taskId = task['id'] as String?;
    final requiresPhotoExact = true;
    final isTransport = (_autoDistance || _isTransportTask);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: DraggableScrollableSheet(
        initialChildSize: 0.92,
        minChildSize: 0.6,
        maxChildSize: 0.98,
        expand: false,
        builder: (context, scrollController) {
          return Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: SingleChildScrollView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 44,
                      height: 5,
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Colors.black12,
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  Text(
                    'إتمام المهمة',
                    style: GoogleFonts.ibmPlexSansArabic(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: appColors.dark,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    title,
                    style: GoogleFonts.ibmPlexSansArabic(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: appColors.primary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(
                        Icons.star_border,
                        color: appColors.primary,
                        size: 20,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '$pts نقطة',
                        style: GoogleFonts.ibmPlexSansArabic(
                          fontWeight: FontWeight.w700,
                          color: appColors.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    desc,
                    style: GoogleFonts.ibmPlexSansArabic(
                      fontSize: 14,
                      height: 1.7,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (!_ready) _buildPhotoInstructions(),
                  if (!_ready) const SizedBox(height: 16),
                  if (requiresPhotoExact && !isTransport && !_ready)
                    _gradientButton(
                      label: 'ابدأ التصوير',
                      icon: Icons.camera_alt,
                      onTap: _openingCamera ? null : () => _openCamera(),
                      loading: _openingCamera,
                    ),
                  if (requiresPhotoExact && isTransport && !_ready) ...[
                    _gradientButton(
                      label: 'ابدأ',
                      icon: Icons.play_arrow_rounded,
                      onTap: () => _startFlowForTransportTask(),
                    ),
                    if (_manualDistanceKm != null) ...[
                      const SizedBox(height: 10),
                      _hintCard(
                        'المسار المحدد: ${_manualDistanceKm!.toStringAsFixed(2)} كم\nاضغط "ابدأ" مرة أخرى لفتح الكاميرا إذا رغبت بتعديل المسار.',
                      ),
                    ],
                  ],
                  const SizedBox(height: 16),
                  if (_ready)
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      child: SizedBox(
                        height: 420,
                        child: LayoutBuilder(
                          builder: (context, cons) {
                            final w = cons.maxWidth;
                            final h = cons.maxHeight;
                            return Stack(
                              alignment: Alignment.center,
                              children: [
                                Positioned.fill(
                                  child: _capturedPath != null
                                      ? ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                          child: Image.file(
                                            File(_capturedPath!),
                                            fit: BoxFit.cover,
                                          ),
                                        )
                                      : ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                          child: FittedBox(
                                            fit: BoxFit.cover,
                                            child: SizedBox(
                                              width:
                                                  _controller!
                                                      .value
                                                      .previewSize
                                                      ?.height ??
                                                  w,
                                              height:
                                                  _controller!
                                                      .value
                                                      .previewSize
                                                      ?.width ??
                                                  h,
                                              child: GestureDetector(
                                                behavior:
                                                    HitTestBehavior.opaque,
                                                onTapDown: (d) =>
                                                    _setFocusAndExposurePoint(
                                                      d,
                                                      Size(w, h),
                                                    ),
                                                child: CameraPreview(
                                                  _controller!,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                ),
                                Positioned(
                                  top: 10,
                                  right: 10,
                                  left: 10,
                                  child: Row(
                                    children: [
                                      _roundedGlass(
                                        child: IconButton(
                                          tooltip: 'تبديل الكاميرا',
                                          icon: const Icon(
                                            Icons.cameraswitch_rounded,
                                            color: Colors.white,
                                          ),
                                          onPressed: _switchCamera,
                                        ),
                                      ),
                                      const Spacer(),
                                      _roundedGlass(
                                        child: IconButton(
                                          tooltip: 'وضع الفلاش',
                                          onPressed: _cycleFlash,
                                          icon: Icon(
                                            _flashMode == FlashMode.off
                                                ? Icons.flash_off_rounded
                                                : _flashMode == FlashMode.auto
                                                ? Icons.flash_auto_rounded
                                                : _flashMode == FlashMode.always
                                                ? Icons.flash_on_rounded
                                                : Icons.highlight_rounded,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Positioned(
                                  bottom: 10,
                                  left: 12,
                                  right: 12,
                                  child: Column(
                                    children: [
                                      _sliderCard(
                                        label: 'التقريب',
                                        value: _zoom,
                                        min: _minZoom,
                                        max: _maxZoom,
                                        onChanged: (v) => _setZoom(v),
                                      ),
                                      const SizedBox(height: 8),
                                      _sliderCard(
                                        label: 'التعريض',
                                        value: _exposure,
                                        min: _minExposure,
                                        max: _maxExposure,
                                        onChanged: (v) => _setExposure(v),
                                      ),
                                    ],
                                  ),
                                ),
                                if (_requiresItemDialog &&
                                    (_itemCount != null && _itemCount! > 0))
                                  Positioned(
                                    top: 54,
                                    right: 12,
                                    child: _roundedGlass(
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 8,
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              'عدد العناصر: $_itemCount',
                                              style:
                                                  GoogleFonts.ibmPlexSansArabic(
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                            ),
                                            const SizedBox(width: 6),
                                            InkWell(
                                              onTap:
                                                  _promptForItemCountIfNeeded,
                                              borderRadius:
                                                  BorderRadius.circular(999),
                                              child: const Icon(
                                                Icons.edit,
                                                size: 18,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                if (_inlineError != null)
                                  Positioned(
                                    top: 12,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 10,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withOpacity(0.72),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        _inlineError!,
                                        style: GoogleFonts.ibmPlexSansArabic(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ),
                                IgnorePointer(
                                  child: AnimatedOpacity(
                                    opacity: _flashOpacity,
                                    duration: const Duration(milliseconds: 120),
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.9),
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),

                  // ✅ عرض نتيجة التحقق بالـ AI
                  const SizedBox(height: 10),
                  if (_ready) ...[
                    if (_capturedPath == null)
                      _gradientButton(
                        label: _isCapturing
                            ? 'جاري الالتقاط...'
                            : 'التقاط صورة',
                        icon: Icons.camera,
                        onTap: _isCapturing
                            ? null
                            : () async {
                                if (!mounted) return;
                                setState(() {
                                  _isCapturing = true;
                                  _flashOpacity = 0.9;
                                });
                                await Future.delayed(
                                  const Duration(milliseconds: 90),
                                );
                                if (mounted)
                                  setState(() => _flashOpacity = 0.0);

                                final shot = await _safeTakePicture();
                                if (!mounted) return;

                                if (shot != null) {
                                  setState(() => _capturedPath = shot.path);
                                  await _verifyTaskImage(shot.path);
                                }
                                if (mounted)
                                  setState(() => _isCapturing = false);
                              },
                      )
                    else if (_isUploading)
                      _gradientButton(
                        label: 'جاري إكمال المهمة...',
                        icon: Icons.cloud_upload,
                        enabled: false,
                        loading: true,
                        onTap: null,
                      )
                    else if (_isVerifying)
                      _gradientButton(
                        label: 'جاري التحقق...',
                        icon: Icons.search,
                        enabled: false,
                        loading: true,
                        onTap: null,
                      )
                    // في الـ build داخل else if (!_isCompleted)
                    else if (!_isCompleted)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (_verificationResult != null)
                            _buildVerificationResult(), // ✅ المربع البرتقالي يظهر مرة واحدة فقط من هنا
                          const SizedBox(height: 16),

                          // زر إعادة التقاط
                          OutlinedButton.icon(
                            icon: Icon(Icons.refresh, color: appColors.primary),
                            label: Text(
                              'إعادة التقاط',
                              style: GoogleFonts.ibmPlexSansArabic(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                                color: appColors.primary,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(
                                color: appColors.primary,
                                width: 2,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            onPressed: () async {
                              try {
                                if (_capturedPath != null) {
                                  final f = File(_capturedPath!);
                                  if (await f.exists()) await f.delete();
                                }
                              } catch (_) {}
                              if (mounted) {
                                setState(() {
                                  _capturedPath = null;
                                  _verificationResult = null;
                                  _isUploading = false;
                                  _isVerifying = false;
                                  _isCompleted = false;
                                });
                              }
                            },
                          ),

                          // 🗑️ تم حذف المربع البرتقالي المكرر من هنا ❌

                          // رسالة توجيهية إذا كانت الصورة معتمدة (المربع الأخضر فقط)
                          if (_verificationResult != null &&
                              _isAiApproved(_verificationResult) &&
                              !_isUploading)
                            Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.green.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.green),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.check_circle,
                                      color: Colors.green,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'الصورة معتمدة',
                                            style:
                                                GoogleFonts.ibmPlexSansArabic(
                                                  fontWeight: FontWeight.w600,
                                                  color: Colors.green,
                                                ),
                                          ),
                                          Text(
                                            'سيتم إكمال المهمة تلقائياً...',
                                            style:
                                                GoogleFonts.ibmPlexSansArabic(
                                                  fontSize: 12,
                                                  color: Colors.black87,
                                                ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.green,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _hintCard(String text) => _hintCardWidget(text);

  Widget _hintCardWidget(String text) {
    return Material(
      elevation: 2,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(text, textAlign: TextAlign.center),
      ),
    );
  }

  Future<void> showTaskFailedDialogAndRedirect(BuildContext context) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          insetPadding: const EdgeInsets.symmetric(horizontal: 24),
          child: SizedBox(
            width: 340,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset(
                    'assets/img/nameerSad.png',
                    height: 120,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'لم يتم التحقق', // نفس حجم الخط والتنسيق
                    textAlign: TextAlign.center,
                    style: GoogleFonts.ibmPlexSansArabic(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: appColors.dark,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'يرجى إعادة التقاط الصورة مع:\n• إضاءة مناسبة\n• وضوح العنصر\n• زاوية تصوير جيدة',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.ibmPlexSansArabic(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: appColors.dark,
                      height: 1.6,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Center(
                    child: SizedBox(
                      width: 140, // 👈 نفس عرض الزر 140
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: appColors.primary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 10, // 👈 نفس الـ padding
                          ),
                        ),
                        onPressed: () {
                          Navigator.of(dialogContext).pop();
                        },
                        child: Text(
                          'حسناً',
                          style: GoogleFonts.ibmPlexSansArabic(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 16, // 👈 نفس حجم الخط
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _roundedGlass({required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.25),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white24, width: 1),
      ),
      child: child,
    );
  }

  Widget _sliderCard({
    required String label,
    required double value,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.25),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white24, width: 1),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 56,
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: GoogleFonts.ibmPlexSansArabic(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Slider(
              value: value.clamp(min, max).toDouble(),
              min: min,
              max: max == min ? min + 0.001 : max,
              onChanged: onChanged,
              activeColor: Colors.white,
              inactiveColor: Colors.white54,
            ),
          ),
          SizedBox(
            width: 58,
            child: Text(
              label == 'التقريب'
                  ? '${value.toStringAsFixed(1)}x'
                  : value.toStringAsFixed(1),
              textAlign: TextAlign.center,
              style: GoogleFonts.ibmPlexSansArabic(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _gradientButton({
    required String label,
    IconData? icon,
    required VoidCallback? onTap,
    bool loading = false,
    bool enabled = true, // ✅ جديد
  }) {
    final bool isDisabled = !enabled || loading || onTap == null;

    final child = loading
        ? const SizedBox(
            height: 22,
            width: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white,
            ),
          )
        : Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, color: Colors.white),
                const SizedBox(width: 8),
              ],
              Text(
                label,
                style: GoogleFonts.ibmPlexSansArabic(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  color: Colors.white,
                ),
              ),
            ],
          );

    return SizedBox(
      width: double.infinity,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: isDisabled
              ? LinearGradient(
                  colors: [Colors.grey.shade400, Colors.grey.shade400],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                )
              : const LinearGradient(
                  colors: [appColors.primary, appColors.mint],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: InkWell(
          onTap: isDisabled ? null : onTap, // ✅ يمنع الضغط
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Center(child: child),
          ),
        ),
      ),
    );
  }

  Widget _buildPhotoInstructions() {
    final bullets = [
      'تأكد من أن الإضاءة جيدة والعنصر واضح.',
      'التقط صورة تُظهر قيامك بالمهمة (مثل العناصر المجمعة).',
      'لا تستخدم صورًا من الإنترنت.',
      'التقط من زاوية مناسبة وبدون فلاش إن أمكن.',
    ];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: appColors.mint.withOpacity(0.15),
        border: Border.all(color: appColors.mint, width: 1.5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.camera_alt_outlined,
                color: appColors.primary,
                size: 22,
              ),
              const SizedBox(width: 8),
              Text(
                'تعليمات التصوير',
                style: GoogleFonts.ibmPlexSansArabic(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: appColors.dark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...bullets.map(
            (txt) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('•  ', style: TextStyle(height: 1.7)),
                  Expanded(
                    child: Text(
                      txt,
                      style: GoogleFonts.ibmPlexSansArabic(
                        fontSize: 13.8,
                        height: 1.8,
                        color: Colors.black87,
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

  Widget _counterButton({required IconData icon, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: appColors.primary.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: appColors.primary.withOpacity(0.45),
            width: 1.3,
          ),
        ),
        child: Icon(icon, size: 22, color: appColors.primary),
      ),
    );
  }
}
