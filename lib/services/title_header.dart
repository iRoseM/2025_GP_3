import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/app_colors.dart';

class NameerAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final double height;
  final bool centerTitle;
  final List<Widget>? actions;
  final PreferredSizeWidget? bottom;
  final bool frosted;
  final bool showTitleInBar;
  final bool showBack; // ✅ زر الرجوع

  const NameerAppBar({
    super.key,
    this.title = '',
    this.height = 80,
    this.centerTitle = false,
    this.actions,
    this.bottom,
    this.frosted = false,
    this.showTitleInBar = false,
    this.showBack = false, // 🔹 افتراضيًا غير ظاهر
  });

  @override
  Size get preferredSize =>
      Size.fromHeight(height + (bottom?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context) {
    final leading = showBack
        ? IconButton(
            icon: const Icon(
              Icons.arrow_back_ios_new_rounded,
              color: Colors.white,
              size: 20,
            ),
            onPressed: () => Navigator.maybePop(context),
            tooltip: 'رجوع',
          )
        : null;

    // العنوان داخل الهيدر (اختياري)
    final titleWidget = Text(
      title,
      style: GoogleFonts.ibmPlexSansArabic(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: Colors.white,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: centerTitle ? TextAlign.center : TextAlign.right,
    );

    // خلفية متدرجة متناسقة مع الخلفية العامة
    final gradientBg = Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            appColors.primary,
            appColors.primary.withOpacity(.7),
            appColors.primary.withOpacity(.1),
            appColors.background,
          ],
          stops: const [0.0, 0.55, 1.0, 1.0],
        ),
      ),
    );

    // طبقة زجاجية خفيفة (اختيارية)
    final frostedLayer = frosted
        ? ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
              child: Container(color: Colors.white.withOpacity(0.06)),
            ),
          )
        : const SizedBox.shrink();

    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      automaticallyImplyLeading: false,
      leading: leading,
      centerTitle: centerTitle,
      toolbarHeight: height,
      actions: actions,
      title: showTitleInBar ? titleWidget : null,
      flexibleSpace: Stack(
        fit: StackFit.expand,
        children: [gradientBg, frostedLayer],
      ),
      bottom:
          bottom ??
          const PreferredSize(
            preferredSize: Size.fromHeight(0),
            child: SizedBox.shrink(),
          ),
    );
  }
}
