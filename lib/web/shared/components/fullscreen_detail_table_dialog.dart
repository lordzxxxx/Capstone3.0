import 'package:flutter/material.dart';

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
        TextSpan(
          text: value.substring(start, match.start),
          style: baseStyle,
        ),
      );
    }

    spans.add(
      TextSpan(
        text: value.substring(match.start, match.end),
        style: baseStyle.copyWith(color: const Color(0xFF00E5F7)),
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
  final rows = items
      .where((item) {
        final normalized = item.value.trim().toLowerCase();
        return normalized.isNotEmpty &&
            normalized != 'null' &&
            normalized != 'undefined';
      })
      .toList();

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
            color: const Color(0xFF0A1F24),
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
                    color: const Color(0xFF10343C),
                    border: Border(
                      bottom: BorderSide(
                        color: Colors.white.withValues(alpha: 0.08),
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
                                color: Colors.white,
                                fontSize: isCompact ? 22 : 26,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            if (subject.trim().isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(
                                subject,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.78),
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
                        color: Colors.white,
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
                        color: const Color(0xFF0E2F34),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: const Color(0xFF00A8B5).withValues(alpha: 0.18),
                        ),
                      ),
                      child: rows.isEmpty
                          ? Padding(
                              padding: const EdgeInsets.all(20),
                              child: Text(
                                'No details available.',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.8),
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
                                  color: Colors.white.withValues(alpha: 0.08),
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
                                            color: const Color(0xFF00A8B5),
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
                                                  Colors.white.withValues(
                                                    alpha: 0.86,
                                                  ),
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
                                          child: _buildHighlightedDetailValueText(
                                            item.value,
                                            TextStyle(
                                              color:
                                                  item.valueColor ??
                                                  Colors.white.withValues(
                                                    alpha: 0.8,
                                                  ),
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

String detailText(
  dynamic value, {
  String fallback = '',
}) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? fallback : text;
}
