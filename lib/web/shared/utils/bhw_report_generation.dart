import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:mycapstone_project/firebase_helper.dart';
import 'package:mycapstone_project/shared/official_report_layout.dart';
import 'package:mycapstone_project/web/shared/utils/report_branding.dart';
import 'package:mycapstone_project/web/shared/utils/file_download.dart';
import 'package:mycapstone_project/web/shared/utils/pdf_fonts.dart';
import 'package:mycapstone_project/web/shared/theme/app_theme.dart';
import 'package:mycapstone_project/web/shared/components/app_buttons.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

enum ReportPeriod { monthly, quarterly, yearly }

enum ReportExportFormat { pdf, excel }

extension ReportPeriodLabel on ReportPeriod {
  String get label {
    switch (this) {
      case ReportPeriod.monthly:
        return 'Monthly';
      case ReportPeriod.quarterly:
        return 'Quarterly';
      case ReportPeriod.yearly:
        return 'Yearly';
    }
  }

  IconData get icon {
    switch (this) {
      case ReportPeriod.monthly:
        return Icons.calendar_view_month_rounded;
      case ReportPeriod.quarterly:
        return Icons.calendar_view_week_rounded;
      case ReportPeriod.yearly:
        return Icons.date_range_rounded;
    }
  }
}

class ReportCsvColumn {
  final String header;
  final String Function(Map<String, dynamic> record) valueBuilder;
  final double flex;
  final bool center;

  const ReportCsvColumn(
    this.header,
    this.valueBuilder, {
    this.flex = 1,
    this.center = false,
  });
}

class _ReportDialogDefaults {
  final String barangayName;
  final String preparedBy;
  final String preparedByPosition;
  final String bhwHead;
  final String bhwHeadPosition;
  final String reviewedBy;
  final String reviewedByPosition;
  final String approvedBy;
  final String approvedByPosition;
  final String remarks;

  const _ReportDialogDefaults({
    required this.barangayName,
    required this.preparedBy,
    required this.preparedByPosition,
    required this.bhwHead,
    required this.bhwHeadPosition,
    required this.reviewedBy,
    required this.reviewedByPosition,
    required this.approvedBy,
    required this.approvedByPosition,
    required this.remarks,
  });
}

class _ReportSelection {
  final ReportPeriod period;
  final int month;
  final int year;
  final String barangayName;
  final String preparedBy;
  final String preparedByPosition;
  final String bhwHead;
  final String bhwHeadPosition;
  final String reviewedBy;
  final String reviewedByPosition;
  final String approvedBy;
  final String approvedByPosition;
  final String remarks;
  final ReportExportFormat format;

  const _ReportSelection({
    required this.period,
    required this.month,
    required this.year,
    required this.barangayName,
    required this.preparedBy,
    required this.preparedByPosition,
    required this.bhwHead,
    required this.bhwHeadPosition,
    required this.reviewedBy,
    required this.reviewedByPosition,
    required this.approvedBy,
    required this.approvedByPosition,
    required this.remarks,
    this.format = ReportExportFormat.pdf,
  });

  _ReportSelection copyWith({ReportExportFormat? format}) {
    return _ReportSelection(
      period: period,
      month: month,
      year: year,
      barangayName: barangayName,
      preparedBy: preparedBy,
      preparedByPosition: preparedByPosition,
      bhwHead: bhwHead,
      bhwHeadPosition: bhwHeadPosition,
      reviewedBy: reviewedBy,
      reviewedByPosition: reviewedByPosition,
      approvedBy: approvedBy,
      approvedByPosition: approvedByPosition,
      remarks: remarks,
      format: format ?? this.format,
    );
  }

  int get quarter => ((month - 1) ~/ 3) + 1;

  String get scopeLabel {
    switch (period) {
      case ReportPeriod.monthly:
        return DateFormat.yMMMM().format(DateTime(year, month));
      case ReportPeriod.quarterly:
        final startMonth = month;
        final endMonth = month + 2;
        final startLabel = DateFormat.MMM().format(DateTime(year, startMonth));
        final endLabel = DateFormat.MMM().format(DateTime(year, endMonth));
        return 'Quarter $quarter, $year ($startLabel-$endLabel)';
      case ReportPeriod.yearly:
        return year.toString();
    }
  }

  String get filenameToken {
    switch (period) {
      case ReportPeriod.monthly:
        return '${year}_${month.toString().padLeft(2, '0')}';
      case ReportPeriod.quarterly:
        return '${year}_q$quarter';
      case ReportPeriod.yearly:
        return year.toString();
    }
  }
}

class _ReportAggregation {
  final int totalRecords;
  final int uniqueSubjects;
  final DateTime? earliestDate;
  final DateTime? latestDate;
  final Map<String, int> sexCounts;
  final Map<String, int> statusCounts;
  final Map<String, int> primaryCounts;
  final String primaryLabel;

  const _ReportAggregation({
    required this.totalRecords,
    required this.uniqueSubjects,
    required this.earliestDate,
    required this.latestDate,
    required this.sexCounts,
    required this.statusCounts,
    required this.primaryCounts,
    required this.primaryLabel,
  });
}

/// Parameters for PDF generation that can be passed to an isolate
class _PdfGenerationParams {
  final String moduleLabel;
  final _ReportSelection selection;
  final List<Map<String, dynamic>> records;
  final List<ReportCsvColumn> columns;
  final DateTime? Function(Map<String, dynamic> record) dateResolver;
  final List<int>? cityLogoBytes;
  final List<int>? healthOfficeLogoBytes;
  final List<int>? barangayLogoBytes;

  const _PdfGenerationParams({
    required this.moduleLabel,
    required this.selection,
    required this.records,
    required this.columns,
    required this.dateResolver,
    this.cityLogoBytes,
    this.healthOfficeLogoBytes,
    this.barangayLogoBytes,
  });
}

String reportText(dynamic value, {String fallback = 'N/A'}) {
  if (value == null) return fallback;

  if (value is String) {
    final text = value.trim();
    if (text.isEmpty) return fallback;
    final normalized = text.toLowerCase();
    if (normalized == 'null' || normalized == 'undefined') {
      return fallback;
    }
    return text;
  }

  if (value is Iterable) {
    final parts = value
        .map((item) => reportText(item, fallback: ''))
        .where((item) => item.isNotEmpty)
        .toList();
    return parts.isEmpty ? fallback : parts.join('; ');
  }

  if (value is Map) {
    try {
      return jsonEncode(value);
    } catch (_) {
      return value.toString();
    }
  }

  final text = value.toString().trim();
  return text.isEmpty ? fallback : text;
}

String reportJoin(
  List<dynamic> values, {
  String separator = ' ',
  String fallback = 'N/A',
}) {
  final parts = values
      .map((value) => reportText(value, fallback: ''))
      .where((value) => value.isNotEmpty)
      .toList();
  return parts.isEmpty ? fallback : parts.join(separator);
}

DateTime? parseReportDateValue(dynamic value) {
  if (value == null) return null;

  if (value is DateTime) {
    return value;
  }

  if (value is String) {
    final text = value.trim();
    if (text.isEmpty) return null;
    return DateTime.tryParse(text);
  }

  if (value is num) {
    try {
      return DateTime.fromMillisecondsSinceEpoch(value.toInt());
    } catch (_) {
      return null;
    }
  }

  try {
    final converted = (value as dynamic).toDate();
    if (converted is DateTime) {
      return converted;
    }
  } catch (_) {}

  return null;
}

String formatReportDateValue(dynamic value, {String fallback = 'N/A'}) {
  final parsed = parseReportDateValue(value);
  if (parsed == null) {
    return reportText(value, fallback: fallback);
  }

  return DateFormat('yyyy-MM-dd').format(parsed);
}

