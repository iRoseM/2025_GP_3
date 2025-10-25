import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:ui';

import 'services/admin_bottom_nav.dart';
import 'admin_home.dart';
import 'admin_reward.dart';
import 'admin_map.dart';
import 'services/background_container.dart';
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

class AdminTasksPage extends StatefulWidget {
  const AdminTasksPage({super.key});

  @override
  State<AdminTasksPage> createState() => _AdminTasksPageState();
}

class _AdminTasksPageState extends State<AdminTasksPage> {
  // 🔹 Firestore reference
  final CollectionReference _taskCollection = FirebaseFirestore.instance
      .collection('tasks');

  List<Map<String, dynamic>> _tasks = [];
  List<String> _categories = [];
  Set<String> _selectedCategories = {};
  final Set<int> _expandedIndexes = {};

  bool _isLoading = true;
  bool _isCatsLoading = true;
  String searchQuery = '';

  int _currentIndex = 2;

  // ---------------------------------------------------------------------------
  // 🔹 Lifecycle
  @override
  void initState() {
    super.initState();
    _fetchTasks();
    _fetchCategories();
  }

  // ---------------------------------------------------------------------------
  // 🔹 Fetch Tasks
  Future<void> _fetchTasks() async {
    try {
      final qs = await _taskCollection.get();
      setState(() {
        _tasks =
            qs.docs.map((doc) {
              final data = doc.data() as Map<String, dynamic>;
              data['id'] = doc.id;
              return data;
            }).toList()..sort((a, b) {
              final aStatus = a['status'] ?? '';
              final bStatus = b['status'] ?? '';
              return aStatus.compareTo(bStatus);
            });
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading tasks: $e');
      setState(() => _isLoading = false);
    }
  }

  // ---------------------------------------------------------------------------
  // 🔹 Fetch Categories
  Future<void> _fetchCategories() async {
    try {
      final qs = await FirebaseFirestore.instance
          .collection('categories')
          .get();
      final names =
          qs.docs
              .map((d) => (d['name'] ?? '').toString().trim())
              .where((n) => n.isNotEmpty)
              .toList()
            ..sort((a, b) => a.compareTo(b));
      setState(() {
        _categories = names;
        _isCatsLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading categories: $e');
      setState(() => _isCatsLoading = false);
    }
  }

  // ---------------------------------------------------------------------------
  // 🔹 Navigation
  void _onBottomNavTap(int i) {
    if (i == _currentIndex) return;
    switch (i) {
      case 0:
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => AdminRewardsPage()),
        );
        break;
      case 1:
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const AdminMapPage()),
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

  // ---------------------------------------------------------------------------
  // 🔹 Determine Status Label Text
  String _getTaskStatus(Map<String, dynamic> task) {
    final status = task['status'] ?? 'active';
    switch (status) {
      case 'hidden':
        return 'مخفية';
      case 'expired':
        return 'منتهية';
      default:
        return 'نشطة';
    }
  }

  // ---------------------------------------------------------------------------
  // 🔹 Main UI Build (fixed to match original Nameer style)
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final isKeyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;
    final theme = Theme.of(context);
    final textTheme = GoogleFonts.ibmPlexSansArabicTextTheme(theme.textTheme);

    final query = searchQuery.trim().toLowerCase();

    // 🔹 Filter and sort tasks (active first)
    final filteredTasks =
        _tasks.where((task) {
          final title =
              task['title_normalized']?.toString() ??
              task['title']?.toString().toLowerCase() ??
              '';
          final desc = task['description']?.toString().toLowerCase() ?? '';
          final cat = task['category']?.toString() ?? '';
          final matchesSearch =
              query.isEmpty || title.contains(query) || desc.contains(query);
          final matchesCategory =
              _selectedCategories.isEmpty || _selectedCategories.contains(cat);
          return matchesSearch && matchesCategory;
        }).toList()..sort((a, b) {
          if (a['status'] == b['status']) return 0;
          return a['status'] == 'active' ? -1 : 1;
        });

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Theme(
        data: theme.copyWith(textTheme: textTheme),
        child: Scaffold(
          extendBody: true,
          extendBodyBehindAppBar: true,
          backgroundColor: Colors.transparent,

          // ✅ نفس الهيدر الأصلي (شفاف)
          appBar: const NameerAppBar(showTitleInBar: false, showBack: false),

          // ✅ خلفية متحركة خضراء شفافة
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
                            // 👇 العنوان نفس النسخة القديمة
                            Text(
                              'قائمة المهام',
                              style: GoogleFonts.ibmPlexSansArabic(
                                fontSize: 24,
                                fontWeight: FontWeight.w700,
                                color: AppColors.dark,
                              ),
                            ),
                            const SizedBox(height: 15),

                            _buildSearchBar(),
                            const SizedBox(height: 12),

                            Expanded(child: _buildTaskList(filteredTasks)),
                          ],
                        ),
                );
              },
            ),
          ),

          // ✅ زر الإضافة (نفس الموقع والحجم واللون)
          floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
          floatingActionButton: _buildAddFab(),

          bottomNavigationBar: isKeyboardOpen
              ? null
              : AdminBottomNav(
                  currentIndex: _currentIndex,
                  onTap: _onBottomNavTap,
                ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 🔹 Search Bar
  Widget _buildSearchBar() {
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
                hintText: 'ابحث عن مهمة...',
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

  // ---------------------------------------------------------------------------
  // 🔹 Task List Builder
  Widget _buildTaskList(List<Map<String, dynamic>> tasks) {
    if (tasks.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset('assets/img/nameerSleep.png', width: 200, height: 200),
            const SizedBox(height: 16),
            Text(
              'لا توجد مهام حالياً 📅',
              style: GoogleFonts.ibmPlexSansArabic(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.dark,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _fetchTasks,
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 200),
        itemCount: tasks.length,
        itemBuilder: (context, index) {
          final task = tasks[index];
          final isExpanded = _expandedIndexes.contains(index);
          return _buildTaskCard(task, index, isExpanded);
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 🔹 Task Card
  Widget _buildTaskCard(Map<String, dynamic> task, int index, bool isExpanded) {
    final statusText = _getTaskStatus(task);
    Color statusColor;
    switch (statusText) {
      case 'منتهية':
        statusColor = Colors.redAccent;
        break;
      case 'مخفية':
        statusColor = Colors.grey;
        break;
      default:
        statusColor = Colors.green;
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 5,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Stack(
        children: [
          Column(
            children: [
              ListTile(
                title: Text(
                  task['title'] ?? '',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.dark,
                  ),
                ),
                subtitle: Text(
                  task['category'] ?? '',
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF666666),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                trailing: IconButton(
                  icon: Icon(
                    isExpanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    color: AppColors.primary,
                  ),
                  onPressed: () {
                    setState(() {
                      isExpanded
                          ? _expandedIndexes.remove(index)
                          : _expandedIndexes.add(index);
                    });
                  },
                ),
              ),
              if (isExpanded) _buildExpandedTaskContent(task),
            ],
          ),
          Positioned(
            top: 8,
            left: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.1),
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

  Widget _buildExpandedTaskContent(Map<String, dynamic> task) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            task['description'] ?? '',
            style: const TextStyle(fontSize: 14, color: AppColors.dark),
          ),
          const SizedBox(height: 8),
          Text(
            'النقاط: ${task['points'] ?? 0}',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // ✏️ تعديل المهمة
              IconButton(
                icon: const Icon(Icons.edit, color: Colors.grey),
                onPressed: () async {
                  final updated = await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => AddTaskPage(task: task)),
                  );
                  if (updated == true) _fetchTasks();
                },
              ),

              // 👁️ إخفاء المهمة بدل الحذف
              IconButton(
                icon: const Icon(Icons.visibility_off, color: Colors.redAccent),
                onPressed: () => _hideTaskDialog(task),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 🔹 إخفاء المهمة (بدل الحذف)
  // void _hideTaskDialog(Map<String, dynamic> task) {
  //   showDialog(
  //     context: context,
  //     builder: (context) {
  //       return AlertDialog(
  //         title: Text('إخفاء المهمة',
  //             style: GoogleFonts.ibmPlexSansArabic(
  //                 fontWeight: FontWeight.w800, color: AppColors.dark)),
  //         content: Text(
  //           'سيتم إخفاء هذه المهمة من الشهر القادم.\nهل ترغب بالمتابعة؟',
  //           style: GoogleFonts.ibmPlexSansArabic(fontSize: 14),
  //         ),
  //         actions: [
  //           TextButton(
  //             onPressed: () => Navigator.pop(context),
  //             child: const Text('إلغاء',
  //                 style: TextStyle(color: Colors.redAccent)),
  //           ),
  //           ElevatedButton(
  //             style: ElevatedButton.styleFrom(
  //                 backgroundColor: AppColors.primary),
  //             onPressed: () async {
  //               await _taskCollection
  //                   .doc(task['id'])
  //                   .update({'status': 'hidden'});
  //               Navigator.pop(context);
  //               _fetchTasks();
  //               ScaffoldMessenger.of(context).showSnackBar(SnackBar(
  //                 content: Text('تم إخفاء المهمة ✅',
  //                     style: GoogleFonts.ibmPlexSansArabic(
  //                         fontWeight: FontWeight.w700)),
  //               ));
  //             },
  //             child: const Text('تأكيد'),
  //           ),
  //         ],
  //       );
  //     },
  //   );
  // }
  // ---------------------------------------------------------------------------
  // 🔹 منطق "إخفاء المهمة" المعدل وفق القاعدة الشهرية الجديدة
  // ---------------------------------------------------------------------------
  void _hideTaskDialog(Map<String, dynamic> task) async {
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
            'إخفاء المهمة',
            style: GoogleFonts.ibmPlexSansArabic(
              fontWeight: FontWeight.w800,
              color: AppColors.dark,
            ),
          ),
          content: Text(
            'هل أنت متأكد من إخفاء هذه المهمة؟ سيتم تطبيق الإخفاء في الشهر القادم (${nextMonthKey})',
            style: GoogleFonts.ibmPlexSansArabic(color: Colors.black87),
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
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () async {
                Navigator.pop(context);

                try {
                  final now = DateTime.now();
                  final nextMonthDate = DateTime(now.year, now.month + 1, 1);
                  final nextMonthKey =
                      "${nextMonthDate.year}-${nextMonthDate.month.toString().padLeft(2, '0')}";

                  await FirebaseFirestore.instance
                      .collection('tasks')
                      .doc(task['id'])
                      .update({
                        'status': 'hidden',
                        'expiry_month': nextMonthKey,
                      });

                  if (mounted) {
                    // ✅ Pop-up to inform admin
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
                              Text('تم جدولة الإخفاء'),
                            ],
                          ),
                          content: Text(
                            'سيتم تطبيق الإخفاء تلقائيًا في بداية الشهر القادم (${nextMonthKey}).',
                            style: GoogleFonts.ibmPlexSansArabic(
                              color: AppColors.dark,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () {
                                Navigator.pop(context);
                                _fetchTasks();
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
                  }
                } catch (e) {
                  debugPrint('Error hiding task: $e');
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

  // ---------------------------------------------------------------------------
  // 🔹 FAB
  // ---------------------------------------------------------------------------
  // 🔹 زر الإضافة (نفس التصميم القديم + Bottom Sheet بخيارين)
  // ---------------------------------------------------------------------------
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

  // ---------------------------------------------------------------------------
  // 🔹 Bottom Sheet عند الضغط على زر الإضافة
  // ---------------------------------------------------------------------------
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

              // ✅ زر إضافة مهمة جديدة
              _gradientActionButton(
                icon: Icons.check_circle_outline,
                label: 'إضافة مهمة جديدة',
                colors: const [AppColors.primary, AppColors.mint],
                onTap: () async {
                  Navigator.pop(context);
                  final updated = await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const AddTaskPage()),
                  );
                  if (updated == true) _fetchTasks();
                },
              ),

              const SizedBox(height: 12),

              // ✅ زر إضافة فئة جديدة
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

  // ---------------------------------------------------------------------------
  // 🔹 زر Gradient مع أيقونة (نفس شكل الأزرار القديمة)
  // ---------------------------------------------------------------------------
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

  // ---------------------------------------------------------------------------
  // 🔹 فلترة حسب الفئة فقط (تبقى بسيطة)
  void _showFilterSheet() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) {
        final selectedLocal = Set<String>.from(_selectedCategories);
        return StatefulBuilder(
          builder: (context, setSt) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'تصفية المهام حسب الفئة',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: _categories.map((cat) {
                      final selected = selectedLocal.contains(cat);
                      return FilterChip(
                        label: Text(cat),
                        selected: selected,
                        onSelected: (v) => setSt(
                          () => v
                              ? selectedLocal.add(cat)
                              : selectedLocal.remove(cat),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                    ),
                    onPressed: () {
                      Navigator.pop(context);
                      setState(() => _selectedCategories = selectedLocal);
                    },
                    child: const Text('تطبيق'),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                      setState(() => _selectedCategories.clear());
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

class AddTaskPage extends StatefulWidget {
  final Map<String, dynamic>? task; // null => add, not null => edit
  const AddTaskPage({super.key, this.task});

  @override
  State<AddTaskPage> createState() => _AddTaskPageState();
}

class _AddTaskPageState extends State<AddTaskPage> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _pointsCtrl = TextEditingController();

  String? _selectedCategory;
  String? _validationType;
  bool _isEditing = false;

  // 🔹 الشهر القادم والشهر الحالي
  final now = DateTime.now();
  late final String nextMonth;
  late final String currentMonth;

  // 🔹 شهر الانتهاء (expiry_month)
  String? _expiryMonth;
  List<String> _monthsList = [];

  final _tasks = FirebaseFirestore.instance.collection('tasks');
  final _categoriesCol = FirebaseFirestore.instance.collection('categories');
  List<String> _categories = [];
  bool _catsLoading = true;

  @override
  void initState() {
    super.initState();

    currentMonth = "${now.year}-${now.month.toString().padLeft(2, '0')}";
    final n = DateTime(now.year, now.month + 1);
    nextMonth = "${n.year}-${n.month.toString().padLeft(2, '0')}";

    _generateMonths();
    _loadCategories();
    _prefillIfEditing();
  }

  void _generateMonths() {
    // 🗓 توليد قائمة الأشهر القادمة (مثلاً حتى نهاية 2026)
    final months = <String>[];
    final start = DateTime.now();
    for (int i = 0; i < 24; i++) {
      final m = DateTime(start.year, start.month + i);
      months.add("${m.year}-${m.month.toString().padLeft(2, '0')}");
    }
    _monthsList = months;
  }

  Future<void> _loadCategories() async {
    final qs = await _categoriesCol.get();
    setState(() {
      _categories =
          qs.docs
              .map((d) => (d['name'] ?? '').toString().trim())
              .where((n) => n.isNotEmpty)
              .toList()
            ..sort((a, b) => a.compareTo(b));
      _catsLoading = false;
    });
  }

  void _prefillIfEditing() {
    final t = widget.task;
    if (t == null) return;
    _isEditing = true;
    _titleCtrl.text = t['title'] ?? '';
    _descCtrl.text = t['description'] ?? '';
    _pointsCtrl.text = t['points']?.toString() ?? '';
    _selectedCategory = t['category'];
    _validationType = t['validationStrategy'];
    _expiryMonth = t['expiry_month'];
  }

  // ---------------------------------------------------------------------------
  // 🟩 واجهة الصفحة
  @override
  Widget build(BuildContext context) {
    final isEdit = _isEditing;
    final titleText = isEdit ? 'تعديل المهمة' : 'إضافة مهمة جديدة';

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        extendBodyBehindAppBar: true,
        backgroundColor: AppColors.background,

        // ✅ هيدر نمير الموحد (زر رجوع من داخله)
        appBar: const NameerAppBar(
          showTitleInBar: false,
          showBack: true,
          height: 80,
        ),

        body: Builder(
          builder: (context) {
            final statusBar = MediaQuery.of(context).padding.top;
            const headerH = 20.0; // ارتفاع التولبار الفعلي للهيدر
            const gap = 12.0; // مسافة بسيطة بعد الهيدر
            final topPadding = statusBar + headerH + gap;

            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(16, topPadding, 16, 16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ✅ العنوان تحت الهيدر مباشرة
                    Text(
                      titleText,
                      style: GoogleFonts.ibmPlexSansArabic(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: AppColors.dark,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // 🟢 باقي الحقول كما هي
                    _fieldLabel('عنوان المهمة', required: true),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _titleCtrl,
                      decoration: const InputDecoration(
                        hintText: 'مثال: إعادة تدوير الورق',
                        prefixIcon: Icon(Icons.task_alt_outlined),
                      ),
                      validator: (v) =>
                          (v == null || v.isEmpty) ? 'أدخل عنوان المهمة' : null,
                    ),
                    const SizedBox(height: 14),

                    _fieldLabel('وصف المهمة', required: true),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _descCtrl,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        hintText: 'مثال: التوعية بأهمية إعادة التدوير',
                        prefixIcon: Icon(Icons.description_outlined),
                      ),
                      validator: (v) =>
                          (v == null || v.isEmpty) ? 'أدخل وصف المهمة' : null,
                    ),
                    const SizedBox(height: 14),

                    _fieldLabel('عدد النقاط', required: true),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _pointsCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        hintText: 'مثال: 30',
                        prefixIcon: Icon(Icons.stars_rounded),
                      ),
                      validator: (v) {
                        final n = int.tryParse(v ?? '');
                        if (n == null || n <= 0)
                          return 'أدخل عددًا صحيحًا موجبًا';
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),

                    _fieldLabel('تصنيف المهمة', required: true),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      value: _selectedCategory,
                      alignment: Alignment.centerRight,
                      isExpanded: true,
                      decoration: InputDecoration(
                        hintText: _catsLoading
                            ? '...يتم تحميل الفئات'
                            : 'اختر الفئة',
                        prefixIcon: const Icon(
                          Icons.category_outlined,
                          color: AppColors.primary,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      items: _categories
                          .map(
                            (name) => DropdownMenuItem(
                              value: name,
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: Text(name),
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setState(() => _selectedCategory = v),
                      validator: (v) =>
                          (v == null || v.isEmpty) ? 'اختر تصنيف المهمة' : null,
                    ),
                    const SizedBox(height: 20),

                    _fieldLabel('طريقة التحقق', required: true),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      value: _validationType,
                      alignment: Alignment.centerRight,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        hintText: 'اختر طريقة التحقق',
                        prefixIcon: Icon(Icons.verified_outlined),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(12)),
                        ),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'manual',
                          child: Text('تحقق يدوي'),
                        ),
                        DropdownMenuItem(value: 'photo', child: Text('صورة')),
                        DropdownMenuItem(value: 'qr', child: Text('رمز QR')),
                        DropdownMenuItem(
                          value: 'التحقق عبر معالجة الصور',
                          child: Text('التحقق عبر معالجة الصور'),
                        ),
                        DropdownMenuItem(
                          value: 'التحقق عبر تتبع القراءة',
                          child: Text('التحقق عبر تتبع القراءة'),
                        ),
                      ],
                      onChanged: (v) => setState(() => _validationType = v),
                      validator: (v) =>
                          (v == null || v.isEmpty) ? 'اختر طريقة التحقق' : null,
                    ),
                    const SizedBox(height: 20),

                    _fieldLabel('تاريخ انتهاء المهمة (شهر)', required: false),
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: () async {
                        final picked = await _showExpiryMonthPicker(
                          context: context,
                          initialYear: now.year,
                          initialMonth: now.month,
                          selected: _expiryMonth,
                        );
                        if (picked != null) {
                          setState(() => _expiryMonth = picked);
                          final currentKey = currentMonth;
                          if (_expiryMonth!.compareTo(currentKey) <= 0) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                backgroundColor: Colors.redAccent,
                                content: Text(
                                  '⚠️ الشهر المختار منتهي أو داخل الشهر الحالي — سيتم التعامل معه كإخفاء بدءًا من الشهر القادم',
                                  style: GoogleFonts.ibmPlexSansArabic(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            );
                          }
                        }
                      },
                      child: Container(
                        height: 52,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: AppColors.light.withOpacity(.7),
                          ),
                          borderRadius: BorderRadius.circular(12),
                          color: Colors.white,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _expiryMonth == null
                                  ? 'اختر شهر الانتهاء (اختياري)'
                                  : _expiryMonth!,
                              style: GoogleFonts.ibmPlexSansArabic(
                                color: AppColors.dark,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const Icon(
                              Icons.calendar_month,
                              color: AppColors.primary,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 30),

                    _buildGradientSaveButton(
                      text: isEdit ? 'تحديث المهمة' : 'حفظ المهمة',
                      onPressed: _saveTask,
                    ),
                    const SizedBox(height: 10),
                    _buildRedCancelButton(
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 🧩 منطق الحفظ
  Future<void> _saveTask() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final normalizedTitle = _titleCtrl.text
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ')
        .toLowerCase();

    final existing = await _tasks
        .where('title_normalized', isEqualTo: normalizedTitle)
        .limit(1)
        .get();

    if (existing.docs.isNotEmpty &&
        (widget.task == null || existing.docs.first.id != widget.task!['id'])) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text(
            'اسم المهمة "${_titleCtrl.text.trim()}" مستخدم بالفعل، يرجى اختيار اسم آخر',
            style: GoogleFonts.ibmPlexSansArabic(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
      return;
    }

    // 🔸 تحديد الحالة حسب شهر الانتهاء
    String status = 'active';
    if (_expiryMonth != null && _expiryMonth!.compareTo(currentMonth) <= 0) {
      status = 'hidden';
    }

    final data = {
      'title': _titleCtrl.text.trim(),
      'title_normalized': normalizedTitle,
      'description': _descCtrl.text.trim(),
      'points': int.parse(_pointsCtrl.text),
      'category': _selectedCategory,
      'validationStrategy': _validationType,
      'status': status,
      'visible_from': nextMonth, // يبدأ الشهر القادم
      'expiry_month': _expiryMonth,
      'managedBy': 'nameer admin',
      'createdAt': FieldValue.serverTimestamp(),
    };

    try {
      if (widget.task == null) {
        await _tasks.add(data);
      } else {
        await _tasks.doc(widget.task!['id']).update(data);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.green,
            content: Text(
              'تم حفظ المهمة ✅ (ستظهر الشهر القادم)',
              style: GoogleFonts.ibmPlexSansArabic(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      debugPrint('Error saving task: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // 🗓 Bottom Sheet لاختيار (السنة + الشهر) بشكل جميل
  // يرجّع String مثل "2026-06" أو null لو أُغلِق بدون اختيار.
  // يمنع اختيار الأشهر الماضية.
  // ---------------------------------------------------------------------------
  Future<String?> _showExpiryMonthPicker({
    required BuildContext context,
    required int initialYear,
    required int initialMonth,
    String? selected,
  }) async {
    int year = initialYear;
    String? result;

    bool isPast(int y, int m) {
      final nowY = now.year, nowM = now.month;
      if (y < nowY) return true;
      if (y == nowY && m < nowM) return true;
      return false;
    }

    final months = const [
      'يناير',
      'فبراير',
      'مارس',
      'أبريل',
      'مايو',
      'يونيو',
      'يوليو',
      'أغسطس',
      'سبتمبر',
      'أكتوبر',
      'نوفمبر',
      'ديسمبر',
    ];

    await showModalBottomSheet(
      context: context,
      isScrollControlled: false,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setSt) {
            return Directionality(
              textDirection: TextDirection.rtl,
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
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
                    // رأس: سنة + أسهم
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // 🔁 عكسنا الاتجاه
                        IconButton(
                          tooltip: 'السنة السابقة',
                          onPressed: () => setSt(() => year--),
                          icon: const Icon(
                            Icons.chevron_left,
                            size: 28,
                            color: AppColors.dark,
                          ),
                        ),
                        Text(
                          '$year',
                          style: GoogleFonts.ibmPlexSansArabic(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: AppColors.dark,
                          ),
                        ),
                        IconButton(
                          tooltip: 'السنة التالية',
                          onPressed: () => setSt(() => year++),
                          icon: const Icon(
                            Icons.chevron_right,
                            size: 28,
                            color: AppColors.dark,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // شبكة الأشهر (3 أعمدة)
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: List.generate(12, (i) {
                        final m = i + 1;
                        final key = "$year-${m.toString().padLeft(2, '0')}";
                        final disabled = isPast(year, m);
                        final isSelected = selected == key;

                        return SizedBox(
                          width:
                              (MediaQuery.of(context).size.width -
                                  20 * 2 -
                                  20) /
                              3,
                          height: 44,
                          child: ElevatedButton(
                            onPressed: disabled
                                ? null
                                : () {
                                    result = key;
                                    Navigator.pop(context);
                                  },
                            style:
                                ElevatedButton.styleFrom(
                                  padding: EdgeInsets.zero,
                                  elevation: 0,
                                  backgroundColor: Colors.transparent,
                                  shadowColor: Colors.transparent,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ).merge(
                                  ButtonStyle(
                                    // خلفية متدرجة مثل أزراركم إذا مختار، أو إطار خفيف إن لم يُختَر
                                    backgroundColor:
                                        WidgetStateProperty.resolveWith((
                                          states,
                                        ) {
                                          if (disabled)
                                            return Colors.grey.shade200;
                                          return Colors.transparent;
                                        }),
                                  ),
                                ),
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                gradient: disabled
                                    ? null
                                    : isSelected
                                    ? const LinearGradient(
                                        colors: [
                                          AppColors.primary,
                                          AppColors.mint,
                                        ],
                                      )
                                    : null,
                                border: isSelected || disabled
                                    ? null
                                    : Border.all(
                                        color: AppColors.light.withOpacity(.7),
                                      ),
                                color: (disabled || isSelected)
                                    ? null
                                    : Colors.white,
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                months[i],
                                style: GoogleFonts.ibmPlexSansArabic(
                                  fontWeight: FontWeight.w700,
                                  color: disabled
                                      ? Colors.grey
                                      : isSelected
                                      ? Colors.white
                                      : AppColors.dark,
                                ),
                              ),
                            ),
                          ),
                        );
                      }),
                    ),

                    const SizedBox(height: 16),

                    // // أزرار أسفل (مسح/إغلاق)
                    // Row(
                    //   children: [
                    //     Expanded(
                    //       child: OutlinedButton(
                    //         style: OutlinedButton.styleFrom(
                    //           side: const BorderSide(color: Colors.redAccent, width: 1.2),
                    //           shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    //           padding: const EdgeInsets.symmetric(vertical: 12),
                    //         ),
                    //         onPressed: () { result = null; Navigator.pop(context); },
                    //         child: Text('إلغاء',
                    //           style: GoogleFonts.ibmPlexSansArabic(
                    //             color: Colors.redAccent, fontWeight: FontWeight.w700)),
                    //       ),
                    //     ),
                    //     const SizedBox(width: 10),
                    //     Expanded(
                    //       child: Container(
                    //         decoration: const BoxDecoration(
                    //           gradient: LinearGradient(colors: [AppColors.primary, AppColors.mint]),
                    //           borderRadius: BorderRadius.all(Radius.circular(12)),
                    //         ),
                    //         child: ElevatedButton(
                    //           onPressed: () { selected = null; result = null; Navigator.pop(context); },
                    //           style: ElevatedButton.styleFrom(
                    //             backgroundColor: Colors.transparent,
                    //             shadowColor: Colors.transparent,
                    //             padding: const EdgeInsets.symmetric(vertical: 12),
                    //             shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    //           ),
                    //           child: Text('مسح الاختيار',
                    //             style: GoogleFonts.ibmPlexSansArabic(
                    //               color: Colors.white, fontWeight: FontWeight.w800)),
                    //         ),
                    //       ),
                    //     ),
                    //   ],
                    // ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    return result;
  }

  // ---------------------------------------------------------------------------
  // 🔹 Widgets مساعدة
  Widget _fieldLabel(String text, {bool required = false}) => Align(
    alignment: Alignment.centerRight,
    child: RichText(
      text: TextSpan(
        text: text,
        style: GoogleFonts.ibmPlexSansArabic(
          fontWeight: FontWeight.w700,
          color: AppColors.dark.withOpacity(.9),
          fontSize: 14,
        ),
        children: required
            ? const [
                TextSpan(
                  text: ' *',
                  style: TextStyle(
                    color: Colors.redAccent,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ]
            : [],
      ),
    ),
  );

  Widget _buildGradientSaveButton({
    required String text,
    required VoidCallback onPressed,
  }) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primary, AppColors.mint],
          begin: Alignment.bottomLeft,
          end: Alignment.topRight,
        ),
        borderRadius: BorderRadius.all(Radius.circular(14)),
      ),
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: Text(
          text,
          style: GoogleFonts.ibmPlexSansArabic(
            color: Colors.white,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }

  Widget _buildRedCancelButton({required VoidCallback onPressed}) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        side: const BorderSide(color: Colors.redAccent, width: 1.4),
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      child: Text(
        'إلغاء',
        style: GoogleFonts.ibmPlexSansArabic(
          color: Colors.redAccent,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 🟨 Add / Edit Category Page
//  ملاحظة: لم يتم تعديل المنطق هنا لأنها لا تتأثر بتغييرات الجدولة أو الحالة.
//  تظل كما هي فقط لإضافة وتعديل الفئات (categories).
// ---------------------------------------------------------------------------

class AddCategoryPage extends StatefulWidget {
  final Map<String, dynamic>? category; // null => add, not null => edit
  const AddCategoryPage({super.key, this.category});

  @override
  State<AddCategoryPage> createState() => _AddCategoryPageState();
}

class _AddCategoryPageState extends State<AddCategoryPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  String? _parent;

  bool _isDirty = false;

  final CollectionReference _categoriesCol = FirebaseFirestore.instance
      .collection('categories');

  @override
  void initState() {
    super.initState();
    _wireDirty();
    _prefillIfEditing();
  }

  void _wireDirty() {
    for (final c in [_nameCtrl, _descCtrl]) {
      c.addListener(() => _isDirty = true);
    }
  }

  void _prefillIfEditing() {
    final c = widget.category;
    if (c == null) return;
    _nameCtrl.text = c['name'] ?? '';
    _descCtrl.text = c['description'] ?? '';
    _parent = c['parent'];
    _isDirty = false;
  }

  Future<bool> _confirmLeaveIfDirty() async {
    if (!_isDirty) return true;
    bool shouldLeave = false;

    await showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black26,
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (context, anim1, anim2) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
          child: Center(
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: MediaQuery.of(context).size.width * 0.85,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 25,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x33000000),
                      blurRadius: 10,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Directionality(
                  textDirection: TextDirection.rtl,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.warning_amber_rounded,
                        color: Colors.redAccent,
                        size: 48,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'تأكيد الخروج',
                        style: GoogleFonts.ibmPlexSansArabic(
                          fontWeight: FontWeight.w800,
                          fontSize: 20,
                          color: AppColors.dark,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'هل أنت متأكد من العودة دون حفظ التغييرات؟',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.ibmPlexSansArabic(
                          fontSize: 15,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        icon: const Icon(
                          Icons.exit_to_app,
                          color: Colors.white,
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          minimumSize: const Size(double.infinity, 48),
                        ),
                        onPressed: () {
                          shouldLeave = true;
                          Navigator.pop(context);
                        },
                        label: Text(
                          'تأكيد الخروج',
                          style: GoogleFonts.ibmPlexSansArabic(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.redAccent),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          minimumSize: const Size(double.infinity, 48),
                        ),
                        onPressed: () => Navigator.pop(context),
                        child: Text(
                          'إلغاء',
                          style: GoogleFonts.ibmPlexSansArabic(
                            color: Colors.redAccent,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, anim1, anim2, child) {
        return FadeTransition(
          opacity: anim1,
          child: ScaleTransition(
            scale: CurvedAnimation(parent: anim1, curve: Curves.easeOutBack),
            child: child,
          ),
        );
      },
    );

    return shouldLeave;
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.category != null;
    final titleText = isEdit ? 'تعديل الفئة' : 'إضافة فئة جديدة';

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        // لو المحاولة تمت بالفعل، لا تسوي شيء
        if (didPop) return;

        // تأكيد قبل الخروج
        if (await _confirmLeaveIfDirty()) {
          if (mounted) Navigator.pop(context, false);
        }
      },
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          extendBodyBehindAppBar: true,
          backgroundColor: AppColors.background,

          // ✅ هيدر نمير الموحد (زر رجوع من داخله)
          appBar: const NameerAppBar(
            showTitleInBar: false,
            showBack: true,
            height: 80,
          ),

          body: Builder(
            builder: (context) {
              final statusBar = MediaQuery.of(context).padding.top;
              const headerH = 20.0; // نفس ارتفاع التولبار الفعلي للهيدر
              const gap = 12.0; // مسافة بسيطة بعد الهيدر
              final topPadding = statusBar + headerH + gap;

              return SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(16, topPadding, 16, 16),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // ✅ العنوان تحت الهيدر
                      Text(
                        titleText,
                        style: GoogleFonts.ibmPlexSansArabic(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: AppColors.dark,
                        ),
                      ),
                      const SizedBox(height: 16),

                      _fieldLabel('اسم الفئة', required: true),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _nameCtrl,
                        decoration: const InputDecoration(
                          hintText: 'مثال: النقل المستدام',
                          prefixIcon: Icon(Icons.category_outlined),
                        ),
                        onChanged: (_) => _isDirty = true,
                        validator: (v) =>
                            (v == null || v.isEmpty) ? 'أدخل اسم الفئة' : null,
                      ),
                      const SizedBox(height: 14),

                      _fieldLabel('الفئة الرئيسية', required: true),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        value: _parent,
                        alignment: Alignment.centerRight,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          hintText: 'اختر الفئة الرئيسية',
                          prefixIcon: Icon(Icons.hub_outlined),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.all(Radius.circular(12)),
                          ),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'سلوك مباشر',
                            child: Text('سلوك مباشر'),
                          ),
                          DropdownMenuItem(
                            value: 'سلوك غير مباشر',
                            child: Text('سلوك غير مباشر'),
                          ),
                        ],
                        onChanged: (v) {
                          setState(() => _parent = v);
                          _isDirty = true;
                        },
                        validator: (v) => (v == null || v.isEmpty)
                            ? 'اختر الفئة الرئيسية'
                            : null,
                      ),
                      const SizedBox(height: 14),

                      _fieldLabel('وصف الفئة', required: true),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _descCtrl,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          hintText: 'اكتب وصفًا موجزًا للفئة...',
                          prefixIcon: Icon(Icons.description_outlined),
                        ),
                        onChanged: (_) => _isDirty = true,
                        validator: (v) =>
                            (v == null || v.isEmpty) ? 'أدخل وصف الفئة' : null,
                      ),
                      const SizedBox(height: 24),

                      _buildGradientSaveButton(
                        text: isEdit ? 'تحديث الفئة' : 'حفظ الفئة',
                        onPressed: _saveCategory,
                      ),
                      const SizedBox(height: 10),

                      _buildRedCancelButton(
                        onPressed: () async {
                          if (await _confirmLeaveIfDirty()) {
                            if (mounted) Navigator.pop(context);
                          }
                        },
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _saveCategory() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      setState(() {});
      return;
    }

    try {
      final normalized = _nameCtrl.text
          .trim()
          .replaceAll(RegExp(r'\s+'), ' ')
          .toLowerCase();

      if (widget.category == null) {
        // 🔹 Duplicate check
        final dup = await _categoriesCol
            .where('name_normalized', isEqualTo: normalized)
            .limit(1)
            .get();

        if (dup.docs.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: Colors.redAccent,
              content: Text(
                '⚠️ اسم الفئة "${_nameCtrl.text.trim()}" مستخدم بالفعل، يرجى اختيار اسم آخر',
                style: GoogleFonts.ibmPlexSansArabic(
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          );
          return;
        }

        await _categoriesCol.add({
          'name': _nameCtrl.text.trim(),
          'name_normalized': normalized,
          'parent': _parent,
          'description': _descCtrl.text.trim(),
          'createdAt': FieldValue.serverTimestamp(),
        });
      } else {
        await _categoriesCol.doc(widget.category!['id']).update({
          'name': _nameCtrl.text.trim(),
          'name_normalized': normalized,
          'parent': _parent,
          'description': _descCtrl.text.trim(),
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.green,
            content: Text(
              widget.category == null
                  ? 'تمت إضافة الفئة بنجاح ✅'
                  : 'تم تحديث الفئة بنجاح ✅',
              style: GoogleFonts.ibmPlexSansArabic(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );
        _isDirty = false;
        Navigator.pop(context, true);
      }
    } catch (e) {
      debugPrint('Error saving category: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // 🔹 Local UI Helpers
  Widget _fieldLabel(String text, {bool required = false}) => Align(
    alignment: Alignment.centerRight,
    child: RichText(
      text: TextSpan(
        text: text,
        style: GoogleFonts.ibmPlexSansArabic(
          fontWeight: FontWeight.w700,
          color: AppColors.dark.withOpacity(.9),
          fontSize: 14,
        ),
        children: required
            ? const [
                TextSpan(
                  text: ' *',
                  style: TextStyle(
                    color: Colors.redAccent,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ]
            : [],
      ),
    ),
  );

  Widget _buildGradientSaveButton({
    required String text,
    required VoidCallback onPressed,
  }) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primary, AppColors.mint],
          begin: Alignment.bottomLeft,
          end: Alignment.topRight,
        ),
        borderRadius: BorderRadius.all(Radius.circular(14)),
      ),
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: Text(
          text,
          style: GoogleFonts.ibmPlexSansArabic(
            color: Colors.white,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }

  Widget _buildRedCancelButton({required VoidCallback onPressed}) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        side: const BorderSide(color: Colors.redAccent, width: 1.4),
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      child: Text(
        'إلغاء',
        style: GoogleFonts.ibmPlexSansArabic(
          color: Colors.redAccent,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
