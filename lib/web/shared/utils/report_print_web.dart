import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

class _ReportPrintTarget {
  const _ReportPrintTarget(this.window);

  final web.Window window;
}

Object? prepareReportPrintTarget({
  String title = 'Preparing referral report...',
}) {
  try {
    final target = web.window.open('', '_blank');
    return target == null ? null : _ReportPrintTarget(target);
  } catch (_) {
    return null;
  }
}

void closeReportPrintTarget(Object? target) {
  if (target is _ReportPrintTarget) {
    try {
      target.window.close();
    } catch (_) {}
  }
}

bool printReportFile({
  required List<int> bytes,
  required String filename,
  String mimeType = 'application/pdf',
  Object? target,
}) {
  final blob = web.Blob(
    <web.BlobPart>[Uint8List.fromList(bytes).toJS].toJS,
    web.BlobPropertyBag(type: mimeType),
  );
  final pdfUrl = web.URL.createObjectURL(blob);

  try {
    if (target is _ReportPrintTarget) {
      target.window.location.href = pdfUrl;
    } else {
      web.window.open(pdfUrl, '_blank');
    }
  } catch (_) {
    web.URL.revokeObjectURL(pdfUrl);
    return false;
  }

  Future<void>.delayed(const Duration(minutes: 2), () {
    web.URL.revokeObjectURL(pdfUrl);
  });
  return true;
}
