import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:mycapstone_project/firebase_helper.dart';
import 'package:mycapstone_project/shared/barangay_scope_utils.dart';
import 'package:mycapstone_project/web/shared/services/user_access_scope_service.dart';

class MortalityDatabaseHelper {
  static final MortalityDatabaseHelper instance =
      MortalityDatabaseHelper._init();
  static Database? _database;
  bool _connectivityListenerStarted = false;
  bool _isConnectivitySyncRunning = false;

  MortalityDatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('mortality_records.db');
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
      CREATE TABLE mortality_records (
        id $idType,
        name $textType,
        date $textType,
        month $textType,
        age $textType,
        ageRange $textType,
        gender $textType,
        causeOfDeath $textType,
        place $textType,
        reportedBy $textType,
        verification $textType,
        dateReported $textType,
        synced $intType
      )
    ''');
  }

  dynamic _toSqliteValue(dynamic value) {
    if (value == null || value is num || value is String) {
      return value;
    }

    if (value is bool) {
      return value ? 1 : 0;
    }

    if (value is Timestamp) {
      return value.toDate().toIso8601String();
    }

    if (value is DateTime) {
      return value.toIso8601String();
    }

    if (value is List) {
      return jsonEncode(value.map(_toSqliteValue).toList(growable: false));
    }

    if (value is Map) {
      final normalized = <String, dynamic>{};
      value.forEach((key, nestedValue) {
        normalized[key.toString()] = _toSqliteValue(nestedValue);
      });
      return jsonEncode(normalized);
    }

    return value.toString();
  }

  Map<String, dynamic> _sanitizeRecordForSqlite(Map<String, dynamic> source) {
    final sanitized = <String, dynamic>{};
    source.forEach((key, value) {
      sanitized[key] = _toSqliteValue(value);
    });
    return sanitized;
  }

  Future<Set<String>> _getTableColumns(Database db, String tableName) async {
    final rows = await db.rawQuery('PRAGMA table_info($tableName)');
    return rows
        .map((row) => (row['name'] ?? '').toString())
        .where((name) => name.isNotEmpty)
        .toSet();
  }

  Map<String, dynamic> _filterToKnownColumns(
    Map<String, dynamic> source,
    Set<String> knownColumns,
  ) {
    final filtered = <String, dynamic>{};
    source.forEach((key, value) {
      if (knownColumns.contains(key)) {
        filtered[key] = value;
      }
    });
    return filtered;
  }

  // Insert record locally
  Future<String> insertRecord(Map<String, dynamic> record) async {
    final id = record['id'] ?? DateTime.now().millisecondsSinceEpoch.toString();

    // On web, save directly to Firebase
    if (kIsWeb) {
      try {
        final recordWithId = {
          'id': id,
          'name': record['name'] ?? '',
          'date': record['date'] ?? '',
          'month': record['month'] ?? '',
          'age': record['age'] ?? '',
          'ageRange': record['ageRange'] ?? '',
          'gender': record['gender'] ?? '',
          'causeOfDeath': record['causeOfDeath'] ?? '',
          'place': record['place'] ?? '',
          'reportedBy': record['reportedBy'] ?? '',
          'verification': record['verification'] ?? 'Pending',
          'dateReported':
              record['dateReported'] ?? DateTime.now().toIso8601String(),
        };
        await getFirestoreInstance()
            .collection('mortality_records')
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
      'name': record['name'] ?? '',
      'date': record['date'] ?? '',
      'month': record['month'] ?? '',
      'age': record['age'] ?? '',
      'ageRange': record['ageRange'] ?? '',
      'gender': record['gender'] ?? '',
      'causeOfDeath': record['causeOfDeath'] ?? '',
      'place': record['place'] ?? '',
      'reportedBy': record['reportedBy'] ?? '',
      'verification': record['verification'] ?? 'Pending',
      'dateReported':
          record['dateReported'] ?? DateTime.now().toIso8601String(),
      'synced': 0,
    };

    // Save to local database first
    await db.insert(
      'mortality_records',
      recordWithId,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    // If online, immediately save to Firestore
    if (hasInternet) {
      try {
        final firestoreData = Map<String, dynamic>.from(recordWithId);
        firestoreData.remove('synced');

        await getFirestoreInstance()
            .collection('mortality_records')
            .doc(id)
            .set(firestoreData);

        await db.update(
          'mortality_records',
          {'synced': 1},
          where: 'id = ?',
          whereArgs: [id],
        );

        print('✅ Mortality record $id saved to Firestore immediately');
      } catch (e) {
        print('⚠️ Failed to save to Firestore, will retry later: $e');
        await db.update(
          'mortality_records',
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
    return await db.query('mortality_records', orderBy: 'dateReported DESC');
  }

  // Get records by cause of death
  Future<List<Map<String, dynamic>>> getRecordsByCause(String cause) async {
    final db = await database;
    return await db.query(
      'mortality_records',
      where: 'causeOfDeath = ?',
      whereArgs: [cause],
      orderBy: 'dateReported DESC',
    );
  }

  // Get verified records
  Future<List<Map<String, dynamic>>> getVerifiedRecords() async {
    final db = await database;
    return await db.query(
      'mortality_records',
      where: 'verification = ?',
      whereArgs: ['Verified'],
      orderBy: 'dateReported DESC',
    );
  }

  // Get pending verification records
  Future<List<Map<String, dynamic>>> getPendingRecords() async {
    final db = await database;
    return await db.query(
      'mortality_records',
      where: 'verification = ?',
      whereArgs: ['Pending'],
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
      'mortality_records',
      where: 'dateReported >= ? AND dateReported <= ?',
      whereArgs: [start.toIso8601String(), end.toIso8601String()],
      orderBy: 'dateReported DESC',
    );
  }

  // Get records by age range
  Future<List<Map<String, dynamic>>> getRecordsByAgeRange(
    String ageRange,
  ) async {
    final db = await database;
    return await db.query(
      'mortality_records',
      where: 'ageRange = ?',
      whereArgs: [ageRange],
      orderBy: 'dateReported DESC',
    );
  }

  // Calculate mortality statistics
  Future<Map<String, dynamic>> calculateMortalityStats() async {
    final records = await getAllRecords();
    final causeMap = <String, int>{};
    int verifiedCount = 0;
    int pendingCount = 0;
    int elderlyCount = 0; // 60+

    for (final record in records) {
      final cause = record['causeOfDeath'] as String;
      causeMap[cause] = (causeMap[cause] ?? 0) + 1;

      if (record['verification'] == 'Verified') {
        verifiedCount++;
      } else if (record['verification'] == 'Pending') {
        pendingCount++;
      }

      try {
        final age = int.tryParse(record['age'].toString()) ?? 0;
        if (age >= 60) {
          elderlyCount++;
        }
      } catch (e) {
        print('Error parsing age: $e');
      }
    }

    return {
      'totalDeaths': records.length,
      'causeStats': causeMap,
      'verifiedCount': verifiedCount,
      'pendingCount': pendingCount,
      'elderlyDeaths': elderlyCount,
      'verificationRate': records.isEmpty
          ? 0.0
          : (verifiedCount / records.length * 100).toStringAsFixed(1),
    };
  }

  // Get leading cause of death
  Future<String> getLeadingCause() async {
    final records = await getAllRecords();
    final causeMap = <String, int>{};

    for (final record in records) {
      final cause = record['causeOfDeath'] as String;
      causeMap[cause] = (causeMap[cause] ?? 0) + 1;
    }

    if (causeMap.isEmpty) return 'N/A';
    return causeMap.entries.reduce((a, b) => a.value > b.value ? a : b).key;
  }

  // Get monthly trend data
  Future<List<Map<String, dynamic>>> getMonthlyTrends() async {
    final records = await getAllRecords();
    final monthlyData = <String, int>{};

    final now = DateTime.now();
    for (int i = 5; i >= 0; i--) {
      final date = DateTime(now.year, now.month - i, 1);
      final monthKey =
          ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][date.month - 1];
      monthlyData[monthKey] = 0;
    }

    for (final record in records) {
      try {
        final recordDate = DateTime.parse(record['dateReported'] as String);
        final monthKey =
            ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][recordDate.month - 1];

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

  // Get cause distribution data
  Future<List<Map<String, dynamic>>> getCauseDistribution() async {
    final records = await getAllRecords();
    final causeMap = <String, int>{};

    for (final record in records) {
      final cause = record['causeOfDeath'] as String;
      causeMap[cause] = (causeMap[cause] ?? 0) + 1;
    }

    return causeMap.entries
        .map((e) => {'cause': e.key, 'count': e.value})
        .toList()
      ..sort((a, b) => (b['count'] as int).compareTo(a['count'] as int));
  }

  // Get age distribution data
  Future<List<Map<String, dynamic>>> getAgeDistribution() async {
    final records = await getAllRecords();
    final ageMap = <String, int>{};

    final ageRanges = ['0-20', '21-40', '41-60', '61-80', '81+'];
    for (var range in ageRanges) {
      ageMap[range] = 0;
    }

    for (final record in records) {
      final ageRange = record['ageRange'] as String;
      if (ageMap.containsKey(ageRange)) {
        ageMap[ageRange] = (ageMap[ageRange] ?? 0) + 1;
      }
    }

    return ageRanges
        .map((range) => {'ageRange': range, 'count': ageMap[range] ?? 0})
        .toList();
  }

  // Sync all unsynced records from local to Firebase
  Future<void> _syncToFirebase() async {
    if (kIsWeb) return;

    try {
      final connectivityResult = await Connectivity().checkConnectivity();
      final hasInternet = !connectivityResult.contains(ConnectivityResult.none);

      if (!hasInternet) {
        print('No internet connection. Will sync mortality records later.');
        return;
      }

      final db = await database;
      final unsyncedRecords = await db.query(
        'mortality_records',
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
              .collection('mortality_records')
              .doc(id)
              .set(recordData, SetOptions(merge: true));

          await db.update(
            'mortality_records',
            {'synced': 1},
            where: 'id = ?',
            whereArgs: [id],
          );

          print('Synced mortality record: $id');
        } catch (e) {
          print('Error syncing mortality record ${record['id']}: $e');
        }
      }
    } catch (e) {
      print('Error during mortality sync: $e');
    }
  }

  Future<void> syncFromFirebase() async {
    if (kIsWeb) return; // Web syncs in real-time

    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        print('No authenticated user. Skipping mortality Firebase sync.');
        return;
      }

      final accessScope = await UserAccessScopeService.instance.loadCurrentScope();
      if (!accessScope.isAuthenticated) {
        print('No authenticated access scope. Skipping mortality Firebase sync.');
        return;
      }
      if (!accessScope.canViewAllBarangays &&
          accessScope.barangayCode.trim().isEmpty &&
          accessScope.barangay.trim().isEmpty) {
        print('No barangay scope loaded. Skipping mortality Firebase sync.');
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
        'mortality_records',
        accessScope,
      ).get();

      final records = snapshot.docs
          .map(materializeFirestoreRecord)
          .where((record) => recordMatchesAccessScope(record, accessScope))
          .toList(growable: false);

      final db = await database;
      final tableColumns = await _getTableColumns(db, 'mortality_records');

      for (final record in records) {
        final data = Map<String, dynamic>.from(record);
        data.remove('_firestorePath');
        data['synced'] = 1;
        final sqliteData = _sanitizeRecordForSqlite(data);
        final insertData = _filterToKnownColumns(sqliteData, tableColumns);

        if (!insertData.containsKey('id')) {
          continue;
        }

        await db.insert(
          'mortality_records',
          insertData,
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
    await db.delete('mortality_records');
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
            .collection('mortality_records')
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
      'mortality_records',
      record,
      where: 'id = ?',
      whereArgs: [id],
    );

    if (hasInternet) {
      try {
        final updateData = Map<String, dynamic>.from(record);
        updateData.remove('synced');
        await getFirestoreInstance()
            .collection('mortality_records')
            .doc(id)
            .update(updateData);
        await db.update(
          'mortality_records',
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
            .collection('mortality_records')
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
    await db.delete('mortality_records', where: 'id = ?', whereArgs: [id]);

    final connectivityResult = await Connectivity().checkConnectivity();
    final hasInternet = !connectivityResult.contains(ConnectivityResult.none);

    if (hasInternet) {
      try {
        await getFirestoreInstance()
            .collection('mortality_records')
            .doc(id)
            .delete();
      } catch (e) {
        print('⚠️ Failed to delete from Firestore: $e');
      }
    }
  }

  // Seed 100 sample mortality records
  Future<void> seedSample100Records() async {
    final List<String> names = [
      'Maria Santos',
      'Juan Garcia',
      'Jose Martinez',
      'Rosa Rodriguez',
      'Miguel Hernandez',
      'Carmen Lopez',
      'Luis Gonzalez',
      'Ana Perez',
      'Ricardo Sanchez',
      'Elena Ramirez',
      'Francisco Torres',
      'Sofia Flores',
      'Diego Morales',
      'Gloria Castillo',
      'Manuel Romero',
      'Lucia Vargas',
      'Carlos Reyes',
      'Beatriz Ramos',
      'Antonio Cruz',
      'Francisca Soto',
      'Gabriel Medina',
      'Teresa Ortiz',
      'Fernando Navarro',
      'Catalina Herrera',
      'Sergio Jimenez',
      'Patricia Rojas',
      'Roberto Mesa',
      'Magdalena Vega',
      'Alberto Fuentes',
      'Raquel Velasco',
      'Jorge Dela Cruz',
      'Dolores Santos',
      'Pedro Garcia',
      'Margarita Martinez',
      'Andres Rodriguez',
      'Esperanza Hernandez',
      'Marcos Lopez',
      'Emilia Gonzalez',
      'Pablo Perez',
      'Constuelo Sanchez',
      'Enrique Ramirez',
      'Leticia Torres',
      'Ruben Flores',
      'Aurea Morales',
      'Hector Castillo',
      'Guillermo Romero',
      'Florencia Vargas',
      'Vicente Reyes',
      'Martina Ramos',
      'Rolando Cruz',
      'Benito Salamat',
      'Victoria Medina',
      'Ismael Ortega',
      'Alicia Navarro',
      'Rodolfo Herrera',
      'Antonia Jimenez',
      'Domingo Rojas',
      'Severina Mesa',
      'Ernesto Vega',
      'Montserrat Fuentes',
      'Olimpio Velasco',
      'Herminia Dela Cruz',
      'Maximiliano Santos',
      'Jacinta Garcia',
      'Ignacio Martinez',
      'Felipa Rodriguez',
      'Simeón Hernandez',
      'Crescencia Lopez',
      'Laureano Gonzalez',
      'Benicia Perez',
      'Agustin Sanchez',
      'Escolastica Ramirez',
      'Florentino Torres',
      'Gertrudis Flores',
      'Venancio Morales',
      'Eulogia Castillo',
      'Abundio Romero',
      'Casilda Vargas',
      'Leopoldo Reyes',
      'Simplicia Ramos',
      'Epifanio Cruz',
      'Cleofe Soto',
      'Geronimo Medina',
      'Otilia Ortiz',
      'Protasio Navarro',
    ];

    final List<String> causesOfDeath = [
      'Acute Myocardial Infarction',
      'Stroke',
      'Pneumonia',
      'Sepsis',
      'Respiratory Failure',
      'Diabetes Complications',
      'Cancer',
      'Severe Malaria',
      'Tuberculosis',
      'Hemorrhage',
      'Traffic Accident',
      'Cardiac Arrest',
      'Kidney Failure',
      'Liver Cirrhosis',
      'Suicide',
      'Homicide',
      'Asphyxia',
      'Acute Gastroenteritis',
      'Influenza',
      'COVID-19',
      'Dengue Hemorrhagic Fever',
      'Meningitis',
      'Aneurysm',
      'Acute Pancreatitis',
      'COPD Exacerbation',
    ];

    final List<String> places = [
      'Hospital',
      'Home',
      'Road/Accident Scene',
      'Emergency Room',
      'ICU',
      'Community Health Center',
      'Private Clinic',
      'Barangay Health Station',
      'On Transit',
      'Other',
    ];

    final List<String> verificationStatuses = [
      'Pending',
      'Verified',
      'Under Review',
      'Incomplete',
      'Approved',
    ];

    final List<String> ageRanges = [
      '0-4',
      '5-9',
      '10-14',
      '15-19',
      '20-24',
      '25-29',
      '30-34',
      '35-39',
      '40-44',
      '45-49',
      '50-54',
      '55-59',
      '60-64',
      '65-69',
      '70-74',
      '75-79',
      '80+',
    ];

    final List<String> genders = ['Male', 'Female'];

    final List<String> months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];

    final List<String> reporters = [
      'Dr. Santos',
      'Dr. Garcia',
      'Nurse Maria',
      'Health Officer Lopez',
      'Barangay Captain',
      'Dr. Martinez',
      'Health Worker Rodriguez',
      'Dr. Hernandez',
      'Midwife Carmen',
      'Dr. Torres',
    ];

    try {
      final List<Map<String, dynamic>> samples = [];

      // Generate 100 sample records
      for (int i = 0; i < 100; i++) {
        final age = (20 + (i % 80)).toString();
        final id = 'mortality_${DateTime.now().millisecondsSinceEpoch}_$i';

        // Mix past dates over the last 12 months
        final daysAgo = i % 365;
        final dateReported = DateTime.now().subtract(Duration(days: daysAgo));

        samples.add({
          'id': id,
          'name': names[i % names.length],
          'date': dateReported.toIso8601String(),
          'month': months[dateReported.month - 1],
          'age': age,
          'ageRange':
              ageRanges[(int.parse(age) ~/ 5).clamp(0, ageRanges.length - 1)],
          'gender': genders[i % 2],
          'causeOfDeath': causesOfDeath[i % causesOfDeath.length],
          'place': places[i % places.length],
          'reportedBy': reporters[i % reporters.length],
          'verification': verificationStatuses[i % verificationStatuses.length],
          'dateReported': dateReported.toIso8601String(),
          'synced': 1,
        });
      }

      // Insert all samples
      final db = await database;
      int inserted = 0;

      for (var sample in samples) {
        try {
          await db.insert(
            'mortality_records',
            sample,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          inserted++;
        } catch (e) {
          print('Error inserting sample mortality record ${sample['id']}: $e');
        }
      }

      print('✅ Successfully seeded $inserted sample mortality records');

      // Sync to Firestore if online
      final connectivityResult = await Connectivity().checkConnectivity();
      if (!connectivityResult.contains(ConnectivityResult.none)) {
        try {
          final firestore = getFirestoreInstance();
          for (var sample in samples) {
            final firestoreData = Map<String, dynamic>.from(sample);
            firestoreData.remove('synced');
            await firestore
                .collection('mortality_records')
                .doc(sample['id'])
                .set(firestoreData);
          }
          print('✅ Synced $inserted sample mortality records to Firestore');
        } catch (e) {
          print('⚠️ Could not sync to Firestore: $e');
        }
      }
    } catch (e) {
      print('❌ Error seeding mortality data: $e');
      rethrow;
    }
  }
}
