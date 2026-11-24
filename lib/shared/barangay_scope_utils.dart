import 'dart:convert';

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

Future<QuerySnapshot<Map<String, dynamic>>> getScopedRecordQuerySnapshot(
  FirebaseFirestore firestore,
  String collectionName,
  UserAccessScope accessScope,
) async {
  final normalizedCollectionName = collectionName.trim();
  final baseQuery = buildScopedRecordQuery(
    firestore,
    normalizedCollectionName,
    accessScope,
  );
  if (accessScope.canViewAllBarangays) {
    return baseQuery.get();
  }

  final resolvedBarangayCode = resolveScopedBarangayCode(
    accessScope: accessScope,
  );
  Query<Map<String, dynamic>> primaryQuery = baseQuery;
  if (normalizedCollectionName == 'referrals' && accessScope.isBhw) {
    primaryQuery = primaryQuery.where(
      'createdByUid',
      isEqualTo: accessScope.userId,
    );
  }

  try {
    return await primaryQuery.get();
  } on FirebaseException catch (error) {
    if (error.code != 'permission-denied' ||
        resolvedBarangayCode == null ||
        resolvedBarangayCode.isEmpty) {
      rethrow;
    }

    Query<Map<String, dynamic>> filteredQuery = primaryQuery.where(
      'barangayCode',
      isEqualTo: resolvedBarangayCode,
    );
    try {
      return await filteredQuery.get();
    } on FirebaseException catch (filteredError) {
      if (filteredError.code != 'permission-denied') {
        rethrow;
      }
      try {
        return await primaryQuery.get(const GetOptions(source: Source.cache));
      } catch (_) {
        try {
          return await filteredQuery.get(
            const GetOptions(source: Source.cache),
          );
        } catch (_) {
          throw error;
        }
      }
    }
  }
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

/// Converts Firestore values to types supported by the mobile SQLite cache.
/// Firestore records can contain Timestamp, nested maps, or lists; passing
/// those objects directly to sqflite causes startup sync warnings/failures.
dynamic sqliteSafeValue(dynamic value) {
  if (value == null || value is num || value is String) return value;
  if (value is bool) return value ? 1 : 0;
  if (value is Timestamp) return value.toDate().toUtc().toIso8601String();
  if (value is DateTime) return value.toIso8601String();
  if (value is List) {
    return jsonEncode(value.map(sqliteSafeValue).toList(growable: false));
  }
  if (value is Map) {
    final normalized = <String, dynamic>{};
    value.forEach((key, nestedValue) {
      normalized[key.toString()] = sqliteSafeValue(nestedValue);
    });
    return jsonEncode(normalized);
  }
  return value.toString();
}

Map<String, dynamic> sanitizeRecordForSqlite(Map<String, dynamic> source) {
  return source.map((key, value) => MapEntry(key, sqliteSafeValue(value)));
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
    // Imported and manually transcribed records can legitimately predate the
    // modern timestamp schema. The visibility boundary must not hide records
    // authored by the same BHW who owns the current barangay workspace.
    final ownerIds = <String>{
      (record['createdByUid'] ?? '').toString().trim(),
      (record['recordScopeUserId'] ?? '').toString().trim(),
      (record['workspaceImportedForUid'] ?? '').toString().trim(),
    }..removeWhere((value) => value.isEmpty);
    return accessScope.userId.isNotEmpty &&
        ownerIds.contains(accessScope.userId);
  }

  return !activityDate.isBefore(visibleFrom);
}

/// Returns true for records that are explicitly synthetic or carry a stable
/// demo identifier. Production lists and analytics use this as a final guard
/// so an accidentally re-run seed cannot be presented as resident data.
bool isSyntheticDemoRecord(Map<String, dynamic> record) {
  if (record['isDemoData'] == true) return true;

  final demoDataset = (record['demoDataset'] ?? '').toString().trim();
  if (demoDataset.isNotEmpty) return true;

  final identifiers = <dynamic>[
    record['id'],
    record['patientId'],
    record['linkedPatientId'],
    record['patientRecordId'],
    record['recordId'],
  ];
  for (final identifier in identifiers) {
    final normalized = identifier?.toString().trim().toLowerCase() ?? '';
    if (normalized.startsWith('demo-') || normalized.startsWith('temp-seed-')) {
      return true;
    }
  }
  return false;
}

bool recordMatchesAccessScope(
  Map<String, dynamic> record,
  UserAccessScope accessScope, {
  String? selectedBarangay,
}) {
  if (isSyntheticDemoRecord(record)) return false;
  if (!recordMatchesInitializationWindow(record, accessScope)) {
    return false;
  }

  final scopedRecord = applyBarangayScopeToRecord(
    record,
    accessScope: accessScope,
  );
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

/// Removes root/workspace mirrors while preserving distinct clinical events.
/// Mirrors retain the same document ID, so deduplicating by ID is safe while
/// deduplicating by patient ID would incorrectly collapse repeat visits.
List<Map<String, dynamic>> deduplicateFirestoreRecords(
  Iterable<Map<String, dynamic>> records,
) {
  final byDocumentId = <String, Map<String, dynamic>>{};
  final withoutIdentity = <Map<String, dynamic>>[];

  for (final source in records) {
    final record = Map<String, dynamic>.from(source);
    if (isSyntheticDemoRecord(record)) continue;

    final documentId = (record['id'] ?? '').toString().trim();
    if (documentId.isEmpty) {
      withoutIdentity.add(record);
      continue;
    }

    final existing = byDocumentId[documentId];
    if (existing == null) {
      byDocumentId[documentId] = record;
      continue;
    }

    final existingPath = (existing['_firestorePath'] ?? '').toString();
    final candidatePath = (record['_firestorePath'] ?? '').toString();
    final existingIsWorkspace = existingPath.startsWith('barangays/');
    final candidateIsWorkspace = candidatePath.startsWith('barangays/');
    if (!existingIsWorkspace && candidateIsWorkspace) {
      byDocumentId[documentId] = record;
    }
  }

  return <Map<String, dynamic>>[...byDocumentId.values, ...withoutIdentity];
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
