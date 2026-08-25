import 'package:flutter/material.dart';
import 'package:mycapstone_project/web/shared/theme/app_theme.dart';

enum DecisionSupportAudience { bhw, cho, doctor, administrator }

class DecisionSupportItem {
  const DecisionSupportItem({
    required this.label,
    required this.value,
    required this.icon,
    this.isPriority = false,
  });

  final String label;
  final String value;
  final IconData icon;
  final bool isPriority;
}

/// Role-specific decision support. It deliberately avoids probability or
/// confidence displays because those values are not medical certainty.
class RoleDecisionSupportPanel extends StatelessWidget {
  const RoleDecisionSupportPanel({
    super.key,
    required this.audience,
    required this.summary,
    required this.items,
  });

  final DecisionSupportAudience audience;
  final String summary;
  final List<DecisionSupportItem> items;

  String get _title => switch (audience) {
    DecisionSupportAudience.bhw => 'Patient decision support',
    DecisionSupportAudience.cho => 'CHO planning decision support',
    DecisionSupportAudience.doctor => 'Clinical review context',
    DecisionSupportAudience.administrator => 'AI governance status',
  };

  String get _roleExplanation => switch (audience) {
    DecisionSupportAudience.bhw =>
      'Use the recorded warning signs and next steps to support follow-up or referral.',
    DecisionSupportAudience.cho =>
      'Use aggregated patterns to prioritize barangays, validate records, and plan services.',
    DecisionSupportAudience.doctor =>
      'Review the submitted case context together with your own clinical assessment.',
    DecisionSupportAudience.administrator =>
      'Review model provenance, availability, and audit controls—not patient care decisions.',
  };

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: '$_title. $_roleExplanation',
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.22)),
          boxShadow: const <BoxShadow>[
            BoxShadow(
              color: Color(0x12071A33),
              blurRadius: 18,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.assistant_outlined,
                  color: AppColors.primary,
                  semanticLabel: 'Decision support',
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _title,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        _roleExplanation,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              summary,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700,
                height: 1.4,
              ),
            ),
            if (items.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: items
                    .map(
                      (item) => Container(
                        constraints: const BoxConstraints(minWidth: 190),
                        padding: const EdgeInsets.all(AppSpacing.md),
                        decoration: BoxDecoration(
                          color: item.isPriority
                              ? AppColors.error.withValues(alpha: 0.07)
                              : AppColors.surfaceSubtle,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: item.isPriority
                                ? AppColors.error.withValues(alpha: 0.28)
                                : AppColors.border,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              item.icon,
                              color: item.isPriority
                                  ? AppColors.error
                                  : AppColors.primary,
                              size: 20,
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Flexible(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.label,
                                    style: const TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 12,
                                    ),
                                  ),
                                  Text(
                                    item.value,
                                    style: const TextStyle(
                                      color: AppColors.textPrimary,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                    .toList(growable: false),
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            const Text(
              'Decision support only—not a confirmed diagnosis, prescription, or substitute for clinical review.',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                fontStyle: FontStyle.italic,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
