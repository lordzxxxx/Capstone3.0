import 'file_download_stub.dart'
    if (dart.library.html) 'file_download_web.dart'
    as impl;

bool downloadFile({
  required List<int> bytes,
  required String filename,
  String mimeType = 'application/octet-stream',
}) {
  return impl.downloadFile(
    bytes: bytes,
    filename: filename,
    mimeType: mimeType,
  );
}
