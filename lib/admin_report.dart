import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'admin_bottom_nav.dart';
import 'admin_home.dart';
import 'admin_task.dart';
import 'admin_map.dart';
import 'admin_reward.dart';

class AdminReportPage extends StatefulWidget {
  const AdminReportPage({super.key});

  @override
  State<AdminReportPage> createState() => _AdminReportPageState();
}

class _AdminReportPageState extends State<AdminReportPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _currentIndex = 1; // لأننا جايين من الخريطة غالباً

  final List<Map<String, String>> unresolvedReports = [
    {
      'title': 'امتلاء الحاوية',
      'desc': 'حاوية القوارير في حي النخيل ممتلئة بالكامل.',
    },
    {
      'title': 'تلف الحاوية',
      'desc': 'حاوية الملابس في حي الياسمين مكسورة وتحتاج صيانة.',
    },
  ];

  final List<Map<String, String>> resolvedReports = [
    {
      'title': 'تم استبدال الحاوية',
      'desc': 'تم تركيب حاوية جديدة بدل التالفة في حي العليا.',
    },
  ];

  void _onTap(int i) {
    if (i == _currentIndex) return;
    switch (i) {
      case 0:
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const AdminHomePage()),
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
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const AdminRewardsPage()),
        );
        break;
    }
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  Widget build(BuildContext context) {
    final baseTheme = Theme.of(context);
    final textTheme = GoogleFonts.ibmPlexSansArabicTextTheme(
      baseTheme.textTheme,
    );
    final isKeyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;

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
          ),
        ),
        child: Scaffold(
          appBar: AppBar(
            centerTitle: true,
            title: const Text("التقارير"),
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
            bottom: TabBar(
              controller: _tabController,
              indicatorColor: Colors.black,
              labelColor: Colors.black,
              unselectedLabelColor: Colors.black54,
              labelStyle: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
              tabs: const [
                Tab(text: 'قيد المراجعة'),
                Tab(text: 'تمت المعالجة'),
              ],
            ),
          ),
          body: TabBarView(
            controller: _tabController,
            children: [
              _buildReportList(unresolvedReports, false),
              _buildReportList(resolvedReports, true),
            ],
          ),
          bottomNavigationBar: isKeyboardOpen
              ? null
              : AdminBottomNav(currentIndex: _currentIndex, onTap: _onTap),
        ),
      ),
    );
  }

  Widget _buildReportList(List<Map<String, String>> reports, bool resolved) {
    if (reports.isEmpty) {
      return const Center(
        child: Text(
          'لا توجد تقارير حالياً 📭',
          style: TextStyle(fontSize: 16, color: Colors.black54),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: reports.length,
      itemBuilder: (context, i) {
        final r = reports[i];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Colors.black12),
          ),
          child: ListTile(
            title: Text(
              r['title']!,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(r['desc']!),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!resolved)
                  IconButton(
                    icon: const Icon(Icons.check_circle, color: Colors.black),
                    tooltip: 'تمييز كمُعالَج',
                    onPressed: () {
                      setState(() {
                        resolvedReports.add(r);
                        unresolvedReports.remove(r);
                      });
                    },
                  ),
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  tooltip: 'حذف التقرير',
                  onPressed: () {
                    setState(() {
                      reports.remove(r);
                    });
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
