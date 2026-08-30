import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:mycapstone_project/firebase_helper.dart';
import 'package:mycapstone_project/shared/barangay_scope_utils.dart';
import 'package:mycapstone_project/shared/official_report_layout.dart';
import 'package:mycapstone_project/web/roles/bhw/checkups/checkup_database_helper.dart';
import 'package:mycapstone_project/web/roles/bhw/immunization/immunization_database_helper.dart';
import 'package:mycapstone_project/web/roles/bhw/surveillance/mortality_database_helper.dart';
import 'package:mycapstone_project/web/roles/bhw/patients/patient_database_helper.dart';
import 'package:mycapstone_project/web/roles/bhw/prenatal/prenatal_database_helper.dart';
import 'package:mycapstone_project/web/shared/services/user_access_scope_service.dart';
import 'package:mycapstone_project/web/shared/utils/file_download.dart';
import 'package:mycapstone_project/web/shared/utils/pdf_fonts.dart';
import 'package:mycapstone_project/web/shared/utils/report_branding.dart';
import 'package:mycapstone_project/web/shared/utils/report_generation.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:mycapstone_project/web/shared/theme/app_theme.dart';
import 'package:mycapstone_project/web/shared/components/app_buttons.dart';

const Color _launcherPrimaryAqua = AppColors.primary;
const Color _launcherDarkDeepTeal = AppColors.backgroundDark;
const Color _launcherSidebarDark = AppColors.surfaceDark;
const Color _launcherMutedCoolGray = AppColors.textOnDarkMuted;

enum DashboardReportType {
  checkup,
  prenatal,
  immunization,
  communicable,
  nonCommunicable,
  mortality,
  morbidity,
  patientRecords,
}

class _DashboardReportOption {
  final DashboardReportType type;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;

  const _DashboardReportOption({
    required this.type,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
  });
}

class _DashboardReportPayload {
  final String moduleLabel;
  final List<Map<String, dynamic>> records;
  final DateTime? Function(Map<String, dynamic> record) dateResolver;
  final List<ReportCsvColumn> columns;
  final String Function(Map<String, dynamic> record, int index)?
  sectionTitleBuilder;

  const _DashboardReportPayload({
    required this.moduleLabel,
    required this.records,
    required this.dateResolver,
    required this.columns,
    this.sectionTitleBuilder,
  });
}

class _OverallReportSelection {
  final ReportPeriod period;
  final int month;
  final int year;
  final String barangay;
  final String municipality;
  final String province;

  const _OverallReportSelection({
    required this.period,
    required this.month,
    required this.year,
    required this.barangay,
    required this.municipality,
    required this.province,
  });

  int get quarter => ((month - 1) ~/ 3) + 1;

  String get scopeLabel {
    switch (period) {
      case ReportPeriod.monthly:
        return DateFormat.yMMMM().format(DateTime(year, month));
      case ReportPeriod.quarterly:
        final startLabel = DateFormat.MMM().format(DateTime(year, month));
        final endLabel = DateFormat.MMM().format(DateTime(year, month + 2));
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

class _OverallReportData {
  final List<Map<String, dynamic>> checkups;
  final List<Map<String, dynamic>> prenatal;
  final List<Map<String, dynamic>> immunizations;
  final List<Map<String, dynamic>> patients;
  final List<Map<String, dynamic>> communicable;
  final List<Map<String, dynamic>> nonCommunicable;
  final List<Map<String, dynamic>> morbidity;
  final List<Map<String, dynamic>> mortality;

  const _OverallReportData({
    required this.checkups,
    required this.prenatal,
    required this.immunizations,
    required this.patients,
    required this.communicable,
    required this.nonCommunicable,
    required this.morbidity,
    required this.mortality,
  });
}

class _DateRange {
  final DateTime start;
  final DateTime end;

  const _DateRange({required this.start, required this.end});
}

class _SexMetricRow {
  final String indicator;
  final int male;
  final int female;
  final int total;
  final String remarks;

  const _SexMetricRow({
    required this.indicator,
    required this.male,
    required this.female,
    required this.total,
    this.remarks = '',
  });
}

class _AgeMetricRow {
  final String indicator;
  final int age10to14;
  final int age15to19;
  final int age20to49;
  final int total;
  final String remarks;

  const _AgeMetricRow({
    required this.indicator,
    required this.age10to14,
    required this.age15to19,
    required this.age20to49,
    required this.total,
    this.remarks = '',
  });
}

const List<_DashboardReportOption> _dashboardReportOptions = [
  _DashboardReportOption(
    type: DashboardReportType.checkup,
    title: 'Check-up',
    subtitle: 'Clinical encounters and action taken',
    icon: Icons.assignment_turned_in_rounded,
    accent: Color(0xFF22D3EE),
  ),
  _DashboardReportOption(
    type: DashboardReportType.prenatal,
    title: 'Prenatal',
    subtitle: 'Maternal monitoring and due dates',
    icon: Icons.pregnant_woman_rounded,
    accent: Color(0xFFF97316),
  ),
  _DashboardReportOption(
    type: DashboardReportType.immunization,
    title: 'Immunization',
    subtitle: 'Vaccines, doses, and schedule status',
    icon: Icons.vaccines_rounded,
    accent: Color(0xFF10B981),
  ),
  _DashboardReportOption(
    type: DashboardReportType.communicable,
    title: 'Communicable',
    subtitle: 'Infectious and transmissible cases',
    icon: Icons.coronavirus_rounded,
    accent: Color(0xFFEF4444),
  ),
  _DashboardReportOption(
    type: DashboardReportType.nonCommunicable,
    title: 'Non-Communicable',
    subtitle: 'Chronic and non-infectious cases',
    icon: Icons.health_and_safety_rounded,
    accent: Color(0xFF8B5CF6),
  ),
  _DashboardReportOption(
    type: DashboardReportType.mortality,
    title: 'Mortality',
    subtitle: 'Deaths, causes, and verification status',
    icon: Icons.monitor_heart_rounded,
    accent: Color(0xFFF59E0B),
  ),
  _DashboardReportOption(
    type: DashboardReportType.morbidity,
    title: 'Morbidity',
    subtitle: 'Disease surveillance and case follow-up',
    icon: Icons.analytics_rounded,
    accent: Color(0xFF38BDF8),
  ),
  _DashboardReportOption(
    type: DashboardReportType.patientRecords,
    title: 'Patient Records',
    subtitle: 'Registry and demographic profiles',
    icon: Icons.badge_rounded,
    accent: Color(0xFF14B8A6),
  ),
];

Future<void> showOverallHealthReportDialog({
  required BuildContext context,
}) async {
  final selection = await _showOverallSelectionDialog(context);
  if (selection == null || !context.mounted) return;

  final messenger = ScaffoldMessenger.maybeOf(context);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    useRootNavigator: true,
    builder: (_) {
      return const Center(
        child: CircularProgressIndicator(color: _launcherPrimaryAqua),
      );
    },
  );

  // Let the loader render before starting heavy data/PDF work.
  await Future<void>.delayed(const Duration(milliseconds: 16));

  try {
    final data = await _loadOverallReportData(selection);
    final pdfBytes = await _buildOverallHealthPdf(selection, data);
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }
    if (!context.mounted) return;

    final downloaded = downloadFile(
      bytes: pdfBytes,
      filename: 'overall_health_report_${selection.filenameToken}.pdf',
      mimeType: 'application/pdf',
    );

    messenger?.showSnackBar(
      SnackBar(
        content: Text(
          downloaded
              ? 'Overall ${selection.period.label.toLowerCase()} report downloaded.'
              : 'PDF generation is only supported in the web dashboard.',
        ),
        backgroundColor: downloaded ? _launcherPrimaryAqua : Colors.orange,
      ),
    );
  } catch (e) {
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }
    messenger?.showSnackBar(
      SnackBar(
        content: Text('Failed to generate overall report: $e'),
        backgroundColor: Colors.red,
      ),
    );
  }
}

