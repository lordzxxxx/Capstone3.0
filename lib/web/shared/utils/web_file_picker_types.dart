import 'dart:typed_data';

class WebSelectedFile {
  const WebSelectedFile({
    required this.bytes,
    required this.name,
    required this.mimeType,
    required this.size,
  });

  final Uint8List bytes;
  final String name;
  final String mimeType;
  final int size;
}