Future<void> generateReportPdf({
  required BuildContext context,
  required String moduleLabel,
  required List<Map<String, dynamic>> records,
  required DateTime? Function(Map<String, dynamic> record) dateResolver,
  required List<ReportCsvColumn> columns,
  required Color accentColor,
  required Color dialogColor,
  required Color textColor,
  required Color mutedColor,
  String Function(Map<String, dynamic> record, int index)? sectionTitleBuilder,
}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);

  if (records.isEmpty) {
    messenger?.showSnackBar(
      SnackBar(
        content: Text('No $moduleLabel records are available to generate.'),
        backgroundColor: Colors.orange,
      ),
    );
    return;
  }

  final datedRecords = records
      .where((record) => dateResolver(record) != null)
      .toList();

  if (datedRecords.isEmpty) {
    messenger?.showSnackBar(
      SnackBar(
        content: Text(
          'No $moduleLabel records have a valid date for report generation yet.',
        ),
        backgroundColor: Colors.orange,
      ),
    );
    return;
  }

  final defaults = await _loadReportDialogDefaults(records);
  if (!context.mounted) return;
  // Some legacy callers still pass the old light-surface/white-text pair.
  // Normalize the dialog palette here so every report workflow remains
  // readable without changing report data or export behavior.
  final isDarkDialog =
      ThemeData.estimateBrightnessForColor(dialogColor) == Brightness.dark;
  final readableTextColor = isDarkDialog ? Colors.white : AppColors.textPrimary;
  final readableMutedColor = isDarkDialog
      ? AppColors.textOnDarkMuted
      : AppColors.textSecondary;
  final selection = await _showReportGenerationDialog(
    context: context,
    moduleLabel: moduleLabel,
    records: datedRecords,
    dateResolver: dateResolver,
    accentColor: accentColor,
    dialogColor: dialogColor,
    textColor: readableTextColor,
    mutedColor: readableMutedColor,
    defaults: defaults,
  );

  if (selection == null || !context.mounted) return;

  final filteredRecords =
      _filterRecordsForSelection(datedRecords, dateResolver, selection)
        ..sort((a, b) {
          final first = dateResolver(a);
          final second = dateResolver(b);
          if (first == null && second == null) return 0;
          if (first == null) return 1;
          if (second == null) return -1;
          return first.compareTo(second);
        });

  if (filteredRecords.isEmpty) {
    messenger?.showSnackBar(
      SnackBar(
        content: Text(
          'No $moduleLabel records matched ${selection.scopeLabel}.',
        ),
        backgroundColor: Colors.orange,
      ),
    );
    return;
  }

  final branding = await loadReportBranding(
    barangayName: selection.barangayName,
  );

  if (selection.format == ReportExportFormat.excel) {
    final excelBytes = _buildFormalBhwReportExcelBytes(
      moduleLabel: moduleLabel,
      selection: selection,
      records: filteredRecords,
      columns: columns,
      dateResolver: dateResolver,
      branding: branding,
    );
    final filename =
        '${_slugify(moduleLabel)}_${selection.period.label.toLowerCase()}_${selection.filenameToken}_report.xls';
    final downloaded = downloadFile(
      bytes: excelBytes,
      filename: filename,
      mimeType: 'application/vnd.ms-excel',
    );
    messenger?.showSnackBar(
      SnackBar(
        content: Text(
          downloaded
              ? '${selection.period.label} $moduleLabel Excel report downloaded with ${filteredRecords.length} record${filteredRecords.length == 1 ? '' : 's'}.'
              : 'Excel export is only supported in the web dashboard.',
        ),
        backgroundColor: downloaded ? accentColor : Colors.orange,
      ),
    );
    return;
  }

  final pdfBytes = await _buildFormalBhwReportPdfBytes(
    moduleLabel: moduleLabel,
    selection: selection,
    records: filteredRecords,
    columns: columns,
    dateResolver: dateResolver,
    branding: branding,
  );

  final filename =
      '${_slugify(moduleLabel)}_${selection.period.label.toLowerCase()}_${selection.filenameToken}_report.pdf';

  final downloaded = downloadFile(
    bytes: pdfBytes,
    filename: filename,
    mimeType: 'application/pdf',
  );

  messenger?.showSnackBar(
    SnackBar(
      content: Text(
        downloaded
            ? '${selection.period.label} $moduleLabel PDF downloaded with ${filteredRecords.length} record${filteredRecords.length == 1 ? '' : 's'}.'
            : 'PDF generation is only supported in the web dashboard.',
      ),
      backgroundColor: downloaded ? accentColor : Colors.orange,
    ),
  );
}

Future<_ReportDialogDefaults> _loadReportDialogDefaults(
  List<Map<String, dynamic>> records,
) async {
  String preparedBy = _defaultPreparedBy();
  String preparedByPosition = 'BHW Assigned on Duty';

  final user = FirebaseAuth.instance.currentUser;
  if (user != null) {
    try {
      final userDoc = await getFirestoreInstance()
          .collection('users')
          .doc(user.uid)
          .get();
      final data = userDoc.data() ?? const <String, dynamic>{};
      preparedBy = _cleanFieldValue(
        data['username']?.toString() ??
            data['fullName']?.toString() ??
            data['displayName']?.toString() ??
            preparedBy,
        fallback: preparedBy,
      );
      preparedByPosition = _roleToPosition(
        data['role']?.toString() ?? '',
        fallback: preparedByPosition,
      );
    } catch (_) {}
  }

  return _ReportDialogDefaults(
    barangayName: _deriveDefaultBarangayName(records),
    preparedBy: preparedBy,
    preparedByPosition: preparedByPosition,
    bhwHead: '',
    bhwHeadPosition: 'BHW Head',
    reviewedBy: '',
    reviewedByPosition: 'Barangay Kagawad in Health',
    approvedBy: '',
    approvedByPosition: 'Barangay Captain',
    remarks:
        'This report was generated from encoded BHW records for official monitoring, submission, and filing.',
  );
}