Future<void> showDashboardReportLauncher({
  required BuildContext context,
}) async {
  final option = await showDialog<_DashboardReportOption>(
    context: context,
    builder: (dialogContext) {
      final theme = Theme.of(dialogContext);
      return AlertDialog(
        backgroundColor: _launcherSidebarDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        titlePadding: const EdgeInsets.fromLTRB(24, 22, 24, 0),
        contentPadding: const EdgeInsets.fromLTRB(24, 18, 24, 22),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _launcherPrimaryAqua.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.picture_as_pdf_rounded,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    'Generate Dashboard Reports',
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Choose which health module to export. The next step will ask for the reporting period and signatory details.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.white70,
                height: 1.45,
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 760,
          child: Wrap(
            spacing: 14,
            runSpacing: 14,
            children: _dashboardReportOptions
                .map(
                  (option) => _DashboardReportCard(
                    option: option,
                    onTap: () => Navigator.of(dialogContext).pop(option),
                  ),
                )
                .toList(),
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
        ],
      );
    },
  );

  if (option == null || !context.mounted) return;
  await _generateDashboardReport(context, option);
}

Future<void> _generateDashboardReport(
  BuildContext context,
  _DashboardReportOption option,
) async {
  final messenger = ScaffoldMessenger.maybeOf(context);

  showDialog<void>(
    context: context,
    barrierDismissible: false,
    useRootNavigator: true,
    builder: (_) {
      return const Center(
        child: CircularProgressIndicator(color: _launcherPrimaryAqua),
      );
    },
  );

  try {
    final payload = await _loadDashboardReportPayload(option.type);
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }
    if (!context.mounted) return;

    await generateReportPdf(
      context: context,
      moduleLabel: payload.moduleLabel,
      records: payload.records,
      dateResolver: payload.dateResolver,
      columns: payload.columns,
      accentColor: option.accent,
      dialogColor: _launcherSidebarDark,
      textColor: Colors.white,
      mutedColor: Colors.white70,
      sectionTitleBuilder: payload.sectionTitleBuilder,
    );
  } catch (e) {
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }
    messenger?.showSnackBar(
      SnackBar(
        content: Text('Failed to prepare ${option.title} report data: $e'),
        backgroundColor: Colors.red,
      ),
    );
  }
}

Future<_OverallReportSelection?> _showOverallSelectionDialog(
  BuildContext context,
) async {
  ReportPeriod selectedPeriod = ReportPeriod.monthly;
  int selectedYear = DateTime.now().year;
  int selectedMonth = DateTime.now().month;

  final barangayController = TextEditingController();
  final municipalityController = TextEditingController();
  final provinceController = TextEditingController();

  try {
    // Pre-fill from the signed-in user's own profile so the header doesn't
    // default to "Barangay Not Specified" when the report data is already
    // correctly barangay-scoped -- still user-editable, never fabricated.
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser != null) {
      try {
        final userDoc = await getFirestoreInstance()
            .collection('users')
            .doc(currentUser.uid)
            .get();
        final data = userDoc.data() ?? const <String, dynamic>{};
        barangayController.text = (data['barangay'] ?? '').toString().trim();
      } catch (_) {}
    }
    if (!context.mounted) return null;

    return await showDialog<_OverallReportSelection>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            selectedMonth = _normalizeMonthForOverallPeriod(
              selectedMonth,
              selectedPeriod,
            );

            return AlertDialog(
              backgroundColor: AppColors.surfaceLight,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
                side: const BorderSide(color: _launcherPrimaryAqua, width: 1.5),
              ),
              title: const Text(
                'Generate Overall Health Report',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              content: SizedBox(
                width: 540,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'This will generate one consolidated PDF from the homepage using the table-style layout based on your reference forms.',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 18),
                      _buildOverallDialogSection(
                        title: 'Report Scope',
                        subtitle:
                            'Choose the official reporting window for the generated PDF.',
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
                                        ? _launcherPrimaryAqua
                                        : AppColors.textSecondary,
                                  ),
                                  label: Text(period.label),
                                  labelStyle: TextStyle(
                                    color: isSelected
                                        ? AppColors.textPrimary
                                        : AppColors.textSecondary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  backgroundColor: Colors.black.withValues(
                                    alpha: 0.04,
                                  ),
                                  selectedColor: _launcherPrimaryAqua
                                      .withValues(alpha: 0.16),
                                  side: BorderSide(
                                    color: isSelected
                                        ? _launcherPrimaryAqua
                                        : AppColors.textSecondary.withValues(
                                            alpha: 0.25,
                                          ),
                                  ),
                                  onSelected: (_) {
                                    setDialogState(() {
                                      selectedPeriod = period;
                                      selectedMonth =
                                          _normalizeMonthForOverallPeriod(
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
                              _buildOverallDropdownField<int>(
                                label: selectedPeriod == ReportPeriod.quarterly
                                    ? 'Quarter'
                                    : 'Month',
                                value: selectedMonth,
                                items:
                                    _monthOptionsForOverallPeriod(
                                      selectedPeriod,
                                    ).map((month) {
                                      return DropdownMenuItem<int>(
                                        value: month,
                                        child: Text(
                                          _monthLabelForOverallPeriod(
                                            month,
                                            selectedPeriod,
                                          ),
                                        ),
                                      );
                                    }).toList(),
                                onChanged: (value) {
                                  if (value == null) return;
                                  setDialogState(() => selectedMonth = value);
                                },
                              ),
                              const SizedBox(height: 14),
                            ],
                            _buildOverallDropdownField<int>(
                              label: 'Year',
                              value: selectedYear,
                              items: _overallYearOptions().map((year) {
                                return DropdownMenuItem<int>(
                                  value: year,
                                  child: Text(year.toString()),
                                );
                              }).toList(),
                              onChanged: (value) {
                                if (value == null) return;
                                setDialogState(() => selectedYear = value);
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      _buildOverallDialogSection(
                        title: 'Document Details',
                        subtitle:
                            'These values appear in the report header and body.',
                        child: Column(
                          children: [
                            _buildOverallTextField(
                              controller: barangayController,
                              label: 'Barangay',
                            ),
                            const SizedBox(height: 12),
                            _buildOverallTextField(
                              controller: municipalityController,
                              label: 'Municipality / City',
                            ),
                            const SizedBox(height: 12),
                            _buildOverallTextField(
                              controller: provinceController,
                              label: 'Province',
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
                  style: TextButton.styleFrom(
                    foregroundColor: _launcherPrimaryAqua,
                  ),
                  child: const Text('Cancel'),
                ),
                FilledButton.icon(
                  onPressed: () {
                    Navigator.of(dialogContext).pop(
                      _OverallReportSelection(
                        period: selectedPeriod,
                        month: selectedMonth,
                        year: selectedYear,
                        barangay: barangayController.text.trim(),
                        municipality: municipalityController.text.trim(),
                        province: provinceController.text.trim(),
                      ),
                    );
                  },
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
    municipalityController.dispose();
    provinceController.dispose();
  }
}

List<int> _overallYearOptions() {
  final currentYear = DateTime.now().year;
  return List<int>.generate(6, (index) => currentYear - index);
}

int _normalizeMonthForOverallPeriod(int month, ReportPeriod period) {
  if (period == ReportPeriod.quarterly) {
    if (month <= 3) return 1;
    if (month <= 6) return 4;
    if (month <= 9) return 7;
    return 10;
  }
  if (month < 1) return 1;
  if (month > 12) return 12;
  return month;
}

List<int> _monthOptionsForOverallPeriod(ReportPeriod period) {
  if (period == ReportPeriod.quarterly) {
    return const [1, 4, 7, 10];
  }
  return List<int>.generate(12, (index) => index + 1);
}

String _monthLabelForOverallPeriod(int month, ReportPeriod period) {
  if (period == ReportPeriod.quarterly) {
    final quarter = ((month - 1) ~/ 3) + 1;
    final startLabel = DateFormat.MMM().format(DateTime(2024, month));
    final endLabel = DateFormat.MMM().format(DateTime(2024, month + 2));
    return 'Quarter $quarter ($startLabel-$endLabel)';
  }
  return DateFormat.MMMM().format(DateTime(2024, month));
}

// Mirrors bhw_report_generation.dart's _buildDialogSection exactly (the
// canonical per-module "Generate Official Report" reference dialog, e.g.
// /bhw/checkups?view=insights), so this dialog reads as the same design
// system rather than a one-off. Duplicated locally rather than shared
// because that helper is file-private and used by several other report
// dialogs already -- reusing it here without changing its signature would
// require making it public, which is a wider change than this fix needs.
Widget _buildOverallDialogSection({
  required String title,
  required String subtitle,
  required Widget child,
}) {
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: 0.04),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: _launcherPrimaryAqua.withValues(alpha: 0.2)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: const TextStyle(color: AppColors.textSecondary, height: 1.4),
        ),
        const SizedBox(height: 14),
        child,
      ],
    ),
  );
}

Widget _buildOverallDropdownField<T>({
  required String label,
  required T value,
  required List<DropdownMenuItem<T>> items,
  required ValueChanged<T?> onChanged,
}) {
  return DropdownButtonFormField<T>(
    initialValue: value,
    isExpanded: true,
    dropdownColor: Colors.white,
    iconEnabledColor: AppColors.textPrimary,
    style: const TextStyle(color: AppColors.textPrimary),
    decoration: InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: AppColors.textSecondary),
      filled: true,
      fillColor: Colors.black.withValues(alpha: 0.04),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(
          color: AppColors.textSecondary.withValues(alpha: 0.22),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _launcherPrimaryAqua, width: 1.5),
      ),
    ),
    items: items,
    onChanged: onChanged,
  );
}

Widget _buildOverallTextField({
  required TextEditingController controller,
  required String label,
}) {
  return TextField(
    controller: controller,
    style: const TextStyle(color: AppColors.textPrimary),
    decoration: InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: AppColors.textSecondary),
      filled: true,
      fillColor: Colors.black.withValues(alpha: 0.04),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(
          color: AppColors.textSecondary.withValues(alpha: 0.22),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _launcherPrimaryAqua, width: 1.5),
      ),
    ),
  );
}

