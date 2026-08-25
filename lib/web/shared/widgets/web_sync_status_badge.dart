import 'package:flutter/material.dart';
import 'package:mycapstone_project/web/shared/services/web_record_sync.dart';
import 'package:mycapstone_project/web/shared/theme/app_theme.dart';

class WebSyncStatusBadge extends StatelessWidget {
  const WebSyncStatusBadge({
    super.key,
    required this.record,
    this.onRetry,
    this.compact = true,
  });

  final Map<String, dynamic> record;
  final VoidCallback? onRetry;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final status = WebRecordSyncStatus.fromRecord(record);
    final visual = _visualFor(status.state);
    final content = Container(
      constraints: const BoxConstraints(minHeight: 32),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: visual.color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: visual.color.withValues(alpha: 0.38)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(visual.icon, size: 16, color: visual.color),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              status.label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: visual.color,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          if (onRetry != null && status.canRetry) ...[
            const SizedBox(width: 4),
            IconButton(
              tooltip: 'Retry synchronization',
              onPressed: onRetry,
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              color: visual.color,
            ),
          ],
        ],
      ),
    );

    return Semantics(
      container: true,
      liveRegion: status.state != WebRecordSyncState.synchronized,
      label: '${status.label}. ${status.instruction}',
      child: Tooltip(
        message: status.error?.isNotEmpty == true
            ? '${status.instruction}\n${status.error}'
            : status.instruction,
        child: compact
            ? content
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  content,
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    status.instruction,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _SyncVisual {
  const _SyncVisual(this.icon, this.color);

  final IconData icon;
  final Color color;
}

_SyncVisual _visualFor(WebRecordSyncState state) {
  return switch (state) {
    WebRecordSyncState.savedLocally => const _SyncVisual(
      Icons.save_outlined,
      AppColors.primary,
    ),
    WebRecordSyncState.pending => const _SyncVisual(
      Icons.schedule_rounded,
      AppColors.warning,
    ),
    WebRecordSyncState.syncing => const _SyncVisual(
      Icons.sync_rounded,
      AppColors.primary,
    ),
    WebRecordSyncState.synchronized => const _SyncVisual(
      Icons.cloud_done_rounded,
      AppColors.success,
    ),
    WebRecordSyncState.failed => const _SyncVisual(
      Icons.cloud_off_rounded,
      AppColors.error,
    ),
    WebRecordSyncState.conflict => const _SyncVisual(
      Icons.compare_arrows_rounded,
      AppColors.error,
    ),
  };
}
