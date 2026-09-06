import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Shared print layout for official reports produced by the web and mobile
/// Flutter targets.  Keep this file free of platform-specific APIs so that
/// every export surface can use the same header and signature page.
class OfficialReportSignature {
  final String title;
  final String printedName;
  final String position;

  const OfficialReportSignature({
    required this.title,
    this.printedName = '',
    this.position = '',
  });
}

pw.Widget buildOfficialReportHeader({
  required String title,
  required String systemName,
  required DateTime generatedAt,
  String subtitle = '',
  String barangayName = '',
  String reportReference = '',
  pw.MemoryImage? cityLogo,
  pw.MemoryImage? healthOfficeLogo,
  pw.MemoryImage? barangayLogo,
  bool isCompact = false,
}) {
  final location = barangayName.trim().isEmpty
      ? ''
      : 'BARANGAY: ${barangayName.trim()}';

  final logoSize = isCompact ? 36.0 : 52.0;

  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(
        'REPUBLIC OF THE PHILIPPINES  •  PROVINCE OF BUKIDNON',
        style: pw.TextStyle(
          fontSize: isCompact ? 7.2 : 7.6,
          fontWeight: pw.FontWeight.bold,
          color: PdfColors.black,
          letterSpacing: 0.45,
        ),
      ),
      pw.SizedBox(height: isCompact ? 2 : 4),
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          _reportLogo(cityLogo, 'CITY', size: logoSize),
          pw.SizedBox(width: isCompact ? 5 : 7),
          _reportLogo(healthOfficeLogo, 'CHO', size: logoSize),
          pw.SizedBox(width: isCompact ? 5 : 7),
          _reportLogo(barangayLogo, 'BARANGAY', size: logoSize),
          pw.SizedBox(width: isCompact ? 8 : 12),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Text(
                  'CITY OF MALAYBALAY',
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(
                    fontSize: isCompact ? 11.5 : 13,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.black,
                    letterSpacing: isCompact ? 0.5 : 0.75,
                  ),
                ),
                pw.SizedBox(height: 1),
                pw.Text(
                  'SAKA TA MALAYBALAY',
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(
                    fontSize: isCompact ? 7.6 : 8.2,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.black,
                    letterSpacing: isCompact ? 0.6 : 0.9,
                  ),
                ),
                pw.SizedBox(height: isCompact ? 2 : 5),
                pw.Text(
                  systemName.toUpperCase(),
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(
                    fontSize: isCompact ? 7.0 : 7.5,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.black,
                    letterSpacing: 0.45,
                  ),
                ),
              ],
            ),
          ),
          if (reportReference.trim().isNotEmpty) ...[
            pw.SizedBox(width: isCompact ? 8 : 12),
            pw.Container(
              width: isCompact ? 108 : 126,
              padding: pw.EdgeInsets.symmetric(
                horizontal: isCompact ? 6 : 9,
                vertical: isCompact ? 4 : 7,
              ),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.black),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'REPORT CONTROL',
                    style: pw.TextStyle(
                      fontSize: isCompact ? 7.0 : 7.6,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.black,
                      letterSpacing: 0.6,
                    ),
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    reportReference,
                    style: pw.TextStyle(
                      fontSize: isCompact ? 7.8 : 8.4,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.black,
                    ),
                  ),
                  pw.SizedBox(height: 1),
                  pw.Text(
                    'Generated: ${_formatOfficialDateTime(generatedAt)}',
                    style: pw.TextStyle(
                      fontSize: isCompact ? 6.8 : 7.3,
                      color: PdfColors.black,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
      pw.SizedBox(height: isCompact ? 4 : 7),
      pw.Text(
        title,
        style: pw.TextStyle(
          fontSize: isCompact ? 13 : 15,
          fontWeight: pw.FontWeight.bold,
          color: PdfColors.black,
        ),
      ),
      if (location.isNotEmpty || subtitle.trim().isNotEmpty) ...[
        pw.SizedBox(height: 1),
        pw.Text(
          [
            location,
            subtitle.trim(),
          ].where((value) => value.isNotEmpty).join('  |  '),
          style: pw.TextStyle(
            fontSize: isCompact ? 8.2 : 8.6,
            color: PdfColors.black,
          ),
        ),
      ],
      pw.SizedBox(height: isCompact ? 4 : 7),
      pw.Divider(color: PdfColors.black),
    ],
  );
}

pw.Widget buildOfficialReportFooter(
  pw.Context context, {
  String footerText =
      'Generated by AI-DSUHIS • Confidential health information',
}) {
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
              footerText,
              style: pw.TextStyle(
                fontSize: 7.8,
                color: PdfColors.black,
                height: 1.25,
              ),
            ),
          ),
          pw.SizedBox(width: 12),
          pw.Text(
            'Page ${context.pageNumber} of ${context.pagesCount}',
            style: pw.TextStyle(
              fontSize: 8.2,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.black,
            ),
          ),
        ],
      ),
    ],
  );
}

