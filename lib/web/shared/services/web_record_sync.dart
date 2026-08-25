import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:mycapstone_project/web/shared/utils/browser_online_state.dart';

/// User-visible lifecycle for a web clinical record.
///
/// The values are intentionally broader than Firestore's `hasPendingWrites`:
/// cached reads, queued writes, rejected writes, and version conflicts require
/// different instructions for a health worker.
enum WebRecordSyncState {
  savedLocally,
  pending,
  syncing,
  synchronized,
  failed,
  conflict,
}

class WebRecordSyncStatus {
  const WebRecordSyncStatus({
    required this.state,
    required this.label,
    required this.instruction,
    this.error,
  });

  final WebRecordSyncState state;
  final String label;
  final String instruction;
  final String? error;

  bool get canRetry =>
      state == WebRecordSyncState.failed || state == WebRecordSyncState.pending;

  static WebRecordSyncStatus fromRecord(Map<String, dynamic> record) {
    final explicit = (record['_syncStatus'] ?? record['syncStatus'])
        ?.toString()
        .trim()
        .toLowerCase();
    final error = (record['_syncError'] ?? record['syncError'])
        ?.toString()
        .trim();
    final hasConflict =
        record['_hasConflict'] == true ||
        record['hasConflict'] == true ||
        explicit == 'conflict';
    if (hasConflict) {
      return WebRecordSyncStatus(
        state: WebRecordSyncState.conflict,
        label: 'Conflict—review required',
        instruction:
            'A newer remote change exists. Compare both versions before saving.',
        error: error?.isEmpty == true ? null : error,
      );
    }
    if (error?.isNotEmpty == true || explicit == 'failed') {
      return WebRecordSyncStatus(
        state: WebRecordSyncState.failed,
        label: 'Synchronization failed',
        instruction:
            'Your local information is retained. Check the connection, then retry.',
        error: error,
      );
    }
    if (explicit == 'syncing') {
      return const WebRecordSyncStatus(
        state: WebRecordSyncState.syncing,
        label: 'Synchronizing',
        instruction: 'Keep this browser open while the change is confirmed.',
      );
    }
    if (record['_hasPendingWrites'] == true ||
        record['hasPendingWrites'] == true ||
        explicit == 'pending' ||
        record['synced'] == 0) {
      return const WebRecordSyncStatus(
        state: WebRecordSyncState.pending,
        label: 'Pending synchronization',
        instruction:
            'The change is queued and will retry when the connection is available.',
      );
    }
    if (record['_isFromCache'] == true || explicit == 'saved_locally') {
      return const WebRecordSyncStatus(
        state: WebRecordSyncState.savedLocally,
        label: 'Saved locally',
        instruction:
            'This cached copy remains available offline. Reconnect to confirm the latest server version.',
      );
    }
    return const WebRecordSyncStatus(
      state: WebRecordSyncState.synchronized,
      label: 'Synchronized',
      instruction: 'The server has confirmed this version.',
    );
  }
}

Map<String, dynamic> attachWebSyncMetadata(
  Map<String, dynamic> record, {
  required bool hasPendingWrites,
  required bool isFromCache,
}) {
  final documentId = (record['id'] ?? '').toString();
  final trackedState = WebPendingWriteRegistry.stateFor(documentId);
  final trackedError = WebPendingWriteRegistry.errorFor(documentId);
  final explicitState =
      trackedState == WebRecordSyncState.failed ||
          trackedState == WebRecordSyncState.conflict
      ? trackedState?.name
      : hasPendingWrites
      ? 'pending'
      : isFromCache
      ? 'saved_locally'
      : trackedState == WebRecordSyncState.syncing
      ? 'syncing'
      : 'synchronized';
  return <String, dynamic>{
    ...record,
    '_hasPendingWrites': hasPendingWrites,
    '_isFromCache': isFromCache,
    if (trackedError != null) '_syncError': trackedError,
    '_syncStatus': explicitState,
  };
}

/// Keeps non-sensitive write state long enough for metadata snapshots to
/// explain a timeout or rejected queued write. No patient payload is stored.
abstract final class WebPendingWriteRegistry {
  static final Map<String, WebRecordSyncState> _states = {};
  static final Map<String, String> _errors = {};

  static WebRecordSyncState? stateFor(String documentId) => _states[documentId];

  static String? errorFor(String documentId) => _errors[documentId];

  static void mark(
    String documentId,
    WebRecordSyncState state, {
    Object? error,
  }) {
    if (documentId.isEmpty) return;
    _states[documentId] = state;
    if (error == null) {
      _errors.remove(documentId);
    } else {
      _errors[documentId] = _safeError(error);
    }
  }

  static String _safeError(Object error) {
    if (error is FirebaseException) {
      return switch (error.code) {
        'permission-denied' =>
          'Your account is not allowed to synchronize this record.',
        'unavailable' => 'The server is temporarily unavailable.',
        'unauthenticated' => 'Sign in again before retrying synchronization.',
        _ => 'The server rejected the queued change (${error.code}).',
      };
    }
    return 'The queued change could not be synchronized.';
  }

  static void clearForTest() {
    _states.clear();
    _errors.clear();
  }
}

