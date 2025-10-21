import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'home.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'main.dart';
import 'widgets/background_container.dart';
import 'widgets/bottom_nav.dart';
import 'my_reports_page.dart';

class AppColors {
  static const primary = Color(0xFF009688);
  static const dark = Color(0xFF00695C);
  static const light = Color(0xFF4DB6AC);
  static const background = Color(0xFFFAFCFB);
  static const orange = Color(0xFFFFB74D);
  static const mint = Color(0xFFB6E9C1);
}

class profilePage extends StatelessWidget {
  const profilePage({super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = GoogleFonts.ibmPlexSansArabicTextTheme(
      Theme.of(context).textTheme,
    );

    final user = FirebaseAuth.instance.currentUser;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Theme(
        data: Theme.of(context).copyWith(textTheme: textTheme),
        child: Scaffold(
          extendBody: true,
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            title: Text(
              'الحساب',
              style: GoogleFonts.ibmPlexSansArabic(
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
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
            centerTitle: true,
            elevation: 0,
            backgroundColor: Colors.transparent,
          ),
          body: AnimatedBackgroundContainer(
            child: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    // ---------- بطاقة معلومات المستخدم ----------
                    StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                      stream: user == null
                          ? const Stream.empty()
                          : FirebaseFirestore.instance
                                .collection('users')
                                .doc(user.uid)
                                .snapshots(),
                      builder: (context, snap) {
                        final isLoading =
                            snap.connectionState == ConnectionState.waiting;
                        final data = snap.data?.data();

                        final username = (data?['username'] ?? 'مستخدم')
                            .toString();
                        final email = (data?['email'] ?? user?.email ?? '')
                            .toString();
                        final age = (data?['age'] is int)
                            ? (data?['age'] as int)
                            : int.tryParse('${data?['age'] ?? ''}') ?? 0;
                        final gender = (data?['gender'] ?? 'male').toString();

                        // ✅ نقرأ pfpIndex من الداتابيس
                        final int? pfpIndex = (data?['pfpIndex'] is int)
                            ? (data?['pfpIndex'] as int)
                            : int.tryParse('${data?['pfpIndex'] ?? ''}');

                        // مسار الأفاتار لو متوفر (0..7) -> pfp1..pfp8
                        String? avatarPath;
                        if (pfpIndex != null && pfpIndex >= 0 && pfpIndex < 8) {
                          avatarPath = 'assets/pfp/pfp${pfpIndex + 1}.png';
                        }

                        return Column(
                          children: [
                            // ✅ لم تعد قابلة للنقر – فقط عرض
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(16),
                              margin: const EdgeInsets.only(top: 16),
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
                              child: Row(
                                children: [
                                  // صورة بروفايل داخل خلفية خضراء (أفاتار إن وُجد)
                                  Container(
                                    decoration: const BoxDecoration(
                                      color: AppColors.light,
                                      shape: BoxShape.circle,
                                    ),
                                    child: CircleAvatar(
                                      radius: 28,
                                      backgroundColor: Colors.transparent,
                                      backgroundImage:
                                          (avatarPath != null && !isLoading)
                                          ? AssetImage(avatarPath)
                                          : null,
                                      child: (avatarPath == null || isLoading)
                                          ? const Icon(
                                              Icons.person_outline,
                                              color: Colors.white,
                                              size: 30,
                                            )
                                          : null,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        // اسم العرض
                                        Text(
                                          isLoading
                                              ? 'جارٍ التحميل…'
                                              : username,
                                          overflow: TextOverflow.ellipsis,
                                          style: GoogleFonts.ibmPlexSansArabic(
                                            fontSize: 18,
                                            fontWeight: FontWeight.w700,
                                            color: AppColors.dark,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        // ✅ السطر الثاني = البريد الإلكتروني
                                        Text(
                                          isLoading ? '...' : email,
                                          overflow: TextOverflow.ellipsis,
                                          style: GoogleFonts.ibmPlexSansArabic(
                                            fontSize: 14,
                                            color: AppColors.dark.withOpacity(
                                              .7,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  // ✅ شلنا أيقونة التعديل
                                ],
                              ),
                            ),

                            const SizedBox(height: 24),

                            // ---------- خانات الإعدادات ----------
                            _SettingsCard(
                              children: [
                                if (data?['role'] != 'admin')
                                  // ✅ بلاغاتي مع عدّاد الإشعارات
                                  StreamBuilder<
                                    QuerySnapshot<Map<String, dynamic>>
                                  >(
                                    stream: FirebaseFirestore.instance
                                        .collection('notifications')
                                        .where(
                                          'userId',
                                          isEqualTo: FirebaseAuth
                                              .instance
                                              .currentUser
                                              ?.uid,
                                        )
                                        .where('read', isEqualTo: false)
                                        .snapshots(),
                                    builder: (context, snapshot) {
                                      final unreadCount =
                                          snapshot.data?.docs.length ?? 0;

                                      return _SettingTile(
                                        title: 'بلاغاتي',
                                        icon: Icons.notifications_outlined,
                                        trailing: unreadCount > 0
                                            ? Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 4,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: Colors.redAccent,
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                ),
                                                child: Text(
                                                  '$unreadCount جديدة',
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              )
                                            : const Icon(
                                                Icons.chevron_left,
                                                color: Colors.black54,
                                                size: 22,
                                              ),
                                        onTap: () {
                                          Navigator.of(context).push(
                                            MaterialPageRoute(
                                              builder: (_) =>
                                                  const MyReportsPage(),
                                            ),
                                          );
                                        },
                                      );
                                    },
                                  ),

                                _SettingTile(
                                  title: 'اللغة',
                                  icon: Icons.language,
                                  trailing: Text(
                                    'العربية',
                                    style: GoogleFonts.ibmPlexSansArabic(
                                      color: AppColors.dark.withOpacity(.8),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  onTap: () {
                                    _showSnack(context, 'تغيير اللغة قريباً ✨');
                                  },
                                ),
                                _SettingTile(
                                  title: 'الخصوصية والأمان',
                                  icon: Icons.lock_outline,
                                  onTap: () => _showPrivacySheet(context),
                                ),
                                _SettingTile(
                                  title: 'المساعدة والدعم',
                                  icon: Icons.help_outline,
                                  onTap: () => _showSupportSheet(context),
                                ),
                              ],
                            ),
                            // ---------- زر تعديل الحساب ----------
                            SizedBox(
                              width: double.infinity,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(14),
                                  gradient: const LinearGradient(
                                    colors: [
                                      AppColors.mint,
                                      AppColors.primary,
                                      AppColors.primary,
                                    ],
                                    stops: [0.0, 0.6, 1.0],
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
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.transparent,
                                    shadowColor: Colors.transparent,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 16,
                                      horizontal: 20,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    elevation: 0,
                                  ),
                                  icon: const Icon(
                                    Icons.edit,
                                    color: Colors.white,
                                  ),
                                  label: Text(
                                    'تعديل الحساب',
                                    style: GoogleFonts.ibmPlexSansArabic(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                  ),
                                  onPressed: (user == null || isLoading)
                                      ? null
                                      : () {
                                          Navigator.of(context).push(
                                            MaterialPageRoute(
                                              builder: (_) => EditProfilePage(
                                                initialUsername: username,
                                                initialHandle: '$username',
                                                initialEmail: email,
                                                initialAge: age == 0 ? 18 : age,
                                                initialGender:
                                                    gender, // male/female
                                                initialPfpIndex: pfpIndex,
                                              ),
                                            ),
                                          );
                                        },
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),

                    const SizedBox(height: 16),

                    const SizedBox(height: 16),

                    _SettingsCard(
                      children: [
                        _SettingTile(
                          title: 'تسجيل الخروج',
                          icon: Icons.logout,
                          iconColor: Colors.redAccent,
                          titleColor: Colors.redAccent,
                          onTap: () async {
                            showDialog(
                              context: context,
                              barrierDismissible: false,
                              builder: (context) {
                                return Dialog(
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  insetPadding: const EdgeInsets.symmetric(
                                    horizontal: 24,
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(20),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        // ✅ الصورة العلوية
                                        Image.asset(
                                          'assets/img/nameerThink.png',
                                          height: 120,
                                          fit: BoxFit.contain,
                                        ),
                                        const SizedBox(height: 16),

                                        // ✅ النص
                                        Text(
                                          'هل أنت متأكد أنك تريد تسجيل الخروج؟',
                                          textAlign: TextAlign.center,
                                          style: GoogleFonts.ibmPlexSansArabic(
                                            fontSize: 18,
                                            fontWeight: FontWeight.w600,
                                            color: AppColors.dark,
                                          ),
                                        ),
                                        const SizedBox(height: 24),

                                        // ✅ الأزرار
                                        Row(
                                          children: [
                                            Expanded(
                                              child: OutlinedButton(
                                                style: OutlinedButton.styleFrom(
                                                  side: const BorderSide(
                                                    color: AppColors.primary,
                                                  ),
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          12,
                                                        ),
                                                  ),
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        vertical: 12,
                                                      ),
                                                ),
                                                onPressed: () {
                                                  Navigator.of(
                                                    context,
                                                  ).pop(); // إغلاق النافذة فقط
                                                },
                                                child: Text(
                                                  'إلغاء',
                                                  style:
                                                      GoogleFonts.ibmPlexSansArabic(
                                                        color:
                                                            AppColors.primary,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        fontSize: 16,
                                                      ),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: ElevatedButton(
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor:
                                                      AppColors.primary,
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          12,
                                                        ),
                                                  ),
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        vertical: 12,
                                                      ),
                                                ),
                                                onPressed: () async {
                                                  Navigator.of(
                                                    context,
                                                  ).pop(); // إغلاق الرسالة أولاً
                                                  try {
                                                    await FirebaseAuth.instance
                                                        .signOut();
                                                  } catch (_) {}
                                                  if (context.mounted) {
                                                    Navigator.of(
                                                      context,
                                                    ).pushAndRemoveUntil(
                                                      MaterialPageRoute(
                                                        builder: (_) =>
                                                            const RegisterPage(),
                                                      ),
                                                      (route) => false,
                                                    );
                                                  }
                                                },
                                                child: Text(
                                                  'تأكيد',
                                                  style:
                                                      GoogleFonts.ibmPlexSansArabic(
                                                        color: Colors.white,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        fontSize: 16,
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
                              },
                            );
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ======== BottomSheets: Privacy & Support ========

  void _showPrivacySheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 44,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: const Color(0x22000000),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                Row(
                  children: [
                    const Icon(Icons.lock_outline, color: AppColors.primary),
                    const SizedBox(width: 8),
                    Text(
                      'الخصوصية والأمان',
                      style: GoogleFonts.ibmPlexSansArabic(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppColors.dark,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _privacyBullet(
                  'نحافظ على سريّة بياناتك ولا نشاركها مع أطراف ثالثة دون موافقتك.',
                ),
                _privacyBullet(
                  'يمكنك تنزيل/حذف بياناتك من الإعدادات > إدارة البيانات.',
                ),
                _privacyBullet(
                  'كلمات المرور تُخزَّن بشكل مُشفّر وفق أفضل الممارسات.',
                ),
                _privacyBullet(
                  'تستطيع ضبط صلاحيات الوصول للموقع والكاميرا والإشعارات.',
                ),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text('تم'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showSupportSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 44,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: const Color(0x22000000),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                Row(
                  children: [
                    const Icon(Icons.support_agent, color: AppColors.primary),
                    const SizedBox(width: 8),
                    Text(
                      'المساعدة والدعم',
                      style: GoogleFonts.ibmPlexSansArabic(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppColors.dark,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _faqItem(
                  q: 'كيف أستعيد كلمة المرور؟',
                  a: 'من شاشة تسجيل الدخول اختر "نسيت كلمة المرور" واتبع التعليمات لإعادة التعيين.',
                ),
                const SizedBox(height: 8),
                _faqItem(
                  q: 'كيف أتواصل مع الدعم؟',
                  a: 'أرسل لنا رسالة من داخل التطبيق: الإعدادات > المساعدة والدعم > تواصل معنا.',
                ),
                const SizedBox(height: 8),
                _faqItem(
                  q: 'كيف أبلّغ عن مشكلة؟',
                  a: 'أرفق وصف المشكلة ولقطة شاشة إن أمكن وسنراجعها خلال أقرب وقت.',
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () {
                        Navigator.pop(ctx);
                        _showSnack(context, 'جارٍ فتح نموذج التواصل…');
                      },
                      icon: const Icon(Icons.chat_bubble_outline),
                      label: Text(
                        'تواصل معنا',
                        style: GoogleFonts.ibmPlexSansArabic(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('إغلاق'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  // عناصر مساعدة للـ BottomSheet
  static Widget _privacyBullet(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.verified_user, size: 18, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.ibmPlexSansArabic(
                fontSize: 14,
                height: 1.5,
                color: AppColors.dark,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Widget _faqItem({required String q, required String a}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF7FBF9),
        border: Border.all(color: const Color(0xFFE3F1EC)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            q,
            style: GoogleFonts.ibmPlexSansArabic(
              fontWeight: FontWeight.w800,
              color: AppColors.dark,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            a,
            style: GoogleFonts.ibmPlexSansArabic(
              color: AppColors.dark.withOpacity(.8),
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  static void _showSnack(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          msg,
          style: GoogleFonts.ibmPlexSansArabic(fontWeight: FontWeight.w600),
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

// ===================== Widgets مساعدة =====================

class _SettingsCard extends StatelessWidget {
  final List<Widget> children;
  const _SettingsCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            blurRadius: 10,
            offset: Offset(0, 6),
            color: Color(0x14000000),
          ),
        ],
      ),
      child: Column(children: children),
    );
  }
}

class _SettingTile extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget? trailing;
  final Color? iconColor;
  final Color? titleColor;
  final VoidCallback? onTap;

  const _SettingTile({
    required this.title,
    required this.icon,
    this.trailing,
    this.iconColor,
    this.titleColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.light.withOpacity(.2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: iconColor ?? AppColors.primary),
      ),
      title: Text(
        title,
        style: GoogleFonts.ibmPlexSansArabic(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: titleColor ?? AppColors.dark,
        ),
      ),
      trailing:
          trailing ??
          const Icon(Icons.chevron_left, color: Colors.black54, size: 22),
    );
  }
}

/* ===================== صفحة تعديل الحساب ===================== */

class EditProfilePage extends StatefulWidget {
  final String initialUsername;
  final String initialHandle;
  final String initialEmail;
  final int initialAge;
  final String initialGender; // 'male' or 'female'
  final int? initialPfpIndex; // اختياري

  const EditProfilePage({
    super.key,
    required this.initialUsername,
    required this.initialHandle,
    required this.initialEmail,
    required this.initialAge,
    required this.initialGender,
    this.initialPfpIndex,
  });

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _usernameCtrl;
  late final TextEditingController _handleCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _ageCtrl;

  // إدارة تغيير كلمة المرور (عرض كنقاط ثم وضع التغيير)
  bool _changePassword = false;
  late final TextEditingController _currentPassCtrl;
  late final TextEditingController _newPassCtrl;
  late final TextEditingController _confirmPassCtrl;
  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;

  // تغيير الإيميل (BottomSheet)
  final _currentPassForEmailCtrl = TextEditingController();
  final _newEmailCtrl = TextEditingController();

  late String _gender;

  // ✅ قائمة صور الأفاتار من مجلد assets/pfp
  final List<String> _avatars = const [
    'assets/pfp/pfp1.png',
    'assets/pfp/pfp2.png',
    'assets/pfp/pfp3.png',
    'assets/pfp/pfp4.png',
    'assets/pfp/pfp5.png',
    'assets/pfp/pfp6.png',
    'assets/pfp/pfp7.png',
    'assets/pfp/pfp8.png',
  ];
  int? _pfpIndex; // null = أيقونة افتراضية

  @override
  void initState() {
    super.initState();
    _usernameCtrl = TextEditingController(text: widget.initialUsername);
    _handleCtrl = TextEditingController(text: widget.initialHandle);
    _emailCtrl = TextEditingController(text: widget.initialEmail);
    _ageCtrl = TextEditingController(text: widget.initialAge.toString());

    _currentPassCtrl = TextEditingController();
    _newPassCtrl = TextEditingController();
    _confirmPassCtrl = TextEditingController();

    _gender = widget.initialGender;
    _pfpIndex = widget.initialPfpIndex; // الافتراضي من الداتابيس
  }

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _handleCtrl.dispose();
    _emailCtrl.dispose();
    _ageCtrl.dispose();

    _currentPassCtrl.dispose();
    _newPassCtrl.dispose();
    _confirmPassCtrl.dispose();

    _currentPassForEmailCtrl.dispose();
    _newEmailCtrl.dispose();

    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'لا يوجد مستخدم مسجّل.',
            style: GoogleFonts.ibmPlexSansArabic(),
          ),
        ),
      );
      return;
    }

    try {
      // تجهيز البيانات
      final usernameWithoutAt = _handleCtrl.text.trim().startsWith('@')
          ? _handleCtrl.text.trim().substring(1)
          : _handleCtrl.text.trim();

      final update = <String, dynamic>{
        'username': usernameWithoutAt.isEmpty
            ? widget.initialUsername
            : usernameWithoutAt,
        'email': _emailCtrl.text.trim(),
        'age': int.tryParse(_ageCtrl.text.trim()) ?? widget.initialAge,
        'gender': _gender, // 'male' أو 'female'
        'updatedAt': FieldValue.serverTimestamp(),
      };

      // ✅ حفظ فهرس صورة البروفايل pfpIndex
      if (_pfpIndex != null) {
        update['pfpIndex'] = _pfpIndex;
      }

      // 1) تحديث Firestore (دمج)
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .set(update, SetOptions(merge: true));

      // 2) تغيير كلمة المرور (إذا تم تفعيل وضع التغيير)
      if (_changePassword) {
        final email = user.email ?? _emailCtrl.text.trim();
        if (email.isEmpty) {
          throw 'لا يمكن إعادة المصادقة: البريد غير متوفر.';
        }

        final current = _currentPassCtrl.text;
        final newPass = _newPassCtrl.text;

        // إعادة المصادقة
        final cred = EmailAuthProvider.credential(
          email: email,
          password: current,
        );
        await user.reauthenticateWithCredential(cred);

        // تحديث كلمة المرور
        await user.updatePassword(newPass);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'تم حفظ التغييرات بنجاح ✅',
            style: GoogleFonts.ibmPlexSansArabic(fontWeight: FontWeight.w700),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'حدث خطأ أثناء الحفظ: $e',
            style: GoogleFonts.ibmPlexSansArabic(),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // ===== تغيير الإيميل بنفس منطق الأوث (reauth → updateEmail → verify → Firestore → VerifyEmailPage)
  void _showChangeEmailSheet() {
    _currentPassForEmailCtrl.clear();
    _newEmailCtrl.text = _emailCtrl.text;

    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        bool _obsc = true;
        return Directionality(
          textDirection: TextDirection.rtl,
          child: StatefulBuilder(
            builder: (ctx, setSt) => Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: 16 + MediaQuery.of(ctx).viewInsets.bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 44,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: const Color(0x22000000),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  Row(
                    children: const [
                      Icon(
                        Icons.mark_email_read_outlined,
                        color: AppColors.primary,
                      ),
                      SizedBox(width: 8),
                      Text(
                        'تغيير البريد الإلكتروني',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                          color: AppColors.dark,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _newEmailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      hintText: 'new@example.com',
                      prefixIcon: Icon(Icons.email_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _currentPassForEmailCtrl,
                    obscureText: _obsc,
                    decoration: InputDecoration(
                      hintText: 'كلمة المرور الحالية',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        onPressed: () => setSt(() => _obsc = !_obsc),
                        icon: Icon(
                          _obsc ? Icons.visibility : Icons.visibility_off,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            gradient: const LinearGradient(
                              colors: [
                                AppColors.mint,
                                AppColors.primary,
                                AppColors.primary,
                              ],
                              stops: [0.0, 0.5, 1.0],
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
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              padding: const EdgeInsets.symmetric(
                                vertical: 14,
                                horizontal: 18,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 0,
                            ),
                            onPressed: () async {
                              final newEmail = _newEmailCtrl.text.trim();
                              final pass = _currentPassForEmailCtrl.text;
                              if (newEmail.isEmpty || pass.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'أدخل البريد الجديد وكلمة المرور الحالية',
                                    ),
                                  ),
                                );
                                return;
                              }
                              Navigator.pop(ctx);
                              await _changeEmailSecure(
                                currentPassword: pass,
                                newEmail: newEmail,
                              );
                            },
                            icon: const Icon(Icons.check, color: Colors.white),
                            label: const Text(
                              'تأكيد التغيير',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('إلغاء'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _changeEmailSecure({
    required String currentPassword,
    required String newEmail,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('لا يوجد مستخدم مسجّل')));
      return;
    }

    try {
      // reauth
      final cred = EmailAuthProvider.credential(
        email: user.email!,
        password: currentPassword,
      );
      await user.reauthenticateWithCredential(cred);

      // update email
      await user.updateEmail(newEmail);

      // send verification
      await FirebaseAuth.instance.setLanguageCode('ar');
      await user.sendEmailVerification();

      // update Firestore
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'email': newEmail.toLowerCase(),
        'isVerified': false,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // reflect locally
      setState(() {
        _emailCtrl.text = newEmail;
      });

      if (!mounted) return;
      // go to VerifyEmailPage from main.dart
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => VerifyEmailPage(email: newEmail)),
      );

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم إرسال رسالة تحقق إلى بريدك الجديد')),
      );
    } on FirebaseAuthException catch (e) {
      String msg = 'تعذّر تغيير البريد';
      switch (e.code) {
        case 'requires-recent-login':
          msg = 'لأسباب أمان، سجّل دخولك مجددًا ثم حاول.';
          break;
        case 'wrong-password':
          msg = 'كلمة المرور الحالية غير صحيحة.';
          break;
        case 'invalid-email':
          msg = 'بريد إلكتروني غير صالح.';
          break;
        case 'email-already-in-use':
          msg = 'هذا البريد مستخدم بالفعل.';
          break;
        case 'network-request-failed':
          msg = 'تعذّر الاتصال — تأكد من الإنترنت.';
          break;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('❌ $msg')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('❌ خطأ غير متوقع أثناء تغيير البريد')),
      );
    }
  }

  void _openAvatarPicker() {
    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 44,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: const Color(0x22000000),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                Row(
                  children: [
                    const Icon(Icons.image_outlined, color: AppColors.primary),
                    const SizedBox(width: 8),
                    Text(
                      'اختر صورة الحساب',
                      style: GoogleFonts.ibmPlexSansArabic(
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                        color: AppColors.dark,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                GridView.builder(
                  shrinkWrap: true,
                  itemCount: _avatars.length,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                  ),
                  itemBuilder: (_, i) {
                    final selected = _pfpIndex == i;
                    return InkWell(
                      borderRadius: BorderRadius.circular(999),
                      onTap: () {
                        setState(() => _pfpIndex = i);
                        Navigator.pop(ctx);
                      },
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          CircleAvatar(
                            radius: 36,
                            backgroundColor: selected
                                ? AppColors.primary
                                : AppColors.light.withOpacity(.25),
                            child: CircleAvatar(
                              radius: 32,
                              backgroundImage: AssetImage(_avatars[i]),
                              backgroundColor: Colors.white,
                            ),
                          ),
                          if (selected)
                            const Positioned(
                              bottom: 4,
                              right: 4,
                              child: CircleAvatar(
                                radius: 10,
                                backgroundColor: Colors.white,
                                child: Icon(
                                  Icons.check_circle,
                                  color: AppColors.primary,
                                  size: 18,
                                ),
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('إغلاق'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final avatarWidget = Stack(
      clipBehavior: Clip.none,
      children: [
        // خلفية دائرية خضراء خفيفة + صورة/أيقونة
        Container(
          decoration: const BoxDecoration(
            color: AppColors.light,
            shape: BoxShape.circle,
          ),
          child: CircleAvatar(
            radius: 32,
            backgroundColor: Colors.transparent,
            backgroundImage: _pfpIndex != null
                ? AssetImage(_avatars[_pfpIndex!])
                : null,
            child: _pfpIndex == null
                ? const Icon(
                    Icons.person_outline,
                    color: Colors.white,
                    size: 34,
                  )
                : null,
          ),
        ),
        // زر القلم
        Positioned(
          bottom: -4,
          left: -4,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _openAvatarPicker,
              borderRadius: BorderRadius.circular(999),
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x33000000),
                      blurRadius: 8,
                      offset: Offset(0, 3),
                    ),
                  ],
                ),
                child: const Icon(Icons.edit, color: Colors.white, size: 16),
              ),
            ),
          ),
        ),
      ],
    );

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: Text(
            'تعديل الحساب',
            style: GoogleFonts.ibmPlexSansArabic(
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          flexibleSpace: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.primary, AppColors.primary, AppColors.mint],
                stops: [0.0, 0.5, 1.0],
                begin: Alignment.bottomLeft,
                end: Alignment.topRight,
              ),
            ),
          ),
          centerTitle: true,
          elevation: 0,
          backgroundColor: Colors.transparent,
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                // صورة رمزية + قلم تعديل
                Row(children: [avatarWidget, const SizedBox(width: 10)]),

                const SizedBox(height: 14),

                // اليوزر (الهاندل)
                _fieldLabel('اسم المستخدم'),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _handleCtrl,
                  decoration: const InputDecoration(
                    hintText: 'username',
                    prefixIcon: Icon(Icons.alternate_email),
                  ),
                  validator: (v) {
                    final val = v?.trim() ?? '';
                    if (val.isEmpty) {
                      return 'أدخل اسم المستخدم';
                    }
                    if (val.length < 3) {
                      return 'اسم المستخدم قصير جداً';
                    }
                    final re = RegExp(r'^[a-zA-Z0-9._-]+$');
                    if (!re.hasMatch(val)) {
                      return 'استخدم حروف/أرقام و . _ - فقط';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 14),

                // الإيميل (readOnly + زر تغيير)
                _fieldLabel('البريد الإلكتروني'),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _emailCtrl,
                  readOnly: true,
                  enableInteractiveSelection: false,
                  decoration: InputDecoration(
                    hintText: 'name@example.com',
                    prefixIcon: const Icon(Icons.email_outlined),
                    suffixIcon: TextButton(
                      onPressed: _showChangeEmailSheet,
                      child: const Text('تغيير'),
                    ),
                  ),
                ),

                const SizedBox(height: 14),

                // العمر + الجنس
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _fieldLabel('العمر'),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _ageCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              hintText: 'مثال: 22',
                              prefixIcon: Icon(Icons.cake_outlined),
                            ),
                            validator: (v) {
                              final n = int.tryParse(v ?? '');
                              if (n == null || n < 7 || n > 120) {
                                return 'أدخل عمرًا منطقيًا';
                              }
                              return null;
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _fieldLabel('الجنس'),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: _GenderChipEdit(
                                  selected: _gender == 'male',
                                  icon: Icons.male,
                                  label: 'ذكر',
                                  onTap: () => setState(() {
                                    _gender = 'male';
                                  }),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _GenderChipEdit(
                                  selected: _gender == 'female',
                                  icon: Icons.female,
                                  label: 'أنثى',
                                  onTap: () => setState(() {
                                    _gender = 'female';
                                  }),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 14),

                // ===== كلمة المرور =====
                _fieldLabel('كلمة المرور'),
                const SizedBox(height: 8),

                if (!_changePassword) ...[
                  TextFormField(
                    enabled: false,
                    initialValue: '••••••••',
                    obscureText: true,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.lock_outline),
                      hintText: '••••••••',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () => setState(() => _changePassword = true),
                      icon: const Icon(Icons.edit),
                      label: const Text('تغيير كلمة المرور'),
                    ),
                  ),
                ] else ...[
                  TextFormField(
                    controller: _currentPassCtrl,
                    obscureText: _obscureCurrent,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.lock_outline),
                      hintText: 'كلمة المرور الحالية',
                      suffixIcon: IconButton(
                        onPressed: () =>
                            setState(() => _obscureCurrent = !_obscureCurrent),
                        icon: Icon(
                          _obscureCurrent
                              ? Icons.visibility
                              : Icons.visibility_off,
                        ),
                      ),
                    ),
                    validator: (v) {
                      if (_changePassword && (v == null || v.isEmpty)) {
                        return 'أدخل كلمة المرور الحالية';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _newPassCtrl,
                    obscureText: _obscureNew,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.lock_reset),
                      hintText: 'كلمة المرور الجديدة',
                      suffixIcon: IconButton(
                        onPressed: () =>
                            setState(() => _obscureNew = !_obscureNew),
                        icon: Icon(
                          _obscureNew ? Icons.visibility : Icons.visibility_off,
                        ),
                      ),
                    ),
                    validator: (v) {
                      if (_changePassword) {
                        if (v == null || v.isEmpty) {
                          return 'أدخل كلمة المرور الجديدة';
                        }
                        if (v.length < 6) return '6 أحرف على الأقل';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _confirmPassCtrl,
                    obscureText: _obscureConfirm,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.check_circle_outline),
                      hintText: 'تأكيد كلمة المرور الجديدة',
                      suffixIcon: IconButton(
                        onPressed: () =>
                            setState(() => _obscureConfirm = !_obscureConfirm),
                        icon: Icon(
                          _obscureConfirm
                              ? Icons.visibility
                              : Icons.visibility_off,
                        ),
                      ),
                    ),
                    validator: (v) {
                      if (_changePassword) {
                        if (v == null || v.isEmpty) {
                          return 'أعد إدخال كلمة المرور';
                        }
                        if (v != _newPassCtrl.text) {
                          return 'كلمتا المرور غير متطابقتين';
                        }
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () {
                        setState(() {
                          _changePassword = false;
                          _currentPassCtrl.clear();
                          _newPassCtrl.clear();
                          _confirmPassCtrl.clear();
                        });
                      },
                      child: const Text('إلغاء التغيير'),
                    ),
                  ),
                ],

                const SizedBox(height: 22),

                // زر حفظ (تدرّج)
                SizedBox(
                  width: double.infinity,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
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
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        padding: const EdgeInsets.symmetric(
                          vertical: 14,
                          horizontal: 18,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 0,
                      ),
                      onPressed: _save,
                      icon: const Icon(Icons.save, color: Colors.white),
                      label: Text(
                        'حفظ التغييرات',
                        style: GoogleFonts.ibmPlexSansArabic(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _fieldLabel(String text) => Align(
    alignment: Alignment.centerRight,
    child: Text(
      text,
      style: GoogleFonts.ibmPlexSansArabic(
        fontWeight: FontWeight.w700,
        color: AppColors.dark.withOpacity(.9),
      ),
    ),
  );
}

class _GenderChipEdit extends StatelessWidget {
  final bool selected;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _GenderChipEdit({
    required this.selected,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = selected
        ? AppColors.primary.withOpacity(.12)
        : Colors.transparent;
    final border = selected ? AppColors.primary : AppColors.light;
    final fg = selected ? AppColors.dark : Colors.black.withOpacity(.7);

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: border, width: 1.2),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 20, color: AppColors.primary),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.ibmPlexSansArabic(
                fontWeight: FontWeight.w700,
                color: fg,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
