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
import 'admin_task_reports.dart';

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

    _refreshTimer = Timer.periodic(const Duration(hours: 1), (_) {
      if (mounted) {
        setState(() {});
        _loadChartData(); // أضف هذه السطر لتحميل البيانات الجديدة
      }
    });
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

  Future<void> _loadUserGrowthData() async {
    try {
      final startDate = _getStartDateForRange(_selectedTimeRange);
      final endDate = _getEndDateForRange(_selectedTimeRange);

      // خيار 1: احصل على جميع المستخدمين ثم فلتر محلياً (أقل كفاءة)
      final usersSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .get();

      // أنشئ قائمة الأيام/الفترات
      final Map<String, int> periodCounts = {};
      final periodKeys = _generatePeriodKeys(
        startDate,
        endDate,
        _selectedTimeRange,
      );

      for (final key in periodKeys) {
        periodCounts[key] = 0;
      }

      // فلتر محلياً للمستخدمين المؤكدين في الفترة
      for (final doc in usersSnapshot.docs) {
        final data = doc.data();
        final isVerified = data['isVerified'] == true;
        final createdAt = data['createdAt'];

        if (isVerified && createdAt is Timestamp) {
          final userDate = createdAt.toDate();

          // تحقق إذا كان في الفترة المحددة
          if (userDate.isAfter(startDate) && userDate.isBefore(endDate)) {
            final periodKey = _getPeriodKey(userDate, _selectedTimeRange);

            if (periodCounts.containsKey(periodKey)) {
              periodCounts[periodKey] = periodCounts[periodKey]! + 1;
            }
          }
        }
      }

      // حوّل إلى FlSpots
      final List<FlSpot> spots = [];
      int index = 0;
      double cumulative = 0;

      for (final key in periodKeys) {
        cumulative += periodCounts[key] ?? 0;
        spots.add(FlSpot(index.toDouble(), cumulative));
        index++;
      }

      setState(() {
        _userGrowthSpots = spots;
      });
    } catch (e) {
      debugPrint('❌ User growth error: $e');
    }
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
      final endDate = _getEndDateForRange(_selectedTimeRange);

      // احصل على جميع التقديمات المعتمدة في الفترة
      final submissionsSnapshot = await FirebaseFirestore.instance
          .collection('submissions')
          .where('status', isEqualTo: 'approved')
          .where(
            'createdAt',
            isGreaterThanOrEqualTo: Timestamp.fromDate(startDate),
          )
          .where('createdAt', isLessThanOrEqualTo: Timestamp.fromDate(endDate))
          .get();

      // أنشئ قائمة الفترات
      final Map<String, int> periodCounts = {};
      final periodKeys = _generatePeriodKeys(
        startDate,
        endDate,
        _selectedTimeRange,
      );

      for (final key in periodKeys) {
        periodCounts[key] = 0;
      }

      // عد المهام لكل فترة
      for (final doc in submissionsSnapshot.docs) {
        final data = doc.data();
        final createdAt = data['createdAt'];
        if (createdAt is Timestamp) {
          final taskDate = createdAt.toDate();
          final periodKey = _getPeriodKey(taskDate, _selectedTimeRange);

          if (periodCounts.containsKey(periodKey)) {
            periodCounts[periodKey] = periodCounts[periodKey]! + 1;
          }
        }
      }

      // حوّل إلى FlSpots
      final List<FlSpot> spots = [];
      int index = 0;

      for (final key in periodKeys) {
        spots.add(
          FlSpot(index.toDouble(), (periodCounts[key] ?? 0).toDouble()),
        );
        index++;
      }

      setState(() {
        _taskCompletionSpots = spots;
      });
    } catch (e) {
      debugPrint('❌ Task completion error: $e');
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
    final double maxY = _getMaxYValue(spots);
    final double average = spots.isNotEmpty
        ? spots.map((e) => e.y).reduce((a, b) => a + b) / spots.length
        : 0;

    return Container(
      padding: const EdgeInsets.all(16), // نفس البادينج
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20), // نفس الزوايا
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
          /// العنوان + الفلتر (نفس التصميم)
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
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: color.withOpacity(0.3)),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedTimeRange,
                    icon: Icon(Icons.arrow_drop_down, size: 20, color: color),
                    onChanged: (v) {
                      if (v != null) {
                        setState(() {
                          _selectedTimeRange = v;
                        });
                        _loadChartData();
                      }
                    },
                    items: _timeRanges
                        .map(
                          (e) => DropdownMenuItem(
                            value: e,
                            child: Text(
                              e,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: appColors.dark,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          /// 👇 الرسم البياني الخطي
          SizedBox(
            height: 160, // نفس الارتفاع
            child: spots.isEmpty
                ? const Center(child: Text('لا توجد بيانات'))
                : LineChart(
                    LineChartData(
                      minY: 0,
                      maxY: maxY == 0 ? 10 : null,
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        horizontalInterval: maxY == 0
                            ? 1
                            : math.max(1, (maxY / 3).ceilToDouble()),
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
                            reservedSize: 36,
                            getTitlesWidget: _buildLeftTitle,
                          ),
                        ),

                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 36, // نفس الحجم
                            interval: _getInterval(),
                            getTitlesWidget: (value, _) {
                              return _buildXAxisTitle(value.toInt());
                            },
                          ),
                        ),
                      ),
                      borderData: FlBorderData(
                        show: true,
                        border: Border.all(color: Colors.grey[300]!, width: 1),
                      ),
                      lineBarsData: [
                        LineChartBarData(
                          spots: spots,
                          isCurved: true,
                          barWidth: 3, // نفس السماكة
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
                                ),
                              );
                            }).toList();
                          },
                        ),
                      ),
                    ),
                  ),
          ),

          const SizedBox(height: 8),
          _buildRangeNavigator(),

          /// 👇 الإحصائيات (نفس تشارت اليوزر)
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

  // DateTime _getEndDateForRange(String range) {
  //   final start = _getStartDateForRange(range);

  //   switch (range) {
  //     case 'اليوم':
  //       return start.add(const Duration(days: 1));
  //     case 'أسبوع':
  //       return start.add(const Duration(days: 7));
  //     case 'شهر':
  //       return DateTime(start.year, start.month + 1, 1);
  //     case 'سنة':
  //       return DateTime(start.year + 1, 1, 1);
  //     default:
  //       return DateTime.now();
  //   }
  // }

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
    String timeRange,
  ) {
    final double maxY = _getMaxYValue(spots);
    final double average = spots.isNotEmpty
        ? spots.map((e) => e.y).reduce((a, b) => a + b) / spots.length
        : 0;

    return Container(
      padding: const EdgeInsets.all(16), // نفس البادينج
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20), // نفس الزوايا
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
          /// العنوان + الفلتر (نفس التصميم)
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
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: color.withOpacity(0.3)),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedTimeRange,
                    icon: Icon(Icons.arrow_drop_down, size: 20, color: color),
                    onChanged: (v) {
                      if (v != null) {
                        setState(() {
                          _selectedTimeRange = v;
                        });
                        _loadChartData();
                      }
                    },
                    items: _timeRanges
                        .map(
                          (e) => DropdownMenuItem(
                            value: e,
                            child: Text(
                              e,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: appColors.dark,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          /// 👇 الرسم البياني العمودي
          SizedBox(
            height: 160, // نفس الارتفاع
            child: spots.isEmpty
                ? const Center(child: Text('لا توجد بيانات'))
                : BarChart(
                    BarChartData(
                      minY: 0,
                      maxY: maxY == 0 ? 3 : null,
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        horizontalInterval: maxY == 0
                            ? 1
                            : math.max(1, (maxY / 3).ceilToDouble()),
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
                            reservedSize: 36,
                            getTitlesWidget: _buildLeftTitle,
                          ),
                        ),

                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 36, // نفس الحجم
                            interval: _getInterval(),
                            getTitlesWidget: (value, _) {
                              return _buildXAxisTitle(value.toInt());
                            },
                          ),
                        ),
                      ),
                      borderData: FlBorderData(
                        show: true,
                        border: Border.all(color: Colors.grey[300]!, width: 1),
                      ),
                      barGroups: spots.map((spot) {
                        return BarChartGroupData(
                          x: spot.x.toInt(),
                          barRods: [
                            BarChartRodData(
                              toY: spot.y,
                              width: _getBarWidth(_selectedTimeRange),
                              borderRadius: BorderRadius.circular(4),
                              color: spot.y > 0 ? color : Colors.grey[300]!,
                              backDrawRodData: BackgroundBarChartRodData(
                                show: true,
                                toY: spot.y + 0.5,
                                color: Colors.grey[100]!,
                              ),
                            ),
                          ],
                        );
                      }).toList(),
                      barTouchData: BarTouchData(
                        enabled: true,
                        touchTooltipData: BarTouchTooltipData(
                          tooltipBgColor: color,
                          getTooltipItem: (group, _, rod, __) {
                            return BarTooltipItem(
                              '${rod.toY.toInt()}',
                              const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
          ),

          const SizedBox(height: 8),
          _buildRangeNavigator(),

          /// 👇 الإحصائيات (نفس تشارت اليوزر)
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

    return Column(
      children: [
        // الجزء العلوي - بطاقة الإجمالي (تم تصغيره)
        GestureDetector(
          onTap: () {
            setState(() {
              _isCarbonExpanded = !_isCarbonExpanded;
            });
          },
          child: Stack(
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(
                  14,
                  12,
                  14,
                  12,
                ), // قللنا البادينج
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16), // زوايا أقل
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.withOpacity(0.12),
                      blurRadius: 8, // ظل أخف
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    // 👇 تصغير دائرة التقدم
                    SizedBox(
                      width: 60, // قللنا العرض
                      height: 60, // قللنا الارتفاع
                      child: Stack(
                        children: [
                          CircularProgressIndicator(
                            value: progress,
                            strokeWidth: 6, // سماكة أقل
                            backgroundColor: Colors.teal.withOpacity(0.2),
                            color: Colors.teal,
                          ),
                          Center(
                            child: Text(
                              '${(progress * 100).toStringAsFixed(0)}%',
                              style: GoogleFonts.ibmPlexSansArabic(
                                fontSize: 12, // خط أصغر
                                fontWeight: FontWeight.w800,
                                color: Colors.teal,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(width: 12), // مسافة أقل
                    // 📄 النص والمعلومات
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min, // ارتفاع أدنى
                        children: [
                          Text(
                            'إجمالي توفير الكربون',
                            style: GoogleFonts.ibmPlexSansArabic(
                              fontSize: 14, // خط أصغر
                              fontWeight: FontWeight.w700,
                              color: appColors.dark,
                            ),
                          ),
                          const SizedBox(height: 2), // مسافة أقل
                          Text(
                            '${totalCarbon.toStringAsFixed(1)} كجم',
                            style: GoogleFonts.ibmPlexSansArabic(
                              fontSize: 12, // خط أصغر
                              fontWeight: FontWeight.w600,
                              color: Colors.grey[700],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // السهم في الزاوية اليمين العليا (تم تصغيره)
              Positioned(
                top: 8,
                left: 8,
                child: Icon(
                  _isCarbonExpanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  color: Colors.teal,
                  size: 18, // أيقونة أصغر
                ),
              ),
            ],
          ),
        ),

        // الجزء السفلي - الرسم البياني (يظهر فقط عند التوسيع)
        if (_isCarbonExpanded) ...[
          const SizedBox(height: 8), // مسافة أقل
          _buildExpandedCarbonChart(carbonSpots),
        ],
      ],
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
                'تطور توفير الكربون',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: appColors.dark,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.teal.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.teal.withOpacity(0.3)),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedTimeRange,
                    icon: Icon(
                      Icons.arrow_drop_down,
                      size: 20,
                      color: Colors.teal,
                    ),
                    onChanged: (v) {
                      if (v != null) {
                        setState(() {
                          _selectedTimeRange = v;
                        });
                        _loadChartData();
                      }
                    },
                    items: _timeRanges
                        .map(
                          (e) => DropdownMenuItem(
                            value: e,
                            child: Text(
                              e,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: appColors.dark,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          /// 👇 الرسم البياني
          SizedBox(
            height: 160,
            child: carbonSpots.isEmpty
                ? const Center(child: Text('لا توجد بيانات'))
                : BarChart(
                    BarChartData(
                      minY: 0,
                      maxY: maxY == 0 ? 10 : null,
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        horizontalInterval: maxY == 0
                            ? 1
                            : math.max(1, (maxY / 3).ceilToDouble()),
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
                            reservedSize: 36,
                            getTitlesWidget: _buildLeftTitle,
                          ),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 36,
                            interval: _getInterval(),
                            getTitlesWidget: (value, _) {
                              return _buildXAxisTitle(value.toInt());
                            },
                          ),
                        ),
                      ),
                      borderData: FlBorderData(
                        show: true,
                        border: Border.all(color: Colors.grey[300]!, width: 1),
                      ),
                      barGroups: carbonSpots.map((spot) {
                        return BarChartGroupData(
                          x: spot.x.toInt(),
                          barRods: [
                            BarChartRodData(
                              toY: spot.y,
                              width: _getBarWidth(_selectedTimeRange),
                              borderRadius: BorderRadius.circular(4),
                              color: spot.y > 0
                                  ? Colors.teal
                                  : Colors.grey[300]!,
                              backDrawRodData: BackgroundBarChartRodData(
                                show: true,
                                toY: spot.y + 0.5,
                                color: Colors.grey[100]!,
                              ),
                            ),
                          ],
                        );
                      }).toList(),
                      barTouchData: BarTouchData(
                        enabled: true,
                        touchTooltipData: BarTouchTooltipData(
                          tooltipBgColor: Colors.teal,
                          getTooltipItem: (group, _, rod, __) {
                            return BarTooltipItem(
                              '${rod.toY.toInt()} كجم',
                              const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
          ),

          const SizedBox(height: 8),
          _buildRangeNavigator(),

          /// 👇 الإحصائيات
          const SizedBox(height: 12),
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
                      final double totalPointsValue = totalPoints.toDouble();
                      final double totalTasksValue = totalCompletedTasks
                          .toDouble();
                      final double totalCarbonValue = totalCarbon.toDouble();
                      return Column(
                        children: [
                          _buildCarbonOverviewCard(
                            totalCarbon: totalCarbon,
                            carbonSpots: _carbonSpots,
                          ),

                          const SizedBox(height: 20),

                          SizedBox(
                            height: 400,
                            child: PageView(
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
                          ),

                          const SizedBox(
                            height: 16,
                          ), // قللت من الـ SizedBox هنا
                          // باقي الكود (طلبات المهام والبلاغات) يبقى كما هو...
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
                  const SizedBox(height: 14),

                  StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: FirebaseFirestore.instance
                        .collection('taskReports')
                        .where('decision', isEqualTo: 'pending')
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
                              builder: (_) => const AdminTaskReportsPage(),
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
                              color: appColors.accent.withOpacity(0.25),
                              width: 1.5,
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  color: appColors.accent.withOpacity(.14),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.report_gmailerrorred_rounded,
                                  color: appColors.accent,
                                ),
                              ),
                              const SizedBox(width: 12),

                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'بلاغات المهام للمراجعة',
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
                                                ? 'لا توجد بلاغات جديدة حالياً'
                                                : 'لديك $count بلاغ${count == 1 ? '' : 'ات'} بانتظار المراجعة'),
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
                                      color: appColors.accent.withOpacity(.14),
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Text(
                                      isLoading ? '—' : '$count',
                                      style: GoogleFonts.ibmPlexSansArabic(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w700,
                                        color: appColors.accent,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  const Icon(
                                    Icons.chevron_left,
                                    color: appColors.accent,
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

  // 🔧 دالة لعرض تسميات المحور X (نفس تشارت اليوزر)
  Widget _buildXAxisTitle(int index) {
    if (_selectedTimeRange == 'اليوم') {
      final showHours = [0, 3, 6, 9, 12, 15, 18, 21, 23];
      if (showHours.contains(index)) {
        return Text('$index', style: const TextStyle(fontSize: 10));
      }
      return const SizedBox();
    }

    if (_selectedTimeRange == 'أسبوع') {
      const days = ['أحد', 'إثن', 'ثلا', 'أرب', 'خم', 'جم', 'سبت'];
      if (index >= 0 && index < 7) {
        return Text(days[index], style: const TextStyle(fontSize: 10));
      }
      return const SizedBox();
    }

    if (_selectedTimeRange == 'شهر') {
      final day = index + 1;
      final lastDay = DateTime(_cursorDate.year, _cursorDate.month, 0).day;
      final showDays = [1, 5, 10, 15, 20, 25, lastDay];
      if (showDays.contains(day)) {
        return Text(day.toString(), style: const TextStyle(fontSize: 10));
      }
      return const SizedBox();
    }

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
    if (index >= 0 && index < 12) {
      return Text(months[index], style: const TextStyle(fontSize: 10));
    }
    return const SizedBox();
  }

  // 🔧 إحصائيات مصغرة (نفس تشارت اليوزر)
  Widget _buildCompactMiniStat(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: appColors.dark,
          ),
        ),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
      ],
    );
  }
}
