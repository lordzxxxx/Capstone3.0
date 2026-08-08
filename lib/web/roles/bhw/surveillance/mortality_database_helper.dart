import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:mycapstone_project/firebase_helper.dart';
import 'package:mycapstone_project/shared/barangay_scope_utils.dart';
import 'package:mycapstone_project/web/shared/services/user_access_scope_service.dart';

class MortalityDatabaseHelper {
  static final MortalityDatabaseHelper instance =
      MortalityDatabaseHelper._init();
  static Database? _database;
  static const int _dbVersion = 2;
  static const String _collectionName = 'mortality_records';

  MortalityDatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('mortality_records.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: _dbVersion,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
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
        patientId $textType,
        causeCategory $textType,
        causeOfDeath $textType,
        reason $textType,
        explanation $textType,
        dateTimeOfDeath $textType,
        timeOfDeath $textType,
        purok $textType,
        place $textType,
        reportedBy $textType,
        verification $textType,
        dateReported $textType,
        synced $intType
      )
    ''');
  }

  Future<void> _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute(
        "ALTER TABLE mortality_records ADD COLUMN patientId TEXT NOT NULL DEFAULT ''",
      );
      await db.execute(
        "ALTER TABLE mortality_records ADD COLUMN causeCategory TEXT NOT NULL DEFAULT ''",
      );
      await db.execute(
        "ALTER TABLE mortality_records ADD COLUMN reason TEXT NOT NULL DEFAULT ''",
      );
      await db.execute(
        "ALTER TABLE mortality_records ADD COLUMN explanation TEXT NOT NULL DEFAULT ''",
      );
      await db.execute(
        "ALTER TABLE mortality_records ADD COLUMN dateTimeOfDeath TEXT NOT NULL DEFAULT ''",
      );
      await db.execute(
        "ALTER TABLE mortality_records ADD COLUMN timeOfDeath TEXT NOT NULL DEFAULT ''",
      );
      await db.execute(
        "ALTER TABLE mortality_records ADD COLUMN purok TEXT NOT NULL DEFAULT ''",
      );
    }
  }

  // Insert record locally
  Future<String> insertRecord(Map<String, dynamic> record) async {
    final id = record['id'] ?? DateTime.now().millisecondsSinceEpoch.toString();

    // On web, save directly to Firebase
    if (kIsWeb) {
      try {
        final accessScope = await UserAccessScopeService.instance
            .loadCurrentScope();
        final recordWithId = {
          'id': id,
          'name': record['name'] ?? '',
          'patientId': record['patientId'] ?? '',
          'linkedPatientId':
              record['linkedPatientId'] ?? record['patientId'] ?? '',
          'date': record['date'] ?? '',
          'dateTimeOfDeath': record['dateTimeOfDeath'] ?? '',
          'timeOfDeath': record['timeOfDeath'] ?? '',
          'month': record['month'] ?? '',
          'age': record['age'] ?? '',
          'ageRange': record['ageRange'] ?? '',
          'gender': record['gender'] ?? '',
          'causeCategory': record['causeCategory'] ?? '',
          'causeOfDeath': record['causeOfDeath'] ?? '',
          'reason': record['reason'] ?? '',
          'explanation': record['explanation'] ?? '',
          'purok': record['purok'] ?? '',
          'place': record['place'] ?? '',
          'reportedBy': record['reportedBy'] ?? '',
          'verification': record['verification'] ?? 'Pending',
          'dateReported':
              record['dateReported'] ?? DateTime.now().toIso8601String(),
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        };
        final scopedRecord = applyBarangayScopeToRecord(
          recordWithId,
          accessScope: accessScope,
        );
        final documentRef = await resolveScopedRecordDocumentReference(
          getFirestoreInstance(),
          _collectionName,
          id,
          accessScope: accessScope,
          record: scopedRecord,
        );
        await documentRef.set(scopedRecord);
        await syncMortalityToPatientHistory(scopedRecord);
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
      'patientId': record['patientId'] ?? '',
      'date': record['date'] ?? '',
      'dateTimeOfDeath': record['dateTimeOfDeath'] ?? '',
      'timeOfDeath': record['timeOfDeath'] ?? '',
      'month': record['month'] ?? '',
      'age': record['age'] ?? '',
      'ageRange': record['ageRange'] ?? '',
      'gender': record['gender'] ?? '',
      'causeCategory': record['causeCategory'] ?? '',
      'causeOfDeath': record['causeOfDeath'] ?? '',
      'reason': record['reason'] ?? '',
      'explanation': record['explanation'] ?? '',
      'purok': record['purok'] ?? '',
      'place': record['place'] ?? '',
      'reportedBy': record['reportedBy'] ?? '',
      'verification': record['verification'] ?? 'Pending',
      'dateReported':
          record['dateReported'] ?? DateTime.now().toIso8601String(),
      'synced': hasInternet ? 1 : 0,
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
        await syncMortalityToPatientHistory(firestoreData);

        print('✅ Mortality record $id saved to Firestore immediately');
      } catch (e) {
        print('⚠️ Failed to save to Firestore, will retry later: $e');
      }
    }

    return id;
  }

  // Get all records from Firestore (for web) or local database (for mobile)
  Future<List<Map<String, dynamic>>> getAllRecords() async {
    if (kIsWeb) {
      try {
        final accessScope = await UserAccessScopeService.instance
            .loadCurrentScope();
        final query = buildScopedRecordQuery(
          getFirestoreInstance(),
          _collectionName,
          accessScope,
        );
        final snapshot = await query.get();
        final scopedDocs = snapshot.docs
            .map(materializeFirestoreRecord)
            .where((record) => recordMatchesAccessScope(record, accessScope));
        return sortRecordsByActivityDateDescending(scopedDocs);
      } catch (e) {
        print('Error fetching from Firebase: $e');
        return [];
      }
    }

    // Mobile: query local database
    final db = await database;
    return await db.query('mortality_records', orderBy: 'dateReported DESC');
  }

  // Get records by cause of death
  Future<List<Map<String, dynamic>>> getRecordsByCause(String cause) async {
    if (kIsWeb) {
      try {
        final accessScope = await UserAccessScopeService.instance
            .loadCurrentScope();
        final query = buildScopedRecordQuery(
          getFirestoreInstance(),
          _collectionName,
          accessScope,
        ).where('causeOfDeath', isEqualTo: cause);
        final snapshot = await query.get();
        final scopedDocs = snapshot.docs
            .map(materializeFirestoreRecord)
            .where((record) => recordMatchesAccessScope(record, accessScope));
        return sortRecordsByActivityDateDescending(scopedDocs);
      } catch (e) {
        print('Error fetching from Firebase: $e');
        return [];
      }
    }

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
    if (kIsWeb) {
      try {
        final accessScope = await UserAccessScopeService.instance
            .loadCurrentScope();
        final query = buildScopedRecordQuery(
          getFirestoreInstance(),
          _collectionName,
          accessScope,
        ).where('verification', isEqualTo: 'Verified');
        final snapshot = await query.get();
        final scopedDocs = snapshot.docs
            .map(materializeFirestoreRecord)
            .where((record) => recordMatchesAccessScope(record, accessScope));
        return sortRecordsByActivityDateDescending(scopedDocs);
      } catch (e) {
        print('Error fetching from Firebase: $e');
        return [];
      }
    }

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
    if (kIsWeb) {
      try {
        final accessScope = await UserAccessScopeService.instance
            .loadCurrentScope();
        final query = buildScopedRecordQuery(
          getFirestoreInstance(),
          _collectionName,
          accessScope,
        ).where('verification', isEqualTo: 'Pending');
        final snapshot = await query.get();
        final scopedDocs = snapshot.docs
            .map(materializeFirestoreRecord)
            .where((record) => recordMatchesAccessScope(record, accessScope));
        return sortRecordsByActivityDateDescending(scopedDocs);
      } catch (e) {
        print('Error fetching from Firebase: $e');
        return [];
      }
    }

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
    if (kIsWeb) {
      try {
        final accessScope = await UserAccessScopeService.instance
            .loadCurrentScope();
        final query =
            buildScopedRecordQuery(
                  getFirestoreInstance(),
                  _collectionName,
                  accessScope,
                )
                .where(
                  'dateReported',
                  isGreaterThanOrEqualTo: start.toIso8601String(),
                )
                .where(
                  'dateReported',
                  isLessThanOrEqualTo: end.toIso8601String(),
                );
        final snapshot = await query.get();
        final scopedDocs = snapshot.docs
            .map(materializeFirestoreRecord)
            .where((record) => recordMatchesAccessScope(record, accessScope));
        return sortRecordsByActivityDateDescending(scopedDocs);
      } catch (e) {
        print('Error fetching from Firebase: $e');
        return [];
      }
    }

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
    if (kIsWeb) {
      try {
        final accessScope = await UserAccessScopeService.instance
            .loadCurrentScope();
        final query = buildScopedRecordQuery(
          getFirestoreInstance(),
          _collectionName,
          accessScope,
        ).where('ageRange', isEqualTo: ageRange);
        final snapshot = await query.get();
        final scopedDocs = snapshot.docs
            .map(materializeFirestoreRecord)
            .where((record) => recordMatchesAccessScope(record, accessScope));
        return sortRecordsByActivityDateDescending(scopedDocs);
      } catch (e) {
        print('Error fetching from Firebase: $e');
        return [];
      }
    }

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
    int elderlyCount = 0;

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

  // Update record
  Future<void> updateRecord(Map<String, dynamic> record) async {
    final id = record['id'];

    if (kIsWeb) {
      try {
        final accessScope = await UserAccessScopeService.instance
            .loadCurrentScope();
        final updateData = applyBarangayScopeToRecord(
          Map<String, dynamic>.from(record)
            ..remove('synced')
            ..['updatedAt'] = FieldValue.serverTimestamp(),
          accessScope: accessScope,
        );
        final documentRef = await resolveScopedRecordDocumentReference(
          getFirestoreInstance(),
          _collectionName,
          id,
          accessScope: accessScope,
          record: updateData,
          existingPath: (record['_firestorePath'] ?? '').toString(),
        );
        await documentRef.update(updateData);
        await syncMortalityToPatientHistory(updateData);
        return;
      } catch (e) {
        print('Error updating on Firebase: $e');
        rethrow;
      }
    }

    // Mobile: update locally
    final db = await database;
    await db.update(
      'mortality_records',
      record,
      where: 'id = ?',
      whereArgs: [id],
    );

    // Try to sync if online
    final connectivityResult = await Connectivity().checkConnectivity();
    final hasInternet = !connectivityResult.contains(ConnectivityResult.none);
    if (hasInternet) {
      try {
        final updateData = Map<String, dynamic>.from(record);
        updateData.remove('synced');
        await getFirestoreInstance()
            .collection('mortality_records')
            .doc(id)
            .update(updateData);
        await syncMortalityToPatientHistory(updateData);
      } catch (e) {
        print('⚠️ Failed to update on Firestore: $e');
      }
    }
  }

  // Delete record
  Future<void> deleteRecord(String id) async {
    if (kIsWeb) {
      try {
        final accessScope = await UserAccessScopeService.instance
            .loadCurrentScope();
        final documentRef = await resolveScopedRecordDocumentReference(
          getFirestoreInstance(),
          _collectionName,
          id,
          accessScope: accessScope,
        );
        await documentRef.delete();
        return;
      } catch (e) {
        print('Error deleting from Firebase: $e');
        rethrow;
      }
    }

    // Mobile: delete locally
    final db = await database;
    await db.delete('mortality_records', where: 'id = ?', whereArgs: [id]);

    // Try to sync if online
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

  Future<void> syncMortalityToPatientHistory(
    Map<String, dynamic> mortalityRecord,
  ) async {
    final patientId = (mortalityRecord['patientId'] ?? '').toString().trim();
    if (patientId.isEmpty) {
      return;
    }

    final timelineEntry = <String, dynamic>{
      'type': 'mortality',
      'recordId': (mortalityRecord['id'] ?? '').toString(),
      'patientId': patientId,
      'patientName': (mortalityRecord['name'] ?? '').toString(),
      'causeOfDeath': (mortalityRecord['causeOfDeath'] ?? '').toString(),
      'causeCategory': (mortalityRecord['causeCategory'] ?? '').toString(),
      'reason': (mortalityRecord['reason'] ?? '').toString(),
      'explanation': (mortalityRecord['explanation'] ?? '').toString(),
      'dateTimeOfDeath': (mortalityRecord['dateTimeOfDeath'] ?? '').toString(),
      'timeOfDeath': (mortalityRecord['timeOfDeath'] ?? '').toString(),
      'date': (mortalityRecord['date'] ?? '').toString(),
      'purok': (mortalityRecord['purok'] ?? '').toString(),
      'place': (mortalityRecord['place'] ?? '').toString(),
      'reportedBy': (mortalityRecord['reportedBy'] ?? '').toString(),
      'verification': (mortalityRecord['verification'] ?? '').toString(),
      'loggedAt': FieldValue.serverTimestamp(),
    };

    final patientRef = await resolveScopedRecordDocumentReference(
      getFirestoreInstance(),
      'patient_records',
      patientId,
      record: mortalityRecord,
    );

    await patientRef.set({
      'status': 'Deceased',
      'mortalityLinked': true,
      'mortalityRecordId': (mortalityRecord['id'] ?? '').toString(),
      'mortalityCauseOfDeath': (mortalityRecord['causeOfDeath'] ?? '')
          .toString(),
      'mortalityReason': (mortalityRecord['reason'] ?? '').toString(),
      'mortalityExplanation': (mortalityRecord['explanation'] ?? '').toString(),
      'mortalityDateTimeOfDeath': (mortalityRecord['dateTimeOfDeath'] ?? '')
          .toString(),
      'mortalityPurok': (mortalityRecord['purok'] ?? '').toString(),
      'mortalityPlace': (mortalityRecord['place'] ?? '').toString(),
      'updatedAt': FieldValue.serverTimestamp(),
      'patientHistoryTimeline': FieldValue.arrayUnion([timelineEntry]),
    }, SetOptions(merge: true));
  }
}
