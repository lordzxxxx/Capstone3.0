import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:mycapstone_project/shared/widgets/spring_data_motion.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:mycapstone_project/firebase_helper.dart';
import 'package:mycapstone_project/shared/official_report_layout.dart';
import 'package:mycapstone_project/shared/barangay_scope_utils.dart';
import 'package:mycapstone_project/shared/malaybalay_barangays.dart';
import 'package:mycapstone_project/shared/user_access_scope.dart';
import 'package:mycapstone_project/web/roles/cho/portal/cho_navigation.dart';
import 'package:mycapstone_project/web/roles/cho/portal/cho_portal_components.dart';
import 'package:mycapstone_project/web/shared/components/app_metric_card.dart';
import 'package:mycapstone_project/web/shared/components/app_buttons.dart';
import 'package:mycapstone_project/web/roles/cho/portal/cho_portal_config.dart';
import 'package:mycapstone_project/web/features/auth/login.dart';
import 'package:mycapstone_project/web/shared/services/user_access_scope_service.dart';
import 'package:mycapstone_project/web/shared/utils/csv_download.dart';
import 'package:mycapstone_project/web/shared/utils/report_download.dart';
import 'package:mycapstone_project/web/shared/utils/report_branding.dart';
import 'package:mycapstone_project/web/shared/navigation/web_routes.dart';

// Names are historical (page was dark-themed); values now point at the
// white-card system used across the rest of the app.
const Color _primaryAqua = ChoColors.aqua;
const Color _secondaryIceBlue = ChoColors.ice;
const Color _darkDeepTeal = ChoColors.background;
const Color _panelSurface = ChoColors.surface;
const Color _panelAlt = ChoColors.surfaceAlt;
const Color _lightOffWhite = ChoColors.text;
const Color _mutedCoolGray = ChoColors.muted;

class AnalyticsPage extends StatefulWidget {
  const AnalyticsPage({super.key});

  @override
  State<AnalyticsPage> createState() => _AnalyticsPageState();
}

class _AnalyticsPageState extends State<AnalyticsPage> {
  static const Map<String, String> _collectionLabels = <String, String>{
    'patient_records': 'Patients',
    'checkup_records': 'Check-ups',
    'prenatal_records': 'Prenatal',
    'immunization_records': 'Immunization',
    'morbidity_records': 'Morbidity',
    'mortality_records': 'Mortality',
  };

  static const List<String> _periodModes = <String>[
    'Weekly',
    'Monthly',
    'Quarterly',
    'Yearly',
  ];

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final FirebaseFirestore _firestore = getFirestoreInstance();
  Timer? _refreshTimer;

  UserAccessScope _accessScope = UserAccessScope.unauthenticated;
  bool _isLoading = true;
  String _selectedBarangayFilter = 'ALL';
  String _selectedPeriodMode = 'Monthly';
  List<_NormalizedHealthRecord> _records = <_NormalizedHealthRecord>[];
  int _recentActivityPage = 1;
  static const int _recentActivityPageSize = 10;

