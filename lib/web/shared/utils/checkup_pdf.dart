import 'dart:convert';

import 'package:mycapstone_project/web/shared/utils/record_pdf_builder.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

Future<List<int>> buildCheckupPdfBytes(Map<String, dynamic> record) async {
  final patientName = pdfText(record['patient'], fallback: 'Unknown Patient');

  final patientFields = <MapEntry<String, String>>[
    pdfField('Patient Name', patientName),
    pdfField('Age', record['age']),
    pdfField('Address', record['address']),
  ];

  final encounterFields = <MapEntry<String, String>>[
    pdfField('Record ID', record['id']),
    pdfField('Date & Time', record['datetime']),
    pdfField(
      'Disease Classification',
      record['diseaseType'],
      fallback: 'General',
    ),
    pdfField('Status', record['status'], fallback: 'Completed'),
    pdfField('Follow-up Date', record['followup']),
  ];

  final clinicalFields = <MapEntry<String, String>>[
    pdfField('Vital Signs', record['vitalsigns']),
    pdfField('Symptoms', record['symptoms']),
    pdfField('Treatment Plan', record['plan']),
    pdfField('Assessment Details', record['details']),
  ];

  final category = pdfText(record['ai_category'], fallback: '');
  final severity = pdfText(record['ai_severity'], fallback: '');
  final method = pdfText(record['ai_method'], fallback: '');
  final keywords = _safeKeywords(record['ai_keywords']);
  final confidence = _safeConfidence(record['ai_confidence']);
  final recoveryPlan = _parseRecoveryPlan(record['ai_recovery_plan']);

  return buildRecordPdfBytes(
    title: 'Check-Up Record',
    subtitle: '',
    footerText: 'Generated from the Check-Up records module.',
    barangayName: pdfText(record['barangay']),
    summaryFields: [],
    signatureSectionOnNewPage: true,
    signatureSectionAtPageBottom: true,
    sections: [
      RecordPdfSection(title: 'Patient Information', fields: patientFields),
      RecordPdfSection(title: 'Encounter Details', fields: encounterFields),
      RecordPdfSection(title: 'Clinical Summary', fields: clinicalFields),
    ],
    trailingWidgets: [
      // AI Classification and Recovery recommendations removed as per requirements
    ],
  );
}

String buildCheckupPdfFilename(Map<String, dynamic> record) {
  return buildRecordPdfFilename(
    prefix: 'checkup',
    subject: pdfText(record['patient'], fallback: 'patient'),
    rawDate: record['datetime'],
  );
}

pw.Widget _buildAiSection({
  required String category,
  required String severity,
  required String method,
  required double confidence,
  required List<String> keywords,
}) {
  final aiFields = <MapEntry<String, String>>[
    if (category.isNotEmpty) MapEntry('Category', category),
    if (severity.isNotEmpty) MapEntry('Severity', severity),
    if (confidence > 0)
      MapEntry('Confidence', '${(confidence * 100).toStringAsFixed(0)}%'),
    if (method.isNotEmpty) MapEntry('Method', method),
  ];

  return _buildSupplementSection(
    title: 'AI Classification Review',
    backgroundColor: PdfColor.fromHex('#F4FAFC'),
    borderColor: PdfColors.black,
    titleColor: PdfColors.black,
    children: [
      ...aiFields.map(_buildFieldRow),
      if (keywords.isNotEmpty) ...[
        pw.SizedBox(height: 8),
        _buildBulletList('Keywords', keywords),
      ],
    ],
  );
}

pw.Widget _buildRecoverySection(Map<String, dynamic> recoveryPlan) {
  final homeCare = _safeStringList(recoveryPlan['home_care']);
  final precautions = _safeStringList(recoveryPlan['precautions']);
  final generalAdvice = _safeStringList(recoveryPlan['general_advice']);
  final estimatedRecovery = pdfText(
    recoveryPlan['estimated_recovery'],
    fallback: '',
  );

  return _buildSupplementSection(
    title: 'Recovery Recommendations',
    backgroundColor: PdfColor.fromHex('#F8FBF6'),
    borderColor: PdfColors.black,
    titleColor: PdfColors.black,
    children: [
      if (estimatedRecovery.isNotEmpty)
        _buildFieldRow(MapEntry('Estimated Recovery', estimatedRecovery)),
      if (homeCare.isNotEmpty) ...[
        pw.SizedBox(height: 8),
        _buildBulletList('Home Care', homeCare),
      ],
      if (precautions.isNotEmpty) ...[
        pw.SizedBox(height: 8),
        _buildBulletList('Precautions', precautions),
      ],
      if (generalAdvice.isNotEmpty) ...[
        pw.SizedBox(height: 8),
        _buildBulletList('General Advice', generalAdvice),
      ],
    ],
  );
}

