import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'admin_bottom_nav.dart';
import 'admin_home.dart';
import 'admin_reward.dart';
import 'admin_map.dart';
import 'dart:ui';

class AdminTasksPage extends StatefulWidget {
  const AdminTasksPage({super.key});

  @override
  State<AdminTasksPage> createState() => _AdminTasksPageState();
}

class _AdminTasksPageState extends State<AdminTasksPage> {
  int _currentIndex = 2;
  String searchQuery = '';

  final List<Map<String, dynamic>> _tasks = [
    // ♻️ إعادة التدوير
    {
      'title': 'إعادة تدوير الزجاجات',
      'description':
          'اجمع الزجاجات البلاستيكية الفارغة وضعها في أقرب حاوية إعادة تدوير معتمدة.',
      'points': 40,
      'icon': Icons.recycling,
      'validation': 'التحقق عبر معالجة الصور', // جديد
      'isActive': true,// جديد

    },
    {
      'title': 'إعادة تدوير الملابس',
      'description':
          'تبرّع بالملابس غير المستخدمة في صناديق التدوير داخل الجامعة أو الأحياء.',
      'points': 50,
      'icon': Icons.recycling,
      'validation': 'التحقق عبر معالجة الصور', // جديد
      'isActive': true,                           // جديد

    },
    {
      'title': 'إعادة تدوير الورق',
      'description':
          'اجمع الأوراق القديمة وضعها في حاويات إعادة التدوير المخصصة للورق.',
      'points': 30,
      'icon': Icons.recycling,
      'validation': 'التحقق عبر معالجة الصور', // جديد
      'isActive': true,                           // جديد

    },

    // 🚴 المواصلات
    {
      'title': 'استخدام الدراجة الهوائية',
      'description':
          'استخدم الدراجة للتنقل لمسافات قصيرة بدلاً من السيارة لتقليل الانبعاثات.',
      'points': 45,
      'icon': Icons.directions_bike_outlined,
      'validation': 'التحقق عبر معالجة الصور', // جديد
      'isActive': false,                           // جديد

    },

    // 🧑‍🎓 التعليم
    {
      'title': 'قراءة مقال توعوي',
      'description':
          'اقرأ مقالاً عن الاستدامة من مصادر موثوقة مثل المبادرة السعودية الخضراء.',
      'points': 20,
      'icon': Icons.school_outlined,
      'validation': 'التحقق عبر تتبع القراءة', // جديد
      'isActive': true,                           // جديد
    },
    {
      'title': 'متابعة أخبار البيئة',
      'description':
          'اطّلع على أحدث المبادرات البيئية في المملكة من خلال رؤية 2030 أو جرين الرياض.',
      'points': 25,
      'icon': Icons.school_outlined,
      'validation': 'التحقق عبر تتبع القراءة', // جديد
      'isActive': false,                           // جديد
    },
  ];

  final Set<int> _expandedIndexes = {};

  // ============================================================
  // 🔹 Navigation logic
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
    final textTheme = GoogleFonts.ibmPlexSansArabicTextTheme(
      baseTheme.textTheme,
    );

