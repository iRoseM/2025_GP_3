import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';

import 'services/connection.dart';
import 'services/fcm_service.dart';
import 'services/admin_bottom_nav.dart';
import 'admin_task.dart';
import 'admin_reward.dart' as reward;
import 'admin_map.dart';
import 'profile.dart';
import 'services/background_container.dart';
import 'services/title_header.dart';
import 'admin_task_check.dart';
import '../services/app_colors.dart';
import 'admin_task_reports.dart';
import 'admin_task_reports.dart'
    as taskReports; // للكلاسات العامة في ملف البلاغات
import 'admin_reports.dart'
    as containerReports; // للكلاسات العامة في ملف بلاغات الحاويات

class AdminHomePage extends StatefulWidget {
  const AdminHomePage({super.key});
  @override
  State<AdminHomePage> createState() => _AdminHomePageState();
}

class _AdminHomePageState extends State<AdminHomePage> {
  int _currentIndex = 3;
  Timer? _refreshTimer;
  String _selectedTimeRange = 'اليوم';

  List<String> _timeRanges = ['اليوم', 'أسبوع', 'شهر', 'سنة'];

  List<FlSpot> _userGrowthSpots = [];
  List<FlSpot> _taskCompletionSpots = [];
  List<FlSpot> _pointsSpots = [];
  List<FlSpot> _carbonSpots = [];
  DateTime _cursorDate = DateTime.now();
  bool _isCarbonExpanded = false;
  List<Map<String, dynamic>> _topUsers = [];
  List<BarChartGroupData> _taskBarGroups = [];
  Map<String, Color> _categoryColors = {};
  Map<String, String> _categoryNames = {};
  Set<String> _uniqueCategories = {};
  Map<int, Map<String, dynamic>> _barCategoriesInfo =
      {}; // لتخزين معلومات كل شريط
  bool _isLoadingTopUsers = false;
  int _selectedQuickIconIndex = 0; // 0: لوحة التحكم, 1: البلاغات, 2: التوصيات
  int _selectedReportsTab = 0; // 0: بلاغات المهام, 1: بلاغات الحاويات
  int _unreadTaskReports = 0;
  int _unreadContainerReports = 0;
  bool _isRefreshing = false; // أضف هذا مع باقي المتغيرات
  // متغيرات التخزين المؤقت للمستخدمين
  Map<String, dynamic> _cachedUsersData = {};
  DateTime _lastUsersUpdate = DateTime.now();
  bool _isLoadingUsers = false;
  // أضف هذا المتغير
  Future<QuerySnapshot<Map<String, dynamic>>>? _taskReportsFuture;
  Future<List<Map<String, dynamic>>>? _containerReportsFuture;

  // متغيرات التخزين المؤقت لبلاغات المهام
  Map<String, dynamic> _cachedTaskReportsData = {};
  DateTime _lastTaskReportsUpdate = DateTime.now();
  bool _isLoadingTaskReports = false;
  // متغيرات التخزين المؤقت لبلاغات الحاويات
  List<Map<String, dynamic>> _cachedContainerReports = [];
  DateTime _lastContainerReportsUpdate = DateTime.now();
  bool _isLoadingContainerReports = false;
  bool _isFetchingRecommendations = false;
  // متغيرات للتحكم في عرض البلاغات
  bool _showAllTaskReports = false;
  bool _showAllContainerReports = false;
  Map<String, bool> _viewedTaskReports = {}; // لتخزين البلاغات التي تم عرضها
  Map<String, bool> _viewedContainerReports = {};
  // أضف هذه المتغيرات مع باقي المتغيرات في بداية الكلاس
  int _cachedTotalReportsCount = 0;
  DateTime _lastTotalReportsUpdate = DateTime.now();
  bool _isLoadingTotalReports = false;

  bool _initialReportsLoaded = false;
  bool _isInReportsTab = false;
  bool _initialContainerReportsLoaded = false;

  // في AdminHomePageState أضف هذه المتغيرات
  List<Map<String, dynamic>> _adminRecommendations = [];
  bool _isLoadingRecommendations = false;
  String? _currentSeason;
  Map<String, dynamic>? _summary;
  // أضف هذا المتغير
  bool _isTestingFunction = false;

  late SharedPreferences _prefs;
  Set<String> _hiddenRecommendations = {};

  final PageController _dashboardPageController = PageController();
  int _dashboardPageIndex = 0;

  // أضف هذه الدالة
  Future<void> _testFunctionDirectly() async {
    if (_isTestingFunction) return;

    setState(() => _isTestingFunction = true);

    try {
      print('🔵 [Test] جاري اختبار الدالة مباشرة...');
      final functions = FirebaseFunctions.instanceFor(region: 'us-central1');
      final result = await functions
          .httpsCallable('getAdminRecommendations')
          .call();

      print('✅ [Test] الدالة اشتغلت بنجاح!');
      print('📦 [Test] النتيجة: ${result.data}');

      // حول البيانات
      final data = Map<String, dynamic>.from(result.data);
      final recs = data['recommendations'] as List;

      print('📊 [Test] عدد التوصيات: ${recs.length}');

      if (recs.isNotEmpty) {
        setState(() {
          _adminRecommendations = List<Map<String, dynamic>>.from(
            recs.map((e) => Map<String, dynamic>.from(e)),
          );
        });
        print('✅ [Test] تم تحديث الواجهة');
      }
    } on FirebaseFunctionsException catch (e) {
      print('❌ [Test] خطأ في الدالة:');
      print('   - الكود: ${e.code}');
      print('   - الرسالة: ${e.message}');
      print('   - التفاصيل: ${e.details}');
    } catch (e) {
      print('❌ [Test] خطأ عام: $e');
    } finally {
      setState(() => _isTestingFunction = false);
    }
  }

  Future<void> _loadAdminRecommendations() async {
    if (_isFetchingRecommendations) return;
    _isFetchingRecommendations = true;

    setState(() => _isLoadingRecommendations = true);

    try {
      final function = FirebaseFunctions.instanceFor(region: 'us-central1');
      final callable = function.httpsCallable('getAdminRecommendations');

      final result = await callable().timeout(
        const Duration(seconds: 60), // ← زيدها من 15 لـ 60
      );

      if (!mounted) return;

      if (result.data != null) {
        final Map<String, dynamic> data = Map<String, dynamic>.from(
          result.data as Map,
        );

        setState(() {
          if (data.containsKey('recommendations')) {
            final recs = data['recommendations'] as List;
            final recommendationsWithIds = recs.asMap().entries.map((entry) {
              final index = entry.key;
              final e = entry.value;
              final rec = Map<String, dynamic>.from(e as Map);
              if (!rec.containsKey('id')) {
                rec['id'] =
                    'rec_${rec['type']}_${rec['title']}'; // ← احذفي الـ timestamp
              }
              return rec;
            }).toList();

            _adminRecommendations = recommendationsWithIds.where((rec) {
              final recId =
                  rec['id'] ?? rec['taskId'] ?? rec.hashCode.toString();
              return !_hiddenRecommendations.contains(recId);
            }).toList();
          }

          if (data['season'] != null) {
            final season = data['season'];
            if (season is Map) {
              _currentSeason = Map<String, dynamic>.from(
                season,
              )['season']?.toString();
            } else if (season is String) {
              _currentSeason = season;
            }
          }

          if (data['summary'] != null) {
            _summary = Map<String, dynamic>.from(data['summary'] as Map);
          }

          _isLoadingRecommendations = false;
        });
      }
    } on TimeoutException catch (_) {
      // ← هنا يمسك الـ timeout
      print('⚠️ Recommendations timeout — loading from cache');
      await _loadRecommendationsFromCache();
    } catch (e) {
      print('🔴 Error loading recommendations: $e');
      await _loadRecommendationsFromCache(); // ← في حالة أي خطأ كمان جرب الكاش
    } finally {
      _isFetchingRecommendations = false;
      if (mounted) setState(() => _isLoadingRecommendations = false);
    }
  }

  Future<void> _loadRecommendationsFromCache() async {
    try {
      final currentMonth = DateTime.now().toIso8601String().substring(0, 7);
      final cached = await FirebaseFirestore.instance
          .collection('adminRecommendations')
          .doc(currentMonth)
          .get();

      if (cached.exists && mounted) {
        final data = cached.data()!;
        final recs = data['recommendations'] as List? ?? [];
        setState(() {
          _adminRecommendations = List<Map<String, dynamic>>.from(
            recs.map((e) => Map<String, dynamic>.from(e)),
          );
          _isLoadingRecommendations = false;
        });
      }
    } catch (e) {
      print('❌ Cache load failed: $e');
    }
  }

  // في AdminHomePageState أضف هذا المتغير
  List<String> _taskCategories = [];

  // وأضف دالة لجلب التصنيفات
  Future<void> _loadTaskCategories() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('categories')
          .get();

      final categories =
          snapshot.docs
              .map((doc) {
                final data = doc.data() as Map<String, dynamic>;
                return data['name']?.toString() ?? '';
              })
              .where((name) => name.isNotEmpty)
              .toList()
            ..sort();

