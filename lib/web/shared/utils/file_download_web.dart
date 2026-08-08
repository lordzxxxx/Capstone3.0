import 'dart:html' as html;
import 'dart:typed_data';

bool downloadFile({
  required List<int> bytes,
  required String filename,
  String mimeType = 'application/octet-stream',
}) {
  final blob = html.Blob([Uint8List.fromList(bytes)], mimeType);
  final url = html.Url.createObjectUrlFromBlob(blob);

  html.AnchorElement(href: url)
    ..setAttribute('download', filename)
    ..click();

  html.Url.revokeObjectUrl(url);
  return true;
}
