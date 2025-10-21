import 'package:flutter/material.dart';

class BottomNavPage extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const BottomNavPage({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const items = [
      _NavItem(Icons.home_outlined, Icons.home, 'الرئيسية'),
      _NavItem(Icons.fact_check_outlined, Icons.fact_check, 'مهامي'),
      _NavItem(Icons.flag_outlined, Icons.flag, 'المراحل', isCenter: true),
      _NavItem(Icons.map_outlined, Icons.map, 'الخريطة'),
      _NavItem(Icons.group_outlined, Icons.group, 'الأصدقاء'),
    ];

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Container(
          height: 74,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(26),
            boxShadow: const [
              BoxShadow(
                color: Color(0x22000000),
                blurRadius: 18,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(items.length, (i) {
              final it = items[i];
              final selected = i == currentIndex;

              // الزر الوسطي الدائري (المراحل)
              if (it.isCenter) {
                final bool centerSelected = currentIndex == 2;
                return Expanded(
                  child: Center(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(999),
                      onTap: () => onTap(2),
                      child: Container(
                        width: 60,
                        height: 60,
                        decoration: const BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Color(0x33000000),
                              blurRadius: 10,
                              offset: Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Icon(
                          centerSelected
                              ? Icons.flag
                              : Icons
                                    .flag_outlined, // ✅ ممتلئة عند currentIndex=2
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                    ),
                  ),
                );
              }

              // العناصر الجانبية
              final iconData = selected ? it.filled : it.outlined;
              final color = selected ? AppColors.primary : Colors.black54;

              return Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () => onTap(i),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(iconData, color: color, size: 26),
                      const SizedBox(height: 3),
                      Text(
                        it.label,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: selected
                              ? FontWeight.w800
                              : FontWeight.w500,
                          color: color,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

class _NavItem {
  final IconData outlined;
  final IconData filled;
  final String label;
  final bool isCenter;
  const _NavItem(
    this.outlined,
    this.filled,
    this.label, {
    this.isCenter = false,
  });
}

// ألوان الهوية (نفس المستخدمة في الصفحة)
class AppColors {
  static const primary = Color(0xFF4BAA98);
  static const dark = Color(0xFF3C3C3B);
  static const accent = Color(0xFFF4A340);
  static const sea = Color(0xFF1F7A8C);
  static const light = Color(0xFF79D0BE);
  static const background = Color(0xFFF3FAF7);
  static const mint = Color(0xFFB6E9C1);
  static const tealSoft = Color(0xFF75BCAF);
}