Future<_OverallReportData> _loadOverallReportData(
  _OverallReportSelection selection,
) async {
  final checkups = await DatabaseHelper.instance.getAllRecords();
  final prenatal = await PrenatalDatabaseHelper.instance.getAllRecords();
  final immunizations = await ImmunizationDatabaseHelper.instance
      .getAllRecords();
  final patients = await PatientDatabaseHelper.instance.getAllRecords();
  final mortality = await MortalityDatabaseHelper.instance.getAllRecords();
  final morbidity = await _loadNormalizedMorbidityRecords();

  final filteredCheckups = _filterBySelection(
    checkups,
    (record) => parseReportDateValue(record['datetime']),
    selection,
  );
  final filteredPrenatal = _filterBySelection(
    prenatal,
    (record) =>
        parseReportDateValue(record['registrationDate']) ??
        parseReportDateValue(record['dueDate']),
    selection,
  );
  final filteredImmunizations = _filterBySelection(
    immunizations,
    (record) =>
        parseReportDateValue(record['administrationDate']) ??
        parseReportDateValue(record['date']),
    selection,
  );
  final filteredPatients = _filterBySelection(
    patients,
    (record) =>
        parseReportDateValue(record['registrationDate']) ??
        parseReportDateValue(record['lastCheckup']),
    selection,
  );
  final filteredMorbidity = _filterBySelection(
    morbidity,
    _resolveMorbidityDate,
    selection,
  );
  final filteredMortality = _filterBySelection(
    mortality,
    (record) =>
        parseReportDateValue(record['date']) ??
        parseReportDateValue(record['dateReported']),
    selection,
  );

  final communicable = filteredMorbidity.where((record) {
    return _normalizeClassification(record['caseClassification']) ==
        'communicable';
  }).toList();
  final nonCommunicable = filteredMorbidity.where((record) {
    return _normalizeClassification(record['caseClassification']) ==
        'noncommunicable';
  }).toList();

  return _OverallReportData(
    checkups: filteredCheckups,
    prenatal: filteredPrenatal,
    immunizations: filteredImmunizations,
    patients: filteredPatients,
    communicable: communicable,
    nonCommunicable: nonCommunicable,
    morbidity: filteredMorbidity,
    mortality: filteredMortality,
  );
}

List<Map<String, dynamic>> _filterBySelection(
  List<Map<String, dynamic>> records,
  DateTime? Function(Map<String, dynamic> record) dateResolver,
  _OverallReportSelection selection,
) {
  final range = _selectionRange(selection);
  return records.where((record) {
    final date = dateResolver(record);
    if (date == null) return false;
    return !date.isBefore(range.start) && !date.isAfter(range.end);
  }).toList();
}

_DateRange _selectionRange(_OverallReportSelection selection) {
  switch (selection.period) {
    case ReportPeriod.monthly:
      final start = DateTime(selection.year, selection.month, 1);
      final end = DateTime(selection.year, selection.month + 1, 0, 23, 59, 59);
      return _DateRange(start: start, end: end);
    case ReportPeriod.quarterly:
      final start = DateTime(selection.year, selection.month, 1);
      final end = DateTime(selection.year, selection.month + 3, 0, 23, 59, 59);
      return _DateRange(start: start, end: end);
    case ReportPeriod.yearly:
      return _DateRange(
        start: DateTime(selection.year, 1, 1),
        end: DateTime(selection.year, 12, 31, 23, 59, 59),
      );
  }
}

int _parseAge(dynamic value) {
  final text = value?.toString() ?? '';
  final match = RegExp(r'\d+').firstMatch(text);
  if (match == null) return -1;
  return int.tryParse(match.group(0) ?? '') ?? -1;
}

String _normalizeSexValue(dynamic value) {
  final normalized = (value?.toString().trim().toLowerCase() ?? '');
  if (normalized == 'm' || normalized == 'male') return 'Male';
  if (normalized == 'f' || normalized == 'female') return 'Female';
  return '';
}

String _patientLookupKey(Map<String, dynamic> record) {
  final fullName = reportJoin(
    [record['firstName'], record['middleName'], record['surname']],
    separator: ' ',
    fallback: '',
  );
  return fullName.trim().toLowerCase();
}

Map<String, String> _buildPatientSexLookup(
  List<Map<String, dynamic>> patients,
) {
  final lookup = <String, String>{};
  for (final patient in patients) {
    final id = (patient['patientId'] ?? patient['id'] ?? '').toString().trim();
    final nameKey = _patientLookupKey(patient);
    final sex = _normalizeSexValue(patient['gender'] ?? patient['sex']);
    if (sex.isEmpty) continue;
    if (id.isNotEmpty) {
      lookup[id] = sex;
    }
    if (nameKey.isNotEmpty) {
      lookup[nameKey] = sex;
    }
  }
  return lookup;
}

String _resolveRecordSex(
  Map<String, dynamic> record,
  Map<String, String> patientSexLookup,
) {
  final sourceRecord = record['sourceRecord'] is Map
      ? Map<String, dynamic>.from(record['sourceRecord'] as Map)
      : const <String, dynamic>{};
  final direct = _normalizeSexValue(
    record['gender'] ??
        record['sex'] ??
        sourceRecord['gender'] ??
        sourceRecord['sex'],
  );
  if (direct.isNotEmpty) return direct;

  final patientId =
      (record['patientId'] ??
              record['linkedPatientId'] ??
              sourceRecord['patientId'] ??
              '')
          .toString()
          .trim();
  if (patientId.isNotEmpty && patientSexLookup.containsKey(patientId)) {
    return patientSexLookup[patientId]!;
  }

  final nameKey = reportText(
    record['patientName'] ?? record['patient'],
    fallback: '',
  ).toLowerCase();
  return patientSexLookup[nameKey] ?? '';
}

_SexMetricRow _buildSexMetricRow({
  required String indicator,
  required List<Map<String, dynamic>> records,
  required Map<String, String> patientSexLookup,
  String remarks = '',
}) {
  int male = 0;
  int female = 0;

  for (final record in records) {
    final sex = _resolveRecordSex(record, patientSexLookup);
    if (sex == 'Male') male++;
    if (sex == 'Female') female++;
  }

  return _SexMetricRow(
    indicator: indicator,
    male: male,
    female: female,
    total: records.length,
    remarks: remarks,
  );
}

