import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:mycapstone_project/app/features/checkups/checkup_database_helper.dart';
import 'package:mycapstone_project/app/features/immunization/immunization_database_helper.dart';
import 'package:mycapstone_project/app/features/surveillance/morbidity/morbidity_database_helper.dart';
import 'package:mycapstone_project/app/features/surveillance/mortality/mortality_database_helper.dart';
import 'package:mycapstone_project/app/features/patients/patient_database_helper.dart';
import 'package:mycapstone_project/app/features/prenatal/prenatal_database_helper.dart';
import 'package:mycapstone_project/app/core/services/mobile_sync_utils.dart';

bool _mobileSyncBootstrapInitialized = false;
const String _mobileSyncCacheOwnerUidKey = 'mobile_sync_cache_owner_uid';
const Duration _mobileSyncStartupTimeout = Duration(seconds: 20);
StreamSubscription<List<ConnectivityResult>>? _mobileConnectivitySubscription;
Timer? _mobileSyncRetryTimer;
bool _mobileSyncPassRunning = false;
int _mobileSyncRetryAttempt = 0;

bool _hasNetwork(List<ConnectivityResult> results) =>
    !results.contains(ConnectivityResult.none);

/// A bounded reconciliation retry protects the common case where Android
/// reports Wi-Fi before that network can actually reach Firestore. We retry
/// after a successful reconnect as well: the first pass can be served from a
/// stale transport while the second pass flushes the SQLite outbox.
Duration _retryDelayFor(int attempt) {
  const delays = <Duration>[
    Duration(seconds: 3),
    Duration(seconds: 12),
    Duration(seconds: 45),
  ];
  return delays[attempt.clamp(0, delays.length - 1)];
}

void _startAllMobileSyncListeners() {
  DatabaseHelper.instance.startConnectivityListener();
  PrenatalDatabaseHelper.instance.startConnectivityListener();
  ImmunizationDatabaseHelper.instance.startConnectivityListener();
  PatientDatabaseHelper.instance.startConnectivityListener();
  MortalityDatabaseHelper.instance.startConnectivityListener();
  MorbidityDatabaseHelper.instance.startConnectivityListener();
}

/// Confirms an individual module did not silently leave local writes queued.
/// Several legacy helpers log per-record Firestore errors to keep the local
/// database safe. This boundary turns that condition into an observable pass
/// failure so the coordinator can retry after connectivity recovers.
Future<void> _syncAndVerifyOutbox({
  required String module,
  required Future<void> Function() sync,
  required Future<Database> database,
  required String table,
}) async {
  await sync();
  final db = await database;
  final queued =
      Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM $table WHERE synced = 0'),
      ) ??
      0;
  if (queued > 0) {
    throw StateError('$module still has $queued record(s) waiting to sync.');
  }
}

Future<void> _clearAllMobileLocalCaches() async {
  await DatabaseHelper.instance.clearLocalCache();
  await PrenatalDatabaseHelper.instance.clearLocalCache();
  await ImmunizationDatabaseHelper.instance.clearLocalCache();
  await PatientDatabaseHelper.instance.clearLocalCache();
  await MortalityDatabaseHelper.instance.clearLocalCache();
  await MorbidityDatabaseHelper.instance.clearLocalCache();
}

Future<void> _ensureCurrentUserOwnsMobileCache(User user) async {
  final currentUid = user.uid.trim();
  if (currentUid.isEmpty) {
    return;
  }

  final prefs = await SharedPreferences.getInstance();
  final cachedUid = (prefs.getString(_mobileSyncCacheOwnerUidKey) ?? '').trim();

  if (cachedUid.isNotEmpty && cachedUid != currentUid) {
    await _clearAllMobileLocalCaches();
  }

  if (cachedUid != currentUid) {
    await prefs.setString(_mobileSyncCacheOwnerUidKey, currentUid);
  }
}

Future<void> initializeMobileOfflineSync() async {
  if (kIsWeb || _mobileSyncBootstrapInitialized) {
    return;
  }
  _mobileSyncBootstrapInitialized = true;
  _startMobileConnectivityCoordinator();

  // Firebase Auth is restored during app startup before this function is
  // called. Keep this first event for callers that initialize sync directly
  // in tests or from another entrypoint.
  try {
    await FirebaseAuth.instance.authStateChanges().first.timeout(
      const Duration(seconds: 8),
    );
  } on TimeoutException {
    // The startup shell remains usable with the local cache. Auth listeners
    // continue below and will begin synchronization once Firebase emits a
    // session event.
  }

  if (FirebaseAuth.instance.currentUser != null) {
    // Sync runs in the background so an unavailable network cannot keep the
    // application on its startup loader.
    _scheduleMobileSyncPass();
  }

  FirebaseAuth.instance.authStateChanges().listen((user) async {
    if (user != null) {
      _scheduleMobileSyncPass();
    }
  });
}