Future<_ReportSelection?> _showReportGenerationDialog({
  required BuildContext context,
  required String moduleLabel,
  required List<Map<String, dynamic>> records,
  required DateTime? Function(Map<String, dynamic> record) dateResolver,
  required Color accentColor,
  required Color dialogColor,
  required Color textColor,
  required Color mutedColor,
  required _ReportDialogDefaults defaults,
}) async {
  final yearOptions = _buildAvailableYears(records, dateResolver);
  ReportPeriod selectedPeriod = ReportPeriod.monthly;
  int selectedYear = yearOptions.first;
  int selectedMonth = _normalizeMonthForPeriod(
    DateTime.now().month,
    ReportPeriod.monthly,
  );

  final barangayController = TextEditingController(text: defaults.barangayName);
  final preparedByController = TextEditingController(text: defaults.preparedBy);
  final preparedByPositionController = TextEditingController(
    text: defaults.preparedByPosition,
  );
  final bhwHeadController = TextEditingController(text: defaults.bhwHead);
  final bhwHeadPositionController = TextEditingController(
    text: defaults.bhwHeadPosition,
  );
  final reviewedByController = TextEditingController(text: defaults.reviewedBy);
  final reviewedByPositionController = TextEditingController(
    text: defaults.reviewedByPosition,
  );
  final approvedByController = TextEditingController(text: defaults.approvedBy);
  final approvedByPositionController = TextEditingController(
    text: defaults.approvedByPosition,
  );
  final remarksController = TextEditingController(text: defaults.remarks);

  try {
    return await showDialog<_ReportSelection>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            selectedMonth = _normalizeMonthForPeriod(
              selectedMonth,
              selectedPeriod,
            );
            final selection = _ReportSelection(
              period: selectedPeriod,
              month: selectedMonth,
              year: selectedYear,
              barangayName: _cleanFieldValue(
                barangayController.text,
                fallback: 'Barangay Not Specified',
              ),
              preparedBy: _cleanFieldValue(
                preparedByController.text,
                fallback: _defaultPreparedBy(),
              ),
              preparedByPosition: _cleanFieldValue(
                preparedByPositionController.text,
                fallback: 'BHW Assigned on Duty',
              ),
              bhwHead: bhwHeadController.text.trim(),
              bhwHeadPosition: _cleanFieldValue(
                bhwHeadPositionController.text,
                fallback: 'BHW Head',
              ),
              reviewedBy: reviewedByController.text.trim(),
              reviewedByPosition: _cleanFieldValue(
                reviewedByPositionController.text,
                fallback: 'Barangay Kagawad in Health',
              ),
              approvedBy: approvedByController.text.trim(),
              approvedByPosition: _cleanFieldValue(
                approvedByPositionController.text,
                fallback: 'Barangay Captain',
              ),
              remarks: _cleanFieldValue(
                remarksController.text,
                fallback:
                    'This report was generated from encoded BHW records for official monitoring, submission, and filing.',
              ),
            );
            final matchingCount = _filterRecordsForSelection(
              records,
              dateResolver,
              selection,
            ).length;
            final reportTitle = _buildOfficialReportTitle(
              moduleLabel,
              selection.period,
            );
            final isDarkSurface =
                ThemeData.estimateBrightnessForColor(dialogColor) ==
                Brightness.dark;

            return AlertDialog(
              backgroundColor: dialogColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: Text(
                'Generate Official $moduleLabel Report',
                style: TextStyle(color: textColor, fontWeight: FontWeight.w700),
              ),
              content: SizedBox(
                width: 560,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Set the reporting period and signatory details, then export a print-ready submission report.',
                        style: TextStyle(color: mutedColor, height: 1.45),
                      ),
                      const SizedBox(height: 18),
                      _buildDialogSection(
                        title: 'Report Scope',
                        subtitle:
                            'Choose the official reporting window for the generated PDF.',
                        isDarkSurface: isDarkSurface,
                        accentColor: accentColor,
                        mutedColor: mutedColor,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: ReportPeriod.values.map((period) {
                                final isSelected = period == selectedPeriod;
                                return ChoiceChip(
                                  selected: isSelected,
                                  showCheckmark: false,
                                  avatar: Icon(
                                    period.icon,
                                    size: 18,
                                    color: isSelected
                                        ? accentColor
                                        : mutedColor,
                                  ),
                                  label: Text(period.label),
                                  labelStyle: TextStyle(
                                    color: isSelected ? textColor : mutedColor,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  backgroundColor: isDarkSurface
                                      ? Colors.white.withValues(alpha: 0.05)
                                      : Colors.black.withValues(alpha: 0.04),
                                  selectedColor: accentColor.withValues(
                                    alpha: 0.16,
                                  ),
                                  side: BorderSide(
                                    color: isSelected
                                        ? accentColor
                                        : mutedColor.withValues(alpha: 0.25),
                                  ),
                                  onSelected: (_) {
                                    setDialogState(() {
                                      selectedPeriod = period;
                                      selectedMonth = _normalizeMonthForPeriod(
                                        selectedMonth,
                                        selectedPeriod,
                                      );
                                    });
                                  },
                                );
                              }).toList(),
                            ),
                            const SizedBox(height: 16),
                            if (selectedPeriod != ReportPeriod.yearly) ...[
                              _buildDropdownField<int>(
                                label: selectedPeriod == ReportPeriod.quarterly
                                    ? 'Quarter'
                                    : 'Month',
                                value: selectedMonth,
                                items: _monthOptionsForPeriod(selectedPeriod)
                                    .map(
                                      (month) => DropdownMenuItem<int>(
                                        value: month,
                                        child: Text(
                                          _monthLabelForPeriod(
                                            month,
                                            selectedPeriod,
                                          ),
                                        ),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (value) {
                                  if (value == null) return;
                                  setDialogState(() => selectedMonth = value);
                                },
                                accentColor: accentColor,
                                fieldColor: dialogColor,
                                textColor: textColor,
                                mutedColor: mutedColor,
                                isDarkSurface: isDarkSurface,
                              ),
                              const SizedBox(height: 14),
                            ],
                            _buildDropdownField<int>(
                              label: 'Year',
                              value: selectedYear,
                              items: yearOptions
                                  .map(
                                    (year) => DropdownMenuItem<int>(
                                      value: year,
                                      child: Text(year.toString()),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (value) {
                                if (value == null) return;
                                setDialogState(() => selectedYear = value);
                              },
                              accentColor: accentColor,
                              fieldColor: dialogColor,
                              textColor: textColor,
                              mutedColor: mutedColor,
                              isDarkSurface: isDarkSurface,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      _buildDialogSection(
                        title: 'Document Details',
                        subtitle:
                            'These values appear in the report header and body.',
                        isDarkSurface: isDarkSurface,
                        accentColor: accentColor,
                        mutedColor: mutedColor,
                        child: Column(
                          children: [
                            _buildDialogTextField(
                              label: 'Barangay Name',
                              controller: barangayController,
                              textColor: textColor,
                              mutedColor: mutedColor,
                              accentColor: accentColor,
                              isDarkSurface: isDarkSurface,
                            ),
                            const SizedBox(height: 12),
                            _buildDialogTextField(
                              label: 'BHW Assigned on Duty',
                              controller: preparedByController,
                              textColor: textColor,
                              mutedColor: mutedColor,
                              accentColor: accentColor,
                              isDarkSurface: isDarkSurface,
                            ),
                            const SizedBox(height: 12),
                            _buildDialogTextField(
                              label: 'BHW Assigned on Duty Position',
                              controller: preparedByPositionController,
                              textColor: textColor,
                              mutedColor: mutedColor,
                              accentColor: accentColor,
                              isDarkSurface: isDarkSurface,
                            ),
                            const SizedBox(height: 12),
                            _buildDialogTextField(
                              label: 'Remarks / Notes',
                              controller: remarksController,
                              maxLines: 3,
                              textColor: textColor,
                              mutedColor: mutedColor,
                              accentColor: accentColor,
                              isDarkSurface: isDarkSurface,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      _buildDialogSection(
                        title: 'Signatory Section',
                        subtitle:
                            'These names and positions are printed in the signature block.',
                        isDarkSurface: isDarkSurface,
                        accentColor: accentColor,
                        mutedColor: mutedColor,
                        child: Column(
                          children: [
                            _buildDialogTextField(
                              label: 'Barangay Captain',
                              controller: approvedByController,
                              textColor: textColor,
                              mutedColor: mutedColor,
                              accentColor: accentColor,
                              isDarkSurface: isDarkSurface,
                            ),
                            const SizedBox(height: 12),
                            _buildDialogTextField(
                              label: 'Barangay Captain Position',
                              controller: approvedByPositionController,
                              textColor: textColor,
                              mutedColor: mutedColor,
                              accentColor: accentColor,
                              isDarkSurface: isDarkSurface,
                            ),
                            const SizedBox(height: 12),
                            _buildDialogTextField(
                              label: 'Barangay Kagawad in Health',
                              controller: reviewedByController,
                              textColor: textColor,
                              mutedColor: mutedColor,
                              accentColor: accentColor,
                              isDarkSurface: isDarkSurface,
                            ),
                            const SizedBox(height: 12),
                            _buildDialogTextField(
                              label: 'Barangay Kagawad in Health Position',
                              controller: reviewedByPositionController,
                              textColor: textColor,
                              mutedColor: mutedColor,
                              accentColor: accentColor,
                              isDarkSurface: isDarkSurface,
                            ),
                            const SizedBox(height: 12),
                            _buildDialogTextField(
                              label: 'BHW Head',
                              controller: bhwHeadController,
                              textColor: textColor,
                              mutedColor: mutedColor,
                              accentColor: accentColor,
                              isDarkSurface: isDarkSurface,
                            ),
                            const SizedBox(height: 12),
                            _buildDialogTextField(
                              label: 'BHW Head Position',
                              controller: bhwHeadPositionController,
                              textColor: textColor,
                              mutedColor: mutedColor,
                              accentColor: accentColor,
                              isDarkSurface: isDarkSurface,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: isDarkSurface
                              ? Colors.white.withValues(alpha: 0.05)
                              : Colors.black.withValues(alpha: 0.04),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: accentColor.withValues(alpha: 0.28),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Preview',
                              style: TextStyle(
                                color: mutedColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              reportTitle,
                              style: TextStyle(
                                color: textColor,
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Coverage: ${selection.scopeLabel}',
                              style: TextStyle(color: mutedColor),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Barangay: ${selection.barangayName.isEmpty ? 'Barangay Not Specified' : selection.barangayName}',
                              style: TextStyle(color: mutedColor),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              '$matchingCount matching record${matchingCount == 1 ? '' : 's'} ready for print-ready PDF or Excel export.',
                              style: TextStyle(
                                color: matchingCount > 0
                                    ? textColor
                                    : Colors.orange.shade300,
                                height: 1.4,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _selectionHint(selection),
                              style: TextStyle(color: mutedColor, height: 1.45),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  style: TextButton.styleFrom(foregroundColor: mutedColor),
                  child: const Text('Cancel'),
                ),
                OutlinedButton.icon(
                  onPressed: matchingCount == 0
                      ? null
                      : () => Navigator.of(dialogContext).pop(
                          selection.copyWith(format: ReportExportFormat.excel),
                        ),
                  icon: const Icon(Icons.table_chart_outlined),
                  label: const Text('Generate Excel'),
                  style: AppButtonStyles.outline(),
                ),
                FilledButton.icon(
                  onPressed: matchingCount == 0
                      ? null
                      : () => Navigator.of(dialogContext).pop(
                          selection.copyWith(format: ReportExportFormat.pdf),
                        ),
                  style: AppButtonStyles.report(),
                  icon: const Icon(Icons.picture_as_pdf_rounded),
                  label: const Text('Generate PDF'),
                ),
              ],
            );
          },
        );
      },
    );
  } finally {
    barangayController.dispose();
    preparedByController.dispose();
    preparedByPositionController.dispose();
    bhwHeadController.dispose();
    bhwHeadPositionController.dispose();
    reviewedByController.dispose();
    reviewedByPositionController.dispose();
    approvedByController.dispose();
    approvedByPositionController.dispose();
    remarksController.dispose();
  }
}

Widget _buildDialogSection({
  required String title,
  required String subtitle,
  required bool isDarkSurface,
  required Color accentColor,
  required Color mutedColor,
  required Widget child,
}) {
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: isDarkSurface
          ? Colors.white.withValues(alpha: 0.05)
          : Colors.black.withValues(alpha: 0.04),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: accentColor.withValues(alpha: 0.2)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(color: mutedColor, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(subtitle, style: TextStyle(color: mutedColor, height: 1.4)),
        const SizedBox(height: 14),
        child,
      ],
    ),
  );
}

Widget _buildDialogTextField({
  required String label,
  required TextEditingController controller,
  required Color textColor,
  required Color mutedColor,
  required Color accentColor,
  required bool isDarkSurface,
  int maxLines = 1,
}) {
  return TextField(
    controller: controller,
    maxLines: maxLines,
    style: TextStyle(color: textColor),
    decoration: InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: mutedColor),
      filled: true,
      fillColor: isDarkSurface
          ? Colors.white.withValues(alpha: 0.05)
          : Colors.black.withValues(alpha: 0.04),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: mutedColor.withValues(alpha: 0.22)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: accentColor, width: 1.5),
      ),
    ),
  );
}

Widget _buildDropdownField<T>({
  required String label,
  required T value,
  required List<DropdownMenuItem<T>> items,
  required ValueChanged<T?> onChanged,
  required Color accentColor,
  required Color fieldColor,
  required Color textColor,
  required Color mutedColor,
  required bool isDarkSurface,
}) {
  return DropdownButtonFormField<T>(
    initialValue: value,
    isExpanded: true,
    dropdownColor: fieldColor,
    iconEnabledColor: textColor,
    style: TextStyle(color: textColor),
    decoration: InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: mutedColor),
      filled: true,
      fillColor: isDarkSurface
          ? Colors.white.withValues(alpha: 0.05)
          : Colors.black.withValues(alpha: 0.04),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: mutedColor.withValues(alpha: 0.22)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: accentColor, width: 1.5),
      ),
    ),
    items: items,
    onChanged: onChanged,
  );
}

List<int> _buildAvailableYears(
  List<Map<String, dynamic>> records,
  DateTime? Function(Map<String, dynamic> record) dateResolver,
) {
  final years =
      records
          .map(dateResolver)
          .whereType<DateTime>()
          .map((date) => date.year)
          .toSet()
          .toList()
        ..sort((a, b) => b.compareTo(a));

  if (years.isNotEmpty) {
    return years;
  }

  final currentYear = DateTime.now().year;
  return List<int>.generate(6, (index) => currentYear - index);
}

List<Map<String, dynamic>> _filterRecordsForSelection(
  List<Map<String, dynamic>> records,
  DateTime? Function(Map<String, dynamic> record) dateResolver,
  _ReportSelection selection,
) {
  return records.where((record) {
    final recordDate = dateResolver(record);
    if (recordDate == null) return false;

    switch (selection.period) {
      case ReportPeriod.monthly:
        return recordDate.year == selection.year &&
            recordDate.month == selection.month;
      case ReportPeriod.quarterly:
        final quarter = ((recordDate.month - 1) ~/ 3) + 1;
        return recordDate.year == selection.year &&
            quarter == selection.quarter;
      case ReportPeriod.yearly:
        return recordDate.year == selection.year;
    }
  }).toList();
}

List<int> _monthOptionsForPeriod(ReportPeriod period) {
  switch (period) {
    case ReportPeriod.quarterly:
      return const [1, 4, 7, 10];
    case ReportPeriod.monthly:
    case ReportPeriod.yearly:
      return List<int>.generate(12, (index) => index + 1);
  }
}

int _normalizeMonthForPeriod(int month, ReportPeriod period) {
  final safeMonth = month.clamp(1, 12);
  if (period == ReportPeriod.quarterly) {
    return (((safeMonth - 1) ~/ 3) * 3) + 1;
  }
  return safeMonth;
}

String _monthLabelForPeriod(int month, ReportPeriod period) {
  if (period == ReportPeriod.quarterly) {
    final quarter = ((month - 1) ~/ 3) + 1;
    final start = DateFormat.MMM().format(DateTime(2024, month));
    final end = DateFormat.MMM().format(DateTime(2024, month + 2));
    return 'Q$quarter ($start-$end)';
  }

  return DateFormat.MMMM().format(DateTime(2024, month));
}

String _selectionHint(_ReportSelection selection) {
  switch (selection.period) {
    case ReportPeriod.monthly:
      return 'Builds an official monthly PDF for records dated within ${selection.scopeLabel}.';
    case ReportPeriod.quarterly:
      return 'Builds an official quarterly PDF for ${selection.scopeLabel}. The selected quarter is based on the chosen start month.';
    case ReportPeriod.yearly:
      return 'Builds an official yearly PDF for all encoded records dated within ${selection.year}.';
  }
}

String _slugify(String value) {
  return value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
}

Color _bestForegroundColor(Color background) {
  return background.computeLuminance() > 0.45 ? Colors.black : Colors.white;
}

Future<List<int>> _buildFormalBhwReportPdfBytes({
  required String moduleLabel,
  required _ReportSelection selection,
  required List<Map<String, dynamic>> records,
  required List<ReportCsvColumn> columns,
  required DateTime? Function(Map<String, dynamic> record) dateResolver,
  required ReportBranding branding,
}) async {
  // Run the heavy PDF generation on a background isolate to prevent UI freezing
  return compute(
    _generatePdfBytesInBackground,
    _PdfGenerationParams(
      moduleLabel: moduleLabel,
      selection: selection,
      records: records,
      columns: columns,
      dateResolver: dateResolver,
      cityLogoBytes: branding.cityLogo,
      healthOfficeLogoBytes: branding.healthOfficeLogo,
      barangayLogoBytes: branding.barangayLogo,
    ),
  );
}

// Top-level function that can be run in an isolate
Future<List<int>> _generatePdfBytesInBackground(
  _PdfGenerationParams params,
) async {
  final fonts = await loadPdfFontBundle();
  final pdf = pw.Document(
    theme: pw.ThemeData.withFont(
      base: fonts.base,
      bold: fonts.bold,
      italic: fonts.italic,
      boldItalic: fonts.boldItalic,
    ),
  );

  final generatedAt = DateTime.now();
  final reportTitle = _buildOfficialReportTitle(
    params.moduleLabel,
    params.selection.period,
  );
  final reportReference = _buildReportReference(
    params.moduleLabel,
    params.selection,
    generatedAt,
  );
  final aggregation = _summarizeRecords(
    params.records,
    params.moduleLabel,
    params.dateResolver,
  );
  final cityLogo = params.cityLogoBytes == null
      ? null
      : pw.MemoryImage(Uint8List.fromList(params.cityLogoBytes!));
  final healthOfficeLogo = params.healthOfficeLogoBytes == null
      ? null
      : pw.MemoryImage(Uint8List.fromList(params.healthOfficeLogoBytes!));
  final barangayLogo = params.barangayLogoBytes == null
      ? null
      : pw.MemoryImage(Uint8List.fromList(params.barangayLogoBytes!));

  pdf.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4.landscape,
      margin: const pw.EdgeInsets.fromLTRB(28, 32, 28, 26),
      footer: (context) => _buildReportFooter(context, generatedAt),
      build: (context) => [
        _buildReportHeader(
          reportTitle: reportTitle,
          selection: params.selection,
          generatedAt: generatedAt,
          reportReference: reportReference,
          cityLogo: cityLogo,
          healthOfficeLogo: healthOfficeLogo,
          barangayLogo: barangayLogo,
        ),
        _buildReportIdentityBlock(
          moduleLabel: params.moduleLabel,
          reportTitle: reportTitle,
          selection: params.selection,
          generatedAt: generatedAt,
          reportReference: reportReference,
        ),
        pw.SizedBox(height: 12),
        _buildSummarySection(
          moduleLabel: params.moduleLabel,
          selection: params.selection,
          aggregation: aggregation,
        ),
        pw.SizedBox(height: 14),
        _buildSectionHeading(
          'II. Main Records Table',
          '${params.moduleLabel} records arranged for official reporting and print submission.',
        ),
        pw.SizedBox(height: 8),
        _buildRecordsTable(context, params.records, params.columns),
        pw.SizedBox(height: 14),
        _buildSectionHeading(
          'III. Totals / Aggregated Data',
          'Consolidated figures derived from the selected reporting period.',
        ),
        pw.SizedBox(height: 8),
        _buildTotalsSection(aggregation),
        pw.SizedBox(height: 14),
        _buildSectionHeading(
          'IV. Remarks / Notes',
          'Administrative remarks and system notice for the generated report.',
        ),
        pw.SizedBox(height: 8),
        _buildRemarksSection(params.selection.remarks),
      ],
    ),
  );

  pdf.addPage(
    buildOfficialReportSignaturePage(
      pageFormat: PdfPageFormat.a4.landscape,
      signatures: [
        OfficialReportSignature(
          title: 'Barangay Captain',
          printedName: params.selection.approvedBy,
          position: params.selection.approvedByPosition,
        ),
        OfficialReportSignature(
          title: 'Barangay Kagawad in Health',
          printedName: params.selection.reviewedBy,
          position: params.selection.reviewedByPosition,
        ),
        OfficialReportSignature(
          title: 'BHW Head',
          printedName: params.selection.bhwHead,
          position: params.selection.bhwHeadPosition,
        ),
        OfficialReportSignature(
          title: 'BHW Assigned on Duty',
          printedName: params.selection.preparedBy,
          position: params.selection.preparedByPosition,
        ),
      ],
      footerText:
          'System-generated by Barangay Health Worker Information System',
    ),
  );

  return pdf.save();
}

