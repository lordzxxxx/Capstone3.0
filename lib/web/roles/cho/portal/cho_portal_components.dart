import 'package:flutter/material.dart';

abstract final class ChoColors {
  static const background = Color(0xFFF5F7FA);
  static const surface = Colors.white;
  static const surfaceAlt = Color(0xFFEDF3FA);
  static const border = Color(0xFFD9E5F2);
  static const aqua = Color(0xFF2F80ED);
  static const ice = Color(0xFF163B66);
  static const text = Color(0xFF0B1F3A);
  static const muted = Color(0xFF4B6075);
  static const navBackground = Color(0xFF071A33);
  static const navSurface = Color(0xFF0D274D);
  static const navText = Color(0xFFF8FBFF);
  static const navMuted = Color(0xFFB8C9DB);
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
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: ChoColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: ChoColors.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 760;
            final heading = Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 5,
                  height: 58,
                  decoration: BoxDecoration(
                    color: ChoColors.aqua,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$breadcrumb / $title',
                        style: const TextStyle(
                          fontFamily: 'Manrope',
                          color: ChoColors.aqua,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        title,
                        style: TextStyle(
                          fontFamily: 'Manrope',
                          color: ChoColors.text,
                          fontSize: compact ? 23 : 28,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        description,
                        style: const TextStyle(
                          fontFamily: 'Manrope',
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
                    const SizedBox(height: 18),
                    actionBar,
                  ],
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: heading),
                const SizedBox(width: 20),
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
            borderRadius: BorderRadius.circular(14),
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 13,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    textStyle: const TextStyle(
                      fontFamily: 'Manrope',
                      fontWeight: FontWeight.w700,
                    ),
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
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          height: 132,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: ChoColors.navSurface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: ChoColors.navBorder),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(color: color.withValues(alpha: 0.35)),
                ),
                child: Icon(icon, color: Colors.white, size: 20),
              ),
              const Spacer(),
              Text(
                value,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  color: ChoColors.navText,
                  fontSize: 23,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                label,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  color: ChoColors.navMuted,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (supportingText.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  supportingText,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    color: ChoColors.navMuted,
                    fontSize: 11,
                  ),
                ),
              ],
            ],
          ),
        ),
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
        final width = (constraints.maxWidth - (14 * (columns - 1))) / columns;
        return Wrap(
          spacing: 14,
          runSpacing: 14,
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
      padding: const EdgeInsets.symmetric(vertical: 55, horizontal: 20),
      child: Center(
        child: Column(
          children: [
            Icon(icon, color: ChoColors.muted, size: 48),
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
