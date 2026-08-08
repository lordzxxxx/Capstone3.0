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

class PrenatalDatabaseHelper {
  static final PrenatalDatabaseHelper instance = PrenatalDatabaseHelper._init();
  static Database? _database;
  bool _connectivityListenerStarted = false;
  bool _isConnectivitySyncRunning = false;

  PrenatalDatabaseHelper._init();

  Future<Database> get database async {
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
        };
        await getFirestoreInstance()
            .collection('prenatal_records')
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
      'synced': 0,
    };

    // Save to local database first
    await db.insert(
      'prenatal_records',
      recordWithId,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    // If online, immediately save to Firestore
    if (hasInternet) {
      try {
        final firestoreData = Map<String, dynamic>.from(recordWithId);
        firestoreData.remove('synced'); // Don't save synced flag to Firestore

        await getFirestoreInstance()
            .collection('prenatal_records')
            .doc(id)
            .set(firestoreData);

        await db.update(
          'prenatal_records',
          {'synced': 1},
          where: 'id = ?',
          whereArgs: [id],
        );

        print('✅ Prenatal record $id saved to Firestore immediately');
      } catch (e) {
        print('⚠️ Failed to save to Firestore, will retry later: $e');
        // Mark as unsynced so it will retry later
        await db.update(
          'prenatal_records',
          {'synced': 0},
          where: 'id = ?',
          whereArgs: [id],
        );
      }
    } else {
      print(
        '📴 Offline: Prenatal record $id saved locally, will sync when online',
      );
    }

    return id;
  }

  // Get all records
  // Get real-time stream of records (for live updates)
  Stream<List<Map<String, dynamic>>> getRecordsStream() {
    // On web, use Firestore real-time listener
    if (kIsWeb) {
      return getFirestoreInstance()
          .collection('prenatal_records')
          .orderBy('registrationDate', descending: true)
          .snapshots()
          .map((snapshot) {
            return snapshot.docs.map((doc) {
              final data = doc.data();
              data['id'] = doc.id;
              return data;
            }).toList();
          });
    }

    // On mobile, return a stream that updates when data changes
    return Stream.periodic(const Duration(seconds: 2)).asyncMap((_) async {
      return await getAllRecords();
    });
  }

  Future<List<Map<String, dynamic>>> getAllRecords() async {
    // On web, use Firebase directly
    if (kIsWeb) {
      try {
        final snapshot = await getFirestoreInstance()
            .collection('prenatal_records')
            .orderBy('registrationDate', descending: true)
            .get();
        return snapshot.docs.map((doc) {
          final data = doc.data();
          data['id'] = doc.id;
          return data;
        }).toList();
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
        final updatedRecord = {...record, 'id': id};
        await getFirestoreInstance()
            .collection('prenatal_records')
            .doc(id)
            .update(updatedRecord);
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

    // Ensure AI fields are stored as strings for SQLite compatibility
    if (updatedRecord['ai_confidence'] != null) {
      updatedRecord['ai_confidence'] = updatedRecord['ai_confidence']
          .toString();
    }
    if (updatedRecord['ai_recovery_plan'] != null &&
        updatedRecord['ai_recovery_plan'] is! String) {
      updatedRecord['ai_recovery_plan'] = updatedRecord['ai_recovery_plan']
          .toString();
    }

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
        await getFirestoreInstance()
            .collection('prenatal_records')
            .doc(id)
            .delete();
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
          await getFirestoreInstance()
              .collection('prenatal_records')
              .doc(id)
              .delete();
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
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        print('No authenticated user. Skipping prenatal Firebase sync.');
        return;
      }

      final accessScope = await UserAccessScopeService.instance
          .loadCurrentScope();
      if (!accessScope.isAuthenticated) {
        print(
          'No authenticated access scope. Skipping prenatal Firebase sync.',
        );
        return;
      }
      if (!accessScope.canViewAllBarangays &&
          accessScope.barangayCode.trim().isEmpty &&
          accessScope.barangay.trim().isEmpty) {
        print('No barangay scope loaded. Skipping prenatal Firebase sync.');
        return;
      }

      final connectivityResult = await Connectivity().checkConnectivity();
      if (connectivityResult.contains(ConnectivityResult.none)) {
        print('No internet connection. Using offline data.');
        return;
      }

      final snapshot = await buildScopedRecordQuery(
        getFirestoreInstance(),
        'prenatal_records',
        accessScope,
      ).get();

      final records = snapshot.docs
          .map(materializeFirestoreRecord)
          .where((record) => recordMatchesAccessScope(record, accessScope))
          .toList(growable: false);

      final db = await database;

      for (final record in records) {
        final data = Map<String, dynamic>.from(record);
        data.remove('_firestorePath');
        data['synced'] = 1;

        // Convert boolean values to integers for SQLite
        data.forEach((key, value) {
          if (value is bool) {
            data[key] = value ? 1 : 0;
          }
        });

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

      print('Synced ${records.length} prenatal records from Firebase');
    } catch (e) {
      print('Error syncing prenatal records from Firebase: $e');
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
    await db.delete('prenatal_records');
  }

  // Start listening for connectivity changes
  void startConnectivityListener() {
    if (kIsWeb || _connectivityListenerStarted) return;

    _connectivityListenerStarted = true;
    _runConnectivitySync();

    Connectivity().onConnectivityChanged.listen((result) async {
      if (!result.contains(ConnectivityResult.none)) {
        print('Internet connected! Syncing prenatal data...');
        await _runConnectivitySync();
      }
    });
  }

  // Migrate recovery plans from old UTF-8 format to safe ASCII format
  Future<void> migrateRecoveryPlans() async {
    try {
      final db = await database;

      // Check if database is writable by attempting a test transaction
      try {
        await db.transaction((txn) async {
          // If this succeeds, database is writable
        });
      } catch (e) {
        // Database is read-only, skip migration silently
        return;
      }

      final List<Map<String, dynamic>> records = await db.query(
        'prenatal_records',
      );

      final safeDefault = {
        'home_care': [],
        'precautions': [],
        'estimated_recovery': 'Varies by condition',
        'general_advice': [
          '[OK] Follow healthcare provider instructions',
          '[OK] Complete full course of medications',
          '[OK] Report any worsening symptoms',
          '[OK] Maintain healthy lifestyle habits',
        ],
      };

      int migratedCount = 0;

      for (var record in records) {
        bool needsUpdate = false;

        // Check if ai_recovery_plan needs migration
        if (record['ai_recovery_plan'] is String) {
          final planStr = record['ai_recovery_plan'] as String;

          // Look for UTF-8 emoji markers that indicate old format
          if (planStr.contains('\u2705') || planStr.contains('\ud83d\udccb')) {
            // Old UTF-8 format detected, replace with safe default
            record['ai_recovery_plan'] = jsonEncode(safeDefault);
            needsUpdate = true;
          } else if (planStr.isNotEmpty) {
            // Try to decode; if it fails, replace with safe default
            try {
              jsonDecode(planStr);
            } catch (e) {
              record['ai_recovery_plan'] = jsonEncode(safeDefault);
              needsUpdate = true;
            }
          }
        }

        // Update the record if needed
        if (needsUpdate) {
          try {
            await db.update(
              'prenatal_records',
              record,
              where: 'id = ?',
              whereArgs: [record['id']],
            );
            migratedCount++;
          } catch (e) {
            // Silently skip records that can't be updated
          }
        }
      }

      if (migratedCount > 0) {
        print(
          '✓ Migrated $migratedCount prenatal recovery plans to ASCII-safe format',
        );
      }
    } catch (e) {
      // Migration is non-critical, silently fail
    }
  }

  Future<void> seedSamplePrenatalData() async {
    final List<String> firstNames = [
      'Maria',
      'Juan',
      'Jose',
      'Rosa',
      'Miguel',
      'Carmen',
      'Luis',
      'Ana',
      'Ricardo',
      'Elena',
      'Francisco',
      'Sofia',
      'Diego',
      'Gloria',
      'Manuel',
      'Lucia',
      'Carlos',
      'Beatriz',
      'Antonio',
      'Francisca',
      'Gabriel',
      'Teresa',
      'Fernando',
      'Catalina',
      'Sergio',
      'Patricia',
      'Roberto',
      'Magdalena',
      'Alberto',
      'Raquel',
      'Jorge',
      'Dolores',
      'Pedro',
      'Francisca',
      'Andres',
      'Margarita',
      'Marcos',
      'Esperanza',
      'Pablo',
      'Almudena',
      'Enrique',
      'Emilia',
    ];

    final List<String> surnames = [
      'Santos',
      'Garcia',
      'Martinez',
      'Rodriguez',
      'Hernandez',
      'Lopez',
      'Gonzalez',
      'Perez',
      'Sanchez',
      'Ramirez',
      'Torres',
      'Flores',
      'Morales',
      'Castillo',
      'Romero',
      'Vargas',
      'Reyes',
      'Ramos',
      'Cruz',
      'Soto',
      'Medina',
      'Ortiz',
      'Navarro',
      'Herrera',
      'Jimenez',
      'Rojas',
      'Mesa',
      'Vega',
      'Fuentes',
      'Velasco',
    ];

    final List<String> barangays = [
      'Del Carmen',
      'Sagcahan',
      'Binakayan',
      'Kanluran',
      'Silang',
      'Salawag',
      'Paliparan',
      'Pag-asa',
      'Sampalukan',
      'Bagtas',
      'Magdalo',
      'Bayan',
      'Caloocan',
      'San Roque',
      'Dasmariñas',
      'Pakil',
      'Marikina',
    ];

    final List<String> riskLevels = [
      'Low Risk',
      'Low Risk',
      'Low Risk',
      'Moderate Risk',
      'High Risk',
    ];

    final List<String> bloodTypes = [
      'O+',
      'O-',
      'A+',
      'A-',
      'B+',
      'B-',
      'AB+',
      'AB-',
    ];

    final List<String> civilStatuses = [
      'Single',
      'Married',
      'Widowed',
      'Separated',
    ];

    final List<String> religions = [
      'Catholic',
      'Protestant',
      'Muslim',
      'INC',
      'None',
    ];

    final List<String> statuses = [
      'Active',
      'Active',
      'Active',
      'Follow-up',
      'Completed',
    ];

    int savedCount = 0;
    final timestamp = DateTime.now().millisecondsSinceEpoch;

    for (int i = 0; i < 100; i++) {
      final lmpDate = DateTime.now().subtract(Duration(days: 100 + (i % 200)));
      final eddDate = lmpDate.add(const Duration(days: 280));
      final age = 18 + (i % 35);
      final gravida = 1 + (i % 8);
      final para = i % 6;
      final wt = 45 + (i % 55);
      final bmi = (wt / 1.65 / 1.65).toStringAsFixed(1);

      final prenatalRecord = {
        'id': 'prenatal_${timestamp}_$i',
        'patientName':
            '${firstNames[i % firstNames.length]} ${surnames[i % surnames.length]}',
        'age': age.toString(),
        'address': '${barangays[i % barangays.length]}, Kawit, Cavite',
        'patientId': 'PID-${1000 + i}',
        'contactNumber': '09${100000000 + i}',
        'civilStatus': civilStatuses[i % civilStatuses.length],
        'religion': religions[i % religions.length],
        'philhealthNumber': 'PH-${DateTime.now().year}-${100000 + i}',
        'philhealthMember': i % 2 == 0 ? 'Yes' : 'No',
        'lmpDate': lmpDate.toString().split(' ')[0],
        'eddDate': eddDate.toString().split(' ')[0],
        'lastDeliveryDate': i > 50
            ? DateTime.now()
                  .subtract(Duration(days: 365 + (i % 730)))
                  .toString()
                  .split(' ')[0]
            : '',
        'gravida': gravida.toString(),
        'para': para.toString(),
        'riskLevel': riskLevels[i % riskLevels.length],
        'bloodType': bloodTypes[i % bloodTypes.length],
        'allergies': i % 5 == 0
            ? 'Penicillin'
            : i % 5 == 1
            ? 'Aspirin'
            : 'None',
        'preExistingConditions': i % 4 == 0
            ? 'Hypertension'
            : i % 4 == 1
            ? 'Diabetes'
            : 'None',
        'previousComplications': i % 6 == 0
            ? 'Gestational Diabetes'
            : i % 6 == 1
            ? 'Preeclampsia'
            : 'None',
        'aog': '${20 + (i % 20)} weeks',
        'wt': wt.toString(),
        'at': '${155 + (i % 20)} cm',
        'temp': '${36.5 + (i % 1)}',
        'bp': '${110 + (i % 30)}/${70 + (i % 20)}',
        'bmi': bmi,
        'fh': i % 2 == 0 ? 'Positive' : 'Negative',
        'dhb': i % 3 == 0 ? 'Yes' : 'No',
        'tcb': i % 4 == 0 ? 'Yes' : 'No',
        'registrationDate': DateTime.now()
            .subtract(Duration(days: 30 + (i % 90)))
            .toString()
            .split(' ')[0],
        'registeredBy': 'Health Worker ${(i % 5) + 1}',
        'additionalNote': 'Sample prenatal care record #${i + 1}',
        'gestationalAge': '${20 + (i % 20)} weeks',
        'dueDate': eddDate.toString().split(' ')[0],
        'status': statuses[i % statuses.length],
        'ai_category': 'Prenatal Care',
        'ai_severity': 'Normal',
        'ai_confidence': '0.95',
        'ai_method': 'Automated',
        'ai_keywords': 'prenatal, pregnancy, antenatal',
        'ai_recovery_plan': jsonEncode({
          'recommendations': [
            'Regular checkups',
            'Prenatal vitamins',
            'Healthy diet',
          ],
          'followUpDate': eddDate.toString().split(' ')[0],
        }),
        'synced': kIsWeb ? 1 : 0,
      };

      // On web, save to Firebase
      if (kIsWeb) {
        try {
          prenatalRecord.remove('synced');
          await getFirestoreInstance()
              .collection('prenatal_records')
              .doc(prenatalRecord['id'] as String)
              .set(prenatalRecord);
        } catch (e) {
          print('Error saving to Firebase: $e');
        }
      } else {
        // On mobile, save to local database
        try {
          final db = await database;
          await db.insert(
            'prenatal_records',
            prenatalRecord,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        } catch (e) {
          print('Error saving to local database: $e');
        }
      }

      savedCount++;
    }

    if (!kIsWeb) {
      try {
        await _syncToFirebase();
        await syncFromFirebase();
      } catch (e) {
        print('Could not synchronize seeded prenatal records: $e');
      }
    }

    print('✓ Successfully seeded $savedCount prenatal records');
  }

  // Close database
  Future close() async {
    final db = await database;
    db.close();
  }
}
