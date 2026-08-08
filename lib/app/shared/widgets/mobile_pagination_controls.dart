import 'package:flutter/material.dart';

class MobilePaginationControls extends StatelessWidget {
  const MobilePaginationControls({
    super.key,
    required this.currentPage,
    required this.totalPages,
    required this.totalItems,
    required this.startIndex,
    required this.endIndex,
    required this.rowsPerPage,
    required this.onRowsPerPageChanged,
    required this.onPreviousPage,
    required this.onNextPage,
    required this.accentColor,
    required this.textColor,
    required this.surfaceColor,
    this.itemLabel = 'records',
    this.rowsPerPageOptions = const [5, 10, 20],
  });

  final int currentPage;
  final int totalPages;
  final int totalItems;
  final int startIndex;
  final int endIndex;
  final int rowsPerPage;
  final ValueChanged<int> onRowsPerPageChanged;
  final VoidCallback? onPreviousPage;
  final VoidCallback? onNextPage;
  final Color accentColor;
  final Color textColor;
  final Color surfaceColor;
  final String itemLabel;
  final List<int> rowsPerPageOptions;

  @override
  Widget build(BuildContext context) {
    if (totalItems == 0) {
      return const SizedBox.shrink();
    }

    final effectiveTotalPages = totalPages < 1 ? 1 : totalPages;
    final effectiveCurrentPage = currentPage < 1
        ? 1
        : (currentPage > effectiveTotalPages ? effectiveTotalPages : currentPage);
    final dropdownValue = rowsPerPageOptions.contains(rowsPerPage)
        ? rowsPerPage
        : rowsPerPageOptions.first;

    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: accentColor.withValues(alpha: 0.22),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Showing ${startIndex + 1}-$endIndex of $totalItems $itemLabel',
            style: TextStyle(
              color: textColor,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: surfaceColor.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: textColor.withValues(alpha: 0.16),
                  ),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    value: dropdownValue,
                    dropdownColor: surfaceColor,
                    borderRadius: BorderRadius.circular(12),
                    iconEnabledColor: textColor,
                    style: TextStyle(
                      color: textColor,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                    items: rowsPerPageOptions
                        .map(
                          (rows) => DropdownMenuItem<int>(
                            value: rows,
                            child: Text('$rows / page'),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) {
                        onRowsPerPageChanged(value);
                      }
                    },
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    _PaginationIconButton(
                      icon: Icons.chevron_left_rounded,
                      tooltip: 'Previous page',
                      onPressed: onPreviousPage,
                      accentColor: accentColor,
                      textColor: textColor,
                      surfaceColor: surfaceColor,
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: surfaceColor.withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: textColor.withValues(alpha: 0.16),
                        ),
                      ),
                      child: Text(
                        '$effectiveCurrentPage / $effectiveTotalPages',
                        style: TextStyle(
                          color: textColor,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _PaginationIconButton(
                      icon: Icons.chevron_right_rounded,
                      tooltip: 'Next page',
                      onPressed: onNextPage,
                      accentColor: accentColor,
                      textColor: textColor,
                      surfaceColor: surfaceColor,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PaginationIconButton extends StatelessWidget {
  const _PaginationIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    required this.accentColor,
    required this.textColor,
    required this.surfaceColor,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final Color accentColor;
  final Color textColor;
  final Color surfaceColor;

  @override
  Widget build(BuildContext context) {
    final isEnabled = onPressed != null;

    return Container(
      decoration: BoxDecoration(
        color: isEnabled ? accentColor.withValues(alpha: 0.14) : surfaceColor.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isEnabled ? accentColor.withValues(alpha: 0.24) : textColor.withValues(alpha: 0.12),
        ),
      ),
      child: IconButton(
        tooltip: tooltip,
        visualDensity: VisualDensity.compact,
        splashRadius: 20,
        onPressed: onPressed,
        icon: Icon(
          icon,
          color: isEnabled ? accentColor : textColor.withValues(alpha: 0.35),
        ),
      ),
    );
  }
}
