import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'main.dart';
import 'home.dart';
import 'services/background_container.dart';
import 'services/bottom_nav.dart';
import 'notifications.dart';
import 'services/connection.dart';
import 'services/title_header.dart';
import '../services/app_colors.dart';
import 'support_page.dart';
import 'admin_faq_page.dart';

class profilePage extends StatefulWidget {
  const profilePage({super.key});

  @override
  State<profilePage> createState() => _profilePageState();
}

class _profilePageState extends State<profilePage> {
  bool _autoAgentMode = false;
  bool _isLoadingAgentMode = true;

  @override
  void initState() {
    super.initState();
    _loadAutoAgentMode();
  }

  Future<void> _loadAutoAgentMode() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        if (doc.exists) {
          final data = doc.data();
          setState(() {
            _autoAgentMode = data?['autoAgentMode'] ?? false;
            _isLoadingAgentMode = false;
          });
        } else {
          setState(() {
            _isLoadingAgentMode = false;
          });
        }
      } else {
        setState(() {
          _isLoadingAgentMode = false;
        });
      }
    } catch (e) {
      debugPrint('❌ Error loading auto agent mode: $e');
      setState(() {
        _isLoadingAgentMode = false;
      });
    }
  }

  Future<void> _saveAutoAgentMode(bool value) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .update({
              'autoAgentMode': value,
              'updatedAt': FieldValue.serverTimestamp(),
            });

        setState(() {
          _autoAgentMode = value;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                value
                    ? '✅ تم تفعيل وضع التحكم التلقائي للـ Agent'
                    : '❌ تم إيقاف وضع التحكم التلقائي للـ Agent',
                style: GoogleFonts.ibmPlexSansArabic(),
              ),
              backgroundColor: value ? Colors.green : Colors.grey,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('❌ Error saving auto agent mode: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'حدث خطأ في حفظ الإعدادات',
              style: GoogleFonts.ibmPlexSansArabic(),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = GoogleFonts.ibmPlexSansArabicTextTheme(
      Theme.of(context).textTheme,
    );

    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, authSnap) {
        if (authSnap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(color: appColors.primary),
            ),
          );
        }

        final user = authSnap.data;
        if (user == null) {
          return const SizedBox.shrink();
        }

        return Directionality(
          textDirection: TextDirection.rtl,
          child: Theme(
            data: Theme.of(context).copyWith(textTheme: textTheme),
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
                              'حسابي الشخصي',
                              style: GoogleFonts.ibmPlexSansArabic(
                                fontSize: 24,
                                fontWeight: FontWeight.w700,
                                color: appColors.dark,
                              ),
                            ),
                            const SizedBox(height: 16),

                            StreamBuilder<
                              DocumentSnapshot<Map<String, dynamic>>
                            >(
                              stream: FirebaseFirestore.instance
                                  .collection('users')
                                  .doc(user.uid)
                                  .snapshots(),
                              builder: (context, snap) {
                                if (snap.connectionState ==
                                    ConnectionState.waiting) {
                                  return const SizedBox(
                                    height: 120,
                                    child: Center(
                                      child: CircularProgressIndicator(
                                        color: appColors.primary,
                                      ),
                                    ),
                                  );
                                }

                                if (snap.hasError) {
                                  final err = snap.error;
                                  if (err is FirebaseException) {
                                    final isNetwork =
                                        err.code == 'unavailable' ||
                                        err.code == 'network-request-failed';
                                    final isAuth =
                                        err.code == 'permission-denied' ||
                                        err.code == 'unauthenticated';
                                    if (isNetwork) {
                                      WidgetsBinding.instance
                                          .addPostFrameCallback((_) {
                                            if (context.mounted)
                                              showNoInternetDialog(context);
                                          });
                                    }
                                    if (isAuth) return const SizedBox.shrink();
                                  }
                                  return const SizedBox.shrink();
                                }

                                final isLoading =
                                    snap.connectionState ==
                                    ConnectionState.waiting;
                                final data = snap.data?.data();

                                final username = (data?['username'] ?? 'مستخدم')
                                    .toString();
                                final email =
                                    (data?['email'] ?? user.email ?? '')
                                        .toString();
                                final age = (data?['age'] is int)
                                    ? (data?['age'] as int)
                                    : int.tryParse('${data?['age'] ?? ''}') ??
                                          0;
                                final gender = (data?['gender'] ?? 'male')
                                    .toString();

                                final int? pfpIndex = (data?['pfpIndex'] is int)
                                    ? (data?['pfpIndex'] as int)
                                    : int.tryParse(
                                        '${data?['pfpIndex'] ?? ''}',
                                      );
                                String? avatarPath;
                                if (pfpIndex != null &&
                                    pfpIndex >= 0 &&
                                    pfpIndex < 8) {
                                  avatarPath =
                                      'assets/pfp/pfp${pfpIndex + 1}.png';
                                }

                                return Column(
                                  children: [
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
                                          Container(
                                            decoration: const BoxDecoration(
                                              color: appColors.light,
                                              shape: BoxShape.circle,
                                            ),
                                            child: CircleAvatar(
                                              radius: 28,
                                              backgroundColor:
                                                  Colors.transparent,
                                              backgroundImage:
                                                  (avatarPath != null &&
                                                      !isLoading)
                                                  ? AssetImage(avatarPath)
                                                  : null,
                                              child:
                                                  (avatarPath == null ||
                                                      isLoading)
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
                                                Text(
                                                  isLoading
                                                      ? 'جارٍ التحميل…'
                                                      : username,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style:
                                                      GoogleFonts.ibmPlexSansArabic(
                                                        fontSize: 18,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        color: appColors.dark,
                                                      ),
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  isLoading ? '...' : email,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style:
                                                      GoogleFonts.ibmPlexSansArabic(
                                                        fontSize: 14,
                                                        color: appColors.dark
                                                            .withOpacity(.7),
                                                      ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 16),

                                    SizedBox(
                                      width: double.infinity,
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                          gradient: const LinearGradient(
                                            colors: [
                                              appColors.mint,
                                              appColors.primary,
                                              appColors.primary,
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
                                              borderRadius:
                                                  BorderRadius.circular(14),
                                            ),
                                            elevation: 0,
                                          ),
                                          icon: const Icon(
                                            Icons.edit,
                                            color: Colors.white,
                                          ),
                                          label: Text(
                                            'تعديل الحساب',
                                            style:
                                                GoogleFonts.ibmPlexSansArabic(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w700,
                                                  color: Colors.white,
                                                ),
                                          ),
                                          onPressed: (isLoading)
                                              ? null
                                              : () {
                                                  Navigator.of(context).push(
                                                    MaterialPageRoute(
                                                      builder: (_) =>
                                                          EditProfilePage(
                                                            initialUsername:
                                                                username,
                                                            initialHandle:
                                                                '$username',
                                                            initialEmail: email,
                                                            initialAge: age == 0
                                                                ? 18
                                                                : age,
                                                            initialGender:
                                                                gender,
                                                            initialPfpIndex:
                                                                pfpIndex,
                                                          ),
                                                    ),
                                                  );
                                                },
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 24),

                                    _SettingsCard(
                                      children: [
                                        if (data?['role'] != 'admin')
                                          StreamBuilder<
                                            DocumentSnapshot<
                                              Map<String, dynamic>
                                            >
                                          >(
                                            stream: FirebaseFirestore.instance
                                                .collection('users')
                                                .doc(
                                                  FirebaseAuth
                                                      .instance
                                                      .currentUser!
                                                      .uid,
                                                )
                                                .snapshots(),
                                            builder: (context, userSnap) {
                                              if (!userSnap.hasData) {
                                                return _SettingTile(
                                                  title: 'إشعاراتي',
                                                  icon: Icons
                                                      .notifications_outlined,
                                                  trailing: const Icon(
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
                                              }

                                              final userData = userSnap.data!
                                                  .data()!;
                                              final lastOpened =
                                                  userData['lastOpenedNotifications']
                                                      as Timestamp?;

                                              return StreamBuilder<
                                                QuerySnapshot<
                                                  Map<String, dynamic>
                                                >
                                              >(
                                                stream: FirebaseFirestore
                                                    .instance
                                                    .collection('notifications')
                                                    .where(
                                                      'userId',
                                                      isEqualTo: FirebaseAuth
                                                          .instance
                                                          .currentUser!
                                                          .uid,
                                                    )
                                                    .orderBy(
                                                      'createdAt',
                                                      descending: true,
                                                    )
                                                    .snapshots(),
                                                builder: (context, notifSnap) {
                                                  if (!notifSnap.hasData) {
                                                    return _SettingTile(
                                                      title: 'إشعاراتي',
                                                      icon: Icons
                                                          .notifications_outlined,
                                                      trailing: const Icon(
                                                        Icons.chevron_left,
                                                        color: Colors.black54,
                                                        size: 22,
                                                      ),
                                                      onTap: () {
                                                        Navigator.of(
                                                          context,
                                                        ).push(
                                                          MaterialPageRoute(
                                                            builder: (_) =>
                                                                const MyReportsPage(),
                                                          ),
                                                        );
                                                      },
                                                    );
                                                  }

                                                  int newCount = 0;
                                                  for (var doc
                                                      in notifSnap.data!.docs) {
                                                    final createdAt =
                                                        doc['createdAt']
                                                            as Timestamp?;
                                                    if (lastOpened == null ||
                                                        (createdAt != null &&
                                                            createdAt
                                                                .toDate()
                                                                .isAfter(
                                                                  lastOpened
                                                                      .toDate(),
                                                                ))) {
                                                      newCount++;
                                                    }
                                                  }

                                                  Widget trailing = newCount > 0
                                                      ? Container(
                                                          padding:
                                                              const EdgeInsets.symmetric(
                                                                horizontal: 8,
                                                                vertical: 4,
                                                              ),
                                                          decoration: BoxDecoration(
                                                            color: Colors
                                                                .redAccent,
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                  12,
                                                                ),
                                                          ),
                                                          child: const Text(
                                                            'جديدة',
                                                            style: TextStyle(
                                                              color:
                                                                  Colors.white,
                                                              fontSize: 12,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold,
                                                            ),
                                                          ),
                                                        )
                                                      : const Icon(
                                                          Icons.chevron_left,
                                                          color: Colors.black54,
                                                          size: 22,
                                                        );

                                                  return _SettingTile(
                                                    title: 'إشعاراتي',
                                                    icon: Icons
                                                        .notifications_outlined,
                                                    trailing: trailing,
                                                    onTap: () {
                                                      Navigator.of(
                                                        context,
                                                      ).push(
                                                        MaterialPageRoute(
                                                          builder: (_) =>
                                                              const MyReportsPage(),
                                                        ),
                                                      );
                                                    },
                                                  );
                                                },
                                              );
                                            },
                                          ),

                                        _buildLanguageAndAgentTile(
                                          isAdmin: data?['role'] == 'admin',
                                        ),

                                        _SettingTile(
                                          title: 'الخصوصية والأمان',
                                          icon: Icons.lock_outline,
                                          onTap: () =>
                                              _showPrivacySheet(context),
                                        ),

                                        _SettingTile(
                                          title: 'المساعدة والدعم',
                                          icon: Icons.help_outline,
                                          onTap: () {
                                            final role =
                                                (data?['role'] ?? 'user')
                                                    .toString();
                                            Navigator.of(context).push(
                                              MaterialPageRoute(
                                                builder: (_) => role == 'admin'
                                                    ? const AdminFaqPage()
                                                    : const SupportPage(),
                                              ),
                                            );
                                          },
                                        ),
                                      ],
                                    ),
                                  ],
                                );
                              },
                            ),

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
                                            borderRadius: BorderRadius.circular(
                                              20,
                                            ),
                                          ),
                                          insetPadding:
                                              const EdgeInsets.symmetric(
                                                horizontal: 24,
                                              ),
                                          child: Padding(
                                            padding: const EdgeInsets.all(20),
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Image.asset(
                                                  'assets/img/nameerThink.png',
                                                  height: 120,
                                                  fit: BoxFit.contain,
                                                ),
                                                const SizedBox(height: 16),
                                                Text(
                                                  'هل تريد تأكيد تسجيل الخروج؟',
                                                  textAlign: TextAlign.center,
                                                  style:
                                                      GoogleFonts.ibmPlexSansArabic(
                                                        fontSize: 18,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        color: appColors.dark,
                                                      ),
                                                ),
                                                const SizedBox(height: 24),
                                                Row(
                                                  children: [
                                                    Expanded(
                                                      child: OutlinedButton(
                                                        style: OutlinedButton.styleFrom(
                                                          side:
                                                              const BorderSide(
                                                                color: appColors
                                                                    .primary,
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
                                                        onPressed: () =>
                                                            Navigator.of(
                                                              context,
                                                            ).pop(),
                                                        child: Text(
                                                          'إلغاء',
                                                          style:
                                                              GoogleFonts.ibmPlexSansArabic(
                                                                color: appColors
                                                                    .primary,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w700,
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
                                                              appColors.primary,
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
                                                          ).pop();
                                                          try {
                                                            await FirebaseAuth
                                                                .instance
                                                                .signOut();
                                                          } catch (_) {}
                                                          if (context.mounted) {
                                                            Navigator.of(
                                                              context,
                                                            ).pushAndRemoveUntil(
                                                              MaterialPageRoute(
                                                                builder: (_) =>
                                                                    RegisterPage(),
                                                              ),
                                                              (route) => false,
                                                            );
                                                          }
                                                        },
                                                        child: Text(
                                                          'تأكيد',
                                                          style:
                                                              GoogleFonts.ibmPlexSansArabic(
                                                                color: Colors
                                                                    .white,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w700,
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
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // ✅ دالة لبناء خيار اللغة مع Toggle للـ Agent (يظهر فقط للمدير)

  // ثم عدل دالة _buildLanguageAndAgentTile في نفس الملف
  Widget _buildLanguageAndAgentTile({required bool isAdmin}) {
    print('🔍 _buildLanguageAndAgentTile - isAdmin: $isAdmin');

    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade200, width: 0.5),
        ),
      ),
      child: Column(
        children: [
          // خيار اللغة (يظهر للجميع)
          ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 2,
            ),
            leading: Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: appColors.light.withOpacity(.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.language, color: appColors.primary),
            ),
            title: Text(
              'اللغة',
              style: GoogleFonts.ibmPlexSansArabic(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: appColors.dark,
              ),
            ),
            trailing: Text(
              'العربية',
              style: GoogleFonts.ibmPlexSansArabic(
                color: appColors.dark.withOpacity(.8),
                fontWeight: FontWeight.w600,
              ),
            ),
            onTap: () => _showSnack(
              context,
              'التطبيق حالياً يدعم اللغة العربية فقط، وسيتم إضافة لغات أخرى قريباً بإذن الله✨',
            ),
          ),

          // ✅ مفتاح تبديل وضع الـ Agent (يظهر فقط للمدير - Admin)
          if (isAdmin) ...[
            ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 2,
              ),
              leading: Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: appColors.light.withOpacity(.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.admin_panel_settings,
                  color: _autoAgentMode ? appColors.primary : Colors.grey,
                  size: 24,
                ),
              ),
              title: Text(
                'التحكم التلقائي للـ Agent',
                style: GoogleFonts.ibmPlexSansArabic(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: appColors.dark,
                ),
              ),
              subtitle: Text(
                _autoAgentMode
                    ? '🔒 الوضع التلقائي مفعل - الـ Agent يتحكم بالمهام والفئات'
                    : 'تفعيل التحكم التلقائي لمدير النظام',
                style: GoogleFonts.ibmPlexSansArabic(
                  fontSize: 11,
                  color: _autoAgentMode ? appColors.primary : Colors.grey[600],
                ),
              ),
              trailing: _isLoadingAgentMode
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Switch(
                      value: _autoAgentMode,
                      onChanged: (value) async {
                        await _saveAutoAgentMode(value);
                        // تحديث واجهة الإدارة إذا كانت مفتوحة
                        if (mounted && Navigator.of(context).canPop()) {
                          Navigator.of(context).pop();
                        }
                      },
                      activeColor: appColors.primary,
                      activeTrackColor: appColors.primary.withOpacity(0.3),
                    ),
            ),
          ],
        ],
      ),
    );
  }

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
                    const Icon(Icons.lock_outline, color: appColors.primary),
                    const SizedBox(width: 8),
                    Text(
                      'الخصوصية والأمان',
                      style: GoogleFonts.ibmPlexSansArabic(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: appColors.dark,
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
                  'يمكنك ضبط صلاحيات الوصول للموقع والكاميرا والإشعارات.',
                ),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text('تم'),
                    style: TextButton.styleFrom(
                      foregroundColor: appColors.primary,
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

  Future<void> _openSupportEmail() async {
    final Uri emailUri = Uri(
      scheme: 'mailto',
      path: 'appnameer@gmail.com',
      queryParameters: <String, String>{'subject': 'دعم تطبيق Nameer'},
    );

    if (!await launchUrl(emailUri)) {
      throw Exception('لا يمكن فتح تطبيق البريد');
    }
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
                    const Icon(Icons.support_agent, color: appColors.primary),
                    const SizedBox(width: 8),
                    Text(
                      'المساعدة والدعم',
                      style: GoogleFonts.ibmPlexSansArabic(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: appColors.dark,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _faqItem(
                  q: 'كيف أستعيد كلمة المرور؟',
                  a: 'أعد تعيين كلمة المرور عبر حسابك الشخصي أو من شاشة تسجيل الدخول اختر "نسيت كلمة المرور" واتبع التعليمات لإعادة التعيين.',
                ),
                const SizedBox(height: 8),
                _faqItem(
                  q: 'كيف أتواصل مع الدعم؟',
                  a: 'أرسل لنا رسالة عبر تواصل معنا : الإعدادات > المساعدة والدعم > تواصل معنا.',
                ),
                const SizedBox(height: 8),
                _faqItem(
                  q: 'كيف أبلّغ عن مشكلة؟',
                  a: 'أرسل لنا رسالة عبر تواصل معنا تتضمّن وصف المشكلة وصورة لها إن أمكن: الإعدادات > المساعدة والدعم > تواصل معنا.',
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: appColors.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () async {
                        Navigator.pop(ctx);
                        try {
                          await _openSupportEmail();
                        } catch (e) {
                          _showSnack(
                            context,
                            'تعذر فتح تطبيق البريد. يرجى التحقق من وجود تطبيق البريد على الجهاز.',
                          );
                        }
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

  static Widget _privacyBullet(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.verified_user, size: 18, color: appColors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.ibmPlexSansArabic(
                fontSize: 14,
                height: 1.5,
                color: appColors.dark,
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
              color: appColors.dark,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            a,
            style: GoogleFonts.ibmPlexSansArabic(
              color: appColors.dark.withOpacity(.8),
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
        backgroundColor: slackMesseges.red,
        content: Text(
          msg,
          style: GoogleFonts.ibmPlexSansArabic(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
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
          color: appColors.light.withOpacity(.2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: iconColor ?? appColors.primary),
      ),
      title: Text(
        title,
        style: GoogleFonts.ibmPlexSansArabic(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: titleColor ?? appColors.dark,
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

  late final TextEditingController _usernameCtrl; // عرض فقط
  late final TextEditingController _handleCtrl; // عرض فقط
  late final TextEditingController _emailCtrl; // عرض فقط
  late final TextEditingController _ageCtrl;

  // تغيير كلمة المرور (اختياري)
  bool _changePassword = false;
  late final TextEditingController _currentPassCtrl;
  late final TextEditingController _newPassCtrl;
  late final TextEditingController _confirmPassCtrl;
  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;

  late String _gender;

  // صور الأفاتار
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
  int? _pfpIndex;

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
    _pfpIndex = widget.initialPfpIndex; // من الداتابيس

    _googlePhotoUrl = FirebaseAuth.instance.currentUser?.photoURL;
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

    super.dispose();
  }

  String? _googlePhotoUrl;
  bool _useGooglePhoto = false;
  // شارة “غير قابل للتعديل”
  Widget _lockedTag() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
    decoration: BoxDecoration(
      color: appColors.primary.withOpacity(.12),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: appColors.primary.withOpacity(.3)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: const [
        Icon(Icons.lock, size: 12, color: appColors.primary),
        SizedBox(width: 3),
        Text(
          'غير قابل للتعديل',
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            color: appColors.primary,
          ),
        ),
      ],
    ),
  );

  // ديكور الحقول المقفولة (تظليل + حد)
  InputDecoration _lockedDecoration({
    required String hint,
    required IconData icon,
  }) {
    return InputDecoration(
      hintText: hint,
      prefixIcon: Icon(icon),
      filled: true,
      fillColor: appColors.primary.withOpacity(.10), // ✅ تظليل أخضر
      suffixIcon: Padding(
        padding: const EdgeInsetsDirectional.only(end: 8),
        child: _lockedTag(),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: const BorderRadius.all(Radius.circular(14)),
        borderSide: BorderSide(
          color: appColors.primary.withOpacity(.65),
          width: 1.4,
        ),
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(14)),
        borderSide: BorderSide(color: appColors.primary, width: 1.6),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }

  // حقل مقفول باستخدام AbsorbPointer (بديل readOnly)
  Widget _lockedTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
  }) {
    return AbsorbPointer(
      child: TextFormField(
        controller: controller,
        enableInteractiveSelection: false,
        decoration: _lockedDecoration(hint: hint, icon: icon),
      ),
    );
  }

  Future<void> _save() async {
    if (!await hasInternetConnection()) {
      if (context.mounted) showNoInternetDialog(context);
      return;
    }
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: slackMesseges.red,
          content: Text(
            'لا يوجد مستخدم مسجّل.',
            style: GoogleFonts.ibmPlexSansArabic(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
      return;
    }

    try {
      final fs = FirebaseFirestore.instance;
      final userRef = fs.collection('users').doc(user.uid);

      final newAge = int.tryParse(_ageCtrl.text.trim()) ?? widget.initialAge;
      final newGender = _gender;
      final newPfp = _pfpIndex;

      final patch = <String, dynamic>{'age': newAge, 'gender': newGender};

      // ← حفظ الصورة المختارة
      if (_useGooglePhoto && _googlePhotoUrl != null) {
        patch['googlePhotoUrl'] = _googlePhotoUrl;
        patch['pfpIndex'] = FieldValue.delete();
      } else if (newPfp != null) {
        patch['pfpIndex'] = newPfp;
        patch['googlePhotoUrl'] = FieldValue.delete();
      }

      await userRef.set(patch, SetOptions(merge: true));

      // تغيير كلمة المرور (اختياري)
      if (_changePassword) {
        final emailForAuth = user.email;
        if (emailForAuth == null || emailForAuth.isEmpty) {
          throw Exception('لا يمكن إعادة المصادقة: البريد غير متوفر.');
        }
        final cred = EmailAuthProvider.credential(
          email: emailForAuth,
          password: _currentPassCtrl.text,
        );
        await user.reauthenticateWithCredential(cred);
        await user.updatePassword(_newPassCtrl.text);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: slackMesseges.primary,
          content: Text(
            'تم حفظ التغييرات ✅',
            style: GoogleFonts.ibmPlexSansArabic(fontWeight: FontWeight.w700),
          ),
        ),
      );
      Navigator.of(context).pop();
    } on FirebaseAuthException catch (e) {
      var msg = 'تعذّر حفظ التغييرات (${e.code})';
      if (e.code == 'requires-recent-login') {
        msg = 'لأسباب أمان، يرجى تسجيل الدخول مجددًا ثم المحاولة.';
      } else if (e.code == 'wrong-password') {
        msg = 'كلمة المرور الحالية غير صحيحة.';
      } else if (e.code == 'network-request-failed') {
        msg = 'تعذّر الاتصال — يرجى التحقق من الإنترنت.';
      }
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('❌ $msg')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: slackMesseges.red,
          content: Text(
            '❌ خطأ غير متوقع: $e',
            style: GoogleFonts.ibmPlexSansArabic(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
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
                    const Icon(Icons.image_outlined, color: appColors.primary),
                    const SizedBox(width: 8),
                    Text(
                      'اختر صورة الحساب',
                      style: GoogleFonts.ibmPlexSansArabic(
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                        color: appColors.dark,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (_googlePhotoUrl != null)
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _useGooglePhoto = true;
                        _pfpIndex = null;
                      });
                      Navigator.pop(ctx);
                    },
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: _useGooglePhoto
                            ? appColors.primary.withOpacity(0.1)
                            : Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: _useGooglePhoto
                              ? appColors.primary
                              : Colors.grey.shade200,
                          width: 1.5,
                        ),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 24,
                            backgroundImage: NetworkImage(_googlePhotoUrl!),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'استخدام صورة Google',
                            style: GoogleFonts.ibmPlexSansArabic(
                              fontWeight: FontWeight.w700,
                              color: appColors.dark,
                            ),
                          ),
                          const Spacer(),
                          if (_useGooglePhoto)
                            const Icon(
                              Icons.check_circle,
                              color: appColors.primary,
                            ),
                        ],
                      ),
                    ),
                  ),
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
                    final selected = !_useGooglePhoto && _pfpIndex == i;
                    return InkWell(
                      borderRadius: BorderRadius.circular(999),
                      onTap: () {
                        setState(() {
                          _pfpIndex = i;
                          _useGooglePhoto = false;
                        });
                        Navigator.pop(ctx);
                      },
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          CircleAvatar(
                            radius: 36,
                            backgroundColor: selected
                                ? appColors.primary
                                : appColors.light.withOpacity(.25),
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
                                  color: appColors.primary,
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
        Container(
          decoration: const BoxDecoration(
            color: appColors.light,
            shape: BoxShape.circle,
          ),
          child: CircleAvatar(
            radius: 32,
            backgroundColor: Colors.transparent,
            backgroundImage: _useGooglePhoto && _googlePhotoUrl != null
                ? NetworkImage(_googlePhotoUrl!) as ImageProvider
                : _pfpIndex != null
                ? AssetImage(_avatars[_pfpIndex!])
                : null,
            child: (!_useGooglePhoto && _pfpIndex == null)
                ? const Icon(
                    Icons.person_outline,
                    color: Colors.white,
                    size: 34,
                  )
                : null,
          ),
        ),
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
                decoration: const BoxDecoration(
                  color: appColors.primary,
                  shape: BoxShape.circle,
                  boxShadow: [
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
        backgroundColor: appColors.background,
        extendBodyBehindAppBar: true,
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

            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(16, topPadding, 16, 16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'تعديل الحساب',
                      style: GoogleFonts.ibmPlexSansArabic(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: appColors.dark,
                      ),
                    ),
                    const SizedBox(height: 15),

                    Row(children: [avatarWidget, const SizedBox(width: 10)]),
                    const SizedBox(height: 14),

                    // اسم المستخدم (مقفل)
                    _fieldLabel('اسم المستخدم'),
                    const SizedBox(height: 8),
                    _lockedTextField(
                      controller: _handleCtrl,
                      hint: 'username',
                      icon: Icons.alternate_email,
                    ),

                    const SizedBox(height: 14),

                    // البريد الإلكتروني (مقفل)
                    _fieldLabel('البريد الإلكتروني'),
                    const SizedBox(height: 8),
                    _lockedTextField(
                      controller: _emailCtrl,
                      hint: 'name@example.com',
                      icon: Icons.email_outlined,
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
                                    return 'يرجى إدخال عمر منطقي';
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
                          onPressed: () =>
                              setState(() => _changePassword = true),
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
                            onPressed: () => setState(
                              () => _obscureCurrent = !_obscureCurrent,
                            ),
                            icon: Icon(
                              _obscureCurrent
                                  ? Icons.visibility
                                  : Icons.visibility_off,
                            ),
                          ),
                        ),
                        validator: (v) {
                          if (_changePassword && (v == null || v.isEmpty)) {
                            return 'يرجى إدخال كلمة المرور الحالية';
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
                              _obscureNew
                                  ? Icons.visibility
                                  : Icons.visibility_off,
                            ),
                          ),
                        ),
                        validator: (v) {
                          if (_changePassword) {
                            if (v == null || v.isEmpty) {
                              return 'يرجى إدخال كلمة المرور الجديدة';
                            }
                            if (v.length < 8) {
                              return 'كلمة المرور يجب أن تكون 8 أحرف على الأقل';
                            } else if (!RegExp(r'[A-Z]').hasMatch(v) ||
                                !RegExp(r'[a-z]').hasMatch(v)) {
                              return 'يجب أن تحتوي كلمة المرور على حرف كبير وحرف صغير على الأقل.';
                            }
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
                            onPressed: () => setState(
                              () => _obscureConfirm = !_obscureConfirm,
                            ),
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
                              return 'يرجى إعادة إدخال كلمة المرور';
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

                    // زر حفظ
                    SizedBox(
                      width: double.infinity,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
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
            );
          },
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
        color: appColors.dark.withOpacity(.9),
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
        ? appColors.primary.withOpacity(.12)
        : Colors.transparent;
    final border = selected ? appColors.primary : appColors.light;
    final fg = selected ? appColors.dark : Colors.black.withOpacity(.7);

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
            Icon(icon, size: 20, color: appColors.primary),
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
