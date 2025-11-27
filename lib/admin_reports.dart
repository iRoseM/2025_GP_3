// lib/pages/admin_report.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/services.dart';

import 'services/fcm_service.dart';
import 'services/connection.dart';
import 'services/title_header.dart';
import 'services/background_container.dart';
import '../services/app_colors.dart';

class AdminReportPage extends StatefulWidget {
  const AdminReportPage({super.key});

  @override
  State<AdminReportPage> createState() => _AdminReportPageState();
}

class _AdminReportPageState extends State<AdminReportPage> {
  final GlobalKey<ScaffoldMessengerState> _messengerKey =
      GlobalKey<ScaffoldMessengerState>();

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

  final TextEditingController _searchCtrl = TextEditingController();

  /// 🔹 الآن ما فيه "الكل"؛ عندنا الحالات الثلاث فقط
  final Map<String, String> statusMap = const {
    'قيد المراجعة': 'pending',
    'تمت المعالجة': 'approved',
    'البلاغ غير صحيح': 'rejected',
  };

  /// 🔹 الحالات المختارة في الفلتر (Labels بالعربي)
  final Set<String> _selectedStatusLabels = {};

  // 🔹 BottomSheet لتصفية الحالات (متعدد الاختيار)
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
                  const Text(
                    'تصفية البلاغات حسب الحالة',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 12),

                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: statuses.map((label) {
                      final selected = localSelected.contains(label);
                      return FilterChip(
                        label: Text(label),
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
                    child: const Text('تطبيق'),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                      setState(() {
                        _selectedStatusLabels.clear(); // لا شيء → يعرض الكل
                      });
                    },
                    child: const Text('إلغاء الفلاتر'),
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
  Widget build(BuildContext context) {
    final baseTheme = Theme.of(context);
    final textTheme = GoogleFonts.ibmPlexSansArabicTextTheme(
      baseTheme.textTheme,
    );

    // نحول الـ labels المختارة إلى قيم decision الحقيقية
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
                          'بلاغات الحاويات',
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
                                hint: 'ابحث بالوصف / النوع / معرف الحاوية…',
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
                          child: _ReportList(
                            statusFilters: selectedDecisionValues,
                            searchText: _searchCtrl.text,
                            messengerKey: _messengerKey, // ✅ نمرر المفتاح
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

class _ReportList extends StatelessWidget {
  final List<String> statusFilters;
  final String searchText;

  final GlobalKey<ScaffoldMessengerState> messengerKey;

  const _ReportList({
    required this.statusFilters,
    required this.searchText,
    required this.messengerKey,
  });

  Query<Map<String, dynamic>> _baseQuery() {
    final col = FirebaseFirestore.instance.collection('facilityReports');
    // 🔹 دائمًا نجيب الكل مرتّب بتاريخ الإنشاء (الأحدث أولًا)
    return col.orderBy('createdAt', descending: true);
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

        // الأولوية للـ pending
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

          // فلترة بالحالة (لو فيه حالات مختارة)
          bool matchStatus = true;
          if (hasStatusFilter) {
            final decision = (m['decision'] ?? '').toString();
            matchStatus = statusFilters.contains(decision);
          }

          // فلترة بالبحث
          bool matchSearch = true;
          if (s.isNotEmpty) {
            final hay = [
              m['description'] ?? '',
              m['type'] ?? '',
              m['facilityID'] ?? '',
              m['reportedBy'] ?? '',
              m['managedBy'] ?? '',
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
                  'لا توجد بلاغات مسجّلة حالياً 🌿',
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
              final d = filtered[i];
              return _ReportCard(
                doc: d,
                messengerKey: messengerKey, // ✅ نمرر المفتاح للكارت
              );
            },
          ),
        );
      },
    );
  }
}

/// بطاقة التقرير
class _ReportCard extends StatefulWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final GlobalKey<ScaffoldMessengerState> messengerKey;

  const _ReportCard({required this.doc, required this.messengerKey, super.key});

  @override
  State<_ReportCard> createState() => _ReportCardState();
}

class _ReportCardState extends State<_ReportCard> {
  bool _busy = false;

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
        return 'تمت المعالجة';
      case 'rejected':
        return 'البلاغ غير صحيح';
      default:
        return s;
    }
  }

  /// 👤 جلب اسم المستخدم من users/{uid}
  Future<String> _getUserName(String userId) async {
    if (userId.isEmpty) return '';
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .get();
      if (!snap.exists) return userId;
      final data = snap.data() ?? {};
      return data['username'] ?? data['name'] ?? userId;
    } catch (_) {
      return userId;
    }
  }

  /// 🗑️ جلب اسم/وصف الحاوية من facilities/{id}
  Future<String> _getFacilityName(String facilityId) async {
    if (facilityId.isEmpty) return '';
    try {
      final snap = await FirebaseFirestore.instance
          .collection('facilities')
          .doc(facilityId)
          .get();
      if (!snap.exists) return facilityId;
      final data = snap.data() ?? {};
      final name = data['name'] ?? '';
      final type = data['type'] ?? '';
      if ((name as String).trim().isNotEmpty) {
        return name;
      }
      if ((type as String).trim().isNotEmpty) {
        return type;
      }
      return facilityId;
    } catch (_) {
      return facilityId;
    }
  }

  Future<void> _updateDecision(String decision, {String? reason}) async {
    if (!await hasInternetConnection()) {
      if (mounted) showNoInternetDialog(context);
      return;
    }
    setState(() => _busy = true);

    try {
      await widget.doc.reference.update({
        'decision': decision,
        if (reason != null && reason.isNotEmpty) 'rejectionReason': reason,
      });
      // نجيب بيانات البلاغ
      final m = widget.doc.data();
      final reportedBy = (m['reportedBy'] ?? '').toString();
      final facilityId = m['facilityID'] ?? '';

      // نجيب بيانات الحاوية
      Map<String, dynamic>? facility;
      try {
        final fsnap = await FirebaseFirestore.instance
            .collection('facilities')
            .doc(facilityId)
            .get();
        if (fsnap.exists) facility = fsnap.data();
      } catch (_) {}

      final facName = facility?['name'] ?? facility?['type'] ?? 'الحاوية';
      final fullAddress = (facility?['address'] ?? '').toString();

      String district = '';

      // نبحث عن كلمة "حي"
      final idx = fullAddress.indexOf('حي');
      if (idx != -1) {
        // ناخذ النص من "حي" إلى آخر العنوان
        String after = fullAddress.substring(idx).trim();

        // نشيل أي فواصل مباشرة بعد "حي"
        after = after.replaceAll('،', '').replaceAll(',', '').trim();

        // نفصل بالكلمات
        List<String> parts = after.split(RegExp(r'\s+'));

        // "حي شراء" فقط
        if (parts.length >= 2) {
          district = '${parts[0]} ${parts[1]}'.trim();
        } else {
          district = parts[0].trim();
        }

        // نتأكد ما فيها فاصلة مرة ثانية
        district = district.replaceAll('،', '').replaceAll(',', '').trim();
      }

      // =====================================================

      // 🔔 تركيب النصوص
      String notifTitle;
      String notifBody;

      if (decision == 'approved') {
        notifTitle = 'تم معالجة البلاغ';

        if (district.isNotEmpty) {
          notifBody =
              'تم معالجة البلاغ المتعلق بـ "$facName" في $district. شكرًا لتعاونك 🌱';
        } else {
          notifBody =
              'تم معالجة البلاغ المتعلق بـ "$facName". شكرًا لتعاونك 🌱';
        }
      } else {
        notifTitle = 'البلاغ غير صحيح';

        if (district.isNotEmpty) {
          notifBody =
              'بعد التحقق من البلاغ المتعلق بـ "$facName" في $district. تبيّن أنه غير صحيح ♻️';
        } else {
          notifBody =
              'بعد التحقق من البلاغ المتعلق بـ "$facName". تبيّن أنه غير صحيح ♻️';
        }
      }

      // إضافة الإشعار
      await FirebaseFirestore.instance.collection('notifications').add({
        'type': decision == 'approved'
            ? 'facility_report_approved'
            : 'facility_report_rejected',
        'userId': reportedBy,
        'reportId': widget.doc.id,
        'createdAt': FieldValue.serverTimestamp(),
        'seen': false,
        'title': notifTitle,
        'body': notifBody,
      });

      // نحدد الرسالة واللون حسب القرار
      String? successMsg;
      Color? snackColor;

      if (decision == 'approved') {
        successMsg = 'تم اعتماد البلاغ بنجاح ✅';
        snackColor = slackMesseges.primary;
      } else if (decision == 'rejected') {
        successMsg = 'تم رفض البلاغ وإشعار المستخدم ❌';
        snackColor = slackMesseges.red;
      }
      // 👈 لا else: لو رجعتيه لقيد المراجعة ما نعرض SnackBar

      final messenger = widget.messengerKey.currentState;
      if (messenger != null && successMsg != null && snackColor != null) {
        messenger
          ..clearSnackBars()
          ..showSnackBar(
            SnackBar(
              backgroundColor: snackColor,
              content: Text(
                successMsg,
                style: GoogleFonts.ibmPlexSansArabic(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          );
      }
    } catch (e) {
      final messenger = widget.messengerKey.currentState;
      if (messenger != null) {
        messenger
          ..clearSnackBars()
          ..showSnackBar(
            SnackBar(
              backgroundColor: slackMesseges.red,
              content: Text(
                'حدث خطأ أثناء تحديث حالة البلاغ، حاول مرة أخرى.',
                style: GoogleFonts.ibmPlexSansArabic(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
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
                const Text(
                  'رفض التقرير',
                  textAlign: TextAlign.right,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),

                TextField(
                  controller: ctrl,
                  maxLines: 3,
                  textAlign: TextAlign.right,
                  decoration: const InputDecoration(
                    labelText: 'سبب الرفض (اختياري)',
                    hintText: 'اكتب سببًا موجزًا',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(),
                  ),
                ),

                const SizedBox(height: 16),

                Row(
                  children: [
                    // زر تأكيد الرفض (Filled)
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
                        child: const Text('تأكيد الرفض'),
                      ),
                    ),

                    const SizedBox(width: 12),

                    // زر الإلغاء Outlined بنفس الارتفاع
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
                        child: const Text('إلغاء'),
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
          title: const Text('إرجاع لقيد المراجعة'),
          content: const Text(
            'هل أنت متأكد من إرجاع هذا التقرير لقيد المراجعة؟',
          ),
          contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 10),
          actionsPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 8,
          ),
          actions: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('إلغاء'),
                  ),
                ),
                const SizedBox(height: 4),
                FilledButton(
                  onPressed: () async {
                    Navigator.pop(context);
                    await _updateDecision('pending');
                  },
                  child: const Text('تأكيد'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<Map<String, dynamic>?> _fetchFacility(String id) async {
    if (!await hasInternetConnection()) {
      if (mounted) showNoInternetDialog(context);
      return null;
    }
    try {
      final snap = await FirebaseFirestore.instance
          .collection('facilities')
          .doc(id)
          .get();
      return snap.data();
    } catch (_) {
      return null;
    }
  }

  void _showFacilitySheet(String id) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) {
        return FutureBuilder<Map<String, dynamic>?>(
          future: _fetchFacility(id),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const SizedBox(
                height: 160,
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final f = snap.data;
            if (f == null) {
              return const Padding(
                padding: EdgeInsets.all(16),
                child: Text('تعذّر جلب بيانات الحاوية.'),
              );
            }
            final name = f['name'] ?? '';
            final type = f['type'] ?? '';
            final address = f['address'] ?? '';

            return Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    (name is String && name.isNotEmpty)
                        ? name
                        : 'حاوية بدون اسم',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    type.toString(),
                    style: const TextStyle(color: Colors.black54),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    icon: const Icon(Icons.copy),
                    label: const Text(
                      'نسخ معرف الحاوية',
                      textAlign: TextAlign.right,
                    ),
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: id));
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          backgroundColor: appColors.primary,
                          content: Text(
                            'تم نسخ معرف الحاوية',
                            style: GoogleFonts.ibmPlexSansArabic(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      );
                    },
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
  Widget build(BuildContext context) {
    final m = widget.doc.data();
    final decision = m['decision'] ?? 'pending';
    final description = m['description'] ?? '';
    final type = m['type'] ?? 'بلاغ حاوية';
    final facilityID = m['facilityID'] ?? '';
    final reportedBy = m['reportedBy'] ?? '';
    final createdAt = (m['createdAt'] as Timestamp?)?.toDate();

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // الصف العلوي: العنوان + الأيقونات
            Row(
              children: [
                Expanded(
                  child: Text(
                    type,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.info_outline,
                    color: slackMesseges.primary,
                  ),
                  tooltip: 'تفاصيل الحاوية',
                  onPressed: facilityID.isEmpty
                      ? null
                      : () => _showFacilitySheet(facilityID),
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

            if (description.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                description,
                style: const TextStyle(fontSize: 13),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],

            const SizedBox(height: 8),

            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                FutureBuilder<String>(
                  future: _getFacilityName(facilityID.toString()),
                  builder: (context, snap) {
                    final facName = (snap.data != null && snap.data!.isNotEmpty)
                        ? snap.data!
                        : facilityID.toString();
                    return _Chip(
                      icon: Icons.pin_drop_outlined,
                      label: 'الحاوية: $facName',
                    );
                  },
                ),
                FutureBuilder<String>(
                  future: _getUserName(reportedBy.toString()),
                  builder: (context, snap) {
                    final userName =
                        (snap.data != null && snap.data!.isNotEmpty)
                        ? snap.data!
                        : reportedBy.toString();
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
                    label: const Text('اعتماد'),
                    onPressed: _busy || decision == 'approved'
                        ? null
                        : () => _updateDecision('approved'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color.fromARGB(255, 220, 92, 83),
                    ),
                    icon: const Icon(Icons.cancel_outlined),
                    label: const Text('رفض'),
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
          prefixIcon: const Icon(Icons.search),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 12,
          ),
        ),
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
                style: const TextStyle(fontSize: 12, height: 1.3),
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