  @override
  void initState() {
    super.initState();
    _loadAnalytics();
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _loadAnalytics(showLoader: false);
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadAnalytics({bool showLoader = true}) async {
    if (showLoader && mounted) {
      setState(() => _isLoading = true);
    }

    try {
      final scope = await UserAccessScopeService.instance.loadCurrentScope(
        forceRefresh: true,
      );
      if (!scope.isAuthenticated) {
        if (mounted) {
          Get.offAllNamed(WebRoutes.login);
        }
        return;
      }

      final snapshots = await Future.wait(
        _collectionLabels.keys.map(
          (collection) =>
              buildScopedRecordQuery(_firestore, collection, scope).get(),
        ),
      );

      final normalized = <_NormalizedHealthRecord>[];
      for (int i = 0; i < snapshots.length; i++) {
        final collection = _collectionLabels.keys.elementAt(i);
        for (final doc in snapshots[i].docs) {
          final rawData = Map<String, dynamic>.from(doc.data());
          rawData['id'] = doc.id;
          final scopedRaw = applyBarangayScopeToRecord(
            rawData,
            accessScope: scope,
          );
          if (!recordMatchesAccessScope(
            scopedRaw,
            scope,
            selectedBarangay: _selectedBarangayFilter == 'ALL'
                ? null
                : _selectedBarangayFilter,
          )) {
            continue;
          }

          final normalizedRecord = _normalizeRecord(collection, scopedRaw);
          if (normalizedRecord != null) {
            normalized.add(normalizedRecord);
          }
        }
      }

      normalized.sort((a, b) => b.recordDate.compareTo(a.recordDate));

      if (!mounted) return;
      setState(() {
        _accessScope = scope;
        _records = normalized;
        final pageCount = normalized.isEmpty
            ? 1
            : (normalized.length + _recentActivityPageSize - 1) ~/
                  _recentActivityPageSize;
        if (_recentActivityPage > pageCount) {
          _recentActivityPage = pageCount;
        }
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      Get.snackbar(
        'Analytics unavailable',
        'Failed to load analytics data: $e',
        backgroundColor: Colors.redAccent,
        colorText: Colors.white,
      );
    }
  }

  _NormalizedHealthRecord? _normalizeRecord(
    String collection,
    Map<String, dynamic> record,
  ) {
    final date = _extractDate(record);
    if (date == null) return null;

    final disease = _extractDiseaseLabel(collection, record);
    final patientLabel = _extractPatientLabel(collection, record);
    final severity = _extractSeverity(record);

    return _NormalizedHealthRecord(
      id: (record['id'] ?? '').toString(),
      sourceCollection: collection,
      sourceLabel: _collectionLabels[collection] ?? collection,
      patientLabel: patientLabel,
      diseaseLabel: disease,
      severityLabel: severity,
      barangay: (record['barangay'] ?? 'Unassigned').toString(),
      barangayCode: (record['barangayCode'] ?? '').toString(),
      barangayDistrict: (record['barangayDistrict'] ?? 'Unknown District')
          .toString(),
      recordDate: date,
      raw: record,
    );
  }

  DateTime? _extractDate(Map<String, dynamic> record) {
    final candidates = <dynamic>[
      record['datetime'],
      record['dateReported'],
      record['administrationDate'],
      record['registrationDate'],
      record['date'],
      record['createdAt'],
      record['time'],
    ];

    for (final value in candidates) {
      if (value == null) continue;
      if (value is Timestamp) return value.toDate();
      if (value is DateTime) return value;
      if (value is String && value.trim().isNotEmpty) {
        final parsed = DateTime.tryParse(value);
        if (parsed != null) return parsed;
      }
    }
    return null;
  }

  String _extractDiseaseLabel(String collection, Map<String, dynamic> record) {
    switch (collection) {
      case 'checkup_records':
        return (record['diseaseType'] ?? record['type'] ?? 'General Check-up')
            .toString();
      case 'prenatal_records':
        return (record['riskLevel'] ?? 'Prenatal Monitoring').toString();
      case 'immunization_records':
        return (record['vaccine'] ?? 'Immunization').toString();
      case 'mortality_records':
        return (record['causeOfDeath'] ?? 'Mortality Case').toString();
      case 'morbidity_records':
        return (record['disease'] ??
                record['diseaseName'] ??
                record['condition'] ??
                'Morbidity Case')
            .toString();
      default:
        return (record['chiefComplaint'] ??
                record['currentSymptoms'] ??
                'Patient Registry')
            .toString();
    }
  }

  String _extractPatientLabel(String collection, Map<String, dynamic> record) {
    if (collection == 'patient_records') {
      final firstName = (record['firstName'] ?? '').toString();
      final surname = (record['surname'] ?? '').toString();
      final fullName = '$firstName $surname'.trim();
      return fullName.isEmpty ? 'Unnamed Patient' : fullName;
    }

    return (record['patientName'] ??
            record['patient'] ??
            record['name'] ??
            'Unknown Patient')
        .toString();
  }

  String _extractSeverity(Map<String, dynamic> record) {
    return (record['severity'] ??
            record['ai_severity'] ??
            record['riskLevel'] ??
            record['status'] ??
            record['verification'] ??
            'Normal')
        .toString();
  }

  int _severityWeight(String label) {
    final normalized = label.toLowerCase();
    if (normalized.contains('critical')) return 5;
    if (normalized.contains('high') || normalized.contains('severe')) return 4;
    if (normalized.contains('moderate') || normalized.contains('follow')) {
      return 3;
    }
    if (normalized.contains('mild') || normalized.contains('pending')) return 2;
    return 1;
  }

  Map<String, int> _diseaseCounts() {
    final counts = <String, int>{};
    for (final record in _records) {
      counts.update(
        record.diseaseLabel,
        (value) => value + 1,
        ifAbsent: () => 1,
      );
    }
    return counts;
  }

  List<_HeatmapEntry> _heatmapEntries() {
    final entries = <String, _HeatmapEntry>{};
    for (final barangay in MalaybalayBarangays.all) {
      entries[barangay.name] = _HeatmapEntry(
        barangay: barangay.name,
        district: barangay.district,
        caseCount: 0,
        severityScore: 0,
      );
    }

    for (final record in _records) {
      final existing =
          entries[record.barangay] ??
          _HeatmapEntry(
            barangay: record.barangay,
            district: record.barangayDistrict,
            caseCount: 0,
            severityScore: 0,
          );
      entries[record.barangay] = existing.copyWith(
        caseCount: existing.caseCount + 1,
        severityScore:
            existing.severityScore + _severityWeight(record.severityLabel),
      );
    }

    final list = entries.values.toList();
    list.sort((a, b) {
      final byCases = b.caseCount.compareTo(a.caseCount);
      if (byCases != 0) return byCases;
      return b.severityScore.compareTo(a.severityScore);
    });
    return list;
  }

  Map<String, int> _trendBuckets() {
    final buckets = <String, int>{};
    for (final record in _records) {
      final label = _periodLabel(record.recordDate);
      buckets.update(label, (value) => value + 1, ifAbsent: () => 1);
    }
    final keys = buckets.keys.toList()..sort();
    final ordered = <String, int>{};
    for (final key in keys) {
      ordered[key] = buckets[key]!;
    }
    return ordered;
  }

  String _periodLabel(DateTime date) {
    switch (_selectedPeriodMode) {
      case 'Weekly':
        final weekStart = date.subtract(Duration(days: date.weekday - 1));
        return '${weekStart.year}-W${_isoWeekNumber(weekStart).toString().padLeft(2, '0')}';
      case 'Quarterly':
        final quarter = ((date.month - 1) ~/ 3) + 1;
        return '${date.year}-Q$quarter';
      case 'Yearly':
        return '${date.year}';
      case 'Monthly':
      default:
        return '${date.year}-${date.month.toString().padLeft(2, '0')}';
    }
  }

  int _isoWeekNumber(DateTime date) {
    final thursday = date.add(Duration(days: 4 - date.weekday));
    final firstDay = DateTime(thursday.year, 1, 1);
    return ((thursday.difference(firstDay).inDays) / 7).floor() + 1;
  }

  Future<void> _exportCsv() async {
    final buffer = StringBuffer()
      ..writeln('Source,Patient,Disease,Severity,Barangay,District,Date');
    for (final record in _records) {
      buffer.writeln(
        [
          record.sourceLabel,
          record.patientLabel,
          record.diseaseLabel,
          record.severityLabel,
          record.barangay,
          record.barangayDistrict,
          record.recordDate.toIso8601String(),
        ].map(_escapeCsv).join(','),
      );
    }

    downloadCsvFile(
      bytes: utf8.encode(buffer.toString()),
      filename: _reportFileName('csv'),
    );
  }

  Future<void> _exportExcel() async {
    final scopeName = _selectedBarangayFilter == 'ALL'
        ? (_accessScope.canViewAllBarangays
              ? 'Citywide'
              : _accessScope.barangay)
        : _selectedBarangayFilter;
    final branding = await loadReportBranding(barangayName: scopeName);
    final rows = _records
        .map(
          (record) =>
              '''
            <tr>
              <td>${_escapeHtml(record.sourceLabel)}</td>
              <td>${_escapeHtml(record.patientLabel)}</td>
              <td>${_escapeHtml(record.diseaseLabel)}</td>
              <td class="center">${_escapeHtml(record.severityLabel)}</td>
              <td>${_escapeHtml(record.barangay)}</td>
              <td>${_escapeHtml(record.barangayDistrict)}</td>
              <td class="center">${DateFormat('yyyy-MM-dd').format(record.recordDate)}</td>
            </tr>
          ''',
        )
        .join();

    final html =
        '''
<!DOCTYPE html>
<html xmlns:o="urn:schemas-microsoft-com:office:office"
      xmlns:x="urn:schemas-microsoft-com:office:excel">
<head>
  <meta charset="utf-8">
  <style>
    @page { size: landscape; margin: 0.45in; }
    body { font-family: Arial, sans-serif; color: #000000; font-size: 10pt; }
    table { border-collapse: collapse; width: 100%; }
    .header td { border: 0; vertical-align: middle; }
    .seal-cell { width: 78px; text-align: center; }
    .seal { width: 58px; height: 58px; object-fit: contain; }
    .seal-label { font-size: 6pt; font-weight: bold; color: #000000; }
    .identity { text-align: center; }
    .province { font-size: 8pt; font-weight: bold; color: #000000; }
    .city { font-size: 16pt; font-weight: bold; color: #000000; }
    .program { font-size: 9pt; font-weight: bold; color: #000000; letter-spacing: 1px; }
    .system { font-size: 8pt; font-weight: bold; color: #000000; }
    .title { border-top: 1px solid #000000; padding: 8px 0 2px; font-size: 15pt; font-weight: bold; color: #000000; }
    .subtitle { color: #000000; padding-bottom: 10px; }
    .records { table-layout: fixed; }
    .records thead { display: table-header-group; }
    .records th { background: #FFFFFF; color: #000000; border: 1px solid #000000; border-bottom: 2px solid #000000; padding: 7px; text-align: left; }
    .records td { border: 1px solid #000000; padding: 6px; word-wrap: break-word; }
    .records tr:nth-child(even) td { background: #FFFFFF; }
    .center { text-align: center; }
    .signatures { margin-top: 28px; table-layout: fixed; }
    .signatures td { border: 1px solid #000000; padding: 10px; vertical-align: top; height: 110px; }
    .signature-line { display: block; border-bottom: 1px solid #000000; height: 26px; }
    .signature-label { font-size: 8pt; color: #000000; }
    .footer { border-top: 1px solid #000000; color: #000000; font-size: 8pt; padding-top: 6px; margin-top: 18px; }
  </style>
</head>
<body>
  <table class="header">
    <tr>
      <td class="seal-cell">${_excelImage(branding.cityLogo, 'Malaybalay City seal')}<br><span class="seal-label">MALAYBALAY CITY</span></td>
      <td class="seal-cell">${_excelImage(branding.healthOfficeLogo, 'City Health Office seal')}<br><span class="seal-label">CITY HEALTH OFFICE</span></td>
      <td class="seal-cell">${_excelImage(branding.barangayLogo, 'Barangay seal')}<br><span class="seal-label">BARANGAY</span></td>
      <td class="identity"><div class="province">REPUBLIC OF THE PHILIPPINES • PROVINCE OF BUKIDNON</div><div class="city">CITY OF MALAYBALAY</div><div class="program">SAKA TA MALAYBALAY</div><div class="system">CITY HEALTH OFFICE ANALYTICS</div></td>
    </tr>
  </table>
  <div class="title">CHO Health Records Analytics Report</div>
  <div class="subtitle">Scope: ${_escapeHtml(scopeName)} &nbsp; | &nbsp; Grouping: ${_escapeHtml(_selectedPeriodMode)} &nbsp; | &nbsp; Generated: ${DateFormat('MMMM dd, yyyy hh:mm a').format(DateTime.now())}</div>
  <table class="records">
    <thead><tr>
      <th>Source</th><th>Patient</th><th>Disease / Condition</th><th>Severity</th><th>Barangay</th><th>District</th><th>Date</th>
    </tr></thead>
    <tbody>$rows</tbody>
  </table>
  <table class="signatures">
    <tr>
      ${_excelSignatureCell('Barangay Captain', '', 'Barangay Captain')}
      ${_excelSignatureCell('Barangay Kagawad in Health', '', 'Barangay Kagawad in Health')}
      ${_excelSignatureCell('BHW Head', '', 'BHW Head')}
      ${_excelSignatureCell('BHW Assigned on Duty', '', 'BHW Assigned on Duty')}
    </tr>
  </table>
  <div class="footer">Generated by AI-DSUHIS • Confidential health information</div>
</body>
</html>
''';

    downloadReportFile(
      bytes: utf8.encode(html),
      filename: _reportFileName('xls'),
      mimeType: 'application/vnd.ms-excel',
    );
  }

  Future<void> _exportPdf() async {
    final pdf = pw.Document();
    final scopeName = _selectedBarangayFilter == 'ALL'
        ? (_accessScope.canViewAllBarangays
              ? 'Citywide'
              : _accessScope.barangay)
        : _selectedBarangayFilter;
    final branding = await loadReportBranding(barangayName: scopeName);
    final cityLogo = branding.cityLogo == null
        ? null
        : pw.MemoryImage(Uint8List.fromList(branding.cityLogo!));
    final healthOfficeLogo = branding.healthOfficeLogo == null
        ? null
        : pw.MemoryImage(Uint8List.fromList(branding.healthOfficeLogo!));
    final barangayLogo = branding.barangayLogo == null
        ? null
        : pw.MemoryImage(Uint8List.fromList(branding.barangayLogo!));
    final heatmap = _heatmapEntries().take(10).toList();
    final diseases = _diseaseCounts().entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.fromLTRB(28, 32, 28, 28),
        footer: (context) => buildOfficialReportFooter(
          context,
          footerText:
              'Generated by AI-DSUHIS • Confidential health information',
        ),
        build: (context) => [
          buildOfficialReportHeader(
            title: 'CHO Health Records Analytics Report',
            systemName: 'CITY HEALTH OFFICE ANALYTICS',
            subtitle: 'Scope: $scopeName  |  Grouping: $_selectedPeriodMode',
            barangayName: scopeName,
            generatedAt: DateTime.now(),
            cityLogo: cityLogo,
            healthOfficeLogo: healthOfficeLogo,
            barangayLogo: barangayLogo,
          ),
          pw.SizedBox(height: 16),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.black),
            children: [
              pw.TableRow(
                children: [
                  _pdfCell('Metric', header: true),
                  _pdfCell('Value', header: true),
                ],
              ),
              pw.TableRow(
                children: [
                  _pdfCell('Visible records'),
                  _pdfCell('${_records.length}'),
                ],
              ),
              pw.TableRow(
                children: [
                  _pdfCell('Tracked diseases'),
                  _pdfCell('${_diseaseCounts().length}'),
                ],
              ),
              pw.TableRow(
                children: [
                  _pdfCell('Highest volume barangay'),
                  _pdfCell(heatmap.isEmpty ? 'None' : heatmap.first.barangay),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 16),
          pw.Text(
            'Top Disease Trends',
            style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 8),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.black),
            children: [
              pw.TableRow(
                children: [
                  _pdfCell('Disease', header: true),
                  _pdfCell('Cases', header: true),
                ],
              ),
              ...diseases
                  .take(8)
                  .map(
                    (entry) => pw.TableRow(
                      children: [
                        _pdfCell(entry.key),
                        _pdfCell('${entry.value}'),
                      ],
                    ),
                  ),
            ],
          ),
          pw.SizedBox(height: 16),
          pw.Text(
            'Recent Records',
            style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 8),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.black),
            children: [
              pw.TableRow(
                children: [
                  _pdfCell('Source', header: true),
                  _pdfCell('Patient', header: true),
                  _pdfCell('Disease', header: true),
                  _pdfCell('Barangay', header: true),
                  _pdfCell('Date', header: true),
                ],
              ),
              ..._records
                  .take(12)
                  .map(
                    (record) => pw.TableRow(
                      children: [
                        _pdfCell(record.sourceLabel),
                        _pdfCell(record.patientLabel),
                        _pdfCell(record.diseaseLabel),
                        _pdfCell(record.barangay),
                        _pdfCell(
                          record.recordDate.toIso8601String().split('T').first,
                        ),
                      ],
                    ),
                  ),
            ],
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

    final bytes = await pdf.save();
    downloadReportFile(
      bytes: bytes,
      filename: _reportFileName('pdf'),
      mimeType: 'application/pdf',
    );
  }

  pw.Widget _pdfCell(String text, {bool header = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(6),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontWeight: header ? pw.FontWeight.bold : pw.FontWeight.normal,
          fontSize: 10,
        ),
      ),
    );
  }

