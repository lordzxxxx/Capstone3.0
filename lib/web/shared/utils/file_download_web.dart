import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

bool downloadFile({
  required List<int> bytes,
  required String filename,
  String mimeType = 'application/octet-stream',
}) {
  final blob = web.Blob(
    <web.BlobPart>[Uint8List.fromList(bytes).toJS].toJS,
    web.BlobPropertyBag(type: mimeType),
  );
  final url = web.URL.createObjectURL(blob);

  web.HTMLAnchorElement()
    ..href = url
    ..download = filename
    ..click();

  web.URL.revokeObjectURL(url);
  return true;
}
