import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:camera/camera.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

class AppColors {
  static const primary = Color(0xFF4BAA98);
  static const dark = Color(0xFF3C3C3B);
  static const accent = Color(0xFFF4A340);
  static const sea = Color(0xFF1F7A8C);
  static const primary60 = Color(0x994BAA98);
  static const primary33 = Color(0x544BAA98);
  static const light = Color(0xFF79D0BE);
  static const background = Color(0xFFF3FAF7);
  static const mint = Color(0xFFB6E9C1);
  static const tealSoft = Color(0xFF75BCAF);
}

class CompleteTaskSheet extends StatefulWidget {
  final Map<String, dynamic> taskData;
  final DateTime selectedDay; // اليوم المُختار من التقويم
  final String userTaskDocId; // وثيقة userTasks المراد تحديثها

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
  CameraController? _controller;
  List<CameraDescription>? _cameras;

  bool _ready = false; // الكاميرا جاهزة للمعاينة
  bool _openingCamera = false; // جاري فتح/تهيئة الكاميرا
  bool _isCapturing = false; // قفل أثناء الالتقاط
  bool _isUploading = false; // قفل أثناء الرفع/الإرسال

  String? _inlineError; // ✅ رسالة قصيرة تظهر فوق الكاميرا
  String? _capturedPath; // مسار الصورة الملتقطة للمعاينة
  double _flashOpacity = 0.0;

  int _currentCameraIndex = 0;
  FlashMode _flashMode = FlashMode.off;

  double _minZoom = 1.0, _maxZoom = 1.0, _zoom = 1.0;
  double _minExposure = 0.0, _maxExposure = 0.0, _exposure = 0.0;

  String _yyyyMMdd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';

  // ======== Friendly, short error mapping (Arabic) ========
  String _friendlyError(Object e) {
    // Camera
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
    // Firebase Storage / Firestore
    if (e is FirebaseException) {
      final code = e.code.toLowerCase();
      if (code.contains('permission-denied')) return 'صلاحيات غير كافية.';
      if (code.contains('unauthorized')) return 'غير مُخوّل للرفع.';
      if (code.contains('object-not-found'))
        return 'المسار غير موجود في التخزين.';
      if (code.contains('not-found')) return 'المورد غير موجود.';
      if (code.contains('quota-exceeded')) return 'تم تجاوز الحصة التخزينية.';
      if (code.contains('retry-limit-exceeded'))
        return 'انقطع الاتصال أثناء الرفع.';
      if (code.contains('unavailable')) return 'الخدمة غير متاحة مؤقتًا.';
      return 'خطأ (${e.code}).';
    }
    // Generic
    final s = e.toString();
    if (s.contains('socket') || s.contains('host'))
      return 'تحقق من اتصال الإنترنت.';
    return 'حدث خطأ غير متوقع.';
  }

