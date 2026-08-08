import 'report_print_stub.dart'
    if (dart.library.html) 'report_print_web.dart'
    as impl;

Object? prepareReportPrintTarget({
  String title = 'Preparing referral report...',
}) {
  return impl.prepareReportPrintTarget(title: title);
}

void closeReportPrintTarget(Object? target) {
  impl.closeReportPrintTarget(target);
}

bool printReportFile({
  required List<int> bytes,
  required String filename,
  String mimeType = 'application/pdf',
  Object? target,
}) {
  return impl.printReportFile(
    bytes: bytes,
    filename: filename,
    mimeType: mimeType,
    target: target,
  );
}
