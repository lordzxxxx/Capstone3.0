Object? prepareReportPrintTarget({
  String title = 'Preparing referral report...',
}) {
  return null;
}

void closeReportPrintTarget(Object? target) {}

bool printReportFile({
  required List<int> bytes,
  required String filename,
  String mimeType = 'application/pdf',
  Object? target,
}) {
  return false;
}
