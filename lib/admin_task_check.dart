import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';

// 🧭 نفس ستايل صفحات الأدمن
import 'services/admin_bottom_nav.dart';
import 'admin_home.dart';
import 'admin_task.dart';
import 'admin_map.dart';
import 'services/background_container.dart';
import 'services/connection.dart';
import 'services/title_header.dart';

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

class AdminTaskCheckPage extends StatefulWidget {
  const AdminTaskCheckPage({super.key});

  @override
  State<AdminTaskCheckPage> createState() => _AdminTaskCheckPageState();
}

class _AdminTaskCheckPageState extends State<AdminTaskCheckPage> {
  int _currentIndex = 2;

  @override
  void initState() {
    super.initState();
    _checkConnection();
  }

  Future<void> _checkConnection() async {
    if (!await hasInternetConnection()) {
      if (mounted) showNoInternetDialog(context);
    }
  }

  void _onTap(int i) {
    if (i == _currentIndex) return;
    switch (i) {
      case 0:
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
          MaterialPageRoute(builder: (_) => const AdminHomePage()),
        );
        break;
    }
  }

  // 🔎 سحب طلبات المراجعة (بدون orderBy مؤقتاً)
  Stream<QuerySnapshot> _pendingSubs() {
    return FirebaseFirestore.instance
        .collection('submissions')
        .where('status', isEqualTo: 'pending')
        // .orderBy('createdAt', descending: true) // ⏳ مؤقتاً حتى ينشئ الفهرس
        .snapshots();
  }

  // ✅ اعتماد
  Future<void> _approve(BuildContext context, DocumentSnapshot subDoc) async {
    final data = subDoc.data() as Map<String, dynamic>;
    final userTaskDocId = data['userTaskDocId'] as String;
    final userId = data['userId'] as String;
    final taskPoints = (data['taskPoints'] ?? 0) as int;

    final usersRef = FirebaseFirestore.instance.collection('users').doc(userId);
    final utRef = FirebaseFirestore.instance
        .collection('userTasks')
        .doc(userTaskDocId);
    final subRef = subDoc.reference;

    final admin = FirebaseAuth.instance.currentUser;

    try {
      await FirebaseFirestore.instance.runTransaction((trx) async {
        final subSnap = await trx.get(subRef);
        if (!subSnap.exists) throw 'الطلب غير موجود.';
        final sub = subSnap.data() as Map<String, dynamic>;
        if (sub['status'] != 'pending') {
          throw 'تمت معالجة هذا الطلب مسبقاً.';
        }

        final utSnap = await trx.get(utRef);
        if (!utSnap.exists) throw 'userTask غير موجود.';
        final ut = utSnap.data() as Map<String, dynamic>;
        final currentStatus = ut['status'] as String? ?? 'pending';
        final canComplete = (currentStatus != 'completed');

        // submissions → approved
        trx.update(subRef, {
          'status': 'approved',
          'processedAt': FieldValue.serverTimestamp(),
          'processedBy': admin?.uid,
        });

        // userTasks → completed
        trx.update(utRef, {
          'status': 'completed',
          'completedAt': FieldValue.serverTimestamp(),
        });

        // نقاط المستخدم (مرة واحدة فقط)
        if (canComplete && taskPoints > 0) {
          trx.update(usersRef, {'points': FieldValue.increment(taskPoints)});
        }

        // سجل تاريخ
        final historyRef = FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .collection('history')
            .doc();
        trx.set(historyRef, {
          'type': 'task_approved',
          'userTaskDocId': userTaskDocId,
          'submissionId': subRef.id,
          'points': taskPoints,
          'at': FieldValue.serverTimestamp(),
        });
      });

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم اعتماد الطلب وتحديث النقاط ✅')),
        );
      }
    } catch (e) {
      print('❌ خطأ في الاعتماد: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('خطأ: $e')));
      }
    }
  }

  // ❌ رفض
  Future<void> _reject(BuildContext context, DocumentSnapshot subDoc) async {
    final admin = FirebaseAuth.instance.currentUser;
    final data = subDoc.data() as Map<String, dynamic>;
    final userTaskDocId = data['userTaskDocId'] as String;

    final subRef = subDoc.reference;
    final utRef = FirebaseFirestore.instance
        .collection('userTasks')
        .doc(userTaskDocId);

    try {
      await FirebaseFirestore.instance.runTransaction((trx) async {
        final subSnap = await trx.get(subRef);
        if (!subSnap.exists) throw 'الطلب غير موجود.';
        final sub = subSnap.data() as Map<String, dynamic>;
        if (sub['status'] != 'pending') {
          throw 'تمت معالجة هذا الطلب مسبقاً.';
        }

        trx.update(subRef, {
          'status': 'rejected',
          'processedAt': FieldValue.serverTimestamp(),
          'processedBy': admin?.uid,
        });

        // userTasks → rejected
        trx.update(utRef, {
          'status': 'rejected',
          'rejectedAt': FieldValue.serverTimestamp(),
        });
      });

      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('تم رفض الطلب ❌')));
      }
    } catch (e) {
      print('❌ خطأ في الرفض: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('خطأ: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final baseTheme = Theme.of(context);
    final textTheme = GoogleFonts.ibmPlexSansArabicTextTheme(
      baseTheme.textTheme,
    );

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Theme(
        data: baseTheme.copyWith(
          textTheme: textTheme,
          primaryTextTheme: textTheme,
          appBarTheme: const AppBarTheme(
            backgroundColor: Colors.transparent,
            elevation: 0,
            iconTheme: IconThemeData(color: Colors.white),
          ),
        ),
        child: Scaffold(
          extendBody: true,
          extendBodyBehindAppBar: true,
          backgroundColor: Colors.transparent,

          appBar: const NameerAppBar(showTitleInBar: false, showBack: true),

          body: AnimatedBackgroundContainer(
            child: Builder(
              builder: (context) {
                final statusBar = MediaQuery.of(context).padding.top;
                const headerH = 20.0;
                const fadeH = 0.0;
                const gap = 12.0;
                final topPadding = statusBar + headerH + fadeH + gap;

                return Padding(
                  padding: EdgeInsets.fromLTRB(16, topPadding, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'مراجعة المهام',
                        style: GoogleFonts.ibmPlexSansArabic(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: AppColors.dark,
                        ),
                      ),
                      const SizedBox(height: 15),

                      Expanded(
                        child: StreamBuilder<QuerySnapshot>(
                          stream: _pendingSubs(),
                          builder: (context, snap) {
                            if (snap.connectionState ==
                                ConnectionState.waiting) {
                              return const Center(
                                child: CircularProgressIndicator(),
                              );
                            }

                            if (snap.hasError) {
                              return Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(
                                      Icons.error_outline,
                                      size: 64,
                                      color: Colors.red,
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      'خطأ في تحميل البيانات',
                                      style: GoogleFonts.ibmPlexSansArabic(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.dark,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      '${snap.error}',
                                      style: GoogleFonts.ibmPlexSansArabic(
                                        fontSize: 12,
                                        color: Colors.grey,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                    const SizedBox(height: 20),
                                    ElevatedButton(
                                      onPressed: () => setState(() {}),
                                      child: Text(
                                        'إعادة المحاولة',
                                        style: GoogleFonts.ibmPlexSansArabic(),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }

                            if (!snap.hasData || snap.data!.docs.isEmpty) {
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
                                      'لا توجد طلبات قيد الانتظار.',
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

                            final docs = snap.data!.docs;

                            return ListView.separated(
                              padding: const EdgeInsets.only(bottom: 12),
                              itemCount: docs.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 12),
                              itemBuilder: (context, i) {
                                final d = docs[i];
                                final m = d.data() as Map<String, dynamic>;
                                final images =
                                    (m['imageUrls'] as List?)?.cast<String>() ??
                                    [];

                                return Card(
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  elevation: 2,
                                  child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          m['taskTitle'] ?? '(بدون عنوان)',
                                          style: GoogleFonts.ibmPlexSansArabic(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 16,
                                            color: AppColors.dark,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'المستخدم: ${m['userId']} • النقاط: ${m['taskPoints'] ?? 0}',
                                          style: GoogleFonts.ibmPlexSansArabic(
                                            fontSize: 13,
                                            color: Colors.grey[700],
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        if (images.isNotEmpty)
                                          Wrap(
                                            spacing: 8,
                                            runSpacing: 8,
                                            children: images
                                                .map(
                                                  (url) => ClipRRect(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          12,
                                                        ),
                                                    child: Image.network(
                                                      url,
                                                      height: 100,
                                                      width: 100,
                                                      fit: BoxFit.cover,
                                                      errorBuilder: (context, error, stackTrace) {
                                                        return Container(
                                                          height: 100,
                                                          width: 100,
                                                          decoration: BoxDecoration(
                                                            color: Colors
                                                                .grey[200],
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                  12,
                                                                ),
                                                          ),
                                                          child: Column(
                                                            mainAxisAlignment:
                                                                MainAxisAlignment
                                                                    .center,
                                                            children: [
                                                              Icon(
                                                                Icons
                                                                    .error_outline,
                                                                color: Colors
                                                                    .grey[500],
                                                                size: 30,
                                                              ),
                                                              const SizedBox(
                                                                height: 4,
                                                              ),
                                                              Text(
                                                                'خطأ في التحميل',
                                                                style: GoogleFonts.ibmPlexSansArabic(
                                                                  fontSize: 10,
                                                                  color: Colors
                                                                      .grey[600],
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                        );
                                                      },
                                                    ),
                                                  ),
                                                )
                                                .toList(),
                                          )
                                        else
                                          Container(
                                            height: 100,
                                            width: double.infinity,
                                            decoration: BoxDecoration(
                                              color: Colors.grey[100],
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              border: Border.all(
                                                color: Colors.grey.shade300,
                                              ),
                                            ),
                                            child: Column(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                Icon(
                                                  Icons.photo_library_outlined,
                                                  color: Colors.grey[400],
                                                  size: 40,
                                                ),
                                                const SizedBox(height: 8),
                                                Text(
                                                  'لا توجد صور مرفوعة',
                                                  style:
                                                      GoogleFonts.ibmPlexSansArabic(
                                                        fontSize: 12,
                                                        color: Colors.grey[600],
                                                      ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        const SizedBox(height: 10),
                                        Row(
                                          children: [
                                            Expanded(
                                              child: ElevatedButton.icon(
                                                onPressed: () =>
                                                    _approve(context, d),
                                                icon: const Icon(
                                                  Icons.check_circle_outline,
                                                ),
                                                label: const Text('اعتماد'),
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor:
                                                      AppColors.primary,
                                                  foregroundColor: Colors.white,
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        vertical: 12,
                                                      ),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: OutlinedButton.icon(
                                                onPressed: () =>
                                                    _reject(context, d),
                                                icon: const Icon(
                                                  Icons.cancel_outlined,
                                                ),
                                                label: const Text('رفض'),
                                                style: OutlinedButton.styleFrom(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        vertical: 12,
                                                      ),
                                                  side: const BorderSide(
                                                    color: AppColors.primary,
                                                    width: 2,
                                                  ),
                                                  foregroundColor:
                                                      AppColors.primary,
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
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