_AgeMetricRow _buildMaternalMetricRow({
  required String indicator,
  required List<Map<String, dynamic>> records,
  String remarks = '',
}) {
  int age10to14 = 0;
  int age15to19 = 0;
  int age20to49 = 0;

  for (final record in records) {
    final age = _parseAge(record['age']);
    if (age >= 10 && age <= 14) age10to14++;
    if (age >= 15 && age <= 19) age15to19++;
    if (age >= 20 && age <= 49) age20to49++;
  }

  return _AgeMetricRow(
    indicator: indicator,
    age10to14: age10to14,
    age15to19: age15to19,
    age20to49: age20to49,
    total: records.length,
    remarks: remarks,
  );
}

String _topValueLabel(
  List<Map<String, dynamic>> records,
  dynamic Function(Map<String, dynamic> record) extractor,
  String fallback,
) {
  final counts = <String, int>{};
  for (final record in records) {
    final value = reportText(extractor(record), fallback: '');
    if (value.isEmpty) continue;
    counts[value] = (counts[value] ?? 0) + 1;
  }
  if (counts.isEmpty) return fallback;
  final sorted = counts.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return '${sorted.first.key} (${sorted.first.value})';
}

Future<Uint8List> _buildOverallHealthPdf(
  _OverallReportSelection selection,
  _OverallReportData data,
) async {
  // Yield to event loop at the start
  await Future.delayed(const Duration(milliseconds: 1));

  final generatedAt = DateTime.now();

  final branding = await loadReportBranding(barangayName: selection.barangay);
  final cityLogo = branding.cityLogo == null
      ? null
      : pw.MemoryImage(Uint8List.fromList(branding.cityLogo!));
  final healthOfficeLogo = branding.healthOfficeLogo == null
      ? null
      : pw.MemoryImage(Uint8List.fromList(branding.healthOfficeLogo!));
  final barangayLogo = branding.barangayLogo == null
      ? null
      : pw.MemoryImage(Uint8List.fromList(branding.barangayLogo!));

  final fonts = await loadPdfFontBundle();
  // Yield after loading fonts
  await Future.delayed(const Duration(milliseconds: 1));

  final patientLookup = _buildPatientSexLookup(data.patients);
  final range = _selectionRange(selection);

  final maternalRows = <_AgeMetricRow>[
    _buildMaternalMetricRow(
      indicator: 'Prenatal records encoded',
      records: data.prenatal,
      remarks: 'Derived from prenatal registrations within the selected scope',
    ),
    _buildMaternalMetricRow(
      indicator: 'High-risk pregnancies',
      records: data.prenatal.where((record) {
        return reportText(
          record['riskLevel'],
          fallback: '',
        ).toLowerCase().contains('high');
      }).toList(),
    ),
    _buildMaternalMetricRow(
      indicator: 'Active prenatal monitoring',
      records: data.prenatal.where((record) {
        final status = reportText(record['status'], fallback: '').toLowerCase();
        return status.isEmpty || (status != 'completed' && status != 'closed');
      }).toList(),
    ),
    _buildMaternalMetricRow(
      indicator: 'Expected deliveries within scope',
      records: data.prenatal.where((record) {
        final dueDate = parseReportDateValue(record['dueDate']);
        if (dueDate == null) return false;
        return !dueDate.isBefore(range.start) && !dueDate.isAfter(range.end);
      }).toList(),
    ),
    _buildMaternalMetricRow(
      indicator: 'Completed prenatal records',
      records: data.prenatal.where((record) {
        return reportText(
          record['status'],
          fallback: '',
        ).toLowerCase().contains('completed');
      }).toList(),
    ),
    _buildMaternalMetricRow(
      indicator: 'Records with follow-up notes',
      records: data.prenatal.where((record) {
        return reportText(record['additionalNote'], fallback: '').isNotEmpty;
      }).toList(),
    ),
  ];

  final immunizationRows = <_SexMetricRow>[
    _buildSexMetricRow(
      indicator: 'BCG administered',
      records: data.immunizations.where((record) {
        return reportText(
          record['vaccine'],
          fallback: '',
        ).toLowerCase().contains('bcg');
      }).toList(),
      patientSexLookup: patientLookup,
    ),
    _buildSexMetricRow(
      indicator: 'Hepatitis B administered',
      records: data.immunizations.where((record) {
        return reportText(
          record['vaccine'],
          fallback: '',
        ).toLowerCase().contains('hep');
      }).toList(),
      patientSexLookup: patientLookup,
    ),
    _buildSexMetricRow(
      indicator: 'DPT administered',
      records: data.immunizations.where((record) {
        return reportText(
          record['vaccine'],
          fallback: '',
        ).toLowerCase().contains('dpt');
      }).toList(),
      patientSexLookup: patientLookup,
    ),
    _buildSexMetricRow(
      indicator: 'Polio administered',
      records: data.immunizations.where((record) {
        final vaccine = reportText(
          record['vaccine'],
          fallback: '',
        ).toLowerCase();
        return vaccine.contains('polio') ||
            vaccine.contains('opv') ||
            vaccine.contains('ipv');
      }).toList(),
      patientSexLookup: patientLookup,
    ),
    _buildSexMetricRow(
      indicator: 'MMR administered',
      records: data.immunizations.where((record) {
        return reportText(
          record['vaccine'],
          fallback: '',
        ).toLowerCase().contains('mmr');
      }).toList(),
      patientSexLookup: patientLookup,
    ),
    _buildSexMetricRow(
      indicator: 'Varicella administered',
      records: data.immunizations.where((record) {
        return reportText(
          record['vaccine'],
          fallback: '',
        ).toLowerCase().contains('varicella');
      }).toList(),
      patientSexLookup: patientLookup,
    ),
    _buildSexMetricRow(
      indicator: 'Pneumococcal / PCV administered',
      records: data.immunizations.where((record) {
        final vaccine = reportText(
          record['vaccine'],
          fallback: '',
        ).toLowerCase();
        return vaccine.contains('pneumo') || vaccine.contains('pcv');
      }).toList(),
      patientSexLookup: patientLookup,
    ),
    _buildSexMetricRow(
      indicator: 'Completed immunization doses',
      records: data.immunizations.where((record) {
        return reportText(
          record['status'],
          fallback: '',
        ).toLowerCase().contains('completed');
      }).toList(),
      patientSexLookup: patientLookup,
    ),
  ];

  final checkupRows = <_SexMetricRow>[
    _buildSexMetricRow(
      indicator: 'Total check-ups encoded',
      records: data.checkups,
      patientSexLookup: patientLookup,
      remarks: 'From encoded check-up encounters',
    ),
    _buildSexMetricRow(
      indicator: 'Completed check-ups',
      records: data.checkups.where((record) {
        return reportText(
          record['status'],
          fallback: '',
        ).toLowerCase().contains('completed');
      }).toList(),
      patientSexLookup: patientLookup,
    ),
    _buildSexMetricRow(
      indicator: 'Pending check-ups',
      records: data.checkups.where((record) {
        return reportText(
          record['status'],
          fallback: '',
        ).toLowerCase().contains('pending');
      }).toList(),
      patientSexLookup: patientLookup,
    ),
    _buildSexMetricRow(
      indicator: 'Check-ups with diagnosis encoded',
      records: data.checkups.where((record) {
        return reportText(record['diagnosis'], fallback: '').isNotEmpty;
      }).toList(),
      patientSexLookup: patientLookup,
    ),
  ];

  final patientRows = <_SexMetricRow>[
    _buildSexMetricRow(
      indicator: 'Registered patient records',
      records: data.patients,
      patientSexLookup: patientLookup,
      remarks: 'Based on patient registry dates inside the selected scope',
    ),
    _buildSexMetricRow(
      indicator: 'Active patient records',
      records: data.patients.where((record) {
        return reportText(
          record['status'],
          fallback: '',
        ).toLowerCase().contains('active');
      }).toList(),
      patientSexLookup: patientLookup,
    ),
    _buildSexMetricRow(
      indicator: 'Follow-up patient records',
      records: data.patients.where((record) {
        return reportText(
          record['status'],
          fallback: '',
        ).toLowerCase().contains('follow');
      }).toList(),
      patientSexLookup: patientLookup,
    ),
  ];

  final communicableRows = <_SexMetricRow>[
    _buildSexMetricRow(
      indicator: 'Communicable disease cases',
      records: data.communicable,
      patientSexLookup: patientLookup,
      remarks:
          'Top condition: ${_topValueLabel(data.communicable, (record) => record['disease'], 'No encoded disease')}',
    ),
    _buildSexMetricRow(
      indicator: 'Active / under treatment cases',
      records: data.communicable.where((record) {
        final status = reportText(record['status'], fallback: '').toLowerCase();
        return status.contains('active') ||
            status.contains('pending') ||
            status.contains('treatment');
      }).toList(),
      patientSexLookup: patientLookup,
    ),
    _buildSexMetricRow(
      indicator: 'Recovered / completed cases',
      records: data.communicable.where((record) {
        final status = reportText(record['status'], fallback: '').toLowerCase();
        return status.contains('completed') ||
            status.contains('recovered') ||
            status.contains('resolved');
      }).toList(),
      patientSexLookup: patientLookup,
    ),
  ];

  final nonCommunicableRows = <_SexMetricRow>[
    _buildSexMetricRow(
      indicator: 'Non-communicable disease cases',
      records: data.nonCommunicable,
      patientSexLookup: patientLookup,
      remarks:
          'Top condition: ${_topValueLabel(data.nonCommunicable, (record) => record['disease'], 'No encoded condition')}',
    ),
    _buildSexMetricRow(
      indicator: 'Active / under treatment cases',
      records: data.nonCommunicable.where((record) {
        final status = reportText(record['status'], fallback: '').toLowerCase();
        return status.contains('active') ||
            status.contains('pending') ||
            status.contains('treatment');
      }).toList(),
      patientSexLookup: patientLookup,
    ),
    _buildSexMetricRow(
      indicator: 'Completed / controlled cases',
      records: data.nonCommunicable.where((record) {
        final status = reportText(record['status'], fallback: '').toLowerCase();
        return status.contains('completed') ||
            status.contains('controlled') ||
            status.contains('resolved');
      }).toList(),
      patientSexLookup: patientLookup,
    ),
  ];

  final morbidityRows = <_SexMetricRow>[
    _buildSexMetricRow(
      indicator: 'Morbidity records',
      records: data.morbidity,
      patientSexLookup: patientLookup,
      remarks:
          'Top diagnosis: ${_topValueLabel(data.morbidity, (record) => record['disease'], 'No encoded diagnosis')}',
    ),
    _buildSexMetricRow(
      indicator: 'Closed / completed cases',
      records: data.morbidity.where((record) {
        final status = reportText(record['status'], fallback: '').toLowerCase();
        return status.contains('completed') ||
            status.contains('resolved') ||
            status.contains('recovered');
      }).toList(),
      patientSexLookup: patientLookup,
    ),
  ];

  final mortalityRows = <_SexMetricRow>[
    _buildSexMetricRow(
      indicator: 'Deaths recorded',
      records: data.mortality,
      patientSexLookup: patientLookup,
      remarks:
          'Leading cause: ${_topValueLabel(data.mortality, (record) => record['causeOfDeath'], 'No encoded cause')}',
    ),
    _buildSexMetricRow(
      indicator: 'Verified deaths',
      records: data.mortality.where((record) {
        return reportText(
          record['verification'],
          fallback: '',
        ).toLowerCase().contains('verified');
      }).toList(),
      patientSexLookup: patientLookup,
    ),
    _buildSexMetricRow(
      indicator: 'Senior citizen deaths',
      records: data.mortality
          .where((record) => _parseAge(record['age']) >= 60)
          .toList(),
      patientSexLookup: patientLookup,
    ),
  ];

  final pdf = pw.Document(
    theme: pw.ThemeData.withFont(
      base: fonts.base,
      bold: fonts.bold,
      italic: fonts.italic,
      boldItalic: fonts.boldItalic,
    ),
  );

  pdf.addPage(
    pw.MultiPage(
      pageTheme: pw.PageTheme(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(22),
      ),
      footer: (context) => buildOfficialReportFooter(
        context,
        footerText:
            'Generated by AI-DSUHIS • Confidential health information • Generated: ${DateFormat('MMMM dd, yyyy  hh:mm a').format(generatedAt)}',
      ),
      build: (context) => [
        buildOfficialReportHeader(
          title: 'FHSIS Health Services Report',
          systemName: 'BARANGAY HEALTH WORKER INFORMATION SYSTEM',
          subtitle:
              '${selection.period.label}  |  ${selection.scopeLabel}  |  ${selection.municipality}, ${selection.province}',
          barangayName: branding.barangayName,
          generatedAt: generatedAt,
          cityLogo: cityLogo,
          healthOfficeLogo: healthOfficeLogo,
          barangayLogo: barangayLogo,
        ),
        pw.SizedBox(height: 14),
        _buildOverallSectionTitle('Section A. Maternal Care and Services', ''),
        _buildAgeMetricsTable(context, 'Prenatal Care Services', maternalRows),
        pw.NewPage(),
        _buildOverallSectionTitle('Section B. Child Care and Services', ''),
        _buildSexMetricsTable(
          context,
          'Immunization Services',
          immunizationRows,
        ),
        pw.NewPage(),
        _buildOverallSectionTitle(
          'Section C. General Consultations and Registry',
          '',
        ),
        _buildSexMetricsTable(context, 'Check-up Services', checkupRows),
        pw.SizedBox(height: 10),
        _buildSexMetricsTable(context, 'Patient Records', patientRows),
        pw.NewPage(),
        _buildOverallSectionTitle('Section D. Non-Communicable Diseases', ''),
        _buildSexMetricsTable(
          context,
          'Non-Communicable Disease Services',
          nonCommunicableRows,
        ),
        pw.NewPage(),
        _buildOverallSectionTitle(
          'Section E. Mortality and Morbidity',
          'Mortality and morbidity summaries within the selected period',
        ),
        _buildSexMetricsTable(context, 'Morbidity Summary', morbidityRows),
        pw.SizedBox(height: 10),
        _buildSexMetricsTable(context, 'Mortality Summary', mortalityRows),
        pw.NewPage(),
        _buildOverallSectionTitle(
          'Section F. Infectious Disease Prevention and Control Services',
          'Derived from communicable cases encoded in check-up and morbidity records',
        ),
        _buildSexMetricsTable(
          context,
          'Communicable Disease Services',
          communicableRows,
        ),
      ],
    ),
  );

  pdf.addPage(
    buildOfficialReportSignaturePage(
      pageFormat: PdfPageFormat.a4.landscape,
      signatures: const [
        OfficialReportSignature(title: 'Barangay Captain'),
        OfficialReportSignature(title: 'Barangay Kagawad in Health'),
        OfficialReportSignature(title: 'BHW Head'),
        OfficialReportSignature(title: 'BHW Assigned on Duty'),
      ],
      footerText: 'Generated by AI-DSUHIS • Confidential health information',
    ),
  );

  // Yield to event loop before PDF rendering to allow UI to update
  await Future.delayed(const Duration(milliseconds: 1));

  // The pdf.save() call is synchronous but try to minimize blocking
  // by allowing the event loop to process other events first
  return await Future.delayed(Duration.zero, () => pdf.save());
}