    final filteredTasks = _tasks
        .where((task) =>
            task['title'].toString().contains(searchQuery) ||
            task['description'].toString().contains(searchQuery))
        .toList()
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
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _buildSearchBar(),
                const SizedBox(height: 12),
                _buildTaskList(filteredTasks),
              ],
            ),
          ),

          // ---------------- ADD BUTTON ----------------
          floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
          floatingActionButton: Padding(
            padding: const EdgeInsets.only(right: 300, bottom: 10),
            child: FloatingActionButton(
              backgroundColor: AppColors.primary,
              shape: const CircleBorder(),
              onPressed: _showAddTaskDialog,
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
    return TextField(
      textAlign: TextAlign.right,
      decoration: InputDecoration(
        hintText: 'ابحث عن مهمة...',
        prefixIcon: const Icon(Icons.search, color: AppColors.primary),
        filled: true,
        fillColor: Colors.grey.shade100,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
      onChanged: (v) => setState(() => searchQuery = v),
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

              // ✅ Border stroke
              border: Border.all(
                color: Colors.grey.shade200,
                width: 1.2,
              ),
              // ✅ Enhanced shadow
              boxShadow: [ 
                BoxShadow(
                  color: Colors.black.withOpacity(0.12), // soft gray tone
                  blurRadius: 10,  // smoother, larger shadow
                  spreadRadius: 2, // more diffused
                  offset: const Offset(0, 1), // deeper drop
                ),
              ],
            ),
            child: Column(
              children: [
                ListTile(
                  leading: Container(
                    width: 40,
                    height: 40,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(0xFFE4F3ED), // ✅ Soft mint circle behind icon
                    ),
                    child: Icon(
                      task['icon'],
                      color: AppColors.primary,
                      size: 22,
                    ),
                  ),
                  title: Text(
                    task['title'],
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF333333),
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
          // الوصف
          Text(
            task['description'],
            style: const TextStyle(fontSize: 14, color: Color(0xFF555555)),
          ),
          const SizedBox(height: 8),

          // النقاط
          Text(
            'النقاط: ${task['points']}',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 8),

          // إستراتيجية التحقق
          Text(
            'إستراتيجية التحقق: ${task['validation'] ?? 'غير محددة'}',
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF666666),
            ),
          ),
          const SizedBox(height: 12),

          // أزرار التعديل والحذف
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              IconButton(
                icon: const Icon(Icons.edit, color: Colors.grey),
                onPressed: () => _showEditDialog(task),
              ),
              IconButton(
                icon: const Icon(Icons.delete, color: Colors.redAccent),
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
    final titleController =
        TextEditingController(text: task != null ? task['title'] : '');
    final descriptionController =
        TextEditingController(text: task != null ? task['description'] : '');
    final pointsController =
        TextEditingController(text: task != null ? task['points'].toString() : '');

    String? selectedValidationStrategy =
        task != null ? task['validation'] : null; // dropdown value
    bool isActive = task != null ? (task['isActive'] ?? false) : false; // new field
    String? errorMessage;

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: '',
      barrierColor: Colors.black26,
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (context, anim1, anim2) {
        return StatefulBuilder(
          builder: (context, setState) {
            return BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
              child: Center(
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    width: MediaQuery.of(context).size.width * 0.9,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black26,
                          blurRadius: 10,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // ===== Title =====
                          Center(
                            child: Text(
                              title,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 18,
                                color: Color(0xFF333333),
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),

                          // ===== Error message =====
                          if (errorMessage != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8.0),
                              child: Text(
                                errorMessage!,
                                style: const TextStyle(
                                    color: Colors.red, fontSize: 13),
                                textAlign: TextAlign.center,
                              ),
                            ),

                          // ===== Title field =====
                          _buildLabeledField(
                            label: 'عنوان المهمة',
                            controller: titleController,
                          ),
                          const SizedBox(height: 12),

                          // ===== Description field =====
                          _buildLabeledField(
                            label: 'وصف المهمة',
                            controller: descriptionController,
                            maxLines: 2,
                          ),
                          const SizedBox(height: 12),

                          // ===== Points field =====
                          _buildLabeledField(
                            label: 'النقاط',
                            controller: pointsController,
                            keyboardType: TextInputType.number,
                          ),
                          const SizedBox(height: 12),

                          // ===== Validation Strategy dropdown =====
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Text(
                              'إستراتيجية التحقق',
                              textAlign: TextAlign.right,
                              style: const TextStyle(fontSize: 14),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Directionality(
                          textDirection: TextDirection.rtl,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE4F3ED),
                              borderRadius: BorderRadius.circular(25),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: selectedValidationStrategy,
                                isExpanded: true,
                                alignment: Alignment.centerRight, // ← aligns selected value
                                hint: const Text(
                                  'اختر نوع التحقق',
                                  style: TextStyle(color: Colors.grey),
                                  textAlign: TextAlign.right,
                                ),
                                items: const [
                                  DropdownMenuItem(
                                    alignment: Alignment.centerRight, // ← aligns menu items
                                    value: 'التحقق عبر تتبع القراءة',
                                    child: Text('التحقق عبر تتبع القراءة'),
                                  ),
                                  DropdownMenuItem(
                                    alignment: Alignment.centerRight,
                                    value: 'التحقق عبر معالجة الصور',
                                    child: Text('التحقق عبر معالجة الصور'),
                                  ),
                                ],
                                onChanged: (value) {
                                  setState(() {
                                    selectedValidationStrategy = value;
                                  });
                                },
                              ),
                            ),
                          ),
                        ),

                          const SizedBox(height: 16),

                          // ===== Is Active checkbox =====
                          Directionality(
                            textDirection: TextDirection.rtl,
                            child: Row(
                              children: [
                                const Text(
                                  'هل المهمة مفعّلة؟',
                                  style: TextStyle(fontSize: 14),
                                ),
                                Checkbox(
                                  value: isActive,
                                  activeColor: AppColors.primary,
                                  onChanged: (val) {
                                    setState(() => isActive = val ?? false);
                                  },
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 20),

                          // ===== Save button =====
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(25),
                              ),
                              padding:
                                  const EdgeInsets.symmetric(vertical: 14),
                            ),
                            onPressed: () {
                              if (titleController.text.isEmpty ||
                                  descriptionController.text.isEmpty ||
                                  pointsController.text.isEmpty ||
                                  selectedValidationStrategy == null) {
                                setState(() {
                                  errorMessage =
                                      'يرجى تعبئة جميع الحقول الإلزامية.';
                                });
                              } else {
                                Navigator.pop(context);
                              }
                            },
                            child: const Text(
                              'حفظ التغييرات',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600),
                            ),
                          ),
                          const SizedBox(height: 10),

                          // ===== Cancel button =====
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.redAccent,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(25),
                              ),
                              padding:
                                  const EdgeInsets.symmetric(vertical: 14),
                            ),
                            onPressed: () => Navigator.pop(context),
                            child: const Text(
                              'إلغاء الأمر',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600),
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
        );
      },
      transitionBuilder: (context, anim1, anim2, child) {
        return FadeTransition(
          opacity: anim1,
          child: ScaleTransition(
            scale: CurvedAnimation(
              parent: anim1,
              curve: Curves.easeOutBack,
            ),
            child: child,
          ),
        );
      },
    );
  }

  Widget _buildLabeledField({
    required String label,
    required TextEditingController controller,
    int maxLines = 1,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Text(
            label,
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 14),
          ),
        ),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          textAlign: TextAlign.right,
          maxLines: maxLines,
          keyboardType: keyboardType,
          decoration: InputDecoration(
            filled: true,
            fillColor: const Color(0xFFE4F3ED),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(25),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ],
    );
  }

  void _showDeleteDialog(Map<String, dynamic> task) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 25,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 10,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      color: Colors.redAccent,
                      size: 48,
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'تأكيد الحذف',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        color: Color(0xFF333333),
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'هل أنت متأكد من حذف هذه المهمة؟',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 15, color: Colors.black87),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(25),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        minimumSize: const Size(double.infinity, 40),
                      ),
                      onPressed: () => Navigator.pop(context),
                      child: const Text(
                        'تأكيد الحذف',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(25),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        minimumSize: const Size(double.infinity, 40),
                      ),
                      onPressed: () => Navigator.pop(context),
                      child: const Text(
                        'إلغاء',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
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
}
