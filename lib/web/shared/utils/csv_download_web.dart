import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

bool downloadCsvFile({required List<int> bytes, required String filename}) {
  final blob = web.Blob(<web.BlobPart>[Uint8List.fromList(bytes).toJS].toJS);
  final url = web.URL.createObjectURL(blob);
  web.HTMLAnchorElement()
    ..href = url
    ..download = filename
    ..click();
  web.URL.revokeObjectURL(url);
  return true;
}
