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
import 'admin_category.dart';
import '../services/app_colors.dart';

class AdminTasksPage extends StatefulWidget {
  final Map<String, dynamic>? preFillData; // 👈 أضف هذا

  const AdminTasksPage({
    super.key,
    this.preFillData,
  }); // 👈 أضف this.preFillData

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
  Set<String> _selectedStatusSet = {};

  bool _isLoading = true;
  bool _isCatsLoading = true;
  String searchQuery = '';

  int _currentIndex = 2;

  // ---------------------------------------------------------------------------
  // 🔹 Lifecycle
  @override
  void initState() {
    super.initState();

    // إذا في بيانات جاهزة، عبّي الحقول قبل fetch tasks
    if (widget.preFillData != null) {
      final data = widget.preFillData!;

      // إذا كانت التوصية تحتوي على validationStrategy
      if (data['validationStrategy'] != null) {
        // هنا اختيار validationStrategy من القائمة المنسدلة
        // هذا يحتاج تعديل حسب طريقة تخزينها في صفحة المهام
      }

      // إذا كانت المهمة من نوع modify، ممكن نعرض رسالة
      if (data['type'] == 'modify') {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('تعديل مهمة موجودة بناءً على توصية'),
              backgroundColor: Colors.orange,
            ),
          );
        });
      } else if (data['type'] == 'add') {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('إضافة مهمة جديدة بناءً على توصية'),
              backgroundColor: Colors.green,
            ),
          );
        });
      }
    }

    // جلب المهام والتصنيفات كالمعتاد
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
              .map((doc) {
                final data = doc.data() as Map<String, dynamic>;
                return data['name']?.toString() ?? '';
              })
              .where((name) => name.isNotEmpty)
              .toList()
            ..sort((a, b) => a.compareTo(b));

      setState(() {
        _categories = names;
        _isCatsLoading = false;
      });
    } catch (e) {
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
        return 'غير نشطة';
      case 'expired':
        return 'منتهية';
      case 'active':
        return 'نشطة';
      default:
        return 'غير معروفة';
    }
  }

  // ---------------------------------------------------------------------------
  // 🔹 Main UI Build
  @override
  Widget build(BuildContext context) {
    final isKeyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;
    final theme = Theme.of(context);
    final textTheme = GoogleFonts.ibmPlexSansArabicTextTheme(theme.textTheme);

    final query = searchQuery.trim().toLowerCase();

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
          final matchesStatus =
              _selectedStatusSet.isEmpty ||
              _selectedStatusSet.contains(_getTaskStatus(task));
          return matchesSearch && matchesCategory && matchesStatus;
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
          appBar: const NameerAppBar(showTitleInBar: false, showBack: false),
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
                              'قائمة المهام',
                              style: GoogleFonts.ibmPlexSansArabic(
                                fontSize: 24,
                                fontWeight: FontWeight.w700,
                                color: appColors.dark,
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
          floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
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
                prefixIcon: Icon(Icons.search, color: appColors.primary),
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
            child: const Icon(Icons.tune, color: appColors.dark),
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
                color: appColors.dark,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: appColors.primary,
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
      case 'غير نشطة':
        statusColor = Colors.grey;
        break;
      case 'نشطة':
        statusColor = Colors.green;
        break;
      default:
        statusColor = Colors.black54;
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
                contentPadding: const EdgeInsets.only(
                  right: 16,
                  left: 8,
                  top: 4,
                  bottom: 4,
                ),

                // 👇 أيقونة المهمة (نفس أيقونة الفورم لعنوان المهمة)
                leading: const Icon(
                  Icons.task_alt_outlined,
                  color: appColors.primary,
                ),

                title: Text(
                  task['title'] ?? '',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: appColors.dark,
                  ),
                ),

                // 👇 الفئة مع أيقونة Category
                subtitle: GestureDetector(
                  onTap: () {
                    final catName = task['category']?.toString();
                    if (catName == null || catName.isEmpty) return;
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            AdminCategoryPage(initialCategoryName: catName),
                      ),
                    );
                  },
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.category_outlined,
                        size: 18,
                        color: appColors.sea,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        task['category'] ?? '',
                        style: const TextStyle(
                          fontSize: 13,
                          color: appColors.sea,
                          fontWeight: FontWeight.w600,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ],
                  ),
                ),

                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(height: 4),
                    IconButton(
                      iconSize: 26,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      icon: Icon(
                        isExpanded
                            ? Icons.keyboard_arrow_up
                            : Icons.keyboard_arrow_down,
                        color: appColors.primary,
                      ),
                      onPressed: () {
                        setState(() {
                          isExpanded
                              ? _expandedIndexes.remove(index)
                              : _expandedIndexes.add(index);
                        });
                      },
                    ),
                  ],
                ),
              ),
              if (isExpanded) _buildExpandedTaskContent(task),
            ],
          ),

          // 👇 شارة الحالة (بدون تغيير)
          Positioned(
            top: 8,
            left: 16,
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
    final statusText = _getTaskStatus(task);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 🔹 وصف المهمة + أيقونة الوصف
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.description_outlined,
                size: 20,
                color: appColors.dark,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  task['description'] ?? '',
                  style: const TextStyle(fontSize: 14, color: appColors.dark),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // 🔹 طريقة التحقق + أيقونة التحقق
          Row(
            children: [
              const Icon(
                Icons.verified_outlined,
                size: 20,
                color: appColors.sea,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'طريقة التحقق: ${task['validationStrategy'] ?? 'غير محددة'}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: appColors.sea,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),

          // 🔹 النقاط + أيقونة النجمة (نفس الفورم)
          Row(
            children: [
              const Icon(
                Icons.stars_rounded,
                size: 20,
                color: appColors.primary,
              ),
              const SizedBox(width: 6),
              Text(
                'النقاط: ${task['points'] ?? 0}',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: appColors.primary,
                ),
              ),
            ],
          ),
          // 🔥 العدّاد للمهمات التي تم إخفاؤها
          if (task['status'] == 'hidden' && task['expiry_month'] != null) ...[
            const SizedBox(height: 8),
            _buildHideCountdown(task),
          ],
          // 🔹 تاريخ الانتهاء (للمهام المنتهية فقط) + أيقونة التقويم
          if (statusText == 'منتهية' && task['expiry_month'] != null) ...[
            const SizedBox(height: 6),

            Row(
              children: [
                const Icon(
                  Icons.calendar_month,
                  size: 20,
                  color: Colors.redAccent,
                ),
                const SizedBox(width: 6),
                Text(
                  'تاريخ الانتهاء: ${task['expiry_month']}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.redAccent,
                  ),
                ),
              ],
            ),
          ],

          const SizedBox(height: 12),

          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              IconButton(
                icon: const Icon(Icons.edit_outlined, color: Colors.grey),
                onPressed: () async {
                  final updated = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          AddTaskPage(categories: _categories, task: task),
                    ),
                  );
                  if (updated == true) _fetchTasks();
                },
              ),
              IconButton(
                icon: Icon(
                  task['status'] == 'hidden'
                      ? Icons.visibility_rounded
                      : Icons.visibility_off_rounded,
                  color: task['status'] == 'hidden'
                      ? appColors.primary
                      : Colors.redAccent,
                ),
                onPressed: () {
                  if (task['status'] == 'hidden') {
                    _unhideTaskDialog(task);
                  } else {
                    _hideTaskDialog(task);
                  }
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHideCountdown(Map<String, dynamic> task) {
    final exp = task['expiry_month'];
    if (exp == null) return const SizedBox();

    final parts = exp.split('-');
    if (parts.length != 2) return const SizedBox();

    final year = int.tryParse(parts[0]) ?? 0;
    final month = int.tryParse(parts[1]) ?? 0;

    // بداية الشهر القادم
    final expiryDate = DateTime(year, month, 1);
    final now = DateTime.now();
    final diff = expiryDate.difference(now);

    if (diff.isNegative) {
      return const Text(
        '🔔 تم تطبيق الإخفاء هذا الشهر',
        style: TextStyle(
          fontSize: 13,
          color: Colors.redAccent,
          fontWeight: FontWeight.bold,
        ),
      );
    }

    final days = diff.inDays;
    final hours = diff.inHours % 24;
    final mins = diff.inMinutes % 60;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.timer_outlined, color: appColors.primary),
            const SizedBox(width: 8),
            Text(
              "متبقّي على بدء تطبيق إخفاء المهمة:",
              style: GoogleFonts.ibmPlexSansArabic(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.grey[800],
              ),
            ),
          ],
        ),

        const SizedBox(height: 10),

        // 👇👇 هنا نضيف المربعات 👇👇
        Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            timeFlipBox(days.toString().padLeft(2, '0'), "يوم"),
            const SizedBox(width: 8),
            timeFlipBox(hours.toString().padLeft(2, '0'), "ساعة"),
            const SizedBox(width: 8),
            timeFlipBox(mins.toString().padLeft(2, '0'), "دقيقة"),
          ],
        ),
      ],
    );
  }

  Widget timeFlipBox(String value, String label) {
    return Column(
      children: [
        Container(
          padding: EdgeInsets.symmetric(vertical: 5, horizontal: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: appColors.primary60, width: 1.3),
            boxShadow: [
              BoxShadow(
                color: appColors.primary33,
                blurRadius: 4,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Text(
            value,
            style: GoogleFonts.ibmPlexSansArabic(
              color: appColors.dark,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        SizedBox(height: 4),
        Text(
          label,
          style: GoogleFonts.ibmPlexSansArabic(
            color: appColors.dark,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // 🔹 منطق "إخفاء المهمة" المعدل وفق القاعدة الشهرية
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
              color: appColors.dark,
            ),
          ),
          content: Text(
            'هل أنت متأكد من إخفاء هذه المهمة؟ سيتم تطبيق الإخفاء في الشهر القادم ($nextMonthKey)',
            style: GoogleFonts.ibmPlexSansArabic(color: Colors.black87),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'إلغاء',
                style: GoogleFonts.ibmPlexSansArabic(
                  color: slackMesseges.red,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: appColors.primary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () async {
                Navigator.pop(context);
                final now = DateTime.now();
                final nextMonthDate = DateTime(now.year, now.month + 1, 1);
                final nextMonthKey =
                    "${nextMonthDate.year}-${nextMonthDate.month.toString().padLeft(2, '0')}";

                await FirebaseFirestore.instance
                    .collection('tasks')
                    .doc(task['id'])
                    .update({'status': 'hidden', 'expiry_month': nextMonthKey});

                if (mounted) {
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
                              color: appColors.primary,
                              size: 28,
                            ),
                            SizedBox(width: 8),
                            Text('تم جدولة الإخفاء'),
                          ],
                        ),
                        content: Text(
                          'سيتم تطبيق الإخفاء تلقائيًا في بداية الشهر القادم ($nextMonthKey).',
                          style: GoogleFonts.ibmPlexSansArabic(
                            color: appColors.dark,
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
                                color: appColors.primary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
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

  void _unhideTaskDialog(Map<String, dynamic> task) async {
    // 🔥 منع إظهار مهمة إذا كانت فئتها مخفية
    final catName = task['category'];
    final catDoc = await FirebaseFirestore.instance
        .collection('categories')
        .where('name', isEqualTo: catName)
        .limit(1)
        .get();

    if (catDoc.docs.isNotEmpty) {
      final catData = catDoc.docs.first.data() as Map<String, dynamic>;
      if (catData['status'] == 'hidden') {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: slackMesseges.red,
            content: Text(
              'لا يمكن إعادة إظهار هذه المهمة لأن الفئة التابعة لها مخفية ❌',
              style: GoogleFonts.ibmPlexSansArabic(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );
        return; // ❌ إيقاف الحوار بالكامل
      }
    }

    showDialog(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text(
            'إعادة إظهار المهمة',
            style: GoogleFonts.ibmPlexSansArabic(
              fontWeight: FontWeight.w800,
              color: appColors.dark,
            ),
          ),
          content: Text(
            'هل ترغب بإعادة إظهار هذه المهمة لتُعاد نشرها الشهر القادم؟',
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
                backgroundColor: appColors.primary,
              ),
              onPressed: () async {
                Navigator.pop(context);
                final nextMonth = DateTime.now().month + 1;
                final nextMonthKey =
                    "${DateTime.now().year}-${nextMonth.toString().padLeft(2, '0')}";
                await FirebaseFirestore.instance
                    .collection('tasks')
                    .doc(task['id'])
                    .update({'status': 'active', 'visible_from': nextMonthKey});
                _fetchTasks();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    backgroundColor: appColors.primary,
                    content: Text(
                      'تم إعادة إظهار المهمة ✅',
                      style: GoogleFonts.ibmPlexSansArabic(
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                );
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
  Widget _buildAddFab() {
    return FloatingActionButton(
      onPressed: _showAddOptionsSheet,
      backgroundColor: appColors.primary,
      shape: const CircleBorder(),
      child: const Icon(Icons.add, color: Colors.white, size: 28),
    );
  }

  // ---------------------------------------------------------------------------
  // 🔹 Bottom Sheet عند الضغط على زر الإضافة
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
                  color: appColors.dark,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 20),

              _gradientActionButton(
                icon: Icons.check_circle_outline,
                label: 'إضافة مهمة جديدة',
                colors: const [appColors.primary, appColors.mint],
                onTap: () async {
                  Navigator.pop(context);
                  final updated = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AddTaskPage(
                        categories: _categories,
                        preFillData: widget.preFillData, // 👈 تمرير البيانات
                      ),
                    ),
                  );
                  if (updated == true) _fetchTasks();
                },
              ),
              const SizedBox(height: 12),
              _gradientActionButton(
                icon: Icons.category_outlined,
                label: 'إضافة فئة جديدة',
                colors: const [appColors.mint, appColors.primary],
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

  // ---------------------------------------------------------------------------
  // 🔹 فلترة
  void _showFilterSheet() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) {
        final selectedLocal = Set<String>.from(_selectedCategories);
        final selectedStatuses = Set<String>.from(_selectedStatusSet);
        final statuses = ['نشطة', 'غير نشطة', 'منتهية'];

        return StatefulBuilder(
          builder: (context, setSt) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'تصفية المهام',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 12),

                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        'حسب الفئة',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: appColors.dark,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: _categories.map((cat) {
                        final selected = selectedLocal.contains(cat);
                        return FilterChip(
                          label: Text(cat),
                          selected: selected,
                          selectedColor: appColors.primary.withOpacity(.15),
                          labelStyle: TextStyle(
                            color: selected
                                ? appColors.primary
                                : appColors.dark,
                            fontWeight: FontWeight.w700,
                          ),
                          onSelected: (v) => setSt(
                            () => v
                                ? selectedLocal.add(cat)
                                : selectedLocal.remove(cat),
                          ),
                        );
                      }).toList(),
                    ),

                    const SizedBox(height: 16),

                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        'حسب الحالة',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: appColors.dark,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: statuses.map((s) {
                        final selected = selectedStatuses.contains(s);
                        return FilterChip(
                          label: Text(s),
                          selected: selected,
                          selectedColor: appColors.primary.withOpacity(.15),
                          labelStyle: TextStyle(
                            color: selected
                                ? appColors.primary
                                : appColors.dark,
                            fontWeight: FontWeight.w700,
                          ),
                          onSelected: (v) => setSt(
                            () => v
                                ? selectedStatuses.add(s)
                                : selectedStatuses.remove(s),
                          ),
                        );
                      }).toList(),
                    ),

                    const SizedBox(height: 20),

                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: appColors.primary,
                      ),
                      onPressed: () {
                        Navigator.pop(context);
                        setState(() {
                          _selectedCategories = selectedLocal;
                          _selectedStatusSet = selectedStatuses;
                        });
                      },
                      child: const Text('تطبيق'),
                    ),
                    TextButton(
                      onPressed: () {
                        Navigator.pop(context);
                        setState(() {
                          _selectedCategories.clear();
                          _selectedStatusSet.clear();
                        });
                      },
                      child: const Text('إلغاء الفلاتر'),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// ===============  Add / Edit Task Page  ==================

class AddTaskPage extends StatefulWidget {
  final Map<String, dynamic>? task;
  final List<String> categories;
  final Map<String, dynamic>? preFillData;

  const AddTaskPage({
    super.key,
    this.task,
    required this.categories,
    this.preFillData,
  });

  @override
  State<AddTaskPage> createState() => _AddTaskPageState();
}

class _AddTaskPageState extends State<AddTaskPage> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _pointsCtrl = TextEditingController();
  bool _isDirty = false;

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

    // ✅ تعبئة البيانات من preFillData إذا كانت موجودة
    if (widget.preFillData != null) {
      final data = widget.preFillData!;
      _titleCtrl.text = data['title'] ?? '';
      _descCtrl.text = data['description'] ?? '';
      _selectedCategory = data['category'];
      _validationType = data['validationStrategy'];
      // عرض رسالة ترحيبية
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('إضافة مهمة جديدة بناءً على توصية'),
            backgroundColor: Colors.green,
          ),
        );
      });
      if (data['type'] == 'delete') {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('تم توجيهك لصفحة المهام لحذف المهمة'),
              backgroundColor: Colors.red,
            ),
          );
        });
      }
    }

    _prefillIfEditing(); // هذا للـ task الحالي (تعديل)
  }

  void _fillFromPreFillData(Map<String, dynamic> data) {
    print('📦 Filling from preFillData: $data');

    // تعبئة العنوان
    if (data['title'] != null && data['title'].toString().isNotEmpty) {
      _titleCtrl.text = data['title'];
    }

    // تعبئة الوصف
    if (data['description'] != null &&
        data['description'].toString().isNotEmpty) {
      _descCtrl.text = data['description'];
    }

    // تعبئة التصنيف
    if (data['category'] != null && data['category'].toString().isNotEmpty) {
      _selectedCategory = data['category'];
    }

    // ✅ معالجة validationStrategy - الجزء المهم
    if (data['validationStrategy'] != null) {
      final strategy = data['validationStrategy'].toString();

      // القيم الصالحة للـ DropdownButton
      const validStrategies = [
        'التحقق عبر الصور',
        'التحقق عبر اجراء اختبار قصير',
      ];

      if (validStrategies.contains(strategy)) {
        _validationType = strategy;
      } else {
        // محاولة التطابق الضمني
        if (strategy.contains('صور') ||
            strategy.contains('معالجة') ||
            strategy.contains('image')) {
          _validationType = 'التحقق عبر معالجة الصور';
        } else if (strategy.contains('اختبار') ||
            strategy.contains('قراءة') ||
            strategy.contains('quiz')) {
          _validationType = 'التحقق عبر اجراء اختبار قصير';
        } else {
          _validationType = validStrategies.first; // القيمة الافتراضية
        }
        print(
          '⚠️ Mapped validation strategy: "$strategy" -> "$_validationType"',
        );
      }
    }

    // تعبئة النقاط
    if (data['points'] != null) {
      _pointsCtrl.text = data['points'].toString();
    }

    _isDirty = true;

    // عرض رسالة للمستخدم
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              data['type'] == 'modify'
                  ? '✏️ تعديل مهمة بناءً على توصية'
                  : '➕ إضافة مهمة جديدة بناءً على توصية',
              style: GoogleFonts.ibmPlexSansArabic(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
            backgroundColor: data['type'] == 'modify'
                ? Colors.orange
                : Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    });
  }

  void _generateMonths() {
    final months = <String>[];
    final start = DateTime.now();
    for (int i = 0; i < 24; i++) {
      final m = DateTime(start.year, start.month + i);
      months.add("${m.year}-${m.month.toString().padLeft(2, '0')}");
    }
    _monthsList = months;
  }

  Future<void> _loadCategories() async {
    try {
      final qs = await _categoriesCol.get();
      final names = <String>[];
      for (var doc in qs.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final name = data['name']?.toString().trim();
        if (name != null && name.isNotEmpty) {
          names.add(name);
        }
      }
      names.sort((a, b) => a.compareTo(b));
      setState(() {
        _categories = names;
        _catsLoading = false;
      });
    } catch (e) {
      setState(() => _catsLoading = false);
    }
  }

  void _prefillIfEditing() {
    final t = widget.task;
    if (t == null) return;

    _isEditing = true;

    _titleCtrl.text = t['title']?.toString() ?? '';
    _descCtrl.text = t['description']?.toString() ?? '';
    _pointsCtrl.text = t['points']?.toString() ?? '';

    _selectedCategory = t['category']?.toString();
    _validationType = t['validationStrategy']?.toString();
    _expiryMonth = t['expiry_month']?.toString();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  // ---------------------------------------------------------------------------
  // ✅ تطبيع نص بسيط
  String _norm(String s) =>
      s.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

  // ---------------------------------------------------------------------------
  // ✅ الربط التلقائي EF:
  //
  // يعتمد على:
  //  - keywords + name للتطابق مع نص المهمة
  //  - calcMode / حقول km للتمييز بين km و items
  //  - factorType في emissionFactors:
  //      • baseline  → السيناريو المرجعي (Landfill / سيارة ...)
  //      • actual    → السلوك الأفضل (إعادة التدوير / المترو ...)
  //
  Future<Map<String, dynamic>?> _autoPickEfForTask({
    required String title,
    required String desc,
  }) async {
    final text = _norm('$title $desc');

    final efSnap = await FirebaseFirestore.instance
        .collection('emissionFactors')
        .where('isActive', isEqualTo: true)
        .get();

    if (efSnap.docs.isEmpty) return null;

    int scoreFor(Map<String, dynamic> m) {
      final kws = (m['keywords'] is List)
          ? List.from(m['keywords'])
          : <dynamic>[];
      int s = 0;
      for (final k in kws) {
        final kw = k.toString().trim().toLowerCase();
        if (kw.isEmpty) continue;
        if (text.contains(kw)) s += 2;
      }
      final name = (m['name']?.toString().toLowerCase() ?? '');
      if (name.isNotEmpty && text.contains(name)) s += 1;
      return s;
    }

    bool isKmDoc(Map<String, dynamic> m) {
      final calcMode = (m['calcMode'] ?? m['calc_mode'] ?? '')
          .toString()
          .toLowerCase();
      if (calcMode == 'perkm' || calcMode == 'deltaperkm') return true;
      final hasKmField =
          m.containsKey('kgPerKm') ||
          m.containsKey('perKm') ||
          m.containsKey('co2PerKm') ||
          m.containsKey('co2_per_km');
      return hasKmField;
    }

    String factorTypeOf(Map<String, dynamic> m) =>
        (m['factorType'] ?? '').toString().toLowerCase();

    // جهّز كل العوامل مع بيانات الميتا
    final List<Map<String, dynamic>> factors = efSnap.docs.map((d) {
      final m = d.data() as Map<String, dynamic>;
      final s = scoreFor(m);
      final fType = factorTypeOf(m);
      final isBaseline = fType == 'baseline';
      final isActual = fType == 'actual';

      return {
        ...m,
        '__id': d.id,
        '__score': s,
        '__isKm': isKmDoc(m),
        '__isBaseline': isBaseline,
        '__isActual': isActual,
      };
    }).toList();

    // ترتيب العوامل بحسب درجة التطابق
    factors.sort(
      (a, b) => (b['__score'] as int).compareTo(a['__score'] as int),
    );

    if (factors.isEmpty || (factors.first['__score'] as int) <= 0) {
      // ما وجدنا شيء له علاقة بالنص
      return null;
    }

    // ------------------------------
    // 1) حالة km (المسافات / المواصلات)
    // ------------------------------
    final kmFactors = factors
        .where((m) => m['__isKm'] == true && (m['__score'] as int) > 0)
        .toList();

    if (kmFactors.isNotEmpty) {
      kmFactors.sort(
        (a, b) => (b['__score'] as int).compareTo(a['__score'] as int),
      );

      // ✅ actual: نأخذ أعلى عامل بدرجة تطابق ويكون factorType = actual إن وجد
      List<Map<String, dynamic>> kmActualCandidates = kmFactors
          .where((m) => m['__isActual'] == true)
          .toList();
      Map<String, dynamic> actualKm;
      if (kmActualCandidates.isNotEmpty) {
        actualKm = kmActualCandidates.first;
      } else {
        // لو ما فيه actual محدد، نأخذ أعلى عامل (أقرب واحد للنص)
        actualKm = kmFactors.first;
      }

      // ✅ baseline: نأخذ أعلى عامل factorType = baseline ومختلف عن actual
      Map<String, dynamic>? baselineKm;

      // 1) نحاول نلاقي doc بالـ ID المحدد حتى لو ما طابقت الـ keywords
      const String kDefaultKmBaselineId = 'transportCarGasolinePerKm';

      for (final f in factors) {
        if (f['__id'] == kDefaultKmBaselineId) {
          // نتأكد إنه عامل km فعلاً
          if (f['__isKm'] == true && f['__id'] != actualKm['__id']) {
            baselineKm = f;
          }
          break;
        }
      }

      // 2) لو ما لقينا هذا الـ ID أو ما كان km → نرجع للمنطق القديم
      if (baselineKm == null) {
        final baselineKmList = kmFactors
            .where(
              (m) => m['__isBaseline'] == true && m['__id'] != actualKm['__id'],
            )
            .toList();

        if (baselineKmList.isNotEmpty) {
          baselineKm = baselineKmList.first;
        }
      }

      if (baselineKm != null) {
        // ✅ deltaPerKm (baseline مقابل actual)
        return {
          'calcMode': 'deltaPerKm',
          //'direction': 'save',
          'baselineFactorRef': baselineKm['__id'],
          'actualFactorRef': actualKm['__id'],
          'calc_requires': {
            'askCount': false,
            'askDistanceKm': true,
            'autoDistance': true,
          },
          '__chosen_name':
              'Baseline: ${baselineKm['name'] ?? baselineKm['__id']} / Actual: ${actualKm['name'] ?? actualKm['__id']}',
        };
      } else {
        // ✅ perKm (عامل واحد فقط لكل كم)
        return {
          'calcMode': 'perKm',
          //'direction': 'save',
          'ef_ref': actualKm['__id'],
          'calc_requires': {
            'askCount': false,
            'askDistanceKm': true,
            'autoDistance': true,
          },
          '__chosen_name': actualKm['name'] ?? actualKm['__id'],
        };
      }
    }

    // ------------------------------
    // 2) حالة العناصر (per item / per piece)
    // ------------------------------
    final nonKmFactors = factors
        .where((m) => m['__isKm'] != true && (m['__score'] as int) > 0)
        .toList();

    if (nonKmFactors.isEmpty) return null;

    nonKmFactors.sort(
      (a, b) => (b['__score'] as int).compareTo(a['__score'] as int),
    );

    // ✅ actual: نفضّل factorType = actual لو موجود
    List<Map<String, dynamic>> itemActualCandidates = nonKmFactors
        .where((m) => m['__isActual'] == true)
        .toList();

    Map<String, dynamic> actualItem;
    if (itemActualCandidates.isNotEmpty) {
      actualItem = itemActualCandidates.first;
    } else {
      // fallback: أي عامل ليس baseline
      final nonBaseline = nonKmFactors
          .where((m) => m['__isBaseline'] != true)
          .toList();
      if (nonBaseline.isNotEmpty) {
        actualItem = nonBaseline.first;
      } else {
        // آخر حل: أول عامل
        actualItem = nonKmFactors.first;
      }
    }

    final baselineItemList = nonKmFactors
        .where(
          (m) => m['__isBaseline'] == true && m['__id'] != actualItem['__id'],
        )
        .toList();

    final Map<String, dynamic>? baselineItem = baselineItemList.isNotEmpty
        ? baselineItemList.first
        : null;

    if (baselineItem != null) {
      // ✅ deltaPerItem (قطعة لبس landfill vs إعادة تدوير)
      return {
        'calcMode': 'deltaPerItem',
        //'direction': 'save',
        'baselineFactorRef': baselineItem['__id'],
        'actualFactorRef': actualItem['__id'],
        'calc_requires': {
          'askCount': true,
          'askDistanceKm': false,
          'autoDistance': false,
        },
        '__chosen_name':
            'Baseline: ${baselineItem['name'] ?? baselineItem['__id']} / Actual: ${actualItem['name'] ?? actualItem['__id']}',
      };
    }

    // 🔁 fallback: perItem بعامل واحد (بدون baseline)
    return {
      'calcMode': 'perItem',
      //'direction': 'save',
      'ef_ref': actualItem['__id'],
      'calc_requires': {
        'askCount': true,
        'askDistanceKm': false,
        'autoDistance': false,
      },
      '__chosen_name': actualItem['name'] ?? actualItem['__id'],
    };
  }

  // ---------------------------------------------------------------------------
  // 🟩 واجهة الصفحة
  @override
  Widget build(BuildContext context) {
    final isEdit = _isEditing;
    final titleText = isEdit ? 'تعديل المهمة' : 'إضافة مهمة جديدة';

    return PopScope(
      canPop: true,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        if (await _confirmLeaveIfDirty()) {
          if (mounted) Navigator.pop(context);
        }
      },
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          extendBodyBehindAppBar: true,
          backgroundColor: appColors.background,
          appBar: const NameerAppBar(
            showTitleInBar: false,
            showBack: false,
            height: 80,
          ),
          body: Builder(
            builder: (context) {
              final statusBar = MediaQuery.of(context).padding.top;
              const headerH = 20.0;
              const gap = 12.0;
              final topPadding = statusBar + headerH + gap;

              return Padding(
                padding: EdgeInsets.fromLTRB(20, topPadding, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      titleText,
                      textAlign: TextAlign.right,
                      style: GoogleFonts.ibmPlexSansArabic(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: appColors.dark,
                      ),
                    ),
                    const SizedBox(height: 16),

                    Expanded(
                      child: SingleChildScrollView(
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _fieldLabel('عنوان المهمة', required: true),
                              const SizedBox(height: 8),
                              TextFormField(
                                controller: _titleCtrl,
                                decoration: const InputDecoration(
                                  hintText:
                                      'مثال: استخدام المترو بدلاً من السيارة',
                                  prefixIcon: Icon(Icons.task_alt_outlined),
                                ),
                                onChanged: (_) => _isDirty = true,
                                validator: (v) => (v == null || v.isEmpty)
                                    ? 'أدخل عنوان المهمة'
                                    : null,
                              ),
                              const SizedBox(height: 14),

                              _fieldLabel('وصف المهمة', required: true),
                              const SizedBox(height: 8),
                              TextFormField(
                                controller: _descCtrl,
                                maxLines: 2,
                                decoration: const InputDecoration(
                                  hintText:
                                      'مثال: اذهب بالمترو لمحطتين بدل استخدام السيارة',
                                  prefixIcon: Icon(Icons.description_outlined),
                                ),
                                onChanged: (_) => _isDirty = true,
                                validator: (v) => (v == null || v.isEmpty)
                                    ? 'أدخل وصف المهمة'
                                    : null,
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
                                onChanged: (_) => _isDirty = true,
                                validator: (v) {
                                  final n = int.tryParse(v ?? '');
                                  if (n == null || n <= 0) {
                                    return 'أدخل عددًا صحيحًا موجبًا';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 14),

                              _fieldLabel('تصنيف المهمة', required: true),
                              const SizedBox(height: 8),
                              DropdownButtonFormField<String>(
                                value: _categories.contains(_selectedCategory)
                                    ? _selectedCategory
                                    : null,
                                alignment: Alignment.centerRight,
                                isExpanded: true,
                                decoration: InputDecoration(
                                  hintText: _catsLoading
                                      ? '...يتم تحميل الفئات'
                                      : 'اختر الفئة',
                                  prefixIcon: const Icon(
                                    Icons.category_outlined,
                                    color: appColors.primary,
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
                                onChanged: (v) {
                                  setState(() => _selectedCategory = v);
                                  _isDirty = true;
                                },
                                validator: (v) => (v == null || v.isEmpty)
                                    ? 'اختر تصنيف المهمة'
                                    : null,
                              ),
                              const SizedBox(height: 20),

                              Row(
                                children: [
                                  _fieldLabel('طريقة التحقق', required: true),
                                  const SizedBox(width: 6),
                                  Tooltip(
                                    message:
                                        'التحقق عبر معالجة الصور: للمهام التي تتطلب إثباتًا بصريًا\nالتحقق عبر اختبار قصير/قراءة: للمهام المعرفية',
                                    textStyle: GoogleFonts.ibmPlexSansArabic(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.black87,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    padding: const EdgeInsets.all(12),
                                    preferBelow: false,
                                    triggerMode: TooltipTriggerMode.tap,
                                    child: const Icon(
                                      Icons.info_outline,
                                      color: appColors.primary,
                                      size: 18,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              DropdownButtonFormField<String>(
                                value: _validationType,
                                alignment: Alignment.centerRight,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                  hintText: 'اختر طريقة التحقق',
                                  prefixIcon: Icon(
                                    Icons.verified_outlined,
                                    color: appColors.primary,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.all(
                                      Radius.circular(12),
                                    ),
                                  ),
                                ),
                                items: const [
                                  DropdownMenuItem(
                                    value: 'التحقق عبر معالجة الصور',
                                    child: Text('التحقق عبر معالجة الصور'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'التحقق عبر اجراء اختبار قصير',
                                    child: Text('التحقق عبر اجراء اختبار قصير'),
                                  ),
                                ],
                                onChanged: (v) {
                                  setState(() => _validationType = v);
                                  _isDirty = true;
                                },
                                validator: (v) {
                                  if (v == null || v.isEmpty) {
                                    return 'اختر طريقة التحقق';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 20),

                              _fieldLabel('تاريخ انتهاء المهمة (شهر)'),
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
                                    _isDirty = true;

                                    final currentKey = currentMonth;
                                    if (_expiryMonth!.compareTo(currentKey) <=
                                        0) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          backgroundColor: Colors.redAccent,
                                          content: Text(
                                            '⚠️ الشهر المختار منتهي أو داخل الشهر الحالي — سيتم التعامل معه كإخفاء بدءًا من الشهر القادم',
                                            style:
                                                GoogleFonts.ibmPlexSansArabic(
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
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                  ),
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: appColors.light.withOpacity(.7),
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                    color: Colors.white,
                                  ),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        _expiryMonth == null
                                            ? 'اختر شهر الانتهاء (اختياري)'
                                            : _expiryMonth!,
                                        style: GoogleFonts.ibmPlexSansArabic(
                                          color: appColors.dark,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const Icon(
                                        Icons.calendar_month,
                                        color: appColors.primary,
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
                                onPressed: () async {
                                  if (await _confirmLeaveIfDirty()) {
                                    if (mounted) Navigator.pop(context);
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
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
        return Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: MediaQuery.of(context).size.width * 0.85,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 25),
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
                        color: appColors.dark,
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

                    Container(
                      width: double.infinity,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [appColors.primary, appColors.mint],
                          begin: Alignment.bottomLeft,
                          end: Alignment.topRight,
                        ),
                        borderRadius: BorderRadius.all(Radius.circular(14)),
                      ),
                      child: ElevatedButton.icon(
                        icon: const Icon(
                          Icons.exit_to_app,
                          color: Colors.white,
                        ),
                        onPressed: () {
                          shouldLeave = true;
                          Navigator.pop(context);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        label: Text(
                          'تأكيد الخروج',
                          style: GoogleFonts.ibmPlexSansArabic(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 10),

                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(
                          color: Colors.redAccent,
                          width: 1.4,
                        ),
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
        );
      },
    );

    return shouldLeave;
  }

  // ---------------------------------------------------------------------------
  // 🧩 منطق الحفظ — Auto EF mapping بالكامل
  Future<void> _saveTask() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final title = _titleCtrl.text.trim();
    final desc = _descCtrl.text.trim();
    final normalizedTitle = _norm(title);

    // 🔹 التحقق من التكرار (فقط للإضافة الجديدة)
    if (widget.task == null) {
      final existing = await _tasks
          .where('title_normalized', isEqualTo: normalizedTitle)
          .limit(1)
          .get();
      if (existing.docs.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: slackMesseges.red,
            content: Text(
              'اسم المهمة "$title" مستخدم بالفعل',
              style: GoogleFonts.ibmPlexSansArabic(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );
        return;
      }
    }

    // 🔹 نجيب بيانات الفئة عشان نعرف هل هي سلوك غير مباشر
    bool isIndirectCategory = false;
    if (_selectedCategory != null && _selectedCategory!.isNotEmpty) {
      final catSnap = await FirebaseFirestore.instance
          .collection('categories')
          .where('name', isEqualTo: _selectedCategory)
          .limit(1)
          .get();

      if (catSnap.docs.isNotEmpty) {
        final catData = catSnap.docs.first.data() as Map<String, dynamic>;
        isIndirectCategory = catData['parent']?.toString() == 'سلوك غير مباشر';
      }
    }

    // 🔹 تحديد الحالة
    String status = 'active';
    if (_expiryMonth != null && _expiryMonth!.compareTo(currentMonth) <= 0) {
      status = 'hidden';
    }

    // ✅ الربط التلقائي EF (km + items) إذا كانت الفئة "سلوك مباشر" فقط
    Map<String, dynamic>? autoEf;
    if (!isIndirectCategory) {
      autoEf = await _autoPickEfForTask(title: title, desc: desc);
    }

    // إعداد البيانات الأساسية
    final data = <String, dynamic>{
      'title': title,
      'title_normalized': normalizedTitle,
      'description': desc,
      'points': int.parse(_pointsCtrl.text),
      'category': _selectedCategory,
      'validationStrategy': _validationType,
      'status': status,
      'visible_from': nextMonth,
      if (_expiryMonth != null) 'expiry_month': _expiryMonth,
      //'managedBy': 'nameer admin',
      //'updatedAt': FieldValue.serverTimestamp(),
    };

    // 🟢 حقول الكربون فقط لو الفئة "سلوك مباشر"
    if (!isIndirectCategory) {
      if (autoEf != null) {
        final calcMode = (autoEf['calcMode'] ?? 'perItem').toString();
        data['calcMode'] = calcMode;
        //data['direction'] = 'save';

        if (autoEf['calc_requires'] != null) {
          data['calc_requires'] = autoEf['calc_requires'];
        }

        // if (autoEf['__chosen_name'] != null) {
        //   data['ef_debugLabel'] = autoEf['__chosen_name'];
        // }

        final lowerMode = calcMode.toLowerCase();

        if (lowerMode == 'deltaperkm' || lowerMode == 'deltaperitem') {
          if (autoEf['baselineFactorRef'] != null) {
            data['baselineFactorRef'] = autoEf['baselineFactorRef'];
          }
          if (autoEf['actualFactorRef'] != null) {
            data['emissionFactorRef'] = autoEf['actualFactorRef'];
          }
        } else {
          if (autoEf['ef_ref'] != null) {
            data['emissionFactorRef'] = autoEf['ef_ref'];
          }
        }
      } else {
        // fallback بسيط: لو ما في تطابق، نخلي perItem (بدون مراجع)
        data['calcMode'] = 'perItem';
        //data['direction'] = 'save';
      }
    } else {
      // 🔻 إذا الفئة "سلوك غير مباشر" و كنا نعدّل مهمة قديمة
      // نمسح حقول الكربون من المهمة في حالة التحديث
      if (widget.task != null) {
        data['calcMode'] = FieldValue.delete();
        //data['direction'] = FieldValue.delete();
        data['emissionFactorRef'] = FieldValue.delete();
        data['baselineFactorRef'] = FieldValue.delete();
        data['calc_requires'] = FieldValue.delete();
        //data['ef_debugLabel'] = FieldValue.delete();
      }
      // في حالة الإضافة الجديدة ما نضيف أي من الحقول السابقة أساساً 👍
    }

    // حفظ في فايربيس
    if (widget.task == null) {
      //data['createdAt'] = FieldValue.serverTimestamp();
      await _tasks.add(data);
    } else {
      await _tasks.doc(widget.task!['id']).update(data);
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: appColors.primary,
          content: Text(
            widget.task == null ? 'تم حفظ المهمة ✅' : 'تم تحديث المهمة ✅',
            style: GoogleFonts.ibmPlexSansArabic(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
      Navigator.pop(context, true);
    }
  }

  // ---------------------------------------------------------------------------
  // 🗓 Bottom Sheet لاختيار (السنة + الشهر)
  Future<String?> _showExpiryMonthPicker({
    required BuildContext context,
    required int initialYear,
    required int initialMonth,
    String? selected,
  }) async {
    int year = initialYear;
    String? result = selected;

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
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          tooltip: 'السنة السابقة',
                          onPressed: () => setSt(() => year--),
                          icon: const Icon(
                            Icons.chevron_left,
                            size: 28,
                            color: appColors.dark,
                          ),
                        ),
                        Text(
                          '$year',
                          style: GoogleFonts.ibmPlexSansArabic(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: appColors.dark,
                          ),
                        ),
                        IconButton(
                          tooltip: 'السنة التالية',
                          onPressed: () => setSt(() => year++),
                          icon: const Icon(
                            Icons.chevron_right,
                            size: 28,
                            color: appColors.dark,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: List.generate(12, (i) {
                        final m = i + 1;
                        final key = "$year-${m.toString().padLeft(2, '0')}";
                        final disabled = isPast(year, m);
                        final isSelected = result == key;

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
                                    if (isSelected) {
                                      result = null;
                                    } else {
                                      result = key;
                                    }
                                    setSt(() {});
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
                                    backgroundColor:
                                        MaterialStateProperty.resolveWith<
                                          Color?
                                        >((states) {
                                          if (disabled) {
                                            return Colors.grey.shade200;
                                          }
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
                                          appColors.primary,
                                          appColors.mint,
                                        ],
                                      )
                                    : null,
                                border: isSelected || disabled
                                    ? null
                                    : Border.all(
                                        color: appColors.light.withOpacity(.7),
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
                                      : appColors.dark,
                                ),
                              ),
                            ),
                          ),
                        );
                      }),
                    ),

                    const SizedBox(height: 16),

                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(
                                color: Colors.redAccent,
                                width: 1.2,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            onPressed: () {
                              result = selected;
                              Navigator.pop(context);
                            },
                            child: Text(
                              'إلغاء',
                              style: GoogleFonts.ibmPlexSansArabic(
                                color: Colors.redAccent,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Container(
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                colors: [appColors.primary, appColors.mint],
                              ),
                              borderRadius: BorderRadius.all(
                                Radius.circular(12),
                              ),
                            ),
                            child: ElevatedButton(
                              onPressed: () {
                                Navigator.pop(context);
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.transparent,
                                shadowColor: Colors.transparent,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: Text(
                                'تم',
                                style: GoogleFonts.ibmPlexSansArabic(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                ),
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
          color: appColors.dark.withOpacity(.9),
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
        gradient: LinearGradient(colors: [appColors.primary, appColors.mint]),
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
        return Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: MediaQuery.of(context).size.width * 0.85,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 25),
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
                        color: appColors.dark,
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

                    Container(
                      width: double.infinity,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [appColors.primary, appColors.mint],
                        ),
                        borderRadius: BorderRadius.all(Radius.circular(14)),
                      ),
                      child: ElevatedButton.icon(
                        icon: const Icon(
                          Icons.exit_to_app,
                          color: Colors.white,
                        ),
                        onPressed: () {
                          shouldLeave = true;
                          Navigator.pop(context);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        label: Text(
                          'تأكيد الخروج',
                          style: GoogleFonts.ibmPlexSansArabic(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 10),

                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(
                          color: Colors.redAccent,
                          width: 1.4,
                        ),
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
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          extendBodyBehindAppBar: true,
          backgroundColor: appColors.background,
          appBar: NameerAppBar(
            showTitleInBar: false,
            showBack: false,
            height: 80,
          ),
          body: Builder(
            builder: (context) {
              final statusBar = MediaQuery.of(context).padding.top;
              const headerH = 20.0;
              const gap = 12.0;
              final topPadding = statusBar + headerH + gap;

              return SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(20, topPadding, 20, 20),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        titleText,
                        textAlign: TextAlign.right,
                        style: GoogleFonts.ibmPlexSansArabic(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: appColors.dark,
                        ),
                      ),
                      const SizedBox(height: 20),

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
                            if (mounted) Navigator.pop(context, false);
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
    final normalized = _nameCtrl.text
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ')
        .toLowerCase();

    if (widget.category == null) {
      final dup = await _categoriesCol
          .where('name_normalized', isEqualTo: normalized)
          .limit(1)
          .get();

      if (dup.docs.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: slackMesseges.red,
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
        //'createdAt': FieldValue.serverTimestamp(),
      });
    } else {
      await _categoriesCol.doc(widget.category!['id']).update({
        'name': _nameCtrl.text.trim(),
        'name_normalized': normalized,
        'parent': _parent,
        'description': _descCtrl.text.trim(),
        //'createdAt': FieldValue.serverTimestamp(),
      });
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: slackMesseges.primary,
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
          color: appColors.dark.withOpacity(.9),
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
        gradient: LinearGradient(colors: [appColors.primary, appColors.mint]),
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