List<int> _buildFormalBhwReportExcelBytes({
  required String moduleLabel,
  required _ReportSelection selection,
  required List<Map<String, dynamic>> records,
  required List<ReportCsvColumn> columns,
  required DateTime? Function(Map<String, dynamic> record) dateResolver,
  required ReportBranding branding,
}) {
  final generatedAt = DateTime.now();
  final reportTitle = _buildOfficialReportTitle(moduleLabel, selection.period);
  final reportReference = _buildReportReference(
    moduleLabel,
    selection,
    generatedAt,
  );
  final aggregation = _summarizeRecords(records, moduleLabel, dateResolver);
  final recordRows = records.asMap().entries.map((entry) {
    final cells = <String>[
      _excelCell('${entry.key + 1}', center: true),
      ...columns.map(
        (column) => _excelCell(
          _sanitizeTableCell(column.valueBuilder(entry.value)),
          center: column.center,
        ),
      ),
    ];
    return '<tr>${cells.join()}</tr>';
  }).join();
  final headerCells = [
    _excelCell('No.', header: true, center: true),
    ...columns.map(
      (column) =>
          _excelCell(column.header, header: true, center: column.center),
    ),
  ];
  final summaryRows =
      [
        ['Total Records', aggregation.totalRecords.toString()],
        ['Unique Patients / Subjects', aggregation.uniqueSubjects.toString()],
        [
          'Coverage Window',
          _dateSpanLabel(aggregation.earliestDate, aggregation.latestDate),
        ],
        ['Sex Distribution', _summarizeSexCounts(aggregation.sexCounts)],
        ['Status Snapshot', _summarizeTopCounts(aggregation.statusCounts)],
        [
          aggregation.primaryLabel,
          _summarizeTopCounts(aggregation.primaryCounts),
        ],
      ].map((row) {
        return '<tr>${_excelCell(row[0], header: true)}${_excelCell(row[1])}</tr>';
      }).join();

  final html =
      '''
<!DOCTYPE html>
<html xmlns:o="urn:schemas-microsoft-com:office:office"
      xmlns:x="urn:schemas-microsoft-com:office:excel"
      xmlns="http://www.w3.org/TR/REC-html40">
<head>
  <meta charset="utf-8">
  <meta name="Generator" content="AI-DSUHIS">
  <!-- Excel-compatible print settings: landscape, repeating table header. -->
  <style>
    @page { size: landscape; margin: 0.45in; }
    body { font-family: Arial, sans-serif; color: #000000; font-size: 10pt; }
    table { border-collapse: collapse; width: 100%; }
    .header-table { border: 0; margin-bottom: 10px; }
    .header-table td { border: 0; vertical-align: middle; }
    .seal { width: 58px; height: 58px; object-fit: contain; }
    .seal-cell { width: 76px; text-align: center; }
    .seal-label { display: block; font-size: 6pt; font-weight: bold; color: #000000; }
    .identity { text-align: center; }
    .province { font-size: 8pt; font-weight: bold; color: #000000; letter-spacing: 0.5px; }
    .city { font-size: 16pt; font-weight: bold; color: #000000; letter-spacing: 1px; }
    .program { font-size: 9pt; font-weight: bold; color: #000000; letter-spacing: 1px; }
    .system { font-size: 8pt; font-weight: bold; color: #000000; }
    .control { border: 0; padding: 7px; font-size: 8pt; }
    .title { font-size: 15pt; font-weight: bold; color: #000000; border-top: 1px solid #000000; padding-top: 8px; }
    .subtitle { color: #000000; padding: 3px 0 10px; }
    .section { background: #FFFFFF; color: #000000; font-weight: bold; padding: 6px 0; border-bottom: 1px solid #000000; }
    .summary { margin: 0 0 12px; }
    .summary td, .summary th, .records td, .records th, .signatures td { border: 1px solid #000000; padding: 6px; vertical-align: top; }
    .summary th { background: #FFFFFF; color: #000000; text-align: left; width: 28%; }
    .records { table-layout: fixed; page-break-inside: auto; }
    .records thead { display: table-header-group; }
    .records tr { page-break-inside: avoid; }
    .records th { background: #FFFFFF; color: #000000; font-weight: bold; text-align: left; border-bottom: 2px solid #000000; }
    .records td { word-wrap: break-word; white-space: normal; }
    .records tr:nth-child(even) td { background: #FFFFFF; }
    .center { text-align: center; }
    .notes { border: 1px solid #000000; background: #FFFFFF; padding: 8px; }
    .signatures { margin-top: 10px; table-layout: fixed; }
    .signature-line { display: block; border-bottom: 1px solid #000000; height: 22px; }
    .signature-label { font-size: 8pt; color: #000000; }
    .footer { color: #000000; font-size: 8pt; border-top: 1px solid #000000; padding-top: 6px; margin-top: 12px; }
  </style>
</head>
<body>
  <table class="header-table">
    <tr>
      <td class="seal-cell">${_excelImage(branding.cityLogo, 'Malaybalay City seal')}<span class="seal-label">MALAYBALAY CITY</span></td>
      <td class="seal-cell">${_excelImage(branding.healthOfficeLogo, 'City Health Office seal')}<span class="seal-label">CITY HEALTH OFFICE</span></td>
      <td class="seal-cell">${_excelImage(branding.barangayLogo, 'Barangay seal')}<span class="seal-label">${_escapeHtml(selection.barangayName)}</span></td>
      <td class="identity">
        <div class="province">REPUBLIC OF THE PHILIPPINES • PROVINCE OF BUKIDNON</div>
        <div class="city">CITY OF MALAYBALAY</div>
        <div class="program">SAKA TA MALAYBALAY</div>
        <div class="system">BARANGAY HEALTH WORKER INFORMATION SYSTEM</div>
      </td>
      <td class="control">REPORT CONTROL<br><b>${_escapeHtml(reportReference)}</b><br>${_escapeHtml(_formatFormalDateTime(generatedAt))}</td>
    </tr>
  </table>
  <div class="title">${_escapeHtml(reportTitle)}</div>
  <div class="subtitle">Barangay: ${_escapeHtml(selection.barangayName)} &nbsp; | &nbsp; Reporting Period: ${_escapeHtml(selection.scopeLabel)}</div>

  <table class="summary">
    <tr><td class="section" colspan="2">I. REPORT IDENTIFICATION AND SUMMARY</td></tr>
    <tr><th>Report Type</th><td>${_escapeHtml(selection.period.label)} Report</td></tr>
    <tr><th>Module</th><td>${_escapeHtml(moduleLabel)}</td></tr>
    <tr><th>BHW Assigned on Duty</th><td>${_escapeHtml(selection.preparedBy)} (${_escapeHtml(selection.preparedByPosition)})</td></tr>
    <tr><th>Generated</th><td>${_escapeHtml(_formatFormalDateTime(generatedAt))}</td></tr>
    $summaryRows
  </table>

  <table class="records">
    <thead><tr>${headerCells.join()}</tr></thead>
    <tbody>$recordRows</tbody>
  </table>

  <table class="summary" style="margin-top:12px;">
    <tr><td class="section" colspan="2">III. REMARKS / NOTES</td></tr>
    <tr><td class="notes" colspan="2">${_escapeHtml(selection.remarks)}<br><br><span class="signature-label">System notice: Review the encoded values before filing or submission.</span></td></tr>
  </table>
  <table class="signatures">
    <tr>
      ${_excelSignatureCell('Barangay Captain', selection.approvedBy, selection.approvedByPosition)}
      ${_excelSignatureCell('Barangay Kagawad in Health', selection.reviewedBy, selection.reviewedByPosition)}
      ${_excelSignatureCell('BHW Head', selection.bhwHead, selection.bhwHeadPosition)}
      ${_excelSignatureCell('BHW Assigned on Duty', selection.preparedBy, selection.preparedByPosition)}
    </tr>
  </table>
  <div class="footer">Generated by AI-DSUHIS • Confidential health information</div>
</body>
</html>
''';

  return utf8.encode(html);
}

