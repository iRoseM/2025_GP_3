import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'map.dart';
import '../services/app_colors.dart';
import 'services/title_header.dart'; // NameerAppBar
import 'services/background_container.dart'; // AnimatedBackgroundContainer

class SupportPage extends StatefulWidget {
  const SupportPage({super.key});

  @override
  State<SupportPage> createState() => _SupportPageState();
}

class _SupportPageState extends State<SupportPage> {
  bool _showFaq = false;

  final faqs = const <_FaqItem>[
    _FaqItem(
      q: 'كيف أستعيد كلمة المرور؟',
      a: 'أعد تعيين كلمة المرور عبر حسابك الشخصي أو من شاشة تسجيل الدخول اختر "نسيت كلمة المرور" واتبع التعليمات لإعادة التعيين.',
    ),
    _FaqItem(
      q: 'كيف أكسب نقاط من المهام؟',
      a: 'يمكنك كسب النقاط من خلال الدخول إلى صفحة المهام، وتنفيذ المهمة المطلوبة، ثم رفع الإثبات المناسب (صورة أو باركود حسب نوع المهمة)، ليتم احتساب النقاط بعد التحقق.',
    ),
    _FaqItem(
      q: 'لماذا لا تظهر لي مواقع إعادة التدوير على الخريطة؟',
      a: 'تأكد من تفعيل خدمة الموقع (GPS) ومنح التطبيق صلاحية الوصول إلى الموقع، بالإضافة إلى التأكد من توفر اتصال بالإنترنت.',
    ),

    _FaqItem(
      q: 'كيف أتواصل مع الدعم؟',
      a: 'أرسل لنا رسالة عبر تواصل معنا : الإعدادات > المساعدة والدعم > تواصل معنا.',
    ),
  ];

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

  void _showSnack(String msg) {
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

  Widget _faqList() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE8F1EE), width: 1.2),
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
        itemCount: faqs.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, i) {
          final item = faqs[i];
          return Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 4,
              ),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              leading: const Icon(Icons.help_outline, color: appColors.primary),
              title: Text(
                item.q,
                style: GoogleFonts.ibmPlexSansArabic(
                  fontWeight: FontWeight.w800,
                  color: appColors.dark,
                ),
              ),
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    item.a,
                    style: GoogleFonts.ibmPlexSansArabic(
                      color: appColors.dark.withOpacity(.85),
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
                        'المساعدة والدعم',
                        style: GoogleFonts.ibmPlexSansArabic(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: appColors.dark,
                        ),
                      ),
                      const SizedBox(height: 16),

                      // ✅ الأسئلة الشائعة (تفتح تحتها)
                      _SupportTile(
                        title: 'الأسئلة الشائعة',
                        subtitle: 'إجابات لأكثر الأسئلة تكرارًا',
                        icon: Icons.quiz_outlined,
                        trailing: AnimatedRotation(
                          turns: _showFaq ? 0.5 : 0.0,
                          duration: const Duration(milliseconds: 180),
                          child: const Icon(
                            Icons.keyboard_arrow_down,
                            color: Colors.black54,
                          ),
                        ),
                        onTap: () => setState(() => _showFaq = !_showFaq),
                      ),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child: _showFaq ? _faqList() : const SizedBox.shrink(),
                      ),

                      const SizedBox(height: 12),

                      // ✅ إبلاغ
                      _SupportTile(
                        title: 'إبلاغ',
                        subtitle: 'أبلغنا عن مشكلة',
                        icon: Icons.report_gmailerrorred_outlined,
                        onTap: () => _showReportSheet(context),
                      ),

                      const SizedBox(height: 12),

                      // ✅ تواصل معنا
                      _SupportTile(
                        title: 'تواصل معنا',
                        subtitle: 'راسلنا عبر البريد الإلكتروني',
                        icon: Icons.mail_outline,
                        onTap: () async {
                          try {
                            await _openSupportEmail();
                          } catch (_) {
                            _showSnack(
                              'تعذر فتح تطبيق البريد. تأكد من وجود تطبيق بريد على جهازك.',
                            );
                          }
                        },
                      ),

                      const SizedBox(height: 18),
                      const _HintCard(),
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

/* ===================== صفحة إبلاغ (Placeholder) ===================== */

