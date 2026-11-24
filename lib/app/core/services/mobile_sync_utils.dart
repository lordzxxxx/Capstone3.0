import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:sqflite/sqflite.dart';
import 'package:mycapstone_project/firebase_helper.dart';
import 'package:mycapstone_project/shared/barangay_scope_utils.dart';
import 'package:mycapstone_project/shared/user_access_scope.dart';
import 'package:mycapstone_project/web/shared/services/user_access_scope_service.dart';

/// Serializes outbound sync attempts for one local module.
///
/// Save-triggered retries and connectivity listeners can fire at the same
/// time. Waiting for the active operation prevents two snapshots of the same
/// SQLite queue from racing and makes every caller observe the completed run.
final class MobileSyncQueue {
  Future<void> _tail = Future<void>.value();

  /// Schedules [operation] after every operation already submitted.
  ///
  /// Reserving the slot before awaiting is important: with a shared active
  /// future, two callers that wake when the first attempt completes can both
  /// start together. A chained tail keeps retries strictly FIFO, including
  /// after an operation fails.
  Future<void> run(Future<void> Function() operation) {
    final scheduled = _tail
        .catchError((_) {
          // A failed attempt is reported to its original caller but must not
          // prevent the next queued record snapshot from being attempted.
        })
        .then((_) => operation());
    _tail = scheduled;
    return scheduled.whenComplete(() {
      if (identical(_tail, scheduled)) {
        _tail = Future<void>.value();
      }
    });
  }
}

/// Outcome of one module in a complete mobile synchronization pass.
final class MobileSyncStepResult {
  const MobileSyncStepResult({
    required this.module,
    required this.succeeded,
    this.error,
  });

  final String module;
  final bool succeeded;
  final Object? error;
}

/// Runs every module even when one local store or remote collection fails.
///
/// Health records are stored in independent SQLite databases. Treating the
/// pass as all-or-nothing meant an issue in one module (for example, a schema
/// migration error) silently delayed every later module. Each failure remains
/// observable in the returned result while unaffected modules still reconcile.
Future<List<MobileSyncStepResult>> runMobileSyncOperations(
  Map<String, Future<void> Function()> operations,
) async {
  final results = <MobileSyncStepResult>[];
  for (final entry in operations.entries) {
    try {
      await entry.value();
      results.add(MobileSyncStepResult(module: entry.key, succeeded: true));
    } catch (error) {
      results.add(
        MobileSyncStepResult(module: entry.key, succeeded: false, error: error),
      );
    }
  }
  return results;
}

/// Adds the current authenticated user's scope to a mobile Firestore write.
///
/// Local SQLite rows intentionally keep only each module's canonical schema,
/// so scope metadata must be restored at the outbound boundary. BHW scope is
/// always taken from the authenticated profile rather than from a local row;
/// this prevents an offline row from changing the barangay it can write to.
Map<String, dynamic> applyMobileFirestoreScope(
  Map<String, dynamic> record, {
  required UserAccessScope accessScope,
  String? currentUserId,
}) {
  if (!accessScope.isAuthenticated) {
    throw StateError('Authenticated access scope is required for mobile sync.');
  }

  final scoped = Map<String, dynamic>.from(record);
  if (accessScope.isBhw) {
    final resolvedCode = resolveScopedBarangayCode(accessScope: accessScope);
    if (resolvedCode == null && accessScope.barangay.trim().isEmpty) {
      throw StateError(
        'The BHW account has no barangay scope for mobile sync.',
      );
    }
    if (resolvedCode != null && resolvedCode.isNotEmpty) {
      scoped['barangayCode'] = resolvedCode;
    }
    if (accessScope.barangay.trim().isNotEmpty) {
      scoped['barangay'] = accessScope.barangay.trim();
    }
    if (accessScope.barangayDistrict.trim().isNotEmpty) {
      scoped['barangayDistrict'] = accessScope.barangayDistrict.trim();
    }
  } else {
    scoped.addAll(applyBarangayScopeToRecord(scoped, accessScope: accessScope));
  }

  if ((scoped['createdBy'] ?? '').toString().trim().isEmpty &&
      currentUserId != null &&
      currentUserId.trim().isNotEmpty) {
    scoped['createdBy'] = currentUserId.trim();
  }
  return scoped;
}

/// Loads the current authenticated scope immediately before an outbound write.
Future<Map<String, dynamic>> currentMobileFirestoreData(
  Map<String, dynamic> record,
) async {
  final currentUser = FirebaseAuth.instance.currentUser;
  if (currentUser == null) {
    throw StateError('Sign in before synchronizing mobile records.');
  }
  final accessScope = await UserAccessScopeService.instance.loadCurrentScope();
  return applyMobileFirestoreScope(
    record,
    accessScope: accessScope,
    currentUserId: currentUser.uid,
  );
}

/// Resolves the same canonical document path used by the web BHW workspace.
/// Mobile previously attached barangay metadata but still wrote to the root
/// collection, so CHO could see an event that the BHW web workspace could not.
Future<DocumentReference<Map<String, dynamic>>>
currentMobileFirestoreDocumentReference(
  String collectionName,
  String documentId, {
  Map<String, dynamic>? record,
}) async {
  final currentUser = FirebaseAuth.instance.currentUser;
  if (currentUser == null) {
    throw StateError('Sign in before synchronizing mobile records.');
  }
  final accessScope = await UserAccessScopeService.instance.loadCurrentScope();
  return resolveScopedRecordDocumentReference(
    getFirestoreInstance(),
    collectionName,
    documentId,
    accessScope: accessScope,
    record: record,
  );
}

/// Remote refreshes must not replace an offline edit that is still waiting for
/// outbound sync. Each database helper keeps its existing schema and sync
/// strategy; this small guard only protects the local pending row.
Future<bool> hasPendingLocalSync(
  Database db, {
  required String table,
  required String id,
}) async {
  final rows = await db.query(
    table,
    columns: const ['synced'],
    where: 'id = ?',
    whereArgs: [id],
    limit: 1,
  );
  return rows.isNotEmpty && rows.first['synced'] == 0;
}
