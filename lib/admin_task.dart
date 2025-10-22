import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'widgets/admin_bottom_nav.dart';
import 'admin_home.dart';
import 'admin_reward.dart';
import 'admin_map.dart';
import 'widgets/background_container.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:ui';

/// ---------------------------------------------------------------------------
///  Admin Tasks Management Page
///  Handles viewing, adding, editing, deleting, and filtering sustainability
///  tasks and categories within the Nameer admin dashboard.
///  NOTE: This refactor preserves logic and data flow; changes are cosmetic
///  (naming, structure, documentation, and UI code style) for maintainability. 
/// ---------------------------------------------------------------------------
class AdminTasksPage extends StatefulWidget {
  const AdminTasksPage({super.key});

  @override
  State<AdminTasksPage> createState() => _AdminTasksPageState();
}

class _AdminTasksPageState extends State<AdminTasksPage> {
  // ---------------------------------------------------------------------------
  // 🔹 Data Sources
  final CollectionReference _taskCollection =
      FirebaseFirestore.instance.collection('tasks');

  // ---------------------------------------------------------------------------
  // 🔹 State Variables
  List<Map<String, dynamic>> _tasks = [];
  List<String> _categories = [];
  Set<String> _selectedCategories = {};
  final Set<int> _expandedIndexes = {};

  bool _isLoading = true;
  bool _isCatsLoading = true;
  String searchQuery = '';
  bool _hasSchedule = false;
  DateTime? _scheduleDate;

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
  // 🔹 Firestore Fetch Methods

  /// Fetch all tasks from Firestore, auto-deactivate expired ones.
  Future<void> _fetchTasks() async {
    try {
      final querySnapshot = await _taskCollection.get();
      final now = DateTime.now();

      for (final doc in querySnapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;

        final hasSchedule = data['hasSchedule'] == true;
        final scheduleDate = (data['scheduleDate'] as Timestamp?)?.toDate();
        final hasExpiry = data['hasExpiry'] == true;
        final expiryDate = (data['expiryDate'] as Timestamp?)?.toDate();
        final isActive = data['isActive'] == true;

        // --- Auto Activate when schedule time arrives ---
        if (hasSchedule && scheduleDate != null && scheduleDate.isBefore(now) && !isActive) {
          await _taskCollection.doc(doc.id).update({
            'isActive': true,
            'hasSchedule': false, // mark schedule complete
          });
          data['isActive'] = true;
        }

        // --- Auto Deactivate when expired ---
        if (hasExpiry && expiryDate != null && expiryDate.isBefore(now) && isActive) {
          await _taskCollection.doc(doc.id).update({
            'isActive': false,
          });
          data['isActive'] = false;
        }
      }

      setState(() {
        _tasks = querySnapshot.docs.map((doc) {
          final data = doc.data() as Map<String, dynamic>;
          data['id'] = doc.id;
          return data;
        }).toList()
          ..sort((a, b) {
            if (a['isActive'] == b['isActive']) return 0;
            return a['isActive'] == true ? -1 : 1; // active first
          });
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading tasks: $e');
      setState(() => _isLoading = false);
    }
  }


  /// Fetch all available categories from Firestore.
  Future<void> _fetchCategories() async {
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
  // 🔹 Task Status Helper
  // ---------------------------------------------------------------------------

  /// Returns a localized Arabic status string based on task state.
  /// Logic:
  /// - غير مفعّلة → if isActive == false
  /// - منتهية → if task has expiry date and it's before today
  /// - نشطة → otherwise (active and not expired)
  String _getTaskStatus(Map<String, dynamic> task) {
    final isActive = task['isActive'] == true;
    final hasExpiry = task['hasExpiry'] == true;
    final expiryDate = (task['expiryDate'] as Timestamp?)?.toDate();

    if (!isActive) return 'غير مفعّلة';
    if (hasExpiry && expiryDate != null && expiryDate.isBefore(DateTime.now())) {
      return 'منتهية';
    }
    return 'نشطة';
  }

  // ---------------------------------------------------------------------------
  // 🔹 Main UI Build
  @override
  Widget build(BuildContext context) {
    final isKeyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;
    final theme = Theme.of(context);
    final textTheme = GoogleFonts.ibmPlexSansArabicTextTheme(theme.textTheme);

    final query = searchQuery.trim().toLowerCase();

    // Filter and sort tasks (active first)
    final filteredTasks = _tasks
        .where((task) {
          final title = task['title']?.toString().toLowerCase() ?? '';
          final desc = task['description']?.toString().toLowerCase() ?? '';
          final cat = task['category']?.toString() ?? '';
          final matchesSearch =
              query.isEmpty || title.contains(query) || desc.contains(query);
          final matchesCategory =
              _selectedCategories.isEmpty || _selectedCategories.contains(cat);
          return matchesSearch && matchesCategory;
        })
        .toList()
      ..sort((a, b) {
        if (a['isActive'] == b['isActive']) return 0;
        return a['isActive'] == true ? -1 : 1;
      });

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Theme(
        data: theme.copyWith(textTheme: textTheme),
        child: Scaffold(
          extendBody: true,
          backgroundColor: Colors.transparent,
          appBar: _buildAppBar(),
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
          floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
          floatingActionButton: _buildAddFab(),
          bottomNavigationBar: isKeyboardOpen
              ? null
              : AdminBottomNav(currentIndex: _currentIndex, onTap: _onBottomNavTap),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 🔹 AppBar
  AppBar _buildAppBar() {
    return AppBar(
      automaticallyImplyLeading: false,
      centerTitle: true,
      title: Text(
        'قائمة المهام',
            style: GoogleFonts.ibmPlexSansArabic(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
      ),
      flexibleSpace: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppColors.primary,
              AppColors.primary,
              AppColors.mint,
            ],
            stops: [0.0, 0.5, 1.0],
            begin: Alignment.bottomLeft,
            end: Alignment.topRight,
          ),
        ),
      ),
    );
  }


  // ---------------------------------------------------------------------------
  // 🔹 UI Components

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
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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
      child: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: _fetchTasks,
        child: ListView.builder(
          padding: const EdgeInsets.only(bottom: 200), // increase from 120 → 200
          itemCount: tasks.length + 1, // add 1 for the extra space
          itemBuilder: (context, index) {
            if (index == tasks.length) {
              // extra invisible space at bottom
              return const SizedBox(height: 80);
            }

            final task = tasks[index];
            final isExpanded = _expandedIndexes.contains(index);
            return _buildTaskCard(task, index, isExpanded);
          },
        ),
      ),
    );
  }
  