class ReportPagePlaceholder extends StatelessWidget {
  const ReportPagePlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: appColors.background,
        extendBodyBehindAppBar: true,
        appBar: const NameerAppBar(showTitleInBar: false, showBack: true),
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
                    'إبلاغ',
                    style: GoogleFonts.ibmPlexSansArabic(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: appColors.dark,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
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
                    child: Text(
                      'هنا بنحط نموذج الإبلاغ (نوع البلاغ + وصف + رفع صورة…)\n'
                      'علمني وش تبين بالضبط في الإبلاغ وبنركّبه مضبوط 👌',
                      style: GoogleFonts.ibmPlexSansArabic(
                        height: 1.6,
                        color: appColors.dark.withOpacity(.85),
                        fontWeight: FontWeight.w600,
                      ),
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

void _showReportSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    useSafeArea: true,
    isScrollControlled: false,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      return Directionality(
        textDirection: TextDirection.rtl,
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
          ),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // المقبض اللي فوق
              Container(
                width: 44,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: const Color(0x22000000),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),

              Text(
                'إبلاغ',
                style: GoogleFonts.ibmPlexSansArabic(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: appColors.dark,
                ),
              ),
              const SizedBox(height: 14),

              _gradientActionButton(
                icon: Icons.delete_outline, // تقدرين تغيّرينها
                label: 'إبلاغ عن حاوية',
                colors: const [appColors.primary, appColors.mint],
                onTap: () {
                  Navigator.pop(context); // يقفل البوتوم شيت
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const mapPage(reportMode: true),
                    ),
                  );
                },
              ),

              const SizedBox(height: 12),

              _gradientActionButton(
                icon: Icons.flag_outlined, // تقدرين تغيّرينها
                label: 'إبلاغ عن مهمة',
                colors: const [appColors.mint, appColors.primary],
                onTap: () async {
                  Navigator.pop(ctx);

                  // TODO: هنا نوديه لصفحة/نموذج إبلاغ المهمة
                  // مثال:
                  // await Navigator.push(
                  //   context,
                  //   MaterialPageRoute(builder: (_) => const ReportTaskPage()),
                  // );
                },
              ),
            ],
          ),
        ),
      );
    },
  );
}

// ✅ نفس زرّك بالضبط (Gradient + Icon)
Widget _gradientActionButton({
  required IconData icon,
  required String label,
  required List<Color> colors,
  required VoidCallback onTap,
}) {
  return Container(
    width: double.infinity,
    decoration: BoxDecoration(
      gradient: LinearGradient(colors: colors),
      borderRadius: BorderRadius.circular(14),
    ),
    child: ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.transparent,
        shadowColor: Colors.transparent,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      icon: Icon(icon, color: Colors.white),
      label: Text(
        label,
        style: GoogleFonts.ibmPlexSansArabic(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
      onPressed: onTap,
    ),
  );
}

/* ===================== Widgets مساعدة ===================== */

class _SupportTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;
  final Widget? trailing;

  const _SupportTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE8F1EE), width: 1.2),
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
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: appColors.light.withOpacity(.25),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: appColors.primary),
            ),
            const SizedBox(width: 12),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.ibmPlexSansArabic(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                      color: appColors.dark,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: GoogleFonts.ibmPlexSansArabic(
                      fontWeight: FontWeight.w600,
                      fontSize: 13.5,
                      color: appColors.dark.withOpacity(.7),
                    ),
                  ),
                ],
              ),
            ),

            // ⬇️ سهم لتحت للجميع
            trailing ??
                const Icon(Icons.keyboard_arrow_down, color: Colors.black54),
          ],
        ),
      ),
    );
  }
}

class _HintCard extends StatelessWidget {
  const _HintCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF7FBF9),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE3F1EC)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, color: appColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'إذا لم تجد جواب سؤالك في الأسئلة الشائعة، اضغط "تواصل معنا" وارسل لنا التفاصيل.',
              style: GoogleFonts.ibmPlexSansArabic(
                height: 1.6,
                fontWeight: FontWeight.w600,
                color: appColors.dark.withOpacity(.85),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FaqItem {
  final String q;
  final String a;
  const _FaqItem({required this.q, required this.a});
}