pw.Widget _buildOverallSectionTitle(String title, String subtitle) {
  final hasSubtitle = subtitle.trim().isNotEmpty;

  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: pw.BoxDecoration(
          color: PdfColors.white,
          borderRadius: pw.BorderRadius.circular(4),
        ),
        child: pw.Text(
          title.toUpperCase(),
          style: pw.TextStyle(
            fontSize: 11.5,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.black,
          ),
        ),
      ),
      if (hasSubtitle) ...[
        pw.SizedBox(height: 4),
        pw.Text(
          subtitle,
          style: pw.TextStyle(fontSize: 8.8, color: PdfColors.black),
        ),
      ],
      pw.SizedBox(height: hasSubtitle ? 8 : 4),
    ],
  );
}

pw.Widget _buildAgeMetricsTable(
  pw.Context context,
  String title,
  List<_AgeMetricRow> rows,
) {
  final data = rows
      .map(
        (row) => [
          row.indicator,
          row.age10to14.toString(),
          row.age15to19.toString(),
          row.age20to49.toString(),
          row.total.toString(),
          row.remarks,
        ],
      )
      .toList();

  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(
        title,
        style: pw.TextStyle(
          fontSize: 10.5,
          fontWeight: pw.FontWeight.bold,
          color: PdfColors.black,
        ),
      ),
      pw.SizedBox(height: 6),
      pw.TableHelper.fromTextArray(
        context: context,
        headers: const [
          'Indicators',
          '10-14',
          '15-19',
          '20-49',
          'Total',
          'Remarks',
        ],
        data: data,
        headerDecoration: const pw.BoxDecoration(color: PdfColors.white),
        headerStyle: pw.TextStyle(
          color: PdfColors.black,
          fontSize: 11,
          fontWeight: pw.FontWeight.bold,
        ),
        cellStyle: pw.TextStyle(fontSize: 9.5, color: PdfColors.black),
        headerPadding: const pw.EdgeInsets.symmetric(
          horizontal: 5,
          vertical: 7,
        ),
        cellPadding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 6),
        columnWidths: const {
          0: pw.FlexColumnWidth(2.6),
          1: pw.FlexColumnWidth(0.7),
          2: pw.FlexColumnWidth(0.7),
          3: pw.FlexColumnWidth(0.7),
          4: pw.FlexColumnWidth(0.9),
          5: pw.FlexColumnWidth(2.0),
        },
        border: pw.TableBorder.all(color: PdfColors.black),
        headerAlignments: const {
          0: pw.Alignment.centerLeft,
          1: pw.Alignment.center,
          2: pw.Alignment.center,
          3: pw.Alignment.center,
          4: pw.Alignment.center,
          5: pw.Alignment.centerLeft,
        },
        cellAlignments: const {
          0: pw.Alignment.centerLeft,
          1: pw.Alignment.center,
          2: pw.Alignment.center,
          3: pw.Alignment.center,
          4: pw.Alignment.center,
          5: pw.Alignment.centerLeft,
        },
      ),
    ],
  );
}

