import 'package:flutter/material.dart';

class BarangayLogoImage extends StatelessWidget {
  final String? imageUrl;
  final String? assetPath;
  final double size;
  final BorderRadius borderRadius;

  const BarangayLogoImage({
    super.key,
    this.imageUrl,
    this.assetPath,
    required this.size,
    required this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final resolvedAssetPath = assetPath?.trim() ?? '';
    final resolvedImageUrl = imageUrl?.trim() ?? '';

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        color: const Color(0xFF061920),
      ),
      clipBehavior: Clip.antiAlias,
      child: resolvedAssetPath.isNotEmpty
          ? Image.asset(
              resolvedAssetPath,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return _fallbackPlaceholder();
              },
            )
          : resolvedImageUrl.isNotEmpty
          ? Image.network(
              resolvedImageUrl,
              fit: BoxFit.cover,
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) return child;
                return const Center(
                  child: CircularProgressIndicator(strokeWidth: 2),
                );
              },
              errorBuilder: (context, error, stackTrace) {
                return _fallbackPlaceholder();
              },
            )
          : _fallbackPlaceholder(),
    );
  }

  Widget _fallbackPlaceholder() {
    return Container(
      color: const Color(0xFF0A1F24),
      alignment: Alignment.center,
      child: const Icon(
        Icons.location_city,
        color: Color(0xFF00A8B5),
        size: 28,
      ),
    );
  }
}
