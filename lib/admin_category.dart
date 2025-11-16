import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'services/background_container.dart';
import 'services/title_header.dart';
import 'admin_task.dart';

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

class AdminCategoryPage extends StatefulWidget {
  final String? initialCategoryName; // عشان لو جاي من كرت مهمة

  const AdminCategoryPage({super.key, this.initialCategoryName});

  @override
  State<AdminCategoryPage> createState() => _AdminCategoryPageState();
}

class _AdminCategoryPageState extends State<AdminCategoryPage> {
  final CollectionReference _categoriesCol = FirebaseFirestore.instance
      .collection('categories');

  List<Map<String, dynamic>> _categories = [];
  bool _isLoading = true;
  String searchQuery = '';
  Set<String> _selectedStatusSet = {}; // 'نشطة' / 'غير نشطة'

  @override
  void initState() {
    super.initState();
    _fetchCategories();
  }

  // 🔹 تحميل الفئات من Firestore
  Future<void> _fetchCategories() async {
    try {
      final qs = await _categoriesCol.get();

      final cats = qs.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        data['id'] = doc.id;
        return data;
      }).toList();

      cats.sort((a, b) {
        final init = widget.initialCategoryName;
        if (init != null) {
          final aMatch = (a['name']?.toString() ?? '') == init;
          final bMatch = (b['name']?.toString() ?? '') == init;
          if (aMatch && !bMatch) return -1;
          if (!aMatch && bMatch) return 1;
        }
        return (a['name']?.toString() ?? '').compareTo(
          b['name']?.toString() ?? '',
        );
      });

