import 'csv_download_stub.dart'
    if (dart.library.html) 'csv_download_web.dart' as impl;

bool downloadCsvFile({
  required List<int> bytes,
  required String filename,
}) {
  return impl.downloadCsvFile(
    bytes: bytes,
    filename: filename,
  );
}
