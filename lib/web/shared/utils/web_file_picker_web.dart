import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'web_file_picker_types.dart';

Future<WebSelectedFile?> pickWebFile({required String accept}) async {
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..accept = accept
    ..multiple = false;
  final changed = Completer<void>();
  input.addEventListener(
    'change',
    ((web.Event _) {
      if (!changed.isCompleted) changed.complete();
    }).toJS,
    web.AddEventListenerOptions(once: true),
  );
  input.click();
  await changed.future;

  final file = input.files?.item(0);
  if (file == null) return null;
  final buffer = await file.arrayBuffer().toDart;
  return WebSelectedFile(
    bytes: buffer.toDart.asUint8List(),
    name: file.name,
    mimeType: file.type,
    size: file.size,
  );
}
