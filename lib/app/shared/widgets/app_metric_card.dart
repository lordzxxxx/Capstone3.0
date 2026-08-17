import 'package:flutter/material.dart';
import 'package:mycapstone_project/app/theme/app_theme.dart';

/// Shared mobile summary card used by dashboard and analytics surfaces.
///
/// The card uses the product blue for metric emphasis. Green, orange, and red
/// remain reserved for real status or alert states instead of decorating every
/// metric with a different accent.
class AppMetricCard extends StatelessWidget {
  const AppMetricCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.supportingText,
    this.onTap,
    this.dense = false,
  });

  final String label;
  final String value;
  final IconData icon;
  final String? supportingText;
  final VoidCallback? onTap;

  /// Tighter padding/sizing for grids of cards packed several to a row.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final content = Container(
      constraints: BoxConstraints(minHeight: dense ? 88 : 124),
      padding: EdgeInsets.all(dense ? 10 : 14),
      decoration: BoxDecoration(
        color: AppDesign.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppDesign.border),
        boxShadow: [
          BoxShadow(
            color: AppDesign.navy.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: dense ? 30 : 38,
            height: dense ? 30 : 38,
            decoration: BoxDecoration(
              color: AppDesign.blueSoft,
              borderRadius: BorderRadius.circular(dense ? 9 : 12),
              border: Border.all(color: AppDesign.border),
            ),
            child: Icon(icon, color: AppDesign.blue, size: dense ? 16 : 20),
          ),
          SizedBox(width: dense ? 8 : 12),
          // Loose fit keeps this card compatible with horizontal metric
          // scrollers while still filling the available width in normal
          // bounded layouts.
          Flexible(
            fit: FlexFit.loose,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppDesign.ink,
                    fontSize: dense ? 11.5 : 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: dense ? 2 : 4),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppDesign.blue,
                    fontSize: dense ? 19 : 23,
                    fontWeight: FontWeight.w800,
                    height: 1.05,
                  ),
                ),
                if (supportingText != null &&
                    supportingText!.trim().isNotEmpty) ...[
                  SizedBox(height: dense ? 2 : 3),
                  Text(
                    supportingText!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppDesign.muted,
                      fontSize: dense ? 10 : 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );

    if (onTap == null) return content;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: content,
      ),
    );
  }
}