pw.Widget _buildSexMetricsTable(
  pw.Context context,
  String title,
  List<_SexMetricRow> rows,
) {
  final data = rows
      .map(
        (row) => [
          row.indicator,
          row.male.toString(),
          row.female.toString(),
          row.total.toString(),
          row.remarks,
        ],
      )
      .toList();

  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(
        title,
        style: pw.TextStyle(
          fontSize: 10.5,
          fontWeight: pw.FontWeight.bold,
          color: PdfColors.black,
        ),
      ),
      pw.SizedBox(height: 6),
      pw.TableHelper.fromTextArray(
        context: context,
        headers: const ['Indicators', 'Male', 'Female', 'Total', 'Remarks'],
        data: data,
        headerDecoration: const pw.BoxDecoration(color: PdfColors.white),
        headerStyle: pw.TextStyle(
          color: PdfColors.black,
          fontSize: 11,
          fontWeight: pw.FontWeight.bold,
        ),
        cellStyle: pw.TextStyle(fontSize: 9.5, color: PdfColors.black),
        headerPadding: const pw.EdgeInsets.symmetric(
          horizontal: 5,
          vertical: 7,
        ),
        cellPadding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 6),
        columnWidths: const {
          0: pw.FlexColumnWidth(2.7),
          1: pw.FlexColumnWidth(0.7),
          2: pw.FlexColumnWidth(0.7),
          3: pw.FlexColumnWidth(0.8),
          4: pw.FlexColumnWidth(2.2),
        },
        border: pw.TableBorder.all(color: PdfColors.black),
        headerAlignments: const {
          0: pw.Alignment.centerLeft,
          1: pw.Alignment.center,
          2: pw.Alignment.center,
          3: pw.Alignment.center,
          4: pw.Alignment.centerLeft,
        },
        cellAlignments: const {
          0: pw.Alignment.centerLeft,
          1: pw.Alignment.center,
          2: pw.Alignment.center,
          3: pw.Alignment.center,
          4: pw.Alignment.centerLeft,
        },
      ),
    ],
  );
}

