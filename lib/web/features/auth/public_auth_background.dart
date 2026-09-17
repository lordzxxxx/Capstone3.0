import 'package:flutter/material.dart';
import 'package:mycapstone_project/web/shared/theme/app_theme.dart';

/// The single background asset used by unauthenticated web surfaces.
const String publicAuthBackgroundAsset = 'assets/newbg.png';

enum PublicAuthBackdropTreatment { landing, auth, light }

/// Renders the public/auth backdrop without allowing the image to participate
/// in the page layout. This keeps long forms scrollable and prevents browser
/// resizing from shifting the background composition.
class PublicAuthBackdrop extends StatelessWidget {
  const PublicAuthBackdrop({
    super.key,
    required this.child,
    this.treatment = PublicAuthBackdropTreatment.auth,
    this.scaleAnimation,
    this.alignment = Alignment.center,
  });

  final Widget child;
  final PublicAuthBackdropTreatment treatment;
  final Animation<double>? scaleAnimation;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    Widget image = Image.asset(
      publicAuthBackgroundAsset,
      fit: BoxFit.cover,
      alignment: alignment,
      filterQuality: FilterQuality.medium,
      excludeFromSemantics: true,
      errorBuilder: (context, error, stackTrace) =>
          const ColoredBox(color: AppColors.backgroundDark),
    );
    if (scaleAnimation != null) {
      image = ScaleTransition(scale: scaleAnimation!, child: image);
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(child: image),
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(decoration: _scrimDecoration(treatment)),
          ),
        ),
        child,
      ],
    );
  }

  static BoxDecoration _scrimDecoration(PublicAuthBackdropTreatment treatment) {
    return switch (treatment) {
      PublicAuthBackdropTreatment.landing => BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.backgroundDark.withValues(alpha: 0.12),
            AppColors.secondary.withValues(alpha: 0.08),
            AppColors.backgroundDark.withValues(alpha: 0.24),
          ],
        ),
      ),
      PublicAuthBackdropTreatment.auth => BoxDecoration(
        color: AppColors.backgroundDark.withValues(alpha: 0.34),
      ),
      PublicAuthBackdropTreatment.light => BoxDecoration(
        color: AppColors.surfaceLight.withValues(alpha: 0.78),
      ),
    };
  }
}

/// Decorative image layer for public sections that already provide their own
/// light wash and content-specific opacity.
class PublicBackgroundImage extends StatelessWidget {
  const PublicBackgroundImage({
    super.key,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
  });

  final BoxFit fit;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      publicAuthBackgroundAsset,
      fit: fit,
      alignment: alignment,
      filterQuality: FilterQuality.low,
      excludeFromSemantics: true,
      errorBuilder: (context, error, stackTrace) =>
          const ColoredBox(color: AppColors.backgroundLight),
    );
  }
}