String _excelCell(String value, {bool header = false, bool center = false}) {
  final classes = [if (center) 'center'];
  return '<${header ? 'th' : 'td'}${classes.isEmpty ? '' : ' class="${classes.join(' ')}"'}>${_escapeHtml(value)}</${header ? 'th' : 'td'}>';
}

String _excelSignatureCell(String label, String name, String position) {
  return '<td><b>${_escapeHtml(label.toUpperCase())}</b><br><span class="signature-line"></span><span class="signature-label">Printed Name: ${_escapeHtml(name.isEmpty ? ' ' : name)}<br>Position: ${_escapeHtml(position)}</span></td>';
}

String _excelImage(Uint8List? bytes, String alt) {
  if (bytes == null || bytes.isEmpty) {
    return '<span class="seal-label">SEAL</span>';
  }
  final mime = bytes.length > 1 && bytes[0] == 0xFF && bytes[1] == 0xD8
      ? 'image/jpeg'
      : 'image/png';
  return '<img class="seal" alt="${_escapeHtml(alt)}" src="data:$mime;base64,${base64Encode(bytes)}">';
}

String _escapeHtml(String value) {
  return value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#39;');
}

pw.Widget _buildReportHeader({
  required String reportTitle,
  required _ReportSelection selection,
  required DateTime generatedAt,
  required String reportReference,
  required pw.MemoryImage? cityLogo,
  required pw.MemoryImage? healthOfficeLogo,
  required pw.MemoryImage? barangayLogo,
}) {
  return buildOfficialReportHeader(
    title: reportTitle,
    systemName: 'BARANGAY HEALTH WORKER INFORMATION SYSTEM',
    subtitle: 'Reporting Period: ${selection.scopeLabel}',
    barangayName: selection.barangayName,
    generatedAt: generatedAt,
    reportReference: reportReference,
    cityLogo: cityLogo,
    healthOfficeLogo: healthOfficeLogo,
    barangayLogo: barangayLogo,
  );
}