Future<_DashboardReportPayload> _loadDashboardReportPayload(
  DashboardReportType type,
) async {
  switch (type) {
    case DashboardReportType.checkup:
      final records = await DatabaseHelper.instance.getAllRecords();
      return _DashboardReportPayload(
        moduleLabel: 'Check-up',
        records: records,
        dateResolver: (record) => parseReportDateValue(record['datetime']),
        columns: [
          ReportCsvColumn(
            'Patient Name',
            (record) => reportText(record['patient']),
            flex: 1.4,
          ),
          ReportCsvColumn(
            'Age',
            (record) => reportText(record['age']),
            flex: 0.55,
            center: true,
          ),
          ReportCsvColumn(
            'Sex',
            (record) => reportText(record['gender'] ?? record['sex']),
            flex: 0.7,
            center: true,
          ),
          ReportCsvColumn(
            'Address / Barangay',
            (record) => reportText(record['address']),
            flex: 1.35,
          ),
          ReportCsvColumn(
            'Date of Check-up',
            (record) => formatReportDateValue(record['datetime']),
            flex: 0.95,
            center: true,
          ),
          ReportCsvColumn(
            'Chief Complaint',
            (record) => reportText(record['symptoms']),
            flex: 1.25,
          ),
          ReportCsvColumn(
            'Findings',
            (record) => reportText(
              record['details'],
              fallback: reportText(record['vitalsigns']),
            ),
            flex: 1.35,
          ),
          ReportCsvColumn(
            'Diagnosis',
            (record) => reportText(
              record['diagnosis'],
              fallback: reportText(
                record['diseaseType'],
                fallback: reportText(record['ai_category']),
              ),
            ),
            flex: 1.05,
          ),
          ReportCsvColumn(
            'Treatment / Action Taken',
            (record) => reportText(record['plan']),
            flex: 1.35,
          ),
          ReportCsvColumn('Remarks', (record) {
            final followup = reportText(record['followup'], fallback: '');
            final parts = <String>[
              'Status: ${reportText(record['status'], fallback: 'Completed')}',
            ];
            if (followup.isNotEmpty) {
              parts.add('Follow-up: $followup');
            }
            return reportJoin(
              parts,
              separator: ' | ',
              fallback: reportText(record['remarks']),
            );
          }, flex: 1.1),
        ],
        sectionTitleBuilder: (record, index) =>
            'Record ${index + 1}: ${reportText(record['patient'], fallback: 'Unknown patient')}',
      );
    case DashboardReportType.prenatal:
      final records = await PrenatalDatabaseHelper.instance.getAllRecords();
      return _DashboardReportPayload(
        moduleLabel: 'Prenatal',
        records: records,
        dateResolver: (record) =>
            parseReportDateValue(record['registrationDate']) ??
            parseReportDateValue(record['dueDate']),
        columns: [
          ReportCsvColumn(
            'Patient ID',
            (record) => reportText(record['patientId']),
            flex: 0.85,
          ),
          ReportCsvColumn(
            'Patient Name',
            (record) => reportJoin([
              record['patientName'],
              record['firstName'],
              record['surname'],
            ]),
            flex: 1.35,
          ),
          ReportCsvColumn(
            'Age',
            (record) => reportText(record['age']),
            flex: 0.55,
            center: true,
          ),
          ReportCsvColumn(
            'Registration Date',
            (record) => formatReportDateValue(record['registrationDate']),
            flex: 0.95,
            center: true,
          ),
          ReportCsvColumn(
            'Due Date',
            (record) => formatReportDateValue(record['dueDate']),
            flex: 0.95,
            center: true,
          ),
          ReportCsvColumn(
            'Gestational Age',
            (record) => reportText(record['gestationalAge'] ?? record['aog']),
            flex: 0.85,
            center: true,
          ),
          ReportCsvColumn(
            'Gravida',
            (record) => reportText(record['gravida']),
            flex: 0.5,
            center: true,
          ),
          ReportCsvColumn(
            'Para',
            (record) => reportText(record['para']),
            flex: 0.5,
            center: true,
          ),
          ReportCsvColumn(
            'Risk Level',
            (record) => reportText(record['riskLevel']),
            flex: 0.9,
          ),
          ReportCsvColumn(
            'Status',
            (record) => reportText(record['status']),
            flex: 0.85,
          ),
          ReportCsvColumn(
            'Address / Barangay',
            (record) => reportText(record['address']),
            flex: 1.3,
          ),
          ReportCsvColumn(
            'Remarks',
            (record) => reportText(record['additionalNote']),
            flex: 1.15,
          ),
        ],
        sectionTitleBuilder: (record, index) =>
            'Record ${index + 1}: ${reportJoin([record['patientName'], record['firstName'], record['surname']], fallback: 'Patient')}',
      );
    case DashboardReportType.immunization:
      final records = await ImmunizationDatabaseHelper.instance.getAllRecords();
      return _DashboardReportPayload(
        moduleLabel: 'Immunization',
        records: records,
        dateResolver: (record) =>
            parseReportDateValue(record['administrationDate']) ??
            parseReportDateValue(record['date']),
        columns: [
          ReportCsvColumn(
            'Patient ID',
            (record) => reportText(record['patientId']),
            flex: 0.9,
          ),
          ReportCsvColumn(
            'Patient Name',
            (record) => reportText(record['patientName']),
            flex: 1.35,
          ),
          ReportCsvColumn(
            'Age',
            (record) => reportText(record['age']),
            flex: 0.55,
            center: true,
          ),
          ReportCsvColumn(
            'Vaccine Type',
            (record) => reportText(record['vaccine']),
            flex: 1.2,
          ),
          ReportCsvColumn(
            'Administration Date',
            (record) => formatReportDateValue(record['administrationDate']),
            flex: 0.95,
            center: true,
          ),
          ReportCsvColumn(
            'Dose Number',
            (record) => reportText(record['doseNumber']),
            flex: 0.6,
            center: true,
          ),
          ReportCsvColumn(
            'Status',
            (record) => reportText(record['status']),
            flex: 0.9,
            center: true,
          ),
          ReportCsvColumn(
            'Administered By',
            (record) => reportText(record['administeredBy']),
            flex: 1.1,
          ),
          ReportCsvColumn(
            'Route',
            (record) => reportText(record['routeOfAdministration']),
            flex: 0.95,
          ),
          ReportCsvColumn(
            'Injection Site',
            (record) => reportText(record['injectionSite']),
            flex: 0.95,
          ),
          ReportCsvColumn(
            'Adverse Events Following Immunization (AEFI)',
            (record) => reportText(record['adverseEvents'], fallback: 'None'),
            flex: 1.2,
          ),
        ],
        sectionTitleBuilder: (record, index) =>
            'Record ${index + 1}: ${reportText(record['patientName'], fallback: 'Patient')}',
      );
    case DashboardReportType.communicable:
      final records = await _loadClassifiedMorbidityRecords('communicable');
      return _DashboardReportPayload(
        moduleLabel: 'Communicable',
        records: records,
        dateResolver: (record) => _resolveMorbidityDate(record),
        columns: _buildClassifiedDiseaseColumns(),
        sectionTitleBuilder: (record, index) =>
            'Record ${index + 1}: ${reportText(record['patientName'], fallback: 'Patient')}',
      );
    case DashboardReportType.nonCommunicable:
      final records = await _loadClassifiedMorbidityRecords('noncommunicable');
      return _DashboardReportPayload(
        moduleLabel: 'Non-Communicable',
        records: records,
        dateResolver: (record) => _resolveMorbidityDate(record),
        columns: _buildClassifiedDiseaseColumns(),
        sectionTitleBuilder: (record, index) =>
            'Record ${index + 1}: ${reportText(record['patientName'], fallback: 'Patient')}',
      );
    case DashboardReportType.mortality:
      final records = await MortalityDatabaseHelper.instance.getAllRecords();
      return _DashboardReportPayload(
        moduleLabel: 'Mortality',
        records: records,
        dateResolver: (record) =>
            parseReportDateValue(record['date']) ??
            parseReportDateValue(record['dateReported']),
        columns: [
          ReportCsvColumn('Record ID', (record) => reportText(record['id'])),
          ReportCsvColumn('Name', (record) => reportText(record['name'])),
          ReportCsvColumn(
            'Date of Death',
            (record) => formatReportDateValue(record['date']),
          ),
          ReportCsvColumn(
            'Cause of Death',
            (record) => reportText(record['causeOfDeath']),
          ),
          ReportCsvColumn('Place', (record) => reportText(record['place'])),
          ReportCsvColumn('Age', (record) => reportText(record['age'])),
          ReportCsvColumn('Gender', (record) => reportText(record['gender'])),
          ReportCsvColumn(
            'Verification Status',
            (record) => reportText(record['verification']),
          ),
          ReportCsvColumn(
            'Reported By',
            (record) => reportText(record['reportedBy']),
          ),
          ReportCsvColumn(
            'Date Reported',
            (record) => formatReportDateValue(record['dateReported']),
          ),
        ],
        sectionTitleBuilder: (record, index) =>
            'Record ${index + 1}: ${reportText(record['name'], fallback: 'Record')}',
      );
    case DashboardReportType.morbidity:
      final records = await _loadNormalizedMorbidityRecords();
      return _DashboardReportPayload(
        moduleLabel: 'Morbidity',
        records: records,
        dateResolver: (record) => _resolveMorbidityDate(record),
        columns: [
          ReportCsvColumn(
            'Patient Name',
            (record) => reportText(record['patientName']),
            flex: 1.45,
          ),
          ReportCsvColumn(
            'Age',
            (record) => reportText(
              record['age'],
              fallback: reportText((record['sourceRecord'] as Map?)?['age']),
            ),
            flex: 0.55,
            center: true,
          ),
          ReportCsvColumn(
            'Sex',
            (record) => reportText(
              record['sex'] ?? record['gender'],
              fallback: reportText(
                (record['sourceRecord'] as Map?)?['gender'] ??
                    (record['sourceRecord'] as Map?)?['sex'],
              ),
            ),
            flex: 0.7,
            center: true,
          ),
          ReportCsvColumn(
            'Disease / Diagnosis',
            (record) => reportText(record['disease']),
            flex: 1.45,
          ),
          ReportCsvColumn(
            'Date Recorded',
            (record) => formatReportDateValue(record['reportedDate']),
            flex: 0.95,
            center: true,
          ),
          ReportCsvColumn(
            'Case Status',
            (record) => reportText(record['status']),
            flex: 0.9,
            center: true,
          ),
          ReportCsvColumn(
            'Remarks',
            (record) => reportText(record['remarks']),
            flex: 1.45,
          ),
        ],
        sectionTitleBuilder: (record, index) =>
            'Record ${index + 1}: ${reportText(record['patientName'], fallback: 'Patient')}',
      );
    case DashboardReportType.patientRecords:
      final records = await PatientDatabaseHelper.instance.getAllRecords();
      return _DashboardReportPayload(
        moduleLabel: 'Patient',
        records: records,
        dateResolver: (record) =>
            parseReportDateValue(record['registrationDate']) ??
            parseReportDateValue(record['lastCheckup']) ??
            parseReportDateValue(record['dateOfBirth']),
        columns: [
          ReportCsvColumn(
            'Patient ID',
            (record) => reportText(
              record['patientId'],
              fallback: reportText(record['id']),
            ),
            flex: 0.95,
          ),
          ReportCsvColumn(
            'Patient Name',
            (record) => reportJoin([
              record['firstName'],
              record['middleName'],
              record['surname'],
            ]),
            flex: 1.35,
          ),
          ReportCsvColumn(
            'Registration Date',
            (record) => formatReportDateValue(record['registrationDate']),
            flex: 0.95,
            center: true,
          ),
          ReportCsvColumn(
            'Age',
            (record) => reportText(record['age']),
            flex: 0.55,
            center: true,
          ),
          ReportCsvColumn(
            'Sex',
            (record) => reportText(record['gender']),
            flex: 0.7,
            center: true,
          ),
          ReportCsvColumn(
            'Address / Barangay',
            (record) => reportJoin(
              [record['street'], record['barangay'], record['municipality']],
              separator: ', ',
              fallback: reportText(record['barangay']),
            ),
            flex: 1.35,
          ),
          ReportCsvColumn(
            'Contact Number',
            (record) => reportText(record['phoneNumber']),
            flex: 1.0,
          ),
          ReportCsvColumn(
            'Blood Type',
            (record) => reportText(record['bloodType']),
            flex: 0.7,
            center: true,
          ),
          ReportCsvColumn(
            'Status',
            (record) => reportText(record['status']),
            flex: 0.9,
            center: true,
          ),
        ],
        sectionTitleBuilder: (record, index) =>
            'Record ${index + 1}: ${reportJoin([record['firstName'], record['middleName'], record['surname']], fallback: 'Patient')}',
      );
  }
}

