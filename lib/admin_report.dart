// lib/pages/admin_report.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/services.dart';

/// ألوان خفيفة مستقلة (لو عندك AppColors استبدلها)
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

class _AdminReportPageState extends State<AdminReportPage>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

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
            title: const Text('تقارير الحاويات'),
            centerTitle: true,
            backgroundColor: RColors.primary,
            bottom: TabBar(
              controller: _tab,
              isScrollable: true,
              tabs: const [
                Tab(text: 'الكل'),
                Tab(text: 'قيد المراجعة'),
                Tab(text: 'مقبولة'),
                Tab(text: 'مرفوضة'),
              ],
            ),
          ),
          body: Column(
            children: [
              // شريط البحث
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
                child: _SearchBar(
                  controller: _searchCtrl,
                  hint: 'ابحث بالوصف / النوع / معرف الحاوية…',
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(height: 4),
              Expanded(
                child: TabBarView(
                  controller: _tab,
                  children: [
                    _ReportList(statusFilter: null, searchText: _searchCtrl.text),
                    _ReportList(statusFilter: 'pending', searchText: _searchCtrl.text),
                    _ReportList(statusFilter: 'approved', searchText: _searchCtrl.text),
                    _ReportList(statusFilter: 'rejected', searchText: _searchCtrl.text),
                  ],
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
  final String? statusFilter; // null = الكل
  final String searchText;

  const _ReportList({
    required this.statusFilter,
    required this.searchText,
  });

  Query<Map<String, dynamic>> _baseQuery() {
    final col = FirebaseFirestore.instance.collection('facilityReports');

    if (statusFilter == null) {
      // تبويب "الكل": نرتّب زمنيًا من السحابة
      return col.orderBy('createdAt', descending: true);
    } else {
      // تبويبات الحالة: فلترة فقط (بدون orderBy لتفادي الفهرس المركّب)
      return col.where('decision', isEqualTo: statusFilter);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _baseQuery().snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          debugPrint('🔥 reports query error: ${snap.error}');
          return const Center(child: Text('حدث خطأ أثناء جلب البيانات'));
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        // نأخذ نسخة قابلة للفرز محليًا
        final docs = snap.data!.docs.toList();

        // فرز محلي تنازلي بحسب createdAt عند وجود statusFilter
        if (statusFilter != null) {
          docs.sort((a, b) {
            final ta = (a.data()['createdAt'] as Timestamp?);
            final tb = (b.data()['createdAt'] as Timestamp?);
            final va = ta?.millisecondsSinceEpoch ?? 0;
            final vb = tb?.millisecondsSinceEpoch ?? 0;
            return vb.compareTo(va); // تنازلي
          });
        }

        // فلترة نصية محلية
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

/// بطاقة تقرير واحدة
class _ReportCard extends StatefulWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  const _ReportCard({required this.doc});

  @override
  State<_ReportCard> createState() => _ReportCardState();
}

class _ReportCardState extends State<_ReportCard> {
  bool _busy = false;

  String _statusLabel(String s) {
    switch (s) {
      case 'pending':
        return 'قيد المراجعة';
      case 'approved':
        return 'مقبولة';
      case 'rejected':
        return 'مرفوضة';
      default:
        return s;
    }
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
        return RColors.dark;
    }
  }

  Future<Map<String, dynamic>?> _fetchFacility(String id) async {
    try {
      final snap =
          await FirebaseFirestore.instance.collection('facilities').doc(id).get();
      return snap.data();
    } catch (_) {
      return null;
    }
  }

  Future<void> _updateDecision({
    required String decision,
    String? rejectionReason,
  }) async {
    setState(() => _busy = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      final managedBy = user?.uid ?? 'admin';
      final managedByName = user?.displayName ?? user?.email ?? 'Admin';

      final updates = <String, dynamic>{
        'decision': decision,
        'managedBy': managedBy,
        'managedByName': managedByName,
        'resolvedAt': FieldValue.serverTimestamp(),
      };

      if (rejectionReason != null && rejectionReason.trim().isNotEmpty) {
        updates['rejectionReason'] = rejectionReason.trim();
      }

      await widget.doc.reference.update(updates);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تم تحديث الحالة إلى ${_statusLabel(decision)}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذّر تحديث التقرير')),
        );
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
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              await _updateDecision(decision: 'rejected', rejectionReason: ctrl.text);
            },
            child: const Text('رفض'),
          ),
        ],
      ),
    );
  }

  void _showFacilitySheet(String facilityID) async {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) {
        return FutureBuilder<Map<String, dynamic>?>(
          future: _fetchFacility(facilityID),
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
                child: Text('تعذّر جلب بيانات الحاويات.'),
              );
            }
            final name = (f['name'] ?? '').toString();
            final type = (f['type'] ?? '').toString();
            final provider = (f['provider'] ?? '').toString();
            final address = (f['address'] ?? '').toString();
            final city = (f['city'] ?? '').toString();
            final lat = (f['lat'] as num?)?.toDouble();
            final lng = (f['lng'] as num?)?.toDouble();

            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(name.isEmpty ? 'حاوية بدون اسم' : name,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 6),
                  Text(type, style: const TextStyle(color: Colors.black54)),
                  const SizedBox(height: 8),
                  if (provider.isNotEmpty)
                    Row(children: [
                      const Icon(Icons.factory_outlined, size: 18, color: RColors.dark),
                      const SizedBox(width: 6),
                      Text(provider, style: const TextStyle(fontWeight: FontWeight.w700)),
                    ]),
                  const SizedBox(height: 6),
                  if (address.isNotEmpty || city.isNotEmpty)
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Icon(Icons.place_outlined, size: 18, color: RColors.dark),
                      const SizedBox(width: 6),
                      Expanded(child: Text(address.isNotEmpty ? address : city)),
                    ]),
                  const SizedBox(height: 8),
                  if (lat != null && lng != null)
                    Text('الإحداثيات: $lat, $lng',
                        style: const TextStyle(color: Colors.black54, fontSize: 12)),
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    icon: const Icon(Icons.copy),
                    onPressed: () async {
                      try {
                        await Clipboard.setData(ClipboardData(text: facilityID));
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('تم نسخ معرف الحاوية')),
                        );
                      } catch (_) {}
                    },
                    label: const Text('نسخ معرف الحاوية'),
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

    final decision = (m['decision'] ?? 'pending').toString();
    final description = (m['description'] ?? '').toString();
    final type = (m['type'] ?? '').toString();
    final facilityID = (m['facilityID'] ?? '').toString();
    final reportedBy = (m['reportedBy'] ?? 'unknown').toString();
    final managedBy = (m['managedBy'] ?? '').toString();
    final createdAt = (m['createdAt'] as Timestamp?)?.toDate();
    final rejectionReason = (m['rejectionReason'] ?? '').toString();

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // العنوان + الحالة
            Row(
              children: [
                Expanded(
                  child: Text(
                    type.isEmpty ? 'بلاغ حاوية' : type,
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: _statusColor(decision).withOpacity(.12),
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Text(
                    _statusLabel(decision),
                    style: TextStyle(
                      color: _statusColor(decision),
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            if (description.isNotEmpty) ...[
              Text(description),
              const SizedBox(height: 8),
            ],

            Wrap(
              spacing: 10,
              runSpacing: 6,
              children: [
                _Chip(icon: Icons.pin_drop_outlined, label: 'Facility: $facilityID'),
                _Chip(icon: Icons.person_outline, label: 'المبلِّغ: $reportedBy'),
                if (managedBy.isNotEmpty)
                  _Chip(icon: Icons.verified_user_outlined, label: 'المعالج: $managedBy'),
                if (createdAt != null)
                  _Chip(
                      icon: Icons.calendar_month_outlined,
                      label:
                          'التاريخ: ${createdAt.year}/${createdAt.month}/${createdAt.day}'),
              ],
            ),

            if (rejectionReason.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('سبب الرفض: $rejectionReason',
                  style: const TextStyle(color: Colors.redAccent)),
            ],

            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.info_outline),
                    onPressed: facilityID.isEmpty ? null : () => _showFacilitySheet(facilityID),
                    label: const Text('تفاصيل الحاوية'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    icon: const Icon(Icons.check_circle_outline),
                    onPressed: _busy || decision == 'approved'
                        ? null
                        : () => _updateDecision(decision: 'approved'),
                    label: const Text('اعتماد'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: Colors.red),
                    icon: const Icon(Icons.cancel_outlined),
                    onPressed: _busy || decision == 'rejected'
                        ? null
                        : _confirmReject,
                    label: const Text('رفض'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.refresh),
                    onPressed: _busy || decision == 'pending'
                        ? null
                        : () => _updateDecision(decision: 'pending'),
                    label: const Text('إرجاع لقيد المراجعة'),
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

/* ------------- Widgets صغيرة مساعدة ------------- */

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
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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
