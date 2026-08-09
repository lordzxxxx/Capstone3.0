import 'package:flutter/material.dart';
import 'prenatal_constants.dart';

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
    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            title: 'Total Patients',
            value: '$totalPatients',
            icon: Icons.group_outlined,
            color: primaryAqua,
            subtitle: 'Active cases',
          ),
        ),
        const SizedBox(width: 20),
        Expanded(
          child: _buildStatCard(
            title: 'High Risk',
            value: '$highRiskCount',
            icon: Icons.warning_amber_rounded,
            color: Colors.orange,
            subtitle: 'Requiring monitoring',
          ),
        ),
        const SizedBox(width: 20),
        Expanded(
          child: _buildStatCard(
            title: 'Completed',
            value: '$completedCount',
            icon: Icons.check_circle_outline,
            color: Colors.green,
            subtitle: 'Successful cases',
          ),
        ),
        const SizedBox(width: 20),
        Expanded(
          child: _buildStatCard(
            title: 'Follow Up',
            value: '$followUpCount',
            icon: Icons.event_note_outlined,
            color: secondaryIceBlue,
            subtitle: 'Pending review',
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    required String subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0x140B1F3A),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              /// Icon container
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: color.withValues(alpha: 0.4),
                    width: 1,
                  ),
                ),
                child: Icon(icon, color: color, size: 28),
              ),

              /// Active badge
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Active',
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          /// Value
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 36,
              fontWeight: FontWeight.w800,
              letterSpacing: -1,
            ),
          ),
          const SizedBox(height: 8),

          /// Title
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFF0B1F3A),
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),

          /// Subtitle
          Text(
            subtitle,
            style: TextStyle(
              color: const Color(0xFF4B6075),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
