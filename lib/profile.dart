import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'home.dart'; // يحتوي على AppColors: primary / light / dark / background / mint

class profilePage extends StatelessWidget {
  const profilePage({super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = GoogleFonts.ibmPlexSansArabicTextTheme(
      Theme.of(context).textTheme,
    );

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Theme(
        data: Theme.of(context).copyWith(textTheme: textTheme),
        child: Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            title: Text(
              'الحساب',
              style: GoogleFonts.ibmPlexSansArabic(
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            // تدرّج أخضر مثل شارة النقاط
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
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // ---------- بطاقة معلومات المستخدم ----------
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
                        // صورة بروفايل داخل خلفية خضراء
                        Container(
                          decoration: const BoxDecoration(
                            color: AppColors.light,
                            shape: BoxShape.circle,
                          ),
                          child: const CircleAvatar(
                            radius: 28,
                            backgroundColor: Colors.transparent,
                            child: Icon(
                              Icons.person_outline,
                              color: Colors.white,
                              size: 30,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        // النصوص: اسم المستخدم + @username
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'اسم المستخدم',
                              style: GoogleFonts.ibmPlexSansArabic(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: AppColors.dark,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '@username',
                              style: GoogleFonts.ibmPlexSansArabic(
                                fontSize: 14,
                                color: AppColors.dark.withOpacity(.7),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // ---------- زر تعديل الحساب (تدرّج معكوس: mint يمين -> primary, primary) ----------
                  SizedBox(
                    width: double.infinity,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        gradient: const LinearGradient(
                          colors: [
                            AppColors
                                .mint, // يبدأ من اليمين (begin = centerRight)
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
                          backgroundColor: Colors.transparent, // لإظهار التدرّج
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
                        icon: const Icon(Icons.edit, color: Colors.white),
                        label: Text(
                          'تعديل الحساب',
                          style: GoogleFonts.ibmPlexSansArabic(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        onPressed: () {
                          // افتح صفحة تعديل البيانات مع قيم افتراضيّة/حقيقية
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const EditProfilePage(
                                initialUsername: 'اسم المستخدم',
                                initialHandle: '@username',
                                initialEmail: 'user@email.com',
                                initialAge: 22,
                                initialGender: 'male', // male/female
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // ---------- خانات الإعدادات ----------
                  _SettingsCard(
                    children: [
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

                  const SizedBox(height: 16),

                  _SettingsCard(
                    children: [
                      _SettingTile(
                        title: 'تسجيل الخروج',
                        icon: Icons.logout,
                        iconColor: Colors.redAccent,
                        titleColor: Colors.redAccent,
                        onTap: () {
                          _showSnack(context, 'تم تسجيل الخروج');
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

  const EditProfilePage({
    super.key,
    required this.initialUsername,
    required this.initialHandle,
    required this.initialEmail,
    required this.initialAge,
    required this.initialGender,
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
  late final TextEditingController _passCtrl;

  bool _obscure = true;
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
  int? _avatarIndex; // null = أيقونة افتراضية

  @override
  void initState() {
    super.initState();
    _usernameCtrl = TextEditingController(text: widget.initialUsername);
    _handleCtrl = TextEditingController(text: widget.initialHandle);
    _emailCtrl = TextEditingController(text: widget.initialEmail);
    _ageCtrl = TextEditingController(text: widget.initialAge.toString());
    _passCtrl = TextEditingController();
    _gender = widget.initialGender;
  }

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _handleCtrl.dispose();
    _emailCtrl.dispose();
    _ageCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  void _save() {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    // TODO: احفظ القيم في قاعدة البيانات/الخدمة، بما فيها الصورة المختارة (_avatarIndex)
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'تم حفظ التغييرات بنجاح ✅',
          style: GoogleFonts.ibmPlexSansArabic(fontWeight: FontWeight.w700),
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
    Navigator.of(context).pop(); // رجوع للملف الشخصي
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
                    final selected = _avatarIndex == i;
                    return InkWell(
                      borderRadius: BorderRadius.circular(999),
                      onTap: () {
                        setState(() => _avatarIndex = i);
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
            backgroundImage: _avatarIndex != null
                ? AssetImage(_avatars[_avatarIndex!])
                : null,
            child: _avatarIndex == null
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
                colors: [AppColors.mint, AppColors.primary, AppColors.primary],
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
                Row(
                  children: [
                    avatarWidget,
                    const SizedBox(width: 10),
                    Text(
                      'حدّث بياناتك بسهولة',
                      style: GoogleFonts.ibmPlexSansArabic(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.dark,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 14),

                // اليوزر
                _fieldLabel('اسم المستخدم'),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _handleCtrl,
                  decoration: const InputDecoration(
                    hintText: '@username',
                    prefixIcon: Icon(Icons.alternate_email),
                  ),
                  validator: (v) =>
                      (v == null || !v.startsWith('@') || v.length < 4)
                      ? 'أدخل يوزر صحيح يبدأ بـ @'
                      : null,
                ),

                const SizedBox(height: 14),

                // الإيميل
                _fieldLabel('البريد الإلكتروني'),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    hintText: 'name@example.com',
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'أدخل البريد';
                    final re = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
                    if (!re.hasMatch(v.trim())) return 'بريد غير صالح';
                    return null;
                  },
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

                // كلمة المرور (اختياري)
                _fieldLabel('كلمة المرور (اختياري)'),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _passCtrl,
                  obscureText: _obscure,
                  decoration: InputDecoration(
                    hintText: 'اتركها فارغة إن لم ترغب بالتغيير',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      onPressed: () => setState(() => _obscure = !_obscure),
                      icon: Icon(
                        _obscure ? Icons.visibility : Icons.visibility_off,
                      ),
                    ),
                  ),
                  validator: (v) {
                    if (v != null && v.isNotEmpty && v.length < 6) {
                      return '6 أحرف على الأقل';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 22),

                // زر حفظ (تدرّج بسيط)
                SizedBox(
                  width: double.infinity,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      gradient: const LinearGradient(
                        colors: [AppColors.primary, AppColors.mint],
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
