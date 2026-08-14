import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:mycapstone_project/firebase_helper.dart';
import 'package:mycapstone_project/shared/barangay_scope_utils.dart';
import 'package:mycapstone_project/web/shared/services/user_access_scope_service.dart';
import 'package:mycapstone_project/app/core/services/mobile_sync_utils.dart';

class MorbidityDatabaseHelper {
  static final MorbidityDatabaseHelper instance =
      MorbidityDatabaseHelper._init();
  static Database? _database;
  bool _connectivityListenerStarted = false;
  bool _isConnectivitySyncRunning = false;

  MorbidityDatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('morbidity_records.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(path, version: 1, onCreate: _createDB);
  }

  Future _createDB(Database db, int version) async {
    const idType = 'TEXT PRIMARY KEY';
    const textType = 'TEXT NOT NULL';
    const intType = 'INTEGER NOT NULL';

    await db.execute('''
      CREATE TABLE morbidity_records (
        id $idType,
        patientName $textType,
        patientId $textType,
        age $textType,
        gender $textType,
        disease $textType,
        severity $textType,
        status $textType,
        healthFacility $textType,
        reportedBy $textType,
        treatment $textType,
        dateReported $textType,
        time $textType,
        date $textType,
        synced $intType
      )
    ''');
  }

  // Insert record locally
  Future<String> insertRecord(Map<String, dynamic> record) async {
    final id = record['id'] ?? DateTime.now().millisecondsSinceEpoch.toString();

    // On web, save directly to Firebase
    if (kIsWeb) {
      try {
        final recordWithId = {
          'id': id,
          'patientName': record['patientName'] ?? '',
          'patientId': record['patientId'] ?? '',
          'age': record['age'] ?? '',
          'gender': record['gender'] ?? '',
          'disease': record['disease'] ?? '',
          'severity': record['severity'] ?? '',
          'status': record['status'] ?? '',
          'healthFacility': record['healthFacility'] ?? '',
          'reportedBy': record['reportedBy'] ?? '',
          'treatment': record['treatment'] ?? '',
          'dateReported':
              record['dateReported'] ?? DateTime.now().toIso8601String(),
          'time': record['time'] ?? DateTime.now().toIso8601String(),
          'date': record['date'] ?? DateTime.now().toIso8601String(),
        };
        await getFirestoreInstance()
            .collection('morbidity_records')
            .doc(id)
            .set(recordWithId);
        return id;
      } catch (e) {
        print('Error saving to Firebase on web: $e');
        rethrow;
      }
    }

    // On mobile, check connectivity first
    final connectivityResult = await Connectivity().checkConnectivity();
    final hasInternet = !connectivityResult.contains(ConnectivityResult.none);

    final db = await database;
    final recordWithId = {
      'id': id,
      'patientName': record['patientName'] ?? '',
      'patientId': record['patientId'] ?? '',
      'age': record['age'] ?? '',
      'gender': record['gender'] ?? '',
      'disease': record['disease'] ?? '',
      'severity': record['severity'] ?? '',
      'status': record['status'] ?? '',
      'healthFacility': record['healthFacility'] ?? '',
      'reportedBy': record['reportedBy'] ?? '',
      'treatment': record['treatment'] ?? '',
      'dateReported':
          record['dateReported'] ?? DateTime.now().toIso8601String(),
      'time': record['time'] ?? DateTime.now().toIso8601String(),
      'date': record['date'] ?? DateTime.now().toIso8601String(),
      'synced': 0,
    };

    // Save to local database first
    await db.insert(
      'morbidity_records',
      recordWithId,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    // If online, immediately save to Firestore
    if (hasInternet) {
      try {
        final firestoreData = Map<String, dynamic>.from(recordWithId);
        firestoreData.remove('synced');

        await getFirestoreInstance()
            .collection('morbidity_records')
            .doc(id)
            .set(firestoreData);

        await db.update(
          'morbidity_records',
          {'synced': 1},
          where: 'id = ?',
          whereArgs: [id],
        );

        print('✅ Morbidity record $id saved to Firestore immediately');
      } catch (e) {
        print('⚠️ Failed to save to Firestore, will retry later: $e');
        await db.update(
          'morbidity_records',
          {'synced': 0},
          where: 'id = ?',
          whereArgs: [id],
        );
      }
    }

    return id;
  }

  // Get all records from local database
  Future<List<Map<String, dynamic>>> getAllRecords() async {
    final db = await database;
    return await db.query('morbidity_records', orderBy: 'dateReported DESC');
  }

  // Get records by disease
  Future<List<Map<String, dynamic>>> getRecordsByDisease(String disease) async {
    final db = await database;
    return await db.query(
      'morbidity_records',
      where: 'disease = ?',
      whereArgs: [disease],
      orderBy: 'dateReported DESC',
    );
  }

  // Get active records
  Future<List<Map<String, dynamic>>> getActiveRecords() async {
    final db = await database;
    return await db.query(
      'morbidity_records',
      where: 'status = ?',
      whereArgs: ['Active'],
      orderBy: 'dateReported DESC',
    );
  }

  // Get records by date range
  Future<List<Map<String, dynamic>>> getRecordsByDateRange(
    DateTime start,
    DateTime end,
  ) async {
    final db = await database;
    return await db.query(
      'morbidity_records',
      where: 'dateReported >= ? AND dateReported <= ?',
      whereArgs: [start.toIso8601String(), end.toIso8601String()],
      orderBy: 'dateReported DESC',
    );
  }

  // Calculate disease statistics
  Future<Map<String, dynamic>> calculateDiseaseStats() async {
    final records = await getAllRecords();
    final diseaseMap = <String, int>{};
    int activeCount = 0;
    int recoveredCount = 0;

    for (final record in records) {
      final disease = record['disease'] as String;
      diseaseMap[disease] = (diseaseMap[disease] ?? 0) + 1;

      if (record['status'] == 'Active') {
        activeCount++;
      } else if (record['status'] == 'Recovered') {
        recoveredCount++;
      }
    }

    return {
      'totalRecords': records.length,
      'diseaseStats': diseaseMap,
      'activePatients': activeCount,
      'recoveredPatients': recoveredCount,
      'recoveryRate': records.isEmpty
          ? 0.0
          : (recoveredCount / records.length * 100).toStringAsFixed(1),
    };
  }

  // Get monthly trend data
  Future<List<Map<String, dynamic>>> getMonthlyTrends() async {
    final records = await getAllRecords();
    final monthlyData = <String, int>{};

    final now = DateTime.now();
    for (int i = 5; i >= 0; i--) {
      final date = DateTime(now.year, now.month - i, 1);
      final monthKey = [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ][date.month - 1];
      monthlyData[monthKey] = 0;
    }

    for (final record in records) {
      try {
        final recordDate = DateTime.parse(record['dateReported'] as String);
        final monthKey = [
          'Jan',
          'Feb',
          'Mar',
          'Apr',
          'May',
          'Jun',
          'Jul',
          'Aug',
          'Sep',
          'Oct',
          'Nov',
          'Dec',
        ][recordDate.month - 1];

        if (monthlyData.containsKey(monthKey)) {
          monthlyData[monthKey] = (monthlyData[monthKey] ?? 0) + 1;
        }
      } catch (e) {
        print('Error parsing date: $e');
      }
    }

    return monthlyData.entries
        .map((e) => {'month': e.key, 'count': e.value})
        .toList();
  }

  // Sync all unsynced records from local to Firebase
  Future<void> _syncToFirebase() async {
    if (kIsWeb) return;

    try {
      final connectivityResult = await Connectivity().checkConnectivity();
      final hasInternet = !connectivityResult.contains(ConnectivityResult.none);

      if (!hasInternet) {
        print('No internet connection. Will sync morbidity records later.');
        return;
      }

      final db = await database;
      final unsyncedRecords = await db.query(
        'morbidity_records',
        where: 'synced = ?',
        whereArgs: [0],
      );

      for (final record in unsyncedRecords) {
        try {
          final recordData = Map<String, dynamic>.from(record);
          final id = recordData['id'] as String;
          recordData.remove('synced');
          recordData.remove('id');

          await getFirestoreInstance()
              .collection('morbidity_records')
              .doc(id)
              .set(recordData, SetOptions(merge: true));

          await db.update(
            'morbidity_records',
            {'synced': 1},
            where: 'id = ?',
            whereArgs: [id],
          );

          print('Synced morbidity record: $id');
        } catch (e) {
          print('Error syncing morbidity record ${record['id']}: $e');
        }
      }
    } catch (e) {
      print('Error during morbidity sync: $e');
    }
  }

  Future<void> syncFromFirebase() async {
    if (kIsWeb) return; // Web syncs in real-time

    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        print('No authenticated user. Skipping morbidity Firebase sync.');
        return;
      }

      final accessScope = await UserAccessScopeService.instance
          .loadCurrentScope();
      if (!accessScope.isAuthenticated) {
        print(
          'No authenticated access scope. Skipping morbidity Firebase sync.',
        );
        return;
      }
      if (!accessScope.canViewAllBarangays &&
          accessScope.barangayCode.trim().isEmpty &&
          accessScope.barangay.trim().isEmpty) {
        print('No barangay scope loaded. Skipping morbidity Firebase sync.');
        return;
      }

      final connectivityResult = await Connectivity().checkConnectivity();
      final hasInternet = !connectivityResult.contains(ConnectivityResult.none);

      if (!hasInternet) {
        print('⚠️ No internet connection, skipping sync');
        return;
      }

      print('🔄 Starting sync from Firebase...');

      final snapshot = await buildScopedRecordQuery(
        getFirestoreInstance(),
        'morbidity_records',
        accessScope,
      ).get();

      final records = snapshot.docs
          .map(materializeFirestoreRecord)
          .where((record) => recordMatchesAccessScope(record, accessScope))
          .toList(growable: false);

      final db = await database;
      final tableColumns = (await db.rawQuery(
        'PRAGMA table_info(morbidity_records)',
      ))
          .map((row) => row['name']?.toString())
          .whereType<String>()
          .toSet();

      for (final record in records) {
        final data = Map<String, dynamic>.from(record);
        data.remove('_firestorePath');
        final recordId = (data['id'] ?? '').toString().trim();
        if (recordId.isEmpty ||
            await hasPendingLocalSync(
              db,
              table: 'morbidity_records',
              id: recordId,
            )) {
          continue;
        }
        data['synced'] = 1;

        // Ensure all NOT NULL fields have default values
        data['patientName'] = data['patientName'] ?? '';
        data['patientId'] = data['patientId'] ?? '';
        data['age'] = data['age'] ?? '';
        data['gender'] = data['gender'] ?? '';
        data['disease'] = data['disease'] ?? '';
        data['severity'] = data['severity'] ?? '';
        data['status'] = data['status'] ?? '';
        data['healthFacility'] = data['healthFacility'] ?? '';
        data['reportedBy'] = data['reportedBy'] ?? '';
        data['treatment'] = data['treatment'] ?? '';
        data['dateReported'] =
            data['dateReported'] ?? DateTime.now().toIso8601String();
        data['time'] = data['time'] ?? DateTime.now().toIso8601String();
        data['date'] = data['date'] ?? DateTime.now().toIso8601String();

        final sqliteData = sanitizeRecordForSqlite(data)
          ..removeWhere((key, _) => !tableColumns.contains(key));
        if (!sqliteData.containsKey('id')) continue;

        await db.insert(
          'morbidity_records',
          sqliteData,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      print('✅ Sync completed successfully (${records.length} records)');
    } catch (e) {
      print('❌ Error syncing from Firebase: $e');
    }
  }

  Future<void> _runConnectivitySync() async {
    if (kIsWeb || _isConnectivitySyncRunning) return;

    _isConnectivitySyncRunning = true;
    try {
      await _syncToFirebase();
      await syncFromFirebase();
    } finally {
      _isConnectivitySyncRunning = false;
    }
  }

  Future<void> syncNow() async {
    await _runConnectivitySync();
  }

  Future<void> clearLocalCache() async {
    if (kIsWeb) return;

    final db = await database;
    await db.delete('morbidity_records');
  }

  // Start connectivity listener
  void startConnectivityListener() {
    if (kIsWeb || _connectivityListenerStarted) return;

    _connectivityListenerStarted = true;
    _runConnectivitySync();

    Connectivity().onConnectivityChanged.listen((result) async {
      if (!result.contains(ConnectivityResult.none)) {
        print('📡 Connection detected, attempting sync...');
        await _runConnectivitySync();
      }
    });
  }

  // Update record
  Future<void> updateRecord(Map<String, dynamic> record) async {
    final id = record['id'];

    // On web, update Firebase directly
    if (kIsWeb) {
      try {
        final updateData = Map<String, dynamic>.from(record);
        updateData.remove('synced');
        await getFirestoreInstance()
            .collection('morbidity_records')
            .doc(id)
            .update(updateData);
        return;
      } catch (e) {
        print('Error updating on Firebase: $e');
        rethrow;
      }
    }

    // On mobile, update locally and sync
    final db = await database;
    final connectivityResult = await Connectivity().checkConnectivity();
    final hasInternet = !connectivityResult.contains(ConnectivityResult.none);

    record['synced'] = 0;

    await db.update(
      'morbidity_records',
      record,
      where: 'id = ?',
      whereArgs: [id],
    );

    if (hasInternet) {
      try {
        final updateData = Map<String, dynamic>.from(record);
        updateData.remove('synced');
        await getFirestoreInstance()
            .collection('morbidity_records')
            .doc(id)
            .update(updateData);

        await db.update(
          'morbidity_records',
          {'synced': 1},
          where: 'id = ?',
          whereArgs: [id],
        );
      } catch (e) {
        print('⚠️ Failed to update on Firestore: $e');
      }
    }
  }

  // Delete record
  Future<void> deleteRecord(String id) async {
    // On web, delete from Firebase directly
    if (kIsWeb) {
      try {
        await getFirestoreInstance()
            .collection('morbidity_records')
            .doc(id)
            .delete();
        return;
      } catch (e) {
        print('Error deleting from Firebase: $e');
        rethrow;
      }
    }

    // On mobile, delete locally and sync
    final db = await database;
    await db.delete('morbidity_records', where: 'id = ?', whereArgs: [id]);

    final connectivityResult = await Connectivity().checkConnectivity();
    final hasInternet = !connectivityResult.contains(ConnectivityResult.none);

    if (hasInternet) {
      try {
        await getFirestoreInstance()
            .collection('morbidity_records')
            .doc(id)
            .delete();
      } catch (e) {
        print('⚠️ Failed to delete from Firestore: $e');
      }
    }
  }

  // Seed 100 sample morbidity records
  Future<void> seedData() async {
    final diseases = [
      'Malaria',
      'Typhoid',
      'Dengue',
      'COVID-19',
      'Cholera',
      'Influenza',
      'Measles',
      'Pneumonia',
    ];
    final severities = ['Mild', 'Moderate', 'Severe', 'Critical'];
    final statuses = ['Active', 'Recovered', 'Deceased', 'Under Treatment'];
    final genders = ['Male', 'Female'];
    final facilities = [
      'Central Hospital',
      'District Clinic',
      'Health Center',
      'Primary Care',
      'Medical Center',
    ];

    for (int i = 1; i <= 100; i++) {
      final daysAgo = (i % 30);
      final recordDate = DateTime.now().subtract(Duration(days: daysAgo));

      final record = {
        'id': 'morbidity_$i',
        'patientName': 'Patient $i',
        'patientId': 'P${1000 + i}',
        'age': ((18 + (i % 70)).toString()),
        'gender': genders[i % genders.length],
        'disease': diseases[i % diseases.length],
        'severity': severities[i % severities.length],
        'status': statuses[i % statuses.length],
        'healthFacility': facilities[i % facilities.length],
        'reportedBy': 'Dr. Smith ${i % 5 + 1}',
        'treatment': 'Treatment ${i % 5 + 1}',
        'dateReported': recordDate.toIso8601String(),
        'time': recordDate.toIso8601String(),
        'date': recordDate.toIso8601String(),
      };

      await insertRecord(record);
    }

    print('✅ Successfully seeded 100 morbidity records');
  }
}
