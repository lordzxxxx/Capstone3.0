import 'package:flutter_test/flutter_test.dart';
import 'package:mycapstone_project/web/shared/services/storage_upload_policy.dart';

void main() {
  test('accepts an allowed branding image within the size limit', () {
    expect(
      () => StorageUploadPolicy.validateBranding(
        size: 1024,
        fileName: 'barangay-logo.webp',
        contentType: 'image/webp',
      ),
      returnsNormally,
    );
  });

  test('rejects oversized or mismatched branding files', () {
    expect(
      () => StorageUploadPolicy.validateBranding(
        size: StorageUploadPolicy.maxBrandingBytes + 1,
        fileName: 'logo.png',
        contentType: 'image/png',
      ),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => StorageUploadPolicy.validateBranding(
        size: 1024,
        fileName: 'logo.gif',
        contentType: 'image/png',
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('accepts referral PDFs and rejects unsupported types', () {
    expect(
      () => StorageUploadPolicy.validateReferralAttachment(
        size: 2048,
        fileName: 'referral.pdf',
        contentType: 'application/pdf',
      ),
      returnsNormally,
    );
    expect(
      () => StorageUploadPolicy.validateReferralAttachment(
        size: 2048,
        fileName: 'referral.exe',
        contentType: 'application/octet-stream',
      ),
      throwsA(isA<FormatException>()),
    );
  });
}
