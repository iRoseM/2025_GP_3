import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/services.dart';

import 'services/connection.dart';
import 'services/title_header.dart';
import 'services/background_container.dart';
import '../services/app_colors.dart';

class AdminTaskReportsPage extends StatefulWidget {
  const AdminTaskReportsPage({super.key});

  @override
  State<AdminTaskReportsPage> createState() => _AdminTaskReportsPageState();
}

class _AdminTaskReportsPageState extends State<AdminTaskReportsPage> {
  final GlobalKey<ScaffoldMessengerState> _messengerKey =
      GlobalKey<ScaffoldMessengerState>();

  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _checkNetOnce();
  }

  Future<void> _checkNetOnce() async {
    if (!await hasInternetConnection()) {
      if (mounted) showNoInternetDialog(context);
    }
  }

  /// الحالات (Labels بالعربي -> decision بالقيمة)
  final Map<String, String> statusMap = const {
    'قيد المراجعة': 'pending',
    'تم الاعتماد': 'approved',
    'مرفوض': 'rejected',
  };

  /// الحالات المختارة في الفلتر (Labels)
  final Set<String> _selectedStatusLabels = {};

  void _showStatusFilterSheet() {
    final statuses = statusMap.keys.toList();
    final localSelected = Set<String>.from(_selectedStatusLabels);

    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setSt) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'تصفية بلاغات المهام حسب الحالة',
                    style: GoogleFonts.ibmPlexSansArabic(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: statuses.map((label) {
                      final selected = localSelected.contains(label);
                      return FilterChip(
                        label: Text(
                          label,
                          style: GoogleFonts.ibmPlexSansArabic(),
                        ),
                        selected: selected,
                        selectedColor: slackMesseges.primary.withOpacity(.15),
                        labelStyle: TextStyle(
                          color: selected
                              ? slackMesseges.primary
                              : Colors.black87,
                          fontWeight: FontWeight.w700,
                        ),
                        onSelected: (v) {
                          setSt(() {
                            if (v) {
                              localSelected.add(label);
                            } else {
                              localSelected.remove(label);
                            }
                          });
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: slackMesseges.primary,
                    ),
                    onPressed: () {
                      Navigator.pop(context);
                      setState(() {
                        _selectedStatusLabels
                          ..clear()
                          ..addAll(localSelected);
                      });
                    },
                    child: Text(
                      'تطبيق',
                      style: GoogleFonts.ibmPlexSansArabic(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                      setState(() => _selectedStatusLabels.clear());
                    },
                    child: Text(
                      'إلغاء الفلاتر',
                      style: GoogleFonts.ibmPlexSansArabic(),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final baseTheme = Theme.of(context);
    final textTheme = GoogleFonts.ibmPlexSansArabicTextTheme(
      baseTheme.textTheme,
    );

    final selectedDecisionValues = _selectedStatusLabels
        .map((label) => statusMap[label])
        .whereType<String>()
        .toList();

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Theme(
        data: baseTheme.copyWith(textTheme: textTheme),
        child: ScaffoldMessenger(
          key: _messengerKey,
          child: Scaffold(
            extendBody: true,
            backgroundColor: Colors.transparent,
            extendBodyBehindAppBar: true,
            appBar: const NameerAppBar(showTitleInBar: false, showBack: true),
            body: AnimatedBackgroundContainer(
              child: Builder(
                builder: (context) {
                  final statusBar = MediaQuery.of(context).padding.top;
                  const headerH = 20.0;
                  const gap = 12.0;
                  final topPadding = statusBar + headerH + gap;

                  return Padding(
                    padding: EdgeInsets.fromLTRB(12, topPadding, 12, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'بلاغات المهام',
                          style: GoogleFonts.ibmPlexSansArabic(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            color: appColors.dark,
                          ),
                        ),
                        const SizedBox(height: 15),
                        Row(
                          children: [
                            Expanded(
                              child: _SearchBar(
                                controller: _searchCtrl,
                                hint: 'ابحث باسم المهمة أو نص البلاغ…',
                                onChanged: (_) => setState(() {}),
                              ),
                            ),
                            const SizedBox(width: 8),
                            InkWell(
                              onTap: _showStatusFilterSheet,
                              borderRadius: BorderRadius.circular(14),
                              child: Container(
                                height: 48,
                                width: 48,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(14),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Color(0x14000000),
                                      blurRadius: 12,
                                      offset: Offset(0, 6),
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                  Icons.tune,
                                  color: slackMesseges.primary,
                                  size: 24,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: _TaskReportList(
                            statusFilters: selectedDecisionValues,
                            searchText: _searchCtrl.text,
                            messengerKey: _messengerKey,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TaskReportList extends StatelessWidget {
  final List<String> statusFilters;
  final String searchText;
  final GlobalKey<ScaffoldMessengerState> messengerKey;

  const _TaskReportList({
    required this.statusFilters,
    required this.searchText,
    required this.messengerKey,
  });

  Query<Map<String, dynamic>> _baseQuery() {
    return FirebaseFirestore.instance
        .collection('taskReports')
        .orderBy('createdAt', descending: true);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _baseQuery().snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return const Center(child: Text('حدث خطأ أثناء جلب البيانات'));
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snap.data!.docs.toList();

        // نخلي pending فوق
        docs.sort((a, b) {
          final da = (a.data()['decision'] ?? 'pending') as String;
          final db = (b.data()['decision'] ?? 'pending') as String;
          if (da == 'pending' && db != 'pending') return -1;
          if (db == 'pending' && da != 'pending') return 1;
          return 0;
        });

        final s = searchText.trim().toLowerCase();
        final hasStatusFilter = statusFilters.isNotEmpty;

        final filtered = docs.where((d) {
          final m = d.data();

          bool matchStatus = true;
          if (hasStatusFilter) {
            final decision = (m['decision'] ?? '').toString();
            matchStatus = statusFilters.contains(decision);
          }

          bool matchSearch = true;
          if (s.isNotEmpty) {
            final hay = [
              m['taskTitle'] ?? '',
              m['description'] ?? '',
              m['reportText'] ?? '',
              m['taskId'] ?? '',
              m['reportedBy'] ?? '',
            ].join(' ').toLowerCase();
            matchSearch = hay.contains(s);
          }

          return matchStatus && matchSearch;
        }).toList();

        if (filtered.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Image.asset(
                  'assets/img/nameerSleep.png',
                  width: 200,
                  height: 200,
                  fit: BoxFit.contain,
                ),
                const SizedBox(height: 16),
                Text(
                  'لا توجد بلاغات مهام حالياً 🌿',
                  style: GoogleFonts.ibmPlexSansArabic(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: slackMesseges.sea,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: () async {
            if (!await hasInternetConnection()) {
              if (context.mounted) showNoInternetDialog(context);
              return;
            }
          },
          child: ListView.separated(
            key: UniqueKey(),
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
            itemCount: filtered.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              return _TaskReportCard(
                doc: filtered[i],
                messengerKey: messengerKey,
              );
            },
          ),
        );
      },
    );
  }
}

class _TaskReportCard extends StatefulWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final GlobalKey<ScaffoldMessengerState> messengerKey;

  const _TaskReportCard({
    required this.doc,
    required this.messengerKey,
    super.key,
  });

  @override
  State<_TaskReportCard> createState() => _TaskReportCardState();
}

class _TaskReportCardState extends State<_TaskReportCard> {
  bool _busy = false;
  void _openReportImage(String imageUrl) {
    showDialog(
      context: context,
      builder: (_) {
        return Dialog(
          insetPadding: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'صورة البلاغ',
                          style: GoogleFonts.ibmPlexSansArabic(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: appColors.dark,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(18),
                  ),
                  child: InteractiveViewer(
                    child: Image.network(
                      imageUrl,
                      fit: BoxFit.contain,
                      loadingBuilder: (context, child, progress) {
                        if (progress == null) return child;
                        return const SizedBox(
                          height: 260,
                          child: Center(child: CircularProgressIndicator()),
                        );
                      },
                      errorBuilder: (context, error, stackTrace) {
                        return SizedBox(
                          height: 220,
                          child: Center(
                            child: Text(
                              'تعذر تحميل الصورة',
                              style: GoogleFonts.ibmPlexSansArabic(
                                color: slackMesseges.red,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Color _statusColor(String s) {
    switch (s) {
      case 'pending':
        return Colors.orange;
      case 'approved':
        return Colors.green;
      case 'rejected':
        return Colors.red;
      default:
        return slackMesseges.sea;
    }
  }

  String _statusLabel(String s) {
    switch (s) {
      case 'pending':
        return 'قيد المراجعة';
      case 'approved':
        return 'تم الاعتماد';
      case 'rejected':
        return 'مرفوض';
      default:
        return s;
    }
  }

  Future<String> _getUserName(String uid) async {
    if (uid.isEmpty) return '';
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      if (!snap.exists) return uid;
      final data = snap.data() ?? {};
      return (data['username'] ?? data['name'] ?? uid).toString();
    } catch (_) {
      return uid;
    }
  }

  void _openInfoSheet({required String reportId, required String taskId}) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'تفاصيل البلاغ',
                  style: GoogleFonts.ibmPlexSansArabic(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                  textAlign: TextAlign.right,
                ),
                const SizedBox(height: 14),
                _infoRow(
                  label: 'Report ID',
                  value: reportId,
                  onCopy: () =>
                      Clipboard.setData(ClipboardData(text: reportId)),
                ),
                const SizedBox(height: 10),
                _infoRow(
                  label: 'Task ID',
                  value: taskId.isEmpty ? '—' : taskId,
                  onCopy: taskId.isEmpty
                      ? null
                      : () => Clipboard.setData(ClipboardData(text: taskId)),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: slackMesseges.primary,
                    minimumSize: const Size(0, 48),
                  ),
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(
                    'تم',
                    style: GoogleFonts.ibmPlexSansArabic(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _infoRow({
    required String label,
    required String value,
    VoidCallback? onCopy,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F6F8),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 74,
            child: Text(
              '$label:',
              style: GoogleFonts.ibmPlexSansArabic(
                fontWeight: FontWeight.w800,
                color: appColors.dark,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.ibmPlexSansArabic(
                color: Colors.grey[700],
                height: 1.3,
              ),
              textAlign: TextAlign.left,
            ),
          ),
          if (onCopy != null) ...[
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'نسخ',
              onPressed: () async {
                onCopy();
                final messenger = widget.messengerKey.currentState;
                messenger
                  ?..clearSnackBars()
                  ..showSnackBar(
                    SnackBar(
                      backgroundColor: slackMesseges.primary,
                      content: Text(
                        'تم النسخ ✅',
                        style: GoogleFonts.ibmPlexSansArabic(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  );
              },
              icon: const Icon(Icons.copy, size: 18),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _updateDecision(String decision, {String? reason}) async {
    if (!await hasInternetConnection()) {
      if (mounted) showNoInternetDialog(context);
      return;
    }

    setState(() => _busy = true);

    try {
      final adminId = FirebaseAuth.instance.currentUser?.uid;
      final note = (reason ?? '').trim();

      await widget.doc.reference.update({
        'decision': decision,
        'reviewedAt': FieldValue.serverTimestamp(),
        'reviewedBy': adminId,
        if (note.isNotEmpty) 'adminNote': note,
      });

      final m = widget.doc.data();
      final reportedBy = (m['reportedBy'] ?? '').toString();
      final taskTitle = (m['taskTitle'] ?? 'مهمة').toString();

      final notifTitle = decision == 'approved'
          ? 'تم معالجة البلاغ'
          : decision == 'rejected'
          ? 'تم رفض البلاغ'
          : 'تم تحديث حالة البلاغ';

      String notifBody;

      if (decision == 'approved') {
        notifBody =
            'تمت معالجة البلاغ الخاص بمهمة "$taskTitle". نسعى دائمًا لتحسين تجربتك💚';

        if (note.isNotEmpty) {
          notifBody += '\nملاحظة: $note';
        }
      } else if (decision == 'rejected') {
        notifBody =
            'بعد التحقق من البلاغ الخاص بمهمة "$taskTitle"، تبيّن أنه غير صحيح ♻️';

        if (note.isNotEmpty) {
          notifBody += '\nسبب الرفض: $note';
        }
      } else {
        notifBody =
            'تم إرجاع البلاغ الخاص بمهمة "$taskTitle" إلى قيد المراجعة.';
      }

      await FirebaseFirestore.instance.collection('notifications').add({
        'type': decision == 'approved'
            ? 'task_report_approved'
            : decision == 'rejected'
            ? 'task_report_rejected'
            : 'task_report_pending',
        'userId': reportedBy,
        'reportId': widget.doc.id,
        'createdAt': FieldValue.serverTimestamp(),
        'seen': false,
        'title': notifTitle,
        'body': notifBody,
        if (note.isNotEmpty) 'adminNote': note,
      });

      final messenger = widget.messengerKey.currentState;

      if (messenger != null) {
        String msg;
        Color bg;

        if (decision == 'approved') {
          msg = 'تم اعتماد البلاغ وإشعار المستخدم ✅';
          bg = slackMesseges.primary;
        } else if (decision == 'rejected') {
          msg = 'تم رفض البلاغ وإشعار المستخدم ❌';
          bg = slackMesseges.red;
        } else {
          msg = 'تم إرجاع البلاغ لقيد المراجعة 🔄';
          bg = slackMesseges.primary;
        }

        messenger
          ..clearSnackBars()
          ..showSnackBar(
            SnackBar(
              backgroundColor: bg,
              content: Text(
                msg,
                style: GoogleFonts.ibmPlexSansArabic(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          );
      }
    } catch (_) {
      final messenger = widget.messengerKey.currentState;
      if (messenger != null) {
        messenger
          ..clearSnackBars()
          ..showSnackBar(
            SnackBar(
              backgroundColor: slackMesseges.red,
              content: Text(
                'حدث خطأ أثناء تحديث حالة البلاغ. يرجى المحاولة مرة أخرى.',
                style: GoogleFonts.ibmPlexSansArabic(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _confirmApprove() {
    final ctrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        final bottomInset = MediaQuery.of(ctx).viewInsets.bottom;

        return Directionality(
          textDirection: TextDirection.rtl,
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomInset),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'اعتماد البلاغ',
                  textAlign: TextAlign.right,
                  style: GoogleFonts.ibmPlexSansArabic(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: ctrl,
                  maxLines: 3,
                  textAlign: TextAlign.right,
                  decoration: InputDecoration(
                    labelText: 'سبب الاعتماد (اختياري)',
                    hintText: 'اكتب ملاحظة تظهر للمستخدم',
                    alignLabelWithHint: true,
                    border: const OutlineInputBorder(),
                    labelStyle: GoogleFonts.ibmPlexSansArabic(),
                    hintStyle: GoogleFonts.ibmPlexSansArabic(),
                  ),
                  style: GoogleFonts.ibmPlexSansArabic(),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: slackMesseges.primary,
                          minimumSize: const Size(0, 50),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                          padding: EdgeInsets.zero,
                        ),
                        onPressed: _busy
                            ? null
                            : () async {
                                Navigator.pop(ctx);
                                await _updateDecision(
                                  'approved',
                                  reason: ctrl.text.trim(),
                                );
                              },
                        child: Text(
                          'تأكيد الاعتماد',
                          style: GoogleFonts.ibmPlexSansArabic(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 50),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                          side: BorderSide(
                            color: Colors.grey.shade500,
                            width: 1.4,
                          ),
                          padding: EdgeInsets.zero,
                        ),
                        onPressed: () => Navigator.pop(ctx),
                        child: Text(
                          'إلغاء',
                          style: GoogleFonts.ibmPlexSansArabic(
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
        );
      },
    );
  }

  void _confirmReject() {
    final ctrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        final bottomInset = MediaQuery.of(ctx).viewInsets.bottom;

        return Directionality(
          textDirection: TextDirection.rtl,
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomInset),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'رفض البلاغ',
                  textAlign: TextAlign.right,
                  style: GoogleFonts.ibmPlexSansArabic(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: ctrl,
                  maxLines: 3,
                  textAlign: TextAlign.right,
                  decoration: InputDecoration(
                    labelText: 'سبب الرفض (اختياري)',
                    hintText: 'اكتب سببًا موجزًا',
                    alignLabelWithHint: true,
                    border: const OutlineInputBorder(),
                    labelStyle: GoogleFonts.ibmPlexSansArabic(),
                    hintStyle: GoogleFonts.ibmPlexSansArabic(),
                  ),
                  style: GoogleFonts.ibmPlexSansArabic(),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 50),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                          padding: EdgeInsets.zero,
                        ),
                        onPressed: _busy
                            ? null
                            : () async {
                                Navigator.pop(ctx);
                                await _updateDecision(
                                  'rejected',
                                  reason: ctrl.text.trim(),
                                );
                              },
                        child: Text(
                          'تأكيد الرفض',
                          style: GoogleFonts.ibmPlexSansArabic(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 50),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                          side: BorderSide(
                            color: Colors.grey.shade500,
                            width: 1.4,
                          ),
                          padding: EdgeInsets.zero,
                        ),
                        onPressed: () => Navigator.pop(ctx),
                        child: Text(
                          'إلغاء',
                          style: GoogleFonts.ibmPlexSansArabic(
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
        );
      },
    );
  }

  void _confirmReturn() {
    showDialog(
      context: context,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text(
            'إرجاع لقيد المراجعة',
            style: GoogleFonts.ibmPlexSansArabic(fontWeight: FontWeight.w800),
          ),
          content: Text(
            'هل تريد تأكيد إرجاع هذا البلاغ لقيد المراجعة؟',
            style: GoogleFonts.ibmPlexSansArabic(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('إلغاء', style: GoogleFonts.ibmPlexSansArabic()),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.pop(context);
                await _updateDecision('pending');
              },
              child: Text('تأكيد', style: GoogleFonts.ibmPlexSansArabic()),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.doc.data();

    final decision = (m['decision'] ?? 'pending').toString();
    final taskTitle = (m['taskTitle'] ?? 'مهمة بدون عنوان').toString();
    final description = (m['description'] ?? m['reportText'] ?? '').toString();
    final imageUrl = (m['imageUrl'] ?? '').toString();
    final taskId = (m['taskId'] ?? '').toString();
    final reportedBy = (m['reportedBy'] ?? '').toString();
    final createdAt = (m['createdAt'] as Timestamp?)?.toDate();

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // العنوان + أيقونات
            Row(
              children: [
                Expanded(
                  child: Text(
                    taskTitle, // ✅ اسم المهمة هنا بدل "بلاغ مهمة"
                    style: GoogleFonts.ibmPlexSansArabic(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                      color: appColors.dark,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.info_outline, // ✅ ℹ️
                    color: slackMesseges.primary,
                  ),
                  tooltip: 'تفاصيل البلاغ',
                  onPressed: () =>
                      _openInfoSheet(reportId: widget.doc.id, taskId: taskId),
                ),
                if (decision != 'pending')
                  IconButton(
                    icon: const Icon(
                      Icons.refresh,
                      color: slackMesseges.primary,
                    ),
                    tooltip: 'إرجاع لقيد المراجعة',
                    onPressed: _busy ? null : _confirmReturn,
                  ),
              ],
            ),

            const SizedBox(height: 4),

            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: _statusColor(decision).withOpacity(.12),
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Text(
                  _statusLabel(decision),
                  style: TextStyle(
                    color: _statusColor(decision),
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 8),

            // ✅ البلاغ تحت اسم المهمة
            if (description.isNotEmpty) ...[
              Text(
                'البلاغ: $description',
                style: GoogleFonts.ibmPlexSansArabic(
                  fontSize: 13.5,
                  color: Colors.grey[800],
                  height: 1.5,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ] else ...[
              Text(
                'البلاغ: —',
                style: GoogleFonts.ibmPlexSansArabic(
                  fontSize: 13.5,
                  color: Colors.grey[600],
                  height: 1.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],

            const SizedBox(height: 10),
            if (imageUrl.isNotEmpty) ...[
              const SizedBox(height: 10),
              InkWell(
                onTap: () => _openReportImage(imageUrl),
                borderRadius: BorderRadius.circular(14),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Stack(
                    children: [
                      Image.network(
                        imageUrl,
                        width: double.infinity,
                        height: 150,
                        fit: BoxFit.cover,
                        loadingBuilder: (context, child, progress) {
                          if (progress == null) return child;
                          return Container(
                            width: double.infinity,
                            height: 150,
                            color: const Color(0xFFF3F6F8),
                            child: const Center(
                              child: CircularProgressIndicator(),
                            ),
                          );
                        },
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            width: double.infinity,
                            height: 110,
                            decoration: BoxDecoration(
                              color: const Color(0xFFF3F6F8),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Center(
                              child: Text(
                                'تعذر تحميل الصورة',
                                style: GoogleFonts.ibmPlexSansArabic(
                                  color: slackMesseges.red,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                      Positioned(
                        left: 8,
                        bottom: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(.45),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.zoom_in,
                                color: Colors.white,
                                size: 16,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'عرض الصورة',
                                style: GoogleFonts.ibmPlexSansArabic(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                FutureBuilder<String>(
                  future: _getUserName(reportedBy),
                  builder: (context, snap) {
                    final userName =
                        (snap.data != null && snap.data!.isNotEmpty)
                        ? snap.data!
                        : reportedBy;
                    return _Chip(
                      icon: Icons.person_outline,
                      label: 'المبلِّغ: $userName',
                    );
                  },
                ),
                if (createdAt != null)
                  _Chip(
                    icon: Icons.calendar_month_outlined,
                    label:
                        'التاريخ: ${createdAt.year}/${createdAt.month}/${createdAt.day}',
                  ),
              ],
            ),

            const SizedBox(height: 10),

            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    icon: const Icon(Icons.check_circle_outline),
                    label: Text(
                      'اعتماد',
                      style: GoogleFonts.ibmPlexSansArabic(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    onPressed: _busy || decision == 'approved'
                        ? null
                        : _confirmApprove,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color.fromARGB(255, 220, 92, 83),
                    ),
                    icon: const Icon(Icons.cancel_outlined),
                    label: Text(
                      'رفض',
                      style: GoogleFonts.ibmPlexSansArabic(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    onPressed: _busy || decision == 'rejected'
                        ? null
                        : _confirmReject,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String>? onChanged;

  const _SearchBar({
    required this.controller,
    required this.hint,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 2,
      borderRadius: BorderRadius.circular(14),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: GoogleFonts.ibmPlexSansArabic(),
          prefixIcon: const Icon(Icons.search),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 12,
          ),
        ),
        style: GoogleFonts.ibmPlexSansArabic(),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _Chip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final maxWidth = MediaQuery.of(context).size.width * 0.8;

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFF3F6F8),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: slackMesseges.sea),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                label,
                style: GoogleFonts.ibmPlexSansArabic(fontSize: 12, height: 1.3),
                softWrap: true,
                overflow: TextOverflow.visible,
                maxLines: 3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
