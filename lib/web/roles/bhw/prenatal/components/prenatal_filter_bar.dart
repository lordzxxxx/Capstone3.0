import 'package:flutter/material.dart';
import 'prenatal_constants.dart';

class PrenatalFilterBar extends StatefulWidget {
  final String selectedStatus;
  final DateTime? fromDate;
  final DateTime? toDate;
  final ValueChanged<String> onStatusChanged;
  final VoidCallback onFromDateSelected;
  final VoidCallback onToDateSelected;
  final VoidCallback onClearDates;
  final int filteredCount;

  const PrenatalFilterBar({
    super.key,
    required this.selectedStatus,
    required this.fromDate,
    required this.toDate,
    required this.onStatusChanged,
    required this.onFromDateSelected,
    required this.onToDateSelected,
    required this.onClearDates,
    required this.filteredCount,
  });

  @override
  State<PrenatalFilterBar> createState() => _PrenatalFilterBarState();
}

class _PrenatalFilterBarState extends State<PrenatalFilterBar> {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD9E5F2), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF163B66).withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Prenatal Patients Registry',
                    style: TextStyle(
                      color: const Color(0xFF0B1F3A),
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'View and manage all prenatal patient records',
                    style: const TextStyle(
                      color: Color(0xFF4B6075),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
              // Total count badge
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: primaryAqua.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: primaryAqua.withValues(alpha: 0.4),
                    width: 1,
                  ),
                ),
                child: Text(
                  '${widget.filteredCount} total',
                  style: TextStyle(
                    color: primaryAqua,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Filter controls wrap instead of overflowing on narrow web widths.
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 720;
              final status = _buildStatusFilterDropdown();
              final from = _buildDatePickerButton(
                label: 'From',
                date: widget.fromDate,
                onTap: widget.onFromDateSelected,
              );
              final to = _buildDatePickerButton(
                label: 'To',
                date: widget.toDate,
                onTap: widget.onToDateSelected,
              );
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: compact ? constraints.maxWidth : 260,
                    child: status,
                  ),
                  SizedBox(
                    width: compact ? constraints.maxWidth : 170,
                    child: from,
                  ),
                  SizedBox(
                    width: compact ? constraints.maxWidth : 170,
                    child: to,
                  ),
                  if (widget.fromDate != null || widget.toDate != null)
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEECEC),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: IconButton(
                        onPressed: widget.onClearDates,
                        icon: const Icon(Icons.clear, color: Colors.red),
                        tooltip: 'Clear filters',
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildStatusFilterDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFCBD5E1), width: 1),
      ),
      child: Row(
        children: [
          Icon(Icons.filter_list_rounded, color: primaryAqua, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: widget.selectedStatus,
                isExpanded: true,
                icon: Icon(Icons.arrow_drop_down, color: primaryAqua, size: 20),
                style: const TextStyle(
                  color: const Color(0xFF0B1F3A),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
                dropdownColor: Colors.white,
                items: statusFilterOptions.map((String option) {
                  return DropdownMenuItem<String>(
                    value: option,
                    child: Text(
                      option,
                      style: const TextStyle(color: Color(0xFF0B1F3A)),
                    ),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null) {
                    widget.onStatusChanged(value);
                  }
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDatePickerButton({
    required String label,
    required DateTime? date,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: date != null ? const Color(0xFFEAF3FF) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: date != null
                ? primaryAqua
                : mutedCoolGray.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.calendar_today, color: primaryAqua, size: 16),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                date != null ? '${date.day}/${date.month}' : label,
                style: TextStyle(
                  color: date != null
                      ? const Color(0xFF0B1F3A)
                      : const Color(0xFF4B6075),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
