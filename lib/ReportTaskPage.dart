import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';

import 'services/background_container.dart';
import 'services/connection.dart';
import 'services/title_header.dart';
import '../services/app_colors.dart';

class ReportTaskPage extends StatefulWidget {
  const ReportTaskPage({super.key});

  @override
  State<ReportTaskPage> createState() => _ReportTaskPageState();
}

class _ReportTaskPageState extends State<ReportTaskPage> {
  final _descCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  String? _uid;

  // ✅ selected task (from tasks OR from recent completed)
  String? _selectedTaskId;
  String? _selectedTaskTitle;

  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _checkConnection();
    _uid = FirebaseAuth.instance.currentUser?.uid;
  }

  Future<void> _checkConnection() async {
    if (!await hasInternetConnection()) {
      if (mounted) showNoInternetDialog(context);
    }
  }

  @override
  void dispose() {
    _descCtrl.dispose();
    super.dispose();
  }

  // ===== helpers =====
  String _monthKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}';

  // آخر 3 مهام مكتملة (completedAt desc) من userTasks (اختياري كـ “shortcut”)
  Stream<QuerySnapshot<Map<String, dynamic>>> _recentCompletedStream() {
    final uid = _uid ?? '';
    return FirebaseFirestore.instance
        .collection('userTasks')
        .where('userId', isEqualTo: uid)
        .where('status', isEqualTo: 'completed')
        .where('completedAt', isNull: false)
        .orderBy('completedAt', descending: true)
        .limit(3)
        .snapshots(includeMetadataChanges: true);
  }

  // ✅ كل المهام العامة اللي status = active من tasks
  // + فلترة visible_from <= الشهر الحالي (إذا الحقل موجود عندك)
  Stream<QuerySnapshot<Map<String, dynamic>>> _activeTasksStream() {
    final nowKey = _monthKey(DateTime.now()); // مثل "2026-01"

    // يحتاج غالباً index: status + visible_from
    return FirebaseFirestore.instance
        .collection('tasks')
        .where('status', isEqualTo: 'active')
        .where('visible_from', isLessThanOrEqualTo: nowKey)
        .orderBy('visible_from', descending: true)
        .snapshots(includeMetadataChanges: true);

    // لو ما تبغى/ما عندك visible_from، استخدم هذا بدل اللي فوق:
    // return FirebaseFirestore.instance
    //     .collection('tasks')
    //     .where('status', isEqualTo: 'active')
    //     .snapshots(includeMetadataChanges: true);
  }

  void _pickFromUserTaskDoc(QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data();
    setState(() {
      _selectedTaskId = (m['taskId'] ?? '').toString();
      _selectedTaskTitle = (m['taskTitle'] ?? m['title'] ?? '(بدون عنوان)')
          .toString();
    });
  }

  void _pickFromTaskDoc(QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data();
    setState(() {
      _selectedTaskId = d.id; // ✅ taskId = docId في tasks
      _selectedTaskTitle = (m['title'] ?? '(بدون عنوان)').toString();
    });
  }

  Future<void> _submitReport() async {
    if (_sending) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final uid = _uid ?? FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty) return;

    // ✅ لازم يختار مهمة (من tasks)
    if (_selectedTaskId == null || _selectedTaskId!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: slackMesseges.red,
          content: Text(
            'اختر مهمة أولًا',
            style: GoogleFonts.ibmPlexSansArabic(
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ),
      );
      return;
    }

    setState(() => _sending = true);

    try {
      await FirebaseFirestore.instance.collection('taskReports').add({
        'createdAt': FieldValue.serverTimestamp(),
        'decision': 'pending',
        'description': _descCtrl.text.trim(),
        'reportedBy': uid,

        // ✅ البلاغ صار مربوط بالمهمة العامة نفسها
        'taskId': _selectedTaskId,
        'taskTitle': _selectedTaskTitle ?? '',
      });

      if (!mounted) return;
      _showThanksDialog(
        title: 'شكرًا لك',
        message:
            'تم استلام بلاغك بنجاح\nسيتم مراجعته وسنقوم بإشعارك عند معالجته',
        onDone: () {
          // reset بعد ما يقفل الديالوج (نفس اللي عندك)
          setState(() {
            _descCtrl.clear();
            _selectedTaskId = null;
            _selectedTaskTitle = null;
          });
        },
      );

      // reset
      setState(() {
        _descCtrl.clear();
        _selectedTaskId = null;
        _selectedTaskTitle = null;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: slackMesseges.red,
          content: Text(
            'صار خطأ: $e',
            style: GoogleFonts.ibmPlexSansArabic(
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _showThanksDialog({
    required String title,
    required String message,
    VoidCallback? onDone,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
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
                    title,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.ibmPlexSansArabic(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: appColors.dark,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.ibmPlexSansArabic(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: appColors.dark,
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
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
                      onPressed: () {
                        Navigator.pop(context);
                        onDone?.call();
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
                ],
              ),
            ),
          ),
        );
      },
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
          appBar: const NameerAppBar(showTitleInBar: false, showBack: true),
          body: AnimatedBackgroundContainer(
            child: Builder(
              builder: (context) {
                final statusBar = MediaQuery.of(context).padding.top;
                const headerH = 20.0;
                const gap = 12.0;
                final topPadding = statusBar + headerH + gap;

                return Padding(
                  padding: EdgeInsets.fromLTRB(16, topPadding, 16, 16),
                  child: Form(
                    key: _formKey,
                    child: ListView(
                      children: [
                        Text(
                          'إبلاغ عن مهمة',
                          style: GoogleFonts.ibmPlexSansArabic(
                            fontSize: 24,
                            fontWeight: FontWeight.w600,
                            color: appColors.dark,
                          ),
                        ),
                        const SizedBox(height: 14),

                        // ===== المهام الحديثة (اختياري shortcut) =====
                        _SectionCard(
                          title: 'المهام الحديثة',
                          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                            stream: _recentCompletedStream(),
                            builder: (context, snap) {
                              if (snap.connectionState ==
                                  ConnectionState.waiting) {
                                return const Center(
                                  child: Padding(
                                    padding: EdgeInsets.all(16),
                                    child: CircularProgressIndicator(),
                                  ),
                                );
                              }
                              if (snap.hasError) {
                                return Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Text(
                                    'خطأ في تحميل المهام الحديثة',
                                    style: GoogleFonts.ibmPlexSansArabic(
                                      color: Colors.grey[700],
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                );
                              }

                              final docs = snap.data?.docs ?? [];
                              if (docs.isEmpty) {
                                return Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Text(
                                    'لا يوجد مهام مكتملة حديثًا.',
                                    style: GoogleFonts.ibmPlexSansArabic(
                                      color: Colors.grey[700],
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                );
                              }

                              return Column(
                                children: docs.map((d) {
                                  final m = d.data();
                                  final title =
                                      (m['taskTitle'] ??
                                              m['title'] ??
                                              '(بدون عنوان)')
                                          .toString();

                                  final isSelected =
                                      (m['taskId'] ?? '').toString() ==
                                      (_selectedTaskId ?? '');

                                  return InkWell(
                                    onTap: () => _pickFromUserTaskDoc(d),
                                    borderRadius: BorderRadius.circular(12),
                                    child: Container(
                                      width: double.infinity,
                                      margin: const EdgeInsets.only(bottom: 8),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 12,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isSelected
                                            ? Colors.white.withOpacity(0.95)
                                            : Colors.white.withOpacity(0.75),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: isSelected
                                              ? const Color(0xFF009688)
                                              : Colors.grey.shade300,
                                          width: isSelected ? 2 : 1,
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(
                                            Icons.history,
                                            color: isSelected
                                                ? const Color(0xFF009688)
                                                : Colors.grey[700],
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Text(
                                              title,
                                              style:
                                                  GoogleFonts.ibmPlexSansArabic(
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.w600,
                                                    color: appColors.dark,
                                                  ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                        ],
                                      ),
                                    ),
                                  );
                                }).toList(),
                              );
                            },
                          ),
                        ),

                        const SizedBox(height: 12),

                        // ===== اختر المهمة (كل active من tasks) =====
                        _SectionCard(
                          title: 'اختر المهمة',
                          child:
                              StreamBuilder<
                                QuerySnapshot<Map<String, dynamic>>
                              >(
                                stream: _activeTasksStream(),
                                builder: (context, snap) {
                                  if (snap.connectionState ==
                                      ConnectionState.waiting) {
                                    return const Padding(
                                      padding: EdgeInsets.all(16),
                                      child: Center(
                                        child: CircularProgressIndicator(),
                                      ),
                                    );
                                  }
                                  if (snap.hasError) {
                                    return Padding(
                                      padding: const EdgeInsets.all(12),
                                      child: Text(
                                        'خطأ في تحميل المهام',
                                        style: GoogleFonts.ibmPlexSansArabic(
                                          color: Colors.grey[700],
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    );
                                  }

                                  final docs = snap.data?.docs ?? [];
                                  if (docs.isEmpty) {
                                    return Padding(
                                      padding: const EdgeInsets.all(12),
                                      child: Text(
                                        'لا يوجد مهام متاحة حاليًا.',
                                        style: GoogleFonts.ibmPlexSansArabic(
                                          color: Colors.grey[700],
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    );
                                  }

                                  // selected is taskId (docId)
                                  final validSelected =
                                      docs.any((d) => d.id == _selectedTaskId)
                                      ? _selectedTaskId
                                      : null;

                                  return DropdownButtonFormField<String>(
                                    value: validSelected,
                                    isExpanded: true,
                                    decoration: InputDecoration(
                                      filled: true,
                                      fillColor: Colors.white.withOpacity(0.85),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(14),
                                        borderSide: BorderSide(
                                          color: Colors.grey.shade300,
                                        ),
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(14),
                                        borderSide: BorderSide(
                                          color: Colors.grey.shade300,
                                        ),
                                      ),
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 12,
                                          ),
                                    ),
                                    hint: Text(
                                      'اختر المهمة',
                                      style: GoogleFonts.ibmPlexSansArabic(
                                        color: Colors.grey[700],
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    items: docs.map((d) {
                                      final m = d.data();
                                      final title =
                                          (m['title'] ?? '(بدون عنوان)')
                                              .toString();
                                      return DropdownMenuItem<String>(
                                        value: d.id,
                                        child: Text(
                                          title,
                                          overflow: TextOverflow.ellipsis,
                                          style: GoogleFonts.ibmPlexSansArabic(
                                            fontWeight: FontWeight.w600,
                                            color: appColors.dark,
                                          ),
                                        ),
                                      );
                                    }).toList(),
                                    onChanged: (val) {
                                      if (val == null) return;
                                      final picked = docs.firstWhere(
                                        (d) => d.id == val,
                                      );
                                      _pickFromTaskDoc(picked);
                                    },
                                    validator: (v) {
                                      if (v == null || v.isEmpty)
                                        return 'اختر مهمة';
                                      return null;
                                    },
                                  );
                                },
                              ),
                        ),

                        const SizedBox(height: 12),

                        // ===== وصف البلاغ =====
                        _SectionCard(
                          title: 'وصف البلاغ',
                          child: TextFormField(
                            controller: _descCtrl,
                            minLines: 4,
                            maxLines: 8,
                            decoration: InputDecoration(
                              hintText: 'اكتب تفاصيل البلاغ…',
                              hintStyle: GoogleFonts.ibmPlexSansArabic(
                                color: Colors.grey[600],
                              ),
                              filled: true,
                              fillColor: Colors.white.withOpacity(0.85),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide(
                                  color: Colors.grey.shade300,
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide(
                                  color: Colors.grey.shade300,
                                ),
                              ),
                            ),
                            validator: (v) {
                              final t = (v ?? '').trim();
                              if (t.isEmpty) return 'اكتب وصف البلاغ';
                              if (t.length < 8) {
                                return 'اكتب تفاصيل أكثر (على الأقل 8 أحرف)';
                              }
                              return null;
                            },
                          ),
                        ),

                        const SizedBox(height: 14),

                        Container(
                          width: double.infinity,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [appColors.mint, appColors.primary],
                            ),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            onPressed: _sending ? null : _submitReport,
                            icon: _sending
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(
                                    Icons.report_gmailerrorred_outlined,
                                    color: Colors.white,
                                  ),
                            label: Text(
                              _sending ? 'جاري الإرسال...' : 'إرسال البلاغ',
                              style: GoogleFonts.ibmPlexSansArabic(
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _SectionCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: GoogleFonts.ibmPlexSansArabic(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: appColors.dark,
              ),
            ),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}
