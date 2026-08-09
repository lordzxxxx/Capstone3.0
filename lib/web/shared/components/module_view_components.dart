import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:universal_html/html.dart' as html;

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
  html.window.history.replaceState(null, '', next.toString());
}

class HealthModuleViewHeader extends StatelessWidget {
  const HealthModuleViewHeader({
    super.key,
    required this.title,
    required this.description,
    required this.activeView,
    required this.onViewChanged,
    this.primaryColor = const Color(0xFF2F80ED),
    this.foregroundColor = const Color(0xFF0B1F3A),
    this.mutedColor = const Color(0xFF4B6075),
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
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFD9E5F2)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x120B1F3A),
              blurRadius: 18,
              offset: Offset(0, 8),
            ),
          ],
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
    this.primaryColor = const Color(0xFF2F80ED),
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
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: const Color(0xFFEDF3FA),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFD9E5F2)),
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
                        : const Color(0xFF4B6075),
                    backgroundColor: selected
                        ? primaryColor
                        : Colors.transparent,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 15,
                      vertical: 12,
                    ),
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
                  color: const Color(0xFF0B1F3A),
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF4B6075), height: 1.5),
              ),
              if (action != null) ...[const SizedBox(height: 18), action!],
            ],
          ),
        ),
      ),
    );
  }
}