DateTime? _resolveMorbidityDate(Map<String, dynamic> record) {
  final source = record['sourceRecord'] is Map
      ? Map<String, dynamic>.from(record['sourceRecord'] as Map)
      : const <String, dynamic>{};
  return parseReportDateValue(record['reportedDate']) ??
      parseReportDateValue(source['datetime']) ??
      parseReportDateValue(source['dateReported']) ??
      parseReportDateValue(source['date']);
}

List<ReportCsvColumn> _buildClassifiedDiseaseColumns() {
  return [
    ReportCsvColumn(
      'Patient Name',
      (record) => reportText(record['patientName']),
      flex: 1.4,
    ),
    ReportCsvColumn(
      'Age',
      (record) => reportText(
        record['age'],
        fallback: reportText((record['sourceRecord'] as Map?)?['age']),
      ),
      flex: 0.55,
      center: true,
    ),
    ReportCsvColumn(
      'Sex',
      (record) => reportText(
        record['sex'] ?? record['gender'],
        fallback: reportText(
          (record['sourceRecord'] as Map?)?['gender'] ??
              (record['sourceRecord'] as Map?)?['sex'],
        ),
      ),
      flex: 0.7,
      center: true,
    ),
    ReportCsvColumn(
      'Condition / Disease',
      (record) => reportText(record['disease']),
      flex: 1.4,
    ),
    ReportCsvColumn(
      'Classification',
      (record) => reportText(record['caseClassification']),
      flex: 1.0,
    ),
    ReportCsvColumn(
      'Date Recorded',
      (record) => formatReportDateValue(record['reportedDate']),
      flex: 0.95,
      center: true,
    ),
    ReportCsvColumn(
      'Case Status',
      (record) => reportText(record['status']),
      flex: 0.95,
      center: true,
    ),
    ReportCsvColumn(
      'Treatment / Plan',
      (record) => reportText(
        (record['sourceRecord'] as Map?)?['treatment'],
        fallback: reportText((record['sourceRecord'] as Map?)?['plan']),
      ),
      flex: 1.25,
    ),
    ReportCsvColumn(
      'Remarks',
      (record) => reportText(record['remarks']),
      flex: 1.35,
    ),
  ];
}

Future<List<Map<String, dynamic>>> _loadNormalizedMorbidityRecords() async {
  final accessScope = await UserAccessScopeService.instance.loadCurrentScope();
  final snapshot = await buildScopedRecordQuery(
    getFirestoreInstance(),
    'checkup_records',
    accessScope,
  ).get();
  return _normalizeMorbidityRecords(snapshot.docs);
}

Future<List<Map<String, dynamic>>> _loadClassifiedMorbidityRecords(
  String targetClassification,
) async {
  final normalizedTarget = _normalizeClassification(targetClassification);
  final records = await _loadNormalizedMorbidityRecords();
  return records.where((record) {
    final normalized = _normalizeClassification(record['caseClassification']);
    return normalized == normalizedTarget;
  }).toList();
}

List<Map<String, dynamic>> _normalizeMorbidityRecords(
  List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
) {
  final records = docs
      .map((doc) {
        final source = Map<String, dynamic>.from(doc.data());
        final linkedCheckupId = _safeText(source['id'], fallback: doc.id);
        final linkedPatientId = _safeText(
          source['linkedPatientId'] ??
              source['patientId'] ??
              source['patientID'] ??
              source['patient_id'],
          fallback: 'Not linked',
        );
        final patientName = _safeText(
          source['patient'] ?? source['patientName'],
          fallback: 'Unknown patient',
        );
        final caseClassification = _safeText(
          source['caseClassification'] ??
              source['diseaseType'] ??
              source['classification'],
          fallback: 'General',
        );
        final disease = _safeText(
          source['symptoms'] ??
              source['disease'] ??
              source['diagnosis'] ??
              source['condition'] ??
              source['ai_category'],
          fallback: caseClassification == 'General'
              ? _safeText(source['details'], fallback: 'General clinical case')
              : caseClassification,
        );
        final severity = _safeText(
          source['severity'] ?? source['ai_severity'] ?? source['urgency'],
          fallback: 'Unspecified',
        );
        final remarks = _safeText(
          source['remarks'] ??
              source['plan'] ??
              source['details'] ??
              source['symptoms'],
          fallback: 'No remarks recorded',
        );
        final status = _safeText(
          source['status'] ?? source['caseStatus'],
          fallback: 'Pending',
        );
        final reportedDate =
            source['datetime'] ?? source['dateReported'] ?? source['date'];

        return {
          'id': linkedCheckupId,
          'documentId': doc.id,
          'linkedCheckupId': linkedCheckupId,
          'linkedPatientId': linkedPatientId,
          'patientName': patientName,
          'disease': disease,
          'caseClassification': caseClassification,
          'severity': severity,
          'remarks': remarks,
          'status': status,
          'reportedDate': reportedDate,
          'sourceRecord': source,
        };
      })
      .where(_isLinkedMorbidityRecord)
      .toList();

  records.sort(
    (a, b) =>
        _parseDate(b['reportedDate']).compareTo(_parseDate(a['reportedDate'])),
  );

  return records;
}

bool _isLinkedMorbidityRecord(Map<String, dynamic> record) {
  final classification = _safeText(record['caseClassification']).toLowerCase();
  final disease = _safeText(record['disease']).toLowerCase();
  final severity = _safeText(record['severity']).toLowerCase();
  final remarks = _safeText(record['remarks']).toLowerCase();

  return classification == 'communicable' ||
      classification == 'non-communicable' ||
      (classification.isNotEmpty && classification != 'general') ||
      (disease.isNotEmpty &&
          disease != 'general' &&
          disease != 'general clinical case' &&
          disease != 'unspecified') ||
      (severity.isNotEmpty && severity != 'n/a' && severity != 'unspecified') ||
      (remarks.isNotEmpty && remarks != 'no remarks recorded') ||
      disease.contains('disease') ||
      disease.contains('fever') ||
      disease.contains('infection') ||
      disease.contains('hypertension') ||
      disease.contains('diabetes');
}

String _safeText(dynamic value, {String fallback = ''}) {
  final text = value?.toString().trim() ?? '';
  if (text.isEmpty || text.toLowerCase() == 'null') {
    return fallback;
  }
  return text;
}

DateTime _parseDate(dynamic value) {
  return parseReportDateValue(value) ?? DateTime.fromMillisecondsSinceEpoch(0);
}

String _normalizeClassification(dynamic value) {
  return _safeText(value).toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
}

class _DashboardReportCard extends StatefulWidget {
  final _DashboardReportOption option;
  final VoidCallback onTap;

  const _DashboardReportCard({required this.option, required this.onTap});

  @override
  State<_DashboardReportCard> createState() => _DashboardReportCardState();
}

class _DashboardReportCardState extends State<_DashboardReportCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 340,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: _launcherDarkDeepTeal,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: widget.option.accent.withValues(
                alpha: _isHovered ? 0.85 : 0.4,
              ),
              width: 1.2,
            ),
            boxShadow: _isHovered
                ? [
                    BoxShadow(
                      color: widget.option.accent.withValues(alpha: 0.24),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ]
                : null,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: widget.option.accent.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(widget.option.icon, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.option.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      widget.option.subtitle,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.72),
                        fontSize: 12.5,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Icon(
                Icons.arrow_forward_rounded,
                color: _isHovered ? Colors.white : _launcherMutedCoolGray,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
