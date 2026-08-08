import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mycapstone_project/shared/barangay_firestore_paths.dart';
import 'package:mycapstone_project/shared/malaybalay_barangays.dart';
import 'package:mycapstone_project/shared/user_access_scope.dart';

BarangayReference? inferBarangayReference(Map<String, dynamic> record) {
  final barangayCode = (record['barangayCode'] ?? '').toString().trim();
  final byCode = MalaybalayBarangays.byCode(barangayCode);
  if (byCode != null) {
    return byCode;
  }

  final explicitNames = <String>[
    (record['barangay'] ?? '').toString(),
    (record['barangayName'] ?? '').toString(),
    (record['assignedBarangay'] ?? '').toString(),
  ];
  for (final name in explicitNames) {
    final match = MalaybalayBarangays.byName(name);
    if (match != null) return match;
  }

  final searchableText = <String>[
    (record['address'] ?? '').toString(),
    (record['place'] ?? '').toString(),
    (record['street'] ?? '').toString(),
  ].join(' ').toLowerCase();

  for (final barangay in MalaybalayBarangays.all) {
    if (searchableText.contains(barangay.name.toLowerCase())) {
      return barangay;
    }
  }

  return null;
}

String normalizeStoredBarangayCode(String? barangayCode) {
  final trimmed = (barangayCode ?? '').trim();
  if (trimmed.isEmpty) {
    return '';
  }
  return BarangayFirestorePaths.normalizeBarangayCode(trimmed);
}

String? resolveScopedBarangayCode({
  Map<String, dynamic>? record,
  UserAccessScope? accessScope,
}) {
  final inferred = record == null ? null : inferBarangayReference(record);
  if (inferred != null) {
    return normalizeStoredBarangayCode(inferred.code);
  }

  final scopeBarangayCode = normalizeStoredBarangayCode(
    accessScope?.barangayCode,
  );
  if (scopeBarangayCode.isNotEmpty) {
    return scopeBarangayCode;
  }

  final scopeBarangay = MalaybalayBarangays.byName(accessScope?.barangay);
  if (scopeBarangay != null) {
    return normalizeStoredBarangayCode(scopeBarangay.code);
  }

  return null;
}

Map<String, dynamic> applyBarangayScopeToRecord(
  Map<String, dynamic> record, {
  UserAccessScope? accessScope,
}) {
  final output = Map<String, dynamic>.from(record);
  final inferred = inferBarangayReference(output);

  BarangayReference? resolved = inferred;
  if (resolved == null &&
      accessScope != null &&
      accessScope.barangay.isNotEmpty) {
    resolved = MalaybalayBarangays.byName(accessScope.barangay);
  }

  if (resolved != null) {
    output['barangay'] = resolved.name;
    output['barangayCode'] = normalizeStoredBarangayCode(resolved.code);
    output['barangayDistrict'] = resolved.district;
  } else {
    output['barangay'] = (output['barangay'] ?? '').toString();
    output['barangayCode'] = normalizeStoredBarangayCode(
      (output['barangayCode'] ?? '').toString(),
    );
    output['barangayDistrict'] = (output['barangayDistrict'] ?? '').toString();
  }

  if (accessScope != null && accessScope.userId.isNotEmpty) {
    output['recordScopeRole'] = accessScope.role;
    output['recordScopeUserId'] = accessScope.userId;
  }

  return output;
}

Query<Map<String, dynamic>> buildScopedRecordQuery(
  FirebaseFirestore firestore,
  String collectionName,
  UserAccessScope accessScope,
) {
  final normalizedCollectionName = collectionName.trim();

  if (accessScope.canViewAllBarangays) {
    return firestore.collectionGroup(normalizedCollectionName);
  }

  final resolvedBarangayCode = resolveScopedBarangayCode(
    accessScope: accessScope,
  );
  if (resolvedBarangayCode != null && resolvedBarangayCode.isNotEmpty) {
    return firestore
        .collection(BarangayFirestorePaths.barangaysCollection)
        .doc(resolvedBarangayCode)
        .collection(normalizedCollectionName);
  }

  return firestore
      .collectionGroup(normalizedCollectionName)
      .where('barangayCode', isEqualTo: '__NO_ACCESS_SCOPE__');
}

Future<DocumentReference<Map<String, dynamic>>>
resolveScopedRecordDocumentReference(
  FirebaseFirestore firestore,
  String collectionName,
  String documentId, {
  UserAccessScope? accessScope,
  Map<String, dynamic>? record,
  String? existingPath,
}) async {
  final trimmedExistingPath = (existingPath ?? '').trim();
  if (trimmedExistingPath.isNotEmpty) {
    return firestore.doc(trimmedExistingPath);
  }

  if (accessScope?.canViewAllBarangays == true) {
    final existingNestedRecord = await firestore
        .collectionGroup(collectionName.trim())
        .where(FieldPath.documentId, isEqualTo: documentId.trim())
        .limit(1)
        .get();
    if (existingNestedRecord.docs.isNotEmpty) {
      return existingNestedRecord.docs.first.reference;
    }
  }

  final resolvedBarangayCode = resolveScopedBarangayCode(
    record: record,
    accessScope: accessScope,
  );
  if (resolvedBarangayCode != null && resolvedBarangayCode.isNotEmpty) {
    return firestore.doc(
      BarangayFirestorePaths.barangayRecordDocumentPath(
        resolvedBarangayCode,
        collectionName,
        documentId,
      ),
    );
  }

  if (accessScope?.isBhw == true) {
    throw StateError(
      'This BHW account has no barangay scope loaded yet. Sign out and sign in again, or ask CHO to verify the barangay assignment.',
    );
  }

  return firestore.collection(collectionName.trim()).doc(documentId.trim());
}

