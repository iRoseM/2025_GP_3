import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

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

class NameerAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final double height;
  final bool centerTitle;
  final List<Widget>? actions;
  final PreferredSizeWidget? bottom;
  final bool frosted;
  final bool showTitleInBar;

  const NameerAppBar({
    super.key,
    this.title = '',
    this.height = 80,
    this.centerTitle = false,
    this.actions,
    this.bottom,
    this.frosted = false,
    this.showTitleInBar = false,
  });

  @override
  Size get preferredSize =>
      Size.fromHeight(height + (bottom?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context) {
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
            AppColors.primary,
            AppColors.primary.withOpacity(.7),
            AppColors.primary.withOpacity(.1),
            AppColors.background,
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
      automaticallyImplyLeading: false, // 👈 لا يوجد زر رجوع
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
