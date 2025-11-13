import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'services/admin_bottom_nav.dart';
import 'admin_home.dart';
import 'admin_task.dart';
import 'admin_map.dart';

import 'services/background_container.dart';
import 'services/connection.dart';
import 'services/title_header.dart';

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

class AdminRewardsPage extends StatefulWidget {
  const AdminRewardsPage({super.key});

  @override
  State<AdminRewardsPage> createState() => _AdminRewardsPageState();
}

class _AdminRewardsPageState extends State<AdminRewardsPage> {
  int _currentIndex = 0;
  void _onTap(int i) {
    if (i == _currentIndex) return;

    switch (i) {
      case 0:
        break;

      case 1:
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const AdminMapPage()),
        );
        break;

      case 2:
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const AdminTasksPage()),
        );
        break;

      case 3:
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const AdminHomePage()),
        );
        break;
    }
  }

  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _pointsCtrl = TextEditingController();
  final _imgCtrl = TextEditingController();
  bool _isActive = true;

  // 🎨 حالة زر رفع الصورة داخل الدايالوج
  Color _uploadBtnColor = AppColors.primary;
  String _uploadBtnText = 'اختيار الصورة';
  IconData _uploadBtnIcon = Icons.image_outlined;

  @override
  void initState() {
    super.initState();
    _checkConnection();
  }

  Future<void> _checkConnection() async {
    if (!await hasInternetConnection()) {
      if (mounted) showNoInternetDialog(context);
    }
  }

  Future<void> _saveReward(BuildContext parentContext, {String? docId}) async {
    final title = _titleCtrl.text.trim();
    final desc = _descCtrl.text.trim();
    final points = int.tryParse(_pointsCtrl.text.trim()) ?? 0;
    final img = _imgCtrl.text.trim();

    final rewardData = {
      'title': title,
      'description': desc,
      'costPoints': points,
      'imageUrl': img,
      'isActive': _isActive,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    try {
      if (docId == null) {
        rewardData['createdAt'] = FieldValue.serverTimestamp();
        await FirebaseFirestore.instance.collection('rewards').add(rewardData);
      } else {
        await FirebaseFirestore.instance
            .collection('rewards')
            .doc(docId)
            .update(rewardData);
      }

      _titleCtrl.clear();
      _descCtrl.clear();
      _pointsCtrl.clear();
      _imgCtrl.clear();
      _isActive = true;

      final scaffoldContext = parentContext;
      if (Navigator.of(parentContext, rootNavigator: true).canPop()) {
        Navigator.of(parentContext, rootNavigator: true).pop();
      }

      Future.microtask(() {
        final message = docId == null
            ? 'تمت إضافة المكافأة بنجاح 🎉'
            : 'تم تحديث المكافأة بنجاح ✏️';
        ScaffoldMessenger.of(
          scaffoldContext,
        ).showSnackBar(SnackBar(content: Text(message)));
      });
    } catch (e) {
      final scaffoldContext = parentContext;
      if (Navigator.of(parentContext, rootNavigator: true).canPop()) {
        Navigator.of(parentContext, rootNavigator: true).pop();
      }
      Future.microtask(() {
        ScaffoldMessenger.of(
          scaffoldContext,
        ).showSnackBar(SnackBar(content: Text('خطأ أثناء الإضافة: $e')));
      });
    }
  }

  Future<String?> _pickAndUploadImage() async {
    try {
      String? filePath;

      final choice = await showModalBottomSheet<String>(
        context: context,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(
                  Icons.photo_library,
                  color: AppColors.primary,
                ),
                title: const Text('اختيار من الصور'),
                onTap: () => Navigator.pop(ctx, 'gallery'),
              ),
              ListTile(
                leading: const Icon(Icons.folder, color: AppColors.primary),
                title: const Text('اختيار من الملفات'),
                onTap: () => Navigator.pop(ctx, 'files'),
              ),
            ],
          ),
        ),
      );

      if (choice == null) return null;

      if (choice == 'gallery') {
        final picker = ImagePicker();
        final picked = await picker.pickImage(source: ImageSource.gallery);
        if (picked == null) return null;
        filePath = picked.path;
      } else if (choice == 'files') {
        final result = await FilePicker.platform.pickFiles(
          type: FileType.image,
        );
        if (result == null || result.files.isEmpty) return null;
        filePath = result.files.single.path;
      }

      if (filePath == null || !File(filePath).existsSync()) return null;

      final file = File(filePath);
      final ref = FirebaseStorage.instance.ref().child(
        'rewardImages/${DateTime.now().millisecondsSinceEpoch}.jpg',
      );

      await ref.putFile(file);
      final url = await ref.getDownloadURL();
      return url;
    } on FirebaseException catch (e) {
      debugPrint('Firebase Storage error: ${e.code} - ${e.message}');
      return null;
    } catch (e) {
      debugPrint('Upload error: $e');
      return null;
    }
  }

  void _showAddRewardDialog({
    Map<String, dynamic>? existingData,
    String? docId,
  }) {
    setState(() {
      _uploadBtnColor = AppColors.primary;
      _uploadBtnText = 'اختيار الصورة';
      _uploadBtnIcon = Icons.image_outlined;
    });

    if (existingData != null) {
      _titleCtrl.text = existingData['title'] ?? '';
      _descCtrl.text = existingData['description'] ?? '';
      _pointsCtrl.text = (existingData['costPoints'] ?? '').toString();
      _imgCtrl.text = existingData['imageUrl'] ?? '';
      _isActive = existingData['isActive'] ?? true;

      _uploadBtnColor = _imgCtrl.text.isNotEmpty
          ? Colors.green
          : AppColors.primary;
      _uploadBtnText = _imgCtrl.text.isNotEmpty
          ? 'تم رفع الصورة بنجاح'
          : 'اختيار الصورة';
      _uploadBtnIcon = _imgCtrl.text.isNotEmpty
          ? Icons.check_circle_outline
          : Icons.image_outlined;
    } else {
      _titleCtrl.clear();
      _descCtrl.clear();
      _pointsCtrl.clear();
      _imgCtrl.clear();
      _isActive = true;
      _uploadBtnColor = AppColors.primary;
      _uploadBtnText = 'اختيار الصورة';
      _uploadBtnIcon = Icons.image_outlined;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        final _formKey = GlobalKey<FormState>();

        return Dialog(
          insetPadding: const EdgeInsets.fromLTRB(24, 60, 24, 100),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: StatefulBuilder(
              builder: (context, setSt) {
                return Material(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                    child: Form(
                      key: _formKey,
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  existingData == null
                                      ? 'إضافة مكافأة جديدة'
                                      : 'تعديل المكافأة',
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.close,
                                    color: Colors.grey,
                                  ),
                                  onPressed: () => Navigator.pop(context),
                                ),
                              ],
                            ),
                            const Divider(height: 10),
                            const SizedBox(height: 10),

                            Row(
                              children: const [
                                Text(
                                  'اسم الجهة المقدمة للمكافأة',
                                  style: TextStyle(fontWeight: FontWeight.w700),
                                ),
                                Text(
                                  ' *',
                                  style: TextStyle(
                                    color: Colors.red,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            TextFormField(
                              controller: _titleCtrl,
                              textAlign: TextAlign.right,
                              decoration: _inputDeco(
                                'مثال: Namshi أو Ounass',
                                prefixIcon: const Icon(
                                  Icons.card_giftcard_outlined,
                                ),
                              ),
                              validator: (v) => (v == null || v.trim().isEmpty)
                                  ? 'يرجى إدخال اسم الجهة المقدمة للمكافأة'
                                  : null,
                            ),
                            const SizedBox(height: 14),

                            Row(
                              children: const [
                                Text(
                                  'الوصف',
                                  style: TextStyle(fontWeight: FontWeight.w700),
                                ),
                                Text(
                                  ' *',
                                  style: TextStyle(
                                    color: Colors.red,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            TextFormField(
                              controller: _descCtrl,
                              textAlign: TextAlign.right,
                              maxLines: 2,
                              decoration: _inputDeco(
                                'مثال: كوبون خصم يصل إلى 20%',
                                prefixIcon: const Icon(
                                  Icons.description_outlined,
                                ),
                              ),
                              validator: (v) => (v == null || v.trim().isEmpty)
                                  ? 'يرجى إدخال وصف المكافأة'
                                  : null,
                            ),
                            const SizedBox(height: 14),

                            Row(
                              children: const [
                                Text(
                                  'النقاط المطلوبة',
                                  style: TextStyle(fontWeight: FontWeight.w700),
                                ),
                                Text(
                                  ' *',
                                  style: TextStyle(
                                    color: Colors.red,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            TextFormField(
                              controller: _pointsCtrl,
                              textAlign: TextAlign.right,
                              keyboardType: TextInputType.number,
                              decoration: _inputDeco(
                                'مثال: 50',
                                prefixIcon: const Icon(Icons.star_rate_rounded),
                              ),
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) {
                                  return 'يرجى إدخال عدد النقاط المطلوبة';
                                }
                                final val = int.tryParse(v);
                                if (val == null || val <= 0) {
                                  return 'يرجى إدخال رقم صالح';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 14),

                            const Text(
                              'صورة المكافأة',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 6),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _uploadBtnColor,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              icon: Icon(_uploadBtnIcon, color: Colors.white),
                              label: Text(
                                _uploadBtnText,
                                style: const TextStyle(color: Colors.white),
                              ),
                              onPressed: () async {
                                final url = await _pickAndUploadImage();
                                if (url != null) {
                                  setSt(() {
                                    _imgCtrl.text = url;
                                    _uploadBtnColor = Colors.green;
                                    _uploadBtnText = 'تم رفع الصورة بنجاح';
                                    _uploadBtnIcon = Icons.check_circle_outline;
                                  });
                                } else {
                                  setSt(() {
                                    _uploadBtnColor = Colors.red;
                                    _uploadBtnText = 'لم يتم اختيار صورة';
                                    _uploadBtnIcon = Icons.error_outline;
                                  });
                                }
                              },
                            ),
                            const SizedBox(height: 14),

                            SwitchListTile(
                              title: Text(
                                'الحالة: ${_isActive ? 'نشطة' : 'متوقفة'}',
                              ),
                              value: _isActive,
                              onChanged: (v) => setSt(() => _isActive = v),
                              contentPadding: EdgeInsets.zero,
                            ),
                            const SizedBox(height: 10),

                            DecoratedBox(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                gradient: const LinearGradient(
                                  colors: [
                                    AppColors.mint,
                                    AppColors.primary,
                                    AppColors.primary,
                                  ],
                                  begin: Alignment.centerRight,
                                  end: Alignment.centerLeft,
                                ),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Color(0x33000000),
                                    blurRadius: 8,
                                    offset: Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: FilledButton.icon(
                                icon: const Icon(
                                  Icons.check,
                                  color: Colors.white,
                                ),
                                label: const Text(
                                  'حفظ المكافأة',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                style: FilledButton.styleFrom(
                                  backgroundColor: Colors.transparent,
                                  shadowColor: Colors.transparent,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 10,
                                    horizontal: 18,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  minimumSize: const Size.fromHeight(42),
                                ),
                                onPressed: () async {
                                  if (!(_formKey.currentState?.validate() ??
                                      false))
                                    return;
                                  await _saveReward(context, docId: docId);
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  InputDecoration _inputDeco(String hint, {Widget? prefixIcon}) {
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      prefixIcon: prefixIcon,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.primary),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.primary),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.dark, width: 1.2),
      ),
    );
  }

  Widget _buildAddFab() {
    return FloatingActionButton(
      onPressed: _showAddRewardDialog,
      backgroundColor: AppColors.primary,
      shape: const CircleBorder(),
      child: const Icon(Icons.add, color: Colors.white, size: 28),
    );
  }

  @override
  Widget build(BuildContext context) {
    final baseTheme = Theme.of(context);
    final textTheme = GoogleFonts.ibmPlexSansArabicTextTheme(
      baseTheme.textTheme,
    );

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Theme(
        data: baseTheme.copyWith(
          textTheme: textTheme,
          primaryTextTheme: textTheme,
          appBarTheme: const AppBarTheme(
            backgroundColor: Colors.transparent,
            elevation: 0,
            iconTheme: IconThemeData(color: Colors.white),
          ),
        ),
        child: Scaffold(
          extendBody: true,
          extendBodyBehindAppBar: true,
          backgroundColor: Colors.transparent,

          appBar: const NameerAppBar(
            showTitleInBar: false,
            showBack: false,
            height: 80,
          ),

          body: AnimatedBackgroundContainer(
            child: Builder(
              builder: (context) {
                final statusBar = MediaQuery.of(context).padding.top;
                const headerH = 20.0;
                const gap = 12.0;
                final topPadding = statusBar + headerH + gap;

                return Padding(
                  padding: EdgeInsets.fromLTRB(16, topPadding, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'الجوائز والمكافآت',
                        style: GoogleFonts.ibmPlexSansArabic(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: AppColors.dark,
                        ),
                      ),
                      const SizedBox(height: 20),

                      Expanded(
                        child: StreamBuilder<QuerySnapshot>(
                          stream: FirebaseFirestore.instance
                              .collection('rewards')
                              .orderBy('createdAt', descending: true)
                              .snapshots(),
                          builder: (context, snapshot) {
                            if (snapshot.connectionState ==
                                ConnectionState.waiting) {
                              return const Center(
                                child: CircularProgressIndicator(),
                              );
                            }
                            if (!snapshot.hasData ||
                                snapshot.data!.docs.isEmpty) {
                              return const Center(
                                child: Text('لا يوجد مكافآت مضافة حالياً'),
                              );
                            }

                            final rewards = snapshot.data!.docs;

                            return ListView.builder(
                              physics: const BouncingScrollPhysics(),
                              padding: const EdgeInsets.only(
                                bottom: 100,
                                top: 8,
                              ),
                              itemCount: rewards.length,
                              itemBuilder: (context, i) {
                                final doc = rewards[i];
                                final data =
                                    doc.data() as Map<String, dynamic>? ?? {};

                                return Card(
                                  margin: const EdgeInsets.symmetric(
                                    vertical: 8,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  elevation: 3,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      if ((data['imageUrl'] ?? '')
                                          .toString()
                                          .isNotEmpty)
                                        ClipRRect(
                                          borderRadius: const BorderRadius.only(
                                            topLeft: Radius.circular(16),
                                            topRight: Radius.circular(16),
                                          ),
                                          child: Image.network(
                                            data['imageUrl'],
                                            width: double.infinity,
                                            height: 240,
                                            fit: BoxFit.fitWidth,
                                            alignment: Alignment.center,
                                          ),
                                        )
                                      else
                                        Container(
                                          height: 160,
                                          decoration: const BoxDecoration(
                                            color: AppColors.primary33,
                                            borderRadius: BorderRadius.only(
                                              topLeft: Radius.circular(16),
                                              topRight: Radius.circular(16),
                                            ),
                                          ),
                                          child: const Icon(
                                            Icons.card_giftcard,
                                            color: AppColors.primary,
                                            size: 50,
                                          ),
                                        ),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 12,
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment
                                                      .spaceBetween,
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    data['title'] ?? '',
                                                    style: const TextStyle(
                                                      fontSize: 18,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      color: AppColors.dark,
                                                    ),
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                ),
                                                Container(
                                                  margin: const EdgeInsets.only(
                                                    right: 50,
                                                  ),
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 10,
                                                        vertical: 4,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color:
                                                        (data['isActive'] ==
                                                                    true
                                                                ? Colors.green
                                                                : Colors.grey)
                                                            .withOpacity(0.1),
                                                    border: Border.all(
                                                      color:
                                                          data['isActive'] ==
                                                              true
                                                          ? Colors.green
                                                          : Colors.grey,
                                                      width: 1.4,
                                                    ),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          8,
                                                        ),
                                                  ),
                                                  child: Text(
                                                    data['isActive'] == true
                                                        ? 'نشطة'
                                                        : 'متوقفة',
                                                    style: TextStyle(
                                                      color:
                                                          data['isActive'] ==
                                                              true
                                                          ? Colors.green
                                                          : Colors.grey,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      fontSize: 11,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 6),
                                            Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment
                                                      .spaceBetween,
                                              children: [
                                                Text(
                                                  'النقاط: ${data['costPoints'] ?? '-'}',
                                                  style: const TextStyle(
                                                    fontSize: 15,
                                                    color: Color(0xFF3C3C3B),
                                                  ),
                                                ),
                                                Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    IconButton(
                                                      icon: const Icon(
                                                        Icons.edit_outlined,
                                                        color: Colors.grey,
                                                      ),
                                                      onPressed: () {
                                                        _showAddRewardDialog(
                                                          existingData: data,
                                                          docId: doc.id,
                                                        );
                                                      },
                                                    ),
                                                    IconButton(
                                                      icon: const Icon(
                                                        Icons
                                                            .delete_outline_rounded,
                                                        color: Colors.red,
                                                      ),
                                                      onPressed: () {
                                                        showDialog(
                                                          context: context,
                                                          builder: (ctx) {
                                                            final rewardName =
                                                                data['title'] ??
                                                                'هذه المكافأة';
                                                            return Dialog(
                                                              shape: RoundedRectangleBorder(
                                                                borderRadius:
                                                                    BorderRadius.circular(
                                                                      18,
                                                                    ),
                                                              ),
                                                              child: Padding(
                                                                padding:
                                                                    const EdgeInsets.fromLTRB(
                                                                      20,
                                                                      20,
                                                                      20,
                                                                      12,
                                                                    ),
                                                                child: Column(
                                                                  mainAxisSize:
                                                                      MainAxisSize
                                                                          .min,
                                                                  children: [
                                                                    const Icon(
                                                                      Icons
                                                                          .warning_amber_rounded,
                                                                      size: 48,
                                                                      color: Colors
                                                                          .redAccent,
                                                                    ),
                                                                    const SizedBox(
                                                                      height: 8,
                                                                    ),
                                                                    const Text(
                                                                      'تأكيد الحذف',
                                                                      style: TextStyle(
                                                                        fontSize:
                                                                            20,
                                                                        fontWeight:
                                                                            FontWeight.w800,
                                                                      ),
                                                                    ),
                                                                    const SizedBox(
                                                                      height: 8,
                                                                    ),
                                                                    Text(
                                                                      'هل أنت متأكد من حذف "$rewardName"؟',
                                                                      textAlign:
                                                                          TextAlign
                                                                              .center,
                                                                      style: const TextStyle(
                                                                        color: Colors
                                                                            .black87,
                                                                      ),
                                                                    ),
                                                                    const SizedBox(
                                                                      height:
                                                                          16,
                                                                    ),
                                                                    SizedBox(
                                                                      width: double
                                                                          .infinity,
                                                                      child: FilledButton.icon(
                                                                        icon: const Icon(
                                                                          Icons
                                                                              .delete_outline_rounded,
                                                                        ),
                                                                        label: const Text(
                                                                          'تأكيد الحذف',
                                                                        ),
                                                                        style: FilledButton.styleFrom(
                                                                          backgroundColor:
                                                                              AppColors.primary,
                                                                          padding: const EdgeInsets.symmetric(
                                                                            vertical:
                                                                                14,
                                                                          ),
                                                                          shape: RoundedRectangleBorder(
                                                                            borderRadius: BorderRadius.circular(
                                                                              14,
                                                                            ),
                                                                          ),
                                                                        ),
                                                                        onPressed: () async {
                                                                          try {
                                                                            await FirebaseFirestore.instance
                                                                                .collection(
                                                                                  'rewards',
                                                                                )
                                                                                .doc(
                                                                                  doc.id,
                                                                                )
                                                                                .delete();
                                                                            if (ctx.mounted) {
                                                                              Navigator.pop(
                                                                                ctx,
                                                                              );
                                                                            }
                                                                            ScaffoldMessenger.of(
                                                                              context,
                                                                            ).showSnackBar(
                                                                              SnackBar(
                                                                                content: Text(
                                                                                  'تم حذف "$rewardName" بنجاح 🗑️',
                                                                                ),
                                                                              ),
                                                                            );
                                                                          } catch (
                                                                            e
                                                                          ) {
                                                                            if (ctx.mounted) {
                                                                              Navigator.pop(
                                                                                ctx,
                                                                              );
                                                                            }
                                                                            ScaffoldMessenger.of(
                                                                              context,
                                                                            ).showSnackBar(
                                                                              const SnackBar(
                                                                                content: Text(
                                                                                  'فشل حذف المكافأة ❌',
                                                                                ),
                                                                              ),
                                                                            );
                                                                          }
                                                                        },
                                                                      ),
                                                                    ),
                                                                    const SizedBox(
                                                                      height:
                                                                          10,
                                                                    ),
                                                                    SizedBox(
                                                                      width: double
                                                                          .infinity,
                                                                      child: OutlinedButton(
                                                                        style: OutlinedButton.styleFrom(
                                                                          foregroundColor:
                                                                              Colors.red,
                                                                          side: const BorderSide(
                                                                            color:
                                                                                Colors.red,
                                                                          ),
                                                                          padding: const EdgeInsets.symmetric(
                                                                            vertical:
                                                                                14,
                                                                          ),
                                                                          shape: RoundedRectangleBorder(
                                                                            borderRadius: BorderRadius.circular(
                                                                              14,
                                                                            ),
                                                                          ),
                                                                        ),
                                                                        onPressed: () =>
                                                                            Navigator.pop(
                                                                              ctx,
                                                                            ),
                                                                        child: const Text(
                                                                          'إلغاء',
                                                                        ),
                                                                      ),
                                                                    ),
                                                                  ],
                                                                ),
                                                              ),
                                                            );
                                                          },
                                                        );
                                                      },
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),

          // ✅ بدون BottomNavigationBar — فقط زر إضافة
          floatingActionButton: Padding(
            padding: const EdgeInsets.only(bottom: 8, left: 8),
            child: Align(
              alignment: Alignment.bottomLeft,
              child: _buildAddFab(),
            ),
          ),
          bottomNavigationBar: AdminBottomNav(
            currentIndex: _currentIndex,
            onTap: _onTap,
          ),
        ),
      ),
    );
  }
}
