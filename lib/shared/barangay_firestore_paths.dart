class BarangayFirestorePaths {
  const BarangayFirestorePaths._();

  static const String barangaysCollection = 'barangays';
  static const String usersCollection = 'users';

  static String normalizeBarangayCode(String barangayCode) {
    return barangayCode.trim().toUpperCase();
  }

  static String barangayDocumentPath(String barangayCode) {
    final normalizedCode = normalizeBarangayCode(barangayCode);
    return '$barangaysCollection/$normalizedCode';
  }

  static String barangayUserDocumentPath(String barangayCode, String uid) {
    final normalizedUid = uid.trim();
    return '${barangayDocumentPath(barangayCode)}/$usersCollection/$normalizedUid';
  }

  static String barangayRecordCollectionPath(
    String barangayCode,
    String collectionName,
  ) {
    final normalizedCollectionName = collectionName.trim();
    return '${barangayDocumentPath(barangayCode)}/$normalizedCollectionName';
  }

  static String barangayRecordDocumentPath(
    String barangayCode,
    String collectionName,
    String documentId,
  ) {
    final normalizedDocumentId = documentId.trim();
    return '${barangayRecordCollectionPath(barangayCode, collectionName)}/$normalizedDocumentId';
  }
}