pw.Page buildOfficialReportSignaturePage({
  required List<OfficialReportSignature> signatures,
  PdfPageFormat pageFormat = PdfPageFormat.a4,
  String footerText =
      'Generated by AI-DSUHIS • Confidential health information',
}) {
  return pw.Page(
    pageFormat: pageFormat,
    margin: const pw.EdgeInsets.fromLTRB(32, 40, 32, 40),
    build: (context) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Spacer(),
        buildOfficialReportSignatureSection(signatures),
        pw.SizedBox(height: 28),
        buildOfficialReportFooter(context, footerText: footerText),
      ],
    ),
  );
}

pw.Widget buildOfficialReportSignatureSection(
  List<OfficialReportSignature> signatures, {
  String title = 'SIGNATURE SECTION',
  String note =
      'Complete the printed name, signature, and date fields before filing the report.',
  bool isCompact = false,
}) {
  final visible = signatures
      .where((signature) => signature.title.trim().isNotEmpty)
      .toList();

  if (isCompact) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(height: 6),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            for (var index = 0; index < visible.length; index++) ...[
              if (index > 0) pw.SizedBox(width: 10),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.SizedBox(height: 18),
                    pw.Container(height: 0.8, color: PdfColors.black),
                    pw.SizedBox(height: 2.5),
                    pw.Text(
                      visible[index].title.toUpperCase(),
                      textAlign: pw.TextAlign.center,
                      style: pw.TextStyle(
                        fontSize: isCompact ? 7.2 : 8.5,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.black,
                      ),
                    ),
                    if (visible[index].printedName.trim().isNotEmpty) ...[
                      pw.SizedBox(height: 1),
                      pw.Text(
                        visible[index].printedName.trim(),
                        textAlign: pw.TextAlign.center,
                        style: pw.TextStyle(
                          fontSize: isCompact ? 6.8 : 8.0,
                          color: PdfColors.black,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(
        title,
        style: pw.TextStyle(
          fontSize: 13,
          fontWeight: pw.FontWeight.bold,
          color: PdfColors.black,
          letterSpacing: 0.35,
        ),
      ),
      pw.SizedBox(height: 5),
      pw.Text(
        note,
        style: pw.TextStyle(fontSize: 8.5, color: PdfColors.black, height: 1.3),
      ),
      pw.SizedBox(height: 20),
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          for (var index = 0; index < visible.length; index++) ...[
            if (index > 0) pw.SizedBox(width: 14),
            pw.Expanded(child: _signatureColumn(visible[index])),
          ],
        ],
      ),
    ],
  );
}

pw.Widget _reportLogo(
  pw.MemoryImage? image,
  String fallbackLabel, {
  double size = 52.0,
}) {
  return pw.Column(
    mainAxisSize: pw.MainAxisSize.min,
    children: [
      pw.SizedBox(
        width: size,
        height: size,
        child: image == null
            ? pw.Center(
                child: pw.Text(
                  fallbackLabel,
                  style: pw.TextStyle(
                    fontSize: size * 0.125,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.black,
                  ),
                ),
              )
            : pw.Image(image, fit: pw.BoxFit.contain),
      ),
      pw.SizedBox(height: 2),
      pw.Text(
        fallbackLabel,
        style: pw.TextStyle(
          fontSize: size * 0.088,
          fontWeight: pw.FontWeight.bold,
          color: PdfColors.black,
        ),
      ),
    ],
  );
}

pw.Widget _signatureColumn(OfficialReportSignature signature) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(
        signature.title.toUpperCase(),
        style: pw.TextStyle(
          fontSize: 7.7,
          fontWeight: pw.FontWeight.bold,
          color: PdfColors.black,
          letterSpacing: 0.35,
        ),
      ),
      pw.SizedBox(height: 28),
      _signatureField('Printed Name', signature.printedName),
      pw.SizedBox(height: 13),
      _signatureField('Position', signature.position),
      pw.SizedBox(height: 13),
      _signatureField('Signature', ''),
      pw.SizedBox(height: 13),
      _signatureField('Date', ''),
    ],
  );
}

pw.Widget _signatureField(String label, String value) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(
        label,
        style: pw.TextStyle(fontSize: 7.3, color: PdfColors.black),
      ),
      pw.SizedBox(height: 13),
      pw.Container(height: 0.8, color: PdfColors.black),
      if (value.trim().isNotEmpty) ...[
        pw.SizedBox(height: 3),
        pw.Text(
          value.trim(),
          maxLines: 2,
          style: pw.TextStyle(fontSize: 8.1, color: PdfColors.black),
        ),
      ],
    ],
  );
}

String _formatOfficialDateTime(DateTime value) {
  final hour = value.hour == 0
      ? 12
      : value.hour > 12
      ? value.hour - 12
      : value.hour;
  final minute = value.minute.toString().padLeft(2, '0');
  final meridiem = value.hour >= 12 ? 'PM' : 'AM';
  return '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')} $hour:$minute $meridiem';
}
