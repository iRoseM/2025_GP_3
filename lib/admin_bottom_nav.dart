import 'package:flutter/material.dart';

 // <-- make sure this matches where AppColors is defined

class NavItem {
  final IconData outlined;
  final IconData filled;
  final String label;
  const NavItem({
    required this.outlined,
    required this.filled,
    required this.label,
  });
}

class AdminBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const AdminBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final items = const [
      NavItem(
        outlined: Icons.local_offer_outlined,
        filled: Icons.local_offer,
        label: 'الجوائز',
      ),
      NavItem(
        outlined: Icons.map_outlined,
        filled: Icons.map,
        label: 'الخريطة',
      ),
      NavItem(
        outlined: Icons.description_outlined,
        filled: Icons.description,
        label: 'المهام',
      ),
      NavItem(
        outlined: Icons.dashboard_outlined,
        filled: Icons.dashboard,
        label: 'لوحة التحكم',
      ),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: Container(
          height: 70,
          color: Colors.white,

          // ✅ Fix navigation direction
          child: Directionality(
            textDirection: TextDirection.ltr, // force normal left→right order
            child: Row(
              children: List.generate(items.length, (i) {
                final it = items[i];
                final selected = i == currentIndex;
                final iconData = selected ? it.filled : it.outlined;
                final color =
                    selected ? const Color(0xFF009688) : Colors.black54;

                return Expanded(
                  child: InkWell(
                    onTap: () => onTap(i),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(iconData, color: color, size: 26),
                        const SizedBox(height: 2),
                        Text(
                          it.label,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight:
                                selected ? FontWeight.w800 : FontWeight.w500,
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
      ),
    );
  }
}
