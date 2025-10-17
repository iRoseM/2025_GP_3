// lib/pages/admin_report.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/services.dart';

/// ألوان المشروع
class RColors {
  static const primary = Color(0xFF009688);
  static const dark = Color(0xFF00695C);
  static const bg = Color(0xFFFAFCFB);
}

class AdminReportPage extends StatefulWidget {
  const AdminReportPage({super.key});

  @override
  State<AdminReportPage> createState() => _AdminReportPageState();
}

class _AdminReportPageState extends State<AdminReportPage> {
  final TextEditingController _searchCtrl = TextEditingController();
  String selectedStatus = 'الكل';

  final statusMap = {
    'الكل': null,
    'قيد المراجعة': 'pending',
    'تمت المعالجة': 'approved',
    'البلاغ غير صحيح': 'rejected',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).copyWith(
      textTheme: GoogleFonts.ibmPlexSansArabicTextTheme(
        Theme.of(context).textTheme,
      ),
    );

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Theme(
        data: theme,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('بلاغات الحاويات'),
            centerTitle: true,
            backgroundColor: RColors.primary,
          ),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
                child: Row(
                  children: [
                    // شريط البحث (ياخذ المساحة الباقية)
                    Expanded(
                      child: _SearchBar(
                        controller: _searchCtrl,
                        hint: 'ابحث بالوصف / النوع / معرف الحاوية…',
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 8),

                    // أيقونة الفلتر (يسار)
                    SizedBox(
                      height: 48,
                      width: 48,
                      child: DecoratedBox(
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
                        child: PopupMenuButton<String>(
                          icon: const Icon(
                            Icons.filter_list,
                            color: RColors.primary,
                            size: 24,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          itemBuilder: (context) {
                            return statusMap.keys.map((label) {
                              return PopupMenuItem<String>(
                                value: label,
                                child: Text(
                                  label,
                                  textDirection: TextDirection.rtl,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    color: Colors.black,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              );
                            }).toList();
                          },
                          onSelected: (val) {
                            setState(() => selectedStatus = val);
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 4),
              Expanded(
                child: _ReportList(
                  statusFilter: statusMap[selectedStatus],
                  searchText: _searchCtrl.text,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// قائمة التقارير مع فلترة الحالة والبحث
class _ReportList extends StatelessWidget {
  final String? statusFilter;
  final String searchText;

  const _ReportList({required this.statusFilter, required this.searchText});

  Query<Map<String, dynamic>> _baseQuery() {
    final col = FirebaseFirestore.instance.collection('facilityReports');

    if (statusFilter == null) {
      return col.orderBy('createdAt', descending: true);
    } else {
      return col.where('decision', isEqualTo: statusFilter);
    }
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
        if (statusFilter != null) {
          docs.sort((a, b) {
            final ta = (a.data()['createdAt'] as Timestamp?);
            final tb = (b.data()['createdAt'] as Timestamp?);
            final va = ta?.millisecondsSinceEpoch ?? 0;
            final vb = tb?.millisecondsSinceEpoch ?? 0;
            return vb.compareTo(va);
          });
        }

        final s = searchText.trim().toLowerCase();
        final filtered = s.isEmpty
            ? docs
            : docs.where((d) {
                final m = d.data();
                final hay = [
                  m['description'] ?? '',
                  m['type'] ?? '',
                  m['facilityID'] ?? '',
                  m['reportedBy'] ?? '',
                  m['managedBy'] ?? '',
                ].join(' ').toLowerCase();
                return hay.contains(s);
              }).toList();

        if (filtered.isEmpty) {
          return const Center(child: Text('لا توجد تقارير مطابقة.'));
        }

        return RefreshIndicator(
          onRefresh: () async {},
          child: ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
            itemCount: filtered.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final d = filtered[i];
              return _ReportCard(doc: d);
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
  const _ReportCard({required this.doc});

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
        return RColors.dark;
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

  Future<void> _updateDecision(String decision, {String? reason}) async {
    setState(() => _busy = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      final updates = {
        'decision': decision,
        'managedBy': user?.uid ?? 'admin',
        'managedByName': user?.displayName ?? user?.email ?? 'Admin',
        'resolvedAt': FieldValue.serverTimestamp(),
        if (reason != null && reason.isNotEmpty) 'rejectionReason': reason,
      };
      await widget.doc.reference.update(updates);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم تحديث الحالة إلى ${_statusLabel(decision)}'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('تعذّر تحديث التقرير')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _confirmReject() {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('رفض التقرير'),
        content: TextField(
          controller: ctrl,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'سبب الرفض (اختياري)',
            hintText: 'اكتب سببًا موجزًا',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              await _updateDecision('rejected', reason: ctrl.text);
            },
            child: const Text('رفض'),
          ),
        ],
      ),
    );
  }

  void _confirmReturn() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('إرجاع لقيد المراجعة'),
        content: const Text('هل أنت متأكد من إرجاع هذا التقرير لقيد المراجعة؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              await _updateDecision('pending');
            },
            child: const Text('تأكيد'),
          ),
        ],
      ),
    );
  }

  Future<Map<String, dynamic>?> _fetchFacility(String id) async {
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
            final city = f['city'] ?? '';
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name.isEmpty ? 'حاوية بدون اسم' : name,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(type, style: const TextStyle(color: Colors.black54)),
                  const SizedBox(height: 8),
                  if (address.isNotEmpty || city.isNotEmpty)
                    Text('الموقع: $address، $city'),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    icon: const Icon(Icons.copy),
                    label: const Text('نسخ معرف الحاوية'),
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: id));
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('تم نسخ معرف الحاوية')),
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
            // الصف العلوي للأيقونات// الصف العلوي: العنوان + الأيقونات
            Row(
              children: [
                // العنوان "الموقع غير دقيق"
                Expanded(
                  child: Text(
                    type,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                ),

                // أيقونة التفاصيل
                IconButton(
                  icon: const Icon(Icons.info_outline, color: RColors.primary),
                  tooltip: 'تفاصيل الحاوية',
                  onPressed: facilityID.isEmpty
                      ? null
                      : () => _showFacilitySheet(facilityID),
                ),

                // أيقونة الإرجاع (تظهر فقط إذا التقرير مو "قيد المراجعة")
                if (decision != 'pending')
                  IconButton(
                    icon: const Icon(Icons.refresh, color: RColors.primary),
                    tooltip: 'إرجاع لقيد المراجعة',
                    onPressed: _busy ? null : _confirmReturn,
                  ),
              ],
            ),

            const SizedBox(height: 4),

            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // location + الوصف
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (description.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            description,
                            style: const TextStyle(fontSize: 13),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                  ),
                ),

                // الحالة (مقبولة / مرفوضة)
                Container(
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
              ],
            ),

            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _Chip(
                  icon: Icons.pin_drop_outlined,
                  label: 'Facility: $facilityID',
                ),
                _Chip(
                  icon: Icons.person_outline,
                  label: 'المبلِّغ: $reportedBy',
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
                    style: FilledButton.styleFrom(backgroundColor: Colors.red),
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

/// عناصر واجهة صغيرة
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F6F8),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: RColors.dark),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}
