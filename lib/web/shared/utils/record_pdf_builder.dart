import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:mycapstone_project/web/shared/utils/pdf_fonts.dart';

const String _defaultSystemName = 'Health Records Management System';
const String _defaultConfidentialityNotice =
    'Confidential document. For authorized health personnel use only.';

final Map<String, pw.MemoryImage?> _recordPdfAssetImageCache =
  <String, pw.MemoryImage?>{};

const double _signatureBottomAnchorSpacer = 420;

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
  bool signatureSectionOnNewPage = false,
  bool signatureSectionAtPageBottom = false,
  String systemName = _defaultSystemName,
  String footerText = 'Generated from the web records table.',
  String confidentialityNotice = _defaultConfidentialityNotice,
  DateTime? generatedAt,
  List<RecordPdfSignatureLine> signatureLines = const [
    RecordPdfSignatureLine(title: 'Prepared by'),
    RecordPdfSignatureLine(title: 'Reviewed by'),
    RecordPdfSignatureLine(title: 'Approved by'),
  ],
}) async {
  final headerLogos = await Future.wait<pw.MemoryImage?>([
    _loadRecordPdfAssetImage('assets/logo1.png'),
    _loadRecordPdfAssetImage('assets/logo2.png'),
    _loadRecordPdfAssetImage('assets/logo3.png'),
  ]);

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
      header: (context) => _buildPageHeader(
        systemName: systemName,
        title: title,
        subtitle: subtitle,
        generatedAt: createdAt,
        logos: headerLogos,
      ),
      footer: (context) => _buildPageFooter(
        context: context,
        footerText: footerText,
        confidentialityNotice: confidentialityNotice,
      ),
      build: (context) => [
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
            (widget) => [
              widget,
              pw.SizedBox(height: 14),
            ],
          ),
        ],
        if (visibleSignatureLines.isNotEmpty && !useDedicatedBottomSignaturePage) ...[
          if (signatureSectionOnNewPage) pw.NewPage(),
          if (signatureSectionAtPageBottom)
            pw.SizedBox(height: _signatureBottomAnchorSpacer)
          else
            pw.SizedBox(height: 10),
          _buildSignatureSection(visibleSignatureLines),
        ],
      ],
    ),
  );

  if (visibleSignatureLines.isNotEmpty && useDedicatedBottomSignaturePage) {
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(32, 52, 32, 40),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _buildPageHeader(
              systemName: systemName,
              title: title,
              subtitle: subtitle,
              generatedAt: createdAt,
              logos: headerLogos,
            ),
            pw.Spacer(),
            _buildSignatureSection(visibleSignatureLines),
            pw.SizedBox(height: 10),
            _buildPageFooter(
              context: context,
              footerText: footerText,
              confidentialityNotice: confidentialityNotice,
            ),
          ],
        ),
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

pw.Widget _buildPageHeader({
  required String systemName,
  required String title,
  required String subtitle,
  required DateTime generatedAt,
  List<pw.MemoryImage?> logos = const [],
}) {
  final visibleLogos = logos.whereType<pw.MemoryImage>().toList();

  return pw.Column(
    mainAxisSize: pw.MainAxisSize.min,
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          _buildRecordHeaderLogoStrip(visibleLogos),
          pw.SizedBox(width: 10),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  systemName.toUpperCase(),
                  style: pw.TextStyle(
                    fontSize: 12,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.black,
                    letterSpacing: 0.9,
                  ),
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  title,
                  style: pw.TextStyle(
                    fontSize: 20,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.black,
                  ),
                ),
                if (subtitle.trim().isNotEmpty)
                  pw.Text(
                    subtitle,
                    style: pw.TextStyle(
                      fontSize: 14,
                      color: PdfColors.black,
                    ),
                  ),
              ],
            ),
          ),
          pw.SizedBox(width: 10),
          // Generated date on the right
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.black),
              borderRadius: pw.BorderRadius.circular(8),
              color: PdfColor.fromHex('#F7FAFB'),
            ),
            child: pw.Text(
              'Generated ${_formatDateTime(generatedAt)}',
              style: pw.TextStyle(
                fontSize: 10,
                color: PdfColors.black,
              ),
            ),
          ),
        ],
      ),
      pw.SizedBox(height: 10),
      pw.Divider(color: PdfColors.black),
    ],
  );
}

