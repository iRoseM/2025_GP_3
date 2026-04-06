// lib/widgets/ecoland_grid.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/app_colors.dart';

class EcoLandGrid extends StatelessWidget {
  final String userId;
  final Function(List<IsoItem> items) onItemsLoaded; // ✅ هذا موجود؟

  const EcoLandGrid({
    super.key,
    required this.userId,
    required this.onItemsLoaded, // ✅ required
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('ecolandRewards')
          .orderBy('earnedAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        final List<IsoItem> items = [];

        if (snapshot.hasData && snapshot.data != null) {
          final rewards = snapshot.data!.docs;

          for (int i = 0; i < rewards.length && i < 36; i++) {
            final data = rewards[i].data() as Map<String, dynamic>;
            final row = (i ~/ 6) % 6;
            final col = i % 6;

            items.add(
              IsoItem(
                row: row,
                col: col,
                child: GestureDetector(
                  onTap: () {
                    print('تم النقر على مجسم: ${data['name']}');
                  },
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: _getCategoryColor(
                        data['category'],
                      ).withOpacity(0.8),
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Icon(
                      _getIconForCategory(data['category']),
                      size: 24,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            );
          }
        }

        // تمرير العناصر إلى الـ Widget الأب
        WidgetsBinding.instance.addPostFrameCallback((_) {
          onItemsLoaded(items);
        });

        // ✅ لا نعرض أي شيء مرئي
        return const SizedBox.shrink();
      },
    );
  }

  Color _getCategoryColor(String? category) {
    switch (category) {
      case 'transport':
        return Colors.blue;
      case 'recycling':
        return Colors.green;
      case 'tree':
        return Colors.teal;
      default:
        return appColors.primary;
    }
  }

  IconData _getIconForCategory(String? category) {
    switch (category) {
      case 'transport':
        return Icons.directions_bus;
      case 'recycling':
        return Icons.recycling;
      case 'tree':
        return Icons.eco;
      default:
        return Icons.emoji_events;
    }
  }
}

class IsoItem {
  final int row;
  final int col;
  final Widget child;

  const IsoItem({required this.row, required this.col, required this.child});
}