pw.Widget _buildReportFooter(pw.Context context, DateTime generatedAt) {
  return buildOfficialReportFooter(
    context,
    footerText:
        'System-generated by Barangay Health Worker Information System  •  Generated: ${_formatFormalDateTime(generatedAt)}',
  );
}

pw.Widget _buildReportIdentityBlock({
  required String moduleLabel,
  required String reportTitle,
  required _ReportSelection selection,
  required DateTime generatedAt,
  required String reportReference,
}) {
  final entries = <MapEntry<String, String>>[
    MapEntry('Report Title', reportTitle),
    MapEntry('Report Type', '${selection.period.label} Report'),
    MapEntry('Module', moduleLabel),
    MapEntry('Reporting Period', selection.scopeLabel),
    MapEntry('Barangay Name', selection.barangayName),
    MapEntry('Date Generated', _formatFormalDateTime(generatedAt)),
    MapEntry('BHW Assigned on Duty', selection.preparedBy),
    MapEntry('Reference No.', reportReference),
  ];

  return pw.Container(
    width: double.infinity,
    padding: const pw.EdgeInsets.all(16),
    decoration: const pw.BoxDecoration(
      border: pw.Border(
        top: pw.BorderSide(color: PdfColors.black),
        bottom: pw.BorderSide(color: PdfColors.black),
      ),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'I. Report Identification',
          style: pw.TextStyle(
            fontSize: 12.5,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.black,
          ),
        ),
        pw.SizedBox(height: 6),
        pw.Text(
          'Formal print-ready summary for barangay or health office submission.',
          style: pw.TextStyle(fontSize: 9, color: PdfColors.black),
        ),
        pw.SizedBox(height: 10),
        pw.Wrap(
          spacing: 10,
          runSpacing: 10,
          children: entries
              .map((entry) => _buildMetaCard(entry.key, entry.value))
              .toList(),
        ),
      ],
    ),
  );
}

pw.Widget _buildMetaCard(String label, String value) {
  return pw.Container(
    width: 188,
    padding: const pw.EdgeInsets.all(10),
    decoration: const pw.BoxDecoration(
      border: pw.Border(bottom: pw.BorderSide(color: PdfColors.black)),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          label.toUpperCase(),
          style: pw.TextStyle(
            fontSize: 7.2,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.black,
            letterSpacing: 0.55,
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          value,
          style: pw.TextStyle(
            fontSize: 9.5,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.black,
          ),
        ),
      ],
    ),
  );
}

pw.Widget _buildSummarySection({
  required String moduleLabel,
  required _ReportSelection selection,
  required _ReportAggregation aggregation,
}) {
  final topPrimary = _summarizeTopCounts(aggregation.primaryCounts);
  final statusSummary = _summarizeTopCounts(aggregation.statusCounts);
  final sexSummary = _summarizeSexCounts(aggregation.sexCounts);
  final dateSpan = _dateSpanLabel(
    aggregation.earliestDate,
    aggregation.latestDate,
  );
  final summaryText =
      'This ${selection.period.label.toLowerCase()} ${moduleLabel.toLowerCase()} report covers ${aggregation.totalRecords} encoded record${aggregation.totalRecords == 1 ? '' : 's'} for ${selection.scopeLabel}. '
      'The report is arranged in an official tabular format for barangay and health office submission, with totals and signatory sections prepared for printing.';

  return pw.Container(
    width: double.infinity,
    padding: const pw.EdgeInsets.all(16),
    decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.black)),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _buildSectionHeading(
          'I.A Summary',
          'Overview of the selected report coverage and encoded totals.',
          includeBottomDivider: false,
        ),
        pw.SizedBox(height: 8),
        pw.Text(
          summaryText,
          style: pw.TextStyle(
            fontSize: 9.2,
            color: PdfColors.black,
            height: 1.35,
          ),
        ),
        pw.SizedBox(height: 10),
        pw.Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _buildSummaryCard(
              'Total Records',
              aggregation.totalRecords.toString(),
            ),
            _buildSummaryCard(
              'Unique Patients / Subjects',
              aggregation.uniqueSubjects.toString(),
            ),
            _buildSummaryCard('Coverage Window', dateSpan),
            _buildSummaryCard('Sex Distribution', sexSummary),
            _buildSummaryCard('Status Snapshot', statusSummary),
            _buildSummaryCard(aggregation.primaryLabel, topPrimary),
          ],
        ),
      ],
    ),
  );
}

pw.Widget _buildSummaryCard(String label, String value) {
  return pw.Container(
    width: 190,
    padding: const pw.EdgeInsets.all(10),
    decoration: const pw.BoxDecoration(
      border: pw.Border(bottom: pw.BorderSide(color: PdfColors.black)),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          label.toUpperCase(),
          style: pw.TextStyle(
            fontSize: 7,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.black,
            letterSpacing: 0.55,
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          value,
          style: pw.TextStyle(
            fontSize: 9.2,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.black,
          ),
        ),
      ],
    ),
  );
}

