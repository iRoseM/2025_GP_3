// lib/pages/my_reports_page.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'services/title_header.dart';
import 'services/background_container.dart';

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

class MyReportsPage extends StatefulWidget {
  const MyReportsPage({super.key});

  @override
  State<MyReportsPage> createState() => _MyReportsPageState();
}

class _MyReportsPageState extends State<MyReportsPage> {
  @override
  void dispose() {
    _markAllAsRead(); // ✅ يخلي الإشعارات كمقروء لما المستخدم يطلع
    super.dispose();
  }

  Future<void> _markAllAsRead() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final query = await FirebaseFirestore.instance
        .collection('notifications')
        .where('userId', isEqualTo: user.uid)
        .where('read', isEqualTo: false)
        .get();

    for (var doc in query.docs) {
      await doc.reference.update({'read': true});
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        // نمد الجسم خلف الهيدر ونخلي الخلفية شفافة
        extendBodyBehindAppBar: true,
        backgroundColor: AppColors.background,

        // هيدر نمير العام (بدون عنوان داخله + مع زر رجوع)
        appBar: const NameerAppBar(
          showTitleInBar: false,
          showBack: true,
          height: 80,
        ),

        body: Builder(
          builder: (context) {
            final statusBar = MediaQuery.of(context).padding.top;
            const headerH = 20.0; // ارتفاع شريط الأدوات الفعلي
            const gap = 12.0; // مسافة بسيطة بعد الهيدر
            final topPadding = statusBar + headerH + gap;

            return Padding(
              padding: EdgeInsets.fromLTRB(16, topPadding, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // العنوان تحت الهيدر مباشرة
                  Text(
                    'بلاغاتي',
                    style: GoogleFonts.ibmPlexSansArabic(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: AppColors.dark,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // المحتوى
                  Expanded(
                    child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: FirebaseFirestore.instance
                          .collection('notifications')
                          .where('userId', isEqualTo: user!.uid)
                          .orderBy('createdAt', descending: true)
                          .snapshots(),
                      builder: (context, snap) {
                        if (snap.hasError) {
                          return const Center(
                            child: Text('حدث خطأ أثناء تحميل الإشعارات'),
                          );
                        }
                        if (!snap.hasData) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }

                        final docs = snap.data!.docs;

                        if (docs.isEmpty) {
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
                                  'لا توجد بلاغات مسجّلة لك حالياً 🌿',
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

                        return ListView.builder(
                          padding: const EdgeInsets.only(top: 4),
                          itemCount: docs.length,
                          itemBuilder: (context, i) {
                            final data = docs[i].data();
                            final isRead = data['read'] == true;

                            final title = data['title'] ?? '';
                            final message = data['message'] ?? '';
                            final ts = data['createdAt'] as Timestamp?;
                            final time = ts?.toDate();

                            IconData icon;
                            Color iconColor;

                            if (title.contains('تم معالجة')) {
                              icon = Icons.check_circle;
                              iconColor = Colors.green;
                            } else {
                              icon = Icons.cancel_outlined;
                              iconColor = Colors.redAccent;
                            }

                            return AnimatedContainer(
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeInOut,
                              margin: const EdgeInsets.symmetric(vertical: 8),
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: isRead
                                    ? AppColors.mint.withOpacity(0.20)
                                    : Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black12.withOpacity(
                                      isRead ? 0.05 : 0.15,
                                    ),
                                    blurRadius: isRead ? 2 : 6,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: iconColor.withOpacity(.15),
                                  child: Icon(icon, color: iconColor),
                                ),
                                title: Text(
                                  title,
                                  style: GoogleFonts.ibmPlexSansArabic(
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.dark,
                                  ),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const SizedBox(height: 4),
                                    Text(
                                      message,
                                      style: GoogleFonts.ibmPlexSansArabic(
                                        fontSize: 14,
                                        color: Colors.black87,
                                      ),
                                    ),
                                    if (time != null) ...[
                                      const SizedBox(height: 6),
                                      Text(
                                        '${time.year}/${time.month}/${time.day} - '
                                        '${time.hour}:${time.minute.toString().padLeft(2, '0')}',
                                        style: GoogleFonts.ibmPlexSansArabic(
                                          fontSize: 12,
                                          color: Colors.grey,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
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
        ),
      ),
    );
  }
}