void _startMobileConnectivityCoordinator() {
  if (kIsWeb || _mobileConnectivitySubscription != null) return;
  _mobileConnectivitySubscription = Connectivity().onConnectivityChanged.listen(
    (results) {
      if (_hasNetwork(results) && FirebaseAuth.instance.currentUser != null) {
        _mobileSyncRetryAttempt = 0;
        _scheduleMobileSyncPass();
      }
    },
  );
}

void _scheduleMobileSyncPass() {
  if (kIsWeb || _mobileSyncPassRunning) return;
  unawaited(
    _runScheduledMobileSyncPass().timeout(_mobileSyncStartupTimeout).catchError(
      (error) {
        debugPrint('Mobile sync pass could not finish: $error');
      },
    ),
  );
}

Future<void> _runScheduledMobileSyncPass() async {
  if (_mobileSyncPassRunning) return;
  _mobileSyncPassRunning = true;
  try {
    final results = await syncMobileOfflineDataAfterLogin();
    final failedModules = results.where((result) => !result.succeeded).toList();
    if (failedModules.isNotEmpty) {
      debugPrint(
        'Mobile sync will retry: ${failedModules.map((item) => item.module).join(', ')}',
      );
      _scheduleBoundedRetry();
      return;
    }

    // Make a small number of post-reconnect reconciliation attempts. This is
    // intentionally bounded; background retries never block local care work.
    if (_mobileSyncRetryAttempt < 2) _scheduleBoundedRetry();
  } catch (_) {
    _scheduleBoundedRetry();
    rethrow;
  } finally {
    _mobileSyncPassRunning = false;
  }
}

void _scheduleBoundedRetry() {
  _mobileSyncRetryTimer?.cancel();
  final delay = _retryDelayFor(_mobileSyncRetryAttempt);
  _mobileSyncRetryAttempt++;
  _mobileSyncRetryTimer = Timer(delay, () async {
    final network = await Connectivity().checkConnectivity();
    if (_hasNetwork(network) && FirebaseAuth.instance.currentUser != null) {
      _scheduleMobileSyncPass();
    }
  });
}

Future<List<MobileSyncStepResult>> syncMobileOfflineDataAfterLogin() async {
  if (kIsWeb) {
    return const <MobileSyncStepResult>[];
  }

  final user = FirebaseAuth.instance.currentUser;
  if (user == null) {
    return const <MobileSyncStepResult>[];
  }

  await _ensureCurrentUserOwnsMobileCache(user);

  _startAllMobileSyncListeners();

  final results = await runMobileSyncOperations({
    'check-ups': () => _syncAndVerifyOutbox(
      module: 'check-ups',
      sync: DatabaseHelper.instance.syncNow,
      database: DatabaseHelper.instance.database,
      table: 'checkup_records',
    ),
    'prenatal': () => _syncAndVerifyOutbox(
      module: 'prenatal',
      sync: PrenatalDatabaseHelper.instance.syncNow,
      database: PrenatalDatabaseHelper.instance.database,
      table: 'prenatal_records',
    ),
    'immunization': () => _syncAndVerifyOutbox(
      module: 'immunization',
      sync: ImmunizationDatabaseHelper.instance.syncNow,
      database: ImmunizationDatabaseHelper.instance.database,
      table: 'immunization_records',
    ),
    'patients': () => _syncAndVerifyOutbox(
      module: 'patients',
      sync: PatientDatabaseHelper.instance.syncNow,
      database: PatientDatabaseHelper.instance.database,
      table: 'patient_records',
    ),
    'mortality': () => _syncAndVerifyOutbox(
      module: 'mortality',
      sync: MortalityDatabaseHelper.instance.syncNow,
      database: MortalityDatabaseHelper.instance.database,
      table: 'mortality_records',
    ),
    'morbidity': () => _syncAndVerifyOutbox(
      module: 'morbidity',
      sync: MorbidityDatabaseHelper.instance.syncNow,
      database: MorbidityDatabaseHelper.instance.database,
      table: 'morbidity_records',
    ),
  });
  for (final result in results.where((result) => !result.succeeded)) {
    // Do not suppress a partial synchronization. The local cache remains
    // intact and the connectivity listener will retry this module later.
    debugPrint('Mobile sync failed for ${result.module}: ${result.error}');
  }
  return results;
}
