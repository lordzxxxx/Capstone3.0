import 'dart:html' as html;
import 'dart:typed_data';

Object? prepareReportPrintTarget({
  String title = 'Preparing referral report...',
}) {
  try {
    final target = html.window.open('', '_blank');
    return target;
  } catch (_) {
    return null;
  }
}

void closeReportPrintTarget(Object? target) {
  if (target is html.WindowBase) {
    try {
      target.close();
    } catch (_) {}
  }
}

bool printReportFile({
  required List<int> bytes,
  required String filename,
  String mimeType = 'application/pdf',
  Object? target,
}) {
  final blob = html.Blob([Uint8List.fromList(bytes)], mimeType);
  final pdfUrl = html.Url.createObjectUrlFromBlob(blob);

  try {
    if (target is html.WindowBase) {
      target.location.href = pdfUrl;
    } else {
      html.window.open(pdfUrl, '_blank');
    }
  } catch (_) {
    html.Url.revokeObjectUrl(pdfUrl);
    return false;
  }

  Future<void>.delayed(const Duration(minutes: 2), () {
    html.Url.revokeObjectUrl(pdfUrl);
  });
  return true;
}
