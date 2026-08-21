import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:mycapstone_project/web/shared/utils/record_pdf_builder.dart';

/// Builds a printable/exportable PDF for a generated barangay health summary,
/// reusing the same official report header/footer/branding as other record
/// PDFs (`buildRecordPdfBytes`) so this document looks consistent with the
/// rest of the system's printed output.
Future<List<int>> buildSummaryPdfBytes({
  required String title,
  required List<MapEntry<String, String>> headerFields,
  required String bodyText,
  String barangayName = '',
}) {
  return buildRecordPdfBytes(
    title: title,
    subtitle: 'Barangay Health Summary Report',
    sections: const [],
    summaryFields: headerFields,
    trailingWidgets: _buildSummaryBodyWidgets(bodyText),
    barangayName: barangayName,
    footerText: 'Generated from the BHW summary reporting page.',
    signatureLines: const [],
  );
}

String buildSummaryPdfFilename(String title) {
  return buildRecordPdfFilename(prefix: 'summary', subject: title);
}

List<pw.Widget> _buildSummaryBodyWidgets(String summary) {
  final children = <pw.Widget>[];
  for (final rawLine in summary.split('\n')) {
    final line = rawLine.trimRight();
    if (line.isEmpty) {
      children.add(pw.SizedBox(height: 8));
      continue;
    }

    final isHeading =
        line == line.toUpperCase() && !line.startsWith('- ') && line.length <= 40;
    if (isHeading) {
      children.add(
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: 8, bottom: 4),
          child: pw.Text(
            line,
            style: pw.TextStyle(
              fontSize: 12,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.black,
            ),
          ),
        ),
      );
    } else if (line.startsWith('- ')) {
      children.add(
        pw.Padding(
          padding: const pw.EdgeInsets.only(left: 10, bottom: 4),
          child: pw.Text(
            '-  ${line.substring(2)}',
            style: pw.TextStyle(fontSize: 10, color: PdfColors.black),
          ),
        ),
      );
    } else {
      children.add(
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 6),
          child: pw.Text(
            line,
            style: pw.TextStyle(fontSize: 10, color: PdfColors.black),
          ),
        ),
      );
    }
  }
  return [
    pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: children),
  ];
}
