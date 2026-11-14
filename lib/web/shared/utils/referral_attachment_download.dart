import 'referral_attachment_download_stub.dart'
    if (dart.library.html) 'referral_attachment_download_web.dart'
    as impl;

bool openReferralAttachmentUrl(String url) {
  return impl.openReferralAttachmentUrl(url);
}
