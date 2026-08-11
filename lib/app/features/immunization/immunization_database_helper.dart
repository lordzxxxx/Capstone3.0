import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:mycapstone_project/firebase_helper.dart';
import 'package:mycapstone_project/shared/barangay_scope_utils.dart';
import 'package:mycapstone_project/web/shared/services/user_access_scope_service.dart';

class ImmunizationDatabaseHelper {
  static final ImmunizationDatabaseHelper instance =
      ImmunizationDatabaseHelper._init();
  static Database? _database;
  bool _connectivityListenerStarted = false;
  bool _isConnectivitySyncRunning = false;

  ImmunizationDatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('immunization_records.db');
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
      CREATE TABLE immunization_records (
        id $idType,
        time $textType,
        patientName $textType,
        patientId $textType,
        age $textType,
        contactNumber $textType,
        vaccine $textType,
        vaccineBrand $textType,
        batchNumber $textType,
        expirationDate $textType,
        administrationDate $textType,
        administrationTime $textType,
        doseNumber $textType,
        routeOfAdministration $textType,
        injectionSite $textType,
        administeredBy $textType,
        adverseEvents $textType,
        nextDoseDueDate $textType,
        status $textType,
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
          'time': record['time'] ?? '',
          'patientName': record['patientName'] ?? '',
          'patientId': record['patientId'] ?? '',
          'age': record['age'] ?? '',
          'contactNumber': record['contactNumber'] ?? '',
          'vaccine': record['vaccine'] ?? '',
          'vaccineBrand': record['vaccineBrand'] ?? '',
          'batchNumber': record['batchNumber'] ?? '',
          'expirationDate': record['expirationDate'] ?? '',
          'administrationDate': record['administrationDate'] ?? '',
          'administrationTime': record['administrationTime'] ?? '',
          'doseNumber': record['doseNumber'] ?? '',
          'routeOfAdministration': record['routeOfAdministration'] ?? '',
          'injectionSite': record['injectionSite'] ?? '',
          'administeredBy': record['administeredBy'] ?? '',
          'adverseEvents': record['adverseEvents'] ?? '',
          'nextDoseDueDate': record['nextDoseDueDate'] ?? '',
          'status': record['status'] ?? '',
          'date': record['date'] ?? '',
        };
        await getFirestoreInstance()
            .collection('immunization_records')
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
      'time': record['time'] ?? '',
      'patientName': record['patientName'] ?? '',
      'patientId': record['patientId'] ?? '',
      'age': record['age'] ?? '',
      'contactNumber': record['contactNumber'] ?? '',
      'vaccine': record['vaccine'] ?? '',
      'vaccineBrand': record['vaccineBrand'] ?? '',
      'batchNumber': record['batchNumber'] ?? '',
      'expirationDate': record['expirationDate'] ?? '',
      'administrationDate': record['administrationDate'] ?? '',
      'administrationTime': record['administrationTime'] ?? '',
      'doseNumber': record['doseNumber'] ?? '',
      'routeOfAdministration': record['routeOfAdministration'] ?? '',
      'injectionSite': record['injectionSite'] ?? '',
      'administeredBy': record['administeredBy'] ?? '',
      'adverseEvents': record['adverseEvents'] ?? '',
      'nextDoseDueDate': record['nextDoseDueDate'] ?? '',
      'status': record['status'] ?? '',
      'date': record['date'] ?? '',
      'synced': 0,
    };

    // Save to local database first
    await db.insert(
      'immunization_records',
      recordWithId,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    // If online, immediately save to Firestore
    if (hasInternet) {
      try {
        final firestoreData = Map<String, dynamic>.from(recordWithId);
        firestoreData.remove('synced'); // Don't save synced flag to Firestore

        await getFirestoreInstance()
            .collection('immunization_records')
            .doc(id)
            .set(firestoreData);

        await db.update(
          'immunization_records',
          {'synced': 1},
          where: 'id = ?',
          whereArgs: [id],
        );

        print('✅ Immunization record $id saved to Firestore immediately');
      } catch (e) {
        print('⚠️ Failed to save to Firestore, will retry later: $e');
        // Mark as unsynced so it will retry later
        await db.update(
          'immunization_records',
          {'synced': 0},
          where: 'id = ?',
          whereArgs: [id],
        );
      }
    } else {
      print(
        '📴 Offline: Immunization record $id saved locally, will sync when online',
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
          .collection('immunization_records')
          .orderBy('administrationDate', descending: true)
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
            .collection('immunization_records')
            .orderBy('administrationDate', descending: true)
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
      'immunization_records',
      orderBy: 'administrationDate DESC, administrationTime DESC',
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
            .collection('immunization_records')
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

    final result = await db.update(
      'immunization_records',
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
            .collection('immunization_records')
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
      'immunization_records',
      where: 'id = ?',
      whereArgs: [id],
    );

    if (record.isNotEmpty && record.first['synced'] == 1) {
      try {
        await getFirestoreInstance()
            .collection('immunization_records')
            .doc(id)
            .delete();
      } catch (e) {
        print('Error deleting from Firebase: $e');
      }
    }

    return await db.delete(
      'immunization_records',
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
              .collection('immunization_records')
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
        'immunization_records',
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
              .collection('immunization_records')
              .doc(id)
              .set(recordData, SetOptions(merge: true));

          // Mark as synced
          await db.update(
            'immunization_records',
            {'synced': 1},
            where: 'id = ?',
            whereArgs: [id],
          );

          print('Synced immunization record: $id');
        } catch (e) {
          print('Error syncing immunization record: $e');
        }
      }
    } catch (e) {
      print('Error during immunization sync: $e');
    }
  }

  // Pull data from Firebase (for initial sync or when logging in)
  Future<void> syncFromFirebase() async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        print('No authenticated user. Skipping immunization Firebase sync.');
        return;
      }

      final accessScope = await UserAccessScopeService.instance
          .loadCurrentScope();
      if (!accessScope.isAuthenticated) {
        print(
          'No authenticated access scope. Skipping immunization Firebase sync.',
        );
        return;
      }
      if (!accessScope.canViewAllBarangays &&
          accessScope.barangayCode.trim().isEmpty &&
          accessScope.barangay.trim().isEmpty) {
        print('No barangay scope loaded. Skipping immunization Firebase sync.');
        return;
      }

      final connectivityResult = await Connectivity().checkConnectivity();
      if (connectivityResult.contains(ConnectivityResult.none)) {
        print('No internet connection. Using offline data.');
        return;
      }

      final snapshot = await buildScopedRecordQuery(
        getFirestoreInstance(),
        'immunization_records',
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
          'time': data['time'] ?? '',
          'patientName': data['patientName'] ?? '',
          'patientId': data['patientId'] ?? '',
          'age': data['age'] ?? '',
          'contactNumber': data['contactNumber'] ?? '',
          'vaccine': data['vaccine'] ?? '',
          'vaccineBrand': data['vaccineBrand'] ?? '',
          'batchNumber': data['batchNumber'] ?? '',
          'expirationDate': data['expirationDate'] ?? '',
          'administrationDate': data['administrationDate'] ?? '',
          'administrationTime': data['administrationTime'] ?? '',
          'doseNumber': data['doseNumber'] ?? '',
          'routeOfAdministration': data['routeOfAdministration'] ?? '',
          'injectionSite': data['injectionSite'] ?? '',
          'administeredBy': data['administeredBy'] ?? '',
          'adverseEvents': data['adverseEvents'] ?? '',
          'nextDoseDueDate': data['nextDoseDueDate'] ?? '',
          'status': data['status'] ?? '',
          'date': data['date'] ?? '',
          'synced': 1,
        };

        await db.insert(
          'immunization_records',
          completeData,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      print('Synced ${records.length} immunization records from Firebase');
    } catch (e) {
      print('Error syncing immunization records from Firebase: $e');
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
    await db.delete('immunization_records');
  }

  // Start listening for connectivity changes
  void startConnectivityListener() {
    if (kIsWeb || _connectivityListenerStarted) return;

    _connectivityListenerStarted = true;
    _runConnectivitySync();

    Connectivity().onConnectivityChanged.listen((result) async {
      if (!result.contains(ConnectivityResult.none)) {
        print('Internet connected! Syncing immunization data...');
        await _runConnectivitySync();
      }
    });
  }

  // Seed 100 sample immunization records
  Future<void> seedSampleImmunizationData() async {
    final List<String> patientNames = [
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
    ];

    final List<String> vaccines = [
      'BCG',
      'Hepatitis B',
      'Polio',
      'DPT',
      'MMR',
      'Varicella',
      'Pneumococcal',
      'Influenza',
      'COVID-19',
      'Meningococcal',
      'Yellow Fever',
      'Tetanus',
      'Diphtheria',
      'Pertussis',
      'Typhoid',
      'Japanese Encephalitis',
      'Rabies',
      'Rotavirus',
    ];

    final List<String> brands = [
      'Pfizer',
      'Moderna',
      'AstraZeneca',
      'Sinovac',
      'Janssen',
      'Merck',
      'Sanofi',
      'Novavax',
      'Bharat',
      'GSK',
      'Abbott',
      'Serum Institute',
      'Paxvax',
      'Valneva',
    ];

    final List<String> routeOfAdmin = [
      'Intramuscular',
      'Subcutaneous',
      'Oral',
      'Intradermal',
      'Intranasal',
    ];

    final List<String> injectionSites = [
      'Left Arm',
      'Right Arm',
      'Left Leg',
      'Right Leg',
      'Left Shoulder',
      'Right Shoulder',
    ];

    final List<String> adverseEvents = [
      'None',
      'Mild fever',
      'Local swelling',
      'Redness at injection site',
      'Mild rash',
      'Myalgia',
      'Fatigue',
      'Headache',
      'None reported',
    ];

    final List<String> statuses = [
      'Completed',
      'Pending',
      'Due',
      'Overdue',
      'Completed with adverse event',
    ];

    final samples = <Map<String, dynamic>>[];
    final random = DateTime.now().millisecondsSinceEpoch;

    for (int i = 0; i < 100; i++) {
      final daysAgo = i % 180; // Spread over 6 months
      final recordDate = DateTime.now().subtract(Duration(days: daysAgo));

      final patientAge = 5 + (i % 60); // Ages 5-65
      final doseNum = (i % 4) + 1; // Dose 1-4

      final nextDoseDate = recordDate
          .add(Duration(days: 30 * doseNum))
          .toString()
          .split(' ')[0];

      samples.add({
        'id': 'imm_${random}_$i',
        'time': recordDate.toString(),
        'patientName': patientNames[i % patientNames.length],
        'patientId': 'PAT${1000 + i}',
        'age': patientAge.toString(),
        'contactNumber': '09${100000000 + i}',
        'vaccine': vaccines[i % vaccines.length],
        'vaccineBrand': brands[i % brands.length],
        'batchNumber': 'BATCH${(i + 1).toString().padLeft(6, '0')}',
        'expirationDate': DateTime.now()
            .add(Duration(days: 180 + (i % 365)))
            .toString()
            .split(' ')[0],
        'administrationDate': recordDate.toString().split(' ')[0],
        'administrationTime': '${9 + (i % 8)}:${(i * 15) % 60}',
        'doseNumber': doseNum.toString(),
        'routeOfAdministration': routeOfAdmin[i % routeOfAdmin.length],
        'injectionSite': injectionSites[i % injectionSites.length],
        'administeredBy': 'Nurse ${(i % 20) + 1}',
        'adverseEvents': adverseEvents[i % adverseEvents.length],
        'nextDoseDueDate': nextDoseDate,
        'status': statuses[i % statuses.length],
        'date': recordDate.toString().split(' ')[0],
      });
    }

    try {
      final db = await database;
      int inserted = 0;

      for (var sample in samples) {
        try {
          await db.insert('immunization_records', {
            ...sample,
            'synced': 1,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
          inserted++;
        } catch (e) {
          print('Error inserting sample immunization ${sample['id']}: $e');
        }
      }

      print('✅ Successfully seeded $inserted sample immunization records');

      // Sync to Firestore if online
      final connectivityResult = await Connectivity().checkConnectivity();
      if (!connectivityResult.contains(ConnectivityResult.none)) {
        try {
          final firestore = getFirestoreInstance();
          for (var sample in samples) {
            await firestore
                .collection('immunization_records')
                .doc(sample['id'])
                .set(sample);
          }
          print('✅ Synced sample immunization records to Firestore');
        } catch (e) {
          print('⚠️ Could not sync to Firestore: $e');
        }
      }
    } catch (e) {
      print('❌ Error seeding immunization data: $e');
      rethrow;
    }
  }

  // Close database
  Future close() async {
    final db = await database;
    db.close();
  }
}