pw.Widget _buildSectionHeading(
  String title,
  String subtitle, {
  bool includeBottomDivider = true,
}) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(
        title,
        style: pw.TextStyle(
          fontSize: 12,
          fontWeight: pw.FontWeight.bold,
          color: PdfColors.black,
        ),
      ),
      pw.SizedBox(height: 4),
      pw.Text(
        subtitle,
        style: pw.TextStyle(fontSize: 8.8, color: PdfColors.black),
      ),
      if (includeBottomDivider) ...[
        pw.SizedBox(height: 6),
        pw.Container(height: 1, color: PdfColors.black),
      ],
    ],
  );
}

pw.Widget _buildRecordsTable(
  pw.Context context,
  List<Map<String, dynamic>> records,
  List<ReportCsvColumn> columns,
) {
  final headers = ['No.', ...columns.map((column) => column.header)];
  final columnWidths = <int, pw.TableColumnWidth>{
    0: const pw.FixedColumnWidth(28),
  };
  final alignments = <int, pw.Alignment>{0: pw.Alignment.center};

  for (var index = 0; index < columns.length; index++) {
    columnWidths[index + 1] = pw.FlexColumnWidth(columns[index].flex);
    alignments[index + 1] = columns[index].center
        ? pw.Alignment.center
        : pw.Alignment.centerLeft;
  }

  final data = records.asMap().entries.map((entry) {
    final row = <String>['${entry.key + 1}'];
    for (final column in columns) {
      row.add(_sanitizeTableCell(column.valueBuilder(entry.value)));
    }
    return row;
  }).toList();

  return pw.TableHelper.fromTextArray(
    context: context,
    headers: headers,
    data: data,
    columnWidths: columnWidths,
    headerAlignments: alignments,
    cellAlignments: alignments,
    headerDecoration: const pw.BoxDecoration(color: PdfColors.white),
    rowDecoration: const pw.BoxDecoration(color: PdfColors.white),
    oddRowDecoration: const pw.BoxDecoration(color: PdfColors.white),
    border: pw.TableBorder(
      top: pw.BorderSide(color: PdfColors.black),
      bottom: pw.BorderSide(color: PdfColors.black),
      left: pw.BorderSide(color: PdfColors.black),
      right: pw.BorderSide(color: PdfColors.black),
      horizontalInside: pw.BorderSide(color: PdfColors.black),
      verticalInside: pw.BorderSide(color: PdfColors.black),
    ),
    headerStyle: pw.TextStyle(
      fontSize: 10.5,
      fontWeight: pw.FontWeight.bold,
      color: PdfColors.black,
    ),
    cellStyle: pw.TextStyle(
      fontSize: 9.5,
      color: PdfColors.black,
      height: 1.25,
    ),
    oddCellStyle: pw.TextStyle(
      fontSize: 9.5,
      color: PdfColors.black,
      height: 1.25,
    ),
    headerPadding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 8),
    cellPadding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 7),
    cellHeight: 0,
    headerHeight: 0,
  );
}

pw.Widget _buildTotalsSection(_ReportAggregation aggregation) {
  final entries = <MapEntry<String, String>>[
    MapEntry('Total Encoded Records', aggregation.totalRecords.toString()),
    MapEntry(
      'Unique Patients / Subjects',
      aggregation.uniqueSubjects.toString(),
    ),
    MapEntry(
      'Date Span of Encoded Records',
      _dateSpanLabel(aggregation.earliestDate, aggregation.latestDate),
    ),
    MapEntry('Sex Distribution', _summarizeSexCounts(aggregation.sexCounts)),
    MapEntry(
      'Status Distribution',
      _summarizeTopCounts(aggregation.statusCounts),
    ),
    MapEntry(
      aggregation.primaryLabel,
      _summarizeTopCounts(aggregation.primaryCounts),
    ),
  ];

  return pw.Container(
    width: double.infinity,
    decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.black)),
    child: pw.Table(
      border: pw.TableBorder.symmetric(
        inside: pw.BorderSide(color: PdfColors.black),
      ),
      columnWidths: const {
        0: pw.FlexColumnWidth(1.4),
        1: pw.FlexColumnWidth(2.4),
      },
      children: entries.map((entry) {
        return pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.white),
          children: [
            pw.Container(
              padding: const pw.EdgeInsets.all(9),
              child: pw.Text(
                entry.key,
                style: pw.TextStyle(
                  fontSize: 9.5,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.black,
                ),
              ),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.all(9),
              child: pw.Text(
                entry.value,
                style: pw.TextStyle(fontSize: 9.5, color: PdfColors.black),
              ),
            ),
          ],
        );
      }).toList(),
    ),
  );
}

pw.Widget _buildRemarksSection(String remarks) {
  return pw.Container(
    width: double.infinity,
    padding: const pw.EdgeInsets.all(12),
    decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.black)),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          remarks,
          style: pw.TextStyle(
            fontSize: 9,
            color: PdfColors.black,
            height: 1.35,
          ),
        ),
        pw.SizedBox(height: 8),
        pw.Text(
          'System notice: This document is generated from the encoded BHW database and should be reviewed before final submission.',
          style: pw.TextStyle(fontSize: 8.2, color: PdfColors.black),
        ),
      ],
    ),
  );
}

_ReportAggregation _summarizeRecords(
  List<Map<String, dynamic>> records,
  String moduleLabel,
  DateTime? Function(Map<String, dynamic> record) dateResolver,
) {
  final uniqueSubjects = <String>{};
  final sexCounts = <String, int>{};
  final statusCounts = <String, int>{};
  final primaryCounts = <String, int>{};

  DateTime? earliestDate;
  DateTime? latestDate;

  for (final record in records) {
    final recordDate = dateResolver(record);
    if (recordDate != null) {
      earliestDate = earliestDate == null || recordDate.isBefore(earliestDate)
          ? recordDate
          : earliestDate;
      latestDate = latestDate == null || recordDate.isAfter(latestDate)
          ? recordDate
          : latestDate;
    }

    final subject = _firstNonEmptyValue(record, const [
      'patientId',
      'linkedPatientId',
      'patientName',
      'patient',
      'name',
      'id',
    ]);
    if (subject.isNotEmpty) {
      uniqueSubjects.add(subject.toLowerCase());
    }

    final sexValue = _normalizedSex(
      _firstNonEmptyValue(record, const ['sex', 'gender']),
    );
    if (sexValue.isNotEmpty) {
      sexCounts[sexValue] = (sexCounts[sexValue] ?? 0) + 1;
    }

    final statusValue = _titleCase(
      _firstNonEmptyValue(record, const ['status', 'caseStatus']),
    );
    if (statusValue.isNotEmpty) {
      statusCounts[statusValue] = (statusCounts[statusValue] ?? 0) + 1;
    }

    final primaryValue = _titleCase(
      _firstNonEmptyValue(record, _primaryFieldCandidates(moduleLabel)),
    );
    if (primaryValue.isNotEmpty) {
      primaryCounts[primaryValue] = (primaryCounts[primaryValue] ?? 0) + 1;
    }
  }

  return _ReportAggregation(
    totalRecords: records.length,
    uniqueSubjects: uniqueSubjects.length,
    earliestDate: earliestDate,
    latestDate: latestDate,
    sexCounts: _sortCounts(sexCounts),
    statusCounts: _sortCounts(statusCounts),
    primaryCounts: _sortCounts(primaryCounts),
    primaryLabel: _primarySummaryLabel(moduleLabel),
  );
}

Map<String, int> _sortCounts(Map<String, int> counts) {
  final entries = counts.entries.toList()
    ..sort((a, b) {
      final compare = b.value.compareTo(a.value);
      if (compare != 0) return compare;
      return a.key.compareTo(b.key);
    });
  return {for (final entry in entries) entry.key: entry.value};
}

String _primarySummaryLabel(String moduleLabel) {
  switch (_moduleKey(moduleLabel)) {
    case 'checkup':
      return 'Top Diagnosis / Classification';
    case 'morbidity':
      return 'Top Disease / Diagnosis';
    case 'prenatal':
      return 'Top Risk Level';
    case 'immunization':
      return 'Top Vaccine';
    case 'mortality':
      return 'Top Cause of Death';
    case 'communicable':
      return 'Top Communicable Disease';
    case 'noncommunicable':
      return 'Top Non-Communicable Condition';
    case 'patient':
      return 'Top Patient Status';
    case 'barangay':
      return 'Top Barangay Category';
    default:
      return 'Top Encoded Category';
  }
}

