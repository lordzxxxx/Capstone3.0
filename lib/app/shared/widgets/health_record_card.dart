import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:mycapstone_project/app/theme/app_theme.dart';

@immutable
class RecordMetadata {
  const RecordMetadata({
    required this.label,
    required this.value,
    required this.icon,
    this.emphasize = false,
  });

  final String label;
  final String value;
  final IconData icon;
  final bool emphasize;
}

/// Shared visual foundation for every BHW record module. Modules supply their
/// own clinically relevant fields; this widget owns hierarchy, spacing,
/// selection, status semantics, and responsive behavior.
class HealthRecordCard extends StatelessWidget {
  const HealthRecordCard({
    super.key,
    required this.patientName,
    required this.accentColor,
    required this.metadata,
    this.location,
    this.avatarText,
    this.status,
    this.secondaryStatus,
    this.recordLabel,
    this.isSelected = false,
    this.showSelection = false,
    this.onSelectionChanged,
    this.onTap,
    this.onLongPress,
    this.onAction,
  });

  final String patientName;
  final String? location;
  final String? avatarText;
  final String? status;
  final String? secondaryStatus;
  final String? recordLabel;
  final Color accentColor;
  final List<RecordMetadata> metadata;
  final bool isSelected;
  final bool showSelection;
  final ValueChanged<bool>? onSelectionChanged;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 390;
    final cardPadding = compact ? 12.0 : 16.0;
    final initials =
        (avatarText?.trim().isNotEmpty == true
                ? avatarText!.trim()
                : _initials(patientName))
            .toUpperCase();

    return Semantics(
      button: onTap != null,
      selected: isSelected,
      label: '${recordLabel ?? 'Health record'} for $patientName',
      child: Card(
        margin: EdgeInsets.only(bottom: compact ? 10 : 12),
        elevation: isSelected ? 2 : 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: isSelected ? accentColor : AppDesign.border,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          borderRadius: BorderRadius.circular(16),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: EdgeInsets.all(cardPadding),
            decoration: BoxDecoration(
              color: isSelected
                  ? accentColor.withValues(alpha: 0.07)
                  : AppDesign.surface,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (showSelection) ...[
                      Checkbox(
                        value: isSelected,
                        onChanged: onSelectionChanged == null
                            ? null
                            : (value) => onSelectionChanged!(value ?? false),
                        visualDensity: VisualDensity.compact,
                      ),
                      const SizedBox(width: 4),
                    ],
                    _PatientAvatar(
                      initials: initials,
                      accentColor: accentColor,
                      size: compact ? 46 : 52,
                    ),
                    SizedBox(width: compact ? 9 : 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (recordLabel?.trim().isNotEmpty == true) ...[
                            Text(
                              recordLabel!.toUpperCase(),
                              style: TextStyle(
                                color: accentColor,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.7,
                              ),
                            ),
                            const SizedBox(height: 3),
                          ],
                          Text(
                            patientName.trim().isEmpty
                                ? 'Unknown patient'
                                : patientName,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppDesign.ink,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              height: 1.2,
                            ),
                          ),
                          if (location?.trim().isNotEmpty == true) ...[
                            const SizedBox(height: 5),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(
                                  Icons.location_on_outlined,
                                  color: AppDesign.subtle,
                                  size: 15,
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    location!,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: AppDesign.muted,
                                      fontSize: 12.5,
                                      height: 1.3,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (onAction != null)
                      IconButton(
                        tooltip: 'Record actions',
                        onPressed: onAction,
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(
                          Icons.more_vert_rounded,
                          color: AppDesign.muted,
                        ),
                      ),
                  ],
                ),
                if (status?.trim().isNotEmpty == true ||
                    secondaryStatus?.trim().isNotEmpty == true) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (status?.trim().isNotEmpty == true)
                        RecordStatusBadge(label: status!),
                      if (secondaryStatus?.trim().isNotEmpty == true)
                        RecordStatusBadge(label: secondaryStatus!),
                    ],
                  ),
                ],
                if (metadata.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  const Divider(),
                  const SizedBox(height: 13),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final itemWidth = constraints.maxWidth < 330
                          ? constraints.maxWidth
                          : (constraints.maxWidth - 12) / 2;
                      return Wrap(
                        spacing: 12,
                        runSpacing: 14,
                        children: metadata
                            .where((item) => item.value.trim().isNotEmpty)
                            .map(
                              (item) => SizedBox(
                                width: itemWidth,
                                child: _MetadataItem(
                                  item: item,
                                  accentColor: accentColor,
                                ),
                              ),
                            )
                            .toList(),
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _initials(String value) {
    final parts = value
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1);
    return '${parts.first.substring(0, 1)}${parts.last.substring(0, 1)}';
  }
}

class _PatientAvatar extends StatelessWidget {
  const _PatientAvatar({
    required this.initials,
    required this.accentColor,
    required this.size,
  });

  final String initials;
  final Color accentColor;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.12),
        shape: BoxShape.circle,
        border: Border.all(color: accentColor.withValues(alpha: 0.30)),
      ),
      child: Text(
        initials,
        style: TextStyle(
          color: accentColor,
          fontSize: 16,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _MetadataItem extends StatelessWidget {
  const _MetadataItem({required this.item, required this.accentColor});

  final RecordMetadata item;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: accentColor.withValues(alpha: 0.09),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(item.icon, color: accentColor, size: 16),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.label.toUpperCase(),
                style: const TextStyle(
                  color: AppDesign.subtle,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.45,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                item.value,
                maxLines: item.emphasize ? 3 : 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppDesign.ink,
                  fontSize: 12.5,
                  fontWeight: item.emphasize
                      ? FontWeight.w700
                      : FontWeight.w600,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class RecordStatusBadge extends StatelessWidget {
  const RecordStatusBadge({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = AppDesign.statusColors(label);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colors.foreground.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_statusIcon(label), size: 13, color: colors.foreground),
          const SizedBox(width: 5),
          Text(
            label.toUpperCase(),
            style: TextStyle(
              color: colors.foreground,
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.25,
            ),
          ),
        ],
      ),
    );
  }

  static IconData _statusIcon(String value) {
    final normalized = value.toLowerCase();
    final colors = AppDesign.statusColors(value);
    if (colors.foreground == AppDesign.danger) {
      return Icons.error_outline_rounded;
    }
    if (colors.foreground == AppDesign.warning) {
      return Icons.schedule_rounded;
    }
    if (colors.foreground == AppDesign.success) {
      return Icons.check_circle_outline_rounded;
    }
    if (normalized.contains('refer')) return Icons.call_split_rounded;
    return Icons.info_outline_rounded;
  }
}

abstract final class HealthRecordDate {
  static String format(Object? raw, {bool includeTime = false}) {
    final value = raw?.toString().trim() ?? '';
    if (value.isEmpty || value.toLowerCase() == 'n/a') return 'Not recorded';
    final parsed = DateTime.tryParse(value);
    if (parsed == null) return value;
    return DateFormat(
      includeTime ? 'MMM d, yyyy • h:mm a' : 'MMM d, yyyy',
    ).format(parsed.toLocal());
  }

  static String time(Object? raw) {
    final value = raw?.toString().trim() ?? '';
    if (value.isEmpty || value.toLowerCase() == 'n/a') return 'Not recorded';
    final parsed = DateTime.tryParse(value);
    if (parsed == null) {
      final match = RegExp(r'\b\d{1,2}:\d{2}(?::\d{2})?\b').firstMatch(value);
      return match?.group(0) ?? 'Not recorded';
    }
    return DateFormat('h:mm a').format(parsed.toLocal());
  }
}
