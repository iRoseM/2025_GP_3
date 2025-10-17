import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'admin_bottom_nav.dart';
import 'admin_home.dart';
import 'admin_reward.dart';
import 'admin_map.dart';
import 'dart:ui';
import 'background_container.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AdminTasksPage extends StatefulWidget {
  const AdminTasksPage({super.key});

  @override
  State<AdminTasksPage> createState() => _AdminTasksPageState();
}

class _AdminTasksPageState extends State<AdminTasksPage> {
  List<String> _categories = [];
  bool _isCatsLoading = true;

  int _currentIndex = 2;
  String searchQuery = '';
  Set<String> _selectedCategories = {}; // can hold multiple categories

  final CollectionReference _taskCollection =
      FirebaseFirestore.instance.collection('tasks');

  List<Map<String, dynamic>> _tasks = [];
  bool _isLoading = true;

  final Set<int> _expandedIndexes = {};

  @override
  void initState() {
    super.initState();
    _loadTasks();
    _loadCategories();
  }

  Future<void> _loadTasks() async {
    try {
      final querySnapshot = await _taskCollection.get();

      final now = DateTime.now();

      for (final doc in querySnapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final expiry = (data['expiryDate'] as Timestamp?)?.toDate();
        final isActive = data['isActive'] ?? false;

        // 🔹 If expired, mark inactive automatically
        if (expiry != null && expiry.isBefore(now) && isActive == true) {
          await _taskCollection.doc(doc.id).update({'isActive': false});
        }
      }

      setState(() {
        _tasks = querySnapshot.docs.map((doc) {
          final data = doc.data() as Map<String, dynamic>;
          data['id'] = doc.id;
          return data;
        }).toList();

        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading tasks: $e');
      setState(() => _isLoading = false);
    }
  }
  Future<void> _loadCategories() async {
  try {
    final qs = await FirebaseFirestore.instance.collection('categories').get();
    final names = qs.docs
        .map((d) => (d.data()['name'] ?? '').toString().trim())
        .where((n) => n.isNotEmpty)
        .toSet()
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

  
  // ============================================================
  // 🔹 Navigation
  void _onTap(int i) {
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

  // ============================================================
  // 🔹 UI
  @override
  Widget build(BuildContext context) {
    final isKeyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;
    final baseTheme = Theme.of(context);
    final textTheme =
        GoogleFonts.ibmPlexSansArabicTextTheme(baseTheme.textTheme);

    final q = searchQuery.trim().toLowerCase();

    final filteredTasks = _tasks.where((task) {
      final title = task['title']?.toString().toLowerCase() ?? '';
      final desc = task['description']?.toString().toLowerCase() ?? '';
      final cat = task['category']?.toString() ?? '';
      final matchesSearch = q.isEmpty || title.contains(q) || desc.contains(q);
      final matchesCategory =
          _selectedCategories.isEmpty || _selectedCategories.contains(cat);
      return matchesSearch && matchesCategory;
    }).toList()
      ..sort((a, b) {
        if (a['isActive'] == b['isActive']) return 0;
        return a['isActive'] == true ? -1 : 1;
      });

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Theme(
        data: baseTheme.copyWith(
          textTheme: textTheme,
          appBarTheme: AppBarTheme(
            elevation: 0,
            backgroundColor: Colors.transparent,
            titleTextStyle: GoogleFonts.ibmPlexSansArabic(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
            iconTheme: const IconThemeData(color: Colors.white),
          ),
        ),
        child: Scaffold(
          extendBody: true,
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            centerTitle: true,
            title: const Text("قائمة المهام"),
            flexibleSpace: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.primary,
                    AppColors.primary,
                    AppColors.mint,
                  ],
                  begin: Alignment.bottomLeft,
                  end: Alignment.topRight,
                ),
              ),
            ),
          ),

          // ---------------- BODY ----------------
          body: AnimatedBackgroundContainer(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : Column(
                      children: [
                        _buildSearchBar(),
                        const SizedBox(height: 12),
                        _buildTaskList(filteredTasks),
                      ],
                    ),
            ),
          ),

          // ---------------- ADD BUTTON ----------------
          floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
          floatingActionButton: Padding(
            padding: const EdgeInsets.only(right: 300, bottom: 10),
            child: FloatingActionButton(
              backgroundColor: AppColors.primary,
              shape: const CircleBorder(),
              onPressed: _showAddOptionsSheet, // ✅ new bottom sheet trigger
              child: const Icon(Icons.add, color: Colors.white, size: 28),
            ),
          ),
          bottomNavigationBar: isKeyboardOpen
              ? null
              : AdminBottomNav(currentIndex: _currentIndex, onTap: _onTap),
        ),
      ),
    );
  }

  // ============================================================
  // 🔹 Components

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
              textInputAction: TextInputAction.search,
              onChanged: (v) => setState(() => searchQuery = v),
              decoration: const InputDecoration(
                hintText: 'ابحث عن مهمة...',
                prefixIcon: Icon(Icons.search, color: AppColors.primary),
                border: InputBorder.none,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        InkWell(
          onTap: _showFiltersBottomSheet,
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
                    offset: Offset(0, 6)),
              ],
            ),
            child: const Icon(Icons.tune, color: AppColors.dark),
          ),
        ),
      ],
    );
  }

  Widget _buildTaskList(List<Map<String, dynamic>> tasks) {
    if (tasks.isEmpty) {
      return const Expanded(
        child: Center(
          child: Text(
            'لا توجد مهام متاحة',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.grey,
            ),
          ),
        ),
      );
    }

    return Expanded(
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 120),
        itemCount: tasks.length,
        itemBuilder: (context, index) {
          final task = tasks[index];
          final isExpanded = _expandedIndexes.contains(index);
          return AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade200, width: 1.2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.12),
                  blurRadius: 5,
                  spreadRadius: 2,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Column(
              children: [
              ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                title: Text(
                  task['title'] ?? 'بدون عنوان',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF333333),
                  ),
                ),
                  subtitle: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    children: [
                      const Icon(Icons.category_outlined,
                          size: 16, color: AppColors.dark),
                      const SizedBox(width: 6),
                      Text(
                        task['category'] ?? 'غير مصنف',
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF666666),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isExpanded
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 6),
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: (task['isActive'] == true)
                            ? Colors.green
                            : Colors.grey.shade400,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ),
                onTap: () {
                  setState(() {
                    if (isExpanded) {
                      _expandedIndexes.remove(index);
                    } else {
                      _expandedIndexes.add(index);
                    }
                  });
                },
              ),
                if (isExpanded) _buildExpandedTaskContent(task, index),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildExpandedTaskContent(Map<String, dynamic> task, int index) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(task['description'] ?? '',
              style: const TextStyle(fontSize: 14, color: Color(0xFF555555))),
          const SizedBox(height: 8),
          Text('النقاط: ${task['points'] ?? 0}',
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary)),
          const SizedBox(height: 8),
          Text('إستراتيجية التحقق: ${task['validationStrategy'] ?? 'غير محددة'}',
              style: const TextStyle(fontSize: 13, color: Color(0xFF666666))),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.edit, color: Colors.grey),
                onPressed: () => _showEditDialog(task),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                onPressed: () => _showDeleteDialog(task),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ============================================================
  // 🔸 Dialogs

  void _showAddTaskDialog() => _showTaskDialog(title: 'إضافة مهمة جديدة');
  void _showEditDialog(Map<String, dynamic> task) =>
      _showTaskDialog(title: 'تعديل معلومات المهمة', task: task);

