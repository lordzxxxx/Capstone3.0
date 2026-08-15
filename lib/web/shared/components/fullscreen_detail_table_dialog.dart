import 'package:flutter/material.dart';
import 'package:mycapstone_project/web/shared/theme/app_theme.dart';

class DetailTableItem {
  const DetailTableItem({
    required this.icon,
    required this.label,
    required this.value,
    this.labelColor,
    this.valueColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? labelColor;
  final Color? valueColor;
}

final RegExp _vitalLabelPattern = RegExp(
  r'\b(?:BP|Temp|HR|Bpm|bprm|O2|Weight|Height):',
  caseSensitive: false,
);

Widget _buildHighlightedDetailValueText(String value, TextStyle baseStyle) {
  final matches = _vitalLabelPattern.allMatches(value).toList();
  if (matches.isEmpty) {
    return Text(value, style: baseStyle);
  }

  final spans = <TextSpan>[];
  var start = 0;

  for (final match in matches) {
    if (match.start > start) {
      spans.add(
        TextSpan(text: value.substring(start, match.start), style: baseStyle),
      );
    }

    spans.add(
      TextSpan(
        text: value.substring(match.start, match.end),
        style: baseStyle.copyWith(color: AppColors.primary),
      ),
    );
    start = match.end;
  }

  if (start < value.length) {
    spans.add(TextSpan(text: value.substring(start), style: baseStyle));
  }

  return RichText(text: TextSpan(children: spans));
}

Future<void> showFullscreenDetailTableDialog({
  required BuildContext context,
  required String title,
  required String subject,
  required List<DetailTableItem> items,
}) async {
  final rows = items.where((item) {
    final normalized = item.value.trim().toLowerCase();
    return normalized.isNotEmpty &&
        normalized != 'null' &&
        normalized != 'undefined';
  }).toList();

  await showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.74),
    builder: (dialogContext) {
      final screenSize = MediaQuery.of(dialogContext).size;
      final isCompact = screenSize.width < 860;

      return Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.zero,
        child: SizedBox(
          width: screenSize.width,
          height: screenSize.height,
          child: Container(
            color: AppColors.backgroundLight,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: EdgeInsets.fromLTRB(
                    isCompact ? 20 : 28,
                    isCompact ? 18 : 24,
                    isCompact ? 16 : 22,
                    isCompact ? 18 : 24,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.secondary,
                    border: Border(
                      bottom: BorderSide(
                        color: AppColors.borderStrong.withValues(alpha: 0.45),
                        width: 1,
                      ),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: TextStyle(
                                color: AppColors.textOnDark,
                                fontSize: isCompact ? 22 : 26,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            if (subject.trim().isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(
                                subject,
                                style: TextStyle(
                                  color: AppColors.textOnDark,
                                  fontSize: isCompact ? 14 : 15.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        icon: const Icon(Icons.close_rounded),
                        color: AppColors.textOnDark,
                        tooltip: 'Close',
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.all(isCompact ? 16 : 24),
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.surfaceLight,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: rows.isEmpty
                          ? Padding(
                              padding: const EdgeInsets.all(20),
                              child: Text(
                                'No details available.',
                                style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            )
                          : Table(
                              columnWidths: {
                                0: const FixedColumnWidth(56),
                                1: FixedColumnWidth(isCompact ? 150 : 220),
                                2: const FlexColumnWidth(),
                              },
                              defaultVerticalAlignment:
                                  TableCellVerticalAlignment.middle,
                              border: TableBorder(
                                horizontalInside: BorderSide(
                                  color: AppColors.border,
                                  width: 1,
                                ),
                              ),
                              children: rows
                                  .map(
                                    (item) => TableRow(
                                      children: [
                                        Padding(
                                          padding: const EdgeInsets.all(14),
                                          child: Icon(
                                            item.icon,
                                            color: AppColors.primary,
                                            size: 20,
                                          ),
                                        ),
                                        Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 14,
                                          ),
                                          child: Text(
                                            item.label,
                                            style: TextStyle(
                                              color:
                                                  item.labelColor ??
                                                  AppColors.textPrimary,
                                              fontSize: 13.5,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                        Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 14,
                                          ),
                                          child:
                                              _buildHighlightedDetailValueText(
                                                item.value,
                                                TextStyle(
                                                  color:
                                                      item.valueColor ??
                                                      AppColors.textSecondary,
                                                  fontSize: 13.5,
                                                  height: 1.45,
                                                ),
                                              ),
                                        ),
                                      ],
                                    ),
                                  )
                                  .toList(),
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

String detailText(dynamic value, {String fallback = ''}) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? fallback : text;
}
