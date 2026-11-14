import 'package:web/web.dart' as web;

bool openReferralAttachmentUrl(String url) {
  final normalized = url.trim();
  if (normalized.isEmpty) return false;
  try {
    return web.window.open(normalized, '_blank') != null;
  } catch (_) {
    return false;
  }
}