  String _reportFileName(String extension) {
    final scopeName = _selectedBarangayFilter == 'ALL'
        ? (_accessScope.canViewAllBarangays
              ? 'citywide'
              : _accessScope.barangayCode)
        : (_selectedBarangayFilter
              .toLowerCase()
              .replaceAll(' ', '-')
              .replaceAll('.', ''));
    final period = _selectedPeriodMode.toLowerCase();
    return 'dsuhis-$scopeName-$period-report.$extension';
  }

  String _escapeCsv(String value) {
    final escaped = value.replaceAll('"', '""');
    return '"$escaped"';
  }

  String _escapeHtml(String value) {
    return value
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#39;');
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

  String _excelSignatureCell(String label, String name, String position) {
    return '<td><b>${_escapeHtml(label.toUpperCase())}</b><br><span class="signature-line"></span><span class="signature-label">Printed Name: ${_escapeHtml(name.isEmpty ? ' ' : name)}<br>Position: ${_escapeHtml(position)}</span></td>';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: _darkDeepTeal,
      drawer: const ChoNavigationDrawer(current: ChoDestination.reports),
      appBar: AppBar(
        // Keep reports aligned with the CHO portal shell. The page content is
        // intentionally light, but the navigation bar stays the shared navy
        // surface so its title and controls remain legible.
        backgroundColor: ChoColors.navBackground,
        foregroundColor: ChoColors.navText,
        title: const Text(
          'CHO Reports and Analytics',
          style: TextStyle(
            fontFamily: 'Manrope',
            color: ChoColors.navText,
            fontWeight: FontWeight.w800,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        actions: [
          IconButton(
            onPressed: _loadAnalytics,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: _primaryAqua))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(),
                  const SizedBox(height: 14),
                  _buildFilters(),
                  const SizedBox(height: 14),
                  _buildSummaryGrid(),
                  const SizedBox(height: 14),
                  _buildTrendSection(),
                  const SizedBox(height: 14),
                  _buildHeatmapSection(),
                  const SizedBox(height: 14),
                  _buildRecentRecordsSection(),
                  const SizedBox(height: 20),
                  _buildExportSection(),
                ],
              ),
            ),
    );
  }