List<String> _primaryFieldCandidates(String moduleLabel) {
  switch (_moduleKey(moduleLabel)) {
    case 'checkup':
      return const ['diagnosis', 'diseaseType', 'ai_category', 'type'];
    case 'morbidity':
      return const ['disease', 'diagnosis', 'caseClassification'];
    case 'prenatal':
      return const ['riskLevel', 'status'];
    case 'immunization':
      return const ['vaccine', 'status'];
    case 'mortality':
      return const ['causeOfDeath', 'place'];
    case 'communicable':
      return const ['disease', 'condition', 'diagnosis', 'caseClassification'];
    case 'noncommunicable':
      return const ['disease', 'condition', 'diagnosis', 'caseClassification'];
    case 'patient':
      return const ['status', 'barangay'];
    case 'barangay':
      return const ['recordType', 'barangayName', 'barangay'];
    default:
      return const ['status', 'type'];
  }
}

String _moduleKey(String moduleLabel) {
  return moduleLabel.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
}

String _buildOfficialReportTitle(String moduleLabel, ReportPeriod period) {
  switch (_moduleKey(moduleLabel)) {
    case 'checkup':
      switch (period) {
        case ReportPeriod.monthly:
          return 'Monthly Check-up Accomplishment Report';
        case ReportPeriod.quarterly:
          return 'Quarterly Check-up Accomplishment Report';
        case ReportPeriod.yearly:
          return 'Yearly Check-up Consolidated Report';
      }
    case 'morbidity':
      switch (period) {
        case ReportPeriod.monthly:
          return 'Monthly Morbidity Case Report';
        case ReportPeriod.quarterly:
          return 'Quarterly Morbidity Surveillance Report';
        case ReportPeriod.yearly:
          return 'Yearly Morbidity Consolidated Report';
      }
    case 'prenatal':
      switch (period) {
        case ReportPeriod.monthly:
          return 'Monthly Prenatal Care Monitoring Report';
        case ReportPeriod.quarterly:
          return 'Quarterly Prenatal Service Accomplishment Report';
        case ReportPeriod.yearly:
          return 'Yearly Prenatal Care Consolidated Report';
      }
    case 'immunization':
      switch (period) {
        case ReportPeriod.monthly:
          return 'Monthly Immunization Accomplishment Report';
        case ReportPeriod.quarterly:
          return 'Quarterly Immunization Coverage Report';
        case ReportPeriod.yearly:
          return 'Yearly Immunization Consolidated Report';
      }
    case 'communicable':
      switch (period) {
        case ReportPeriod.monthly:
          return 'Monthly Communicable Disease Report';
        case ReportPeriod.quarterly:
          return 'Quarterly Communicable Disease Surveillance Report';
        case ReportPeriod.yearly:
          return 'Yearly Communicable Disease Consolidated Report';
      }
    case 'noncommunicable':
      switch (period) {
        case ReportPeriod.monthly:
          return 'Monthly Non-Communicable Disease Report';
        case ReportPeriod.quarterly:
          return 'Quarterly Non-Communicable Disease Surveillance Report';
        case ReportPeriod.yearly:
          return 'Yearly Non-Communicable Disease Consolidated Report';
      }
    case 'patient':
      switch (period) {
        case ReportPeriod.monthly:
          return 'Monthly Patient Registry Report';
        case ReportPeriod.quarterly:
          return 'Quarterly Patient Registry Summary Report';
        case ReportPeriod.yearly:
          return 'Yearly Patient Registry Consolidated Report';
      }
    case 'barangay':
      switch (period) {
        case ReportPeriod.monthly:
          return 'Monthly Barangay Health Profile Report';
        case ReportPeriod.quarterly:
          return 'Quarterly Barangay Health Situation Report';
        case ReportPeriod.yearly:
          return 'Yearly Barangay Health Profile Report';
      }
    default:
      return '${period.label} $moduleLabel Report';
  }
}

String _buildReportReference(
  String moduleLabel,
  _ReportSelection selection,
  DateTime generatedAt,
) {
  final moduleToken = _slugify(moduleLabel).toUpperCase();
  final dateToken = DateFormat('yyyyMMdd_HHmmss').format(generatedAt);
  return 'BHW-$moduleToken-${selection.filenameToken.toUpperCase()}-$dateToken';
}

String _sanitizeTableCell(String value) {
  final sanitized = value
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .replaceAll(RegExp(r'\n{2,}'), '\n')
      .trim();
  return sanitized.isEmpty ? 'N/A' : sanitized;
}

String _deriveDefaultBarangayName(List<Map<String, dynamic>> records) {
  final counts = <String, int>{};
  for (final record in records) {
    final value = _firstNonEmptyValue(record, const [
      'barangay',
      'barangayName',
    ]);
    if (value.isEmpty) continue;
    counts[value] = (counts[value] ?? 0) + 1;
  }

  if (counts.isEmpty) {
    return 'Barangay 03';
  }

  final sorted = counts.entries.toList()
    ..sort((a, b) {
      final compare = b.value.compareTo(a.value);
      if (compare != 0) return compare;
      return a.key.compareTo(b.key);
    });
  return sorted.first.key;
}

String _firstNonEmptyValue(Map<String, dynamic> record, List<String> keys) {
  for (final key in keys) {
    final direct = _cleanFieldValue(record[key]?.toString() ?? '');
    if (direct.isNotEmpty && direct != 'N/A') return direct;
  }

  final nested = record['sourceRecord'];
  if (nested is Map) {
    final nestedMap = Map<String, dynamic>.from(nested);
    for (final key in keys) {
      final value = _cleanFieldValue(nestedMap[key]?.toString() ?? '');
      if (value.isNotEmpty && value != 'N/A') return value;
    }
  }

  return '';
}

String _normalizedSex(String value) {
  final lower = value.trim().toLowerCase();
  if (lower.isEmpty) return '';
  if (lower == 'm' || lower == 'male') return 'Male';
  if (lower == 'f' || lower == 'female') return 'Female';
  return _titleCase(value);
}

String _summarizeTopCounts(Map<String, int> counts) {
  if (counts.isEmpty) return 'No encoded data';

  return counts.entries
      .take(4)
      .map((entry) => '${entry.key} (${entry.value})')
      .join(', ');
}

String _summarizeSexCounts(Map<String, int> counts) {
  if (counts.isEmpty) return 'No encoded data';

  final male = counts['Male'] ?? 0;
  final female = counts['Female'] ?? 0;
  final other = counts.entries
      .where((entry) => entry.key != 'Male' && entry.key != 'Female')
      .fold<int>(0, (total, entry) => total + entry.value);

  final parts = <String>[];
  if (male > 0) parts.add('Male ($male)');
  if (female > 0) parts.add('Female ($female)');
  if (other > 0) parts.add('Others / Unspecified ($other)');

  return parts.isEmpty ? 'No encoded data' : parts.join(', ');
}

String _dateSpanLabel(DateTime? start, DateTime? end) {
  if (start == null && end == null) return 'No valid dates';
  if (start == null) return _formatFormalDate(end!);
  if (end == null) return _formatFormalDate(start);
  if (start.year == end.year &&
      start.month == end.month &&
      start.day == end.day) {
    return _formatFormalDate(start);
  }
  return '${_formatFormalDate(start)} to ${_formatFormalDate(end)}';
}

String _defaultPreparedBy() {
  final user = FirebaseAuth.instance.currentUser;
  final displayName = user?.displayName?.trim() ?? '';
  if (displayName.isNotEmpty) return displayName;

  final email = user?.email?.trim() ?? '';
  if (email.isNotEmpty) {
    return email.split('@').first;
  }

  return 'BHW Staff';
}

String _roleToPosition(String role, {required String fallback}) {
  final normalized = role.trim().toLowerCase();
  if (normalized == 'cho') return 'City Health Office Staff';
  if (normalized == 'bhw') return 'BHW Assigned on Duty';
  return fallback;
}

String _cleanFieldValue(String value, {String fallback = ''}) {
  final cleaned = value.trim();
  if (cleaned.isEmpty) return fallback;
  if (cleaned.toLowerCase() == 'null' || cleaned.toLowerCase() == 'undefined') {
    return fallback;
  }
  return cleaned;
}

String _titleCase(String value) {
  final cleaned = value.trim();
  if (cleaned.isEmpty) return '';
  return cleaned
      .split(RegExp(r'\s+'))
      .map((part) {
        if (part.isEmpty) return part;
        return '${part[0].toUpperCase()}${part.substring(1)}';
      })
      .join(' ');
}

String _formatFormalDate(DateTime value) {
  return DateFormat('MMMM dd, yyyy').format(value);
}

String _formatFormalDateTime(DateTime value) {
  return DateFormat('MMMM dd, yyyy  hh:mm a').format(value);
}
