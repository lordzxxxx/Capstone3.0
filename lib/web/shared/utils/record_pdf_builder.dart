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
  bool singlePage = false,
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

  if (singlePage) {
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            buildOfficialReportHeader(
              title: title,
              systemName: systemName,
              subtitle: subtitle,
              generatedAt: createdAt,
              cityLogo: headerLogos.length > 1 ? headerLogos[1] : null,
              healthOfficeLogo: headerLogos.length > 2 ? headerLogos[2] : null,
              barangayLogo: headerLogos.isNotEmpty ? headerLogos[0] : null,
              isCompact: true,
            ),
            if (visibleSummaryFields.isNotEmpty) ...[
              pw.SizedBox(height: 3),
              _buildCompactSummarySection(visibleSummaryFields),
            ],
            pw.SizedBox(height: 3),
            if (visibleSections.isEmpty && trailingWidgets.isEmpty)
              _buildEmptyState()
            else ...[
              ...visibleSections.map(
                (section) => pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 3.5),
                  child: _buildCompactFieldSection(
                    section.title,
                    section.fields,
                  ),
                ),
              ),
              ...trailingWidgets.map(
                (widget) => pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 3.5),
                  child: widget,
                ),
              ),
            ],
            pw.Spacer(),
            if (visibleSignatureLines.isNotEmpty) ...[
              buildOfficialReportSignatureSection(
                visibleSignatureLines
                    .map((line) => OfficialReportSignature(title: line.title))
                    .toList(),
                isCompact: true,
              ),
              pw.SizedBox(height: 5),
            ],
            buildOfficialReportFooter(
              context,
              footerText: [
                footerText.trim(),
                confidentialityNotice.trim(),
              ].where((text) => text.isNotEmpty).join('  '),
            ),
          ],
        ),
      ),
    );
  } else {
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

abstract class _TableChunk {}

class _TwoColChunk extends _TableChunk {
  final MapEntry<String, String> field;
  _TwoColChunk(this.field);
}

class _FourColChunk extends _TableChunk {
  final MapEntry<String, String> field1;
  final MapEntry<String, String> field2;
  _FourColChunk(this.field1, this.field2);
}

pw.Widget _buildTableCellLabel(String text) {
  return pw.Container(
    alignment: pw.Alignment.centerLeft,
    padding: const pw.EdgeInsets.symmetric(horizontal: 4.5, vertical: 2),
    child: pw.Text(
      text,
      style: pw.TextStyle(
        fontSize: 7.8,
        fontWeight: pw.FontWeight.bold,
        color: PdfColors.black,
      ),
    ),
  );
}

pw.Widget _buildTableCellValue(String text) {
  return pw.Container(
    alignment: pw.Alignment.centerLeft,
    padding: const pw.EdgeInsets.symmetric(horizontal: 4.5, vertical: 2),
    child: pw.Text(
      text.isEmpty ? '-' : text,
      style: const pw.TextStyle(
        fontSize: 8.0,
        color: PdfColors.black,
      ),
    ),
  );
}

pw.Widget _buildSummarySection(List<MapEntry<String, String>> fields) {
  return pw.Container(
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: PdfColors.black, width: 0.8),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: const pw.BoxDecoration(
            border: pw.Border(
              bottom: pw.BorderSide(color: PdfColors.black, width: 0.8),
            ),
          ),
          child: pw.Text(
            'RECORD SUMMARY',
            style: pw.TextStyle(
              fontSize: 11,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.black,
              letterSpacing: 0.5,
            ),
          ),
        ),
        pw.Table(
          border: const pw.TableBorder(
            horizontalInside:
                pw.BorderSide(color: PdfColors.grey400, width: 0.5),
            verticalInside: pw.BorderSide(color: PdfColors.grey400, width: 0.5),
          ),
          columnWidths: {
            for (var i = 0; i < fields.length; i++)
              i: const pw.FlexColumnWidth(1),
          },
          children: [
            pw.TableRow(
              children: fields
                  .map(
                    (field) => pw.Container(
                      padding: const pw.EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 4,
                      ),
                      alignment: pw.Alignment.centerLeft,
                      child: pw.Text(
                        field.key.toUpperCase(),
                        style: pw.TextStyle(
                          fontSize: 8.5,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.black,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
            pw.TableRow(
              children: fields
                  .map(
                    (field) => pw.Container(
                      padding: const pw.EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 4,
                      ),
                      alignment: pw.Alignment.centerLeft,
                      child: pw.Text(
                        field.value,
                        style: pw.TextStyle(
                          fontSize: 9.5,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.black,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
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
      pw.SizedBox(height: 4),
      pw.Table(
        border: pw.TableBorder(
          top: const pw.BorderSide(color: PdfColors.black, width: 0.8),
          bottom: const pw.BorderSide(color: PdfColors.black, width: 0.8),
          left: const pw.BorderSide(color: PdfColors.black, width: 0.8),
          right: const pw.BorderSide(color: PdfColors.black, width: 0.8),
          horizontalInside:
              const pw.BorderSide(color: PdfColors.grey400, width: 0.5),
          verticalInside:
              const pw.BorderSide(color: PdfColors.grey400, width: 0.5),
        ),
        columnWidths: const {
          0: pw.FlexColumnWidth(1.35),
          1: pw.FlexColumnWidth(2.65),
        },
        children: fields
            .map(
              (field) => pw.TableRow(
                children: [
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4.5,
                    ),
                    alignment: pw.Alignment.centerLeft,
                    child: pw.Text(
                      field.key,
                      style: pw.TextStyle(
                        fontSize: 9.0,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.black,
                      ),
                    ),
                  ),
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4.5,
                    ),
                    alignment: pw.Alignment.centerLeft,
                    child: pw.Text(
                      field.value,
                      style: const pw.TextStyle(
                        fontSize: 9.0,
                        color: PdfColors.black,
                      ),
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

pw.Widget _buildCompactFieldSection(
  String title,
  List<MapEntry<String, String>> fields,
) {
  final chunks = <_TableChunk>[];
  var i = 0;
  while (i < fields.length) {
    final current = fields[i];
    final isLong = current.value.length > 40 || _isLongFieldKey(current.key);

    if (isLong || i == fields.length - 1) {
      chunks.add(_TwoColChunk(current));
      i++;
    } else {
      final next = fields[i + 1];
      final nextIsLong = next.value.length > 40 || _isLongFieldKey(next.key);
      if (nextIsLong) {
        chunks.add(_TwoColChunk(current));
        i++;
      } else {
        chunks.add(_FourColChunk(current, next));
        i += 2;
      }
    }
  }

  // Group contiguous chunks of the same kind into table blocks
  final blocks = <List<_TableChunk>>[];
  for (final chunk in chunks) {
    if (blocks.isEmpty) {
      blocks.add([chunk]);
    } else {
      final lastBlock = blocks.last;
      if ((lastBlock.first is _FourColChunk && chunk is _FourColChunk) ||
          (lastBlock.first is _TwoColChunk && chunk is _TwoColChunk)) {
        lastBlock.add(chunk);
      } else {
        blocks.add([chunk]);
      }
    }
  }

  final tableWidgets = <pw.Widget>[];
  for (var b = 0; b < blocks.length; b++) {
    final block = blocks[b];
    final isLastBlock = b == blocks.length - 1;
    final isFourCol = block.first is _FourColChunk;

    final border = pw.TableBorder(
      top: pw.BorderSide.none,
      left: pw.BorderSide.none,
      right: pw.BorderSide.none,
      bottom: isLastBlock
          ? pw.BorderSide.none
          : const pw.BorderSide(color: PdfColors.grey400, width: 0.5),
      horizontalInside:
          const pw.BorderSide(color: PdfColors.grey400, width: 0.5),
      verticalInside: const pw.BorderSide(color: PdfColors.grey400, width: 0.5),
    );

    if (isFourCol) {
      tableWidgets.add(
        pw.Table(
          border: border,
          columnWidths: const {
            0: pw.FlexColumnWidth(1.15),
            1: pw.FlexColumnWidth(1.85),
            2: pw.FlexColumnWidth(1.15),
            3: pw.FlexColumnWidth(1.85),
          },
          children: block.cast<_FourColChunk>().map((row) {
            return pw.TableRow(
              children: [
                _buildTableCellLabel(row.field1.key),
                _buildTableCellValue(row.field1.value),
                _buildTableCellLabel(row.field2.key),
                _buildTableCellValue(row.field2.value),
              ],
            );
          }).toList(),
        ),
      );
    } else {
      tableWidgets.add(
        pw.Table(
          border: border,
          columnWidths: const {
            0: pw.FlexColumnWidth(1.15),
            1: pw.FlexColumnWidth(4.85),
          },
          children: block.cast<_TwoColChunk>().map((row) {
            return pw.TableRow(
              children: [
                _buildTableCellLabel(row.field.key),
                _buildTableCellValue(row.field.value),
              ],
            );
          }).toList(),
        ),
      );
    }
  }

  return pw.Container(
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: PdfColors.grey600, width: 0.5),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 2.2),
          decoration: const pw.BoxDecoration(
            border: pw.Border(
              bottom: pw.BorderSide(color: PdfColors.grey600, width: 0.5),
            ),
          ),
          child: pw.Text(
            title.toUpperCase(),
            style: pw.TextStyle(
              fontSize: 8.2,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.black,
              letterSpacing: 0.35,
            ),
          ),
        ),
        ...tableWidgets,
      ],
    ),
  );
}

bool _isLongFieldKey(String key) {
  final k = key.toLowerCase();
  return k.contains('symptom') ||
      k.contains('diagnosis') ||
      k.contains('treatment') ||
      k.contains('plan') ||
      k.contains('details') ||
      k.contains('reason') ||
      k.contains('explanation') ||
      k.contains('address') ||
      k.contains('complaint') ||
      k.contains('note') ||
      k.contains('vitals');
}

pw.Widget _buildCompactSummarySection(List<MapEntry<String, String>> fields) {
  return pw.Container(
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: PdfColors.grey600, width: 0.5),
    ),
    child: pw.Table(
      border: const pw.TableBorder(
        horizontalInside: pw.BorderSide(color: PdfColors.grey400, width: 0.5),
        verticalInside: pw.BorderSide(color: PdfColors.grey400, width: 0.5),
      ),
      columnWidths: {
        for (var i = 0; i < fields.length; i++) i: const pw.FlexColumnWidth(1),
      },
      children: [
        pw.TableRow(
          children: fields
              .map(
                (field) => pw.Container(
                  padding:
                      const pw.EdgeInsets.symmetric(horizontal: 4.5, vertical: 2),
                  alignment: pw.Alignment.centerLeft,
                  child: pw.Text(
                    field.key.toUpperCase(),
                    style: pw.TextStyle(
                      fontSize: 7.6,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.black,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              )
              .toList(),
        ),
        pw.TableRow(
          children: fields
              .map(
                (field) => pw.Container(
                  padding:
                      const pw.EdgeInsets.symmetric(horizontal: 4.5, vertical: 2),
                  alignment: pw.Alignment.centerLeft,
                  child: pw.Text(
                    field.value,
                    style: pw.TextStyle(
                      fontSize: 8.5,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.black,
                    ),
                  ),
                ),
              )
              .toList(),
        ),
      ],
    ),
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
