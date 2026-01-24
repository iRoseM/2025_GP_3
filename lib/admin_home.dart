import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';

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

  @override
  void initState() {
    super.initState();

    Future.microtask(() async {
      if (!await hasInternetConnection()) {
        if (mounted) {
          showNoInternetDialog(context);
          return;
        }
      } else {
        FCMService.requestPermissionAndSaveToken();
        FCMService.listenToForegroundMessages();
      }
    });

    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });

    _loadChartData();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadChartData() async {
    await _loadUserGrowthData();
    await _loadTaskCompletionData();
    await _loadPointsData();
    await _loadCarbonData();
  }

  Future<void> _loadUserGrowthData() async {
    try {
      final startDate = _getStartDateForRange(_selectedTimeRange);
      final days = _getDaysForRange(_selectedTimeRange);

      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('isVerified', isEqualTo: true)
          .get();

      // buckets حسب الفترة (ساعات لليوم، أيام لغيره)
      final Map<int, int> buckets = {};

      final bucketCount = _selectedTimeRange == 'سنة'
          ? 12
          : (_selectedTimeRange == 'اليوم' ? 24 : days + 1);

      for (int i = 0; i < bucketCount; i++) {
        buckets[i] = 0;
      }

      for (final doc in snapshot.docs) {
        final ts = doc.data()['createdAt'];
        if (ts is! Timestamp) continue;

        final date = ts.toDate();

        int index;
        if (_selectedTimeRange == 'سنة') {
          index = ts.toDate().month - 1;
        } else {
          index = ts.toDate().difference(startDate).inDays;
        }

        if (buckets.containsKey(index)) {
          buckets[index] = buckets[index]! + 1;
        }
      }

      // 📈 تراكمي
      double cumulative = 0;
      final List<FlSpot> spots = [];

      for (final entry in buckets.entries) {
        cumulative += entry.value;
        spots.add(FlSpot(entry.key.toDouble(), cumulative));
      }

      setState(() {
        _userGrowthSpots = spots;
      });
    } catch (e) {
      debugPrint('❌ User growth error: $e');
    }
  }

  // 🔧 دالة لتنسيق تسميات المحور Y
  Widget _buildLeftTitle(double value, TitleMeta meta) {
    // تقريب الأعداد الكبيرة
    String formattedValue;
    if (value >= 1000) {
      formattedValue = '${(value / 1000).toStringAsFixed(1)}ك';
    } else if (value >= 1000000) {
      formattedValue = '${(value / 1000000).toStringAsFixed(1)}م';
    } else {
      formattedValue = value.toInt().toString();
    }

    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: Text(
        formattedValue,
        style: GoogleFonts.ibmPlexSansArabic(
          fontSize: 10,
          color: Colors.grey[600],
          fontWeight: FontWeight.w500,
        ),
        textAlign: TextAlign.right,
      ),
    );
  }

  // 🔧 دالة لإنشاء فترات زمنية متساوية للمحور X
  List<String> _generateXLabels(int count, String timeRange) {
    final labels = <String>[];

    switch (timeRange) {
      case 'اليوم':
        for (int i = 0; i <= 23; i += 3) {
          labels.add('$i:00');
        }
        break;

      case 'أسبوع':
        final days = [
          'الأحد',
          'الاثنين',
          'الثلاثاء',
          'الأربعاء',
          'الخميس',
          'الجمعة',
          'السبت',
        ];
        for (int i = 0; i < 7; i++) {
          labels.add(days[i]);
        }
        break;

      case 'شهر':
        // عرض كل 5 أيام
        for (int i = 1; i <= 30; i += 5) {
          labels.add('$i');
        }
        break;

      case 'سنة':
        const months = [
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
        for (int i = 0; i < 12; i += 2) {
          labels.add(months[i]);
        }
        break;
    }

    return labels;
  }

  Future<void> _loadTaskCompletionData() async {
    try {
      final startDate = _getStartDateForRange(_selectedTimeRange);
      final days = _getDaysForRange(_selectedTimeRange);

      final snapshot = await FirebaseFirestore.instance
          .collection('submissions')
          .where('status', isEqualTo: 'approved')
          .get();

      final Map<int, int> buckets = {};

      if (_selectedTimeRange == 'اليوم') {
        // 24 ساعة
        for (int h = 0; h < 24; h++) {
          buckets[h] = 0;
        }
      } else {
        for (int i = 0; i <= days; i++) {
          buckets[i] = 0;
        }
      }

      for (final doc in snapshot.docs) {
        final ts = doc.data()['createdAt'];
        if (ts is! Timestamp) continue;

        if (_selectedTimeRange == 'اليوم') {
          final hour = ts.toDate().hour;
          buckets[hour] = (buckets[hour] ?? 0) + 1;
        } else {
          int index;
          if (_selectedTimeRange == 'سنة') {
            index = ts.toDate().month - 1;
          } else {
            index = ts.toDate().difference(startDate).inDays;
          }

          if (buckets.containsKey(index)) {
            buckets[index] = buckets[index]! + 1;
          }
        }
      }

      setState(() {
        _taskCompletionSpots = buckets.entries
            .map((e) => FlSpot(e.key.toDouble(), e.value.toDouble()))
            .toList();
      });
    } catch (e) {
      debugPrint('❌ Task completion error: $e');
    }
  }

  Future<void> _loadPointsData() async {
    try {
      final startDate = _getStartDateForRange(_selectedTimeRange);
      final days = _getDaysForRange(_selectedTimeRange);

      final snapshot = await FirebaseFirestore.instance
          .collection('submissions')
          .where('status', isEqualTo: 'approved')
          .get();

      final Map<int, double> buckets = {};

      final bucketCount = _selectedTimeRange == 'سنة' ? 12 : days + 1;
      for (int i = 0; i < bucketCount; i++) {
        buckets[i] = 0;
      }

      for (final doc in snapshot.docs) {
        final ts = doc.data()['createdAt'];
        final pts = doc.data()['taskPoints'];

        if (ts is! Timestamp || pts is! num) continue;

        int index;
        if (_selectedTimeRange == 'سنة') {
          index = ts.toDate().month - 1;
        } else {
          index = ts.toDate().difference(startDate).inDays;
        }

        if (buckets.containsKey(index)) {
          buckets[index] = buckets[index]! + pts.toDouble();
        }
      }

      // 📈 تراكمي
      double cumulative = 0;
      final List<FlSpot> spots = [];

      for (final entry in buckets.entries) {
        cumulative += entry.value;
        spots.add(FlSpot(entry.key.toDouble(), cumulative));
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
      final days = _getDaysForRange(_selectedTimeRange);

      final snapshot = await FirebaseFirestore.instance
          .collection('submissions')
          .where('status', isEqualTo: 'approved')
          .where(
            'createdAt',
            isGreaterThanOrEqualTo: Timestamp.fromDate(startDate),
          )
          .get();

      final Map<String, double> daily = {};
      for (int i = 0; i <= days; i++) {
        final d = startDate.add(Duration(days: i));
        daily[DateFormat('yyyy-MM-dd').format(d)] = 0;
      }

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final ts = data['createdAt'];
        final carbon = data['carbonSaved']; // 👈 لازم يكون موجود

        if (ts is! Timestamp || carbon is! num) continue;

        final key = DateFormat('yyyy-MM-dd').format(ts.toDate());
        if (daily.containsKey(key)) {
          daily[key] = daily[key]! + carbon.toDouble();
        }
      }

      final List<FlSpot> spots = [];
      int index = 0;
      for (final value in daily.values) {
        spots.add(FlSpot(index.toDouble(), value));
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
    final now = DateTime.now();

    switch (range) {
      case 'اليوم':
        return DateTime(now.year, now.month, now.day); // بداية اليوم
      case 'أسبوع':
        return now.subtract(const Duration(days: 7));
      case 'شهر':
        return now.subtract(const Duration(days: 30));
      case 'سنة':
        return now.subtract(const Duration(days: 365));
      default:
        return now.subtract(const Duration(days: 7));
    }
  }

  int _getDaysForRange(String range) {
    switch (range) {
      case 'اليوم':
        return 24; // نقطة وحدة
      case 'أسبوع':
        return 7;
      case 'شهر':
        return 30;
      case 'سنة':
        return 365;
      default:
        return 7;
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

  Widget _buildChartCard(
    String title,
    List<FlSpot> spots,
    Color color,
    String timeRange,
  ) {
    // حساب maxX بشكل مختصر وأكثر دقة
    final double maxXValue = spots.isEmpty
        ? 1
        : spots.map((spot) => spot.x).reduce(math.max);

    final double maxY = _getMaxYValue(spots);
    final double average = spots.isNotEmpty
        ? spots.map((e) => e.y).reduce((a, b) => a + b) / spots.length
        : 0;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8), // قلل البادينج
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12), // زوايا أصغر
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
        border: Border.all(color: color.withOpacity(0.2), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // العنوان + الفلتر - نسخة مضغوطة
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.ibmPlexSansArabic(
                    fontSize: 14, // أصغر
                    fontWeight: FontWeight.w700,
                    color: appColors.dark,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6), // أقل مسافة
              _buildCompactTimeRangeSelector(), // فلتر أصغر
            ],
          ),

          const SizedBox(height: 12), // أقل من 16
          // الرسم أو رسالة عدم وجود بيانات
          SizedBox(
            height: 140, // قلل من 180 إلى 140
            child: spots.isEmpty
                ? Center(
                    child: Text(
                      'لا توجد بيانات',
                      style: GoogleFonts.ibmPlexSansArabic(
                        fontSize: 12,
                        color: Colors.grey[500],
                      ),
                    ),
                  )
                : LineChart(
                    LineChartData(
                      minX: 0,
                      maxX: _selectedTimeRange == 'سنة'
                          ? 11
                          : math.max(1, maxXValue),

                      minY: 0,
                      maxY: _getNiceMaxY(maxY, title),

                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        horizontalInterval: _calculateSafeInterval(
                          maxY,
                          title,
                        ), // ✅ صح
                      ),

                      borderData: FlBorderData(
                        show: true,
                        border: Border.all(
                          color: Colors.grey[300]!,
                          width: 0.5,
                        ),
                      ),

                      titlesData: FlTitlesData(
                        show: true,
                        topTitles: AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        rightTitles: AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),

                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            interval: _calculateSafeInterval(
                              maxY,
                              title,
                            ), // ✅ صح
                            reservedSize: 30,
                            getTitlesWidget: (value, meta) {
                              return Padding(
                                padding: const EdgeInsets.only(right: 2.0),
                                child: Text(
                                  _formatCompactNumber(value),
                                  style: GoogleFonts.ibmPlexSansArabic(
                                    fontSize: 8,
                                    color: Colors.grey[600],
                                  ),
                                  textAlign: TextAlign.right,
                                ),
                              );
                            },
                          ),
                        ),

                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 18, // أقل من 24
                            interval: _getCompactXInterval(
                              timeRange,
                            ).toDouble(),
                            getTitlesWidget: (value, meta) {
                              final interval = _getCompactXInterval(timeRange);
                              if (value.toInt() % interval != 0) {
                                return const SizedBox.shrink();
                              }
                              return _buildCompactXAxisTitle(
                                value.toInt(),
                                maxXValue.toInt(),
                                timeRange,
                              );
                            },
                          ),
                        ),
                      ),

                      lineBarsData: [
                        LineChartBarData(
                          spots: spots,
                          isCurved: true,
                          curveSmoothness: 0.3,
                          barWidth: 2, // أرق
                          color: color,
                          dotData: FlDotData(show: false), // إخفاء النقاط
                          belowBarData: BarAreaData(
                            show: true,
                            color: color.withOpacity(0.1),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),

          // 👇 الإحصائيات - نسخة مضغوطة
          if (spots.isNotEmpty) ...[
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildCompactMiniStat('الأعلى', _formatCompactNumber(maxY)),
                  _buildCompactMiniStat(
                    'المتوسط',
                    _formatCompactNumber(average),
                  ),
                  _buildCompactMiniStat(
                    'الفترة',
                    _getCompactPeriodName(timeRange),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  double _calculateSafeInterval(double maxY, String chartTitle) {
    if (maxY <= 0 || maxY.isNaN || maxY.isInfinite) {
      return 1.0;
    }

    final niceMaxY = _getNiceMaxY(maxY, chartTitle);
    if (niceMaxY <= 0 || niceMaxY.isNaN || niceMaxY.isInfinite) {
      return 1.0;
    }

    final interval = niceMaxY / 4;
    if (interval <= 0 || interval.isNaN || interval.isInfinite) {
      return 1.0;
    }

    return interval;
  }

  Widget _buildCompactTimeRangeSelector() {
    return Container(
      height: 28, // أصغر
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: appColors.primary.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: Alignment.center,
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedTimeRange,
          isDense: true,
          icon: Icon(
            Icons.arrow_drop_down,
            color: appColors.primary,
            size: 16, // أصغر
          ),
          dropdownColor: Colors.white,
          borderRadius: BorderRadius.circular(10),
          style: GoogleFonts.ibmPlexSansArabic(
            color: appColors.dark,
            fontWeight: FontWeight.w600,
            fontSize: 10, // أصغر
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
            return DropdownMenuItem<String>(
              value: value,
              child: Text(
                value,
                style: GoogleFonts.ibmPlexSansArabic(fontSize: 10),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildCompactMiniStat(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 10, // أصغر
            height: 1.1,
          ),
        ),
        const SizedBox(height: 2), // أقل مسافة
        Text(
          label,
          style: TextStyle(
            fontSize: 8, // أصغر
            color: Colors.grey[600],
            height: 1.1,
          ),
        ),
      ],
    );
  }

  String _formatCompactNumber(double value) {
    if (value >= 1000000) {
      return '${(value / 1000000).toStringAsFixed(0)}م';
    } else if (value >= 1000) {
      return '${(value / 1000).toStringAsFixed(0)}ألف';
    } else if (value >= 1) {
      return value.toInt().toString();
    } else {
      return value.toStringAsFixed(1);
    }
  }

  int _getCompactXInterval(String timeRange) {
    switch (timeRange) {
      case 'اليوم':
        return 6; // كل 6 ساعات (بدلاً من 3)
      case 'أسبوع':
        return 1; // كل يومين
      case 'شهر':
        return 10; // كل 10 أيام
      case 'سنة':
        return 3; // كل 3 أشهر
      default:
        return 2;
    }
  }

  Widget _buildCompactXAxisTitle(int value, int maxX, String timeRange) {
    switch (timeRange) {
      case 'اليوم':
        if (value > 23) return const SizedBox.shrink();
        if (value % 6 != 0) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 2.0),
          child: Text(
            '$value',
            style: GoogleFonts.ibmPlexSansArabic(
              fontSize: 7, // أصغر
              color: Colors.grey[600],
            ),
          ),
        );

      case 'أسبوع':
        if (value > 6) return const SizedBox.shrink();
        if (value % 2 != 0) return const SizedBox.shrink();
        final days = ['أ', 'ث', 'خ', 'س']; // أيام مختصرة
        final dayIndex = value ~/ 2;
        if (dayIndex < days.length) {
          return Padding(
            padding: const EdgeInsets.only(top: 2.0),
            child: Text(
              days[dayIndex],
              style: GoogleFonts.ibmPlexSansArabic(
                fontSize: 7,
                color: Colors.grey[600],
              ),
            ),
          );
        }
        return const SizedBox.shrink();

      case 'شهر':
        if (value > 29) return const SizedBox.shrink();
        if (value % 10 != 0) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 2.0),
          child: Text(
            '${value + 1}',
            style: GoogleFonts.ibmPlexSansArabic(
              fontSize: 7,
              color: Colors.grey[600],
            ),
          ),
        );

      case 'سنة':
        if (value > 11) return const SizedBox.shrink();
        if (value % 3 != 0) return const SizedBox.shrink();
        const months = ['ينا', 'أبريل', 'يوليو', 'أكتوبر'];
        final monthIndex = value ~/ 3;
        if (monthIndex < months.length) {
          return Padding(
            padding: const EdgeInsets.only(top: 2.0),
            child: Text(
              months[monthIndex],
              style: GoogleFonts.ibmPlexSansArabic(
                fontSize: 7,
                color: Colors.grey[600],
              ),
            ),
          );
        }
        return const SizedBox.shrink();

      default:
        return const SizedBox.shrink();
    }
  }

  String _getCompactPeriodName(String period) {
    switch (period) {
      case 'اليوم':
        return 'اليوم';
      case 'أسبوع':
        return 'أسبوع';
      case 'شهر':
        return 'شهر';
      case 'سنة':
        return 'سنة';
      default:
        return period;
    }
  }

  // 🔧 دالة لتحديد تباعد مناسب للمحور X حسب الفترة
  int _getXInterval(String timeRange) {
    switch (timeRange) {
      case 'اليوم':
        return 3; // كل 3 ساعات
      case 'أسبوع':
        return 1; // كل يوم
      case 'شهر':
        return 5; // كل 5 أيام
      case 'سنة':
        return 2; // كل شهرين
      default:
        return 1;
    }
  }

  // 🔧 دالة لتقريب القيم الكبيرة
  String _formatLargeNumber(double value) {
    if (value >= 1000000) {
      return '${(value / 1000000).toStringAsFixed(1)}م';
    } else if (value >= 1000) {
      return '${(value / 1000).toStringAsFixed(1)}ك';
    } else if (value >= 1) {
      return value.toInt().toString();
    } else {
      return value.toStringAsFixed(1);
    }
  }

  // 🔧 دالة لتحديد عرض البار حسب الفترة
  double _getBarWidth(String timeRange, int spotCount) {
    if (spotCount <= 10) return 12;
    if (spotCount <= 20) return 8;
    if (spotCount <= 30) return 6;
    return 4;
  }

  // 👇 ميثود _buildMiniStat الأصلية التي تريد الاحتفاظ بها
  Widget _buildMiniStat(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
        ),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(fontSize: 10, color: Colors.grey[600])),
      ],
    );
  }

  Widget _buildXAxisTitle(int value, int maxX, String timeRange) {
    // عدم عرض تسميات كثيرة جداً
    if (maxX > 50 && value % 10 != 0 && value != maxX.toInt()) {
      return const SizedBox.shrink();
    }

    if (maxX > 100 && value % 20 != 0 && value != maxX.toInt()) {
      return const SizedBox.shrink();
    }

    switch (timeRange) {
      case 'اليوم':
        if (value > 23) return const SizedBox.shrink();
        if (value % 3 != 0 && value != 0 && value != 23) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: const EdgeInsets.only(top: 4.0),
          child: Text(
            '$value',
            style: GoogleFonts.ibmPlexSansArabic(
              fontSize: 8,
              color: Colors.grey[600],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        );

      case 'أسبوع':
        if (value > 6) return const SizedBox.shrink();

        const days = ['أحد', 'اثن', 'ثلث', 'أرب', 'خمي', 'جمع', 'سبت'];

        return Padding(
          padding: const EdgeInsets.only(top: 2.0),
          child: Text(
            days[value],
            style: GoogleFonts.ibmPlexSansArabic(
              fontSize: 7,
              color: Colors.grey[600],
            ),
          ),
        );

      case 'شهر':
        if (value > 29) return const SizedBox.shrink();
        // عرض فقط أيام محددة
        final daysToShow = [0, 5, 10, 15, 20, 25, 29];
        if (!daysToShow.contains(value)) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: const EdgeInsets.only(top: 4.0),
          child: Text(
            '${value + 1}',
            style: GoogleFonts.ibmPlexSansArabic(
              fontSize: 8,
              color: Colors.grey[600],
            ),
          ),
        );

      case 'سنة':
        if (value > 11) return const SizedBox.shrink();
        // عرض فقط شهور محددة
        if (value % 3 != 0) {
          return const SizedBox.shrink();
        }
        const months = ['ينا', 'أبريل', 'يوليو', 'أكتوبر'];
        final monthIndex = value ~/ 3;
        if (monthIndex < months.length) {
          return Padding(
            padding: const EdgeInsets.only(top: 4.0),
            child: Text(
              months[monthIndex],
              style: GoogleFonts.ibmPlexSansArabic(
                fontSize: 8,
                color: Colors.grey[600],
              ),
            ),
          );
        }
        return const SizedBox.shrink();

      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildChartStats(List<FlSpot> spots, double maxY) {
    final total = spots.map((e) => e.y).reduce((a, b) => a + b);
    final average = total / spots.length;
    final lastValue = spots.isNotEmpty ? spots.last.y : 0;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _buildStatItem('القيمة الأخيرة', lastValue.toStringAsFixed(1)),
        _buildStatItem('المتوسط', average.toStringAsFixed(1)),
        _buildStatItem('الإجمالي', total.toStringAsFixed(1)),
        _buildStatItem('الأعلى', maxY.toStringAsFixed(1)),
      ],
    );
  }

  Widget _buildStatItem(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: GoogleFonts.ibmPlexSansArabic(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: appColors.dark,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: GoogleFonts.ibmPlexSansArabic(
            fontSize: 9,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }

  Widget _miniStat(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        ),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
      ],
    );
  }

  Widget _buildBarChartCard(
    String title,
    List<FlSpot> spots,
    Color color,
    String timeRange, { // ← أضف هذه المعلمة
    bool showStats = true,
  }) {
    final double maxY = _getMaxYValue(spots);
    final double maxXValue = spots.isEmpty
        ? 1
        : spots.map((spot) => spot.x).reduce(math.max);

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8), // أصغر
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.ibmPlexSansArabic(
                    fontSize: 14, // أصغر
                    fontWeight: FontWeight.w700,
                    color: appColors.dark,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              _buildCompactTimeRangeSelector(),
            ],
          ),

          const SizedBox(height: 12),

          // 👇 لا حاجة للـ Scroll الآن
          SizedBox(
            height: 140, // أصغر
            child: spots.isEmpty
                ? Center(
                    child: Text(
                      'لا توجد بيانات',
                      style: GoogleFonts.ibmPlexSansArabic(
                        fontSize: 12,
                        color: Colors.grey[500],
                      ),
                    ),
                  )
                : BarChart(
                    BarChartData(
                      alignment: BarChartAlignment.spaceBetween,

                      groupsSpace: 2, // مسافة أقل

                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        horizontalInterval: _calculateSafeInterval(maxY, title),
                      ),

                      titlesData: FlTitlesData(
                        show: true,
                        topTitles: AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        rightTitles: AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),

                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 30,
                            interval: _safeInterval(
                              _getNiceMaxY(maxY, title) / 3,
                            ),
                            getTitlesWidget: (value, meta) {
                              return Padding(
                                padding: const EdgeInsets.only(right: 2.0),
                                child: Text(
                                  _formatCompactNumber(value),
                                  style: GoogleFonts.ibmPlexSansArabic(
                                    fontSize: 8,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),

                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 18,
                            interval: _getCompactXInterval(
                              timeRange,
                            ).toDouble(),
                            getTitlesWidget: (value, meta) {
                              final interval = _getCompactXInterval(timeRange);
                              if (value.toInt() % interval != 0) {
                                return const SizedBox.shrink();
                              }
                              return _buildCompactXAxisTitle(
                                value.toInt(),
                                maxXValue.toInt(),
                                timeRange,
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

                      barGroups: spots.map((spot) {
                        return BarChartGroupData(
                          x: spot.x.toInt(),
                          barRods: [
                            BarChartRodData(
                              toY: spot.y,
                              width: 3, // أرق
                              borderRadius: BorderRadius.circular(2),
                              color: color,
                            ),
                          ],
                        );
                      }).toList(),

                      minY: 0,
                      maxY: _getNiceMaxY(maxY, title),
                    ),
                  ),
          ),

          if (showStats && spots.isNotEmpty) ...[
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildCompactMiniStat('الأعلى', _formatCompactNumber(maxY)),
                  _buildCompactMiniStat(
                    'المتوسط',
                    _formatCompactNumber(
                      spots.map((e) => e.y).reduce((a, b) => a + b) /
                          spots.length,
                    ),
                  ),
                  _buildCompactMiniStat(
                    'الفترة',
                    _getCompactPeriodName(timeRange),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBottomTitle(double value, TitleMeta meta) {
    final index = value.toInt();

    String text = '';

    switch (_selectedTimeRange) {
      case 'اليوم':
        if (index % 3 == 0) {
          text = '${index}:00'; // كل 3 ساعات
        }
        break;
      case 'أسبوع':
        final index = value.toInt();
        if (index > 6) return const SizedBox.shrink();

        const days = ['أحد', 'اثن', 'ثلث', 'أرب', 'خمي', 'جمع', 'سبت'];

        return Padding(
          padding: const EdgeInsets.only(top: 2.0),
          child: Text(
            days[index],
            style: GoogleFonts.ibmPlexSansArabic(
              fontSize: 7,
              color: Colors.grey[600],
            ),
          ),
        );

      case 'شهر':
        // أرقام الأيام
        // اعرض كل 5 أيام فقط
        if (index % 5 == 0) {
          text = (index + 1).toString();
        }

        break;

      case '3 أشهر':
      case 'سنة':
        // أسماء الشهور
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
        if (index >= 0 && index < months.length) {
          text = months[index];
        }
        break;
    }

    if (text.isEmpty) return const SizedBox.shrink();

    return SideTitleWidget(
      axisSide: meta.axisSide,
      space: 8,
      child: Transform.rotate(
        angle: -math.pi / 4, // 👈 ميل 45 درجة
        child: Text(
          text,
          style: GoogleFonts.ibmPlexSansArabic(
            fontSize: 9,
            color: Colors.grey[600],
          ),
        ),
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

  double _getNiceMaxY(double maxY, String chartTitle) {
    if (maxY <= 0) return 10;

    // معالجة خاصة للكربون والنقاط
    if (chartTitle.contains('كربون') || chartTitle.contains('توفير')) {
      if (maxY < 10) return 10;
      if (maxY < 100) return 100;
      if (maxY < 1000) return 1000;
    }

    if (chartTitle.contains('نقاط') || chartTitle.contains('تراكم')) {
      if (maxY < 100) return 100;
      if (maxY < 1000) return 1000;
      if (maxY < 10000) return 10000;
    }

    // الحساب العام
    if (maxY < 1) return 1;

    if (maxY <= 10) {
      if (maxY <= 2) return 2;
      if (maxY <= 5) return 5;
      return 10;
    }

    // للأعداد الكبيرة
    final int magnitude = maxY.toString().split('.')[0].length - 1;
    final double base = math.pow(10, magnitude).toDouble();
    final double normalized = maxY / base;

    double niceMax;
    if (normalized <= 1) {
      niceMax = 1;
    } else if (normalized <= 2) {
      niceMax = 2;
    } else if (normalized <= 5) {
      niceMax = 5;
    } else {
      niceMax = 10;
    }

    return niceMax * base * 1.2; // هامش 20%
  }

  Widget _buildStatCardSafe({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
    double? progress,
  }) {
    return SizedBox(
      height: 110, // 🔒 ارتفاع ثابت يمنع RenderFlex overflow
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.10),
              blurRadius: 10,
              offset: const Offset(0, 5),
            ),
          ],
          border: Border.all(color: color.withOpacity(0.15), width: 1),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 🔹 أيقونة صغيرة
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 14, color: color),
            ),

            // 🔹 الرقم
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.ibmPlexSansArabic(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: appColors.dark,
                height: 1.0,
              ),
            ),

            // 🔹 العنوان
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.ibmPlexSansArabic(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: appColors.sea,
                height: 1.1,
              ),
            ),

            // 🔹 Progress أو فراغ ثابت
            progress != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: LinearProgressIndicator(
                      value: progress.clamp(0, 1),
                      minHeight: 4,
                      backgroundColor: color.withOpacity(0.15),
                      valueColor: AlwaysStoppedAnimation(color),
                    ),
                  )
                : const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }

  Widget _buildCarbonOverviewCard({
    required num totalCarbon,
    required List<FlSpot> carbonSpots,
  }) {
    final progress = (totalCarbon / 1000).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.12),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          // 🔵 Gauge
          SizedBox(
            width: 90,
            height: 90,
            child: Stack(
              children: [
                CircularProgressIndicator(
                  value: progress,
                  strokeWidth: 8,
                  backgroundColor: Colors.teal.withOpacity(0.2),
                  color: Colors.teal,
                ),
                Center(
                  child: Text(
                    '${(progress * 100).toStringAsFixed(0)}%',
                    style: GoogleFonts.ibmPlexSansArabic(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Colors.teal,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 16),

          // 📄 Text + Chart
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'إجمالي توفير الكربون',
                  style: GoogleFonts.ibmPlexSansArabic(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: appColors.dark,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${totalCarbon.toStringAsFixed(1)} كجم ',
                  style: GoogleFonts.ibmPlexSansArabic(
                    fontSize: 13,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 10),

                SizedBox(
                  height: 50,
                  child: LineChart(
                    LineChartData(
                      gridData: FlGridData(show: false),
                      titlesData: FlTitlesData(show: false),
                      borderData: FlBorderData(show: false),

                      lineBarsData: [
                        LineChartBarData(
                          spots: carbonSpots.isNotEmpty
                              ? carbonSpots
                              : [
                                  FlSpot(0, 2),
                                  FlSpot(1, 4),
                                  FlSpot(2, 3),
                                  FlSpot(3, 6),
                                  FlSpot(4, 5),
                                ],
                          isCurved: true,
                          color: Colors.teal,
                          barWidth: 2,
                          dotData: FlDotData(show: false),
                          belowBarData: BarAreaData(
                            show: true,
                            color: Colors.teal.withOpacity(0.15),
                          ),
                        ),
                      ],
                      minY: 0,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<int> _getActiveUsersCount() async {
    final startDate = _getStartDateForRange(_selectedTimeRange);

    final snapshot = await FirebaseFirestore.instance
        .collection('submissions')
        .where(
          'createdAt',
          isGreaterThanOrEqualTo: Timestamp.fromDate(startDate),
        )
        .get();

    final Set<String> activeUserIds = {};

    for (final doc in snapshot.docs) {
      final userId = doc.data()['userId'];
      if (userId is String) {
        activeUserIds.add(userId);
      }
    }

    return activeUserIds.length;
  }

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
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                18,
                18,
                18,
                18 +
                    MediaQuery.of(context).padding.bottom +
                    kBottomNavigationBarHeight,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 4),

                  StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    stream: userStream,
                    builder: (context, snap) {
                      final isLoading =
                          snap.connectionState == ConnectionState.waiting;
                      final data = snap.data?.data();

                      final String displayName = isLoading
                          ? '...'
                          : (data?['username']?.toString().trim().isNotEmpty ==
                                    true
                                ? data!['username'].toString()
                                : (user?.displayName?.trim().isNotEmpty == true
                                      ? user!.displayName!
                                      : (user?.email ?? 'مستخدم')));

                      int? pfpIndex;
                      if (data?['pfpIndex'] is int) {
                        pfpIndex = data!['pfpIndex'] as int;
                      } else if (data?['pfpIndex'] != null) {
                        pfpIndex = int.tryParse(data!['pfpIndex'].toString());
                      }
                      String? avatarPath;
                      if (pfpIndex != null && pfpIndex >= 0 && pfpIndex < 8) {
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
                                      color: appColors.primary.withOpacity(.2),
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
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  RichText(
                                    text: TextSpan(
                                      children: [
                                        TextSpan(
                                          text: "مرحباً، ",
                                          style: GoogleFonts.ibmPlexSansArabic(
                                            fontSize: 20,
                                            fontWeight: FontWeight.w800,
                                            color: appColors.dark,
                                          ),
                                        ),
                                        TextSpan(
                                          text: displayName,
                                          style: GoogleFonts.ibmPlexSansArabic(
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

                  const SizedBox(height: 26),

                  StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: FirebaseFirestore.instance
                        .collection('users')
                        .where('isVerified', isEqualTo: true)
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return _buildLoadingStats();
                      }

                      if (snapshot.hasError) {
                        return _buildErrorStats();
                      }

                      final docs = snapshot.data?.docs ?? [];
                      final totalUsers = docs.length;

                      num totalPoints = 0;
                      num totalCarbon = 0;
                      num totalCompletedTasks = 0;
                      final now = DateTime.now();
                      final todayStart = DateTime(now.year, now.month, now.day);

                      for (final doc in docs) {
                        final data = doc.data();

                        final p = data['points'];
                        if (p is num)
                          totalPoints += p;
                        else if (p != null)
                          totalPoints += num.tryParse(p.toString()) ?? 0;

                        final c = data['totalCarbonSaved'];
                        if (c is num)
                          totalCarbon += c;
                        else if (c != null)
                          totalCarbon += num.tryParse(c.toString()) ?? 0;

                        final ct = data['completedTask'];
                        if (ct is num)
                          totalCompletedTasks += ct;
                        else if (ct != null)
                          totalCompletedTasks +=
                              num.tryParse(ct.toString()) ?? 0;
                      }

                      return Column(
                        children: [
                          _buildCarbonOverviewCard(
                            totalCarbon: totalCarbon,
                            carbonSpots: _carbonSpots,
                          ),

                          const SizedBox(height: 16),

                          Row(
                            children: [
                              Expanded(
                                child: FutureBuilder<int>(
                                  future: _getActiveUsersCount(),
                                  builder: (context, snap) {
                                    final activeUsers = snap.data ?? 0;

                                    return _buildStatCardSafe(
                                      title: 'المستخدمون النشطون',
                                      value: '$activeUsers',
                                      subtitle: 'خلال $_selectedTimeRange',
                                      icon: Icons.flash_on_rounded,
                                      color: appColors.primary,
                                      progress: totalUsers > 0
                                          ? activeUsers / totalUsers
                                          : 0,
                                    );
                                  },
                                ),
                              ),

                              const SizedBox(width: 14),
                              Expanded(
                                child: _buildStatCardSafe(
                                  title: 'إجمالي النقاط',
                                  value: totalPoints.toStringAsFixed(0),
                                  subtitle: '',
                                  icon: Icons.star_rounded,
                                  color: appColors.accent,
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 20),

                          SizedBox(
                            height: 280,
                            child: PageView(
                              children: [
                                _buildChartCard(
                                  'نمو المستخدمين',
                                  _userGrowthSpots,
                                  appColors.primary,
                                  _selectedTimeRange,
                                ),
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
                                _buildBarChartCard(
                                  'توفير الكربون',
                                  _carbonSpots,
                                  appColors.tealSoft,
                                  _selectedTimeRange,
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 20),

                          // ✅ استدعاء الميثود مع المعلمات الصحيحة
                          _buildDetailedStatsTable(
                            totalUsers, // هذا int
                            totalCompletedTasks.toInt(), // أضف .toInt() هنا
                            totalPoints.toInt(), // وأضف .toInt() هنا
                            totalCarbon,
                          ),
                        ],
                      );
                    },
                  ),

                  const SizedBox(height: 16),

                  StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: FirebaseFirestore.instance
                        .collection('submissions')
                        .where('status', isEqualTo: 'pending')
                        .snapshots(),
                    builder: (context, snap) {
                      final isLoading =
                          snap.connectionState == ConnectionState.waiting;
                      final count = (snap.data?.docs.length ?? 0);

                      return InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const AdminTaskCheckPage(),
                            ),
                          );
                        },
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 16,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.grey.withOpacity(0.15),
                                blurRadius: 8,
                                offset: const Offset(0, 3),
                              ),
                            ],
                            border: Border.all(
                              color: appColors.primary.withOpacity(0.2),
                              width: 1.5,
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  color: appColors.primary.withOpacity(.12),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.fact_check_outlined,
                                  color: appColors.primary,
                                ),
                              ),
                              const SizedBox(width: 12),

                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'طلبات مهام جديدة للمراجعة',
                                      style: GoogleFonts.ibmPlexSansArabic(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                        color: appColors.dark,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      isLoading
                                          ? 'جاري التحميل...'
                                          : (count == 0
                                                ? 'لا توجد طلبات جديدة حالياً'
                                                : 'لديك $count طلب${count == 1 ? '' : 'ات'} بانتظار الاعتماد'),
                                      style: GoogleFonts.ibmPlexSansArabic(
                                        fontSize: 13.5,
                                        color: Colors.grey[700],
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: appColors.primary.withOpacity(.12),
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Text(
                                      isLoading ? '—' : '$count',
                                      style: GoogleFonts.ibmPlexSansArabic(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w700,
                                        color: appColors.primary,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  const Icon(
                                    Icons.chevron_left,
                                    color: appColors.primary,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),

          bottomNavigationBar: isKeyboardOpen
              ? null
              : AdminBottomNav(currentIndex: _currentIndex, onTap: _onTap),
        ),
      ),
    );
  }

  double _safeInterval(double value) {
    if (value.isNaN || value.isInfinite || value <= 0) {
      return 1.0;
    }
    return value;
  }

  Widget _buildDetailedStatsTable(
    int totalUsers,
    num totalTasks, // غير int إلى num
    num totalPoints, // غير int إلى num
    num totalCarbon,
  ) {
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '📊 إحصائيات مفصلة',
                style: GoogleFonts.ibmPlexSansArabic(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: appColors.dark,
                ),
              ),
              IconButton(
                onPressed: _loadChartData,
                icon: const Icon(Icons.refresh, color: appColors.primary),
                tooltip: 'تحديث البيانات',
              ),
            ],
          ),
          const SizedBox(height: 16),

          Table(
            columnWidths: const {
              0: FlexColumnWidth(2),
              1: FlexColumnWidth(1),
              2: FlexColumnWidth(1),
            },
            children: [
              TableRow(
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: Colors.grey[300]!)),
                ),
                children: [
                  _buildTableCell('المؤشر', true),
                  _buildTableCell('القيمة', true),
                  _buildTableCell('النسبة %', true),
                ],
              ),

              TableRow(
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
                ),
                children: [
                  _buildTableCell('متوسط المهام لكل مستخدم', false),
                  _buildTableCell(totalTasks.toStringAsFixed(0), false),
                  _buildTableCell(
                    '${totalUsers > 0 ? (totalTasks / totalUsers).toStringAsFixed(1) : 0}',
                    false,
                  ),
                ],
              ),
              TableRow(
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
                ),
                children: [
                  _buildTableCell('متوسط النقاط لكل مستخدم', false),
                  _buildTableCell(totalPoints.toStringAsFixed(0), false),
                  _buildTableCell(
                    '${totalUsers > 0 ? (totalPoints / totalUsers).toStringAsFixed(0) : 0}',
                    false,
                  ),
                ],
              ),
              TableRow(
                children: [
                  _buildTableCell('متوسط توفير الكربون', false),
                  _buildTableCell(
                    '${totalCarbon.toStringAsFixed(1)} كجم',
                    false,
                  ),
                  _buildTableCell(
                    '${totalUsers > 0 ? (totalCarbon / totalUsers).toStringAsFixed(2) : 0} كجم/مستخدم',
                    false,
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 20),

          // ملخص بصري
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildMiniProgress(
                'المهام',
                totalUsers > 0 ? totalTasks / (totalUsers * 10) : 0,
                Colors.green,
              ),
              _buildMiniProgress(
                'التوفير',
                totalUsers > 0 ? totalCarbon / (totalUsers * 100) : 0,
                Colors.teal,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMiniProgress(String label, double value, Color color) {
    return Column(
      children: [
        SizedBox(
          width: 60,
          height: 60,
          child: Stack(
            children: [
              CircularProgressIndicator(
                value: value.clamp(0.0, 1.0),
                strokeWidth: 6,
                backgroundColor: color.withOpacity(0.2),
                color: color,
              ),
              Center(
                child: Text(
                  '${(value * 100).toStringAsFixed(0)}%',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: GoogleFonts.ibmPlexSansArabic(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }

  Widget _buildTableCell(String text, bool isHeader) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Text(
        text,
        style: GoogleFonts.ibmPlexSansArabic(
          fontSize: isHeader ? 14 : 13,
          fontWeight: isHeader ? FontWeight.w700 : FontWeight.w500,
          color: isHeader ? appColors.dark : Colors.grey[700],
        ),
      ),
    );
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
            'تأكد من اتصال الإنترنت وحاول مرة أخرى',
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
}