  void _showInlineError(String msg) {
    setState(() => _inlineError = msg);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _inlineError = null);
    });
  }

  // ---------------------------
  // التقاط آمن مع إعادة محاولة
  // ---------------------------
  Future<XFile?> _safeTakePicture() async {
    if (_controller == null || !_controller!.value.isInitialized) {
      _showInlineError('الكاميرا غير جاهزة.');
      return null;
    }
    if (_controller!.value.isTakingPicture) return null;

    try {
      return await _controller!.takePicture();
    } on CameraException catch (e) {
      debugPrint('CameraException: ${e.code} | ${e.description}');
      try {
        await Future.delayed(const Duration(milliseconds: 150));
        if (!_controller!.value.isInitialized ||
            _controller!.value.isTakingPicture)
          return null;
        return await _controller!.takePicture();
      } catch (e2) {
        debugPrint('Retry takePicture failed: $e2');
        _showInlineError(_friendlyError(e));
        return null;
      }
    } catch (e) {
      debugPrint('takePicture generic error: $e');
      _showInlineError(_friendlyError(e));
      return null;
    }
  }

  // -----------------------------------------
  // رفع الصورة + إنشاء submission + تحديث userTasks → submitted
  // -----------------------------------------
  Future<void> _createSubmissionAndMarkSubmitted({
    required String localPath,
    required int taskPoints,
    String? taskId,
    Map<String, dynamic>? extra,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('يرجى تسجيل الدخول.');
    }

    final file = File(localPath);
    if (!await file.exists()) {
      throw Exception('لم يتم العثور على ملف الصورة.');
    }

    final uid = user.uid;
    final dayKey = _yyyyMMdd(widget.selectedDay);
    final basePath = 'submissions/$uid/${dayKey}_${widget.userTaskDocId}';
    final name = DateTime.now().millisecondsSinceEpoch.toString();

    final storage = FirebaseStorage.instance;
    final storageRef = storage.ref('$basePath/$name.jpg');

    Future<void> tryUpload() async {
      try {
        await storageRef.putFile(
          file,
          SettableMetadata(
            contentType: 'image/jpeg',
            cacheControl: 'public,max-age=3600',
          ),
        );
      } on FirebaseException catch (e) {
        // 🔹 يعرض رسالة قصيرة على الكاميرا بدل Snackbar
        _showInlineError(
          e.code == 'permission-denied'
              ? 'صلاحيات غير كافية'
              : e.code == 'unauthorized'
              ? 'غير مخوّل للرفع'
              : 'فشل الرفع (${e.code})',
        );
        rethrow;
      } catch (e) {
        _showInlineError('تعذر رفع الصورة');
        rethrow;
      }
    }

    try {
      try {
        await tryUpload();
      } catch (_) {
        await Future.delayed(const Duration(milliseconds: 300));
        await tryUpload();
      }
    } on FirebaseException catch (e) {
      debugPrint('Storage upload error: ${e.code} | ${e.message}');
      throw FirebaseException(
        plugin: e.plugin,
        code: e.code,
        message: _friendlyError(e),
      );
    } catch (e) {
      debugPrint('Storage upload generic error: $e');
      throw Exception(_friendlyError(e));
    }

    // ✅ getDownloadURL مع محاولة ثانية
    Future<String> getUrlWithRetry() async {
      try {
        return await storageRef.getDownloadURL();
      } catch (_) {
        await Future.delayed(const Duration(milliseconds: 200));
        return await storageRef.getDownloadURL();
      }
    }

    String downloadUrl;
    try {
      downloadUrl = await getUrlWithRetry();
    } on FirebaseException catch (e) {
      debugPrint('getDownloadURL error: ${e.code} | ${e.message}');
      try {
        await storageRef.delete();
      } catch (_) {}
      throw FirebaseException(
        plugin: e.plugin,
        code: e.code,
        message: _friendlyError(e),
      );
    } catch (e) {
      try {
        await storageRef.delete();
      } catch (_) {}
      throw Exception(_friendlyError(e));
    }

    // ✅ كتابة Firestore داخل معاملة، وإن فشلت نحذف الصورة كي لا تبقى يتيمة
    final subRef = FirebaseFirestore.instance.collection('submissions').doc();
    final utRef = FirebaseFirestore.instance
        .collection('userTasks')
        .doc(widget.userTaskDocId);

    try {
      // العملية الأولى: إنشاء submission
      await subRef.set({
        'userId': uid,
        'userTaskDocId': widget.userTaskDocId,
        'taskId': taskId ?? '',
        'taskTitle': widget.taskData['title'] ?? '',
        'taskPoints': taskPoints,
        'status': 'pending',
        'imageUrls': [downloadUrl],
        'createdAt': FieldValue.serverTimestamp(),
        'processedAt': null,
        'processedBy': null,
        if (extra != null) ...extra,
      });

      // العملية الثانية: تحديث userTask
      await utRef.set({
        'status': 'submitted',
        'submittedAt': FieldValue.serverTimestamp(),
        'evidence': {
          'type': 'photo',
          'url': downloadUrl,
          'storagePath': storageRef.fullPath,
          'uploadedAt': FieldValue.serverTimestamp(),
        },
        'taskTitle': widget.taskData['title'] ?? '',
        'taskPoints': taskPoints,
        if (taskId != null) 'taskId': taskId,
        'selectedAt': Timestamp.fromDate(
          DateTime(
            widget.selectedDay.year,
            widget.selectedDay.month,
            widget.selectedDay.day,
          ),
        ),
        'windowStart': Timestamp.fromDate(
          DateTime(
            widget.selectedDay.year,
            widget.selectedDay.month,
            widget.selectedDay.day,
          ),
        ),
        'windowEnd': Timestamp.fromDate(
          DateTime(
            widget.selectedDay.year,
            widget.selectedDay.month,
            widget.selectedDay.day,
          ).add(const Duration(days: 1)).subtract(const Duration(seconds: 1)),
        ),
      }, SetOptions(merge: true));
    } on FirebaseException catch (e) {
      debugPrint('Firestore write error: ${e.code} | ${e.message}');
      try {
        await storageRef.delete();
      } catch (_) {}
      throw FirebaseException(
        plugin: e.plugin,
        code: e.code,
        message: _friendlyError(e),
      );
    }
  }

  Future<void> _openCamera({int? index}) async {
    if (_openingCamera) return;
    setState(() {
      _openingCamera = true;
      _capturedPath = null;
    });
    try {
      _cameras ??= await availableCameras();
      if (_cameras == null || _cameras!.isEmpty) {
        throw CameraException('NoCamera', 'لا توجد كاميرا متاحة.');
      }

      if (index != null) {
        _currentCameraIndex = index.clamp(0, _cameras!.length - 1);
      }

      final description = _cameras![_currentCameraIndex];
      await _controller?.dispose();
      _controller = CameraController(
        description,
        ResolutionPreset.high, // غيّرها لـ medium لو تبغى حجم ملف أقل
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await _controller!.initialize();

      _minZoom = await _controller!.getMinZoomLevel();
      _maxZoom = await _controller!.getMaxZoomLevel();
      _zoom = _zoom.clamp(_minZoom, _maxZoom);

      _minExposure = await _controller!.getMinExposureOffset();
      _maxExposure = await _controller!.getMaxExposureOffset();
      _exposure = _exposure.clamp(_minExposure, _maxExposure);

      await _controller!.setFlashMode(_flashMode);
      await _controller!.setZoomLevel(_zoom);
      await _controller!.setExposureOffset(_exposure);

      if (mounted) setState(() => _ready = true);
    } catch (e) {
      debugPrint('Open camera error: $e');
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
      setState(() {});
    } catch (e) {
      _showInlineError(_friendlyError(e));
    }
  }

  Future<void> _setZoom(double value) async {
    if (!(_controller?.value.isInitialized ?? false)) return;
    _zoom = value.clamp(_minZoom, _maxZoom);
    try {
      await _controller!.setZoomLevel(_zoom);
      setState(() {});
    } catch (e) {
      _showInlineError('تعذر ضبط التقريب.');
    }
  }

  Future<void> _setExposure(double value) async {
    if (!(_controller?.value.isInitialized ?? false)) return;
    _exposure = value.clamp(_minExposure, _maxExposure);
    try {
      await _controller!.setExposureOffset(_exposure);
      setState(() {});
    } catch (e) {
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
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final task = widget.taskData;
    final title = task['title'] ?? 'مهمة غير معروفة';
    final desc = task['description'] ?? '';
    final pts = (task['points'] ?? 0) as int;
    final validation = (task['validationStrategy'] ?? 'غير محددة')
        .toString()
        .trim();
    final taskId = task['id'] as String?;
    final requiresPhotoExact = validation == 'التحقق عبر معالجة الصور';

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
                      color: AppColors.dark,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    title,
                    style: GoogleFonts.ibmPlexSansArabic(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(
                        Icons.star_border,
                        color: AppColors.primary,
                        size: 20,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '$pts نقطة',
                        style: GoogleFonts.ibmPlexSansArabic(
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
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
                  const SizedBox(height: 20),

                  if (requiresPhotoExact && !_ready) _buildPhotoInstructions(),
                  const SizedBox(height: 16),

                  if (requiresPhotoExact)
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      child: !_ready
                          ? _gradientButton(
                              label: 'ابدأ التصوير',
                              icon: Icons.camera_alt,
                              onTap: _openingCamera
                                  ? null
                                  : () => _openCamera(),
                              loading: _openingCamera,
                            )
                          : SizedBox(
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
                                                borderRadius:
                                                    BorderRadius.circular(16),
                                                child: Image.file(
                                                  File(_capturedPath!),
                                                  fit: BoxFit.cover,
                                                ),
                                              )
                                            : ClipRRect(
                                                borderRadius:
                                                    BorderRadius.circular(16),
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
                                                      behavior: HitTestBehavior
                                                          .opaque,
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
                                      // Top controls
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
                                                      : _flashMode ==
                                                            FlashMode.auto
                                                      ? Icons.flash_auto_rounded
                                                      : _flashMode ==
                                                            FlashMode.always
                                                      ? Icons.flash_on_rounded
                                                      : Icons.highlight_rounded,
                                                  color: Colors.white,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      // Bottom sliders
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
                                      // ✅ Inline short error over preview
                                      if (_inlineError != null)
                                        Positioned(
                                          top: 12,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 14,
                                              vertical: 10,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.black.withOpacity(
                                                0.72,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                            child: Text(
                                              _inlineError!,
                                              style:
                                                  GoogleFonts.ibmPlexSansArabic(
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                            ),
                                          ),
                                        ),
                                      // Flash overlay
                                      IgnorePointer(
                                        child: AnimatedOpacity(
                                          opacity: _flashOpacity,
                                          duration: const Duration(
                                            milliseconds: 120,
                                          ),
                                          child: Container(
                                            decoration: BoxDecoration(
                                              color: Colors.white.withOpacity(
                                                0.9,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(16),
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

                  const SizedBox(height: 16),

                  // أزرار الإجراءات (تتغير حسب الحالة)
                  if (_ready && requiresPhotoExact) ...[
                    if (_capturedPath == null)
                      _gradientButton(
                        label: _isCapturing
                            ? 'جاري الالتقاط...'
                            : 'التقاط صورة',
                        icon: Icons.camera,
                        onTap: _isCapturing
                            ? null
                            : () async {
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
                                if (shot != null)
                                  setState(() => _capturedPath = shot.path);
                                setState(() => _isCapturing = false);
                              },
                      )
                    else
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _gradientButton(
                            label: _isUploading
                                ? 'جاري الإرسال...'
                                : 'إرسال للمراجعة',
                            icon: Icons.cloud_upload,
                            onTap: _isUploading
                                ? null
                                : () async {
                                    if (_capturedPath == null) return;
                                    setState(() => _isUploading = true);
                                    try {
                                      await _createSubmissionAndMarkSubmitted(
                                        localPath: _capturedPath!,
                                        taskPoints: pts,
                                        taskId: taskId,
                                      );

                                      // نافذة نجاح
                                      await showDialog(
                                        context: context,
                                        barrierDismissible: false,
                                        builder: (context) {
                                          return Dialog(
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(20),
                                            ),
                                            insetPadding:
                                                const EdgeInsets.symmetric(
                                                  horizontal: 24,
                                                ),
                                            child: SizedBox(
                                              width:
                                                  340, // 👈 نفس الثبات في عرض نافذة البلاغ
                                              child: Padding(
                                                padding: const EdgeInsets.all(
                                                  20,
                                                ),
                                                child: Column(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    // 👇 استعمل نفس الصورة المستخدمة في بلاغ المرافق (عدّل المسار لو مختلف)
                                                    Image.asset(
                                                      'assets/img/nameerCamera.png',
                                                      height: 120,
                                                      fit: BoxFit.contain,
                                                    ),
                                                    const SizedBox(height: 16),
                                                    Text(
                                                      '!تم تسجيل مشاركتك بنجاح',
                                                      textAlign:
                                                          TextAlign.center,
                                                      style:
                                                          GoogleFonts.ibmPlexSansArabic(
                                                            fontSize: 20,
                                                            fontWeight:
                                                                FontWeight.w700,
                                                            color:
                                                                AppColors.dark,
                                                          ),
                                                    ),
                                                    const SizedBox(height: 12),
                                                    Text(
                                                      'جاري إرسالها للجنة المراجعة.\n'
                                                      'عند الاعتماد، سيتم إضافة النقاط البيئية إلى حسابك تلقائيًا 🌱',
                                                      textAlign:
                                                          TextAlign.center,
                                                      style:
                                                          GoogleFonts.ibmPlexSansArabic(
                                                            fontSize: 16,
                                                            fontWeight:
                                                                FontWeight.w500,
                                                            color:
                                                                AppColors.dark,
                                                          ),
                                                    ),
                                                    const SizedBox(height: 24),
                                                    Center(
                                                      child: SizedBox(
                                                        width: 140,
                                                        child: ElevatedButton(
                                                          style: ElevatedButton.styleFrom(
                                                            backgroundColor:
                                                                AppColors
                                                                    .primary,
                                                            shape: RoundedRectangleBorder(
                                                              borderRadius:
                                                                  BorderRadius.circular(
                                                                    12,
                                                                  ),
                                                            ),
                                                            padding:
                                                                const EdgeInsets.symmetric(
                                                                  horizontal:
                                                                      24,
                                                                  vertical: 10,
                                                                ),
                                                          ),
                                                          onPressed: () =>
                                                              Navigator.pop(
                                                                context,
                                                              ),
                                                          child: Text(
                                                            'تم',
                                                            style:
                                                                GoogleFonts.ibmPlexSansArabic(
                                                                  color: Colors
                                                                      .white,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w700,
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

                                      // حذف مؤقت/إغلاق
                                      try {
                                        if (_capturedPath != null) {
                                          final f = File(_capturedPath!);
                                          if (await f.exists())
                                            await f.delete();
                                        }
                                      } catch (_) {}
                                      if (!mounted) return;
                                      Navigator.of(context).pop(true);
                                    } catch (e) {
                                      debugPrint('Submit error: $e');
                                      if (!mounted) return;
                                      _showInlineError(_friendlyError(e));
                                    } finally {
                                      if (mounted)
                                        setState(() => _isUploading = false);
                                    }
                                  },
                          ),
                          const SizedBox(height: 10),
                          OutlinedButton.icon(
                            icon: const Icon(
                              Icons.refresh,
                              color: AppColors.primary,
                            ),
                            label: Text(
                              'إعادة التقاط',
                              style: GoogleFonts.ibmPlexSansArabic(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                                color: AppColors.primary,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(
                                color: AppColors.primary,
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
                              setState(() => _capturedPath = null);
                            },
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

  Widget _buildPhotoInstructions() {
    final bullets = [
      'تأكد من أن الإضاءة جيدة والعنصر واضح.',
      'التقط صورة تُظهر قيامك بالمهمة (مثل رمي العبوة في الحاوية).',
      'لا تستخدم صورًا من الإنترنت.',
      'التقط من زاوية مناسبة وبدون فلاش إن أمكن.',
    ];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.mint.withOpacity(0.15),
        border: Border.all(color: AppColors.mint, width: 1.5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.camera_alt_outlined,
                color: AppColors.primary,
                size: 22,
              ),
              const SizedBox(width: 8),
              Text(
                'تعليمات التصوير',
                style: GoogleFonts.ibmPlexSansArabic(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.dark,
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
              value: value.clamp(min, max),
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
  }) {
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
          gradient: const LinearGradient(
            colors: [AppColors.primary, AppColors.mint],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Center(child: child),
          ),
        ),
      ),
    );
  }
}