  // Widget _buildTaskCard(Map<String, dynamic> task, int index, bool isExpanded) {
  //   return AnimatedContainer(
  //     duration: const Duration(milliseconds: 200),
  //     margin: const EdgeInsets.symmetric(vertical: 6),
  //     decoration: BoxDecoration(
  //       color: Colors.white,
  //       borderRadius: BorderRadius.circular(16),
  //       border: Border.all(color: Colors.grey.shade200, width: 1.2),
  //       boxShadow: [
  //         BoxShadow(
  //           color: Colors.black.withOpacity(0.12),
  //           blurRadius: 5,
  //           spreadRadius: 2,
  //           offset: const Offset(0, 1),
  //         ),
  //       ],
  //     ),
  //     child: Column(
  //       children: [
  //         ListTile(
  //           contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
  //           title: Text(
  //             task['title'] ?? 'بدون عنوان',
  //             style: const TextStyle(
  //               fontSize: 16,
  //               fontWeight: FontWeight.w600,
  //               color: Color(0xFF333333),
  //             ),
  //           ),
  //           subtitle: Padding(
  //             padding: const EdgeInsets.only(top: 4),
  //             child: Row(
  //               children: [
  //                 const Icon(Icons.category_outlined, size: 16, color: AppColors.dark),
  //                 const SizedBox(width: 6),
  //                 Text(
  //                   task['category'] ?? 'غير مصنف',
  //                   style: const TextStyle(
  //                     fontSize: 13,
  //                     color: Color(0xFF666666),
  //                     fontWeight: FontWeight.w600,
  //                   ),
  //                 ),
  //               ],
  //             ),
  //           ),
  //           trailing: Row(
  //             mainAxisSize: MainAxisSize.min,
  //             children: [
  //               Icon(
  //                 isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
  //                 color: AppColors.primary,
  //               ),
  //               const SizedBox(width: 6),
  //               Container(
  //                 width: 10,
  //                 height: 10,
  //                 decoration: BoxDecoration(
  //                   color: (task['isActive'] == true)
  //                       ? Colors.green
  //                       : Colors.grey.shade400,
  //                   shape: BoxShape.circle,
  //                 ),
  //               ),
  //             ],
  //           ),
  //           onTap: () {
  //             setState(() {
  //               isExpanded
  //                   ? _expandedIndexes.remove(index)
  //                   : _expandedIndexes.add(index);
  //             });
  //           },
  //         ),
  //         if (isExpanded) _buildExpandedTaskContent(task),
  //       ],
  //     ),
  //   );
  // }

  
// ---------------------------------------------------------------------------
// 🔹 Task Card Builder (Compact + Expandable with Status Label)
// ---------------------------------------------------------------------------

/// Builds an animated task card with title, category, and expansion.
/// The card also shows:
/// - Status label (top-left): نشطة / منتهية / غير مفعّلة
/// - Expansion toggle to reveal task description & action buttons
Widget _buildTaskCard(Map<String, dynamic> task, int index, bool isExpanded) {
  // --- Determine the status text and color ---
  final statusText = _getTaskStatus(task);
  Color statusColor;
  switch (statusText) {
    case 'نشطة':
      statusColor = Colors.green;
      break;
    case 'منتهية':
      statusColor = Colors.redAccent;
      break;
    default:
      statusColor = Colors.grey;
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
          color: Colors.black.withOpacity(0.12),
          blurRadius: 5,
          spreadRadius: 2,
          offset: const Offset(0, 1),
        ),
      ],
    ),

    // --- Stack allows status label overlay (top-left) ---
    child: Stack(
      children: [
        // --- Main Card Content ---
        Column(
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
                  isExpanded
                      ? _expandedIndexes.remove(index)
                      : _expandedIndexes.add(index);
                });
              },
            ),
            if (isExpanded) _buildExpandedTaskContent(task),
          ],
        ),

        // --- Status Label (Top-Left Corner) ---
        Positioned(
          top: 8,  // move slightly down
          left: 12, // move slightly inward
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), // reduced padding
            constraints: const BoxConstraints(minWidth: 50, minHeight: 24), // keeps shape consistent
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.08),
              border: Border.all(color: statusColor, width: 1),
              borderRadius: BorderRadius.circular(8), // smaller radius
            ),
            child: Center(
              child: Text(
                statusText,
                style: GoogleFonts.ibmPlexSansArabic(
                  fontWeight: FontWeight.w700,
                  fontSize: 11, // smaller text
                  color: statusColor,
                ),
                textAlign: TextAlign.center,
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
            style: const TextStyle(fontSize: 14, color: Color(0xFF555555)),
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
          const SizedBox(height: 8),
          Text(
            'إستراتيجية التحقق: ${task['validationStrategy'] ?? 'غير محددة'}',
            style: const TextStyle(fontSize: 13, color: Color(0xFF666666)),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
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

  // ---------------------------------------------------------------------------
  // 🔹 Floating Action Button
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

  // ==========================================================================
  // 🔸 Dialogs and Sheets
  // ==========================================================================

  // 🗑 Delete Confirmation Dialog
  void _showDeleteDialog(Map<String, dynamic> task) {
    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black26,
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (_, __, ___) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
          child: Center(
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: MediaQuery.of(context).size.width * 0.85,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 25),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: const [
                    BoxShadow(color: Color(0x33000000), blurRadius: 10, offset: Offset(0, 4)),
                  ],
                ),
                child: Directionality(
                  textDirection: TextDirection.rtl,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 48),
                      const SizedBox(height: 10),
                      Text(
                        'تأكيد الحذف',
                        style: GoogleFonts.ibmPlexSansArabic(
                          fontWeight: FontWeight.w800,
                          fontSize: 20,
                          color: AppColors.dark,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'هل أنت متأكد من حذف هذه المهمة؟',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.ibmPlexSansArabic(fontSize: 15, color: Colors.black87),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.delete_outline, color: Colors.white),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          minimumSize: const Size(double.infinity, 48),
                        ),
                        onPressed: () async {
                          try {
                            await _taskCollection.doc(task['id']).delete();
                            Navigator.pop(context);
                            _fetchTasks();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'تم حذف المهمة بنجاح 🗑️',
                                  style: GoogleFonts.ibmPlexSansArabic(fontWeight: FontWeight.w700),
                                ),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          } catch (e) {
                            debugPrint('Error deleting task: $e');
                          }
                        },
                        label: Text(
                          'تأكيد الحذف',
                          style: GoogleFonts.ibmPlexSansArabic(color: Colors.white, fontWeight: FontWeight.w800),
                        ),
                      ),
                      const SizedBox(height: 10),
                      _buildCancelButton(context),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (_, anim1, __, child) =>
          FadeTransition(opacity: anim1, child: ScaleTransition(
            scale: CurvedAnimation(parent: anim1, curve: Curves.easeOutBack),
            child: child,
          )),
    );
  }

  // 🧮 Filters Sheet
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
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('تصفية المهام حسب الفئة',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _categories.map((cat) {
                      final selected = selectedLocal.contains(cat);
                      return FilterChip(
                        label: Text(cat),
                        selected: selected,
                        onSelected: (v) => setSt(() =>
                            v ? selectedLocal.add(cat) : selectedLocal.remove(cat)),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        minimumSize: const Size(double.infinity, 48)),
                    onPressed: () {
                      Navigator.pop(context);
                      setState(() => _selectedCategories = selectedLocal);
                    },
                    child: const Text('تطبيق'),
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

  // 🧩 Add Options (Task / Category)
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
              BoxShadow(color: Color(0x33000000), blurRadius: 10, offset: Offset(0, 4)),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('إضافة عنصر جديد',
                  style: GoogleFonts.ibmPlexSansArabic(
                    color: AppColors.dark,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  )),
              const SizedBox(height: 20),

              // ✅ Go to AddTaskPage
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

              // ✅ Go to AddCategoryPage (will add later)
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

  // ==========================================================================
  // 🔹 Helper Widgets & Builders
  // ==========================================================================

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
                      style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w900),
                    ),
                  ]
                : [],
          ),
        ),
      );

  Widget _buildCancelButton(BuildContext context) => OutlinedButton(
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: Colors.redAccent, width: 1.4),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          padding: const EdgeInsets.symmetric(vertical: 14),
          minimumSize: const Size(double.infinity, 48),
        ),
        onPressed: () => Navigator.pop(context),
        child: Text('إلغاء',
            style: GoogleFonts.ibmPlexSansArabic(
              color: Colors.redAccent,
              fontWeight: FontWeight.w700,
            )),
      );

  Widget _gradientActionButton({
    required IconData icon,
    required String label,
    required List<Color> colors,
    required VoidCallback onTap,
  }) =>
      Container(
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
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          icon: Icon(icon, color: Colors.white),
          label: Text(label,
              style: GoogleFonts.ibmPlexSansArabic(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              )),
          onPressed: onTap,
        ),
      );

  // ---- Category dropdown (with validation) ----
  Widget _buildCategoryDropdown({
    required String? selectedValue,
    required ValueChanged<String?> onChanged,
  }) {
    return FormField<String>(
      validator: (_) {
        if (selectedValue == null || selectedValue!.isEmpty) {
          return 'اختر تصنيف المهمة';
        }
        return null;
      },
      builder: (state) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _fieldLabel('تصنيف المهمة', required: true),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                border: Border.all(
                  color: state.hasError
                      ? Colors.redAccent
                      : AppColors.light.withOpacity(0.7),
                  width: 1.4,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: selectedValue,
                  isExpanded: true,
                  hint: _isCatsLoading
                      ? const Text('...يتم تحميل الفئات')
                      : const Text('اختر الفئة'),
                  items: _categories
                      .map((name) => DropdownMenuItem(value: name, child: Text(name)))
                      .toList(),
                  onChanged: (v) {
                    onChanged(v);
                    state.didChange(v);
                  },
                ),
              ),
            ),
            if (state.hasError)
              Padding(
                padding: const EdgeInsets.only(top: 6, right: 4),
                child: Text(
                  state.errorText!,
                  style: const TextStyle(
                    color: Colors.redAccent,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  // ---- Expiry selector (radio + optional date picker) ----
  // Widget _buildExpirySelector({
  //   required bool hasExpiry,
  //   required DateTime? expiryDate,
  //   required ValueChanged<bool> onToggle,
  //   required ValueChanged<DateTime?> onPickDate,
  // }) {
  //   return FormField<bool>(
  //     validator: (_) {
  //       if (hasExpiry && expiryDate == null) {
  //         return 'يرجى اختيار تاريخ انتهاء المهمة';
  //       }
  //       return null;
  //     },
  //     builder: (state) {
  //       return Column(
  //         crossAxisAlignment: CrossAxisAlignment.start,
  //         children: [
  //           _fieldLabel('صلاحية المهمة', required: true),
  //           const SizedBox(height: 8),
  //           Container(
  //             decoration: BoxDecoration(
  //               color: Colors.transparent,
  //               border: Border.all(
  //                 color: state.hasError
  //                     ? Colors.redAccent
  //                     : AppColors.light.withOpacity(0.7),
  //                 width: 1.4,
  //               ),
  //               borderRadius: BorderRadius.circular(12),
  //             ),
  //             child: Column(
  //               children: [
  //                 RadioListTile<bool>(
  //                   value: false,
  //                   groupValue: hasExpiry,
  //                   activeColor: AppColors.primary,
  //                   title: const Text('بدون تاريخ انتهاء'),
  //                   onChanged: (v) {
  //                     onToggle(v ?? false);
  //                     onPickDate(null);
  //                     state.didChange(v);
  //                   },
  //                 ),
  //                 const Divider(height: 0),
  //                 RadioListTile<bool>(
  //                   value: true,
  //                   groupValue: hasExpiry,
  //                   activeColor: AppColors.primary,
  //                   title: const Text('تاريخ انتهاء محدد'),
  //                   onChanged: (v) {
  //                     onToggle(v ?? true);
  //                     if (expiryDate == null) {
  //                       onPickDate(DateTime.now().add(const Duration(days: 7)));
  //                     }
  //                     state.didChange(v);
  //                   },
  //                 ),
  //               ],
  //             ),
  //           ),
  //           const SizedBox(height: 12),
  //           if (hasExpiry)
  //             InkWell(
  //               onTap: () async {
  //                 final picked = await showDatePicker(
  //                   context: context,
  //                   initialDate: expiryDate ?? DateTime.now().add(const Duration(days: 7)),
  //                   firstDate: DateTime.now(),
  //                   lastDate: DateTime(2030),
  //                   builder: (context, child) => Directionality(
  //                     textDirection: TextDirection.rtl,
  //                     child: Theme(
  //                       data: Theme.of(context).copyWith(
  //                         colorScheme: const ColorScheme.light(
  //                           primary: AppColors.primary,
  //                           onPrimary: Colors.white,
  //                           onSurface: AppColors.dark,
  //                         ),
  //                       ),
  //                       child: child!,
  //                     ),
  //                   ),
  //                 );
  //                 if (picked != null) {
  //                   onPickDate(picked);
  //                   state.validate();
  //                 }
  //               },
  //               borderRadius: BorderRadius.circular(12),
  //               child: Container(
  //                 padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
  //                 decoration: BoxDecoration(
  //                   border: Border.all(
  //                     color: state.hasError
  //                         ? Colors.redAccent
  //                         : AppColors.light.withOpacity(0.7),
  //                     width: 1.4,
  //                   ),
  //                   borderRadius: BorderRadius.circular(12),
  //                 ),
  //                 child: Row(
  //                   mainAxisAlignment: MainAxisAlignment.spaceBetween,
  //                   children: [
  //                     Text(
  //                       expiryDate == null
  //                           ? 'اختر تاريخ الانتهاء'
  //                           : 'تاريخ الانتهاء: ${expiryDate!.day}-${expiryDate!.month}-${expiryDate!.year}',
  //                       style: GoogleFonts.ibmPlexSansArabic(
  //                         color: AppColors.dark,
  //                         fontWeight: FontWeight.w700,
  //                       ),
  //                     ),
  //                     const Icon(Icons.calendar_today, color: AppColors.primary, size: 20),
  //                   ],
  //                 ),
  //               ),
  //             ),
  //           if (state.hasError)
  //             Padding(
  //               padding: const EdgeInsets.only(top: 6, right: 4),
  //               child: Text(
  //                 state.errorText!,
  //                 style: const TextStyle(
  //                   color: Colors.redAccent,
  //                   fontSize: 12,
  //                   fontWeight: FontWeight.w600,
  //                 ),
  //               ),
  //             ),
  //         ],
  //       );
  //     },
  //   );
  // }

  // ---- Save button builder (creates/updates task in Firestore) ----
  Widget _buildSaveButton({
    required BuildContext rootContext,
    required GlobalKey<FormState> formKey,
    required TextEditingController titleCtrl,
    required TextEditingController descCtrl,
    required TextEditingController pointsCtrl,
    required String? selectedCategory,
    required String? validationType,
    required bool hasExpiry,
    required DateTime? expiryDate,
    required bool isActive,
    required Map<String, dynamic>? task,
  }) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        icon: const Icon(Icons.save, color: Colors.white),
        label: Text(
          'حفظ التغييرات',
          style: GoogleFonts.ibmPlexSansArabic(
            color: Colors.white,
            fontWeight: FontWeight.w800,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
        ),
        onPressed: () async {
          final form = formKey.currentState!;
          if (!form.validate()) {
            setState(() {}); // show red borders
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
                ScaffoldMessenger.of(rootContext).showSnackBar(
                  SnackBar(
                    backgroundColor: Colors.redAccent,
                    behavior: SnackBarBehavior.floating,
                    content: Text(
                      'اسم المهمة "${titleCtrl.text.trim()}" مستخدم بالفعل، يرجى اختيار اسم آخر',
                      style: GoogleFonts.ibmPlexSansArabic(
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                );
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
              _fetchTasks();
              ScaffoldMessenger.of(rootContext).showSnackBar(
                SnackBar(
                  backgroundColor: Colors.green,
                  behavior: SnackBarBehavior.floating,
                  content: Text(
                    'تم الحفظ بنجاح ✅',
                    style: GoogleFonts.ibmPlexSansArabic(
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              );
            }
          } catch (e) {
            debugPrint('Error saving task: $e');
          }
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 🟩 Add / Edit Task Page
// ---------------------------------------------------------------------------
// 🟩 Add / Edit Task Page (Fixed & Complete)
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

  // ---- Expiry ----
  bool _hasExpiry = false;
  DateTime? _expiryDate;

  // ---- Scheduling / Activation ----
  String _startMode = 'now'; // 'now' or 'scheduled'
  DateTime? _startDate;

  bool _isActive = false;

  String? _selectedCategory;

  bool _isDirty = false;

  final CollectionReference _tasks =
      FirebaseFirestore.instance.collection('tasks');
  final CollectionReference _categoriesCol =
      FirebaseFirestore.instance.collection('categories');

  List<String> _categories = [];
  bool _catsLoading = true;

  @override
  void initState() {
    super.initState();
    _wireDirtyListeners();
    _loadCategories();
    _prefillIfEditing();
  }

  void _wireDirtyListeners() {
    for (final c in [_titleCtrl, _descCtrl, _pointsCtrl]) {
      c.addListener(() => _isDirty = true);
    }
  }

  Future<void> _loadCategories() async {
    final qs = await _categoriesCol.get();
    setState(() {
      _categories = qs.docs
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

    _titleCtrl.text = t['title'] ?? '';
    _descCtrl.text = t['description'] ?? '';
    _pointsCtrl.text = t['points']?.toString() ?? '';
    _selectedCategory = t['category'];

    // Scheduling
    final hasSchedule = t['hasSchedule'] ?? false;
    _startMode = hasSchedule ? 'scheduled' : 'now';
    _startDate = (t['scheduleDate'] as Timestamp?)?.toDate();

    // Expiry
    _hasExpiry = t['hasExpiry'] ?? false;
    _expiryDate = (t['expiryDate'] as Timestamp?)?.toDate();

    _isActive = t['isActive'] ?? false;
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
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 25),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: const [
                    BoxShadow(color: Color(0x33000000), blurRadius: 10, offset: Offset(0, 4)),
                  ],
                ),
                child: Directionality(
                  textDirection: TextDirection.rtl,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 48),
                      const SizedBox(height: 10),
                      Text('تأكيد الخروج',
                          style: GoogleFonts.ibmPlexSansArabic(
                              fontWeight: FontWeight.w800,
                              fontSize: 20,
                              color: AppColors.dark)),
                      const SizedBox(height: 8),
                      Text('هل أنت متأكد من العودة دون حفظ التغييرات؟',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.ibmPlexSansArabic(fontSize: 15, color: Colors.black87)),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.exit_to_app, color: Colors.white),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            minimumSize: const Size(double.infinity, 48)),
                        onPressed: () {
                          shouldLeave = true;
                          Navigator.pop(context);
                        },
                        label: Text('تأكيد الخروج',
                            style: GoogleFonts.ibmPlexSansArabic(
                                color: Colors.white, fontWeight: FontWeight.w800)),
                      ),
                      const SizedBox(height: 10),
                      _buildRedCancelButton(onPressed: () => Navigator.pop(context)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (_, anim1, __, child) => FadeTransition(
        opacity: anim1,
        child: ScaleTransition(
          scale: CurvedAnimation(parent: anim1, curve: Curves.easeOutBack),
          child: child,
        ),
      ),
    );

    return shouldLeave;
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.task != null;
    final titleText = isEdit ? 'تعديل المهمة' : 'إضافة مهمة جديدة';

    return PopScope(
      canPop: false,
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          appBar: AppBar(
            automaticallyImplyLeading: false,
            centerTitle: true,
            title: Text(
              titleText,
              style: GoogleFonts.ibmPlexSansArabic(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: AppColors.dark),
              onPressed: () async {
                if (await _confirmLeaveIfDirty()) Navigator.pop(context, false);
              },
            ),
            flexibleSpace: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppColors.primary, AppColors.primary, AppColors.mint],
                  begin: Alignment.bottomLeft,
                  end: Alignment.topRight,
                ),
              ),
            ),
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
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
                      hintText: 'مثال: إعادة تدوير الورق',
                      prefixIcon: Icon(Icons.task_alt_outlined),
                    ),
                    validator: (v) =>
                        (v == null || v.isEmpty) ? 'أدخل عنوان المهمة' : null,
                    onChanged: (_) => _isDirty = true,
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
                    onChanged: (_) => _isDirty = true,
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
                      if (n == null || n <= 0) return 'أدخل عددًا صحيحًا موجبًا';
                      return null;
                    },
                    onChanged: (_) => _isDirty = true,
                  ),
                  const SizedBox(height: 14),

                  _fieldLabel('تصنيف المهمة', required: true),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: _selectedCategory,
                    isExpanded: true,
                    decoration: InputDecoration(
                      hintText: _catsLoading ? '...يتم تحميل الفئات' : 'اختر الفئة',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    items: _categories
                        .map((name) =>
                            DropdownMenuItem(value: name, child: Text(name)))
                        .toList(),
                    onChanged: (v) {
                      setState(() => _selectedCategory = v);
                      _isDirty = true;
                    },
                    validator: (v) =>
                        (v == null || v.isEmpty) ? 'اختر تصنيف المهمة' : null,
                  ),
                  const SizedBox(height: 20),

                  _fieldLabel('تفعيل وجدولة المهمة', required: true),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.light.withOpacity(0.7)),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        RadioListTile<String>(
                          value: 'now',
                          groupValue: _startMode,
                          activeColor: AppColors.primary,
                          title: const Text('تفعيل المهمة الآن'),
                          onChanged: (v) {
                            setState(() {
                              _startMode = v!;
                              _startDate = null;
                              _isDirty = true;
                            });
                          },
                        ),
                        const Divider(height: 0),
                        RadioListTile<String>(
                          value: 'scheduled',
                          groupValue: _startMode,
                          activeColor: AppColors.primary,
                          title: const Text('تحديد تاريخ بداية'),
                          onChanged: (v) {
                            setState(() {
                              _startMode = v!;
                              _isDirty = true;
                            });
                          },
                        ),
                        if (_startMode == 'scheduled')
                          InkWell(
                            onTap: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: _startDate ?? DateTime.now(),
                                firstDate: DateTime.now(),
                                lastDate: DateTime(2030),
                                builder: (context, child) =>
                                    Directionality(
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
                              if (picked != null) {
                                setState(() => _startDate = picked);
                                _isDirty = true;
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  vertical: 12, horizontal: 14),
                              margin: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 4),
                              decoration: BoxDecoration(
                                border: Border.all(
                                    color: AppColors.light.withOpacity(.7)),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    _startDate == null
                                        ? 'اختر تاريخ البداية'
                                        : 'تاريخ البداية: ${_startDate!.day}-${_startDate!.month}-${_startDate!.year}',
                                    style: GoogleFonts.ibmPlexSansArabic(
                                      color: AppColors.dark,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const Icon(Icons.calendar_today,
                                      color: AppColors.primary, size: 20),
                                ],
                              ),
                            ),
                          ),
                        const Divider(height: 0),
                        CheckboxListTile(
                          title: const Text('تحديد تاريخ انتهاء'),
                          value: _hasExpiry,
                          controlAffinity: ListTileControlAffinity.leading,
                          activeColor: AppColors.primary,
                          onChanged: (v) {
                            setState(() {
                              _hasExpiry = v ?? false;
                              if (!_hasExpiry) _expiryDate = null;
                              _isDirty = true;
                            });
                          },
                        ),
                        if (_hasExpiry)
                          InkWell(
                            onTap: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: _expiryDate ??
                                    DateTime.now().add(const Duration(days: 7)),
                                firstDate: DateTime.now(),
                                lastDate: DateTime(2030),
                                builder: (context, child) =>
                                    Directionality(
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
                              if (picked != null) {
                                setState(() => _expiryDate = picked);
                                _isDirty = true;
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  vertical: 12, horizontal: 14),
                              margin: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 4),
                              decoration: BoxDecoration(
                                border: Border.all(
                                    color: AppColors.light.withOpacity(.7)),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    _expiryDate == null
                                        ? 'اختر تاريخ الانتهاء'
                                        : 'تاريخ الانتهاء: ${_expiryDate!.day}-${_expiryDate!.month}-${_expiryDate!.year}',
                                    style: GoogleFonts.ibmPlexSansArabic(
                                      color: AppColors.dark,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const Icon(Icons.calendar_today,
                                      color: AppColors.primary, size: 20),
                                ],
                              ),
                            ),
                          ),
                        const SizedBox(height: 10),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),
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
          ),
        ),
      ),
    );
  }

  Future<void> _saveTask() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      setState(() {});
      return;
    }

    try {
      final data = {
        'title': _titleCtrl.text.trim(),
        'description': _descCtrl.text.trim(),
        'points': int.parse(_pointsCtrl.text),
        'category': _selectedCategory,
        'managedBy': 'nameer admin',

        // Scheduling fields
        'hasSchedule': _startMode == 'scheduled',
        'scheduleDate': _startMode == 'scheduled' && _startDate != null
            ? Timestamp.fromDate(_startDate!)
            : null,

        // Expiry
        'hasExpiry': _hasExpiry,
        'expiryDate': _hasExpiry && _expiryDate != null
            ? Timestamp.fromDate(_expiryDate!)
            : null,

        // Active now?
        'isActive': _startMode == 'now',

        'createdAt': FieldValue.serverTimestamp(),
      };

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
              widget.task == null
                  ? 'تمت إضافة المهمة بنجاح ✅'
                  : 'تم تحديث المهمة بنجاح ✅',
              style: GoogleFonts.ibmPlexSansArabic(
                  color: Colors.white, fontWeight: FontWeight.w700),
            ),
          ),
        );
        _isDirty = false;
        Navigator.pop(context, true);
      }
    } catch (e) {
      debugPrint('Error saving task: $e');
    }
  }

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
                      style:
                          TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w900),
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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

  final CollectionReference _categoriesCol =
      FirebaseFirestore.instance.collection('categories');

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
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.exit_to_app, color: Colors.white),
                        label: Text(
                          'تأكيد الخروج',
                          style: GoogleFonts.ibmPlexSansArabic(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        onPressed: () {
                          shouldLeave = true;
                          Navigator.pop(context);
                        },
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
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          centerTitle: true,
          title: Text(
            titleText, // already defined above: isEdit ? 'إضافة فئة جديدة' : 'تعديل الفئة',
            style: GoogleFonts.ibmPlexSansArabic(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: AppColors.dark),
            onPressed: () async {
              if (await _confirmLeaveIfDirty()) {
                if (mounted) Navigator.pop(context, false);
              }
            },
            tooltip: 'رجوع',
          ),
          flexibleSpace: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.primary,
                  AppColors.primary,
                  AppColors.mint,
                ],
                stops: [0.0, 0.5, 1.0],
                begin: Alignment.bottomLeft,
                end: Alignment.topRight,
              ),
            ),
          ),
        ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
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
                    isExpanded: true,
                    decoration: const InputDecoration(
                      hintText: 'اختر الفئة الرئيسية',
                      prefixIcon: Icon(Icons.hub_outlined),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(12)),
                      ),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'سلوك مباشر', child: Text('سلوك مباشر')),
                      DropdownMenuItem(value: 'سلوك غير مباشر', child: Text('سلوك غير مباشر')),
                    ],
                    onChanged: (v) {
                      setState(() => _parent = v);
                      _isDirty = true;
                    },
                    validator: (v) =>
                        (v == null || v.isEmpty) ? 'اختر الفئة الرئيسية' : null,
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
                    onPressed: () {
                      Navigator.pop(context); // directly closes, no confirmation
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _saveCategory() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      setState(() {}); // show errors
      return;
    }
    try {
      final normalized =
          _nameCtrl.text.trim().replaceAll(RegExp(r'\\s+'), ' ').toLowerCase();

      if (widget.category == null) {
        // dup check
        final dup = await _categoriesCol
            .where('name_normalized', isEqualTo: normalized)
            .limit(1)
            .get();
        if (dup.docs.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: Colors.redAccent,
              behavior: SnackBarBehavior.floating,
              content: Text(
                'اسم الفئة "${_nameCtrl.text.trim()}" مستخدم بالفعل، يرجى اختيار اسم آخر',
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

  // Local helpers (same visuals)
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



