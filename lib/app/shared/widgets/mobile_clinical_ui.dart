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
