/// Client-side checks for files that will also be enforced by Storage Rules.
///
/// These checks improve feedback and avoid unnecessary uploads. They are not
/// an authorization boundary; the Firebase Storage rules remain authoritative.
class StorageUploadPolicy {
  StorageUploadPolicy._();

  static const int maxBrandingBytes = 5 * 1024 * 1024;
  static const int maxReferralAttachmentBytes = 10 * 1024 * 1024;

  static const Map<String, Set<String>> _extensionsByContentType = {
    'image/png': {'png'},
    'image/jpeg': {'jpg', 'jpeg'},
    'image/webp': {'webp'},
    'application/pdf': {'pdf'},
  };

  static void validateBranding({
    required int size,
    required String fileName,
    required String contentType,
  }) {
    _validate(
      size: size,
      fileName: fileName,
      contentType: contentType,
      maxBytes: maxBrandingBytes,
      allowedContentTypes: const {'image/png', 'image/jpeg', 'image/webp'},
      label: 'Branding images',
    );
  }

  static void validateReferralAttachment({
    required int size,
    required String fileName,
    required String contentType,
  }) {
    _validate(
      size: size,
      fileName: fileName,
      contentType: contentType,
      maxBytes: maxReferralAttachmentBytes,
      allowedContentTypes: const {'application/pdf', 'image/jpeg', 'image/png'},
      label: 'Referral attachments',
    );
  }

  static void _validate({
    required int size,
    required String fileName,
    required String contentType,
    required int maxBytes,
    required Set<String> allowedContentTypes,
    required String label,
  }) {
    if (size <= 0) {
      throw FormatException('$label must not be empty.');
    }
    if (size > maxBytes) {
      throw FormatException(
        '$label must be ${_megabytes(maxBytes)} MB or smaller.',
      );
    }

    final normalizedType = contentType.trim().toLowerCase();
    if (!allowedContentTypes.contains(normalizedType)) {
      throw FormatException('$label have an unsupported file type.');
    }

    final extension = _extensionOf(fileName);
    final allowedExtensions = _extensionsByContentType[normalizedType]!;
    if (!allowedExtensions.contains(extension)) {
      throw FormatException(
        'The file extension does not match its declared content type.',
      );
    }
  }

  static String _extensionOf(String fileName) {
    final name = fileName.trim().toLowerCase();
    final dot = name.lastIndexOf('.');
    if (dot < 1 || dot == name.length - 1) return '';
    return name.substring(dot + 1);
  }

  static String _megabytes(int bytes) => (bytes ~/ (1024 * 1024)).toString();
}
