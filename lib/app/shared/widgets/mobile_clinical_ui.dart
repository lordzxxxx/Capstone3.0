import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:mycapstone_project/app/theme/app_theme.dart';

/// Shared, touch-first visual primitives for the native clinical workflows.
///
/// Keep visual hierarchy here instead of duplicating oversized hero cards and
/// ad-hoc loading spinners in each module. The widgets deliberately use the
/// same 8dp rhythm, semantic colours and compact type scale as the app theme.
class MobilePageInsets extends StatelessWidget {
  const MobilePageInsets({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final horizontal = width < 360
        ? 16.0
        : width < 600
        ? 20.0
        : 28.0;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: horizontal),
      child: child,
    );
  }
}

class ClinicalSectionHeader extends StatelessWidget {
  const ClinicalSectionHeader({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppDesign.blueSoft,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppDesign.border),
          ),
          child: Icon(icon, color: AppDesign.navy, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 3),
              Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 8), trailing!],
      ],
    );
  }
}

/// The restrained material layer used across the mobile application.
///
/// This is intentionally not decorative glassmorphism: the blur is clipped,
/// the foreground remains an opaque-enough clinical surface, and the border
/// preserves contrast over the ambient page background.
class ClinicalGlassSurface extends StatelessWidget {
  const ClinicalGlassSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 20,
    this.tint,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final radiusValue = BorderRadius.circular(radius);
    return ClipRRect(
      borderRadius: radiusValue,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: (tint ?? AppDesign.surface).withValues(alpha: .82),
            borderRadius: radiusValue,
            border: Border.all(color: Colors.white.withValues(alpha: .72)),
            boxShadow: [
              BoxShadow(
                color: AppDesign.navy.withValues(alpha: .10),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Provides subtle ambient colour beneath glass surfaces without relying on
/// gradients as content or reducing the contrast of clinical text.
class ClinicalPageBackground extends StatelessWidget {
  const ClinicalPageBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: AppDesign.page),
        Positioned(
          top: -130,
          right: -95,
          child: _AmbientOrb(color: AppDesign.blue.withValues(alpha: .15)),
        ),
        Positioned(
          top: 260,
          left: -145,
          child: _AmbientOrb(color: AppDesign.teal.withValues(alpha: .08)),
        ),
        child,
      ],
    );
  }
}

class _AmbientOrb extends StatelessWidget {
  const _AmbientOrb({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: 38, sigmaY: 38),
        child: Container(
          width: 260,
          height: 260,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
      ),
    );
  }
}

class ClinicalInsightHero extends StatelessWidget {
  const ClinicalInsightHero({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return ClinicalGlassSurface(
      tint: AppDesign.blueSoft,
      padding: const EdgeInsets.all(18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppDesign.navy,
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(icon, color: Colors.white, size: 23),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 4),
                Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
        ],
      ),
    );
  }
}

/// A deterministic skeleton for record, dashboard and analytics loading.
/// It reserves layout before data arrives without a distracting shimmer loop.
class ClinicalLoadingSkeleton extends StatelessWidget {
  const ClinicalLoadingSkeleton({
    super.key,
    this.lines = 3,
    this.height = 116,
    this.margin = const EdgeInsets.only(bottom: 12),
  });

  final int lines;
  final double height;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Loading clinical data',
      child: Container(
        height: height,
        margin: margin,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppDesign.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppDesign.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: List<Widget>.generate(lines, (index) {
            final widthFactor = index == lines - 1
                ? .46
                : index == 0
                ? .68
                : .88;
            return Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: widthFactor,
                  child: Container(
                    height: 11,
                    decoration: BoxDecoration(
                      color: AppDesign.neutralBackground,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}
