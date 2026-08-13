import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:mycapstone_project/shared/official_report_layout.dart';
import 'package:mycapstone_project/web/shared/utils/pdf_fonts.dart';
import 'package:mycapstone_project/web/shared/utils/report_branding.dart';

const String _defaultSystemName = 'Health Records Management System';
const String _defaultConfidentialityNotice =
    'Confidential document. For authorized health personnel use only.';

class RecordPdfSection {
  final String title;
  final List<MapEntry<String, String>> fields;

  const RecordPdfSection({required this.title, required this.fields});
}

class RecordPdfSignatureLine {
  final String title;

  const RecordPdfSignatureLine({required this.title});
}

Future<List<int>> buildRecordPdfBytes({
  required String title,
  required String subtitle,
  required List<RecordPdfSection> sections,
  List<MapEntry<String, String>> summaryFields = const [],
  List<pw.Widget> trailingWidgets = const [],
  bool signatureSectionOnNewPage = true,
  bool signatureSectionAtPageBottom = true,
  String systemName = _defaultSystemName,
  String footerText = 'Generated from the web records table.',
  String confidentialityNotice = _defaultConfidentialityNotice,
  String barangayName = '',
  DateTime? generatedAt,
  List<RecordPdfSignatureLine> signatureLines = const [
    RecordPdfSignatureLine(title: 'Barangay Captain'),
    RecordPdfSignatureLine(title: 'Barangay Kagawad in Health'),
    RecordPdfSignatureLine(title: 'BHW Head'),
    RecordPdfSignatureLine(title: 'BHW Assigned on Duty'),
  ],
}) async {
  final branding = await loadReportBranding(barangayName: barangayName);
  final headerLogos = <pw.MemoryImage?>[
    _memoryImage(branding.barangayLogo),
    _memoryImage(branding.cityLogo),
    _memoryImage(branding.healthOfficeLogo),
  ];

  final fonts = await loadPdfFontBundle();
  final pdf = pw.Document(
    theme: pw.ThemeData.withFont(
      base: fonts.base,
      bold: fonts.bold,
      italic: fonts.italic,
      boldItalic: fonts.boldItalic,
    ),
  );
  final createdAt = generatedAt ?? DateTime.now();
  final visibleSections = sections
      .map(
        (section) => RecordPdfSection(
          title: section.title,
          fields: section.fields
              .where((field) => field.value.trim().isNotEmpty)
              .toList(),
        ),
      )
      .where((section) => section.fields.isNotEmpty)
      .toList();
  final visibleSummaryFields = summaryFields
      .where((field) => field.value.trim().isNotEmpty)
      .toList();
  final visibleSignatureLines = signatureLines
      .where((line) => line.title.trim().isNotEmpty)
      .toList();
  final useDedicatedBottomSignaturePage =
      signatureSectionOnNewPage && signatureSectionAtPageBottom;

  pdf.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(32, 52, 32, 40),
      footer: (context) => buildOfficialReportFooter(
        context,
        footerText: [
          footerText.trim(),
          confidentialityNotice.trim(),
        ].where((text) => text.isNotEmpty).join('  '),
      ),
      build: (context) => [
        buildOfficialReportHeader(
          title: title,
          systemName: systemName,
          subtitle: subtitle,
          generatedAt: createdAt,
          cityLogo: headerLogos.length > 1 ? headerLogos[1] : null,
          healthOfficeLogo: headerLogos.length > 2 ? headerLogos[2] : null,
          barangayLogo: headerLogos.isNotEmpty ? headerLogos[0] : null,
        ),
        if (visibleSummaryFields.isNotEmpty) ...[
          pw.SizedBox(height: 16),
          _buildSummarySection(visibleSummaryFields),
        ],
        pw.SizedBox(height: 16),
        if (visibleSections.isEmpty && trailingWidgets.isEmpty)
          _buildEmptyState()
        else ...[
          ...visibleSections.expand(
            (section) => [
              _buildFieldSection(section.title, section.fields),
              pw.SizedBox(height: 14),
            ],
          ),
          ...trailingWidgets.expand(
            (widget) => [widget, pw.SizedBox(height: 14)],
          ),
        ],
        if (visibleSignatureLines.isNotEmpty &&
            !useDedicatedBottomSignaturePage) ...[
          if (signatureSectionOnNewPage) pw.NewPage(),
          pw.SizedBox(height: 10),
          buildOfficialReportSignatureSection(
            visibleSignatureLines
                .map((line) => OfficialReportSignature(title: line.title))
                .toList(),
          ),
        ],
      ],
    ),
  );

  if (visibleSignatureLines.isNotEmpty && useDedicatedBottomSignaturePage) {
    pdf.addPage(
      buildOfficialReportSignaturePage(
        signatures: visibleSignatureLines
            .map((line) => OfficialReportSignature(title: line.title))
            .toList(),
        footerText: [
          footerText.trim(),
          confidentialityNotice.trim(),
        ].where((text) => text.isNotEmpty).join('  '),
      ),
    );
  }

  // Yield to event loop before PDF save to prevent UI freezing
  // This allows the UI to refresh before the synchronous pdf.save() executes
  await Future.delayed(Duration.zero);
  return pdf.save();
}

