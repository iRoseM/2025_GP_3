import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'services/background_container.dart';
import 'package:flutter/services.dart';

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

  // 🧠 منطق استبدال المكافأة
  Future<void> _redeemReward(
    BuildContext context,
    Map<String, dynamic> data,
  ) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('الرجاء تسجيل الدخول أولاً')),
      );
      return;
    }

    final rewardID = data['id'] ?? '';
    final rewardTitle = data['title'] ?? 'مكافأة';
    final cost = data['costPoints'] ?? 0;
    final couponCode = data['couponCode'] ?? 'NAMEER10';
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

        tx.set(redemptionRef, {
          'userID': user.uid,
          'rewardID': rewardID,
          'code': couponCode,
          'status': 'pending',
          'redeemedAt': FieldValue.serverTimestamp(),
        });

        if (currentPoints < cost) {
          tx.update(redemptionRef, {
            'status': 'failed',
            'reason': 'رصيدك غير كافٍ',
          });
          throw Exception('رصيدك لا يكفي لاستبدال هذه المكافأة.');
        }

        tx.update(userRef, {'points': currentPoints - cost});

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
        SnackBar(content: Text('تم استبدال "$rewardTitle" بنجاح 🎉')),
      );
    } catch (e) {
      final scaffoldContext = context;

      String message =
          'تعذر تنفيذ الاستبدال مؤقتًا، حاول مرة أخرى بعد لحظات 🔄';

      if (e.toString().contains('رصيدك لا يكفي')) {
        message = 'رصيدك الحالي لا يكفي لاستبدال هذه المكافأة 💰';
      } else if (e.toString().contains('المستخدم غير موجود')) {
        message = 'حدث خلل في حسابك، يرجى تسجيل الدخول من جديد.';
      }

      ScaffoldMessenger.of(
        scaffoldContext,
      ).showSnackBar(SnackBar(content: Text(message)));
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
            ;

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
                          ? AppColors.accent
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
                          style: TextStyle(color: AppColors.dark),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          format(remaining),
                          style: const TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w900,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    )
                  else
                    const Text(
                      'انتهى الوقت ❌',
                      style: TextStyle(
                        color: Colors.redAccent,
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
                        ? AppColors.primary
                        : Colors.grey,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: remaining.inSeconds > 0
                      ? () async {
                          await Clipboard.setData(
                            ClipboardData(text: couponCode),
                          ); // ✅ نسخ فعلي للكود
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('تم نسخ الكود إلى الحافظة ✅'),
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

  // 👇 نفس تصميمك بالضبط
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
          appBar: AppBar(
            title: const Text('المكافآت المتاحة'),
            centerTitle: true,
            backgroundColor: Colors.transparent,
            elevation: 0,
          ),
          body: AnimatedBackgroundContainer(
            child: Column(
              children: [
                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: getActiveRewards(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                        return const Center(
                          child: Text('لا توجد مكافآت متاحة حالياً'),
                        );
                      }

                      final rewards = snapshot.data!.docs;
                      return ListView.builder(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 20,
                        ),
                        itemCount: rewards.length,
                        itemBuilder: (context, i) {
                          final data =
                              rewards[i].data() as Map<String, dynamic>;
                          data['id'] = rewards[i].id;

                          return Card(
                            margin: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            elevation: 4,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (data['imageUrl'] != null &&
                                    data['imageUrl'].toString().isNotEmpty)
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
                                      color: AppColors.primary33,
                                      borderRadius: BorderRadius.only(
                                        topLeft: Radius.circular(16),
                                        topRight: Radius.circular(16),
                                      ),
                                    ),
                                    child: const Icon(
                                      Icons.card_giftcard,
                                      color: AppColors.primary,
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
                                          color: AppColors.dark,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        data['description'] ?? '',
                                        style: const TextStyle(
                                          fontSize: 15,
                                          color: AppColors.dark,
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Row(
                                            children: [
                                              const Icon(
                                                Icons.star_rate_rounded,
                                                color: AppColors.accent,
                                                size: 20,
                                              ),
                                              const SizedBox(width: 6),
                                              Text(
                                                'تكلفة الاستبدال: ${data['costPoints']} نقطة',
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                  color: AppColors.sea,
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
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                          gradient: const LinearGradient(
                                            colors: [
                                              AppColors.mint,
                                              AppColors.primary,
                                              AppColors.primary,
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
                                            backgroundColor: Colors.transparent,
                                            shadowColor: Colors.transparent,
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 12,
                                              horizontal: 18,
                                            ),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(14),
                                            ),
                                            minimumSize: const Size.fromHeight(
                                              45,
                                            ),
                                          ),
                                          onPressed: () async {
                                            final confirm = await showDialog<bool>(
                                              context: context,
                                              builder: (ctx) => AlertDialog(
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(18),
                                                ),
                                                title: const Text(
                                                  '⚠️ تأكيد الاستبدال',
                                                  textAlign: TextAlign.center,
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.bold,
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
                                                  textAlign: TextAlign.center,
                                                ),
                                                actionsAlignment:
                                                    MainAxisAlignment.center,
                                                actions: [
                                                  TextButton(
                                                    onPressed: () =>
                                                        Navigator.pop(
                                                          ctx,
                                                          false,
                                                        ),
                                                    child: const Text('إلغاء'),
                                                  ),
                                                  FilledButton(
                                                    style: FilledButton.styleFrom(
                                                      backgroundColor:
                                                          AppColors.primary,
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
          ),
        ),
      ),
    );
  }
}
