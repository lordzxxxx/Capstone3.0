import 'report_download_stub.dart'
    if (dart.library.html) 'report_download_web.dart' as impl;

bool downloadReportFile({
  required List<int> bytes,
  required String filename,
  required String mimeType,
}) {
  return impl.downloadReportFile(
    bytes: bytes,
    filename: filename,
    mimeType: mimeType,
  );
}