String buildRecordPdfFilename({
  required String prefix,
  required String subject,
  dynamic rawDate,
}) {
  final cleanPrefix = _sanitizeFilenamePart(prefix, fallback: 'record');
  final cleanSubject = _sanitizeFilenamePart(subject, fallback: 'entry');
  final dateToken = _buildDateToken(rawDate);
  return '${cleanPrefix}_${cleanSubject}_$dateToken.pdf';
}

MapEntry<String, String> pdfField(
  String label,
  dynamic value, {
  String fallback = '',
}) {
  return MapEntry(label, pdfText(value, fallback: fallback));
}

String pdfText(dynamic value, {String fallback = ''}) {
  if (value == null) return fallback;
  final text = value.toString().trim();
  final normalized = text.toLowerCase();

  if (text.isEmpty ||
      normalized == 'null' ||
      normalized == 'undefined' ||
      normalized == 'n/a') {
    return fallback;
  }

  return text;
}

String pdfJoin(
  List<dynamic> values, {
  String separator = ', ',
  String fallback = '',
}) {
  final parts = values
      .map((value) => pdfText(value, fallback: '').trim())
      .where((value) => value.isNotEmpty)
      .toList();

  if (parts.isEmpty) {
    return fallback;
  }

  return parts.join(separator);
}

pw.Widget _buildSummarySection(List<MapEntry<String, String>> fields) {
  return pw.Container(
    padding: const pw.EdgeInsets.all(16),
    decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.black)),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'Record Summary',
          style: pw.TextStyle(
            fontSize: 14,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.black,
          ),
        ),
        pw.SizedBox(height: 10),
        pw.Wrap(
          spacing: 10,
          runSpacing: 10,
          children: fields
              .map(
                (field) => pw.Container(
                  width: 236,
                  padding: const pw.EdgeInsets.all(10),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.black),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        field.key.toUpperCase(),
                        style: pw.TextStyle(
                          fontSize: 8,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.black,
                          letterSpacing: 0.7,
                        ),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        field.value,
                        style: pw.TextStyle(
                          fontSize: 11,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.black,
                        ),
                      ),
                    ],
                  ),
                ),
              )
              .toList(),
        ),
      ],
    ),
  );
}

pw.Widget _buildFieldSection(
  String title,
  List<MapEntry<String, String>> fields,
) {
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
      pw.SizedBox(height: 6),
      pw.Table(
        border: pw.TableBorder(
          top: pw.BorderSide(color: PdfColors.black, width: 0.8),
          bottom: pw.BorderSide(color: PdfColors.black, width: 0.8),
          left: pw.BorderSide(color: PdfColors.black, width: 0.8),
          right: pw.BorderSide(color: PdfColors.black, width: 0.8),
          horizontalInside: pw.BorderSide(color: PdfColors.black, width: 0.5),
          verticalInside: pw.BorderSide(color: PdfColors.black, width: 0.5),
        ),
        columnWidths: const {
          0: pw.FlexColumnWidth(1.35),
          1: pw.FlexColumnWidth(2.65),
        },
        children: fields
            .map(
              (field) => pw.TableRow(
                children: [
                  pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    child: pw.Text(
                      field.key,
                      style: pw.TextStyle(
                        fontSize: 9,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.black,
                      ),
                    ),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    child: pw.Text(
                      field.value,
                      style: pw.TextStyle(fontSize: 9, color: PdfColors.black),
                    ),
                  ),
                ],
              ),
            )
            .toList(),
      ),
    ],
  );
}

pw.Widget _buildEmptyState() {
  return pw.Container(
    width: double.infinity,
    padding: const pw.EdgeInsets.all(18),
    decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.black)),
    child: pw.Text(
      'No record details are available for this PDF.',
      style: pw.TextStyle(fontSize: 10.5, color: PdfColors.black),
    ),
  );
}

String _sanitizeFilenamePart(String value, {required String fallback}) {
  final sanitized = value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');

  return sanitized.isEmpty ? fallback : sanitized;
}

String _buildDateToken(dynamic rawDate) {
  final parsedDate = DateTime.tryParse(rawDate?.toString() ?? '');
  final date = parsedDate ?? DateTime.now();
  return '${date.year}${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}';
}

pw.MemoryImage? _memoryImage(Uint8List? bytes) {
  return bytes == null || bytes.isEmpty ? null : pw.MemoryImage(bytes);
}
