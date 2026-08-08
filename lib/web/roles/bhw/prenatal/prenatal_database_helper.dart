import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:mycapstone_project/firebase_helper.dart';
import 'package:mycapstone_project/shared/barangay_scope_utils.dart';
import 'package:mycapstone_project/web/shared/services/user_access_scope_service.dart';

class PrenatalDatabaseHelper {
  static final PrenatalDatabaseHelper instance = PrenatalDatabaseHelper._init();
  static Database? _database;
  static const String _collectionName = 'prenatal_records';

  PrenatalDatabaseHelper._init();

  Future<Database> get database async {
    // On web, throw error since we shouldn't use SQLite
    if (kIsWeb) {
      throw UnsupportedError(
        'SQLite database is not supported on web. Use Firebase directly.',
      );
    }

    if (_database != null) return _database!;
    _database = await _initDB('prenatal_records.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 2,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  Future _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute(
        'ALTER TABLE prenatal_records ADD COLUMN ai_category TEXT DEFAULT ""',
      );
      await db.execute(
        'ALTER TABLE prenatal_records ADD COLUMN ai_severity TEXT DEFAULT ""',
      );
      await db.execute(
        'ALTER TABLE prenatal_records ADD COLUMN ai_confidence TEXT DEFAULT ""',
      );
      await db.execute(
        'ALTER TABLE prenatal_records ADD COLUMN ai_method TEXT DEFAULT ""',
      );
      await db.execute(
        'ALTER TABLE prenatal_records ADD COLUMN ai_keywords TEXT DEFAULT ""',
      );
      await db.execute(
        'ALTER TABLE prenatal_records ADD COLUMN ai_recovery_plan TEXT DEFAULT ""',
      );
    }
  }

  Future _createDB(Database db, int version) async {
    const idType = 'TEXT PRIMARY KEY';
    const textType = 'TEXT NOT NULL';
    const intType = 'INTEGER NOT NULL';

    await db.execute('''
      CREATE TABLE prenatal_records (
        id $idType,
        patientName $textType,
        age $textType,
        address $textType,
        patientId $textType,
        contactNumber $textType,
        civilStatus $textType,
        religion $textType,
        philhealthNumber $textType,
        philhealthMember $textType,
        lmpDate $textType,
        eddDate $textType,
        lastDeliveryDate $textType,
        gravida $textType,
        para $textType,
        riskLevel $textType,
        bloodType $textType,
        allergies $textType,
        preExistingConditions $textType,
        previousComplications $textType,
        aog $textType,
        wt $textType,
        at $textType,
        temp $textType,
        bp $textType,
        bmi $textType,
        fh $textType,
        dhb $textType,
        tcb $textType,
        registrationDate $textType,
        registeredBy $textType,
        additionalNote $textType,
        gestationalAge $textType,
        dueDate $textType,
        status $textType,
        ai_category TEXT DEFAULT '',
        ai_severity TEXT DEFAULT '',
        ai_confidence TEXT DEFAULT '',
        ai_method TEXT DEFAULT '',
        ai_keywords TEXT DEFAULT '',
        ai_recovery_plan TEXT DEFAULT '',
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
        final accessScope = await UserAccessScopeService.instance
            .loadCurrentScope();
        final recordWithId = {
          'id': id,
          'patientName': record['patientName'] ?? '',
          'age': record['age'] ?? '',
          'address': record['address'] ?? '',
          'patientId': record['patientId'] ?? '',
          'linkedPatientId':
              record['linkedPatientId'] ?? record['patientId'] ?? '',
          'contactNumber': record['contactNumber'] ?? '',
          'civilStatus': record['civilStatus'] ?? '',
          'religion': record['religion'] ?? '',
          'philhealthNumber': record['philhealthNumber'] ?? '',
          'philhealthMember': record['philhealthMember'] ?? '',
          'lmpDate': record['lmpDate'] ?? '',
          'eddDate': record['eddDate'] ?? '',
          'lastDeliveryDate': record['lastDeliveryDate'] ?? '',
          'gravida': record['gravida'] ?? '',
          'para': record['para'] ?? '',
          'riskLevel': record['riskLevel'] ?? '',
          'bloodType': record['bloodType'] ?? '',
          'allergies': record['allergies'] ?? '',
          'preExistingConditions': record['preExistingConditions'] ?? '',
          'previousComplications': record['previousComplications'] ?? '',
          'aog': record['aog'] ?? '',
          'wt': record['wt'] ?? '',
          'at': record['at'] ?? '',
          'temp': record['temp'] ?? '',
          'bp': record['bp'] ?? '',
          'bmi': record['bmi'] ?? '',
          'fh': record['fh'] ?? '',
          'dhb': record['dhb'] ?? '',
          'tcb': record['tcb'] ?? '',
          'registrationDate': record['registrationDate'] ?? '',
          'registeredBy': record['registeredBy'] ?? '',
          'additionalNote': record['additionalNote'] ?? '',
          'gestationalAge': record['gestationalAge'] ?? '',
          'dueDate': record['dueDate'] ?? '',
          'status': record['status'] ?? '',
          'ai_category': record['ai_category'] ?? '',
          'ai_severity': record['ai_severity'] ?? '',
          'ai_confidence': record['ai_confidence']?.toString() ?? '',
          'ai_method': record['ai_method'] ?? '',
          'ai_keywords': record['ai_keywords'] ?? '',
          'ai_recovery_plan': record['ai_recovery_plan'] ?? '',
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
        return id;
      } catch (e) {
        print('Error saving to Firebase on web: $e');
        rethrow;
      }
    }

    // On mobile, save to SQLite
    final db = await database;
    final recordWithId = {
      'id': id,
      'patientName': record['patientName'] ?? '',
      'age': record['age'] ?? '',
      'address': record['address'] ?? '',
      'patientId': record['patientId'] ?? '',
      'contactNumber': record['contactNumber'] ?? '',
      'civilStatus': record['civilStatus'] ?? '',
      'religion': record['religion'] ?? '',
      'philhealthNumber': record['philhealthNumber'] ?? '',
      'philhealthMember': record['philhealthMember'] ?? '',
      'lmpDate': record['lmpDate'] ?? '',
      'eddDate': record['eddDate'] ?? '',
      'lastDeliveryDate': record['lastDeliveryDate'] ?? '',
      'gravida': record['gravida'] ?? '',
      'para': record['para'] ?? '',
      'riskLevel': record['riskLevel'] ?? '',
      'bloodType': record['bloodType'] ?? '',
      'allergies': record['allergies'] ?? '',
      'preExistingConditions': record['preExistingConditions'] ?? '',
      'previousComplications': record['previousComplications'] ?? '',
      'aog': record['aog'] ?? '',
      'wt': record['wt'] ?? '',
      'at': record['at'] ?? '',
      'temp': record['temp'] ?? '',
      'bp': record['bp'] ?? '',
      'bmi': record['bmi'] ?? '',
      'fh': record['fh'] ?? '',
      'dhb': record['dhb'] ?? '',
      'tcb': record['tcb'] ?? '',
      'registrationDate': record['registrationDate'] ?? '',
      'registeredBy': record['registeredBy'] ?? '',
      'additionalNote': record['additionalNote'] ?? '',
      'gestationalAge': record['gestationalAge'] ?? '',
      'dueDate': record['dueDate'] ?? '',
      'status': record['status'] ?? '',
      'ai_category': record['ai_category'] ?? '',
      'ai_severity': record['ai_severity'] ?? '',
      'ai_confidence': record['ai_confidence']?.toString() ?? '',
      'ai_method': record['ai_method'] ?? '',
      'ai_keywords': record['ai_keywords'] ?? '',
      'ai_recovery_plan': record['ai_recovery_plan'] ?? '',
      'synced': 0, // 0 = not synced, 1 = synced
    };

    await db.insert(
      'prenatal_records',
      recordWithId,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    // Try to sync immediately if online
    _syncToFirebase();

    return id;
  }

  // Get all records
  Future<List<Map<String, dynamic>>> getAllRecords() async {
    // On web, use Firebase directly
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
        print('Error fetching from Firebase on web: $e');
        return [];
      }
    }

    // On mobile, use SQLite
    final db = await database;
    final result = await db.query(
      'prenatal_records',
      orderBy: 'registrationDate DESC',
    );

    return result.map((record) {
      final map = Map<String, dynamic>.from(record);
      map.remove('synced'); // Remove synced flag from UI data
      return map;
    }).toList();
  }

  // Update record
  Future<int> updateRecord(String id, Map<String, dynamic> record) async {
    // On web, update directly in Firebase
    if (kIsWeb) {
      try {
        final accessScope = await UserAccessScopeService.instance
            .loadCurrentScope();
        final updatedRecord = applyBarangayScopeToRecord({
          ...record,
          'id': id,
          'updatedAt': FieldValue.serverTimestamp(),
        }, accessScope: accessScope);
        final documentRef = await resolveScopedRecordDocumentReference(
          getFirestoreInstance(),
          _collectionName,
          id,
          accessScope: accessScope,
          record: updatedRecord,
          existingPath: (record['_firestorePath'] ?? '').toString(),
        );
        await documentRef.update(updatedRecord);
        return 1;
      } catch (e) {
        print('Error updating Firebase on web: $e');
        return 0;
      }
    }

    // On mobile, update in SQLite
    final db = await database;
    final updatedRecord = {
      ...record,
      'id': id,
      'synced': 0, // Mark as unsynced after update
    };

    final result = await db.update(
      'prenatal_records',
      updatedRecord,
      where: 'id = ?',
      whereArgs: [id],
    );

    _syncToFirebase();
    return result;
  }

  // Delete record
  Future<int> deleteRecord(String id) async {
    // On web, delete directly from Firebase
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
        return 1;
      } catch (e) {
        print('Error deleting from Firebase on web: $e');
        return 0;
      }
    }

    // On mobile, delete from SQLite
    final db = await database;

    // Delete from Firebase if synced
    final record = await db.query(
      'prenatal_records',
      where: 'id = ?',
      whereArgs: [id],
    );

    if (record.isNotEmpty && record.first['synced'] == 1) {
      try {
        await getFirestoreInstance()
            .collection('prenatal_records')
            .doc(id)
            .delete();
      } catch (e) {
        print('Error deleting from Firebase: $e');
      }
    }

    return await db.delete(
      'prenatal_records',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // Delete multiple records
  Future<void> deleteRecords(List<String> ids) async {
    // On web, delete directly from Firebase
    if (kIsWeb) {
      for (String id in ids) {
        try {
          await deleteRecord(id);
        } catch (e) {
          print('Error deleting from Firebase on web: $e');
        }
      }
      return;
    }

    // On mobile, delete from local database
    for (String id in ids) {
      await deleteRecord(id);
    }
  }

  // Sync local data to Firebase
  Future<void> _syncToFirebase() async {
    // On web, data is saved directly to Firebase, no sync needed
    if (kIsWeb) {
      return;
    }

    try {
      final connectivityResult = await Connectivity().checkConnectivity();
      if (connectivityResult.contains(ConnectivityResult.none)) {
        print('No internet connection. Will sync later.');
        return;
      }

      final db = await database;
      final unsyncedRecords = await db.query(
        'prenatal_records',
        where: 'synced = ?',
        whereArgs: [0],
      );

      for (var record in unsyncedRecords) {
        try {
          final recordData = Map<String, dynamic>.from(record);
          final id = recordData['id'];
          recordData.remove('synced');
          recordData.remove('id');

          await getFirestoreInstance()
              .collection('prenatal_records')
              .doc(id)
              .set(recordData, SetOptions(merge: true));

          // Mark as synced
          await db.update(
            'prenatal_records',
            {'synced': 1},
            where: 'id = ?',
            whereArgs: [id],
          );

          print('Synced prenatal record: $id');
        } catch (e) {
          print('Error syncing prenatal record: $e');
        }
      }
    } catch (e) {
      print('Error during prenatal sync: $e');
    }
  }

  // Pull data from Firebase (for initial sync or when logging in)
  Future<void> syncFromFirebase() async {
    // On web, data is already in Firebase, no sync needed
    if (kIsWeb) {
      print('Running on web - data is already in Firebase');
      return;
    }

    try {
      final connectivityResult = await Connectivity().checkConnectivity();
      if (connectivityResult.contains(ConnectivityResult.none)) {
        print('No internet connection. Using offline data.');
        return;
      }

      final snapshot = await getFirestoreInstance()
          .collection('prenatal_records')
          .get();

      final db = await database;

      for (var doc in snapshot.docs) {
        final data = doc.data();
        data['id'] = doc.id;
        data['synced'] = 1;

        // Ensure all fields exist with default values
        final completeData = {
          'id': data['id'],
          'patientName': data['patientName'] ?? '',
          'age': data['age'] ?? '',
          'address': data['address'] ?? '',
          'patientId': data['patientId'] ?? '',
          'contactNumber': data['contactNumber'] ?? '',
          'civilStatus': data['civilStatus'] ?? '',
          'religion': data['religion'] ?? '',
          'philhealthNumber': data['philhealthNumber'] ?? '',
          'philhealthMember': data['philhealthMember'] ?? '',
          'lmpDate': data['lmpDate'] ?? '',
          'eddDate': data['eddDate'] ?? '',
          'lastDeliveryDate': data['lastDeliveryDate'] ?? '',
          'gravida': data['gravida'] ?? '',
          'para': data['para'] ?? '',
          'riskLevel': data['riskLevel'] ?? '',
          'bloodType': data['bloodType'] ?? '',
          'allergies': data['allergies'] ?? '',
          'preExistingConditions': data['preExistingConditions'] ?? '',
          'previousComplications': data['previousComplications'] ?? '',
          'aog': data['aog'] ?? '',
          'wt': data['wt'] ?? '',
          'at': data['at'] ?? '',
          'temp': data['temp'] ?? '',
          'bp': data['bp'] ?? '',
          'bmi': data['bmi'] ?? '',
          'fh': data['fh'] ?? '',
          'dhb': data['dhb'] ?? '',
          'tcb': data['tcb'] ?? '',
          'registrationDate': data['registrationDate'] ?? '',
          'registeredBy': data['registeredBy'] ?? '',
          'additionalNote': data['additionalNote'] ?? '',
          'gestationalAge': data['gestationalAge'] ?? '',
          'dueDate': data['dueDate'] ?? '',
          'status': data['status'] ?? '',
          'ai_category': data['ai_category'] ?? '',
          'ai_severity': data['ai_severity'] ?? '',
          'ai_confidence': data['ai_confidence']?.toString() ?? '',
          'ai_method': data['ai_method'] ?? '',
          'ai_keywords': data['ai_keywords'] ?? '',
          'ai_recovery_plan': data['ai_recovery_plan'] ?? '',
          'synced': 1,
        };

        await db.insert(
          'prenatal_records',
          completeData,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      print('Synced ${snapshot.docs.length} prenatal records from Firebase');
    } catch (e) {
      print('Error syncing prenatal records from Firebase: $e');
    }
  }

  // Start listening for connectivity changes
  void startConnectivityListener() {
    // On web, no need for connectivity listener since data is always in Firebase
    if (kIsWeb) {
      return;
    }

    Connectivity().onConnectivityChanged.listen((result) {
      if (!result.contains(ConnectivityResult.none)) {
        print('Internet connected! Syncing prenatal data...');
        _syncToFirebase();
        syncFromFirebase();
      }
    });
  }

  // Close database
  Future close() async {
    final db = await database;
    db.close();
  }
}