      setState(() {
        _categories = cats;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  // 🔹 تحويل status حقل الفئة إلى نص عربي
  String _getCategoryStatus(Map<String, dynamic> cat) {
    final status = cat['status'] ?? 'active';
    switch (status) {
      case 'hidden':
        return 'غير نشطة';
      case 'active':
      default:
        return 'نشطة';
    }
  }

  Color _getStatusColor(String statusText) {
    switch (statusText) {
      case 'غير نشطة':
        return Colors.grey;
      case 'نشطة':
        return Colors.green;
      default:
        return Colors.black54;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = GoogleFonts.ibmPlexSansArabicTextTheme(theme.textTheme);
    final isKeyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;

    final query = searchQuery.trim().toLowerCase();

    final filtered = _categories.where((cat) {
      final name = (cat['name']?.toString() ?? '').toLowerCase();
      final desc = (cat['description']?.toString() ?? '').toLowerCase();
      final statusText = _getCategoryStatus(cat);

      final matchesSearch =
          query.isEmpty || name.contains(query) || desc.contains(query);

      final matchesStatus =
          _selectedStatusSet.isEmpty || _selectedStatusSet.contains(statusText);

      return matchesSearch && matchesStatus;
    }).toList();

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Theme(
        data: theme.copyWith(textTheme: textTheme),
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
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'فئات المهام',
                              style: GoogleFonts.ibmPlexSansArabic(
                                fontSize: 24,
                                fontWeight: FontWeight.w700,
                                color: AppColors.dark,
                              ),
                            ),
                            const SizedBox(height: 14),
                            _buildSearchAndFilterRow(),
                            const SizedBox(height: 12),
                            Expanded(child: _buildCategoryList(filtered)),
                          ],
                        ),
                );
              },
            ),
          ),
          floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
          floatingActionButton: isKeyboardOpen ? null : _buildAddFab(),
        ),
      ),
    );
  }

  // 🔘 زر + لإضافة مهمة/فئة
  Widget _buildAddFab() {
    return Padding(
      padding: const EdgeInsets.only(right: 300, bottom: 10),
      child: FloatingActionButton(
        backgroundColor: AppColors.primary,
        shape: const CircleBorder(),
        onPressed: _showAddOptionsSheet,
        child: const Icon(Icons.add, color: Colors.white, size: 28),
      ),
    );
  }

  // 🔻 BottomSheet: إضافة مهمة / إضافة فئة
  void _showAddOptionsSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            boxShadow: [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 10,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'إضافة عنصر جديد',
                style: GoogleFonts.ibmPlexSansArabic(
                  color: AppColors.dark,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 20),

              // 🔹 إضافة مهمة جديدة
              _gradientActionButton(
                icon: Icons.check_circle_outline,
                label: 'إضافة مهمة جديدة',
                colors: const [AppColors.primary, AppColors.mint],
                onTap: () async {
                  Navigator.pop(context);

                  final taskCategories = _categories
                      .map((cat) => cat['name']?.toString())
                      .where((name) => name != null && name!.isNotEmpty)
                      .cast<String>()
                      .toList();

                  final updated = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AddTaskPage(categories: taskCategories),
                    ),
                  );

                  if (updated == true) {
                    _fetchCategories();
                  }
                },
              ),
              const SizedBox(height: 12),

              // 🔹 إضافة فئة جديدة
              _gradientActionButton(
                icon: Icons.category_outlined,
                label: 'إضافة فئة جديدة',
                colors: const [AppColors.mint, AppColors.primary],
                onTap: () async {
                  Navigator.pop(context);
                  final updated = await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const AddCategoryPage()),
                  );
                  if (updated == true) _fetchCategories();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 🔹 زر Gradient مع أيقونة
  Widget _gradientActionButton({
    required IconData icon,
    required String label,
    required List<Color> colors,
    required VoidCallback onTap,
  }) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: colors),
        borderRadius: BorderRadius.circular(14),
      ),
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        icon: Icon(icon, color: Colors.white),
        label: Text(
          label,
          style: GoogleFonts.ibmPlexSansArabic(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
        onPressed: onTap,
      ),
    );
  }

  // 🔍 شريط البحث + زر الفلتر
  Widget _buildSearchAndFilterRow() {
    final controller = TextEditingController(text: searchQuery);
    return Row(
      children: [
        Expanded(
          child: Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            elevation: 4,
            child: TextField(
              controller: controller,
              onChanged: (v) => setState(() => searchQuery = v),
              decoration: const InputDecoration(
                hintText: 'ابحث عن فئة...',
                prefixIcon: Icon(Icons.search, color: AppColors.primary),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        InkWell(
          onTap: _showFilterSheet,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.all(12),
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
            child: const Icon(Icons.tune, color: AppColors.dark),
          ),
        ),
      ],
    );
  }

  // 📋 قائمة الفئات (مع مسافة تحت عشان زر الإضافة)
  Widget _buildCategoryList(List<Map<String, dynamic>> cats) {
    if (cats.isEmpty) {
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
              'لا توجد فئات حالياً',
              style: GoogleFonts.ibmPlexSansArabic(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.dark,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _fetchCategories,
      child: ListView.builder(
        // 🔹 زودنا المسافة تحت عشان ما يتصادم مع الـ FAB
        padding: const EdgeInsets.only(bottom: 120),
        itemCount: cats.length,
        itemBuilder: (context, index) {
          final cat = cats[index];
          return _buildCategoryCard(cat);
        },
      ),
    );
  }

  // 🟥 كرت الفئة (مع الأزرار تحت) + الأيقونات الجديدة
  Widget _buildCategoryCard(Map<String, dynamic> cat) {
    final statusText = _getCategoryStatus(cat);
    final statusColor = _getStatusColor(statusText);

    final isHighlighted =
        widget.initialCategoryName != null &&
        widget.initialCategoryName == (cat['name']?.toString() ?? '');

    final parentText = (cat['parent'] ?? '').toString().trim();
    final hasParent = parentText.isNotEmpty;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isHighlighted ? AppColors.primary : Colors.grey.shade200,
          width: isHighlighted ? 1.6 : 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 5,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.only(
              right: 16,
              left: 16,
              top: 14,
              bottom: 10,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 🔹 اسم الفئة مع أيقونة Category
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.category_outlined,
                      size: 20,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        cat['name']?.toString() ?? '',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppColors.dark,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),

                // 🔹 الفئة الرئيسية مع أيقونة Hub (لو موجودة)
                if (hasParent)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.hub_outlined,
                        size: 18,
                        color: Color(0xFF666666),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          'الفئة الرئيسية: $parentText',
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFF666666),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                if (hasParent) const SizedBox(height: 6),

                // الوصف
                Text(
                  cat['description']?.toString() ?? '',
                  style: const TextStyle(fontSize: 14, color: AppColors.dark),
                ),

                const SizedBox(height: 10),

                // ✅ الأزرار أسفل الكارد
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, color: Colors.grey),
                      onPressed: () async {
                        final updated = await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => AddCategoryPage(category: cat),
                          ),
                        );
                        if (updated == true) {
                          _fetchCategories();
                        }
                      },
                    ),
                    IconButton(
                      icon: Icon(
                        cat['status'] == 'hidden'
                            ? Icons.visibility_rounded
                            : Icons.visibility_off_rounded,
                        color: cat['status'] == 'hidden'
                            ? AppColors.primary
                            : Colors.redAccent,
                      ),
                      onPressed: () {
                        if (cat['status'] == 'hidden') {
                          _unhideCategoryDialog(cat);
                        } else {
                          _hideCategoryDialog(cat);
                        }
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),

          // شارة الحالة
          Positioned(
            top: 8,
            left: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.08),
                border: Border.all(color: statusColor),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                statusText,
                style: GoogleFonts.ibmPlexSansArabic(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: statusColor,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 🔹 إخفاء فئة (جدولة الإخفاء للشهر القادم مثل منطق المهام)
  void _hideCategoryDialog(Map<String, dynamic> cat) {
    final now = DateTime.now();
    final nextMonthDate = DateTime(now.year, now.month + 1, 1);
    final nextMonthKey =
        "${nextMonthDate.year}-${nextMonthDate.month.toString().padLeft(2, '0')}";

    showDialog(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text(
            'إخفاء الفئة',
            style: GoogleFonts.ibmPlexSansArabic(
              fontWeight: FontWeight.w800,
              color: AppColors.dark,
            ),
          ),
          content: Text(
            'هل أنت متأكد من إخفاء هذه الفئة؟\n'
            'لن يتم إخفاؤها فورًا من المستخدمين، بل سيتم تطبيق الإخفاء مع بداية الشهر القادم ($nextMonthKey).',
            style: GoogleFonts.ibmPlexSansArabic(
              color: Colors.black87,
              fontSize: 14,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'إلغاء',
                style: GoogleFonts.ibmPlexSansArabic(
                  color: Colors.redAccent,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
              ),
              onPressed: () async {
                Navigator.pop(context);
                try {
                  await _categoriesCol.doc(cat['id']).update({
                    'status': 'hidden',
                    'expiry_month': nextMonthKey,
                    'updatedAt': FieldValue.serverTimestamp(),
                  });

                  if (!mounted) return;

                  // حوار توضيح بعد الجدولة
                  showDialog(
                    context: context,
                    builder: (context) => Directionality(
                      textDirection: TextDirection.rtl,
                      child: AlertDialog(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        title: Row(
                          children: const [
                            Icon(
                              Icons.schedule_rounded,
                              color: AppColors.primary,
                              size: 28,
                            ),
                            SizedBox(width: 8),
                            Text('تم جدولة إخفاء الفئة'),
                          ],
                        ),
                        content: Text(
                          'سيتم تطبيق إخفاء هذه الفئة تلقائيًا في بداية الشهر القادم ($nextMonthKey).\n'
                          'لن تظهر في القوائم الشهرية الجديدة بعد ذلك.',
                          style: GoogleFonts.ibmPlexSansArabic(
                            color: AppColors.dark,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () {
                              Navigator.pop(context);
                              _fetchCategories();
                            },
                            child: Text(
                              'تم',
                              style: GoogleFonts.ibmPlexSansArabic(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      backgroundColor: Colors.redAccent,
                      content: Text(
                        'حدث خطأ أثناء جدولة إخفاء الفئة',
                        style: GoogleFonts.ibmPlexSansArabic(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  );
                }
              },
              child: Text(
                'تأكيد',
                style: GoogleFonts.ibmPlexSansArabic(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 🔹 إعادة إظهار فئة
  void _unhideCategoryDialog(Map<String, dynamic> cat) {
    showDialog(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text(
            'إعادة إظهار الفئة',
            style: GoogleFonts.ibmPlexSansArabic(
              fontWeight: FontWeight.w800,
              color: AppColors.dark,
            ),
          ),
          content: Text(
            'هل ترغب بإعادة إظهار هذه الفئة وجعلها نشطة من جديد؟',
            style: GoogleFonts.ibmPlexSansArabic(fontSize: 14),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'إلغاء',
                style: GoogleFonts.ibmPlexSansArabic(
                  color: Colors.redAccent,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
              ),
              onPressed: () async {
                Navigator.pop(context);
                await _categoriesCol.doc(cat['id']).update({
                  'status': 'active',
                  'updatedAt': FieldValue.serverTimestamp(),
                });
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      backgroundColor: AppColors.primary,
                      content: Text(
                        'تم إعادة تفعيل الفئة ✅',
                        style: GoogleFonts.ibmPlexSansArabic(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  );
                }
                _fetchCategories();
              },
              child: Text(
                'تأكيد',
                style: GoogleFonts.ibmPlexSansArabic(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 🔹 BottomSheet لتصفية الحالات
  void _showFilterSheet() {
    final statuses = ['نشطة', 'غير نشطة'];
    final selectedLocal = Set<String>.from(_selectedStatusSet);

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
                    'تصفية الفئات حسب الحالة',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: statuses.map((s) {
                      final selected = selectedLocal.contains(s);
                      return FilterChip(
                        label: Text(s),
                        selected: selected,
                        selectedColor: AppColors.primary.withOpacity(.15),
                        labelStyle: TextStyle(
                          color: selected ? AppColors.primary : AppColors.dark,
                          fontWeight: FontWeight.w700,
                        ),
                        onSelected: (v) {
                          setSt(
                            () => v
                                ? selectedLocal.add(s)
                                : selectedLocal.remove(s),
                          );
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                    ),
                    onPressed: () {
                      Navigator.pop(context);
                      setState(() {
                        _selectedStatusSet = selectedLocal;
                      });
                    },
                    child: const Text('تطبيق'),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                      setState(() {
                        _selectedStatusSet.clear();
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
}
