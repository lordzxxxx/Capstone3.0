import 'package:flutter/material.dart';
import 'package:mycapstone_project/web/shared/components/app_metric_card.dart';

class PrenatalDashboardStats extends StatelessWidget {
  final int totalPatients;
  final int highRiskCount;
  final int completedCount;
  final int followUpCount;

  const PrenatalDashboardStats({
    super.key,
    required this.totalPatients,
    required this.highRiskCount,
    required this.completedCount,
    required this.followUpCount,
  });

  @override
  Widget build(BuildContext context) {
    final cards = <Widget>[
      AppMetricCard(
        label: 'Total Patients',
        value: '$totalPatients',
        icon: Icons.groups_outlined,
        supportingText: 'Active cases',
      ),
      AppMetricCard(
        label: 'High Risk',
        value: '$highRiskCount',
        icon: Icons.warning_amber_outlined,
        supportingText: 'Requires monitoring',
      ),
      AppMetricCard(
        label: 'Completed',
        value: '$completedCount',
        icon: Icons.check_circle_outline,
        supportingText: 'Completed cases',
      ),
      AppMetricCard(
        label: 'Follow Up',
        value: '$followUpCount',
        icon: Icons.event_note_outlined,
        supportingText: 'Pending review',
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1180
            ? 4
            : constraints.maxWidth >= 700
            ? 2
            : 1;
        final spacing = 16.0;
        final width = columns == 1
            ? constraints.maxWidth
            : (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: cards
              .map((card) => SizedBox(width: width, child: card))
              .toList(growable: false),
        );
      },
    );
  }
}
