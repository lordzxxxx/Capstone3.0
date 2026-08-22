import 'package:flutter/material.dart';
import 'package:mycapstone_project/web/shared/components/app_metric_card.dart';
import 'package:mycapstone_project/web/shared/theme/app_theme.dart';

abstract final class ChoColors {
  static const background = AppColors.backgroundLight;
  static const canvas = AppColors.canvasLight;
  static const surface = AppColors.surfaceLight;
  static const surfaceAlt = AppColors.surfaceSubtle;
  static const border = AppColors.border;
  static const borderStrong = AppColors.borderStrong;
  static const aqua = AppColors.primary;
  static const ice = AppColors.secondary;
  static const text = AppColors.textPrimary;
  static const muted = AppColors.textSecondary;
  static const navBackground = AppColors.backgroundDark;
  static const navSurface = AppColors.surfaceDark;
  static const navText = AppColors.textOnDark;
  static const navMuted = Color(0xFFE3EDF8);
  static const navBorder = Color(0xFF1C3D66);
}

class ChoPageHeader extends StatelessWidget {
  const ChoPageHeader({
    super.key,
    required this.title,
    required this.description,
    required this.icon,
    this.breadcrumb = 'CHO Portal',
    this.actions = const [],
  });

  final String title;
  final String description;
  final IconData icon;
  final String breadcrumb;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      header: true,
      label: '$title page',
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: ChoColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: ChoColors.border),
          boxShadow: const [],
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 760;
            final heading = Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$breadcrumb / $title',
                        style: const TextStyle(
                          color: ChoColors.aqua,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        title,
                        style: TextStyle(
                          fontFamily: AppTheme.displayFontFamily,
                          color: ChoColors.text,
                          fontSize: compact ? 22 : 26,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        description,
                        style: const TextStyle(
                          color: ChoColors.muted,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
            final actionBar = Wrap(
              spacing: 10,
              runSpacing: 10,
              children: actions,
            );
            if (compact || actions.isEmpty) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  heading,
                  if (actions.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    actionBar,
                  ],
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: heading),
                const SizedBox(width: 16),
                actionBar,
              ],
            );
          },
        ),
      ),
    );
  }
}

class ChoViewTabs extends StatelessWidget {
  const ChoViewTabs({
    super.key,
    required this.tabs,
    required this.selectedIndex,
    required this.onChanged,
  });

  final List<String> tabs;
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: 'Page views',
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: ChoColors.surfaceAlt,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: ChoColors.border),
          ),
          child: Row(
            children: List.generate(tabs.length, (index) {
              final selected = index == selectedIndex;
              return Semantics(
                button: true,
                selected: selected,
                label: '${tabs[index]} view',
                child: TextButton(
                  onPressed: () => onChanged(index),
                  style: TextButton.styleFrom(
                    foregroundColor: selected ? Colors.white : ChoColors.muted,
                    backgroundColor: selected
                        ? ChoColors.aqua
                        : Colors.transparent,
                    minimumSize: const Size(48, 44),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    textStyle: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  child: Text(tabs[index]),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

class ChoKpiCard extends StatelessWidget {
  const ChoKpiCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.supportingText = '',
    this.color = ChoColors.aqua,
    this.onTap,
  });

  final String label;
  final String value;
  final String supportingText;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: onTap != null,
      label: '$label: $value. $supportingText',
      child: AppMetricCard(
        label: label,
        value: value,
        icon: icon,
        supportingText: supportingText,
        onTap: onTap,
        compact: true,
      ),
    );
  }
}

class ChoKpiGrid extends StatelessWidget {
  const ChoKpiGrid({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1180
            ? 4
            : constraints.maxWidth >= 700
            ? 2
            : 1;
        final width = (constraints.maxWidth - (12 * (columns - 1))) / columns;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: children
              .map((child) => SizedBox(width: width, child: child))
              .toList(growable: false),
        );
      },
    );
  }
}

class ChoStatusBadge extends StatelessWidget {
  const ChoStatusBadge(this.status, {super.key});

  final String status;

  @override
  Widget build(BuildContext context) {
    final displayStatus = status.trim().isEmpty ? 'Unspecified' : status.trim();
    final normalized = status.toLowerCase();
    final Color color;
    final IconData icon;
    if (normalized.contains('approv') ||
        normalized.contains('complete') ||
        normalized.contains('active')) {
      color = Colors.green.shade700;
      icon = Icons.check_circle_outline;
    } else if (normalized.contains('reject') ||
        normalized.contains('critical') ||
        normalized.contains('urgent')) {
      color = Colors.red.shade700;
      icon = Icons.error_outline;
    } else if (normalized.contains('pending') ||
        normalized.contains('return') ||
        normalized.contains('high')) {
      color = Colors.orange.shade800;
      icon = Icons.schedule_outlined;
    } else {
      color = Colors.blue.shade700;
      icon = Icons.info_outline;
    }
    return Semantics(
      label: 'Status: $displayStatus',
      child: Tooltip(
        message: displayStatus,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: color.withValues(alpha: 0.4)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 14),
              const SizedBox(width: 5),
              Flexible(
                fit: FlexFit.loose,
                child: Text(
                  displayStatus,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Manrope',
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ChoEmptyState extends StatelessWidget {
  const ChoEmptyState({
    super.key,
    required this.title,
    required this.message,
    this.icon = Icons.inbox_outlined,
  });

  final String title;
  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final displayMessage = message.contains('INTERNAL ASSERTION FAILED')
        ? 'The Firestore web connection entered an invalid cached state. Reload the page and try again.'
        : message.length > 320
        ? '${message.substring(0, 320)}…'
        : message;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
      child: Center(
        child: Column(
          children: [
            Icon(icon, color: ChoColors.muted, size: 40),
            const SizedBox(height: 14),
            Text(
              title,
              style: const TextStyle(
                fontFamily: 'Manrope',
                color: ChoColors.text,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              displayMessage,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Manrope',
                color: ChoColors.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ChoErrorState extends StatelessWidget {
  const ChoErrorState({
    super.key,
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 20),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_outlined,
              color: Colors.orange.shade800,
              size: 48,
            ),
            const SizedBox(height: 14),
            const Text(
              'Data could not be loaded',
              style: TextStyle(
                fontFamily: 'Manrope',
                color: ChoColors.text,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Manrope',
                color: ChoColors.muted,
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

class ChoLoadingSkeleton extends StatelessWidget {
  const ChoLoadingSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(48),
      child: Center(child: CircularProgressIndicator(color: ChoColors.aqua)),
    );
  }
}
