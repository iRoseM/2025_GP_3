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
  final DateTime selectedDay; // ✅ اليوم المُختار من التقويم
  final String userTaskDocId; // ✅ وثيقة userTasks المراد تحديثها

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

  bool _ready = false;
  bool _openingCamera = false;
  bool _isCapturing = false;

  String? _inlineError;
  String? _capturedPath; // ملف مؤقت داخل التطبيق
  double _flashOpacity = 0.0;

  int _currentCameraIndex = 0;
  FlashMode _flashMode = FlashMode.off;

  double _minZoom = 1.0;
  double _maxZoom = 1.0;
  double _zoom = 1.0;

  double _minExposure = 0.0;
  double _maxExposure = 0.0;
  double _exposure = 0.0;

  String _yyyyMMdd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';

  /// ✅ يمنح النقاط + يحدّث وثيقة userTasks المحددة (وليس "اليوم الآن")
  Future<void> _awardPointsAndCompleteSelected(
    int points, {
    required String docId, // وثيقة اليوم المحدد
    required DateTime selectedDay, // اليوم المحدد
    String? taskId,
    double? carbonFootPrint,
    String? photoUrl,
    String? photoStoragePath,
    Map<String, dynamic>? extra,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('المستخدم غير مسجل دخول.');
    }
    final uid = user.uid;

    // 1) زيادة النقاط للمستخدم
    final userRef = FirebaseFirestore.instance.collection('users').doc(uid);
    await userRef.update({'points': FieldValue.increment(points)});

    // 2) تحديث وثيقة اليوم المحدد فقط
    final utRef = FirebaseFirestore.instance.collection('userTasks').doc(docId);

    final payload = <String, dynamic>{
      'userId': uid,
      if (taskId != null) 'taskId': taskId,
      'status': 'completed',
      'completedAt': FieldValue.serverTimestamp(),
      // نثبت نافذة اليوم/التواريخ لو كانت مفقودة
      'selectedAt': Timestamp.fromDate(
        DateTime(selectedDay.year, selectedDay.month, selectedDay.day),
      ),
      'windowStart': Timestamp.fromDate(
        DateTime(selectedDay.year, selectedDay.month, selectedDay.day),
      ),
      'windowEnd': Timestamp.fromDate(
        DateTime(
          selectedDay.year,
          selectedDay.month,
          selectedDay.day,
        ).add(const Duration(days: 1)).subtract(const Duration(seconds: 1)),
      ),
      if (carbonFootPrint != null) 'carbonFootPrint': carbonFootPrint,
      if (photoUrl != null)
        'evidence': {
          'type': 'photo',
          'url': photoUrl,
          if (photoStoragePath != null) 'storagePath': photoStoragePath,
          'uploadedAt': FieldValue.serverTimestamp(),
        },
      if (extra != null) ...extra,
    };

    await utRef.set(payload, SetOptions(merge: true));
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
        throw Exception('لا توجد كاميرا متاحة على هذا الجهاز.');
      }

      if (index != null) {
        _currentCameraIndex = index.clamp(0, _cameras!.length - 1);
      }

      final description = _cameras![_currentCameraIndex];
      _controller?.dispose();
      _controller = CameraController(
        description,
        ResolutionPreset.high,
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
      _showInlineError('تعذر فتح الكاميرا');
    } finally {
      if (mounted) setState(() => _openingCamera = false);
    }
  }

  Future<void> _switchCamera() async {
    if ((_cameras?.length ?? 0) < 2) {
      _showInlineError('لا توجد كاميرا أخرى');
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
    } catch (_) {
      _showInlineError('لا يمكن تغيير الفلاش الآن');
    }
  }

  Future<void> _setZoom(double value) async {
    if (!(_controller?.value.isInitialized ?? false)) return;
    _zoom = value.clamp(_minZoom, _maxZoom);
    try {
      await _controller!.setZoomLevel(_zoom);
      setState(() {});
    } catch (_) {
      _showInlineError('تعذر ضبط الزوم');
    }
  }

  Future<void> _setExposure(double value) async {
    if (!(_controller?.value.isInitialized ?? false)) return;
    _exposure = value.clamp(_minExposure, _maxExposure);
    try {
      await _controller!.setExposureOffset(_exposure);
      setState(() {});
    } catch (_) {
      _showInlineError('تعذر ضبط التعريض');
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
      _showInlineError('تم التركيز');
    } catch (_) {
      _showInlineError('تعذر التركيز هنا');
    }
  }

  void _showInlineError(String msg) {
    setState(() => _inlineError = msg);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _inlineError = null);
    });
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
                                                0.7,
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

                  if (_ready && requiresPhotoExact)
                    _gradientButton(
                      label: _isCapturing ? 'جاري الالتقاط...' : 'التقاط صورة',
                      icon: Icons.camera,
                      onTap: _isCapturing
                          ? null
                          : () =>
                                _onCapturePressed(points: pts, taskId: taskId),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// ✅ يلتقط/يرفع الصورة (إن وُجدت) ثم يحدّث وثيقة userTasks لليوم المحدد فقط
  Future<void> _onCapturePressed({required int points, String? taskId}) async {
    try {
      setState(() {
        _isCapturing = true;
        _flashOpacity = 0.9;
      });
      await Future.delayed(const Duration(milliseconds: 90));
      if (mounted) setState(() => _flashOpacity = 0.0);

      XFile? file;
      if (_controller != null && (_controller!.value.isInitialized)) {
        file = await _controller!.takePicture();
      }

      if (!mounted) return;

      if (file != null) setState(() => _capturedPath = file!.path);

      final double? carbon = widget.taskData['carbonFootPrint'] is num
          ? (widget.taskData['carbonFootPrint'] as num).toDouble()
          : null;

      // ✅ رفع الصورة إلى Firebase Storage (اختياري)
      String? downloadUrl;
      String? storagePath;
      try {
        if (file != null) {
          final uid = FirebaseAuth.instance.currentUser?.uid ?? 'anonymous';
          final now = DateTime.now();
          final y = now.year.toString().padLeft(4, '0');
          final m = now.month.toString().padLeft(2, '0');
          final d = now.day.toString().padLeft(2, '0');
          final fileName =
              'task_${taskId ?? 'unknown'}_${now.millisecondsSinceEpoch}.jpg';

          final ref = FirebaseStorage.instance
              .ref()
              .child('task_photos')
              .child(uid)
              .child('$y$m$d')
              .child(fileName);

          await ref.putFile(
            File(file.path),
            SettableMetadata(
              contentType: 'image/jpeg',
              cacheControl: 'public,max-age=3600',
            ),
          );
          downloadUrl = await ref.getDownloadURL();
          storagePath = ref.fullPath;
        }
      } catch (_) {
        downloadUrl = null;
        storagePath = null;
      }

      // ✅ تحديث الوثيقة المحددة (وليس اليوم الحالي)
      await _awardPointsAndCompleteSelected(
        points,
        docId: widget.userTaskDocId,
        selectedDay: widget.selectedDay,
        taskId: taskId,
        carbonFootPrint: carbon,
        photoUrl: downloadUrl,
        photoStoragePath: storagePath,
      );

      await Future.delayed(const Duration(milliseconds: 1200));

      // ✅ نافذة النجاح + حذف الملف المؤقت عند الإغلاق
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          return Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            insetPadding: const EdgeInsets.symmetric(horizontal: 24),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.55,
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset(
                      'assets/img/nameerCamera.png',
                      height: 120,
                      fit: BoxFit.contain,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '!أنجزت مهمتك بنجاح',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.ibmPlexSansArabic(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: AppColors.dark,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'شكرًا لمساهمتك البيئية ❤️ تم اعتماد إنجازك وإضافة النقاط إلى حسابك.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.ibmPlexSansArabic(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: AppColors.dark,
                        height: 1.6,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Center(
                      child: SizedBox(
                        width: 140,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 10,
                            ),
                          ),
                          onPressed: () async {
                            try {
                              if (_capturedPath != null) {
                                final f = File(_capturedPath!);
                                if (await f.exists()) await f.delete();
                                _capturedPath = null;
                              }
                            } catch (_) {}
                            Navigator.pop(context); // يغلق الـ dialog
                            Navigator.of(
                              context,
                            ).pop(true); // يغلق الـ bottomSheet ويُرجِع true
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
    } catch (e) {
      _showInlineError('فشل الالتقاط أو التحديث، حاول مرة أخرى');
    } finally {
      if (mounted) setState(() => _isCapturing = false);
    }
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