pw.Widget _buildRecordHeaderLogoStrip(List<pw.MemoryImage> logos) {
  if (logos.isEmpty) {
    return _buildRecordHeaderLogoBox(null);
  }

  return pw.Row(
    mainAxisSize: pw.MainAxisSize.min,
    children: [
      for (var i = 0; i < logos.length; i++) ...[
        _buildRecordHeaderLogoBox(logos[i]),
        if (i != logos.length - 1) pw.SizedBox(width: 6),
      ],
    ],
  );
}

pw.Widget _buildRecordHeaderLogoBox(pw.MemoryImage? image) {
  return pw.SizedBox(
    width: 58,
    height: 58,
    child: image == null
        ? pw.Center(
            child: pw.Text(
              'LOGO',
              style: pw.TextStyle(
                fontSize: 7,
                color: PdfColors.black,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          )
        : pw.Image(image, fit: pw.BoxFit.contain),
  );
}

pw.Widget _buildPageFooter({
  required pw.Context context,
  required String footerText,
  required String confidentialityNotice,
}) {
  final footerNote = [
    footerText.trim(),
    confidentialityNotice.trim(),
  ].where((text) => text.isNotEmpty).join('  ');

  return pw.Column(
    mainAxisSize: pw.MainAxisSize.min,
    children: [
      pw.Divider(color: PdfColors.black),
      pw.SizedBox(height: 4),
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            child: pw.Text(
              footerNote,
              style: pw.TextStyle(
                fontSize: 8,
                color: PdfColors.black,
                height: 1.3,
              ),
            ),
          ),
          pw.SizedBox(width: 12),
          pw.Text(
            'Page ${context.pageNumber} of ${context.pagesCount}',
            style: pw.TextStyle(
              fontSize: 8.5,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.black,
            ),
          ),
        ],
      ),
    ],
  );
}

pw.Widget _buildDocumentIntro({
  required String title,
  required String subtitle,
  required DateTime generatedAt,
}) {
  return pw.Container(
    padding: const pw.EdgeInsets.all(18),
    decoration: pw.BoxDecoration(
      color: PdfColor.fromHex('#F5FAFB'),
      border: pw.Border.all(color: PdfColors.black),
      borderRadius: pw.BorderRadius.circular(12),
    ),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                title,
                style: pw.TextStyle(
                  fontSize: 22,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.black,
                ),
              ),
              if (subtitle.trim().isNotEmpty) ...[
                pw.SizedBox(height: 4),
                pw.Text(
                  subtitle,
                  style: pw.TextStyle(
                    fontSize: 11,
                    color: PdfColors.black,
                  ),
                ),
              ],
              pw.SizedBox(height: 10),
              pw.Text(
                'Print-ready copy for filing, verification, and signature completion.',
                style: pw.TextStyle(
                  fontSize: 10,
                  color: PdfColors.black,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

pw.Widget _buildSummarySection(List<MapEntry<String, String>> fields) {
  return pw.Container(
    padding: const pw.EdgeInsets.all(16),
    decoration: pw.BoxDecoration(
      color: PdfColor.fromHex('#FBFDFC'),
      border: pw.Border.all(color: PdfColors.black),
      borderRadius: pw.BorderRadius.circular(10),
    ),
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
                    color: PdfColors.white,
                    border: pw.Border.all(color: PdfColors.black),
                    borderRadius: pw.BorderRadius.circular(8),
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
                      style: pw.TextStyle(
                        fontSize: 9,
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

pw.Widget _buildEmptyState() {
  return pw.Container(
    width: double.infinity,
    padding: const pw.EdgeInsets.all(18),
    decoration: pw.BoxDecoration(
      color: PdfColor.fromHex('#FAFCFD'),
      border: pw.Border.all(color: PdfColors.black),
      borderRadius: pw.BorderRadius.circular(10),
    ),
    child: pw.Text(
      'No record details are available for this PDF.',
      style: pw.TextStyle(
        fontSize: 10.5,
        color: PdfColors.black,
      ),
    ),
  );
}

pw.Widget _buildSignatureSection(List<RecordPdfSignatureLine> signatureLines) {
  final columns = <pw.Widget>[];
  for (var i = 0; i < signatureLines.length; i++) {
    if (i > 0) {
      columns.add(pw.SizedBox(width: 16));
    }
    columns.add(
      pw.Expanded(
        child: _buildSignatureColumn(signatureLines[i].title),
      ),
    );
  }

  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(
        'Signature Section',
        style: pw.TextStyle(
          fontSize: 14,
          fontWeight: pw.FontWeight.bold,
          color: PdfColors.black,
        ),
      ),
      pw.SizedBox(height: 6),
      pw.Text(
        'Complete the printed name, signature, and date fields before filing the printed document.',
        style: pw.TextStyle(
          fontSize: 9,
          color: PdfColors.black,
          height: 1.35,
        ),
      ),
      pw.SizedBox(height: 14),
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: columns,
      ),
    ],
  );
}

pw.Widget _buildSignatureColumn(String title) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(
        title,
        style: pw.TextStyle(
          fontSize: 8,
          fontWeight: pw.FontWeight.bold,
          color: PdfColors.black,
        ),
      ),
      pw.SizedBox(height: 18),
      _buildSignatureField('Printed name'),
      pw.SizedBox(height: 14),
      _buildSignatureField('Signature'),
      pw.SizedBox(height: 14),
      _buildSignatureField('Date'),
    ],
  );
}

