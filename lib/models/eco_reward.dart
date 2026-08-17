// lib/widgets/ecoland_grid.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/app_colors.dart';

class EcoLandGrid extends StatelessWidget {
  final String userId;

  const EcoLandGrid({super.key, required this.userId});

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
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: appColors.primary),
          );
        }

        final rewards = snapshot.data?.docs ?? [];

        if (rewards.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.eco_outlined, size: 50, color: Colors.grey[400]),
                const SizedBox(height: 12),
                Text(
                  'أرض EcoLand فارغة 🌱',
                  style: GoogleFonts.ibmPlexSansArabic(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'أنجز مهام الاستدامة لملء أرضك!',
                  style: GoogleFonts.ibmPlexSansArabic(
                    fontSize: 12,
                    color: Colors.grey[500],
                  ),
                ),
              ],
            ),
          );
        }

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            childAspectRatio: 0.9,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
          ),
          itemCount: rewards.length,
          itemBuilder: (context, index) {
            final data = rewards[index].data() as Map<String, dynamic>;
            return _buildEcoCard(data);
          },
        );
      },
    );
  }

  Widget _buildEcoCard(Map<String, dynamic> reward) {
    // ✅ أيقونة حسب rewardId
    IconData getIcon(String rewardId) {
      switch (rewardId) {
        case 'metro':
          return Icons.subway;
        case 'recycle':
          return Icons.recycling;
        case 'bus':
          return Icons.directions_bus;
        case 'bike':
          return Icons.directions_bike;
        case 'tree':
          return Icons.eco;
        default:
          return Icons.emoji_events;
      }
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              color: _getCategoryColor(reward['category']).withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              getIcon(reward['rewardId']),
              size: 40,
              color: _getCategoryColor(reward['category']),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            reward['name'] ?? 'مكافأة',
            style: GoogleFonts.ibmPlexSansArabic(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: appColors.dark,
            ),
          ),
        ],
      ),
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
}
