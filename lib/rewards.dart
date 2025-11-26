import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';

import 'services/background_container.dart';
import 'services/title_header.dart';
import '../services/app_colors.dart';

class RewardsPage extends StatefulWidget {
  const RewardsPage({super.key});
  @override
  State<RewardsPage> createState() => _RewardsPageState();
}

class _RewardsPageState extends State<RewardsPage> {
  Timer? _expireTimer;

  @override
  void initState() {
    super.initState();
    _expireOldRedemptionsForCurrentUser();
    _expireTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      _expireOldRedemptionsForCurrentUser();
    });
  }

  @override
  void dispose() {
    _expireTimer?.cancel();
    super.dispose();
  }

  // 🔥 تحديث تلقائي للحالات المنتهية
  Future<void> _expireOldRedemptionsForCurrentUser() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final now = Timestamp.now();
      final qs = await FirebaseFirestore.instance
          .collection('redemptions')
          .where('userID', isEqualTo: user.uid)
          .where('status', isEqualTo: 'completed')
          .where('expiresAt', isLessThanOrEqualTo: now)
          .get();

      if (qs.docs.isEmpty) return;

      final batch = FirebaseFirestore.instance.batch();
      for (final doc in qs.docs) {
        batch.update(doc.reference, {'status': 'expired'});
      }
      await batch.commit();
    } catch (e) {
      debugPrint('⚠️ خطأ أثناء تحديث حالات الاستبدال المنتهية: $e');
    }
  }

  Stream<QuerySnapshot> getActiveRewards() {
    return FirebaseFirestore.instance
        .collection('rewards')
        .where('isActive', isEqualTo: true)
        .snapshots();
  }

  String generateUniqueCode({int length = 8}) {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = DateTime.now().millisecondsSinceEpoch;
    return List.generate(length, (index) {
      final idx = (random + index * 37) % chars.length;
      return chars[idx];
    }).join();
  }

  // 🧠 منطق استبدال المكافأة
  Future<void> _redeemReward(
    BuildContext context,
    Map<String, dynamic> data,
  ) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'الرجاء تسجيل الدخول أولاً',
            style: GoogleFonts.ibmPlexSansArabic(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
      return;
    }

    final rewardID = data['id'] ?? '';
    final rewardTitle = data['title'] ?? 'مكافأة';
    final cost = data['costPoints'] ?? 0;
    final couponCode = generateUniqueCode();

    final userRef = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid);
    final redemptionRef = FirebaseFirestore.instance
        .collection('redemptions')
        .doc();

    try {
      await FirebaseFirestore.instance.runTransaction((tx) async {
        final userDoc = await tx.get(userRef);
        if (!userDoc.exists) throw Exception('المستخدم غير موجود.');

        final currentPoints = (userDoc.data()?['points'] ?? 0) as int;

        // انشاء السجل أولاً بحالة pending
        tx.set(redemptionRef, {
          'userID': user.uid,
          'rewardID': rewardID,
          'code': couponCode,
          'status': 'pending',
          //'redeemedAt': FieldValue.serverTimestamp(),
        });

        // التحقق من الرصيد
        if (currentPoints < cost) {
          tx.update(redemptionRef, {
            'status': 'failed',
            'reason': 'رصيدك غير كافٍ',
          });
          throw Exception('رصيدك لا يكفي لاستبدال هذه المكافأة.');
        }

        // خصم النقاط
        tx.update(userRef, {'points': currentPoints - cost});

        // إكمال العملية + انتهاء الصلاحية بعد 10 دقائق
        final expiresAt = DateTime.now().add(const Duration(minutes: 10));
        tx.update(redemptionRef, {
          'status': 'completed',
          'rewardTitle': rewardTitle,
          'costPoints': cost,
          'expiresAt': Timestamp.fromDate(expiresAt),
          'createdAt': FieldValue.serverTimestamp(),
        });
      });

      _showCouponPopup(
        context,
        rewardTitle: rewardTitle,
        couponCode: couponCode,
        expiresAt: DateTime.now().add(const Duration(minutes: 10)),
      );

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: slackMesseges.primary,
          content: Text(
            'تم استبدال "$rewardTitle" بنجاح 🎉',
            style: GoogleFonts.ibmPlexSansArabic(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    } catch (e) {
      final scaffoldContext = context;

      String message = 'تعذر تنفيذ الاستبدال مؤقتًا، حاول مرة أخرى بعد لحظات ';
      if (e.toString().contains('رصيدك لا يكفي')) {
        message = 'رصيدك الحالي لا يكفي لاستبدال هذه المكافأة ';
      } else if (e.toString().contains('المستخدم غير موجود')) {
        message = 'حدث خلل في حسابك، يرجى تسجيل الدخول من جديد.';
      }

      ScaffoldMessenger.of(scaffoldContext).showSnackBar(
        SnackBar(
          backgroundColor: slackMesseges.red,
          content: Text(
            message,
            style: GoogleFonts.ibmPlexSansArabic(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    }
  }

  // 🎁 بوب-أب عرض الكود مع العدّاد
  void _showCouponPopup(
    BuildContext context, {
    required String rewardTitle,
    required String couponCode,
    required DateTime expiresAt,
  }) {
    Duration remaining = expiresAt.difference(DateTime.now());
    late Timer timer;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSt) {
            timer = Timer.periodic(const Duration(seconds: 1), (t) {
              final diff = expiresAt.difference(DateTime.now());
              if (diff.inSeconds <= 0) {
                t.cancel();
                if (ctx.mounted) setSt(() => remaining = Duration.zero);
              } else {
                if (ctx.mounted) setSt(() => remaining = diff);
              }
            });

            String format(Duration d) {
              final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
              final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
              return "$m:$s";
            }

            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              title: Text(
                remaining.inSeconds > 0
                    ? '🎉 تم استبدال المكافأة'
                    : '⏱️ انتهت صلاحية الكود',
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    rewardTitle,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 10),
                  SelectableText(
                    couponCode,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: remaining.inSeconds > 0
                          ? appColors.accent
                          : Colors.grey,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (remaining.inSeconds > 0)
                    Column(
                      children: [
                        const Text(
                          ': الوقت المتبقي لاستخدام الكود',
                          style: TextStyle(color: appColors.dark),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          format(remaining),
                          style: const TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w900,
                            color: appColors.primary,
                          ),
                        ),
                      ],
                    )
                  else
                    const Text(
                      'انتهى الوقت ❌',
                      style: TextStyle(
                        color: slackMesseges.red,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                ],
              ),
              actionsAlignment: MainAxisAlignment.center,
              actions: [
                FilledButton.icon(
                  icon: const Icon(Icons.copy, color: Colors.white, size: 18),
                  style: FilledButton.styleFrom(
                    backgroundColor: remaining.inSeconds > 0
                        ? appColors.primary
                        : Colors.grey,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: remaining.inSeconds > 0
                      ? () async {
                          await Clipboard.setData(
                            ClipboardData(text: couponCode),
                          );
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              backgroundColor: slackMesseges.primary,
                              content: Text(
                                'تم نسخ الكود إلى الحافظة ✅',
                                style: GoogleFonts.ibmPlexSansArabic(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          );
                        }
                      : null,
                  label: const Text('نسخ الكود'),
                ),
                TextButton(
                  onPressed: () {
                    timer.cancel();
                    Navigator.pop(ctx);
                  },
                  child: const Text('تم'),
                ),
              ],
            );
          },
        );
      },
    );
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
          scaffoldBackgroundColor: Colors.transparent,
        ),
        child: Scaffold(
          extendBody: true,
          extendBodyBehindAppBar: true,
          backgroundColor: Colors.transparent,

          appBar: const NameerAppBar(
            showTitleInBar: false,
            showBack: true,
            height: 80,
          ),

          body: AnimatedBackgroundContainer(
            child: Builder(
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
                        'الجوائز والمكافآت',
                        style: GoogleFonts.ibmPlexSansArabic(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: appColors.dark,
                        ),
                      ),
                      const SizedBox(height: 12),

                      Expanded(
                        child: StreamBuilder<QuerySnapshot>(
                          stream: getActiveRewards(),
                          builder: (context, snapshot) {
                            if (snapshot.connectionState ==
                                ConnectionState.waiting) {
                              return const Center(
                                child: CircularProgressIndicator(),
                              );
                            }
                            if (!snapshot.hasData ||
                                snapshot.data!.docs.isEmpty) {
                              return const Center(
                                child: Text('لا توجد مكافآت متاحة حالياً'),
                              );
                            }

                            final rewards = snapshot.data!.docs;
                            return ListView.builder(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 0,
                                vertical: 8,
                              ),
                              itemCount: rewards.length,
                              itemBuilder: (context, i) {
                                final data =
                                    rewards[i].data() as Map<String, dynamic>;
                                data['id'] = rewards[i].id;

                                return Card(
                                  margin: const EdgeInsets.symmetric(
                                    vertical: 10,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  elevation: 4,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      if ((data['imageUrl'] ?? '')
                                          .toString()
                                          .isNotEmpty)
                                        ClipRRect(
                                          borderRadius: const BorderRadius.only(
                                            topLeft: Radius.circular(16),
                                            topRight: Radius.circular(16),
                                          ),
                                          child: Image.network(
                                            data['imageUrl'],
                                            width: double.infinity,
                                            height: 220,
                                            fit: BoxFit.cover,
                                          ),
                                        )
                                      else
                                        Container(
                                          height: 200,
                                          decoration: const BoxDecoration(
                                            color: appColors.primary33,
                                            borderRadius: BorderRadius.only(
                                              topLeft: Radius.circular(16),
                                              topRight: Radius.circular(16),
                                            ),
                                          ),
                                          child: const Icon(
                                            Icons.card_giftcard,
                                            color: appColors.primary,
                                            size: 60,
                                          ),
                                        ),
                                      Padding(
                                        padding: const EdgeInsets.all(16.0),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              data['title'] ?? '',
                                              style: const TextStyle(
                                                fontSize: 20,
                                                fontWeight: FontWeight.w700,
                                                color: appColors.dark,
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                            Text(
                                              data['description'] ?? '',
                                              style: const TextStyle(
                                                fontSize: 15,
                                                color: appColors.dark,
                                              ),
                                            ),
                                            const SizedBox(height: 12),
                                            Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment
                                                      .spaceBetween,
                                              children: [
                                                Row(
                                                  children: [
                                                    const Icon(
                                                      Icons.star_rate_rounded,
                                                      color: appColors.accent,
                                                      size: 20,
                                                    ),
                                                    const SizedBox(width: 6),
                                                    Text(
                                                      'تكلفة الاستبدال: ${data['costPoints']} نقطة',
                                                      style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        color: appColors.sea,
                                                        fontSize: 15,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 18),
                                            DecoratedBox(
                                              decoration: BoxDecoration(
                                                borderRadius:
                                                    BorderRadius.circular(14),
                                                gradient: const LinearGradient(
                                                  colors: [
                                                    appColors.mint,
                                                    appColors.primary,
                                                    appColors.primary,
                                                  ],
                                                  begin: Alignment.centerRight,
                                                  end: Alignment.centerLeft,
                                                ),
                                                boxShadow: const [
                                                  BoxShadow(
                                                    color: Color(0x33000000),
                                                    blurRadius: 8,
                                                    offset: Offset(0, 4),
                                                  ),
                                                ],
                                              ),
                                              child: FilledButton.icon(
                                                icon: const Icon(
                                                  Icons.redeem_rounded,
                                                  color: Colors.white,
                                                ),
                                                label: const Text(
                                                  'استبدال المكافأة',
                                                  style: TextStyle(
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                                style: FilledButton.styleFrom(
                                                  backgroundColor:
                                                      Colors.transparent,
                                                  shadowColor:
                                                      Colors.transparent,
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        vertical: 12,
                                                        horizontal: 18,
                                                      ),
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          14,
                                                        ),
                                                  ),
                                                  minimumSize:
                                                      const Size.fromHeight(45),
                                                ),
                                                onPressed: () async {
                                                  final confirm = await showDialog<bool>(
                                                    context: context,
                                                    builder: (ctx) => AlertDialog(
                                                      shape: RoundedRectangleBorder(
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              18,
                                                            ),
                                                      ),
                                                      title: const Text(
                                                        '⚠️ تأكيد الاستبدال',
                                                        textAlign:
                                                            TextAlign.center,
                                                        style: TextStyle(
                                                          fontWeight:
                                                              FontWeight.bold,
                                                        ),
                                                      ),
                                                      contentPadding:
                                                          const EdgeInsets.fromLTRB(
                                                            24,
                                                            20,
                                                            24,
                                                            0,
                                                          ),
                                                      content: const Text(
                                                        ' الكود صالح لمدة 10 دقائق فقط بعد الاستبدال\nتأكد انك جاهز لاستخدامه قبل المتابعة',
                                                        textAlign:
                                                            TextAlign.center,
                                                      ),
                                                      actionsAlignment:
                                                          MainAxisAlignment
                                                              .center,
                                                      actions: [
                                                        TextButton(
                                                          onPressed: () =>
                                                              Navigator.pop(
                                                                ctx,
                                                                false,
                                                              ),
                                                          child: const Text(
                                                            'إلغاء',
                                                          ),
                                                        ),
                                                        FilledButton(
                                                          style: FilledButton.styleFrom(
                                                            backgroundColor:
                                                                appColors
                                                                    .primary,
                                                            shape: RoundedRectangleBorder(
                                                              borderRadius:
                                                                  BorderRadius.circular(
                                                                    12,
                                                                  ),
                                                            ),
                                                          ),
                                                          onPressed: () =>
                                                              Navigator.pop(
                                                                ctx,
                                                                true,
                                                              ),
                                                          child: const Text(
                                                            'استبدال الآن',
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  );

                                                  if (confirm == true) {
                                                    await _redeemReward(
                                                      context,
                                                      data,
                                                    );
                                                  }
                                                },
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
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
