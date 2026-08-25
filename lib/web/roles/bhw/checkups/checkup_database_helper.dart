import 'dart:async';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:mycapstone_project/firebase_helper.dart';
import 'package:mycapstone_project/shared/barangay_scope_utils.dart';
import 'package:mycapstone_project/web/shared/services/web_record_sync.dart';
import 'package:mycapstone_project/web/shared/services/user_access_scope_service.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;
  static const String _collectionName = 'checkup_records';

  DatabaseHelper._init();

  Future<Database> get database async {
    // On web, throw error since we shouldn't use SQLite
    if (kIsWeb) {
      throw UnsupportedError(
        'SQLite database is not supported on web. Use Firebase directly.',
      );
    }

    if (_database != null) return _database!;
    _database = await _initDB('checkup_records.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 2,
      onCreate: _createDB,
      onUpgrade: _onUpgrade,
    );
  }

  Future _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Check if diseaseType column already exists before adding
      try {
        final result = await db.rawQuery('PRAGMA table_info(checkup_records)');
        final columnExists = result.any(
          (column) => column['name'] == 'diseaseType',
        );

        if (!columnExists) {
          await db.execute(
            'ALTER TABLE checkup_records ADD COLUMN diseaseType TEXT DEFAULT "General"',
          );
        }
      } catch (e) {
        debugPrint('Error during database upgrade: $e');
        // Column might already exist, continue
      }
    }
  }

  Future _createDB(Database db, int version) async {
    const idType = 'TEXT PRIMARY KEY';
    const textType = 'TEXT NOT NULL';
    const intType = 'INTEGER NOT NULL';

    await db.execute('''
      CREATE TABLE checkup_records (
        id $idType,
        datetime $textType,
        type $textType,
        diseaseType TEXT DEFAULT 'General',
        patient $textType,
        details $textType,
        plan $textType,
        status $textType,
        synced $intType
      )
    ''');
  }

  // Insert record locally
  Future<String> insertRecord(Map<String, dynamic> record) async {
    final id = record['id'] ?? DateTime.now().millisecondsSinceEpoch.toString();

    debugPrint('🔵 [DATABASE_HELPER] insertRecord called');
    debugPrint('🔵 [DATABASE_HELPER] Platform check - kIsWeb: $kIsWeb');
    debugPrint('🔵 [DATABASE_HELPER] Record ID: $id');
    debugPrint('🔵 [DATABASE_HELPER] Record patient: ${record['patient']}');

    // On web, save directly to Firebase
    if (kIsWeb) {
      try {
        final accessScope = await UserAccessScopeService.instance
            .loadCurrentScope();
        // Check authentication status
        final currentUser = FirebaseAuth.instance.currentUser;
        debugPrint(
          '🔵 [DATABASE_HELPER] Authentication check - User logged in: ${currentUser != null}',
        );
        if (currentUser != null) {
          debugPrint('🔵 [DATABASE_HELPER] User ID: ${currentUser.uid}');
          debugPrint('🔵 [DATABASE_HELPER] User email: ${currentUser.email}');
        } else {
          debugPrint('⚠️ [DATABASE_HELPER] WARNING: No authenticated user!');
          debugPrint(
            '⚠️ [DATABASE_HELPER] If using OPTION 2 Firestore rules, this will fail!',
          );
        }

        debugPrint('🔵 [DATABASE_HELPER] Preparing Firestore write...');
        final recordWithId = applyBarangayScopeToRecord(
          WebRecordWriteCoordinator.prepareCreate({
            ...record,
            'createdBy': currentUser?.uid ?? '',
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          }, documentId: id),
          accessScope: accessScope,
        );
        debugPrint(
          '🔵 [DATABASE_HELPER] Writing to Firestore collection: checkup_records',
        );
        debugPrint('🔵 [DATABASE_HELPER] Document ID: $id');
        debugPrint('🔵 [DATABASE_HELPER] Record data: $recordWithId');
        debugPrint(
          '🔵 [DATABASE_HELPER] Starting Firestore .set() operation...',
        );

        final startTime = DateTime.now();
        debugPrint('🔵 [DATABASE_HELPER] Write started at: $startTime');

        final documentRef = await resolveScopedRecordDocumentReference(
          getFirestoreInstance(),
          _collectionName,
          id,
          accessScope: accessScope,
          record: recordWithId,
        );
        await WebRecordWriteCoordinator(
          firestore: getFirestoreInstance(),
        ).create(reference: documentRef, record: recordWithId);

        final endTime = DateTime.now();
        final elapsed = endTime.difference(startTime).inMilliseconds;
        debugPrint(
          '✅ [DATABASE_HELPER] Firestore write completed in ${elapsed}ms',
        );

        debugPrint(
          '✅ [DATABASE_HELPER] Firestore write completed successfully!',
        );
        return id;
      } on FirebaseException catch (e) {
        debugPrint(
          '❌ [DATABASE_HELPER] FirebaseException: ${e.code} - ${e.message}',
        );
        if (e.code == 'permission-denied') {
          throw Exception(
            'Permission denied! Update your Firestore rules to allow writes.\n'
            'Go to: https://console.firebase.google.com/project/capstone-c98f9/firestore/rules\n'
            'See firestore_rules_needed.txt for correct rules.',
          );
        }
        rethrow;
      } catch (e, stackTrace) {
        debugPrint('❌ [DATABASE_HELPER] Error saving to Firebase on web: $e');
        debugPrint('❌ [DATABASE_HELPER] Error type: ${e.runtimeType}');
        debugPrint('❌ [DATABASE_HELPER] Stack trace: $stackTrace');
        rethrow;
      }
    }

    // On mobile, save to SQLite
    final db = await database;
    final recordWithId = {
      ...record,
      'id': id,
      'synced': 0, // 0 = not synced, 1 = synced
    };

    await db.insert(
      'checkup_records',
      recordWithId,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    // Try to sync immediately if online
    _syncToFirebase();

    return id;
  }

  // Get real-time stream of records (for live updates)
  Stream<List<Map<String, dynamic>>> getRecordsStream() {
    // On web, use Firestore real-time listener
    if (kIsWeb) {
      return Stream.fromFuture(
        UserAccessScopeService.instance.loadCurrentScope(),
      ).asyncExpand((accessScope) {
        return buildScopedRecordQuery(
          getFirestoreInstance(),
          _collectionName,
          accessScope,
        ).snapshots(includeMetadataChanges: true).map((snapshot) {
          final scopedDocs = snapshot.docs
              .map(
                (document) => attachWebSyncMetadata(
                  materializeFirestoreRecord(document),
                  hasPendingWrites: document.metadata.hasPendingWrites,
                  isFromCache: snapshot.metadata.isFromCache,
                ),
              )
              .where((record) => recordMatchesAccessScope(record, accessScope));
          return sortRecordsByActivityDateDescending(scopedDocs);
        });
      });
    }

    // On mobile, return a stream that updates when data changes
    return Stream.periodic(const Duration(seconds: 2)).asyncMap((_) async {
      return await getAllRecords();
    });
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
            .map(
              (document) => attachWebSyncMetadata(
                materializeFirestoreRecord(document),
                hasPendingWrites: document.metadata.hasPendingWrites,
                isFromCache: snapshot.metadata.isFromCache,
              ),
            )
            .where((record) => recordMatchesAccessScope(record, accessScope));
        return sortRecordsByActivityDateDescending(scopedDocs);
      } catch (e) {
        debugPrint('Error fetching from Firebase on web: $e');
        return [];
      }
    }

    // On mobile, use SQLite
    final db = await database;
    final result = await db.query('checkup_records', orderBy: 'datetime DESC');

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
        // `_firestorePath` is local UI metadata added when a query result is
        // materialized. Keep it for resolving legacy root documents, but do
        // not persist it as part of the health record.
        final existingPath = (record['_firestorePath'] ?? '').toString();
        final firestoreRecord = Map<String, dynamic>.from(record)
          ..remove('_firestorePath');
        final updatedRecord = applyBarangayScopeToRecord({
          ...firestoreRecord,
          'id': id,
          'updatedBy': FirebaseAuth.instance.currentUser?.uid ?? '',
          'updatedAt': FieldValue.serverTimestamp(),
        }, accessScope: accessScope);
        final documentRef = await resolveScopedRecordDocumentReference(
          getFirestoreInstance(),
          _collectionName,
          id,
          accessScope: accessScope,
          record: updatedRecord,
          existingPath: existingPath,
        );
        await WebRecordWriteCoordinator(
          firestore: getFirestoreInstance(),
        ).update(
          reference: documentRef,
          changes: updatedRecord,
          expectedVersion: recordVersionOf(record),
        );
        return 1;
      } catch (e) {
        debugPrint('Error updating Firebase on web: $e');
        rethrow;
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
      'checkup_records',
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
        await documentRef.delete().timeout(
          const Duration(seconds: 30),
          onTimeout: () {
            throw TimeoutException(
              'Firestore delete timed out after 30 seconds',
            );
          },
        );
        return 1;
      } catch (e) {
        debugPrint('Error deleting from Firebase on web: $e');
        rethrow;
      }
    }

    // On mobile, delete from SQLite
    final db = await database;

    // Delete from Firebase if synced
    final record = await db.query(
      'checkup_records',
      where: 'id = ?',
      whereArgs: [id],
    );

    if (record.isNotEmpty && record.first['synced'] == 1) {
      try {
        await getFirestoreInstance()
            .collection('checkup_records')
            .doc(id)
            .delete();
      } catch (e) {
        debugPrint('Error deleting from Firebase: $e');
      }
    }

    return await db.delete('checkup_records', where: 'id = ?', whereArgs: [id]);
  }

  // Delete multiple records. Returns the ids that failed to delete so
  // callers can report an accurate per-record success/failure summary
  // instead of assuming the whole batch succeeded.
  Future<List<String>> deleteRecords(List<String> ids) async {
    final failedIds = <String>[];
    for (String id in ids) {
      try {
        await deleteRecord(id);
      } catch (e) {
        debugPrint('Error deleting record $id: $e');
        failedIds.add(id);
      }
    }
    return failedIds;
  }

  // Sync local data to Firebase
  Future<void> _syncToFirebase() async {
    // On web, data is already in Firebase
    if (kIsWeb) return;

    try {
      final connectivityResult = await Connectivity().checkConnectivity();
      if (connectivityResult.contains(ConnectivityResult.none)) {
        debugPrint('No internet connection. Will sync later.');
        return;
      }

      final db = await database;
      final unsyncedRecords = await db.query(
        'checkup_records',
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
              .collection('checkup_records')
              .doc(id)
              .set(recordData, SetOptions(merge: true));

          // Mark as synced
          await db.update(
            'checkup_records',
            {'synced': 1},
            where: 'id = ?',
            whereArgs: [id],
          );

          debugPrint('Synced record: $id');
        } catch (e) {
          debugPrint('Error syncing record: $e');
        }
      }
    } catch (e) {
      debugPrint('Error during sync: $e');
    }
  }

  // Pull data from Firebase (for initial sync or when logging in)
  Future<void> syncFromFirebase() async {
    // On web, data is already from Firebase
    if (kIsWeb) return;

    try {
      final connectivityResult = await Connectivity().checkConnectivity();
      if (connectivityResult.contains(ConnectivityResult.none)) {
        debugPrint('No internet connection. Using offline data.');
        return;
      }

      final snapshot = await getFirestoreInstance()
          .collection('checkup_records')
          .get();

      final db = await database;

      for (var doc in snapshot.docs) {
        final data = doc.data();
        data['id'] = doc.id;
        data['synced'] = 1;

        await db.insert(
          'checkup_records',
          data,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      debugPrint('Synced ${snapshot.docs.length} records from Firebase');
    } catch (e) {
      debugPrint('Error syncing from Firebase: $e');
    }
  }

  // Start listening for connectivity changes
  void startConnectivityListener() {
    // On web, no need for sync listener
    if (kIsWeb) return;

    Connectivity().onConnectivityChanged.listen((result) {
      if (!result.contains(ConnectivityResult.none)) {
        debugPrint('Internet connected! Syncing data...');
        _syncToFirebase();
        syncFromFirebase();
      }
    });
  }

  // Seed 100 sample checkup records
  Future<void> seedSampleCheckupData() async {
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

    final List<String> symptoms = [
      'Cough',
      'Fever',
      'Headache',
      'Body Aches',
      'Fatigue',
      'Sore Throat',
      'Runny Nose',
      'Difficulty Breathing',
      'Chest Pain',
      'Abdominal Pain',
      'Diarrhea',
      'Vomiting',
      'Dizziness',
      'Loss of Appetite',
      'Insomnia',
      'Anxiety',
      'High Blood Pressure',
      'Joint Pain',
      'Skin Rash',
      'Nausea',
    ];

    final List<String> diseaseTypes = [
      'General',
      'Hypertension',
      'Diabetes',
      'Asthma',
      'COVID-19',
      'Influenza',
      'Common Cold',
      'Respiratory Infection',
      'Gastroenteritis',
      'Migraine',
      'Arthritis',
      'Thyroid Disease',
      'Anemia',
      'Bacterial Infection',
      'Allergic Reaction',
    ];

    final List<String> checkupTypes = [
      'General Consultation',
      'Follow Up',
      'Physical Exam',
      'Senior Citizen Checkup',
      'Maternal Care',
      'Child Health',
      'Immunization',
      'Chronic Disease Management',
    ];

    final List<String> statuses = [
      'Completed',
      'Pending',
      'On Follow Up',
      'Process',
    ];

    final List<String> addresses = [
      'Barangay Del Carmen, Rosario',
      'Barangay Sagcahan, Kawit',
      'Barangay Binakayan, Noveleta',
      'Barangay Kanluran, Imus',
      'Barangay Silang, Dasmariñas',
      'Barangay Salawag, Maragondon',
      'Barangay Paliparan, Magallanes',
      'Barangay Pag-asa, Indang',
      'Barangay Sampalukan, Silang',
    ];

    final samples = <Map<String, dynamic>>[];
    final random = DateTime.now().millisecondsSinceEpoch;

    for (int i = 0; i < 100; i++) {
      final daysAgo = i % 120; // Spread over 4 months
      final recordDate = DateTime.now().subtract(Duration(days: daysAgo));
      final recordTime = DateTime(
        recordDate.year,
        recordDate.month,
        recordDate.day,
        8 + (i % 9), // 8 AM to 4 PM
        (i * 7) % 60, // Varied minutes
      );

      final symp = symptoms[i % symptoms.length];
      final temp = 36.5 + (i % 3); // 36.5 to 38.5°C
      final bp = '${120 + (i % 30)}/${80 + (i % 20)}';
      final hr = 60 + (i % 40);

      final followupDate = recordTime.add(Duration(days: 7 + (i % 14)));
      final medications = [
        'Amoxicillin 500mg - 3 times daily',
        'Paracetamol 500mg - Every 4-6 hours',
        'Ibuprofen 200mg - Twice daily',
        'Aspirin 100mg - Once daily',
        'Metformin 500mg - Twice daily',
        'Atorvastatin 10mg - Once at night',
        'Lisinopril 10mg - Once daily',
        'Omeprazole 20mg - Once daily',
        'Cetirizine 10mg - Once daily',
        'Vitamin C 500mg - Twice daily',
      ];

      samples.add({
        'id': 'checkup_${random}_$i',
        'datetime': recordTime.toString(),
        'type': checkupTypes[i % checkupTypes.length],
        'diseaseType': diseaseTypes[i % diseaseTypes.length],
        'patient': patientNames[i % patientNames.length],
        'details':
            'Patient complained of $symp. Examined and treated accordingly. Physical examination completed.',
        'plan': i % 4 == 0
            ? 'Follow-up in 1 week. Prescribe antibiotics.'
            : i % 4 == 1
            ? 'Monitor vital signs. Maintain current medication.'
            : i % 4 == 2
            ? 'Refer to specialist. Schedule appointment.'
            : 'Continue home care. Return if symptoms worsen.',
        'status': statuses[i % statuses.length],
        'address': addresses[i % addresses.length],
        'vitalsigns':
            'Temp: ${temp.toStringAsFixed(1)}°C | BP: $bp | HR: $hr bpm | RR: ${16 + (i % 8)} breaths/min | SpO2: ${95 + (i % 4)}%',
        'symptoms': symp,
        'followup': followupDate.toString().split(' ')[0],
        'age': '${20 + (i * 3) % 60}',
        'gender': i % 2 == 0 ? 'Male' : 'Female',
        'weight': '${50 + (i % 50)} kg',
        'height': '${150 + (i % 30)} cm',
        'bloodType': ['A+', 'A-', 'B+', 'B-', 'O+', 'O-', 'AB+', 'AB-'][i % 8],
        'medications': medications[i % medications.length],
        'diagnosis': diseaseTypes[i % diseaseTypes.length],
        'treatment':
            'Medication prescribed and dietary recommendations provided.',
        'createdBy': 'Healthcare Worker',
        'healthFacility': [
          'Rural Health Unit - Barangay $i',
          'District Hospital',
          'Community Health Center',
          'Clinic Station',
        ][i % 4],
        'ai_category': [
          'Respiratory',
          'Cardiovascular',
          'Gastrointestinal',
          'Neurological',
          'General',
        ][i % 5],
        'ai_severity': ['Low', 'Medium', 'High'][i % 3],
        'ai_confidence': '${75 + (i % 20)}%',
        'ai_method': 'Symptomatic Analysis',
        'ai_keywords': '$symp, temperature, vital signs, blood pressure',
        'ai_recovery_plan':
            'Rest, hydration, and medication as prescribed. Monitor symptoms closely. Follow-up appointment scheduled.',
        'notes':
            'Patient advised on home care. Instructed to report any worsening symptoms.',
        'visitType': ['New', 'Follow-up', 'Emergency', 'Routine'][i % 4],
      });
    }

    // On web, insert directly to Firestore
    try {
      final firestore = getFirestoreInstance();
      int inserted = 0;

      for (var sample in samples) {
        try {
          await firestore
              .collection('checkup_records')
              .doc(sample['id'])
              .set(sample);
          inserted++;
        } catch (e) {
          debugPrint('Error inserting sample checkup ${sample['id']}: $e');
        }
      }

      debugPrint(
        '✅ Successfully seeded $inserted sample checkup records to Firestore',
      );
    } catch (e) {
      debugPrint('❌ Error seeding checkup data: $e');
      rethrow;
    }
  }

  // Close database
  Future close() async {
    // No database to close on web
    if (kIsWeb) return;

    final db = await database;
    db.close();
  }
}