void _showTaskDialog({required String title, Map<String, dynamic>? task}) {
  final formKey = GlobalKey<FormState>();
  final titleCtrl = TextEditingController(text: task?['title'] ?? '');
  final descCtrl = TextEditingController(text: task?['description'] ?? '');
  final pointsCtrl = TextEditingController(text: task != null ? '${task['points']}' : '');
  String? validationType = task?['validationStrategy'];
  String? selectedCategory = task?['category'];

  bool hasExpiry = task?['hasExpiry'] ?? ((task?['expiryDate'] as Timestamp?) != null);
  DateTime? expiryDate = (task?['expiryDate'] as Timestamp?)?.toDate();
  bool isActive = task?['isActive'] ?? (!hasExpiry ? false : true);

  showModalBottomSheet(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) => Builder(
      builder: (rootContext) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 24 + 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              boxShadow: const [
                BoxShadow(color: Color(0x33000000), blurRadius: 10, offset: Offset(0, 4)),
              ],
            ),
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Text(title,
                          style: GoogleFonts.ibmPlexSansArabic(
                            fontWeight: FontWeight.w800,
                            fontSize: 18,
                            color: AppColors.dark,
                          )),
                    ),
                    const SizedBox(height: 18),

                    _fieldLabel('عنوان المهمة', required: true),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: titleCtrl,
                      decoration: const InputDecoration(
                        hintText: 'مثال: إعادة تدوير الورق',
                        prefixIcon: Icon(Icons.task_alt_outlined),
                      ),
                      validator: (v) => (v == null || v.isEmpty) ? 'أدخل عنوان المهمة' : null,
                    ),
                    const SizedBox(height: 14),

                    _fieldLabel('وصف المهمة', required: true),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: descCtrl,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        hintText: 'اكتب وصفًا موجزًا للمهمة...',
                        prefixIcon: Icon(Icons.description_outlined),
                      ),
                      validator: (v) => (v == null || v.isEmpty) ? 'أدخل وصف المهمة' : null,
                    ),
                    const SizedBox(height: 14),

                    _fieldLabel('عدد النقاط', required: true),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: pointsCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        hintText: 'مثال: 30',
                        prefixIcon: Icon(Icons.star_border_rounded),
                      ),
                      validator: (v) {
                        final n = int.tryParse(v ?? '');
                        if (n == null || n <= 0) return 'أدخل عددًا صحيحًا موجبًا';
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),

                    _fieldLabel('تصنيف المهمة', required: true),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(color: AppColors.light.withOpacity(.7)),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: selectedCategory,
                          isExpanded: true,
                          hint: _isCatsLoading
                              ? const Text('...يتم تحميل الفئات')
                              : const Text('اختر الفئة'),
                          items: _categories.map((name) {
                            return DropdownMenuItem(value: name, child: Text(name));
                          }).toList(),
                          onChanged: (v) => selectedCategory = v,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    _fieldLabel('صلاحية المهمة', required: true),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.transparent,
                        border: Border.all(color: AppColors.light.withOpacity(.6)),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          RadioListTile<bool>(
                            value: false,
                            groupValue: hasExpiry,
                            activeColor: AppColors.primary,
                            title: const Text('بدون تاريخ انتهاء'),
                            onChanged: (v) {
                              hasExpiry = v ?? false;
                              expiryDate = null;
                            },
                          ),
                          const Divider(height: 0),
                          RadioListTile<bool>(
                            value: true,
                            groupValue: hasExpiry,
                            activeColor: AppColors.primary,
                            title: const Text('تاريخ انتهاء محدد'),
                            onChanged: (v) {
                              hasExpiry = v ?? true;
                              if (expiryDate == null) {
                                expiryDate = DateTime.now().add(const Duration(days: 7));
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    if (hasExpiry) ...[
                      _fieldLabel('تاريخ الانتهاء', required: true),
                      const SizedBox(height: 8),
                      InkWell(
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: expiryDate ?? DateTime.now().add(const Duration(days: 7)),
                            firstDate: DateTime.now(),
                            lastDate: DateTime(2030),
                            builder: (context, child) => Directionality(
                              textDirection: TextDirection.rtl,
                              child: Theme(
                                data: Theme.of(context).copyWith(
                                  colorScheme: const ColorScheme.light(
                                    primary: AppColors.primary,
                                    onPrimary: Colors.white,
                                    onSurface: AppColors.dark,
                                  ),
                                ),
                                child: child!,
                              ),
                            ),
                          );
                          if (picked != null) expiryDate = picked;
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
                          decoration: BoxDecoration(
                            border: Border.all(color: AppColors.light.withOpacity(.6)),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                expiryDate == null
                                    ? 'اختر تاريخ الانتهاء'
                                    : 'تاريخ الانتهاء: ${expiryDate!.day}-${expiryDate!.month}-${expiryDate!.year}',
                                style: GoogleFonts.ibmPlexSansArabic(
                                    color: AppColors.dark, fontWeight: FontWeight.w700),
                              ),
                              const Icon(Icons.calendar_today,
                                  color: AppColors.primary, size: 20),
                            ],
                          ),
                        ),
                      ),
                    ] else ...[
                      Row(
                        children: [
                          Checkbox(
                            value: isActive,
                            activeColor: AppColors.primary,
                            onChanged: (v) => isActive = v ?? false,
                          ),
                          Text('تفعيل المهمة',
                              style: GoogleFonts.ibmPlexSansArabic(
                                fontWeight: FontWeight.w700,
                                color: AppColors.dark.withOpacity(.9),
                              )),
                        ],
                      ),
                    ],

                    const SizedBox(height: 20),

                    // ✅ Save button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.save, color: Colors.white),
                        label: Text('حفظ التغييرات',
                            style: GoogleFonts.ibmPlexSansArabic(
                                color: Colors.white, fontWeight: FontWeight.w800)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          padding:
                              const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
                        ),
                        onPressed: () async {
                          if (!(formKey.currentState?.validate() ?? false)) return;

                          if (selectedCategory == null || selectedCategory!.isEmpty) {
                            ScaffoldMessenger.of(rootContext).showSnackBar(SnackBar(
                              backgroundColor: Colors.redAccent,
                              behavior: SnackBarBehavior.floating,
                              content: Text('اختر تصنيف المهمة',
                                  style: GoogleFonts.ibmPlexSansArabic(
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white)),
                            ));
                            return;
                          }

                          try {
                            final newTitle = titleCtrl.text
                                .trim()
                                .replaceAll(RegExp(r'\s+'), ' ')
                                .toLowerCase();

                            if (task == null) {
                              final existingTask = await _taskCollection
                                  .where('title_normalized', isEqualTo: newTitle)
                                  .limit(1)
                                  .get();

                              if (existingTask.docs.isNotEmpty) {
                                ScaffoldMessenger.of(rootContext).showSnackBar(SnackBar(
                                  backgroundColor: Colors.redAccent,
                                  behavior: SnackBarBehavior.floating,
                                  content: Text(
                                    'اسم المهمة "${titleCtrl.text.trim()}" مستخدم بالفعل، يرجى اختيار اسم آخر',
                                    style: GoogleFonts.ibmPlexSansArabic(
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white),
                                  ),
                                ));
                                return;
                              }
                            }

                            final data = {
                              'title': titleCtrl.text.trim(),
                              'title_normalized': newTitle,
                              'description': descCtrl.text.trim(),
                              'points': int.parse(pointsCtrl.text),
                              'validationStrategy': validationType,
                              'category': selectedCategory,
                              'hasExpiry': hasExpiry,
                              'expiryDate': hasExpiry && expiryDate != null
                                  ? Timestamp.fromDate(expiryDate!)
                                  : null,
                              'isActive': hasExpiry ? true : isActive,
                              'managedBy': 'nameer admin',
                              'createdAt': FieldValue.serverTimestamp(),
                            };

                            if (task == null) {
                              await _taskCollection.add(data);
                            } else {
                              await _taskCollection.doc(task['id']).update(data);
                            }

                            if (mounted) {
                              Navigator.pop(rootContext);
                              _loadTasks();
                              ScaffoldMessenger.of(rootContext).showSnackBar(SnackBar(
                                backgroundColor: Colors.green,
                                behavior: SnackBarBehavior.floating,
                                content: Text('تم الحفظ بنجاح ✅',
                                    style: GoogleFonts.ibmPlexSansArabic(
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white)),
                              ));
                            }
                          } catch (e) {
                            debugPrint('Error saving: $e');
                          }
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
  );
}



  Widget _fieldLabel(String text, {bool required = false}) {
    return Align(
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
  }

  // ============================================================
  // 🔸 Delete Confirmation
  void _showDeleteDialog(Map<String, dynamic> task) {
    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierLabel: '',
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 25),
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
                      const Icon(Icons.warning_amber_rounded,
                          color: Colors.redAccent, size: 48),
                      const SizedBox(height: 10),
                      Text('تأكيد الحذف',
                          style: GoogleFonts.ibmPlexSansArabic(
                              fontWeight: FontWeight.w800,
                              fontSize: 20,
                              color: AppColors.dark)),
                      const SizedBox(height: 8),
                      Text('هل أنت متأكد من حذف هذه المهمة؟',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.ibmPlexSansArabic(
                              fontSize: 15, color: Colors.black87)),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.delete_outline,
                              color: Colors.white),
                          label: Text('تأكيد الحذف',
                              style: GoogleFonts.ibmPlexSansArabic(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            padding:
                                const EdgeInsets.symmetric(vertical: 14),
                          ),
                          onPressed: () async {
                            try {
                              await _taskCollection
                                  .doc(task['id'])
                                  .delete();
                              Navigator.pop(context);
                              _loadTasks();
                              ScaffoldMessenger.of(context)
                                  .showSnackBar(SnackBar(
                                content: Text('تم حذف المهمة بنجاح 🗑️',
                                    style: GoogleFonts.ibmPlexSansArabic(
                                        fontWeight: FontWeight.w700)),
                                behavior:
                                    SnackBarBehavior.floating,
                              ));
                            } catch (e) {
                              debugPrint('Error deleting: $e');
                            }
                          },
                        ),
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.redAccent),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                          padding:
                              const EdgeInsets.symmetric(vertical: 14),
                          minimumSize:
                              const Size(double.infinity, 48),
                        ),
                        onPressed: () => Navigator.pop(context),
                        child: Text('إلغاء',
                            style: GoogleFonts.ibmPlexSansArabic(
                                color: Colors.redAccent,
                                fontWeight: FontWeight.w700)),
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
  }

  // ============================================================
  // 🔸 Filters Bottom Sheet
  void _showFiltersBottomSheet() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) {
        final allCats = List<String>.from(_categories);

        final selectedLocal = Set<String>.from(_selectedCategories);

        return StatefulBuilder(
          builder: (context, setSt) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'تصفية المهام حسب الفئة',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: allCats.map((cat) {
                      final selected = selectedLocal.contains(cat);
                      return FilterChip(
                        label: Text(cat),
                        selected: selected,
                        onSelected: (v) {
                          setSt(() {
                            if (v) {
                              selectedLocal.add(cat);
                            } else {
                              selectedLocal.remove(cat);
                            }
                          });
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary),
                      onPressed: () {
                        Navigator.pop(context);
                        setState(() => _selectedCategories = selectedLocal);
                      },
                      child: const Text('تطبيق'),
                    ),
                  ),
                  const SizedBox(height: 8),
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
  // ============================
// 🪄 Add Options Bottom Sheet
  void _showAddOptionsSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
          decoration: BoxDecoration(
            color: Colors.white, // ✅ same background as other popups
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            boxShadow: const [
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

              // ✅ Gradient button: إضافة مهمة جديدة
              SizedBox(
                width: double.infinity,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [
                        AppColors.primary,
                        AppColors.mint,
                      ],
                      begin: Alignment.bottomLeft,
                      end: Alignment.topRight,
                    ),
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
                    icon: const Icon(Icons.check_circle_outline, color: Colors.white),
                    label: Text(
                      'إضافة مهمة جديدة',
                      style: GoogleFonts.ibmPlexSansArabic(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    onPressed: () {
                      Navigator.pop(context);
                      _showTaskDialog(title: 'إضافة مهمة جديدة');
                    },
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // ✅ Gradient button: إضافة فئة جديدة
              SizedBox(
                width: double.infinity,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [
                        AppColors.mint,
                        AppColors.primary,
                      ],
                      begin: Alignment.bottomLeft,
                      end: Alignment.topRight,
                    ),
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
                    icon: const Icon(Icons.category_outlined, color: Colors.white),
                    label: Text(
                      'إضافة فئة جديدة',
                      style: GoogleFonts.ibmPlexSansArabic(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    onPressed: () {
                      Navigator.pop(context);
                      _showAddCategoryDialog();
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ============================
  // 🧩 Add Category Dialog (visual only)

  void _showAddCategoryDialog() {
    final formKey = GlobalKey<FormState>();
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    String? parentCategory;

    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => Builder(
        builder: (rootContext) {
          return Directionality(
            textDirection: TextDirection.rtl,
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 24 + 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                boxShadow: const [
                  BoxShadow(color: Color(0x33000000), blurRadius: 10, offset: Offset(0, 4)),
                ],
              ),
              child: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Text('إضافة فئة جديدة',
                            style: GoogleFonts.ibmPlexSansArabic(
                              fontWeight: FontWeight.w800,
                              fontSize: 18,
                              color: AppColors.dark,
                            )),
                      ),
                      const SizedBox(height: 18),

                      _fieldLabel('اسم الفئة', required: true),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: nameCtrl,
                        decoration: const InputDecoration(
                          hintText: 'مثال: النقل المستدام',
                          prefixIcon: Icon(Icons.category_outlined),
                        ),
                        validator: (v) => (v == null || v.isEmpty)
                            ? 'أدخل اسم الفئة'
                            : null,
                      ),
                      const SizedBox(height: 14),

                      _fieldLabel('الفئة الرئيسية', required: true),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(
                          border: Border.all(color: AppColors.light.withOpacity(.7)),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: parentCategory,
                            isExpanded: true,
                            hint: const Text('اختر الفئة الرئيسية'),
                            items: const [
                              DropdownMenuItem(value: 'سلوك مباشر', child: Text('سلوك مباشر')),
                              DropdownMenuItem(value: 'سلوك غير مباشر', child: Text('سلوك غير مباشر')),
                            ],
                            onChanged: (v) => parentCategory = v,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),

                      _fieldLabel('وصف الفئة'),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: descCtrl,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          hintText: 'اكتب وصفًا موجزًا للفئة...',
                          prefixIcon: Icon(Icons.description_outlined),
                        ),
                      ),
                      const SizedBox(height: 20),

                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.save, color: Colors.white),
                          label: Text('حفظ الفئة',
                              style: GoogleFonts.ibmPlexSansArabic(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
                          ),
                          onPressed: () async {
                            if (!(formKey.currentState?.validate() ?? false)) return;

                            try {
                              final newName = nameCtrl.text
                                  .trim()
                                  .replaceAll(RegExp(r'\s+'), ' ')
                                  .toLowerCase();

                              final existing = await FirebaseFirestore.instance
                                  .collection('categories')
                                  .where('name_normalized', isEqualTo: newName)
                                  .limit(1)
                                  .get();

                              if (existing.docs.isNotEmpty) {
                                ScaffoldMessenger.of(rootContext).showSnackBar(SnackBar(
                                  backgroundColor: Colors.redAccent,
                                  behavior: SnackBarBehavior.floating,
                                  content: Text(
                                    'اسم الفئة "${nameCtrl.text.trim()}" مستخدم بالفعل، يرجى اختيار اسم آخر',
                                    style: GoogleFonts.ibmPlexSansArabic(
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white),
                                  ),
                                ));
                                return;
                              }

                              await FirebaseFirestore.instance.collection('categories').add({
                                'name': nameCtrl.text.trim(),
                                'name_normalized': newName,
                                'parent': parentCategory,
                                'description': descCtrl.text.trim(),
                                'createdAt': FieldValue.serverTimestamp(),
                              });

                              if (mounted) {
                                Navigator.pop(rootContext);
                                _loadCategories();
                                ScaffoldMessenger.of(rootContext).showSnackBar(SnackBar(
                                  backgroundColor: Colors.green,
                                  behavior: SnackBarBehavior.floating,
                                  content: Text('تمت إضافة الفئة بنجاح ✅',
                                      style: GoogleFonts.ibmPlexSansArabic(
                                          fontWeight: FontWeight.w700,
                                          color: Colors.white)),
                                ));
                              }
                            } catch (e) {
                              debugPrint('❌ خطأ أثناء حفظ الفئة: $e');
                            }
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
    );
  }
}