Map<String, dynamic> materializeFirestoreRecord(
  QueryDocumentSnapshot<Map<String, dynamic>> doc,
) {
  return <String, dynamic>{
    ...doc.data(),
    'id': doc.id,
    '_firestorePath': doc.reference.path,
  };
}

Query<Map<String, dynamic>> applyAccessScopeToQuery(
  Query<Map<String, dynamic>> query,
  UserAccessScope accessScope,
) {
  if (accessScope.canViewAllBarangays) {
    return query;
  }

  if (accessScope.barangayCode.isNotEmpty) {
    return query.where(
      'barangayCode',
      isEqualTo: normalizeStoredBarangayCode(accessScope.barangayCode),
    );
  }

  if (accessScope.barangay.isNotEmpty) {
    return query.where('barangay', isEqualTo: accessScope.barangay);
  }

  return query.where('barangayCode', isEqualTo: '__NO_ACCESS_SCOPE__');
}

DateTime? extractRecordActivityDate(Map<String, dynamic> record) {
  final candidates = <dynamic>[
    record['createdAt'],
    record['updatedAt'],
    record['registrationDate'],
    record['datetime'],
    record['dateReported'],
    record['administrationDate'],
    record['date'],
    record['time'],
  ];

  for (final value in candidates) {
    if (value == null) continue;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String && value.trim().isNotEmpty) {
      final parsed = DateTime.tryParse(value.trim());
      if (parsed != null) return parsed;
    }
  }

  return null;
}

bool recordMatchesInitializationWindow(
  Map<String, dynamic> record,
  UserAccessScope accessScope,
) {
  final visibleFrom = accessScope.dataVisibleFrom;
  if (visibleFrom == null) {
    return true;
  }

  final activityDate = extractRecordActivityDate(record);
  if (activityDate == null) {
    return false;
  }

  return !activityDate.isBefore(visibleFrom);
}

bool recordMatchesAccessScope(
  Map<String, dynamic> record,
  UserAccessScope accessScope, {
  String? selectedBarangay,
  bool allowHistoricalBhwAnalyticsDemo = false,
}) {
  final scopedRecord = applyBarangayScopeToRecord(
    record,
    accessScope: accessScope,
  );
  final demoDataset = (scopedRecord['demoDataset'] ?? '').toString();
  final isBhwAnalyticsDemo =
      scopedRecord['isDemoData'] == true &&
      demoDataset.startsWith('bhw-analytics-demo-');
  final bypassInitializationWindow =
      allowHistoricalBhwAnalyticsDemo && isBhwAnalyticsDemo;
  if (!bypassInitializationWindow &&
      !recordMatchesInitializationWindow(scopedRecord, accessScope)) {
    return false;
  }
  final barangay = (scopedRecord['barangay'] ?? '').toString();
  final barangayCode = normalizeStoredBarangayCode(
    (scopedRecord['barangayCode'] ?? '').toString(),
  );

  if (selectedBarangay != null && selectedBarangay.isNotEmpty) {
    final selectedRef = MalaybalayBarangays.byName(selectedBarangay);
    if (selectedRef != null) {
      return barangayCode == normalizeStoredBarangayCode(selectedRef.code) ||
          barangay == selectedRef.name;
    }
    return barangay == selectedBarangay;
  }

  if (accessScope.canViewAllBarangays) {
    return true;
  }

  if (accessScope.barangayCode.isNotEmpty) {
    return barangayCode ==
        normalizeStoredBarangayCode(accessScope.barangayCode);
  }

  if (accessScope.barangay.isNotEmpty) {
    return barangay == accessScope.barangay;
  }

  return false;
}

List<Map<String, dynamic>> sortRecordsByActivityDateDescending(
  Iterable<Map<String, dynamic>> records,
) {
  final sorted = records
      .map((record) => Map<String, dynamic>.from(record))
      .toList(growable: false);

  sorted.sort((a, b) {
    final aDate = extractRecordActivityDate(a);
    final bDate = extractRecordActivityDate(b);

    if (aDate == null && bDate == null) {
      return 0;
    }
    if (aDate == null) {
      return 1;
    }
    if (bDate == null) {
      return -1;
    }
    return bDate.compareTo(aDate);
  });

  return sorted;
}