int recordVersionOf(Map<String, dynamic> record) {
  final value = record['recordVersion'];
  if (value is int && value >= 0) return value;
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

Map<String, dynamic> stripLocalWebMetadata(Map<String, dynamic> record) {
  return Map<String, dynamic>.from(record)
    ..removeWhere((key, _) => key.startsWith('_'))
    ..remove('syncStatus')
    ..remove('syncError')
    ..remove('hasPendingWrites')
    ..remove('hasConflict');
}

class WebRecordWriteException implements Exception {
  const WebRecordWriteException(this.message);

  final String message;

  @override
  String toString() => message;
}

class WebOfflineEditException extends WebRecordWriteException {
  const WebOfflineEditException()
    : super(
        'Editing requires a connection so a newer server version is not overwritten. Your existing record is unchanged.',
      );
}

class WebRecordConflictException extends WebRecordWriteException {
  const WebRecordConflictException({
    required this.expectedVersion,
    required this.remoteVersion,
  }) : super(
         'This record changed on another device. Review the latest version before applying your edit.',
       );

  final int expectedVersion;
  final int remoteVersion;
}

typedef WebConnectivityCheck = Future<bool> Function();

class WebRecordWriteCoordinator {
  WebRecordWriteCoordinator({
    required FirebaseFirestore firestore,
    WebConnectivityCheck? connectivityCheck,
  }) : _firestore = firestore,
       _connectivityCheck = connectivityCheck ?? _defaultConnectivityCheck;

  final FirebaseFirestore _firestore;
  final WebConnectivityCheck _connectivityCheck;

  /// Starts an idempotent create and returns after either server confirmation
  /// or a short acknowledgement window. A timeout does not cancel Firestore's
  /// durable offline queue; subsequent metadata snapshots remain `pending`.
  Future<WebRecordSyncState> create({
    required DocumentReference<Map<String, dynamic>> reference,
    required Map<String, dynamic> record,
    Duration acknowledgementTimeout = const Duration(seconds: 2),
  }) async {
    final documentId = reference.id;
    WebPendingWriteRegistry.mark(documentId, WebRecordSyncState.syncing);
    final operation = reference.set(
      prepareCreate(record, documentId: documentId),
    );
    unawaited(
      operation.then<void>(
        (_) => WebPendingWriteRegistry.mark(
          documentId,
          WebRecordSyncState.synchronized,
        ),
        onError: (Object error, StackTrace _) {
          WebPendingWriteRegistry.mark(
            documentId,
            WebRecordSyncState.failed,
            error: error,
          );
        },
      ),
    );
    try {
      await operation.timeout(acknowledgementTimeout);
      return WebRecordSyncState.synchronized;
    } on TimeoutException {
      WebPendingWriteRegistry.mark(documentId, WebRecordSyncState.pending);
      return WebRecordSyncState.pending;
    }
  }

  static Future<bool> _defaultConnectivityCheck() async {
    if (browserIsOnline() == false) return false;
    final result = await Connectivity().checkConnectivity();
    return !result.contains(ConnectivityResult.none);
  }

  /// Applies an edit only when the browser can compare the user's base
  /// version with the authoritative server version in one transaction.
  Future<int> update({
    required DocumentReference<Map<String, dynamic>> reference,
    required Map<String, dynamic> changes,
    required int expectedVersion,
  }) async {
    final documentId = reference.id;
    if (!await _connectivityCheck()) {
      WebPendingWriteRegistry.mark(documentId, WebRecordSyncState.failed);
      throw const WebOfflineEditException();
    }

    WebPendingWriteRegistry.mark(documentId, WebRecordSyncState.syncing);
    try {
      final nextVersion = await _firestore.runTransaction<int>((
        transaction,
      ) async {
        final snapshot = await transaction.get(reference);
        if (!snapshot.exists) {
          throw const WebRecordWriteException(
            'The record no longer exists on the server. Refresh before continuing.',
          );
        }
        final remoteVersion = recordVersionOf(snapshot.data() ?? const {});
        if (remoteVersion != expectedVersion) {
          throw WebRecordConflictException(
            expectedVersion: expectedVersion,
            remoteVersion: remoteVersion,
          );
        }
        final nextVersion = remoteVersion + 1;
        transaction.update(reference, <String, dynamic>{
          ...stripLocalWebMetadata(changes),
          'recordVersion': nextVersion,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        return nextVersion;
      });
      WebPendingWriteRegistry.mark(documentId, WebRecordSyncState.synchronized);
      return nextVersion;
    } on WebRecordConflictException catch (error) {
      WebPendingWriteRegistry.mark(
        documentId,
        WebRecordSyncState.conflict,
        error: error,
      );
      rethrow;
    } catch (error) {
      WebPendingWriteRegistry.mark(
        documentId,
        WebRecordSyncState.failed,
        error: error,
      );
      rethrow;
    }
  }

  /// Adds stable metadata to a create payload. Reusing the same document ID
  /// and operation ID makes a repeated browser submission idempotent.
  static Map<String, dynamic> prepareCreate(
    Map<String, dynamic> record, {
    required String documentId,
  }) {
    return <String, dynamic>{
      ...stripLocalWebMetadata(record),
      'id': documentId,
      'clientOperationId': documentId,
      'recordVersion': 1,
    };
  }
}
