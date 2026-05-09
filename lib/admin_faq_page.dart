import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/app_colors.dart';
import 'services/title_header.dart'; // NameerAppBar
import 'services/background_container.dart'; // AnimatedBackgroundContainer

class AdminFaqPage extends StatefulWidget {
  const AdminFaqPage({super.key});

  @override
  State<AdminFaqPage> createState() => _AdminFaqPageState();
}

class _AdminFaqPageState extends State<AdminFaqPage> {
  Future<void> _openAddDialog() async {
    final qCtrl = TextEditingController();
    final aCtrl = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: Align(
              alignment: Alignment.centerRight,
              child: Text(
                'إضافة سؤال شائع',
                textAlign: TextAlign.right,
                style: GoogleFonts.ibmPlexSansArabic(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: qCtrl,
                  textAlign: TextAlign.right,
                  textDirection: TextDirection.rtl,
                  decoration: const InputDecoration(
                    labelText: 'السؤال',
                    alignLabelWithHint: true,
                    prefixIcon: Icon(Icons.help_outline),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: aCtrl,
                  maxLines: 4,
                  textAlign: TextAlign.right,
                  textDirection: TextDirection.rtl,
                  decoration: const InputDecoration(
                    labelText: 'الإجابة',
                    alignLabelWithHint: true,
                    prefixIcon: Icon(Icons.chat_bubble_outline),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(
                  'إلغاء',
                  style: GoogleFonts.ibmPlexSansArabic(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: appColors.primary,
                  foregroundColor: Colors.white,
                ),
                onPressed: () async {
                  final q = qCtrl.text.trim();
                  final a = aCtrl.text.trim();
                  if (q.isEmpty || a.isEmpty) return;

                  await FirebaseFirestore.instance.collection('faqs').add({
                    'q': q,
                    'a': a,
                    'createdAt': FieldValue.serverTimestamp(),
                  });

                  if (ctx.mounted) Navigator.pop(ctx);
                },
                child: Text(
                  'إضافة',
                  style: GoogleFonts.ibmPlexSansArabic(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openEditDialog({
    required String docId,
    required String initialQ,
    required String initialA,
  }) async {
    final qCtrl = TextEditingController(text: initialQ);
    final aCtrl = TextEditingController(text: initialA);

    await showDialog(
      context: context,
      builder: (ctx) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: Align(
              alignment: Alignment.centerRight,
              child: Text(
                'تعديل السؤال',
                textAlign: TextAlign.right,
                style: GoogleFonts.ibmPlexSansArabic(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: qCtrl,
                  textAlign: TextAlign.right,
                  textDirection: TextDirection.rtl,
                  decoration: const InputDecoration(
                    labelText: 'السؤال',
                    alignLabelWithHint: true,
                    prefixIcon: Icon(Icons.help_outline),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: aCtrl,
                  maxLines: 4,
                  textAlign: TextAlign.right,
                  textDirection: TextDirection.rtl,
                  decoration: const InputDecoration(
                    labelText: 'الإجابة',
                    alignLabelWithHint: true,
                    prefixIcon: Icon(Icons.chat_bubble_outline),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(
                  'إلغاء',
                  style: GoogleFonts.ibmPlexSansArabic(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: appColors.primary,
                  foregroundColor: Colors.white,
                ),
                onPressed: () async {
                  final q = qCtrl.text.trim();
                  final a = aCtrl.text.trim();
                  if (q.isEmpty || a.isEmpty) return;

                  await FirebaseFirestore.instance
                      .collection('faqs')
                      .doc(docId)
                      .update({'q': q, 'a': a});

                  if (ctx.mounted) Navigator.pop(ctx);
                },
                child: Text(
                  'حفظ',
                  style: GoogleFonts.ibmPlexSansArabic(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _confirmDelete(String docId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text(
            'حذف السؤال؟',
            textAlign: TextAlign.right,
            style: GoogleFonts.ibmPlexSansArabic(fontWeight: FontWeight.w800),
          ),
          content: Text(
            'هل تريد تأكيد حذف السؤال؟ سيتم حذف السؤال نهائيًا.',
            textAlign: TextAlign.right,
            style: GoogleFonts.ibmPlexSansArabic(height: 1.5),
          ),
          actionsAlignment: MainAxisAlignment.start, // RTL → يمين
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(
                'إلغاء',
                style: GoogleFonts.ibmPlexSansArabic(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 10,
                ),
                shape: const StadiumBorder(), // كبسولة
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(
                'حذف',
                style: GoogleFonts.ibmPlexSansArabic(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );

    if (ok == true) {
      await FirebaseFirestore.instance.collection('faqs').doc(docId).delete();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        extendBody: true,
        extendBodyBehindAppBar: true,
        backgroundColor: Colors.transparent,
        appBar: const NameerAppBar(showTitleInBar: false, showBack: true),
        floatingActionButton: FloatingActionButton(
          backgroundColor: appColors.primary,
          onPressed: _openAddDialog,
          child: const Icon(Icons.add, color: Colors.white),
        ),
        body: AnimatedBackgroundContainer(
          child: Builder(
            builder: (context) {
              final statusBar = MediaQuery.of(context).padding.top;
              const headerH = 20.0;
              const gap = 12.0;
              final topPadding = statusBar + headerH + gap;

              return SafeArea(
                top: false,
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(16, topPadding, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'إدارة الأسئلة الشائعة',
                        style: GoogleFonts.ibmPlexSansArabic(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: appColors.dark,
                        ),
                      ),
                      const SizedBox(height: 16),

                      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        stream: FirebaseFirestore.instance
                            .collection('faqs')
                            .orderBy('createdAt', descending: true)
                            .snapshots(),
                        builder: (context, snap) {
                          if (snap.connectionState == ConnectionState.waiting) {
                            return const Center(
                              child: CircularProgressIndicator(
                                color: appColors.primary,
                              ),
                            );
                          }

                          if (!snap.hasData || snap.data!.docs.isEmpty) {
                            return Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: const Color(0xFFE8F1EE),
                                  width: 1.2,
                                ),
                              ),
                              child: Text(
                                'لا يوجد أسئلة حالياً اضغط + لإضافة سؤال.',
                                style: GoogleFonts.ibmPlexSansArabic(
                                  fontWeight: FontWeight.w700,
                                  color: appColors.dark.withOpacity(.8),
                                ),
                              ),
                            );
                          }

                          final docs = snap.data!.docs;

                          return Container(
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: const Color(0xFFE8F1EE),
                                width: 1.2,
                              ),
                              boxShadow: const [
                                BoxShadow(
                                  blurRadius: 10,
                                  offset: Offset(0, 6),
                                  color: Color(0x14000000),
                                ),
                              ],
                            ),
                            child: ListView.separated(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: docs.length,
                              separatorBuilder: (_, __) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, i) {
                                final doc = docs[i];
                                final d = doc.data();
                                final q = (d['q'] ?? '').toString();
                                final a = (d['a'] ?? '').toString();

                                return Theme(
                                  data: Theme.of(
                                    context,
                                  ).copyWith(dividerColor: Colors.transparent),
                                  child: ExpansionTile(
                                    tilePadding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 4,
                                    ),
                                    childrenPadding: const EdgeInsets.fromLTRB(
                                      16,
                                      0,
                                      16,
                                      14,
                                    ),
                                    leading: const Icon(
                                      Icons.quiz_outlined,
                                      color: appColors.primary,
                                    ),
                                    title: Text(
                                      q,
                                      style: GoogleFonts.ibmPlexSansArabic(
                                        fontWeight: FontWeight.w800,
                                        color: appColors.dark,
                                      ),
                                    ),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          icon: const Icon(
                                            Icons.edit,
                                            color: appColors.primary,
                                          ),
                                          onPressed: () => _openEditDialog(
                                            docId: doc.id,
                                            initialQ: q,
                                            initialA: a,
                                          ),
                                        ),
                                        IconButton(
                                          icon: const Icon(
                                            Icons.delete,
                                            color: Colors.redAccent,
                                          ),
                                          onPressed: () =>
                                              _confirmDelete(doc.id),
                                        ),
                                      ],
                                    ),

                                    children: [
                                      Align(
                                        alignment: Alignment.centerRight,
                                        child: Text(
                                          a,
                                          style: GoogleFonts.ibmPlexSansArabic(
                                            color: appColors.dark.withOpacity(
                                              .85,
                                            ),
                                            height: 1.6,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
