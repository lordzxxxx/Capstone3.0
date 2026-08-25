import 'web_file_picker_stub.dart'
    if (dart.library.js_interop) 'web_file_picker_web.dart'
    as implementation;
import 'web_file_picker_types.dart';

export 'web_file_picker_types.dart';

Future<WebSelectedFile?> pickWebFile({required String accept}) {
  return implementation.pickWebFile(accept: accept);
}
