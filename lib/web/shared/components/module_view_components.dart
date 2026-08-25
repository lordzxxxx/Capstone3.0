import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mycapstone_project/web/shared/theme/app_theme.dart';
import 'package:mycapstone_project/web/shared/utils/browser_history.dart';

enum HealthModuleView { insights, records }

HealthModuleView parseHealthModuleView(String? value) {
  return value?.toLowerCase() == HealthModuleView.records.name
      ? HealthModuleView.records
      : HealthModuleView.insights;
}

HealthModuleView healthModuleViewFromUrl() {
  if (!kIsWeb) return HealthModuleView.insights;
  return parseHealthModuleView(Uri.base.queryParameters['view']);
}

void persistHealthModuleView(String route, HealthModuleView view) {
  if (!kIsWeb) return;
  final current = Uri.base;
  final query = Map<String, String>.from(current.queryParameters)
    ..['view'] = view.name;
  final next = current.replace(path: route, queryParameters: query);
  replaceBrowserHistory(next.toString());
}

class HealthModuleViewHeader extends StatelessWidget {
  const HealthModuleViewHeader({
    super.key,
    required this.title,
    required this.description,
    required this.activeView,
    required this.onViewChanged,
    this.primaryColor = AppColors.primary,
    this.foregroundColor = AppColors.textPrimary,
    this.mutedColor = AppColors.textSecondary,
    this.actions = const [],
    this.insightsLabel = 'Insights',
    this.recordsLabel = 'Records',
  });

  final String title;
  final String description;
  final HealthModuleView activeView;
  final ValueChanged<HealthModuleView> onViewChanged;
  final Color primaryColor;
  final Color foregroundColor;
  final Color mutedColor;
  final List<Widget> actions;
  final String insightsLabel;
  final String recordsLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      header: true,
      label: '$title module navigation',
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
          boxShadow: const [],
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 760;
            final heading = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: foregroundColor,
                    fontFamily: AppTheme.displayFontFamily,
                    fontSize: compact ? 22 : 27,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  description,
                  style: TextStyle(color: mutedColor, height: 1.45),
                ),
              ],
            );
            final controls = Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                HealthModuleViewTabs(
                  activeView: activeView,
                  onChanged: onViewChanged,
                  primaryColor: primaryColor,
                  insightsLabel: insightsLabel,
                  recordsLabel: recordsLabel,
                ),
                ...actions,
              ],
            );
            if (compact) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [heading, const SizedBox(height: 18), controls],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(child: heading),
                const SizedBox(width: 24),
                controls,
              ],
            );
          },
        ),
      ),
    );
  }
}

class HealthModuleViewTabs extends StatelessWidget {
  const HealthModuleViewTabs({
    super.key,
    required this.activeView,
    required this.onChanged,
    this.primaryColor = AppColors.primary,
    this.insightsLabel = 'Insights',
    this.recordsLabel = 'Records',
  });

  final HealthModuleView activeView;
  final ValueChanged<HealthModuleView> onChanged;
  final Color primaryColor;
  final String insightsLabel;
  final String recordsLabel;

  @override
  Widget build(BuildContext context) {
    return FocusTraversalGroup(
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.xs),
        decoration: BoxDecoration(
          color: AppColors.surfaceSubtle,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: HealthModuleView.values.map((view) {
            final selected = view == activeView;
            final label = view == HealthModuleView.insights
                ? insightsLabel
                : recordsLabel;
            return Semantics(
              button: true,
              selected: selected,
              label: '$label view',
              child: Tooltip(
                message: 'Show $label',
                child: TextButton.icon(
                  key: ValueKey('module-view-${view.name}'),
                  onPressed: () => onChanged(view),
                  icon: Icon(
                    view == HealthModuleView.insights
                        ? Icons.insights_rounded
                        : Icons.table_rows_rounded,
                    size: 18,
                  ),
                  label: Text(label),
                  style: TextButton.styleFrom(
                    foregroundColor: selected
                        ? Colors.white
                        : AppColors.textSecondary,
                    backgroundColor: selected
                        ? primaryColor
                        : Colors.transparent,
                    minimumSize: const Size(48, 44),
                    padding: const EdgeInsets.symmetric(horizontal: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    textStyle: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class ModuleEmptyState extends StatelessWidget {
  const ModuleEmptyState({
    super.key,
    required this.title,
    required this.message,
    this.icon = Icons.inbox_outlined,
    this.action,
  });

  final String title;
  final String message;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 20),
          child: Column(
            children: [
              Icon(icon, size: 52, color: const Color(0xFF7A91A6)),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: AppTheme.displayFontFamily,
                  color: AppColors.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  height: 1.5,
                ),
              ),
              if (action != null) ...[const SizedBox(height: 18), action!],
            ],
          ),
        ),
      ),
    );
  }
}
