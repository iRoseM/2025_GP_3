import 'package:flutter/material.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';

class GlbThumbnail extends StatelessWidget {
  final String glbPath;
  final double width;
  final double height;
  final VoidCallback? onTap;

  const GlbThumbnail({
    super.key,
    required this.glbPath,
    this.width = 80,
    this.height = 80,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.2),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: ModelViewer(
            src: glbPath,
            alt: '3D Model',
            autoRotate: true,
            autoRotateDelay: 0,
            disableZoom: true,
            disableTap: true,
            cameraControls: false,
            backgroundColor: Colors.transparent,
            // style: const TextStyle(fontSize: 0), // إخفاء أي نص
          ),
        ),
      ),
    );
  }
}
