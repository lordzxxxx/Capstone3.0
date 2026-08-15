import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mycapstone_project/app/features/checkups/checkup_database_helper.dart';
import 'package:mycapstone_project/app/features/immunization/immunization_database_helper.dart';
import 'package:mycapstone_project/app/features/surveillance/morbidity/morbidity_database_helper.dart';
import 'package:mycapstone_project/app/features/surveillance/mortality/mortality_database_helper.dart';
import 'package:mycapstone_project/app/features/patients/patient_database_helper.dart';
import 'package:mycapstone_project/app/features/prenatal/prenatal_database_helper.dart';

bool _mobileSyncBootstrapInitialized = false;
const String _mobileSyncCacheOwnerUidKey = 'mobile_sync_cache_owner_uid';

void _startAllMobileSyncListeners() {
  DatabaseHelper.instance.startConnectivityListener();
  PrenatalDatabaseHelper.instance.startConnectivityListener();
  ImmunizationDatabaseHelper.instance.startConnectivityListener();
  PatientDatabaseHelper.instance.startConnectivityListener();
  MortalityDatabaseHelper.instance.startConnectivityListener();
  MorbidityDatabaseHelper.instance.startConnectivityListener();
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

  // Firebase Auth is restored during app startup before this function is
  // called. Keep this first event for callers that initialize sync directly
  // in tests or from another entrypoint.
  await FirebaseAuth.instance.authStateChanges().first;

  if (FirebaseAuth.instance.currentUser != null) {
    await syncMobileOfflineDataAfterLogin();
  }

  FirebaseAuth.instance.authStateChanges().listen((user) async {
    if (user != null) {
      await syncMobileOfflineDataAfterLogin();
    }
  });
}

Future<void> syncMobileOfflineDataAfterLogin() async {
  if (kIsWeb) {
    return;
  }

  final user = FirebaseAuth.instance.currentUser;
  if (user == null) {
    return;
  }

  await _ensureCurrentUserOwnsMobileCache(user);

  _startAllMobileSyncListeners();

  await DatabaseHelper.instance.syncNow();
  await PrenatalDatabaseHelper.instance.syncNow();
  await ImmunizationDatabaseHelper.instance.syncNow();
  await PatientDatabaseHelper.instance.syncNow();
  await MortalityDatabaseHelper.instance.syncNow();
  await MorbidityDatabaseHelper.instance.syncNow();
}