pw.Widget _buildSupplementSection({
  required String title,
  required PdfColor backgroundColor,
  required PdfColor borderColor,
  required PdfColor titleColor,
  required List<pw.Widget> children,
}) {
  return pw.Container(
    width: double.infinity,
    padding: const pw.EdgeInsets.all(16),
    decoration: pw.BoxDecoration(
      color: backgroundColor,
      border: pw.Border.all(color: borderColor),
      borderRadius: pw.BorderRadius.circular(10),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          title,
          style: pw.TextStyle(
            fontSize: 13,
            fontWeight: pw.FontWeight.bold,
            color: titleColor,
          ),
        ),
        if (children.isNotEmpty) ...[pw.SizedBox(height: 10), ...children],
      ],
    ),
  );
}

pw.Widget _buildFieldRow(MapEntry<String, String> field) {
  return pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 8),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(
          width: 150,
          child: pw.Text(
            field.key,
            style: pw.TextStyle(
              fontSize: 10,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.black,
            ),
          ),
        ),
        pw.SizedBox(
          width: 10,
          child: pw.Text(
            ':',
            style: pw.TextStyle(fontSize: 10, color: PdfColors.black),
          ),
        ),
        pw.Expanded(
          child: pw.Text(
            field.value,
            style: pw.TextStyle(
              fontSize: 10,
              color: PdfColors.black,
              height: 1.35,
            ),
          ),
        ),
      ],
    ),
  );
}

pw.Widget _buildBulletList(String title, List<String> items) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(
        title,
        style: pw.TextStyle(
          fontSize: 10,
          fontWeight: pw.FontWeight.bold,
          color: PdfColors.black,
        ),
      ),
      pw.SizedBox(height: 4),
      ...items.map(
        (item) => pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 4),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('- ', style: const pw.TextStyle(fontSize: 10)),
              pw.Expanded(
                child: pw.Text(
                  item,
                  style: pw.TextStyle(
                    fontSize: 10,
                    color: PdfColors.black,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ],
  );
}

List<String> _safeStringList(dynamic value) {
  if (value is! List) {
    return const <String>[];
  }

  return value
      .map((item) => pdfText(item, fallback: '').trim())
      .where((item) => item.isNotEmpty)
      .toList();
}

List<String> _safeKeywords(dynamic rawKeywords) {
  final keywordsText = pdfText(rawKeywords, fallback: '');
  if (keywordsText.isEmpty) {
    return const <String>[];
  }

  final seen = <String>{};
  final keywords = <String>[];
  for (final rawKeyword in keywordsText.split(',')) {
    final keyword = pdfText(rawKeyword, fallback: '').trim();
    if (keyword.isEmpty) continue;
    final normalized = keyword.toLowerCase();
    if (seen.add(normalized)) {
      keywords.add(keyword);
    }
  }
  return keywords;
}

double _safeConfidence(dynamic value) {
  final parsed = value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '');
  if (parsed == null || parsed.isNaN || parsed.isInfinite) {
    return 0;
  }
  return parsed.clamp(0, 1).toDouble();
}

Map<String, dynamic>? _parseRecoveryPlan(dynamic recoveryData) {
  try {
    Map<String, dynamic>? plan;

    if (recoveryData is Map) {
      plan = Map<String, dynamic>.from(recoveryData);
    } else if (recoveryData is String) {
      final normalized = recoveryData.trim().toLowerCase();
      if (normalized.isNotEmpty &&
          normalized != 'null' &&
          normalized != 'undefined') {
        final decoded = jsonDecode(recoveryData);
        if (decoded is Map) {
          plan = Map<String, dynamic>.from(decoded);
        }
      }
    }

    if (plan == null) {
      return null;
    }

    final normalizedPlan = <String, dynamic>{
      'home_care': _safeStringList(plan['home_care']),
      'precautions': _safeStringList(plan['precautions']),
      'general_advice': _safeStringList(plan['general_advice']),
      'estimated_recovery': pdfText(plan['estimated_recovery'], fallback: ''),
    };

    final hasContent =
        (normalizedPlan['home_care'] as List).isNotEmpty ||
        (normalizedPlan['precautions'] as List).isNotEmpty ||
        (normalizedPlan['general_advice'] as List).isNotEmpty ||
        (normalizedPlan['estimated_recovery'] as String).isNotEmpty;

    return hasContent ? normalizedPlan : null;
  } catch (_) {
    return null;
  }
}
