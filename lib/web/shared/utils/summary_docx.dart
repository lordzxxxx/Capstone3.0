import 'dart:convert';

import 'package:archive/archive.dart';

/// Hand-written minimal OOXML (.docx) writer for the barangay health summary
/// export. Deliberately self-contained (no external docx-generation package)
/// since the document only needs a title, a labeled header block, and
/// heading/paragraph/bullet body text — well within what a small amount of
/// raw `word/document.xml` can express.

String _escapeXml(String value) {
  return value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');
}

String _titleParagraph(String text) {
  return '<w:p><w:pPr><w:spacing w:after="240"/><w:jc w:val="center"/></w:pPr>'
      '<w:r><w:rPr><w:b/><w:sz w:val="36"/></w:rPr>'
      '<w:t xml:space="preserve">${_escapeXml(text)}</w:t></w:r></w:p>';
}

String _headerLineParagraph(String label, String value) {
  return '<w:p><w:pPr><w:spacing w:after="60"/></w:pPr>'
      '<w:r><w:rPr><w:b/></w:rPr><w:t xml:space="preserve">${_escapeXml(label)}: </w:t></w:r>'
      '<w:r><w:t xml:space="preserve">${_escapeXml(value)}</w:t></w:r></w:p>';
}

String _headingParagraph(String text) {
  return '<w:p><w:pPr><w:spacing w:before="240" w:after="120"/></w:pPr>'
      '<w:r><w:rPr><w:b/><w:sz w:val="26"/><w:color w:val="2F80ED"/></w:rPr>'
      '<w:t xml:space="preserve">${_escapeXml(text)}</w:t></w:r></w:p>';
}

String _bulletParagraph(String text) {
  return '<w:p><w:pPr><w:spacing w:after="80"/><w:ind w:left="360" w:hanging="180"/></w:pPr>'
      '<w:r><w:t xml:space="preserve">•  ${_escapeXml(text)}</w:t></w:r></w:p>';
}

String _bodyParagraph(String text) {
  return '<w:p><w:pPr><w:spacing w:after="120"/></w:pPr>'
      '<w:r><w:t xml:space="preserve">${_escapeXml(text)}</w:t></w:r></w:p>';
}

/// Converts summary body text (the same plain-text format rendered by the
/// on-screen preview: ALL-CAPS section headings, "- " bullet lines, blank
/// lines as spacing) into document paragraphs.
List<String> _bodyParagraphsFromSummaryText(String summary) {
  final paragraphs = <String>[];
  for (final rawLine in summary.split('\n')) {
    final line = rawLine.trimRight();
    if (line.isEmpty) continue;
    final isHeading =
        line == line.toUpperCase() && !line.startsWith('- ') && line.length <= 40;
    if (isHeading) {
      paragraphs.add(_headingParagraph(line));
    } else if (line.startsWith('- ')) {
      paragraphs.add(_bulletParagraph(line.substring(2)));
    } else {
      paragraphs.add(_bodyParagraph(line));
    }
  }
  return paragraphs;
}

const String _contentTypesXml =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
    '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
    '<Default Extension="xml" ContentType="application/xml"/>'
    '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
    '</Types>';

const String _rootRelsXml =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>'
    '</Relationships>';

/// Builds the raw bytes of a valid, minimal `.docx` file.
///
/// [title] is the document title (rendered centered, bold). [headerLines]
/// are label/value pairs shown under the title (barangay, period, BHW name,
/// generated date). [bodyText] is the plain-text summary body in the same
/// format the on-screen preview renders.
List<int> buildSummaryDocxBytes({
  required String title,
  required List<MapEntry<String, String>> headerLines,
  required String bodyText,
}) {
  final paragraphs = StringBuffer()..write(_titleParagraph(title));
  for (final line in headerLines) {
    paragraphs.write(_headerLineParagraph(line.key, line.value));
  }
  paragraphs.write(
    '<w:p><w:pPr><w:spacing w:after="200"/></w:pPr>'
    '<w:r><w:rPr><w:b/></w:rPr><w:t xml:space="preserve"></w:t></w:r></w:p>',
  );
  for (final paragraph in _bodyParagraphsFromSummaryText(bodyText)) {
    paragraphs.write(paragraph);
  }

  final documentXml =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
      '<w:body>'
      '${paragraphs.toString()}'
      '<w:sectPr><w:pgSz w:w="12240" w:h="15840"/>'
      '<w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440"/>'
      '</w:sectPr>'
      '</w:body></w:document>';

  final archive = Archive()
    ..addFile(_utf8File('[Content_Types].xml', _contentTypesXml))
    ..addFile(_utf8File('_rels/.rels', _rootRelsXml))
    ..addFile(_utf8File('word/document.xml', documentXml));

  final encoded = ZipEncoder().encode(archive);
  return encoded;
}

ArchiveFile _utf8File(String name, String content) {
  final bytes = utf8.encode(content);
  return ArchiveFile(name, bytes.length, bytes);
}
