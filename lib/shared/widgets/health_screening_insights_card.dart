import 'package:flutter/material.dart';
import 'package:mycapstone_project/app/core/services/health_screening_engine.dart';
import 'package:mycapstone_project/web/shared/theme/app_theme.dart';

/// A compact, role-neutral overview built only from persisted screening
/// results. The caller controls the record scope through its existing query.
class HealthScreeningInsightsCard extends StatelessWidget {
  const HealthScreeningInsightsCard({
    required this.records,
    required this.scopeLabel,
    this.title = 'AI screening insights',
    this.onReviewReferral,
    super.key,
  });

  final Iterable<Map<String, dynamic>> records;
  final String scopeLabel;
  final String title;
  final VoidCallback? onReviewReferral;

  @override
  Widget build(BuildContext context) {
    final summary = HealthScreeningInsightSummary.fromRecords(records);
    final needsReview =
        summary.needsAttention +
        summary.referralReview +
        summary.urgentFindings;
    final topFlag = summary.flaggedMeasurements.entries.toList()
      ..sort((left, right) => right.value.compareTo(left.value));

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.surfaceSubtle,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.insights_outlined,
                  color: AppColors.primary,
                  semanticLabel: 'AI screening insights',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      scopeLabel,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 760
                  ? 5
                  : constraints.maxWidth >= 460
                  ? 3
                  : 2;
              final gap = 8.0;
              final width =
                  (constraints.maxWidth - (gap * (columns - 1))) / columns;
              final metrics = [
                _InsightMetric(
                  label: 'Screenings',
                  value: summary.evaluatedScreenings,
                  color: AppColors.primary,
                ),
                _InsightMetric(
                  label: 'Needs review',
                  value: needsReview,
                  color: needsReview > 0
                      ? AppColors.warning
                      : AppColors.success,
                ),
                _InsightMetric(
                  label: 'Urgent',
                  value: summary.urgentFindings,
                  color: summary.urgentFindings > 0
                      ? AppColors.error
                      : AppColors.success,
                ),
                _InsightMetric(
                  label: 'Referral suggestions',
                  value: summary.referralRecommendations,
                  color: summary.referralRecommendations > 0
                      ? AppColors.referral
                      : AppColors.success,
                ),
                _InsightMetric(
                  label: 'Data checks',
                  value: summary.dataQualityIssues,
                  color: summary.dataQualityIssues > 0
                      ? AppColors.warning
                      : AppColors.success,
                ),
              ];
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: metrics
                    .map(
                      (metric) => SizedBox(
                        width: width,
                        child: _InsightMetricTile(metric: metric),
                      ),
                    )
                    .toList(growable: false),
              );
            },
          ),
          const SizedBox(height: 14),
          if (!summary.hasData)
            const Text(
              'No persisted screening results are available in this scope yet. New verified check-ups will appear here.',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12.5,
                height: 1.4,
              ),
            )
          else ...[
            Text(
              topFlag.isEmpty
                  ? 'No screening finding has been recorded in this scope.'
                  : 'Most common screening finding: ${topFlag.first.key} (${topFlag.first.value}).',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12.5,
                height: 1.4,
              ),
            ),
            if (summary.needsProfessionalReview > 0) ...[
              const SizedBox(height: 4),
              Text(
                '${summary.needsProfessionalReview} result${summary.needsProfessionalReview == 1 ? '' : 's'} need professional-context review before action.',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12.5,
                  height: 1.4,
                ),
              ),
            ],
          ],
          if (onReviewReferral != null &&
              summary.referralRecommendations > 0) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: onReviewReferral,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.referralStrong,
                  side: const BorderSide(color: AppColors.referral),
                  minimumSize: const Size(0, 44),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.assignment_return_outlined, size: 18),
                    SizedBox(width: 8),
                    Expanded(child: Text('Review referral suggestions')),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 10),
          const Text(
            'Screening findings are not disease prevalence and do not replace professional judgment. Actual referrals remain separate from AI suggestions.',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11.5,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _InsightMetric {
  const _InsightMetric({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final int value;
  final Color color;
}

class _InsightMetricTile extends StatelessWidget {
  const _InsightMetricTile({required this.metric});

  final _InsightMetric metric;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 72),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.canvasLight,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            metric.value.toString(),
            style: TextStyle(
              color: metric.color,
              fontSize: 21,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            metric.label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11,
              height: 1.2,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