      setState(() {
        _taskCategories = categories;
      });
    } catch (e) {
      debugPrint('❌ Error loading categories: $e');
    }
  }

  // أضف هذا مع باقي المتغيرات
  final GlobalKey<ScaffoldMessengerState> _messengerKey =
      GlobalKey<ScaffoldMessengerState>();

  void _markTaskReportAsViewed(String reportId) {
    // لا تفعل شيئاً هنا - سنقوم بالتحديث فقط عند الضغط على البلاغ
    print('📝 ملاحظة: محاولة تحديث البلاغ $reportId');
  }

  void _markContainerReportAsViewed(String reportId) {
    setState(() {
      _viewedContainerReports[reportId] = true;
    });
  }

  // 🔧 دوال الفترات الزمنية
  List<String> _generatePeriodKeys(DateTime start, DateTime end, String range) {
    final List<String> keys = [];
    DateTime current = start;

    switch (range) {
      case 'اليوم':
        for (int i = 0; i < 24; i++) {
          keys.add(i.toString());
        }
        break;

      case 'أسبوع':
        for (int i = 0; i < 7; i++) {
          keys.add(DateFormat('E').format(current));
          current = current.add(const Duration(days: 1));
        }
        break;

      case 'شهر':
        for (int i = 0; i < 30; i++) {
          keys.add(DateFormat('dd').format(current));
          current = current.add(const Duration(days: 1));
        }
        break;

      case 'سنة':
        for (int i = 0; i < 12; i++) {
          keys.add(DateFormat('MMM').format(DateTime(start.year, i + 1)));
        }
        break;
    }

    return keys;
  }

  String _getPeriodKey(DateTime date, String range) {
    switch (range) {
      case 'اليوم':
        return date.hour.toString();
      case 'أسبوع':
        return DateFormat('E').format(date);
      case 'شهر':
        return DateFormat('dd').format(date);
      case 'سنة':
        return DateFormat('MMM').format(date);
      default:
        return date.toString();
    }
  }

  DateTime _getEndDateForRange(String range) {
    final d = _cursorDate;

    switch (range) {
      case 'اليوم':
        return DateTime(d.year, d.month, d.day, 23, 59, 59);
      case 'أسبوع':
        return d.add(const Duration(days: 7));
      case 'شهر':
        return DateTime(d.year, d.month + 1, d.day);
      case 'سنة':
        return DateTime(d.year + 1, d.month, d.day);
      default:
        return d;
    }
  }

  @override
  void initState() {
    super.initState();

    _initPrefs().then((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadTargetFromFirebase();
        _loadTaskCategories();
        _loadAdminRecommendations();
        // _testFunctionDirectly();
        _loadTopUsers();

        setState(() {
          _containerReportsFuture = _getContainerReports();
        });
      });
    });

    _refreshTimer = Timer.periodic(const Duration(minutes: 30), (_) {
      if (mounted) {
        _refreshData();
      }
    });
  }

  Future<void> _refreshData() async {
    if (_isRefreshing) return;

    setState(() => _isRefreshing = true);

    try {
      // إعادة تعيين الكاش
      _cachedUsersData = {};
      _cachedTaskData = {};
      _cachedContainerReports = []; // أضف هذا السطر
      _cachedTaskReportsData = {};

      _lastUsersUpdate = DateTime.now().subtract(const Duration(hours: 1));
      _lastTaskDataUpdate = DateTime.now().subtract(const Duration(hours: 1));
      _lastContainerReportsUpdate = DateTime.now().subtract(
        const Duration(hours: 1),
      ); // أضف هذا السطر
      _lastTaskReportsUpdate = DateTime.now().subtract(
        const Duration(hours: 1),
      );

      await Future.wait([
        _loadTopUsers(),
        _loadChartData(),
        _loadUnreadCounts(),
      ]);
    } catch (e) {
      debugPrint('❌ Refresh error: $e');
    } finally {
      if (mounted) {
        setState(() => _isRefreshing = false);
      }
    }
  }

  Future<void> _initPrefs() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      final hiddenList = _prefs.getStringList('hidden_recommendations') ?? [];
      setState(() {
        _hiddenRecommendations = hiddenList.toSet();
      });
      print(
        '✅ SharedPreferences initialized with ${_hiddenRecommendations.length} hidden items',
      );
    } catch (e) {
      print('❌ Error initializing SharedPreferences: $e');
      // في حالة الخطأ، نستخدم مجموعة فارغة
      _hiddenRecommendations = {};
    }
  }

  void dispose() {
    _refreshTimer?.cancel();
    _targetController.dispose();
    _dashboardPageController.dispose();
    super.dispose();
  }

  Future<void> _loadTopUsers() async {
    setState(() => _isLoadingTopUsers = true);
    try {
      final topUsers = await _fetchTopUsers();

      if (mounted) {
        setState(() {
          _topUsers = topUsers;
          _isLoadingTopUsers = false;
        });
      }
    } catch (e) {
      print('❌ Error in _loadTopUsers: $e');
      if (mounted) {
        setState(() => _isLoadingTopUsers = false);
      }
    }
  }

  Future<void> _loadChartData() async {
    await _loadUserGrowthData();
    await _loadTaskCompletionData();
    await _loadPointsData();
    await _loadCarbonData();
  }

  String get _rangeLabel {
    switch (_selectedTimeRange) {
      case 'سنة':
        return 'سنة ${_cursorDate.year}';
      case 'شهر':
        return '${_cursorDate.month}/${_cursorDate.year}';
      case 'أسبوع':
        final week = ((_cursorDate.day - 1) / 7).floor() + 1;
        return 'أسبوع $week';
      case 'اليوم':
        return DateFormat('dd/MM/yyyy').format(_cursorDate);
      default:
        return '';
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
        return appColors.sea;
    }
  }

  String _statusLabel(String s) {
    switch (s) {
      case 'pending':
        return 'قيد المراجعة';
      case 'approved':
        return 'تمت المعالجة';
      case 'rejected':
        return 'مرفوض';
      default:
        return s;
    }
  }

  Future<void> _loadUnreadCounts() async {
    try {
      // تحميل عدد بلاغات المهام (pending فقط)
      final taskReports = await FirebaseFirestore.instance
          .collection('taskReports')
          .where('decision', isEqualTo: 'pending')
          .get();

      // تحميل عدد بلاغات الحاويات
      final containerReports = await FirebaseFirestore.instance
          .collection('facilityReports')
          .where('status', isEqualTo: 'pending')
          .get();

      if (mounted) {
        setState(() {
          _unreadTaskReports = taskReports.docs.length;
          _unreadContainerReports = containerReports.docs.length;
        });
      }
    } catch (e) {
      debugPrint('❌ Error loading unread counts: $e');
    }
  }

  Future<int> _getTotalReportsCount() async {
    // إذا كان التحميل جارياً، أرجع القيمة المخزنة مؤقتاً
    if (_isLoadingTotalReports) {
      return _cachedTotalReportsCount;
    }

    // استخدام الكاش إذا كان حديثاً (أقل من 30 ثانية)
    if (DateTime.now().difference(_lastTotalReportsUpdate).inSeconds < 30) {
      return _cachedTotalReportsCount;
    }

    setState(() => _isLoadingTotalReports = true);

    try {
      // تنفيذ الاستعلامات بالتوازي
      final results = await Future.wait([
        FirebaseFirestore.instance
            .collection('taskReports')
            .where('decision', isEqualTo: 'pending')
            .get()
            .then((snapshot) {
              final allReports = snapshot.docs;

              // حساب عدد البلاغات الجديدة فقط (غير المقروءة)
              final newReportsCount = allReports.where((doc) {
                final reportId = doc.id;
                return !(_viewedTaskReports[reportId] ?? false);
              }).length;

              // تحديث عداد بلاغات المهام
              if (mounted) {
                setState(() {
                  _unreadTaskReports = newReportsCount;
                });
              }
              return newReportsCount;
            }),

        FirebaseFirestore.instance
            .collection('facilityReports')
            .where('status', isEqualTo: 'pending')
            .get()
            .then((snapshot) {
              final allReports = snapshot.docs;

              // حساب عدد البلاغات الجديدة فقط (غير المقروءة)
              final newReportsCount = allReports.where((doc) {
                final reportId = doc.id;
                return !(_viewedContainerReports[reportId] ?? false);
              }).length;

              // تحديث عداد بلاغات الحاويات
              if (mounted) {
                setState(() {
                  _unreadContainerReports = newReportsCount;
                });
              }
              return newReportsCount;
            }),
      ]);

      final total = results[0] + results[1];

      if (mounted) {
        setState(() {
          _cachedTotalReportsCount = total;
          _lastTotalReportsUpdate = DateTime.now();
          _isLoadingTotalReports = false;
        });
      }

      return total;
    } catch (e) {
      debugPrint('❌ Error getting reports count: $e');
      if (mounted) {
        setState(() => _isLoadingTotalReports = false);
      }
      return _cachedTotalReportsCount; // أرجع القيمة المخزنة مؤقتاً في حالة الخطأ
    }
  }

  Future<void> _loadUserGrowthData() async {
    try {
      final startDate = _getStartDateForRange(_selectedTimeRange);
      final endDate = _getEndDateForRange(_selectedTimeRange);

      final usersSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('isVerified', isEqualTo: true)
          .get();

      final Map<String, int> periodCounts = {};
      final periodKeys = _generatePeriodKeys(
        startDate,
        endDate,
        _selectedTimeRange,
      );

      for (final key in periodKeys) {
        periodCounts[key] = 0;
      }

      // ✅ فلترة يدوية حسب التاريخ
      int validUsers = 0;
      for (final doc in usersSnapshot.docs) {
        final data = doc.data();
        final createdAt = data['createdAt'];

        if (createdAt is Timestamp) {
          final userDate = createdAt.toDate();

          // تحقق يدوي من التاريخ
          if (userDate.isAfter(startDate) && userDate.isBefore(endDate)) {
            validUsers++;
            final periodKey = _getPeriodKey(userDate, _selectedTimeRange);
            if (periodCounts.containsKey(periodKey)) {
              periodCounts[periodKey] = periodCounts[periodKey]! + 1;
            }
          }
        }
      }

      debugPrint('✅ Valid users in range: $validUsers');
      debugPrint('📊 Period counts: $periodCounts');

      final List<FlSpot> spots = [];
      int index = 0;
      double cumulative = 0;

      for (final key in periodKeys) {
        cumulative += periodCounts[key] ?? 0;
        spots.add(FlSpot(index.toDouble(), cumulative));
        index++;
      }

      debugPrint('📈 Generated spots: $spots');

      if (mounted) {
        setState(() {
          _userGrowthSpots = spots;
        });
      }
    } catch (e) {
      debugPrint('❌ User growth error: $e');
    }
  }

  void _debugCheckNewReports() async {
    debugPrint('🔍 تشخيص البلاغات الجديدة:');

    // جلب جميع البلاغات من Firebase
    final taskReports = await FirebaseFirestore.instance
        .collection('taskReports')
        .where('decision', isEqualTo: 'pending')
        .get();

    debugPrint('📊 عدد البلاغات في Firebase: ${taskReports.docs.length}');

    for (var doc in taskReports.docs) {
      final data = doc.data();
      debugPrint('   - بلاغ: ${doc.id}');
      debugPrint('     taskTitle: ${data['taskTitle']}');
      debugPrint('     decision: ${data['decision']}');
      debugPrint('     createdAt: ${data['createdAt']}');
      debugPrint('     viewed: ${_viewedTaskReports[doc.id] ?? false}');
    }

    // البلاغات الجديدة في الواجهة
    final newReports = taskReports.docs.where((doc) {
      return !(_viewedTaskReports[doc.id] ?? false);
    }).toList();

    debugPrint('✅ البلاغات الجديدة في الواجهة: ${newReports.length}');
  }

  Widget _buildRangeNavigator() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left), // 👈 صح في RTL
          onPressed: () {
            setState(() {
              _cursorDate = _shiftDate(-1); // السابق
            });
            _loadChartData();
          },
        ),

        Text(
          _rangeLabel,
          style: GoogleFonts.ibmPlexSansArabic(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Colors.grey[700],
          ),
        ),

        IconButton(
          icon: const Icon(Icons.chevron_right), // 👈 صح في RTL
          onPressed: () {
            setState(() {
              _cursorDate = _shiftDate(1); // التالي
            });
            _loadChartData();
          },
        ),
      ],
    );
  }

  DateTime _shiftDate(int direction) {
    switch (_selectedTimeRange) {
      case 'اليوم':
        return _cursorDate.add(Duration(days: direction));
      case 'أسبوع':
        return _cursorDate.add(Duration(days: 7 * direction));
      case 'شهر':
        return DateTime(
          _cursorDate.year,
          _cursorDate.month + direction,
          _cursorDate.day,
        );
      case 'سنة':
        return DateTime(
          _cursorDate.year + direction,
          _cursorDate.month,
          _cursorDate.day,
        );
      default:
        return _cursorDate;
    }
  }

  Widget _buildLeaderboardCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // العنوان
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'أعلى 3 مستخدمين إنجازًا',
                style: GoogleFonts.ibmPlexSansArabic(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: appColors.dark,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: appColors.accent.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.leaderboard,
                      size: 14,
                      color: appColors.accent,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'قائمة المتصدرين',
                      style: GoogleFonts.ibmPlexSansArabic(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: appColors.accent,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // المحتوى
          if (_isLoadingTopUsers)
            const Center(child: CircularProgressIndicator())
          else if (_topUsers.isEmpty)
            Center(
              child: Text(
                'لا توجد بيانات متاحة',
                style: GoogleFonts.ibmPlexSansArabic(
                  color: Colors.grey[600],
                  fontSize: 13,
                ),
              ),
            )
          else
            // في _buildLeaderboardCard():
            Column(
              children: _topUsers.asMap().entries.map((entry) {
                final index = entry.key; // 👈 نأخذ الفهرس
                final user = entry.value;

                return _buildLeaderboardItem(
                  index: index, // 👈 نمرر الفهرس بدلاً من الرتبة
                  username: user['username'],
                  completedTasks: user['completedTasks'],
                  points: user['points'],
                  pfpIndex: user['pfpIndex'],
                );
              }).toList(),
            ),

          // زر عرض المزيد (اختياري - يمكنك إزالته إذا أردت)
          if (_topUsers.isNotEmpty && _topUsers.length >= 3)
            Column(
              children: [
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: GestureDetector(
                    onTap: () {
                      _showFullLeaderboard();
                    },
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'عرض القائمة الكاملة',
                          style: GoogleFonts.ibmPlexSansArabic(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: appColors.primary,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.chevron_left,
                          size: 16,
                          color: appColors.primary,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildLeaderboardItem({
    required int index,
    required String username,
    required int completedTasks,
    required int points,
    required int pfpIndex,
  }) {
    final rank = index + 1;

    final Color rankColor;
    final IconData? rankIcon;

    switch (rank) {
      case 1:
        rankColor = const Color(0xFFFFD700);
        rankIcon = Icons.emoji_events;
        break;
      case 2:
        rankColor = const Color(0xFFC0C0C0);
        rankIcon = Icons.emoji_events;
        break;
      case 3:
        rankColor = const Color(0xFFCD7F32);
        rankIcon = Icons.emoji_events;
        break;
      default:
        rankColor = Colors.grey[400]!;
        rankIcon = null;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: index < 3 ? rankColor.withOpacity(0.05) : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        border: index < 3
            ? Border.all(color: rankColor.withOpacity(0.3), width: 1.5)
            : null,
      ),
      child: Row(
        children: [
          // الرتبة
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: rankColor.withOpacity(index < 3 ? 0.2 : 0.1),
              shape: BoxShape.circle,
              border: Border.all(color: rankColor.withOpacity(0.3), width: 1),
            ),
            child: Center(
              child: rankIcon != null && index < 3
                  ? Icon(rankIcon, size: 16, color: rankColor)
                  : Text(
                      '$rank',
                      style: GoogleFonts.ibmPlexSansArabic(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: rankColor,
                      ),
                    ),
            ),
          ),

          const SizedBox(width: 12),

          // الصورة الشخصية
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [
                  appColors.primary.withOpacity(.1),
                  appColors.sea.withOpacity(.05),
                ],
              ),
            ),
            child: CircleAvatar(
              backgroundColor: Colors.transparent,
              backgroundImage: AssetImage('assets/pfp/pfp${pfpIndex + 1}.png'),
              child: pfpIndex >= 0 && pfpIndex < 8
                  ? null
                  : const Icon(
                      Icons.person,
                      size: 20,
                      color: appColors.primary,
                    ),
            ),
          ),

          const SizedBox(width: 12),

          // الاسم والإحصائيات
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  username,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.ibmPlexSansArabic(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: index < 3 ? appColors.dark : Colors.grey[800],
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    // المهام المكتملة
                    Row(
                      children: [
                        Icon(Icons.task_alt, size: 12, color: Colors.green),
                        const SizedBox(width: 4),
                        Text(
                          '$completedTasks',
                          style: GoogleFonts.ibmPlexSansArabic(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Colors.green,
                          ),
                        ),
                        Text(
                          ' مهام',
                          style: GoogleFonts.ibmPlexSansArabic(
                            fontSize: 11,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(width: 12),

                    // النقاط
                    Row(
                      children: [
                        Icon(Icons.star, size: 12, color: Colors.amber),
                        const SizedBox(width: 4),
                        Text(
                          '$points',
                          style: GoogleFonts.ibmPlexSansArabic(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Colors.amber,
                          ),
                        ),
                        Text(
                          ' نقطة',
                          style: GoogleFonts.ibmPlexSansArabic(
                            fontSize: 11,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),

          // مؤشر التقدم (اختياري)
          if (index == 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: rankColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'الأول',
                style: GoogleFonts.ibmPlexSansArabic(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: rankColor,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // دالة لجلب بيانات المستخدمين
  Future<Map<String, dynamic>> _getUsersData() async {
    // استخدام الكاش إذا كان حديثاً
    if (DateTime.now().difference(_lastUsersUpdate).inMinutes < 5 &&
        _cachedUsersData.isNotEmpty) {
      return _cachedUsersData;
    }

    setState(() => _isLoadingUsers = true);

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('isVerified', isEqualTo: true)
          .get();

      num totalCarbon = 0;
      for (final doc in snapshot.docs) {
        totalCarbon += (doc.data()['totalCarbonSaved'] as num?) ?? 0;
      }

      final data = {
        'totalCarbon': totalCarbon,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };

      // تحديث الكاش
      _cachedUsersData = data;
      _lastUsersUpdate = DateTime.now();

      return data;
    } catch (e) {
      debugPrint('❌ Error loading users data: $e');
      return {'totalCarbon': 0};
    } finally {
      if (mounted) {
        setState(() => _isLoadingUsers = false);
      }
    }
  }

  Future<QuerySnapshot<Map<String, dynamic>>> _getTaskReports() async {
    final snapshot = await FirebaseFirestore.instance
        .collection('taskReports')
        .orderBy('createdAt', descending: true)
        .limit(10)
        .get();

    if (!_initialReportsLoaded) {
      for (final doc in snapshot.docs) {
        if (!_viewedTaskReports.containsKey(doc.id)) {
          _viewedTaskReports[doc.id] = false;
        }
      }
      _initialReportsLoaded = true;
    }

    return snapshot;
  }

  // دالة محسنة لجلب بلاغات الحاويات مع تخزين مؤقت
  Future<List<Map<String, dynamic>>> _getContainerReports() async {
    setState(() => _isLoadingContainerReports = true);

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('facilityReports')
          .orderBy('createdAt', descending: true)
          .limit(10)
          .get();

      final reports = snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();

      if (!_initialContainerReportsLoaded) {
        for (final report in reports) {
          final reportId = report['id'];
          if (!_viewedContainerReports.containsKey(reportId)) {
            _viewedContainerReports[reportId] = false;
          }
        }
        _initialContainerReportsLoaded = true;
      } else {
        for (final report in reports) {
          final reportId = report['id'];
          if (!_viewedContainerReports.containsKey(reportId)) {
            _viewedContainerReports[reportId] = false;
          }
        }
      }

      final pendingCount = reports.where((r) {
        final reportId = r['id'];
        return !(_viewedContainerReports[reportId] ?? false);
      }).length;

      if (mounted) {
        setState(() {
          _unreadContainerReports = pendingCount;
          _cachedContainerReports = reports;
          _lastContainerReportsUpdate = DateTime.now();
          _isLoadingContainerReports = false;
        });
      }

      return reports;
    } catch (e) {
      debugPrint('❌ Error loading container reports: $e');

      if (mounted) {
        setState(() => _isLoadingContainerReports = false);
      }

      return _cachedContainerReports.isEmpty ? [] : _cachedContainerReports;
    }
  }

  // أضف مع باقي المتغيرات
  Set<String> _firebaseHiddenRecommendations = {};

  // دالة لجلب التوصيات المخفية من Firebase
  Future<void> _loadFirebaseHiddenRecommendations() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final doc = await FirebaseFirestore.instance
          .collection('adminHiddenRecommendations')
          .doc(user.uid)
          .get();

      if (doc.exists) {
        final data = doc.data();
        if (data != null && data['hiddenIds'] != null) {
          final List<dynamic> hiddenList = data['hiddenIds'];
          setState(() {
            _firebaseHiddenRecommendations = hiddenList
                .map((e) => e.toString())
                .toSet();
          });
          print(
            '✅ Loaded ${_firebaseHiddenRecommendations.length} hidden recommendations from Firebase',
          );
        }
      }
    } catch (e) {
      print('❌ Error loading hidden recommendations from Firebase: $e');
    }
  }

  // دالة لحفظ التوصية المخفية في Firebase
  Future<void> _saveHiddenRecommendationToFirebase(String recId) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final docRef = FirebaseFirestore.instance
          .collection('adminHiddenRecommendations')
          .doc(user.uid);

      await docRef.set({
        'hiddenIds': FieldValue.arrayUnion([recId]),
        'lastUpdated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      print('✅ Saved hidden recommendation to Firebase: $recId');
    } catch (e) {
      print('❌ Error saving hidden recommendation to Firebase: $e');
    }
  }

  // دالة لجلب التوصيات المخفية من المصدرين (Firebase + SharedPreferences)
  Future<void> _loadAllHiddenRecommendations() async {
    await _loadFirebaseHiddenRecommendations();

    // دمج مع SharedPreferences
    setState(() {
      _hiddenRecommendations.addAll(_firebaseHiddenRecommendations);
    });

    // تحديث SharedPreferences
    await _prefs.setStringList(
      'hidden_recommendations',
      _hiddenRecommendations.toList(),
    );
  }

  // ✅ تحسين: تخزين مؤقت للبيانات
  Map<String, dynamic> _cachedTaskData = {};
  DateTime _lastTaskDataUpdate = DateTime.now();
  bool _isLoadingTaskData = false;

  Future<void> _loadTaskCompletionData() async {
    // ✅ منع التحميل المتكرر
    if (_isLoadingTaskData) return;

    setState(() => _isLoadingTaskData = true);

    try {
      final startDate = _getStartDateForRange(_selectedTimeRange);
      final endDate = _getEndDateForRange(_selectedTimeRange);

      debugPrint('📅 Loading tasks from $startDate to $endDate');

      // ✅ استعلام لجلب جميع التقديمات المعتمدة
      final submissionsSnapshot = await FirebaseFirestore.instance
          .collection('submissions')
          .where('status', isEqualTo: 'approved')
          .where(
            'createdAt',
            isGreaterThanOrEqualTo: Timestamp.fromDate(startDate),
          )
          .where('createdAt', isLessThanOrEqualTo: Timestamp.fromDate(endDate))
          .get();

      debugPrint('📦 Loaded ${submissionsSnapshot.docs.length} submissions');

      // أنشئ قائمة الفترات
      final periodKeys = _generatePeriodKeys(
        startDate,
        endDate,
        _selectedTimeRange,
      );

      // خريطة لتخزين البيانات حسب الفترة والـ emissionFactorRef
      final Map<String, Map<String, int>> categoryCounts = {};
      final Set<String> allCategories = {};

      // تهيئة العدادات
      for (final key in periodKeys) {
        categoryCounts[key] = {};
      }

      // أولاً: جمع كل التصنيفات الفريدة وأسمائها من جميع المستندات
      final Map<String, String> tempCategoryNames = {};
      for (final doc in submissionsSnapshot.docs) {
        final data = doc.data();
        final emissionFactorRef =
            data['emissionFactorRef']?.toString() ?? 'غير محدد';
        final taskTitle = data['taskTitle']?.toString() ?? emissionFactorRef;

        allCategories.add(emissionFactorRef);
        tempCategoryNames[emissionFactorRef] = taskTitle;
      }

      // توليد ألوان ديناميكية لكل تصنيف
      final Map<String, Color> tempCategoryColors = {};
      final colorPalette = [
        Colors.green,
        Colors.blue,
        Colors.orange,
        Colors.purple,
        Colors.teal,
        Colors.pink,
        Colors.indigo,
        Colors.amber,
        Colors.brown,
        Colors.cyan,
        Colors.lime,
        Colors.deepOrange,
        Colors.red,
        Colors.yellow,
        Colors.lightBlue,
        Colors.lightGreen,
      ];

      int colorIndex = 0;
      for (final category in allCategories) {
        tempCategoryColors[category] =
            colorPalette[colorIndex % colorPalette.length];
        colorIndex++;
      }

      // عد المهام حسب emissionFactorRef لكل فترة
      for (final doc in submissionsSnapshot.docs) {
        final data = doc.data();
        final createdAt = data['createdAt'];
        final emissionFactorRef =
            data['emissionFactorRef']?.toString() ?? 'غير محدد';

        if (createdAt is Timestamp) {
          final taskDate = createdAt.toDate();
          final periodKey = _getPeriodKey(taskDate, _selectedTimeRange);

          if (categoryCounts.containsKey(periodKey)) {
            final periodData = categoryCounts[periodKey]!;
            periodData[emissionFactorRef] =
                (periodData[emissionFactorRef] ?? 0) + 1;
          }
        }
      }

      // تحويل إلى BarChartGroupData مع أشرطة متعددة
      final List<BarChartGroupData> barGroups = [];
      int index = 0;

      // حساب القيمة القصوى للمحور Y
      double maxCount = 0;
      for (final key in periodKeys) {
        final periodData = categoryCounts[key] ?? {};
        double periodTotal = 0;
        for (final entry in periodData.entries) {
          periodTotal += entry.value;
        }
        if (periodTotal > maxCount) {
          maxCount = periodTotal;
        }
      }

      // تحديث _taskCompletionSpots للاستخدام في الإحصائيات
      final List<FlSpot> spots = [];
      for (final key in periodKeys) {
        final periodData = categoryCounts[key] ?? {};
        double periodTotal = 0;
        for (final entry in periodData.entries) {
          periodTotal += entry.value;
        }
        spots.add(FlSpot(index.toDouble(), periodTotal));
        index++;
      }

      // إعادة تعيين index
      index = 0;
      final Map<int, Map<String, dynamic>> tempBarInfo = {};

      for (final key in periodKeys) {
        final periodData = categoryCounts[key] ?? {};

        // إنشاء أشرطة لكل تصنيف في نفس المجموعة
        final List<BarChartRodData> rods = [];
        final Map<String, dynamic> groupInfo = {};

        // ترتيب التصنيفات حسب العدد (تنازلياً)
        final sortedCategories = periodData.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));

        double currentStack = 0;
        int rodIndex = 0;
        for (final entry in sortedCategories) {
          final category = entry.key;
          final count = entry.value.toDouble();
          final displayName = tempCategoryNames[category] ?? category;

          if (count > 0) {
            // تخزين معلومات هذا الشريط
            groupInfo['rod_$rodIndex'] = {
              'category': category,
              'name': displayName,
              'count': count,
              'color': tempCategoryColors[category] ?? Colors.grey,
              'startY': currentStack,
              'endY': currentStack + count,
            };

            rods.add(
              BarChartRodData(
                toY: currentStack + count,
                width: _getBarWidth(_selectedTimeRange),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(4),
                  topRight: Radius.circular(4),
                ),
                color: tempCategoryColors[category] ?? Colors.grey,
              ),
            );
            currentStack += count;
            rodIndex++;
          }
        }

        // تخزين معلومات المجموعة
        tempBarInfo[index] = groupInfo;

        // إذا كانت rods فارغة، أضف شريطاً فارغاً
        if (rods.isEmpty) {
          rods.add(
            BarChartRodData(
              toY: 0,
              width: _getBarWidth(_selectedTimeRange),
              color: Colors.transparent,
            ),
          );
        }

        barGroups.add(BarChartGroupData(x: index, barRods: rods, barsSpace: 0));

        index++;
      }

      if (mounted) {
        setState(() {
          _taskBarGroups = barGroups;
          _taskCompletionSpots = spots;
          _categoryNames.addAll(tempCategoryNames);
          _categoryColors.addAll(tempCategoryColors);
          _uniqueCategories = allCategories;
          _barCategoriesInfo = tempBarInfo;
          _isLoadingTaskData = false;
        });
      }
    } catch (e) {
      debugPrint('❌ Task completion error: $e');
      if (mounted) {
        setState(() => _isLoadingTaskData = false);
      }
    }
  }

  Future<void> _loadPointsData() async {
    try {
      final startDate = _getStartDateForRange(_selectedTimeRange);
      final endDate = _getEndDateForRange(_selectedTimeRange);

      final submissionsSnapshot = await FirebaseFirestore.instance
          .collection('submissions')
          .where('status', isEqualTo: 'approved')
          .where(
            'createdAt',
            isGreaterThanOrEqualTo: Timestamp.fromDate(startDate),
          )
          .where('createdAt', isLessThanOrEqualTo: Timestamp.fromDate(endDate))
          .get();

      final Map<String, double> periodPoints = {};
      final periodKeys = _generatePeriodKeys(
        startDate,
        endDate,
        _selectedTimeRange,
      );

      for (final key in periodKeys) {
        periodPoints[key] = 0;
      }

      for (final doc in submissionsSnapshot.docs) {
        final data = doc.data();
        final createdAt = data['createdAt'];
        final taskPoints = data['taskPoints'];

        if (createdAt is Timestamp && taskPoints is num) {
          final taskDate = createdAt.toDate();
          final periodKey = _getPeriodKey(taskDate, _selectedTimeRange);

          if (periodPoints.containsKey(periodKey)) {
            periodPoints[periodKey] =
                periodPoints[periodKey]! + taskPoints.toDouble();
          }
        }
      }

      // تراكمي
      final List<FlSpot> spots = [];
      int index = 0;
      double cumulative = 0;

      for (final key in periodKeys) {
        cumulative += periodPoints[key] ?? 0;
        spots.add(FlSpot(index.toDouble(), cumulative));
        index++;
      }

      setState(() {
        _pointsSpots = spots;
      });
    } catch (e) {
      debugPrint('❌ Points error: $e');
    }
  }

  Future<void> _loadCarbonData() async {
    try {
      final startDate = _getStartDateForRange(_selectedTimeRange);
      final endDate = _getEndDateForRange(_selectedTimeRange);

      final snapshot = await FirebaseFirestore.instance
          .collection('submissions')
          .where('status', isEqualTo: 'approved')
          .where(
            'createdAt',
            isGreaterThanOrEqualTo: Timestamp.fromDate(startDate),
          )
          .where('createdAt', isLessThanOrEqualTo: Timestamp.fromDate(endDate))
          .get();

      final periodKeys = _generatePeriodKeys(
        startDate,
        endDate,
        _selectedTimeRange,
      );

      final Map<String, double> periodCarbon = {
        for (final k in periodKeys) k: 0,
      };

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final ts = data['createdAt'];
        final carbon = data['carbonSaved'];

        if (ts is! Timestamp || carbon is! num) continue;

        final date = ts.toDate();
        final key = _getPeriodKey(date, _selectedTimeRange);

        if (periodCarbon.containsKey(key)) {
          periodCarbon[key] = periodCarbon[key]! + carbon.toDouble();
        }
      }

      final List<FlSpot> spots = [];
      int index = 0;

      for (final key in periodKeys) {
        spots.add(FlSpot(index.toDouble(), periodCarbon[key] ?? 0));
        index++;
      }

      setState(() {
        _carbonSpots = spots;
      });
    } catch (e) {
      debugPrint('❌ Carbon error: $e');
    }
  }

  DateTime _getStartDateForRange(String range) {
    final d = _cursorDate;

    switch (range) {
      case 'اليوم':
        return DateTime(d.year, d.month, d.day);

      case 'أسبوع':
        // بداية الأسبوع (الأحد)
        final weekday = d.weekday % 7;
        return DateTime(
          d.year,
          d.month,
          d.day,
        ).subtract(Duration(days: weekday));

      case 'شهر':
        return DateTime(d.year, d.month, 1);

      case 'سنة':
        return DateTime(d.year, 1, 1);

      default:
        return d;
    }
  }

  void _onTap(int i) {
    if (i == _currentIndex) return;
    switch (i) {
      case 0:
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => reward.AdminRewardsPage()),
        );
        break;
      case 1:
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const AdminMapPage()),
        );
        break;
      case 2:
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const AdminTasksPage()),
        );
        break;
      case 3:
        break;
    }
  }

  Widget _buildTimeRangeSelector() {
    return Container(
      height: 34, // 👈 هذا أهم سطر (قلل الارتفاع)
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: appColors.primary.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
      ),
      alignment: Alignment.center,
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedTimeRange,
          isDense: true, // 👈 يقلل الارتفاع الداخلي
          icon: Icon(
            Icons.arrow_drop_down,
            color: appColors.primary,
            size: 20, // 👈 أيقونة أصغر
          ),
          dropdownColor: Colors.white,
          borderRadius: BorderRadius.circular(12),
          style: GoogleFonts.ibmPlexSansArabic(
            color: appColors.dark,
            fontWeight: FontWeight.w600,
            fontSize: 12, // 👈 خط أصغر
          ),
          onChanged: (String? newValue) {
            if (newValue != null) {
              setState(() {
                _selectedTimeRange = newValue;
              });
              _loadChartData();
            }
          },
          items: _timeRanges.map<DropdownMenuItem<String>>((String value) {
            return DropdownMenuItem<String>(value: value, child: Text(value));
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildBarChartCard(
    String title,
    List<FlSpot> spots,
    Color color,
    String timeRange,
  ) {
    final double maxY = _getMaxYValue(spots);
    final double average = spots.isNotEmpty
        ? spots.map((e) => e.y).reduce((a, b) => a + b) / spots.length
        : 0;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          /// العنوان + الفلتر
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: appColors.dark,
                  ),
                ),
                _buildTimeRangeSelector(),
              ],
            ),
          ),

          const SizedBox(height: 8),

          /// 👇 الرسم البياني
          SizedBox(
            height: 200,
            child: Row(
              children: [
                Expanded(
                  child: spots.isEmpty
                      ? const Center(child: Text('لا توجد بيانات'))
                      : BarChart(
                          BarChartData(
                            minY: maxY == 0 ? 0 : 0.0001,
                            maxY: maxY == 0 ? 10 : maxY * 1.1,
                            gridData: FlGridData(
                              show: true,
                              drawVerticalLine: false,
                              horizontalInterval: maxY == 0
                                  ? 1
                                  : (maxY / 3).ceilToDouble(),
                            ),
                            titlesData: FlTitlesData(
                              show: true,
                              topTitles: const AxisTitles(
                                sideTitles: SideTitles(showTitles: false),
                              ),
                              rightTitles: const AxisTitles(
                                sideTitles: SideTitles(showTitles: false),
                              ),
                              leftTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  reservedSize: 30,
                                  interval: maxY <= 1 ? 0.5 : (maxY / 3),
                                  getTitlesWidget: (value, meta) {
                                    if (value.abs() < 0.0001) {
                                      return const SizedBox.shrink();
                                    }

                                    final third = maxY / 3;
                                    final twoThird = maxY * 2 / 3;

                                    bool isMatch(double a, double b) =>
                                        (a - b).abs() < 0.0001;

                                    if (isMatch(value, maxY) ||
                                        isMatch(value, twoThird) ||
                                        isMatch(value, third)) {
                                      return Padding(
                                        padding: const EdgeInsets.only(
                                          right: 4,
                                        ),
                                        child: Text(
                                          value < 1
                                              ? value.toStringAsFixed(1)
                                              : value.toInt().toString(),
                                          style: const TextStyle(
                                            fontSize: 9,
                                            color: Colors.grey,
                                            fontWeight: FontWeight.w500,
                                          ),
                                          textAlign: TextAlign.right,
                                        ),
                                      );
                                    }
                                    return const SizedBox.shrink();
                                  },
                                ),
                              ),
                              bottomTitles: AxisTitles(
                                axisNameWidget: Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(
                                    _getXAxisLabel(),
                                    style: GoogleFonts.ibmPlexSansArabic(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.grey[700],
                                    ),
                                  ),
                                ),
                                axisNameSize: 25,
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  reservedSize: 25,
                                  interval: _getInterval(),
                                  getTitlesWidget: (value, meta) {
                                    return Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: _buildXAxisTitle(value, meta),
                                    );
                                  },
                                ),
                              ),
                            ),
                            borderData: FlBorderData(
                              show: true,
                              border: Border.all(
                                color: Colors.grey[300]!,
                                width: 1,
                              ),
                            ),
                            barGroups: _taskBarGroups.isEmpty
                                ? _buildDefaultBarGroups(spots)
                                : _taskBarGroups,
                            barTouchData: BarTouchData(
                              enabled: true,
                              touchTooltipData: BarTouchTooltipData(
                                tooltipBgColor: color,
                                getTooltipItem:
                                    (group, groupIndex, rod, rodIndex) {
                                      // إذا كان عندنا معلومات عن هذا الشريط
                                      if (_barCategoriesInfo.containsKey(
                                        group.x,
                                      )) {
                                        final groupInfo =
                                            _barCategoriesInfo[group.x]!;
                                        final rodKey = 'rod_$rodIndex';

                                        if (groupInfo.containsKey(rodKey)) {
                                          final rodInfo = groupInfo[rodKey];
                                          final categoryName = rodInfo['name'];
                                          final count = rodInfo['count']
                                              .toInt();

                                          return BarTooltipItem(
                                            '$categoryName\n$count مهمة',
                                            const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 10,
                                            ),
                                          );
                                        }
                                      }

                                      // إذا لم نجد معلومات، نعرض القيمة فقط
                                      return BarTooltipItem(
                                        '${rod.toY.toInt()} مهمة',
                                        const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 10,
                                        ),
                                      );
                                    },
                              ),
                            ),
                          ),
                        ),
                ),

                const SizedBox(width: 1),

                Center(
                  child: RotatedBox(
                    quarterTurns: 3,
                    child: Text(
                      'القيمة',
                      style: GoogleFonts.ibmPlexSansArabic(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[700],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),
          _buildRangeNavigator(),

          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildCompactMiniStat(
                  'الإجمالي',
                  spots.isNotEmpty
                      ? spots
                            .map((e) => e.y)
                            .reduce((a, b) => a + b)
                            .toStringAsFixed(1)
                      : '0',
                ),
                _buildCompactMiniStat('المتوسط', average.toStringAsFixed(1)),
                _buildCompactMiniStat('الأعلى', maxY.toInt().toString()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // دالة لبناء BarGroups افتراضية (احتياطي)
  List<BarChartGroupData> _buildDefaultBarGroups(List<FlSpot> spots) {
    return spots.asMap().entries.map((entry) {
      int index = entry.key;
      FlSpot spot = entry.value;

      return BarChartGroupData(
        x: index,
        barRods: [
          BarChartRodData(
            toY: spot.y,
            width: _getBarWidth(_selectedTimeRange),
            borderRadius: BorderRadius.circular(4),
            color: spot.y > 0 ? appColors.sea : Colors.grey[300]!,
          ),
        ],
      );
    }).toList();
  }

  // دالة وسيلة الإيضاح مع Tooltip

  Widget _buildCompactMiniStat(String label, String value) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: appColors.dark,
          ),
        ),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(fontSize: 9, color: Colors.grey[600])),
      ],
    );
  }

  Widget _buildXAxisTitle(double value, TitleMeta meta) {
    int index = value.toInt();
    String text = '';

    if (_selectedTimeRange == 'اليوم') {
      if (index % 3 == 0) {
        text = index.toString();
      }
    } else if (_selectedTimeRange == 'أسبوع') {
      if (index < 7 && index % 2 == 0) {
        const days = ['أحد', 'اثن', 'ثلث', 'أرب', 'خمي', 'جمع', 'سبت'];
        text = days[index];
      }
    } else if (_selectedTimeRange == 'شهر') {
      if (index % 5 == 0 && index < 30) {
        text = (index + 1).toString();
      }
    } else if (_selectedTimeRange == 'سنة') {
      if (index < 12 && index % 2 == 0) {
        const months = [
          'ينا',
          'فبر',
          'مار',
          'أبر',
          'ماي',
          'يون',
          'يول',
          'أغس',
          'سبت',
          'أكت',
          'نوف',
          'ديس',
        ];
        text = months[index];
      }
    }

    if (text.isEmpty) return const SizedBox.shrink();

    return Text(
      text,
      style: const TextStyle(fontSize: 8, color: Colors.grey),
      textAlign: TextAlign.center,
    );
  }

  /// 🏷️ دالة مساعدة لعنوان المحور X حسب الفترة
  String _getXAxisLabel() {
    switch (_selectedTimeRange) {
      case 'اليوم':
        return 'الساعة';
      case 'أسبوع':
        return 'اليوم';
      case 'شهر':
        return 'اليوم';
      case 'سنة':
        return 'الشهر';
      default:
        return 'الفترة';
    }
  }

  Widget _buildChartCard(
    String title,
    List<FlSpot> spots,
    Color color,
    String timeRange,
  ) {
    final double maxY = _getMaxYValue(spots);
    final double average = spots.isNotEmpty
        ? spots.map((e) => e.y).reduce((a, b) => a + b) / spots.length
        : 0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          /// العنوان + الفلتر
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: appColors.dark,
                ),
              ),
              _buildTimeRangeSelector(),
            ],
          ),

          const SizedBox(height: 16),

          /// 👇 الرسم البياني
          SizedBox(
            height: 180,
            child: Row(
              children: [
                /// الرسم البياني أولاً (على اليمين في RTL)
                Expanded(
                  child: spots.isEmpty
                      ? const Center(child: Text('لا توجد بيانات'))
                      : LineChart(
                          LineChartData(
                            minY: 0,
                            maxY: maxY == 0 ? 10 : maxY * 1.1,
                            gridData: FlGridData(
                              show: true,
                              drawVerticalLine: false,
                              horizontalInterval: maxY == 0
                                  ? 1
                                  : (maxY / 3).ceilToDouble(),
                            ),
                            titlesData: FlTitlesData(
                              show: true,
                              topTitles: const AxisTitles(
                                sideTitles: SideTitles(showTitles: false),
                              ),
                              rightTitles: const AxisTitles(
                                sideTitles: SideTitles(showTitles: false),
                              ),

                              /// محور Y الأيسر (الأرقام)
                              leftTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  reservedSize: 30,
                                  interval: maxY == 0 ? 1 : (maxY / 3),
                                  getTitlesWidget: (value, meta) {
                                    // 🔥 لا تعرض الصفر
                                    if (value.abs() < 0.0001) {
                                      return const SizedBox.shrink();
                                    }

                                    final third = maxY / 3;
                                    final twoThird = maxY * 2 / 3;

                                    // 🔥 مقارنة آمنة للـ double
                                    bool isMatch(double a, double b) =>
                                        (a - b).abs() < 0.0001;

                                    if (isMatch(value, maxY) ||
                                        isMatch(value, twoThird) ||
                                        isMatch(value, third)) {
                                      return Padding(
                                        padding: const EdgeInsets.only(
                                          right: 4,
                                        ),
                                        child: Text(
                                          value < 1
                                              ? value.toStringAsFixed(
                                                  1,
                                                ) // لو رقم صغير
                                              : value
                                                    .toInt()
                                                    .toString(), // لو رقم عادي
                                          style: const TextStyle(
                                            fontSize: 9,
                                            color: Colors.grey,
                                            fontWeight: FontWeight.w500,
                                          ),
                                          textAlign: TextAlign.right,
                                        ),
                                      );
                                    }

                                    return const SizedBox.shrink();
                                  },
                                ),
                              ),

                              /// محور X السفلي
                              bottomTitles: AxisTitles(
                                axisNameWidget: Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(
                                    _getXAxisLabel(),
                                    style: GoogleFonts.ibmPlexSansArabic(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.grey[700],
                                    ),
                                  ),
                                ),
                                axisNameSize: 25,
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  reservedSize: 25,
                                  interval: _getInterval(),
                                  getTitlesWidget: (value, meta) {
                                    return Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: _buildXAxisTitle(value, meta),
                                    );
                                  },
                                ),
                              ),
                            ),
                            borderData: FlBorderData(
                              show: true,
                              border: Border.all(
                                color: Colors.grey[300]!,
                                width: 1,
                              ),
                            ),
                            lineBarsData: [
                              LineChartBarData(
                                spots: spots,
                                isCurved: true,
                                barWidth: 2.5,
                                color: color,
                                dotData: const FlDotData(show: false),
                                belowBarData: BarAreaData(
                                  show: true,
                                  color: color.withOpacity(.15),
                                ),
                              ),
                            ],
                            lineTouchData: LineTouchData(
                              enabled: true,
                              touchTooltipData: LineTouchTooltipData(
                                tooltipBgColor: color,
                                getTooltipItems: (spots) {
                                  return spots.map((spot) {
                                    return LineTooltipItem(
                                      '${spot.y.toInt()}',
                                      const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 10,
                                      ),
                                    );
                                  }).toList();
                                },
                              ),
                            ),
                          ),
                        ),
                ),

                /// مسافة بين الرسم والـ Label
                const SizedBox(width: 1),

                /// 🏷️ Label Y على اليمين (في RTL)
                Center(
                  child: RotatedBox(
                    quarterTurns: 3,
                    child: Text(
                      'القيمة',
                      style: GoogleFonts.ibmPlexSansArabic(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[700],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),
          _buildRangeNavigator(),

          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildCompactMiniStat(
                  'الإجمالي',
                  spots.isNotEmpty
                      ? spots
                            .map((e) => e.y)
                            .reduce((a, b) => a + b)
                            .toStringAsFixed(1)
                      : '0',
                ),
                _buildCompactMiniStat('المتوسط', average.toStringAsFixed(1)),
                _buildCompactMiniStat('الأعلى', maxY.toInt().toString()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // دالة مساعدة لحساب القيمة القصوى
  double _getMaxYValue(List<FlSpot> spots) {
    if (spots.isEmpty) return 100;

    double maxY = spots[0].y;
    for (final spot in spots) {
      if (spot.y > maxY) {
        maxY = spot.y;
      }
    }
    return maxY;
  }

  double _carbonTarget = 1000.0; // القيمة الافتراضية
  final TextEditingController _targetController = TextEditingController();

  void _openTargetForm() {
    _targetController.text = _carbonTarget.toStringAsFixed(0);

    showDialog(context: context, builder: (context) => _buildTargetPopup());
  }

  void _saveTarget() {
    final newTarget = double.tryParse(_targetController.text);
    if (newTarget != null && newTarget > 0) {
      setState(() {
        _carbonTarget = newTarget;
      });

      // إغلاق البوب أب
      Navigator.of(context).pop();

      // حفظ في Firebase (اختياري)
      _saveTargetToFirebase(newTarget);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم تحديث الهدف إلى ${newTarget.toInt()} كجم'),
          backgroundColor: Colors.teal,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('الرجاء إدخال قيمة صحيحة'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _loadTargetFromFirebase() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('appSettings') // ← هذا المسار الصحيح
          .doc('carbonTarget')
          .get();

      if (doc.exists) {
        final target = (doc.data()?['target'] as num?)?.toDouble();
        if (target != null && target > 0) {
          setState(() => _carbonTarget = target);
        }
      }
    } catch (e) {
      debugPrint('⚠️ Could not load carbon target: $e');
    }
  }

  Future<void> _saveTargetToFirebase(double target) async {
    await FirebaseFirestore.instance
        .collection('appSettings') // ← هذا المسار الصحيح
        .doc('carbonTarget')
        .set({
          'target': target,
          'updatedAt': FieldValue.serverTimestamp(),
          'updatedBy': 'admin_manual',
        }, SetOptions(merge: true));
  }

  Widget _buildCarbonOverviewCard({
    required num totalCarbon,
    required List<FlSpot> carbonSpots,
  }) {
    final progress = (totalCarbon / _carbonTarget).clamp(0.0, 1.0);

    return Column(
      children: [
        // الجزء العلوي - بطاقة الإجمالي
        GestureDetector(
          onTap: () {
            setState(() {
              _isCarbonExpanded = !_isCarbonExpanded;
            });
          },
          child: Stack(
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.withOpacity(0.12),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    // 👇 دائرة التقدم مع إمكانية الضغط لتحديد الهدف
                    GestureDetector(
                      onTap: _openTargetForm,
                      child: SizedBox(
                        width: 56,
                        height: 56,
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: Padding(
                                padding: const EdgeInsets.all(4),
                                child: CircularProgressIndicator(
                                  value: progress,
                                  strokeWidth: 5,
                                  backgroundColor: Colors.teal.withOpacity(0.2),
                                  color: Colors.teal,
                                ),
                              ),
                            ),
                            Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    '${(progress * 100).toStringAsFixed(0)}%',
                                    style: GoogleFonts.ibmPlexSansArabic(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.teal,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'هدف',
                                    style: GoogleFonts.ibmPlexSansArabic(
                                      fontSize: 8,
                                      color: Colors.teal.withOpacity(0.7),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(width: 12),

                    // 📄 النص والمعلومات
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'توفير الكربون',
                            style: GoogleFonts.ibmPlexSansArabic(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: appColors.dark,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${totalCarbon.toStringAsFixed(1)} كجم / ${_carbonTarget.toInt()} كجم',
                            style: GoogleFonts.ibmPlexSansArabic(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey[700],
                            ),
                          ),
                          const SizedBox(height: 4),
                          LinearProgressIndicator(
                            value: progress,
                            backgroundColor: Colors.grey[200],
                            color: Colors.teal,
                            borderRadius: BorderRadius.circular(10),
                            minHeight: 4,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // السهم في الزاوية اليمين العليا
              Positioned(
                top: 8,
                left: 8,
                child: Icon(
                  _isCarbonExpanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  color: Colors.teal,
                  size: 18,
                ),
              ),
            ],
          ),
        ),

        // الجزء السفلي - الرسم البياني (يظهر فقط عند التوسيع)
        if (_isCarbonExpanded) ...[
          const SizedBox(height: 8),
          _buildExpandedCarbonChart(carbonSpots),
        ],
      ],
    );
  }

  // أضف دالة لعرض فورم تحديد الهدف
  Widget _buildTargetPopup() {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: Colors.white,
      child: Container(
        width: MediaQuery.of(context).size.width * 0.95,
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    'تحديد هدف الكربون',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: appColors.dark,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, size: 20),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),

            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.teal.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.teal.withOpacity(0.2)),
              ),
              child: Row(
                children: [
                  Icon(Icons.flag, color: Colors.teal, size: 18),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'الهدف الحالي: ${_carbonTarget.toInt()} كجم',
                      style: GoogleFonts.ibmPlexSansArabic(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: Colors.teal,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),
            TextField(
              controller: _targetController,
              keyboardType: TextInputType.number,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'الهدف الجديد',
                labelStyle: GoogleFonts.ibmPlexSansArabic(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
                hintText: 'إدخال قيمة بالكيلوجرام',
                hintStyle: GoogleFonts.ibmPlexSansArabic(
                  fontSize: 12.5,
                  color: Colors.grey[500],
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.teal, width: 2),
                ),
                prefixIcon: const Icon(
                  Icons.edit,
                  color: Colors.teal,
                  size: 20,
                ),
                suffixText: 'كجم',
                suffixStyle: GoogleFonts.ibmPlexSansArabic(
                  color: Colors.teal,
                  fontWeight: FontWeight.w600,
                  fontSize: 12.5,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
              ),
              style: GoogleFonts.ibmPlexSansArabic(
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
                color: appColors.dark,
              ),
            ),

            const SizedBox(height: 28),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      side: BorderSide(color: Colors.grey[400]!),
                    ),
                    child: Text(
                      'إلغاء',
                      style: GoogleFonts.ibmPlexSansArabic(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[700],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _saveTarget,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      'حفظ',
                      style: GoogleFonts.ibmPlexSansArabic(
                        fontSize: 13.5,
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
  }

  // دالة مساعدة لعرض الرسم البياني الموسع
  Widget _buildExpandedCarbonChart(List<FlSpot> carbonSpots) {
    final double maxY = _getMaxYValue(carbonSpots);
    final double average = carbonSpots.isNotEmpty
        ? carbonSpots.map((e) => e.y).reduce((a, b) => a + b) /
              carbonSpots.length
        : 0;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          /// العنوان + الفلتر
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'تطور توفير الكربون',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: appColors.dark,
                  ),
                ),

                /// ✅ استخدام _buildTimeRangeSelector مباشرة
                _buildTimeRangeSelector(),
              ],
            ),
          ),

          const SizedBox(height: 8),

          /// 👇 الرسم البياني مع Label ي مثل _buildBarChartCard
          SizedBox(
            height: 170,
            child: Row(
              children: [
                /// الرسم البياني أولاً
                Expanded(
                  child: carbonSpots.isEmpty
                      ? const Center(child: Text('لا توجد بيانات'))
                      : BarChart(
                          BarChartData(
                            minY: 0,
                            maxY: maxY == 0 ? 10 : maxY * 1.1,
                            gridData: FlGridData(
                              show: true,
                              drawVerticalLine: false,
                              horizontalInterval: maxY == 0
                                  ? 1
                                  : (maxY / 3).ceilToDouble(),
                            ),
                            titlesData: FlTitlesData(
                              show: true,
                              topTitles: const AxisTitles(
                                sideTitles: SideTitles(showTitles: false),
                              ),
                              rightTitles: const AxisTitles(
                                sideTitles: SideTitles(showTitles: false),
                              ),

                              /// محور Y الأيسر (الأرقام)
                              leftTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  reservedSize: 30,
                                  interval: maxY == 0 ? 1 : (maxY / 3),
                                  getTitlesWidget: (value, meta) {
                                    // عرض فقط القيم التي تطابق maxY, maxY*2/3, maxY/3
                                    if (value == maxY ||
                                        value == maxY * 2 / 3 ||
                                        value == maxY / 3) {
                                      return Padding(
                                        padding: const EdgeInsets.only(
                                          right: 4,
                                        ),
                                        child: Text(
                                          value.toInt().toString(),
                                          style: const TextStyle(
                                            fontSize: 9,
                                            color: Colors.grey,
                                            fontWeight: FontWeight.w500,
                                          ),
                                          textAlign: TextAlign.right,
                                        ),
                                      );
                                    }

                                    // إخفاء باقي القيم بما في ذلك الصفر
                                    return const SizedBox.shrink();
                                  },
                                ),
                              ),

                              /// محور X السفلي
                              bottomTitles: AxisTitles(
                                axisNameWidget: Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(
                                    _getXAxisLabel(),
                                    style: GoogleFonts.ibmPlexSansArabic(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.grey[700],
                                    ),
                                  ),
                                ),
                                axisNameSize: 25,
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  reservedSize: 25,
                                  interval: _getInterval(),
                                  getTitlesWidget: (value, meta) {
                                    return Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: _buildXAxisTitle(value, meta),
                                    );
                                  },
                                ),
                              ),
                            ),
                            borderData: FlBorderData(
                              show: true,
                              border: Border.all(
                                color: Colors.grey[300]!,
                                width: 0.5,
                              ),
                            ),
                            barGroups: carbonSpots.asMap().entries.map((entry) {
                              int index = entry.key;
                              FlSpot spot = entry.value;

                              return BarChartGroupData(
                                x: index,
                                barRods: [
                                  BarChartRodData(
                                    toY: spot.y,
                                    width: _getBarWidth(_selectedTimeRange),
                                    borderRadius: BorderRadius.circular(4),
                                    color: spot.y > 0
                                        ? Colors.teal
                                        : Colors.grey[300]!,
                                  ),
                                ],
                              );
                            }).toList(),
                            barTouchData: BarTouchData(
                              enabled: true,
                              touchTooltipData: BarTouchTooltipData(
                                tooltipBgColor: appColors.primary,
                                getTooltipItem:
                                    (group, groupIndex, rod, rodIndex) {
                                      // إذا كان عندنا بيانات التصنيفات
                                      if (_taskBarGroups.isNotEmpty &&
                                          group.barRods.length > 1) {
                                        // نحتاج لمعرفة أي تصنيف يمثله هذا الشريط
                                        // للتبسيط، نعرض القيمة فقط
                                        return BarTooltipItem(
                                          '${rod.toY.toInt()}',
                                          const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 10,
                                          ),
                                        );
                                      } else {
                                        return BarTooltipItem(
                                          '${rod.toY.toInt()} مهمة',
                                          const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 10,
                                          ),
                                        );
                                      }
                                    },
                              ),
                            ),
                          ),
                        ),
                ),

                /// مسافة بين الرسم والـ Label
                const SizedBox(width: 1),

                /// 🏷️ Label Y على اليمين (في RTL)
                Center(
                  child: RotatedBox(
                    quarterTurns: 3,
                    child: Text(
                      'القيمة',
                      style: GoogleFonts.ibmPlexSansArabic(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[700],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),
          _buildRangeNavigator(),

          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildCompactMiniStat(
                  'الإجمالي',
                  carbonSpots.isNotEmpty
                      ? '${carbonSpots.map((e) => e.y).reduce((a, b) => a + b).toStringAsFixed(1)} كجم'
                      : '0 كجم',
                ),
                _buildCompactMiniStat(
                  'المتوسط',
                  '${average.toStringAsFixed(1)} كجم',
                ),
                _buildCompactMiniStat(
                  'الأعلى',
                  '${_getMaxYValue(carbonSpots).toInt()} كجم',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  @override
  Widget build(BuildContext context) {
    final isKeyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;
    final baseTheme = Theme.of(context);
    final textTheme = GoogleFonts.ibmPlexSansArabicTextTheme(
      baseTheme.textTheme,
    );

    final user = FirebaseAuth.instance.currentUser;
    final Stream<DocumentSnapshot<Map<String, dynamic>>>? userStream =
        (user == null)
        ? null
        : FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .snapshots();

    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Theme(
        data: baseTheme.copyWith(
          textTheme: textTheme,
          scaffoldBackgroundColor: Colors.transparent,
        ),
        child: Scaffold(
          extendBody: false,
          backgroundColor: appColors.background,
          body: AnimatedBackgroundContainer(
            child: Column(
              children: [
                // ✅ الجزء الثابت (البروفايل والأيقونات) - بدون scroll
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // StreamBuilder حق الترحيب
                      // StreamBuilder حق الترحيب
                      StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                        stream: userStream,
                        builder: (context, snap) {
                          final isLoading =
                              snap.connectionState == ConnectionState.waiting;
                          final data = snap.data?.data();

                          final String displayName = isLoading
                              ? '...'
                              : (data?['username']
                                            ?.toString()
                                            .trim()
                                            .isNotEmpty ==
                                        true
                                    ? data!['username'].toString()
                                    : (user?.displayName?.trim().isNotEmpty ==
                                              true
                                          ? user!.displayName!
                                          : (user?.email ?? 'مستخدم')));

                          int? pfpIndex;
                          if (data?['pfpIndex'] is int) {
                            pfpIndex = data!['pfpIndex'] as int;
                          } else if (data?['pfpIndex'] != null) {
                            pfpIndex = int.tryParse(
                              data!['pfpIndex'].toString(),
                            );
                          }
                          String? avatarPath;
                          if (pfpIndex != null &&
                              pfpIndex >= 0 &&
                              pfpIndex < 8) {
                            avatarPath = 'assets/pfp/pfp${pfpIndex + 1}.png';
                          }

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Container(
                                    width: 46,
                                    height: 46,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      gradient: LinearGradient(
                                        colors: [
                                          appColors.primary.withOpacity(.2),
                                          appColors.sea.withOpacity(.1),
                                        ],
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: appColors.primary.withOpacity(
                                            .2,
                                          ),
                                          blurRadius: 12,
                                          offset: const Offset(0, 4),
                                        ),
                                      ],
                                    ),
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(999),
                                      onTap: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => const profilePage(),
                                          ),
                                        );
                                      },
                                      child: CircleAvatar(
                                        backgroundColor: Colors.transparent,
                                        radius: 23,
                                        backgroundImage:
                                            (avatarPath != null && !isLoading)
                                            ? AssetImage(avatarPath)
                                            : null,
                                        child: (avatarPath == null || isLoading)
                                            ? const Icon(
                                                Icons.person_outline,
                                                color: appColors.primary,
                                                size: 26,
                                              )
                                            : null,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),

                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      RichText(
                                        text: TextSpan(
                                          children: [
                                            TextSpan(
                                              text: "مرحباً، ",
                                              style:
                                                  GoogleFonts.ibmPlexSansArabic(
                                                    fontSize: 20,
                                                    fontWeight: FontWeight.w800,
                                                    color: appColors.dark,
                                                  ),
                                            ),
                                            TextSpan(
                                              text: displayName,
                                              style:
                                                  GoogleFonts.ibmPlexSansArabic(
                                                    fontSize: 20,
                                                    fontWeight: FontWeight.w800,
                                                    color: appColors.dark,
                                                  ),
                                            ),
                                            const TextSpan(text: " 👋"),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        "لوحة تحكم متكاملة للنظام",
                                        style: GoogleFonts.ibmPlexSansArabic(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: appColors.sea,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 16),

                      // أيقونات سريعة
                      Row(
                        children: [
                          Expanded(
                            child: _buildQuickIcon(
                              icon: Icons.dashboard_outlined,
                              label: 'نشاط المستخدمين',
                              color: appColors.primary,
                              isSelected: _selectedQuickIconIndex == 0,
                              onTap: () {
                                if (_selectedQuickIconIndex == 1 &&
                                    _isInReportsTab) {
                                  _markAllReportsAsRead();
                                }
                                setState(() {
                                  _selectedQuickIconIndex = 0;
                                  _isInReportsTab = false;
                                });
                              },
                            ),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: FutureBuilder<int>(
                              future: _getTotalReportsCount(),
                              builder: (context, snapshot) {
                                final totalCount = snapshot.data ?? 0;
                                return _buildQuickIconWithBadge(
                                  icon: Icons.report_outlined,
                                  label: 'البلاغات',
                                  color: appColors.accent,
                                  badgeCount: totalCount,
                                  isSelected: _selectedQuickIconIndex == 1,
                                  onTap: () {
                                    if (_selectedQuickIconIndex != 1) {
                                      setState(() {
                                        _selectedQuickIconIndex = 1;
                                        _isInReportsTab = true;
                                      });
                                    }
                                  },
                                );
                              },
                            ),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: _buildQuickIcon(
                              icon: Icons.lightbulb_outline,
                              label: 'التوصيات',
                              color: appColors.primary,
                              isSelected: _selectedQuickIconIndex == 2,
                              onTap: () {
                                if (_selectedQuickIconIndex == 1 &&
                                    _isInReportsTab) {
                                  _markAllReportsAsRead();
                                }
                                setState(() {
                                  _selectedQuickIconIndex = 2;
                                  _isInReportsTab = false;
                                });
                                _loadAdminRecommendations();
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),

                // ✅ المحتوى الرئيسي - مع Expanded لملء المساحة
                Expanded(
                  child: IndexedStack(
                    index: _selectedQuickIconIndex,
                    children: [
                      _buildDashboardContent(),
                      _buildReportsContent(),
                      _buildRecommendationsContent(),
                    ],
                  ),
                ),
              ],
            ),
          ),
          bottomNavigationBar: isKeyboardOpen
              ? null
              : AdminBottomNav(currentIndex: _currentIndex, onTap: _onTap),
        ),
      ),
    );
  }

  void _markAllReportsAsRead() async {
    print('📝 تحديث جميع البلاغات كمقروءة...');

    // تحديث بلاغات المهام
    final taskReports = await FirebaseFirestore.instance
        .collection('taskReports')
        .where('decision', isEqualTo: 'pending')
        .get();

    for (final doc in taskReports.docs) {
      if (_viewedTaskReports[doc.id] == false) {
        setState(() {
          _viewedTaskReports[doc.id] = true;
        });
      }
    }

    // تحديث بلاغات الحاويات
    final containerReports = await FirebaseFirestore.instance
        .collection('facilityReports')
        .where('status', isEqualTo: 'pending')
        .get();

    for (final doc in containerReports.docs) {
      if (_viewedContainerReports[doc.id] == false) {
        setState(() {
          _viewedContainerReports[doc.id] = true;
        });
      }
    }

    // إعادة تحميل العدادات
    _getTotalReportsCount();

    print('✅ تم تحديث جميع البلاغات كمقروءة');
  }

  // ================== دوال المحتوى المتغير ==================
  Widget _buildDashboardContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      physics: const AlwaysScrollableScrollPhysics(),
      child: Column(
        children: [
          const SizedBox(height: 26),
          FutureBuilder<Map<String, dynamic>>(
            future: _getUsersData(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting &&
                  !_cachedUsersData.containsKey('totalCarbon')) {
                return _buildCarbonShimmer();
              }
              final totalCarbon =
                  snapshot.data?['totalCarbon'] ??
                  _cachedUsersData['totalCarbon'] ??
                  0;
              return _buildCarbonOverviewCard(
                totalCarbon: totalCarbon,
                carbonSpots: _carbonSpots,
              );
            },
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 400,
            child: Column(
              children: [
                Expanded(
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      PageView(
                        controller: _dashboardPageController,
                        onPageChanged: (index) {
                          setState(() {
                            _dashboardPageIndex = index;
                          });
                        },
                        children: [
                          _buildBarChartCard(
                            'إكمال المهام',
                            _taskCompletionSpots,
                            appColors.sea,
                            _selectedTimeRange,
                          ),
                          _buildChartCard(
                            'تراكم النقاط',
                            _pointsSpots,
                            appColors.accent,
                            _selectedTimeRange,
                          ),
                          _buildChartCard(
                            'نمو المستخدمين',
                            _userGrowthSpots,
                            appColors.primary,
                            _selectedTimeRange,
                          ),
                        ],
                      ),

                      // السهم الموجود يمين الشاشة
                      Positioned(
                        right: 6,
                        child: _buildDashboardArrow(
                          icon: Icons.chevron_left_rounded,
                          isEnabled: _dashboardPageIndex > 0,
                          onTap: () {
                            if (_dashboardPageIndex > 0) {
                              _dashboardPageController.previousPage(
                                duration: const Duration(milliseconds: 300),
                                curve: Curves.easeOut,
                              );
                            }
                          },
                        ),
                      ),

                      // السهم الموجود يسار الشاشة
                      Positioned(
                        left: 6,
                        child: _buildDashboardArrow(
                          icon: Icons.chevron_right_rounded,
                          isEnabled: _dashboardPageIndex < 2,
                          onTap: () {
                            if (_dashboardPageIndex < 2) {
                              _dashboardPageController.nextPage(
                                duration: const Duration(milliseconds: 300),
                                curve: Curves.easeOut,
                              );
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 8),

                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(3, (index) {
                    final isSelected = _dashboardPageIndex == index;

                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: isSelected ? 18 : 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: isSelected
                            ? appColors.primary
                            : appColors.primary.withOpacity(0.25),
                        borderRadius: BorderRadius.circular(20),
                      ),
                    );
                  }),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _buildLeaderboardCard(),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildDashboardArrow({
    required IconData icon,
    required bool isEnabled,
    required VoidCallback onTap,
  }) {
    return IgnorePointer(
      ignoring: !isEnabled,
      child: AnimatedOpacity(
        opacity: isEnabled ? 1 : 0.25,
        duration: const Duration(milliseconds: 200),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.95),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.10),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Icon(icon, color: appColors.primary, size: 21),
          ),
        ),
      ),
    );
  }

  // ✅ دالة مساعدة لشimmer الكربون
  Widget _buildCarbonShimmer() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: Colors.grey[200],
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(width: 100, height: 16, color: Colors.grey[200]),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  height: 8,
                  color: Colors.grey[200],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReportsContent() {
    if (_selectedQuickIconIndex == 1 && !_isInReportsTab) {
      _isInReportsTab = true;
    }

    return Column(
      children: [
        // تبويبات البلاغات
        Container(
          margin: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(30),
          ),
          child: Row(
            children: [
              Expanded(
                child: _buildReportTab(
                  label: 'بلاغات المهام',
                  count: _unreadTaskReports,
                  isSelected: _selectedReportsTab == 0,
                  onTap: () => setState(() => _selectedReportsTab = 0),
                ),
              ),
              Expanded(
                child: _buildReportTab(
                  label: 'بلاغات الحاويات',
                  count: _unreadContainerReports,
                  isSelected: _selectedReportsTab == 1,
                  onTap: () => setState(() => _selectedReportsTab = 1),
                ),
              ),
            ],
          ),
        ),

        // المحتوى - مع Expanded
        Expanded(
          child: IndexedStack(
            index: _selectedReportsTab,
            children: [_buildTaskReportsView(), _buildContainerReportsView()],
          ),
        ),
      ],
    );
  }

  Widget _buildReportTab({
    required String label,
    required int count,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? appColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(30),
        ),
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: GoogleFonts.ibmPlexSansArabic(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? Colors.white : Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTaskReportsView() {
    // إنشاء future جديد فقط إذا كان فارغاً
    _taskReportsFuture ??= _getTaskReports();

    return FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
      future: _taskReportsFuture,
      builder: (context, snapshot) {
        // حالة التحميل
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        // حالة الخطأ
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline, color: Colors.red, size: 48),
                const SizedBox(height: 12),
                Text('حدث خطأ في تحميل البلاغات'),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _taskReportsFuture = null;
                    });
                  },
                  child: const Text('إعادة المحاولة'),
                ),
              ],
            ),
          );
        }

        final allReports = snapshot.data?.docs ?? [];

        // فصل البلاغات الجديدة (غير المقروءة) عن القديمة
        final newReports = allReports.where((doc) {
          return !(_viewedTaskReports[doc.id] ?? false);
        }).toList();

        final oldReports = allReports.where((doc) {
          return _viewedTaskReports[doc.id] ?? false;
        }).toList();

        // لا توجد بلاغات نهائياً
        if (allReports.isEmpty) {
          return Container(
            width: double.infinity,
            height:
                MediaQuery.of(context).size.height *
                0.4, // ارتفاع ثابت 40% من الشاشة
            child: Column(
              mainAxisAlignment:
                  MainAxisAlignment.spaceBetween, // يوزع المسافة بين العناصر
              children: [
                // الجزء العلوي (الأيقونة والنصوص)
                Column(
                  children: [
                    Icon(
                      Icons.check_circle_outline,
                      size: 48,
                      color: Colors.green[400],
                    ),
                    const SizedBox(height: 16),
                    Text('لا توجد بلاغات مهام'),
                    const SizedBox(height: 8),
                    Text('كل البلاغات تمت معالجتها'),
                  ],
                ),

                // الزر في الأسفل
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: FilledButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const AdminTaskReportsPage(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.list_alt),
                    label: Text(
                      'عرض جميع البلاغات',
                      style: GoogleFonts.ibmPlexSansArabic(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: appColors.primary,
                      minimumSize: const Size(double.infinity, 48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 20), // مسافة إضافية في الأسفل
              ],
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            children: [
              // عنوان بعدد البلاغات الجديدة
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Row(
                  children: [
                    Text(
                      'البلاغات الجديدة',
                      style: GoogleFonts.ibmPlexSansArabic(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: appColors.dark,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: appColors.accent,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${newReports.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // قائمة البلاغات الجديدة
              if (newReports.isNotEmpty)
                Expanded(
                  flex: 3,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: newReports.length,
                    itemBuilder: (context, index) {
                      final doc = newReports[index];
                      final report = doc.data();
                      final createdAt = report['createdAt'] as Timestamp?;

                      return _buildTaskReportCard(
                        report: report,
                        reportId: doc.id,
                        createdAt: createdAt,
                        isNew: true,
                        onTap: () {
                          // تحديث حالة المشاهدة عند النقر فقط
                          if (_viewedTaskReports[doc.id] == false) {
                            setState(() {
                              _viewedTaskReports[doc.id] = true;
                            });
                          }
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const AdminTaskReportsPage(),
                            ),
                          );
                        },
                      );
                    },
                  ),
                )
              else
                Expanded(
                  flex: 2,
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.check_circle_outline,
                          size: 40,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'لا توجد بلاغات جديدة',
                          style: GoogleFonts.ibmPlexSansArabic(
                            color: Colors.grey[500],
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              const SizedBox(height: 16),

              // ✅ زر "جميع البلاغات" يظهر دائماً في الأسفل
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: FilledButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const AdminTaskReportsPage(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.list_alt),
                  label: Text(
                    oldReports.isNotEmpty
                        ? 'عرض جميع البلاغات (${oldReports.length})'
                        : 'عرض جميع البلاغات',
                    style: GoogleFonts.ibmPlexSansArabic(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: appColors.primary,
                    minimumSize: const Size(double.infinity, 48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // دالة مساعدة لبناء كارد البلاغ (بنفس التصميم الأصلي)
  Widget _buildTaskReportCard({
    required Map<String, dynamic> report,
    required String reportId,
    required Timestamp? createdAt,
    required bool isNew,
    required VoidCallback onTap,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shadowColor: Colors.black.withOpacity(0.05),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isNew ? appColors.accent : Colors.grey[300]!,
          width: isNew ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // أيقونة البلاغ مع لون مختلف للجديد
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: isNew
                      ? appColors.accent.withOpacity(0.1)
                      : Colors.grey[100],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.assignment_late,
                  color: isNew ? appColors.accent : Colors.grey[600],
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),

              // محتوى البلاغ
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            report['taskTitle'] ?? 'مهمة غير محددة',
                            style: GoogleFonts.ibmPlexSansArabic(
                              fontSize: 15,
                              fontWeight: isNew
                                  ? FontWeight.w700
                                  : FontWeight.w600,
                              color: isNew ? appColors.dark : Colors.grey[700],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isNew)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: appColors.accent,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              'جديد',
                              style: GoogleFonts.ibmPlexSansArabic(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: isNew
                            ? appColors.accent.withOpacity(0.1)
                            : Colors.grey[100],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'سبب البلاغ: ${report['reason'] ?? 'غير محدد'}',
                        style: GoogleFonts.ibmPlexSansArabic(
                          fontSize: 12,
                          color: isNew ? appColors.accent : Colors.grey[600],
                        ),
                      ),
                    ),
                    if (createdAt != null) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(
                            Icons.access_time,
                            size: 12,
                            color: Colors.grey[500],
                          ),
                          const SizedBox(width: 4),
                          Text(
                            DateFormat(
                              'dd/MM/yyyy hh:mm a',
                            ).format(createdAt.toDate()),
                            style: GoogleFonts.ibmPlexSansArabic(
                              fontSize: 11,
                              color: Colors.grey[500],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(Icons.chevron_left, color: appColors.accent, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContainerReportsView() {
    _containerReportsFuture ??= _getContainerReports();

    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _containerReportsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline, color: Colors.red, size: 48),
                const SizedBox(height: 12),
                Text('حدث خطأ في تحميل البلاغات'),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _containerReportsFuture = null;
                    });
                  },
                  child: const Text('إعادة المحاولة'),
                ),
              ],
            ),
          );
        }

        final allReports = snapshot.data ?? [];

        // فصل البلاغات الجديدة (غير المقروءة) عن القديمة
        final newReports = allReports.where((report) {
          final reportId = report['id'];
          return !(_viewedContainerReports[reportId] ?? false);
        }).toList();

        final oldReports = allReports.where((report) {
          final reportId = report['id'];
          return _viewedContainerReports[reportId] ?? false;
        }).toList();
        // لا توجد بلاغات نهائياً
        if (allReports.isEmpty) {
          return Container(
            width: double.infinity,
            height:
                MediaQuery.of(context).size.height *
                0.45, // ارتفاع ثابت 45% من الشاشة
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // الجزء العلوي (الدائرة والنصوص)
                Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.check_circle_outline,
                        size: 48,
                        color: Colors.green[400],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'لا توجد بلاغات حاويات',
                      style: GoogleFonts.ibmPlexSansArabic(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'كل البلاغات تمت معالجتها',
                      style: GoogleFonts.ibmPlexSansArabic(
                        fontSize: 14,
                        color: Colors.grey[500],
                      ),
                    ),
                  ],
                ),

                // الزر في الأسفل
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: FilledButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              const containerReports.AdminReportPage(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.list_alt),
                    label: Text(
                      'عرض جميع البلاغات',
                      style: GoogleFonts.ibmPlexSansArabic(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: appColors.primary,
                      minimumSize: const Size(double.infinity, 48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 20), // مسافة في الأسفل
              ],
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            children: [
              // عنوان بعدد البلاغات الجديدة
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Row(
                  children: [
                    Text(
                      'البلاغات الجديدة',
                      style: GoogleFonts.ibmPlexSansArabic(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: appColors.dark,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: appColors.accent,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${newReports.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // قائمة البلاغات الجديدة
              if (newReports.isNotEmpty)
                Expanded(
                  flex: 3,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: newReports.length,
                    itemBuilder: (context, index) {
                      final report = newReports[index];

                      return _buildContainerReportCard(
                        report: report,
                        isNew: true,
                        onTap: () {
                          // تحديث حالة المشاهدة عند النقر فقط
                          if (_viewedContainerReports[report['id']] == false) {
                            setState(() {
                              _viewedContainerReports[report['id']] = true;
                            });
                          }
                          // فتح صفحة التفاصيل
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  const containerReports.AdminReportPage(),
                            ),
                          );
                        },
                      );
                    },
                  ),
                )
              else
                Expanded(
                  flex: 2,
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.check_circle_outline,
                          size: 40,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'لا توجد بلاغات جديدة',
                          style: GoogleFonts.ibmPlexSansArabic(
                            color: Colors.grey[500],
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              const SizedBox(height: 16),

              // ✅ زر "جميع البلاغات" يظهر دائماً في الأسفل
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: FilledButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            const containerReports.AdminReportPage(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.list_alt),
                  label: Text(
                    oldReports.isNotEmpty
                        ? 'عرض جميع البلاغات (${oldReports.length})'
                        : 'عرض جميع البلاغات',
                    style: GoogleFonts.ibmPlexSansArabic(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: appColors.primary,
                    minimumSize: const Size(double.infinity, 48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildContainerReportCard({
    required Map<String, dynamic> report,
    required bool isNew,
    required VoidCallback onTap,
  }) {
    final createdAt = report['createdAt'] as Timestamp?;
    final status = report['status'] ?? 'pending';
    final reportId = report['id'];

    Color _statusColor(String s) {
      switch (s) {
        case 'pending':
          return Colors.orange;
        case 'approved':
          return Colors.green;
        case 'rejected':
          return Colors.red;
        default:
          return appColors.sea;
      }
    }

    String _statusLabel(String s) {
      switch (s) {
        case 'pending':
          return 'قيد المراجعة';
        case 'approved':
          return 'تمت المعالجة';
        case 'rejected':
          return 'مرفوض';
        default:
          return s;
      }
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shadowColor: Colors.black.withOpacity(0.05),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isNew ? appColors.accent : Colors.grey[300]!,
          width: isNew ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // أيقونة البلاغ مع لون مختلف للجديد
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: isNew
                      ? appColors.accent.withOpacity(0.1)
                      : Colors.grey[100],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.delete_outline,
                  color: isNew ? appColors.accent : Colors.grey[600],
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),

              // محتوى البلاغ
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            report['type'] ?? 'بلاغ حاوية',
                            style: GoogleFonts.ibmPlexSansArabic(
                              fontSize: 15,
                              fontWeight: isNew
                                  ? FontWeight.w700
                                  : FontWeight.w600,
                              color: isNew ? appColors.dark : Colors.grey[700],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isNew)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: appColors.accent,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              'جديد',
                              style: GoogleFonts.ibmPlexSansArabic(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    // حالة البلاغ
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: isNew
                            ? _statusColor(status).withOpacity(0.1) // ✅ status
                            : Colors.grey[100],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'الحالة: ${_statusLabel(status)}', // ✅ status
                        style: GoogleFonts.ibmPlexSansArabic(
                          fontSize: 12,
                          color: isNew
                              ? _statusColor(status)
                              : Colors.grey[600], // ✅ status
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    // وصف البلاغ
                    Text(
                      report['description'] ?? 'لا يوجد وصف',
                      style: GoogleFonts.ibmPlexSansArabic(
                        fontSize: 13,
                        color: Colors.grey[800],
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (createdAt != null) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(
                            Icons.access_time,
                            size: 12,
                            color: Colors.grey[500],
                          ),
                          const SizedBox(width: 4),
                          Text(
                            DateFormat(
                              'dd/MM/yyyy hh:mm a',
                            ).format(createdAt.toDate()),
                            style: GoogleFonts.ibmPlexSansArabic(
                              fontSize: 11,
                              color: Colors.grey[500],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(Icons.chevron_left, color: appColors.accent, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRecommendationsContent() {
    if (_isLoadingRecommendations) {
      return const Center(child: CircularProgressIndicator());
    }

    // تصفية التوصيات المخفية
    final visibleRecommendations = _adminRecommendations.where((rec) {
      final recId =
          rec['id'] ?? rec['taskId'] ?? 'rec_${rec['type']}_${rec['title']}';
      return !_hiddenRecommendations.contains(recId);
    }).toList();

    if (visibleRecommendations.isEmpty) {
      return Center(
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: _buildEmptyRecommendations(),
        ),
      );
    }

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(12),
      itemCount: visibleRecommendations.length,
      itemBuilder: (context, index) {
        return _buildRecommendationCard(
          visibleRecommendations[index],
          index,
          _taskCategories,
        );
      },
    );
  }

  // حالة عدم وجود توصيات
  Widget _buildEmptyRecommendations() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: appColors.primary.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.lightbulb_outline,
              size: 48,
              color: appColors.primary.withOpacity(0.5),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'لا توجد توصيات حالياً',
            style: GoogleFonts.ibmPlexSansArabic(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'سيتم إنشاء التوصيات قريباً',
            style: GoogleFonts.ibmPlexSansArabic(
              fontSize: 14,
              color: Colors.grey[500],
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _loadAdminRecommendations,
            icon: const Icon(Icons.refresh),
            label: Text(
              'تحديث',
              style: GoogleFonts.ibmPlexSansArabic(fontWeight: FontWeight.w600),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: appColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(30),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // أضف مع باقي المتغيرات
  bool _isProcessingRecommendation = false;

  // دالة لتسجيل تنفيذ التوصية في Firestore
  Future<void> _logRecommendationAction(
    Map<String, dynamic> rec,
    String action,
  ) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      await FirebaseFirestore.instance.collection('recommendationActions').add({
        'recommendationId': rec['id'] ?? rec['taskId'] ?? 'unknown',
        'recommendationType': rec['type'],
        'recommendationTitle': rec['title'],
        'action': action, // 'ignore', 'add', 'modify', 'delete', 'review'
        'userId': user.uid,
        'userEmail': user.email,
        'timestamp': FieldValue.serverTimestamp(),
        'metadata': {
          'category': rec['category'],
          'basedOn': rec['basedOn'],
          'taskId': rec['taskId'],
          'facilityId': rec['facilityId'],
          'reportCount': rec['reportCount'],
        },
      });

      print('✅ Logged recommendation action: $action');
    } catch (e) {
      print('❌ Error logging recommendation action: $e');
    }
  }

  Future<void> _hideRecommendation(String recId) async {
    if (_isProcessingRecommendation) return;
    _isProcessingRecommendation = true;

    setState(() {
      _hiddenRecommendations.add(recId);
      // أزيلي التوصية من القائمة مباشرة
      _adminRecommendations.removeWhere((rec) {
        final id =
            rec['id'] ?? rec['taskId'] ?? 'rec_${rec['type']}_${rec['title']}';
        return id == recId;
      });
    });

    await _prefs.setStringList(
      'hidden_recommendations',
      _hiddenRecommendations.toList(),
    );

    _isProcessingRecommendation = false;
  }

  Widget _buildRecommendationCard(
    Map<String, dynamic> rec,
    int index,
    List<String> categories,
  ) {
    // إنشاء ID فريد للتوصية
    final String recId =
        rec['id'] ?? rec['taskId'] ?? 'rec_${rec['type']}_${rec['title']}';

    // اختيار الأيقونة واللون حسب نوع التوصية
    IconData getIcon() {
      switch (rec['type']) {
        case 'add':
          return Icons.add_circle_outline;
        case 'delete':
          return Icons.delete_outline;
        case 'modify':
          return Icons.edit_outlined;
        case 'review_reports':
          // ✅ التحقق إذا كانت توصية حاوية أم مهمة
          if (rec.containsKey('facilityId') && rec['facilityId'] != null) {
            return Icons.delete_outline; // أيقونة حاوية
          }
          return Icons.report_outlined; // أيقونة مهمة
        default:
          return Icons.lightbulb_outline;
      }
    }

    Color getColor() {
      switch (rec['type']) {
        case 'add':
          return Colors.green;
        case 'delete':
          return Colors.red;
        case 'modify':
          return Colors.orange;
        case 'review_reports':
          return Colors.purple;
        default:
          return appColors.primary;
      }
    }

    String getTypeText() {
      switch (rec['type']) {
        case 'add':
          return 'إضافة مهمة';
        case 'delete':
          return 'حذف مهمة';
        case 'modify':
          return 'تعديل مهمة';
        case 'review_reports':
          // ✅ تمييز بين بلاغات المهام والحاويات
          if (rec.containsKey('facilityId') && rec['facilityId'] != null) {
            return 'بلاغات حاوية';
          }
          return 'بلاغات مهمة';
        default:
          return 'توصية';
      }
    }

    // ✅ دالة للحصول على وصف المهمة (لنوع add)
    String getUserDescription() {
      if (rec['type'] == 'add' && rec.containsKey('userDescription')) {
        return rec['userDescription']?.toString() ?? '';
      }
      return '';
    }

    // ✅ دالة للحصول على استراتيجية التحقق (لنوع add)
    String getValidationStrategy() {
      if (rec['type'] == 'add' && rec.containsKey('validationStrategy')) {
        return rec['validationStrategy']?.toString() ?? '';
      }
      return '';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shadowColor: Colors.black.withOpacity(0.05),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: getColor().withOpacity(0.3), width: 1),
      ),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [getColor().withOpacity(0.05), Colors.white],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // الصف العلوي: النوع + التصنيف
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: getColor().withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(getIcon(), color: getColor(), size: 18),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          getTypeText(),
                          style: GoogleFonts.ibmPlexSansArabic(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: getColor(),
                          ),
                        ),
                        if (rec['category'] != null)
                          Text(
                            rec['category']?.toString() ?? '',
                            style: GoogleFonts.ibmPlexSansArabic(
                              fontSize: 10,
                              color: Colors.grey[600],
                            ),
                          ),
                      ],
                    ),
                  ),
                  // ✅ مصدر التوصية (basedOn) - تأكد من وجوده
                  if (rec['basedOn'] != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        (rec['basedOn']?.toString() ?? 'تحليل').length > 15
                            ? '${rec['basedOn'].toString().substring(0, 15)}...'
                            : (rec['basedOn']?.toString() ?? 'تحليل'),
                        style: GoogleFonts.ibmPlexSansArabic(
                          fontSize: 8,
                          color: Colors.grey[600],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),

              const SizedBox(height: 8),

              // العنوان
              Text(
                rec['title'] ?? 'توصية',
                style: GoogleFonts.ibmPlexSansArabic(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: appColors.dark,
                ),
              ),

              const SizedBox(height: 4),

              // ✅ الوصف - موجود لجميع الأنواع
              if (rec['description'] != null &&
                  rec['description'].toString().isNotEmpty)
                Text(
                  rec['description']?.toString() ?? '',
                  style: GoogleFonts.ibmPlexSansArabic(
                    fontSize: 12,
                    color: Colors.grey[700],
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),

              // ✅ وصف المستخدم (لنوع add فقط)
              if (rec['type'] == 'add' && getUserDescription().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.description, size: 14, color: Colors.green),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            getUserDescription(),
                            style: GoogleFonts.ibmPlexSansArabic(
                              fontSize: 11,
                              color: Colors.green[700],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              const SizedBox(height: 8),

              // ✅ صندوق الاقتراح - موجود لجميع الأنواع
              if (rec['suggestion'] != null &&
                  rec['suggestion'].toString().isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: getColor().withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.lightbulb, size: 14, color: getColor()),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          rec['suggestion']?.toString() ?? '',
                          style: GoogleFonts.ibmPlexSansArabic(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: getColor(),
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              // ✅ الوصف المحسن (للتوصيات من نوع modify)
              if (rec['type'] == 'modify' &&
                  rec['improvedDescription'] != null &&
                  rec['improvedDescription'].toString().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.orange.withOpacity(0.3),
                        width: 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.auto_awesome,
                              size: 14,
                              color: Colors.orange,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'الوصف المحسن المقترح:',
                              style: GoogleFonts.ibmPlexSansArabic(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Colors.orange,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          rec['improvedDescription'].toString(),
                          style: GoogleFonts.ibmPlexSansArabic(
                            fontSize: 12,
                            color: Colors.orange.shade800,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 8),
                        // زر نسخ الوصف
                        GestureDetector(
                          onTap: () {
                            Clipboard.setData(
                              ClipboardData(
                                text: rec['improvedDescription'].toString(),
                              ),
                            );
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'تم نسخ الوصف ✅',
                                  style: GoogleFonts.ibmPlexSansArabic(),
                                ),
                                backgroundColor: Colors.orange,
                                duration: const Duration(seconds: 2),
                              ),
                            );
                          },
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.copy, size: 12, color: Colors.orange),
                              const SizedBox(width: 4),
                              Text(
                                'نسخ الوصف',
                                style: GoogleFonts.ibmPlexSansArabic(
                                  fontSize: 10,
                                  color: Colors.orange,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // ✅ معلومات إضافية للحاويات (نوع review_reports مع facilityId)
              if (rec['type'] == 'review_reports' &&
                  rec.containsKey('facilityId') &&
                  rec['facilityId'] != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    children: [
                      Icon(
                        Icons.location_on,
                        size: 12,
                        color: Colors.grey[500],
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          '${rec['facilityName'] ?? 'حاوية'} - ${rec['facilityAddress'] ?? 'عنوان غير معروف'}',
                          style: GoogleFonts.ibmPlexSansArabic(
                            fontSize: 10,
                            color: Colors.grey[600],
                          ),
                        ),
                      ),
                      if (rec['facilityIssueType'] != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            rec['facilityIssueType'].toString(),
                            style: GoogleFonts.ibmPlexSansArabic(
                              fontSize: 9,
                              color: Colors.red,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),

              // ✅ معلومات إضافية للمهام (نوع review_reports مع taskId)
              if (rec['type'] == 'review_reports' &&
                  rec.containsKey('taskId') &&
                  rec['taskId'] != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    children: [
                      Icon(Icons.task, size: 12, color: Colors.grey[500]),
                      const SizedBox(width: 4),
                      Text(
                        'المهمة: ${rec['taskId']}',
                        style: GoogleFonts.ibmPlexSansArabic(
                          fontSize: 10,
                          color: Colors.grey[600],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${rec['reportCount'] ?? 0} بلاغ',
                          style: GoogleFonts.ibmPlexSansArabic(
                            fontSize: 9,
                            color: Colors.orange,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 4),

              // أزرار سريعة
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  // زر تجاهل
                  TextButton.icon(
                    onPressed: () async {
                      await _hideRecommendation(recId);
                    },
                    icon: const Icon(Icons.close, size: 14),
                    label: Text(
                      'تجاهل',
                      style: GoogleFonts.ibmPlexSansArabic(fontSize: 10),
                    ),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.grey[600],
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      minimumSize: const Size(40, 24),
                    ),
                  ),

                  // ✅ زر إضافة (لنوع add)
                  if (rec['type'] == 'add')
                    ElevatedButton.icon(
                      onPressed: () async {
                        await _hideRecommendation(recId);
                        await Future.delayed(const Duration(milliseconds: 50));
                        if (mounted) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => AddTaskPage(
                                categories: categories,
                                preFillData: {
                                  'category': rec['category'],
                                  'title': rec['title'],
                                  'description': rec['userDescription'],
                                  'userDescription': rec['userDescription'],
                                  'suggestion': rec['suggestion'],
                                  'validationStrategy':
                                      rec['validationStrategy'],
                                  'calcMode': rec['calcMode'],
                                  'askCount': rec['askCount'],
                                  'points': rec['points'],
                                },
                              ),
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.add, size: 14),
                      label: Text(
                        'إضافة',
                        style: GoogleFonts.ibmPlexSansArabic(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: getColor(),
                        foregroundColor: Colors.white,
                        minimumSize: const Size(50, 24),
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                    ),

                  // ✅ زر تعديل (لنوع modify)
                  if (rec['type'] == 'modify')
                    ElevatedButton.icon(
                      onPressed: () async {
                        await _hideRecommendation(recId);
                        await Future.delayed(const Duration(milliseconds: 50));
                        if (mounted) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => AddTaskPage(
                                categories: categories,
                                preFillData: {
                                  'category': rec['category'],
                                  'title': rec['title'],
                                  'description':
                                      rec['improvedDescription'] != null &&
                                          rec['improvedDescription']
                                              .toString()
                                              .isNotEmpty
                                      ? rec['improvedDescription']
                                      : rec['description'],
                                  'suggestion': rec['suggestion'],
                                  'taskId': rec['taskId'],
                                  'type': 'modify',
                                },
                              ),
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.edit, size: 14),
                      label: Text(
                        'تعديل',
                        style: GoogleFonts.ibmPlexSansArabic(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: getColor(),
                        foregroundColor: Colors.white,
                        minimumSize: const Size(50, 24),
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                    ),

                  // ✅ زر حذف (لنوع delete)
                  if (rec['type'] == 'delete')
                    ElevatedButton.icon(
                      onPressed: () async {
                        await _hideRecommendation(recId);
                        await Future.delayed(const Duration(milliseconds: 50));
                        if (mounted) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => AdminTasksPage(
                                preFillData: {
                                  'category': rec['category'],
                                  'title': rec['title'],
                                  'description':
                                      rec['improvedDescription'] != null &&
                                          rec['improvedDescription']
                                              .toString()
                                              .isNotEmpty
                                      ? rec['improvedDescription']
                                      : rec['description'],
                                  'type': 'delete',
                                  'taskId': rec['taskId'],
                                },
                              ),
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.delete, size: 14),
                      label: Text(
                        'حذف',
                        style: GoogleFonts.ibmPlexSansArabic(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: getColor(),
                        foregroundColor: Colors.white,
                        minimumSize: const Size(50, 24),
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                    ),

                  // ✅ زر مراجعة (لنوع review_reports)
                  if (rec['type'] == 'review_reports')
                    ElevatedButton.icon(
                      onPressed: () async {
                        await _hideRecommendation(recId);
                        await Future.delayed(const Duration(milliseconds: 50));
                        if (mounted) {
                          // ✅ تحديد الوجهة حسب نوع البلاغ
                          if (rec.containsKey('facilityId') &&
                              rec['facilityId'] != null) {
                            // بلاغات حاوية
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    const containerReports.AdminReportPage(),
                              ),
                            );
                          } else {
                            // بلاغات مهمة
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const AdminTaskReportsPage(),
                              ),
                            );
                          }
                        }
                      },
                      icon: const Icon(Icons.visibility, size: 14),
                      label: Text(
                        'مراجعة',
                        style: GoogleFonts.ibmPlexSansArabic(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: getColor(),
                        foregroundColor: Colors.white,
                        minimumSize: const Size(50, 24),
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickIcon({
    required IconData icon,
    required String label,
    required Color color,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: 70,
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withOpacity(0.08)
              : Colors.white, // خلفية أفتح (0.08 بدل 0.15)
          borderRadius: BorderRadius.circular(16),
          border: isSelected
              ? Border.all(color: color.withOpacity(0.3), width: 1.5)
              : null, // حدود شفافة
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: isSelected ? color : color.withOpacity(0.5),
              size: 26,
            ), // أيقونة أفتح
            const SizedBox(height: 6),
            Text(
              label,
              style: GoogleFonts.ibmPlexSansArabic(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                color: isSelected
                    ? color
                    : Colors.grey[600], // نص بلون الأيقونة أو رمادي
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickIconWithBadge({
    required IconData icon,
    required String label,
    required Color color,
    required int badgeCount,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: 70,
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.08) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: isSelected
              ? Border.all(color: color.withOpacity(0.3), width: 1.5)
              : null,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Icon(
                      icon,
                      color: isSelected ? color : color.withOpacity(0.5),
                      size: 26,
                    ),
                    // ✅ نقطة حمراء صغيرة - تظهر فقط إذا كان badgeCount > 0
                    if (badgeCount > 0)
                      Positioned(
                        top: -2,
                        right: -2,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: appColors.red,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  label,
                  style: GoogleFonts.ibmPlexSansArabic(
                    fontSize: 11,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                    color: isSelected ? color : Colors.grey[600],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showFullLeaderboard() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.60,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(30),
              topRight: Radius.circular(30),
            ),
          ),
          child: Column(
            children: [
              // شريط السحب
              Container(
                margin: const EdgeInsets.only(top: 8, bottom: 4),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // العنوان
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'قائمة المتصدرين',
                      style: GoogleFonts.ibmPlexSansArabic(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: appColors.dark,
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),

              // القائمة الكاملة
              Expanded(
                child: FutureBuilder<List<Map<String, dynamic>>>(
                  future: _fetchFullLeaderboard(), // دالة جديدة
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    if (!snapshot.hasData || snapshot.data!.isEmpty) {
                      return Center(
                        child: Text(
                          'لا توجد بيانات',
                          style: GoogleFonts.ibmPlexSansArabic(
                            color: Colors.grey[600],
                          ),
                        ),
                      );
                    }

                    final allUsers = snapshot.data!;

                    return ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: allUsers.length,
                      itemBuilder: (context, index) {
                        final user = allUsers[index];
                        return _buildLeaderboardItem(
                          index: index,
                          username: user['username'],
                          completedTasks: user['completedTasks'],
                          points: user['points'],
                          pfpIndex: user['pfpIndex'],
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<List<Map<String, dynamic>>> _fetchTopUsers() async {
    try {
      print('🔍 Fetching top users...');

      // ✅ نجيب كل المستخدمين أولاً بدون فلترة
      final usersSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('isVerified', isEqualTo: true)
          .get();

      print('📊 Total users found: ${usersSnapshot.docs.length}');

      final List<Map<String, dynamic>> usersData = [];

      for (final doc in usersSnapshot.docs) {
        final data = doc.data();

        // ✅ نجيب البيانات بشكل آمن
        final completedTasks = (data['completedTask'] as num?)?.toInt() ?? 0;
        final points = (data['points'] as num?)?.toInt() ?? 0;
        final username = data['username']?.toString() ?? 'مستخدم';
        final pfpIndex = (data['pfpIndex'] as num?)?.toInt() ?? 0;

        // ✅ نضيف المستخدم حتى لو completedTasks = 0
        usersData.add({
          'id': doc.id,
          'username': username,
          'completedTasks': completedTasks,
          'points': points,
          'pfpIndex': pfpIndex,
        });
      }

      print('📊 Users after mapping: ${usersData.length}');

      // ✅ ترتيب تنازلي حسب المهام المكتملة
      usersData.sort((a, b) {
        final aTasks = a['completedTasks'] as int;
        final bTasks = b['completedTasks'] as int;
        return bTasks.compareTo(aTasks);
      });

      // ✅ نأخذ أول 3 مستخدمين فقط
      final topThree = usersData.take(3).toList();

      print('🏆 Top 3 users:');
      for (var i = 0; i < topThree.length; i++) {
        print(
          '   ${i + 1}. ${topThree[i]['username']} - ${topThree[i]['completedTasks']} tasks',
        );
      }

      return topThree;
    } catch (e) {
      debugPrint('❌ Leaderboard error: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> _fetchFullLeaderboard() async {
    try {
      final usersSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('isVerified', isEqualTo: true)
          .get();

      final List<Map<String, dynamic>> usersData = [];

      for (final doc in usersSnapshot.docs) {
        final data = doc.data();
        final completedTasks = data['completedTask'] ?? 0;
        final points = data['points'] ?? 0;
        final username = data['username'] ?? 'مستخدم';
        final pfpIndex = data['pfpIndex'] ?? 0;

        usersData.add({
          'username': username,
          'completedTasks': completedTasks is num ? completedTasks.toInt() : 0,
          'points': points is num ? points.toInt() : 0,
          'pfpIndex': pfpIndex,
        });
      }

      // ترتيب تنازلي
      usersData.sort(
        (a, b) => b['completedTasks'].compareTo(a['completedTasks']),
      );

      return usersData;
    } catch (e) {
      debugPrint('❌ Full leaderboard error: $e');
      return [];
    }
  }

  Widget _buildLoadingStats() {
    return Column(
      children: [
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.5,
          children: List.generate(4, (index) => _buildShimmerCard()),
        ),
        const SizedBox(height: 20),
        Container(
          height: 180,
          decoration: BoxDecoration(
            color: Colors.grey[200],
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Center(child: CircularProgressIndicator()),
        ),
      ],
    );
  }

  Widget _buildErrorStats() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(Icons.error_outline, color: Colors.red, size: 50),
          const SizedBox(height: 16),
          Text(
            'حدث خطأ في تحميل البيانات',
            style: GoogleFonts.ibmPlexSansArabic(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.red,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'يرجى التحقق من اتصال الإنترنت ثم إعادة المحاولة',
            style: GoogleFonts.ibmPlexSansArabic(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _loadChartData,
            style: ElevatedButton.styleFrom(
              backgroundColor: appColors.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              'إعادة المحاولة',
              style: GoogleFonts.ibmPlexSansArabic(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShimmerCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(16),
      ),
    );
  }

  // 🔧 دالة لتحديد عرض الأشرطة (نفس تشارت اليوزر)
  double _getBarWidth(String range) {
    switch (range) {
      case 'اليوم':
        return 8.0;
      case 'أسبوع':
        return 14.0;
      case 'شهر':
        return 4.0;
      case 'سنة':
        return 10.0;
      default:
        return 10.0;
    }
  }

  // 🔧 دالة للفاصل الزمني (نفس تشارت اليوزر)
  double _getInterval() {
    switch (_selectedTimeRange) {
      case 'اليوم':
        return 3.0;
      case 'أسبوع':
        return 1.0;
      case 'شهر':
        return 5.0;
      case 'سنة':
        return 1.0;
      default:
        return 1.0;
    }
  }
}
