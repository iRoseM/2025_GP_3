// lib/pages/my_reports_page.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'services/title_header.dart';
import 'services/background_container.dart';
import '../services/app_colors.dart';

class MyReportsPage extends StatefulWidget {
  const MyReportsPage({super.key});

  @override
  State<MyReportsPage> createState() => _MyReportsPageState();
}

class _MyReportsPageState extends State<MyReportsPage> {
  Timestamp? lastOpened;

  @override
  void initState() {
    super.initState();
    _loadAndUpdateLastOpened();
  }

  Future<void> _loadAndUpdateLastOpened() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();

    lastOpened = userDoc.data()?['lastOpenedNotifications'] as Timestamp?;

    // حدّث الوقت الحالي كآخر زيارة
    await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
      'lastOpenedNotifications': FieldValue.serverTimestamp(),
    });

    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        extendBodyBehindAppBar: true,
        backgroundColor: appColors.background,
        appBar: const NameerAppBar(
          showTitleInBar: false,
          showBack: true,
          height: 80,
        ),
        body: Builder(
          builder: (context) {
            final statusBar = MediaQuery.of(context).padding.top;
            const headerH = 20.0;
            const gap = 12.0;
            final topPadding = statusBar + headerH + gap;

            return Padding(
              padding: EdgeInsets.fromLTRB(16, topPadding, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'إشعاراتي',
                    style: GoogleFonts.ibmPlexSansArabic(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: appColors.dark,
                    ),
                  ),
                  const SizedBox(height: 12),

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

                        // 🔥 لو lastOpened = null (أول مرة يدخل) نستخدم تاريخ قديم بحيث كله يعتبر "جديد"
                        final localLastOpened =
                            lastOpened?.toDate() ?? DateTime(2000);

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
                                  'لا توجد إشعارات مسجّلة لك حالياً 🌿',
                                  style: GoogleFonts.ibmPlexSansArabic(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: appColors.dark,
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
                            final ts = data['createdAt'] as Timestamp?;
                            final time = ts?.toDate();

                            final isNew =
                                ts != null &&
                                ts.toDate().isAfter(localLastOpened);

                            final title =
                                (data['title'] ?? data['header'] ?? '')
                                    .toString();
                            final message =
                                (data['message'] ?? data['body'] ?? '')
                                    .toString();
                            final type = (data['type'] ?? '').toString();

                            // ===== الأيقونات =====
                            IconData icon;
                            Color iconColor;

                            switch (type) {
                              case 'submission_approved':
                              case 'task_approved':
                                icon = Icons.verified_rounded;
                                iconColor = Colors.green;
                                break;
                              case 'submission_rejected':
                              case 'task_rejected':
                                icon = Icons.cancel_rounded;
                                iconColor = Colors.redAccent;
                                break;
                              default:
                                icon = Icons.notifications_active_outlined;
                                iconColor = appColors.sea;
                            }

                            return AnimatedContainer(
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeInOut,
                              margin: const EdgeInsets.symmetric(vertical: 8),
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: isNew
                                    ? appColors.mint.withOpacity(0.20)
                                    : Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black12.withOpacity(
                                      isNew ? 0.12 : 0.05,
                                    ),
                                    blurRadius: isNew ? 6 : 2,
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
                                  title.isEmpty ? 'إشعار' : title,
                                  style: GoogleFonts.ibmPlexSansArabic(
                                    fontWeight: FontWeight.w700,
                                    color: appColors.dark,
                                  ),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const SizedBox(height: 4),
                                    Text(
                                      message.isEmpty ? '—' : message,
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