  Widget _buildHeader() {
    final accessLabel = _accessScope.canViewAllBarangays
        ? 'CHO Central Command View'
        : 'Barangay Scoped View';
    final accessDescription = _accessScope.canViewAllBarangays
        ? 'Monitor every barangay, compare disease movement, and drill into detailed records.'
        : 'Access is restricted to ${_accessScope.barangay}. Reports and analytics are isolated to your barangay scope.';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _panelSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _primaryAqua.withValues(alpha: 0.18)),
      ),
      child: Wrap(
        spacing: 20,
        runSpacing: 20,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 720,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  accessLabel,
                  style: const TextStyle(
                    color: _lightOffWhite,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  accessDescription,
                  style: TextStyle(
                    color: _lightOffWhite.withValues(alpha: 0.78),
                    fontSize: 15,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: _panelAlt,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFD9E5F2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Active scope',
                  style: TextStyle(
                    color: _mutedCoolGray,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _accessScope.canViewAllBarangays
                      ? (_selectedBarangayFilter == 'ALL'
                            ? 'All barangays'
                            : _selectedBarangayFilter)
                      : _accessScope.barangay,
                  style: const TextStyle(
                    color: _lightOffWhite,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _selectedPeriodMode,
                  style: const TextStyle(color: _primaryAqua),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilters() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _panelSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _primaryAqua.withValues(alpha: 0.16)),
      ),
      child: Wrap(
        spacing: 14,
        runSpacing: 14,
        children: [
          SizedBox(
            width: 190,
            child: DropdownButtonFormField<String>(
              initialValue: _selectedPeriodMode,
              dropdownColor: _panelAlt,
              style: const TextStyle(color: _lightOffWhite),
              decoration: _inputDecoration('Trend grouping'),
              items: _periodModes
                  .map(
                    (value) => DropdownMenuItem<String>(
                      value: value,
                      child: Text(value),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value == null) return;
                setState(() => _selectedPeriodMode = value);
              },
            ),
          ),
          if (_accessScope.canViewAllBarangays)
            SizedBox(
              width: 260,
              child: DropdownButtonFormField<String>(
                initialValue: _selectedBarangayFilter,
                dropdownColor: _panelAlt,
                style: const TextStyle(color: _lightOffWhite),
                decoration: _inputDecoration('Barangay filter'),
                items:
                    <String>[
                          'ALL',
                          ...MalaybalayBarangays.all.map((item) => item.name),
                        ]
                        .map(
                          (value) => DropdownMenuItem<String>(
                            value: value,
                            child: Text(
                              value == 'ALL' ? 'All barangays' : value,
                            ),
                          ),
                        )
                        .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    _selectedBarangayFilter = value;
                    _recentActivityPage = 1;
                  });
                  _loadAnalytics(showLoader: false);
                },
              ),
            ),
          ActionChip(
            avatar: const Icon(Icons.policy_outlined, size: 18),
            label: const Text('Isolation enforced'),
            backgroundColor: _darkDeepTeal,
            labelStyle: const TextStyle(color: _lightOffWhite),
            side: BorderSide(color: _primaryAqua.withValues(alpha: 0.2)),
            onPressed: () {},
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: _lightOffWhite),
      filled: true,
      fillColor: _darkDeepTeal,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
    );
  }

  Widget _buildSummaryGrid() {
    final diseaseCounts = _diseaseCounts().entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final heatmap = _heatmapEntries();
    final topHeat = heatmap.isEmpty ? null : heatmap.first;

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1000
            ? 4
            : constraints.maxWidth >= 600
            ? 2
            : 1;
        return GridView.count(
          crossAxisCount: columns,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: columns == 1 ? 2.5 : 2.1,
          children: [
            _buildMetricCard(
              'Visible records',
              '${_records.length}',
              Icons.dataset_outlined,
            ),
            _buildMetricCard(
              'Tracked diseases',
              '${diseaseCounts.length}',
              Icons.coronavirus_outlined,
            ),
            _buildMetricCard(
              'Leading disease',
              diseaseCounts.isEmpty ? 'None' : diseaseCounts.first.key,
              Icons.trending_up_outlined,
            ),
            _buildMetricCard(
              'Highest-load barangay',
              topHeat == null ? 'None' : topHeat.barangay,
              Icons.location_city_outlined,
            ),
          ],
        );
      },
    );
  }

  Widget _buildMetricCard(String label, String value, IconData icon) {
    return AppMetricCard(label: label, value: value, icon: icon, compact: true);
  }

  Widget _buildTrendSection() {
    final trendData = _trendBuckets().entries.toList();
    final maxCount = trendData.isEmpty
        ? 1
        : trendData.map((entry) => entry.value).reduce((a, b) => a > b ? a : b);
    final diseaseData = _diseaseCounts().entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _panelSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _primaryAqua.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Disease Trends and Comparison',
            style: TextStyle(
              color: _lightOffWhite,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Track disease movement by $_selectedPeriodMode and compare burden between barangays.',
            style: TextStyle(color: _lightOffWhite.withValues(alpha: 0.72)),
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final isStacked = constraints.maxWidth < 980;
              final trendWidget = _buildTrendBars(trendData, maxCount);
              final diseaseWidget = _buildTopDiseaseTable(diseaseData);
              if (isStacked) {
                return Column(
                  children: [
                    trendWidget,
                    const SizedBox(height: 16),
                    diseaseWidget,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: trendWidget),
                  const SizedBox(width: 18),
                  Expanded(child: diseaseWidget),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTrendBars(List<MapEntry<String, int>> trendData, int maxCount) {
    final visible = trendData.length > 10
        ? trendData.sublist(trendData.length - 10)
        : trendData;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _darkDeepTeal,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Trend Volume',
            style: TextStyle(
              color: _lightOffWhite,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 14),
          if (visible.isEmpty)
            Text(
              'No trend data available for the current scope.',
              style: TextStyle(color: _lightOffWhite.withValues(alpha: 0.65)),
            )
          else
            ...visible.map((entry) {
              final fraction = entry.value / maxCount;
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    SizedBox(
                      width: 90,
                      child: Text(
                        entry.key,
                        style: const TextStyle(color: _lightOffWhite),
                      ),
                    ),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          value: fraction,
                          minHeight: 12,
                          backgroundColor: _panelAlt,
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            _primaryAqua,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '${entry.value}',
                      style: const TextStyle(
                        color: _lightOffWhite,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildTopDiseaseTable(List<MapEntry<String, int>> diseaseData) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _darkDeepTeal,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Top Disease Burden',
            style: TextStyle(
              color: _lightOffWhite,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 14),
          if (diseaseData.isEmpty)
            Text(
              'No disease entries found.',
              style: TextStyle(color: _lightOffWhite.withValues(alpha: 0.65)),
            )
          else
            ...diseaseData
                .take(8)
                .map(
                  (entry) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            entry.key,
                            style: const TextStyle(color: _lightOffWhite),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: _panelAlt,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '${entry.value}',
                            style: const TextStyle(
                              color: _primaryAqua,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
        ],
      ),
    );
  }

  Widget _buildHeatmapSection() {
    final heatmap = _heatmapEntries();
    final maxCases = heatmap.fold<int>(
      1,
      (max, item) => item.caseCount > max ? item.caseCount : max,
    );
    final ranking = heatmap
        .where((entry) => entry.caseCount > 0)
        .take(10)
        .toList();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _panelSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _primaryAqua.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Barangay Heatmap Intelligence',
            style: TextStyle(
              color: _lightOffWhite,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Color intensity reflects case concentration. Ranking combines total cases and severity score for rapid intervention planning.',
            style: TextStyle(color: _lightOffWhite.withValues(alpha: 0.72)),
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 1000
                  ? 4
                  : constraints.maxWidth >= 600
                  ? 2
                  : 1;
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: heatmap.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: columns == 1 ? 2.8 : 1.35,
                ),
                itemBuilder: (context, index) {
                  final entry = heatmap[index];
                  final intensity = entry.caseCount == 0
                      ? 0.08
                      : (entry.caseCount / maxCases).clamp(0.12, 1.0);
                  final color = Color.lerp(
                    ChoColors.ice.withValues(alpha: 0.15),
                    ChoColors.aqua.withValues(alpha: 0.90),
                    intensity,
                  )!;
                  return Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _lightOffWhite.withValues(alpha: 0.08),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.barangay,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          entry.district,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.78),
                            fontSize: 12,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '${entry.caseCount} cases',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                        Text(
                          'Severity score ${entry.severityScore}',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.78),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
          const SizedBox(height: 20),
          if (ranking.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _darkDeepTeal,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Priority Ranking',
                    style: TextStyle(
                      color: _lightOffWhite,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...ranking.asMap().entries.map(
                    (entry) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 28,
                            child: Text(
                              '#${entry.key + 1}',
                              style: const TextStyle(
                                color: _primaryAqua,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              entry.value.barangay,
                              style: const TextStyle(color: _lightOffWhite),
                            ),
                          ),
                          Text(
                            '${entry.value.caseCount} / ${entry.value.severityScore}',
                            style: const TextStyle(color: _mutedCoolGray),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildRecentRecordsSection() {
    final pageCount = _records.isEmpty
        ? 1
        : (_records.length + _recentActivityPageSize - 1) ~/
              _recentActivityPageSize;
    final page = _recentActivityPage.clamp(1, pageCount);
    final startIndex = _records.isEmpty
        ? 0
        : (page - 1) * _recentActivityPageSize;
    final pageRecords = _records
        .skip(startIndex)
        .take(_recentActivityPageSize)
        .toList(growable: false);
    final firstVisible = _records.isEmpty ? 0 : startIndex + 1;
    final lastVisible = startIndex + pageRecords.length;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _panelSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _primaryAqua.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Recent Activity and Drilldown',
            style: TextStyle(
              color: _lightOffWhite,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Review the latest encoded records across modules and drill down to patient-level detail for compliance and monitoring.',
            style: TextStyle(color: _lightOffWhite.withValues(alpha: 0.72)),
          ),
          const SizedBox(height: 18),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SpringDataMotion(
              dataKey: pageRecords,
              child: DataTable(
                headingTextStyle: const TextStyle(
                  color: _lightOffWhite,
                  fontWeight: FontWeight.w800,
                ),
                dataTextStyle: const TextStyle(
                  color: _lightOffWhite,
                  fontWeight: FontWeight.w500,
                ),
                headingRowColor: WidgetStatePropertyAll(
                  _darkDeepTeal.withValues(alpha: 0.85),
                ),
                dataRowColor: const WidgetStatePropertyAll(_panelAlt),
                dividerThickness: 0.6,
                columns: const [
                  DataColumn(label: Text('Source')),
                  DataColumn(label: Text('Patient')),
                  DataColumn(label: Text('Disease / Condition')),
                  DataColumn(label: Text('Barangay')),
                  DataColumn(label: Text('Severity')),
                  DataColumn(label: Text('Date')),
                ],
                rows: pageRecords.map((record) {
                  return DataRow(
                    cells: [
                      DataCell(Text(record.sourceLabel)),
                      DataCell(Text(record.patientLabel)),
                      DataCell(Text(record.diseaseLabel)),
                      DataCell(Text(record.barangay)),
                      DataCell(Text(record.severityLabel)),
                      DataCell(
                        Text(
                          record.recordDate.toIso8601String().split('T').first,
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final summary = Text(
                'Showing $firstVisible–$lastVisible of ${_records.length} activities',
                style: const TextStyle(
                  color: _lightOffWhite,
                  fontWeight: FontWeight.w600,
                ),
              );
              final controls = Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  OutlinedButton.icon(
                    onPressed: page > 1
                        ? () => setState(() => _recentActivityPage = page - 1)
                        : null,
                    icon: const Icon(Icons.chevron_left_rounded, size: 18),
                    label: const Text('Previous'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _lightOffWhite,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: _primaryAqua.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: _primaryAqua.withValues(alpha: 0.32),
                      ),
                    ),
                    child: Text(
                      'Page $page of $pageCount',
                      style: const TextStyle(
                        color: _lightOffWhite,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton.icon(
                    onPressed: page < pageCount
                        ? () => setState(() => _recentActivityPage = page + 1)
                        : null,
                    icon: const Icon(Icons.chevron_right_rounded, size: 18),
                    label: const Text('Next'),
                    iconAlignment: IconAlignment.end,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _lightOffWhite,
                    ),
                  ),
                ],
              );
              if (constraints.maxWidth < 700) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    summary,
                    const SizedBox(height: 12),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: controls,
                    ),
                  ],
                );
              }
              return Row(children: [summary, const Spacer(), controls]);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildExportSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _panelSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _primaryAqua.withValues(alpha: 0.16)),
      ),
      child: Wrap(
        spacing: 14,
        runSpacing: 14,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 420,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Reporting and Export',
                  style: TextStyle(
                    color: _lightOffWhite,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _accessScope.canViewAllBarangays
                      ? 'Generate city-wide reports, barangay comparisons, and focused barangay exports on demand.'
                      : 'Generate barangay-specific reports for weekly, monthly, quarterly, and yearly review.',
                  style: TextStyle(
                    color: _lightOffWhite.withValues(alpha: 0.72),
                  ),
                ),
              ],
            ),
          ),
          OutlinedButton.icon(
            onPressed: _records.isEmpty ? null : _exportCsv,
            icon: const Icon(Icons.table_view_outlined),
            label: const Text('Export CSV'),
            style: AppButtonStyles.outline(),
          ),
          OutlinedButton.icon(
            onPressed: _records.isEmpty ? null : _exportExcel,
            icon: const Icon(Icons.grid_on_outlined),
            label: const Text('Export Excel'),
            style: AppButtonStyles.outline(),
          ),
          FilledButton.icon(
            onPressed: _records.isEmpty ? null : _exportPdf,
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: const Text('Export PDF'),
            style: AppButtonStyles.report(),
          ),
        ],
      ),
    );
  }
}

class _NormalizedHealthRecord {
  final String id;
  final String sourceCollection;
  final String sourceLabel;
  final String patientLabel;
  final String diseaseLabel;
  final String severityLabel;
  final String barangay;
  final String barangayCode;
  final String barangayDistrict;
  final DateTime recordDate;
  final Map<String, dynamic> raw;

  const _NormalizedHealthRecord({
    required this.id,
    required this.sourceCollection,
    required this.sourceLabel,
    required this.patientLabel,
    required this.diseaseLabel,
    required this.severityLabel,
    required this.barangay,
    required this.barangayCode,
    required this.barangayDistrict,
    required this.recordDate,
    required this.raw,
  });
}

class _HeatmapEntry {
  final String barangay;
  final String district;
  final int caseCount;
  final int severityScore;

  const _HeatmapEntry({
    required this.barangay,
    required this.district,
    required this.caseCount,
    required this.severityScore,
  });

  _HeatmapEntry copyWith({int? caseCount, int? severityScore}) {
    return _HeatmapEntry(
      barangay: barangay,
      district: district,
      caseCount: caseCount ?? this.caseCount,
      severityScore: severityScore ?? this.severityScore,
    );
  }
}
