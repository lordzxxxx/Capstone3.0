import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:mycapstone_project/firebase_helper.dart';
import 'package:mycapstone_project/shared/barangay_scope_utils.dart';
import 'package:mycapstone_project/web/shared/services/user_access_scope_service.dart';

class ImmunizationDatabaseHelper {
  static final ImmunizationDatabaseHelper instance =
      ImmunizationDatabaseHelper._init();
  static Database? _database;
  static const String _collectionName = 'immunization_records';

  ImmunizationDatabaseHelper._init();

  Future<Database> get database async {
    // On web, throw error since we shouldn't use SQLite
    if (kIsWeb) {
      throw UnsupportedError(
        'SQLite database is not supported on web. Use Firebase directly.',
      );
    }

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
        final accessScope = await UserAccessScopeService.instance
            .loadCurrentScope();
        final recordWithId = {
          'id': id,
          'time': record['time'] ?? '',
          'patientName': record['patientName'] ?? '',
          'patientId': record['patientId'] ?? '',
          'linkedPatientId':
              record['linkedPatientId'] ?? record['patientId'] ?? '',
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
      'synced': 0, // 0 = not synced, 1 = synced
    };

    await db.insert(
      'immunization_records',
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
          .collection('immunization_records')
          .get();

      final db = await database;

      for (var doc in snapshot.docs) {
        final data = doc.data();
        data['id'] = doc.id;
        data['synced'] = 1;

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

      print(
        'Synced ${snapshot.docs.length} immunization records from Firebase',
      );
    } catch (e) {
      print('Error syncing immunization records from Firebase: $e');
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
        print('Internet connected! Syncing immunization data...');
        _syncToFirebase();
        syncFromFirebase();
      }
    });
  }

  // Seed 100 sample immunization records
  Future<void> seedSampleImmunizationData() async {
    if (kIsWeb) {
      throw UnsupportedError(
        'Sample data seeding is disabled by the barangay isolation policy.',
      );
    }

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

    // On web, insert directly to Firestore
    try {
      final firestore = getFirestoreInstance();
      int inserted = 0;

      for (var sample in samples) {
        try {
          await firestore
              .collection('immunization_records')
              .doc(sample['id'])
              .set(sample);
          inserted++;
        } catch (e) {
          print('Error inserting sample immunization ${sample['id']}: $e');
        }
      }

      print(
        '✅ Successfully seeded $inserted sample immunization records to Firestore',
      );
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