pw.Widget _buildSignatureField(String label) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Container(height: 1, color: PdfColors.black),
      pw.SizedBox(height: 4),
      pw.Text(
        label,
        style: pw.TextStyle(
          fontSize: 8,
          color: PdfColors.black,
        ),
      ),
    ],
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

String _formatDateTime(DateTime dateTime) {
  final year = dateTime.year.toString();
  final month = dateTime.month.toString().padLeft(2, '0');
  final day = dateTime.day.toString().padLeft(2, '0');
  final hour = dateTime.hour.toString().padLeft(2, '0');
  final minute = dateTime.minute.toString().padLeft(2, '0');
  return '$year-$month-$day $hour:$minute';
}

Future<pw.MemoryImage?> _loadRecordPdfAssetImage(String assetPath) async {
  if (_recordPdfAssetImageCache.containsKey(assetPath)) {
    return _recordPdfAssetImageCache[assetPath];
  }

  try {
    final byteData = await rootBundle.load(assetPath);
    final optimizedBytes = await _optimizePdfImageBytes(
      byteData.buffer.asUint8List(),
      targetLongestSide: 220,
    );
    final image = pw.MemoryImage(optimizedBytes);
    _recordPdfAssetImageCache[assetPath] = image;
    return image;
  } catch (_) {
    _recordPdfAssetImageCache[assetPath] = null;
    return null;
  }
}

Future<Uint8List> _optimizePdfImageBytes(
  Uint8List bytes, {
  required int targetLongestSide,
}) async {
  try {
    final initialCodec = await ui.instantiateImageCodec(bytes);
    final initialFrame = await initialCodec.getNextFrame();
    final width = initialFrame.image.width;
    final height = initialFrame.image.height;
    final longestSide = math.max(width, height);

    if (longestSide <= targetLongestSide) {
      return bytes;
    }

    final scale = targetLongestSide / longestSide;
    final targetWidth = math.max(1, (width * scale).round());
    final targetHeight = math.max(1, (height * scale).round());

    final resizedCodec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: targetWidth,
      targetHeight: targetHeight,
    );
    final resizedFrame = await resizedCodec.getNextFrame();
    final resizedBytes = await resizedFrame.image.toByteData(
      format: ui.ImageByteFormat.png,
    );

    if (resizedBytes == null) {
      return bytes;
    }

    return resizedBytes.buffer.asUint8List();
  } catch (_) {
    return bytes;
  }
}
