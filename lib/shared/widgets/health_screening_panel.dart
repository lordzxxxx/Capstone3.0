import 'package:flutter/material.dart';
import 'package:mycapstone_project/app/core/services/health_screening_engine.dart';
import 'package:mycapstone_project/web/shared/theme/app_theme.dart';

/// Compact presentation of a persisted screening result.
///
/// This widget intentionally presents findings and the BHW action boundary. It
/// does not describe a diagnosis and it never submits a referral itself.
class HealthScreeningPanel extends StatelessWidget {
  const HealthScreeningPanel({
    required this.record,
    this.onReferralRequested,
    this.compact = false,
    super.key,
  });

  final Map<String, dynamic> record;
  final VoidCallback? onReferralRequested;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final result = HealthScreeningEngine.resultFromRecord(record);
    if (result == null) return const SizedBox.shrink();

    final statusColor = _statusColor(result.status);
    final actionableFindings = result.findings
        .where((finding) => !finding.isInformational)
        .toList(growable: false);
    final canSuggestReferral =
        result.referralRecommendation.index >=
        HealthReferralRecommendation.considerReferral.index;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 14 : 18),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: statusColor.withValues(alpha: 0.35)),
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
                  color: statusColor.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  _statusIcon(result.status),
                  color: statusColor,
                  size: 22,
                  semanticLabel: 'Screening status',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'AI-assisted screening',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: compact ? 15 : 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        _StatusChip(
                          label: result.status.label,
                          color: statusColor,
                        ),
                        _StatusChip(
                          label: 'Data: ${result.dataQuality.label}',
                          color:
                              result.dataQuality == HealthDataQuality.complete
                              ? AppColors.success
                              : AppColors.warning,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            result.suggestedAction,
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: compact ? 12.5 : 13.5,
              height: 1.45,
            ),
          ),
          if (actionableFindings.isNotEmpty) ...[
            const SizedBox(height: 14),
            _SectionLabel(
              icon: Icons.flag_outlined,
              label: 'Findings and explanations',
            ),
            const SizedBox(height: 8),
            ...actionableFindings.map(
              (finding) => _FindingRow(finding: finding),
            ),
          ],
          if (result.qualityIssues.isNotEmpty) ...[
            const SizedBox(height: 14),
            _SectionLabel(
              icon: Icons.fact_check_outlined,
              label: 'Data quality checks',
            ),
            const SizedBox(height: 8),
            ...result.qualityIssues.map(
              (issue) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  '${issue.field}: ${issue.message}',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12.5,
                    height: 1.4,
                  ),
                ),
              ),
            ),
          ],
          if (result.missingInformation.isNotEmpty) ...[
            const SizedBox(height: 10),
            _SectionLabel(
              icon: Icons.info_outline_rounded,
              label: 'Information to verify',
            ),
            const SizedBox(height: 6),
            ...result.missingInformation.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  item,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12.5,
                    height: 1.4,
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surfaceSubtle,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Referral support: ${result.referralRecommendation.label}',
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (result.referralReasons.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  ...result.referralReasons.map(
                    (reason) => Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Text(
                        '• $reason',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ),
                ],
                if (onReferralRequested != null && canSuggestReferral) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: onReferralRequested,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.referralStrong,
                        side: const BorderSide(color: AppColors.referral),
                        minimumSize: const Size(0, 44),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.assignment_return_outlined, size: 18),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text('Review existing referral workflow'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'This is decision support based on the recorded information. It does not diagnose, prescribe treatment, or replace authorized healthcare-professional judgment.',
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

  static Color _statusColor(HealthScreeningStatus status) {
    switch (status) {
      case HealthScreeningStatus.urgentAssessment:
        return AppColors.error;
      case HealthScreeningStatus.referralReview:
        return AppColors.referral;
      case HealthScreeningStatus.needsAttention:
        return AppColors.warning;
      case HealthScreeningStatus.needsProfessionalReview:
        return AppColors.secondary;
      case HealthScreeningStatus.withinExpectedRange:
        return AppColors.success;
    }
  }

  static IconData _statusIcon(HealthScreeningStatus status) {
    switch (status) {
      case HealthScreeningStatus.urgentAssessment:
        return Icons.emergency_outlined;
      case HealthScreeningStatus.referralReview:
        return Icons.assignment_return_outlined;
      case HealthScreeningStatus.needsAttention:
        return Icons.warning_amber_rounded;
      case HealthScreeningStatus.needsProfessionalReview:
        return Icons.person_search_outlined;
      case HealthScreeningStatus.withinExpectedRange:
        return Icons.verified_outlined;
    }
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: AppColors.primary, size: 17),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}

class _FindingRow extends StatelessWidget {
  const _FindingRow({required this.finding});

  final HealthMeasurementFinding finding;

  @override
  Widget build(BuildContext context) {
    final color = HealthScreeningPanel._statusColor(finding.status);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            finding.measurement,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            finding.status.label,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Recorded: ${finding.recordedValue}',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            'Reason: ${finding.reason}',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            'Suggested action: ${finding.suggestedAction}',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}
