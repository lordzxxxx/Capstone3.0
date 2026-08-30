import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:mycapstone_project/firebase_helper.dart';
import 'package:mycapstone_project/shared/barangay_scope_utils.dart';
import 'package:mycapstone_project/web/shared/services/user_access_scope_service.dart';

class PatientDatabaseHelper {
  static final PatientDatabaseHelper instance = PatientDatabaseHelper._init();
  static Database? _database;
  bool _connectivityListenerStarted = false;
  bool _isConnectivitySyncRunning = false;
  bool _isInboundSyncRunning = false;

  PatientDatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) {
      await _ensurePatientRecordsTable(_database!);
      return _database!;
    }
    _database = await _initDB('patient_records.db');
    await _ensurePatientRecordsTable(_database!);
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDB,
      onOpen: (db) async {
        await _ensurePatientRecordsTable(db);
      },
    );
  }

  Future<void> _ensurePatientRecordsTable(Database db) async {
    final existing = await db.query(
      'sqlite_master',
      columns: ['name'],
      where: 'type = ? AND name = ?',
      whereArgs: ['table', 'patient_records'],
      limit: 1,
    );

    if (existing.isEmpty) {
      await _createDB(db, 1);
    }
    await _ensureCanonicalColumns(db);
  }

  Future<void> _ensureCanonicalColumns(Database db) async {
    final columns = await db.rawQuery('PRAGMA table_info(patient_records)');
    final existing = columns
        .map((column) => column['name']?.toString() ?? '')
        .toSet();
    const canonicalColumns = <String>[
      'patientId',
      'fullName',
      'middleName',
      'address',
      'householdId',
      'guardian',
      'contactNumber',
      'emergencyContactName',
      'emergencyRelationship',
      'emergencyContactPhone',
      'emergencyContactAddress',
      'emergencyContact',
      'emergencyContactNumber',
      'medicalHistory',
    ];
    for (final column in canonicalColumns) {
      if (!existing.contains(column)) {
        await db.execute(
          "ALTER TABLE patient_records ADD COLUMN $column TEXT NOT NULL DEFAULT ''",
        );
      }
    }
  }

  static String generatePatientId([DateTime? value]) {
    final now = value ?? DateTime.now();
    String two(int number) => number.toString().padLeft(2, '0');
    final serial = now.millisecondsSinceEpoch
        .remainder(1000)
        .toString()
        .padLeft(3, '0');
    return 'PAT-${now.year}${two(now.month)}${two(now.day)}-${two(now.hour)}${two(now.minute)}${two(now.second)}-$serial';
  }

  Future _createDB(Database db, int version) async {
    const idType = 'TEXT PRIMARY KEY';
    const textType = 'TEXT NOT NULL';
    const intType = 'INTEGER NOT NULL';

    await db.execute('''
      CREATE TABLE IF NOT EXISTS patient_records (
        id $idType,
        firstName $textType,
        surname $textType,
        mothersMaidenName $textType,
        dateOfBirth $textType,
        age $textType,
        placeOfBirth $textType,
        nationality $textType,
        civilStatus $textType,
        gender $textType,
        religion $textType,
        occupation $textType,
        educationalAttainment $textType,
        employeeStatus $textType,
        phoneNumber $textType,
        emailAddress $textType,
        alternativePhone $textType,
        guardian $textType,
        street $textType,
        barangay $textType,
        municipality $textType,
        province $textType,
        height $textType,
        weight $textType,
        bmi $textType,
        bloodType $textType,
        allergies $textType,
        immunizationStatus $textType,
        familyMedicalHistory $textType,
        pastMedicalHistory $textType,
        currentMedications $textType,
        chronicConditions $textType,
        chiefComplaint $textType,
        currentSymptoms $textType,
        bodyTemperature $textType,
        temperatureUnit $textType,
        bpSystolic $textType,
        bpDiastolic $textType,
        heartRate $textType,
        respiratoryRate $textType,
        oxygenSaturation $textType,
        disability $textType,
        mentalHealthStatus $textType,
        substanceUseHistory $textType,
        lastCheckup $textType,
        nextCheckup $textType,
        emergencyContactName $textType,
        emergencyRelationship $textType,
        emergencyContactPhone $textType,
        emergencyContactAddress $textType,
        smokingStatus $textType,
        exerciseFrequency $textType,
        alcoholConsumption $textType,
        dietaryRestrictions $textType,
        mentalHealthStatusLifestyle $textType,
        sleepQuality $textType,
        morbidityRiskLevel $textType,
        numberOfComorbidities $textType,
        functionalStatus $textType,
        mobilityStatus $textType,
        frailtyIndex $textType,
        polypharmacyRisk $textType,
        preventiveCareCompliance $textType,
        healthLiteracyLevel $textType,
        socialSupportLevel $textType,
        economicStatusImpact $textType,
        morbidityNotes $textType,
        insuranceProvider $textType,
        insuranceNumber $textType,
        insuranceExpiry $textType,
        monthlyIncome $textType,
        additionalInfo $textType,
        educationLevel $textType,
        preferredLanguage $textType,
        referralSource $textType,
        transportation $textType,
        consentGiven $textType,
        registrationDate $textType,
        registeredBy $textType,
        additionalNotes $textType,
        status $textType,
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
        final recordWithId = _prepareRecordData(record, id);
        recordWithId.remove('synced'); // Remove synced field for web
        await getFirestoreInstance()
            .collection('patient_records')
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
    final recordWithId = _prepareRecordData(record, id);
    recordWithId['synced'] = 0;

    // Save to local database first
    await db.insert(
      'patient_records',
      recordWithId,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    // If online, immediately save to Firestore
    if (hasInternet) {
      try {
        final firestoreData = Map<String, dynamic>.from(recordWithId);
        firestoreData.remove('synced'); // Don't save synced flag to Firestore

        await getFirestoreInstance()
            .collection('patient_records')
            .doc(id)
            .set(firestoreData);

        await db.update(
          'patient_records',
          {'synced': 1},
          where: 'id = ?',
          whereArgs: [id],
        );

        print('✅ Patient record $id saved to Firestore immediately');
      } catch (e) {
        print('⚠️ Failed to save to Firestore, will retry later: $e');
        // Mark as unsynced so it will retry later
        await db.update(
          'patient_records',
          {'synced': 0},
          where: 'id = ?',
          whereArgs: [id],
        );
      }
    } else {
      print(
        '📴 Offline: Patient record $id saved locally, will sync when online',
      );
    }

    return id;
  }

  Map<String, dynamic> _prepareRecordData(
    Map<String, dynamic> record,
    String id,
  ) {
    final firstName = (record['firstName'] ?? '').toString().trim();
    final middleName = (record['middleName'] ?? '').toString().trim();
    final surname = (record['surname'] ?? '').toString().trim();
    final computedFullName = [firstName, middleName, surname]
        .where((s) => s.isNotEmpty)
        .join(' ');
    final fullName = (record['fullName'] ?? computedFullName).toString().trim();
    final address = (record['address'] ?? record['street'] ?? '').toString().trim();
    final contactNumber = (record['contactNumber'] ?? record['phoneNumber'] ?? record['phone'] ?? '').toString().trim();
    final emergencyContact = (record['emergencyContact'] ?? record['emergencyContactName'] ?? '').toString().trim();
    final emergencyContactNumber = (record['emergencyContactNumber'] ?? record['emergencyContactPhone'] ?? '').toString().trim();
    final medicalHistory = (record['medicalHistory'] ?? record['pastMedicalHistory'] ?? '').toString().trim();

    return {
      'id': id,
      'patientId': record['patientId'] ?? id,
      'fullName': fullName,
      'firstName': firstName,
      'middleName': middleName,
      'surname': surname,
      'address': address,
      'householdId': record['householdId'] ?? '',
      'contactNumber': contactNumber,
      'emergencyContact': emergencyContact,
      'emergencyContactNumber': emergencyContactNumber,
      'medicalHistory': medicalHistory,
      'mothersMaidenName': record['mothersMaidenName'] ?? '',
      'dateOfBirth': record['dateOfBirth'] ?? '',
      'age': record['age'] ?? '',
      'placeOfBirth': record['placeOfBirth'] ?? '',
      'nationality': record['nationality'] ?? '',
      'civilStatus': record['civilStatus'] ?? '',
      'gender': record['gender'] ?? '',
      'religion': record['religion'] ?? '',
      'occupation': record['occupation'] ?? '',
      'educationalAttainment': record['educationalAttainment'] ?? '',
      'employeeStatus': record['employeeStatus'] ?? '',
      'phoneNumber': record['phoneNumber'] ?? '',
      'emailAddress': record['emailAddress'] ?? '',
      'alternativePhone': record['alternativePhone'] ?? '',
      'guardian': record['guardian'] ?? '',
      'street': record['street'] ?? '',
      'barangay': record['barangay'] ?? '',
      'municipality': record['municipality'] ?? '',
      'province': record['province'] ?? '',
      'height': record['height'] ?? '',
      'weight': record['weight'] ?? '',
      'bmi': record['bmi'] ?? '',
      'bloodType': record['bloodType'] ?? '',
      'allergies': record['allergies'] ?? '',
      'immunizationStatus': record['immunizationStatus'] ?? '',
      'familyMedicalHistory': record['familyMedicalHistory'] ?? '',
      'pastMedicalHistory': record['pastMedicalHistory'] ?? '',
      'currentMedications': record['currentMedications'] ?? '',
      'chronicConditions': record['chronicConditions'] ?? '',
      'chiefComplaint': record['chiefComplaint'] ?? '',
      'currentSymptoms': record['currentSymptoms'] ?? '',
      'bodyTemperature': record['bodyTemperature'] ?? '',
      'temperatureUnit': record['temperatureUnit'] ?? '',
      'bpSystolic': record['bpSystolic'] ?? '',
      'bpDiastolic': record['bpDiastolic'] ?? '',
      'heartRate': record['heartRate'] ?? '',
      'respiratoryRate': record['respiratoryRate'] ?? '',
      'oxygenSaturation': record['oxygenSaturation'] ?? '',
      'disability': record['disability'] ?? '',
      'mentalHealthStatus': record['mentalHealthStatus'] ?? '',
      'substanceUseHistory': record['substanceUseHistory'] ?? '',
      'lastCheckup': record['lastCheckup'] ?? '',
      'nextCheckup': record['nextCheckup'] ?? '',
      'emergencyContactName': record['emergencyContactName'] ?? '',
      'emergencyRelationship': record['emergencyRelationship'] ?? '',
      'emergencyContactPhone': record['emergencyContactPhone'] ?? '',
      'emergencyContactAddress': record['emergencyContactAddress'] ?? '',
      'smokingStatus': record['smokingStatus'] ?? '',
      'exerciseFrequency': record['exerciseFrequency'] ?? '',
      'alcoholConsumption': record['alcoholConsumption'] ?? '',
      'dietaryRestrictions': record['dietaryRestrictions'] ?? '',
      'mentalHealthStatusLifestyle':
          record['mentalHealthStatusLifestyle'] ?? '',
      'sleepQuality': record['sleepQuality'] ?? '',
      'morbidityRiskLevel': record['morbidityRiskLevel'] ?? '',
      'numberOfComorbidities': record['numberOfComorbidities'] ?? '',
      'functionalStatus': record['functionalStatus'] ?? '',
      'mobilityStatus': record['mobilityStatus'] ?? '',
      'frailtyIndex': record['frailtyIndex'] ?? '',
      'polypharmacyRisk': record['polypharmacyRisk'] ?? '',
      'preventiveCareCompliance': record['preventiveCareCompliance'] ?? '',
      'healthLiteracyLevel': record['healthLiteracyLevel'] ?? '',
      'socialSupportLevel': record['socialSupportLevel'] ?? '',
      'economicStatusImpact': record['economicStatusImpact'] ?? '',
      'morbidityNotes': record['morbidityNotes'] ?? '',
      'insuranceProvider': record['insuranceProvider'] ?? '',
      'insuranceNumber': record['insuranceNumber'] ?? '',
      'insuranceExpiry': record['insuranceExpiry'] ?? '',
      'monthlyIncome': record['monthlyIncome'] ?? '',
      'additionalInfo': record['additionalInfo'] ?? '',
      'educationLevel': record['educationLevel'] ?? '',
      'preferredLanguage': record['preferredLanguage'] ?? '',
      'referralSource': record['referralSource'] ?? '',
      'transportation': record['transportation'] ?? '',
      'consentGiven': record['consentGiven'] ?? '',
      'registrationDate': record['registrationDate'] ?? '',
      'registeredBy': record['registeredBy'] ?? '',
      'additionalNotes': record['additionalNotes'] ?? '',
      'status': record['status'] ?? 'Active',
    };
  }

  // Get all records
  // Get real-time stream of records (for live updates)
  Stream<List<Map<String, dynamic>>> getRecordsStream() {
    // On web, use Firestore real-time listener
    if (kIsWeb) {
      return getFirestoreInstance()
          .collection('patient_records')
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
            .collection('patient_records')
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
      'patient_records',
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
        final updatedRecord = _prepareRecordData(record, id);
        updatedRecord.remove('synced');
        await getFirestoreInstance()
            .collection('patient_records')
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
    final updatedRecord = _prepareRecordData(record, id);
    updatedRecord['synced'] = 0; // Mark as unsynced after update

    final result = await db.update(
      'patient_records',
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
            .collection('patient_records')
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
      'patient_records',
      where: 'id = ?',
      whereArgs: [id],
    );

    if (record.isNotEmpty && record.first['synced'] == 1) {
      try {
        await getFirestoreInstance()
            .collection('patient_records')
            .doc(id)
            .delete();
      } catch (e) {
        print('Error deleting from Firebase: $e');
      }
    }

    return await db.delete('patient_records', where: 'id = ?', whereArgs: [id]);
  }

  // Delete multiple records
  Future<void> deleteRecords(List<String> ids) async {
    // On web, delete directly from Firebase
    if (kIsWeb) {
      for (String id in ids) {
        try {
          await getFirestoreInstance()
              .collection('patient_records')
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
        'patient_records',
        where: 'synced = ?',
        whereArgs: [0],
      );

      for (var record in unsyncedRecords) {
        try {
          final recordData = Map<String, dynamic>.from(record);
          recordData.remove('synced');

          await getFirestoreInstance()
              .collection('patient_records')
              .doc(record['id'] as String)
              .set(recordData);

          // Mark as synced
          await db.update(
            'patient_records',
            {'synced': 1},
            where: 'id = ?',
            whereArgs: [record['id']],
          );

          print('Synced patient record: ${record['id']}');
        } catch (e) {
          print('Error syncing patient record ${record['id']}: $e');
        }
      }
    } catch (e) {
      print('Error in sync process: $e');
    }
  }

  // Sync from Firebase to local
  Future<void> syncFromFirebase() async {
    if (kIsWeb || _isInboundSyncRunning) return;

    _isInboundSyncRunning = true;
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        print('No authenticated user. Skipping patient Firebase sync.');
        return;
      }

      final accessScope = await UserAccessScopeService.instance
          .loadCurrentScope();
      if (!accessScope.isAuthenticated) {
        print('No authenticated access scope. Skipping patient Firebase sync.');
        return;
      }
      if (!accessScope.canViewAllBarangays &&
          accessScope.barangayCode.trim().isEmpty &&
          accessScope.barangay.trim().isEmpty) {
        print('No barangay scope loaded. Skipping patient Firebase sync.');
        return;
      }

      final connectivityResult = await Connectivity().checkConnectivity();
      if (connectivityResult.contains(ConnectivityResult.none)) {
        print('No internet connection. Cannot sync from Firebase.');
        return;
      }

      final snapshot = await buildScopedRecordQuery(
        getFirestoreInstance(),
        'patient_records',
        accessScope,
      ).get();

      final records = snapshot.docs
          .map(materializeFirestoreRecord)
          .where((record) => recordMatchesAccessScope(record, accessScope))
          .toList(growable: false);

      final db = await database;
      final columnRows = await db.rawQuery(
        'PRAGMA table_info(patient_records)',
      );
      final sqliteColumns = columnRows
          .map((row) => row['name']?.toString())
          .whereType<String>()
          .toSet();

      for (final record in records) {
        final recordId = (record['id'] ?? record['patientId'] ?? '')
            .toString()
            .trim();
        if (recordId.isEmpty) continue;

        // Keep a local edit authoritative until the outbound sync succeeds.
        // This prevents a reconnect refresh from reverting an offline change.
        final local = await db.query(
          'patient_records',
          columns: const ['synced'],
          where: 'id = ?',
          whereArgs: [recordId],
          limit: 1,
        );
        if (local.isNotEmpty && local.first['synced'] == 0) continue;

        // Reuse the canonical local schema mapper so every NOT NULL column
        // receives a safe default, while unknown Firestore-only fields are
        // intentionally ignored.
        final data = _prepareRecordData(
          sanitizeRecordForSqlite(record),
          recordId,
        )..removeWhere((key, _) => !sqliteColumns.contains(key));
        data['synced'] = 1;

        await db.insert(
          'patient_records',
          data,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      print('Synced ${records.length} patient records from Firebase');
    } catch (e) {
      print('Error syncing from Firebase: $e');
    } finally {
      _isInboundSyncRunning = false;
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
    await db.delete('patient_records');
  }

  // Listen to connectivity changes
  void startConnectivityListener() {
    if (kIsWeb || _connectivityListenerStarted) return;

    _connectivityListenerStarted = true;
    _runConnectivitySync();

    Connectivity().onConnectivityChanged.listen((result) async {
      if (!result.contains(ConnectivityResult.none)) {
        print('Internet connection restored. Syncing patient data...');
        await _runConnectivitySync();
      }
    });
  }

  // Generate and insert 100 sample patient records
  Future<void> seedSamplePatientData() async {
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
      'Consuelo',
      'Enrique',
      'Emilia',
      'Ruben',
      'Leticia',
      'Hector',
      'Aurea',
      'Guillermo',
      'Florencia',
      'Vincent',
      'Veronica',
      'Victor',
      'Vanessa',
      'Valentin',
      'Valentina',
      'Vicente',
      'Violeta',
      'Walter',
      'Wanda',
      'Wilfredo',
      'Wilma',
      'Wendell',
      'Winifred',
      'Wesley',
      'Winona',
      'Xavier',
      'Xiomara',
      'Xander',
      'Xenia',
      'Xerxes',
      'Xiaowen',
      'Xochitl',
      'Xenia',
      'Yolanda',
      'Yasmin',
      'Yanira',
      'Yara',
      'Yolande',
      'Yaritza',
      'Yancy',
      'Yosef',
      'Zachary',
      'Zita',
      'Zoe',
      'Zandra',
      'Zabel',
      'Zabrina',
      'Zebulon',
      'Zeitgeist',
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
      'Aguirre',
      'Alvarez',
      'Ancheta',
      'Andaya',
      'Arellano',
      'Arenas',
      'Arguelles',
      'Arias',
      'Ariza',
      'Armada',
      'Armenteros',
      'Armijo',
      'Arnaiz',
      'Arnaldo',
      'Arnedo',
      'Arnejo',
      'Arnold',
      'Arpa',
      'Arranz',
      'Arratia',
      'Arreaga',
      'Arrebol',
      'Arrechederra',
      'Arrecido',
      'Arredondo',
      'Arreglado',
      'Arreglo',
      'Arregui',
      'Arrellano',
      'Arrelucea',
      'Arrellano',
      'Arreola',
      'Bacani',
      'Bacilio',
      'Balais',
      'Balbuena',
      'Balicao',
      'Balilo',
      'Ballesteros',
      'Balmes',
      'Bacud',
      'Badaro',
      'Baeta',
      'Bagon',
      'Bagtas',
      'Bahia',
      'Balaao',
      'Balador',
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

    final List<String> occupations = [
      'Farmer',
      'Teacher',
      'Nurse',
      'Driver',
      'Mechanic',
      'Carpenter',
      'Vendor',
      'Cook',
      'Domestic Helper',
      'Security Guard',
      'Factory Worker',
      'Laborer',
      'Businessperson',
      'Accountant',
      'Engineer',
      'Doctor',
      'Pharmacist',
      'Salesperson',
      'Retired',
      'Student',
      'Housewife',
      'OFW',
      'Contractor',
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

    final List<String> chronicConditions = [
      'Hypertension',
      'Diabetes',
      'Asthma',
      'COPD',
      'Heart Disease',
      'Arthritis',
      'None',
      'Thyroid Disease',
      'Kidney Disease',
      'Liver Disease',
      'Tuberculosis',
    ];

    final List<String> medications = [
      'Metformin',
      'Lisinopril',
      'Atorvastatin',
      'Aspirin',
      'Omeprazole',
      'Ibuprofen',
      'Amoxicillin',
      'Paracetamol',
      'None',
      'Albuterol',
    ];

    final List<String> allergyList = [
      'Penicillin',
      'Peanuts',
      'Shellfish',
      'Latex',
      'Sulfa',
      'Aspirin',
      'None',
      'Dust',
      'Pollen',
      'Dairy',
      'Iodine',
    ];

    final List<String> religions = [
      'Catholic',
      'Protestant',
      'Muslim',
      'INC',
      'Iglesia ni Cristo',
      'Jehovah\'s Witness',
      'None',
      'Buddhist',
      'Seventh Day Adventist',
      'Methodist',
    ];

    final List<String> municipalities = [
      'Rosario',
      'Kawit',
      'Noveleta',
      'Imus',
      'Dasmariñas',
      'Maragondon',
      'Magallanes',
      'Indang',
      'Silang',
      'Tagaytay',
      'Mendez',
      'Cavite City',
    ];

    final samples = <Map<String, dynamic>>[];
    final random = DateTime.now().millisecondsSinceEpoch;

    for (int i = 0; i < 100; i++) {
      final birthDate = DateTime(1940 + (i % 70), 1 + (i % 12), 1 + (i % 28));
      final age = DateTime.now().year - birthDate.year;
      final height = 145 + (i % 45);
      final weight = 45 + (i % 65);
      final bmi = (weight / ((height / 100) * (height / 100))).toStringAsFixed(
        1,
      );

      samples.add({
        'id': 'patient_${random}_$i',
        'firstName': firstNames[i % firstNames.length],
        'surname': surnames[i % surnames.length],
        'mothersMaidenName': surnames[(i + 1) % surnames.length],
        'dateOfBirth': birthDate.toString().split(' ')[0],
        'age': age.toString(),
        'placeOfBirth': municipalities[i % municipalities.length],
        'nationality': 'Filipino',
        'civilStatus': ['Single', 'Married', 'Widowed', 'Separated'][i % 4],
        'gender': i % 2 == 0 ? 'Male' : 'Female',
        'religion': religions[i % religions.length],
        'occupation': occupations[i % occupations.length],
        'educationalAttainment': [
          'Elementary',
          'High School',
          'College',
          'Vocational',
        ][i % 4],
        'employeeStatus': [
          'Employed',
          'Unemployed',
          'Self-Employed',
          'Retired',
        ][i % 4],
        'phoneNumber': '09${100000000 + i}',
        'emailAddress':
            '${firstNames[i % firstNames.length].toLowerCase()}$i@email.com',
        'alternativePhone': '09${200000000 + i}',
        'guardian': i > 50
            ? '${firstNames[(i + 5) % firstNames.length]} ${surnames[(i + 3) % surnames.length]}'
            : '',
        'street': 'Street ${i + 1}',
        'barangay': barangays[i % barangays.length],
        'municipality': municipalities[i % municipalities.length],
        'province': 'Cavite',
        'height': height.toString(),
        'weight': weight.toString(),
        'bmi': bmi,
        'bloodType': bloodTypes[i % bloodTypes.length],
        'allergies': allergyList[i % allergyList.length],
        'immunizationStatus': [
          'Complete',
          'Partial',
          'None',
          'Unknown',
        ][(i % 4)],
        'familyMedicalHistory': i % 3 == 0 ? 'Hypertension, Diabetes' : 'None',
        'pastMedicalHistory': i % 4 == 0
            ? 'Pneumonia (2022), Dengue (2021)'
            : 'None',
        'currentMedications': medications[i % medications.length],
        'chronicConditions': chronicConditions[i % chronicConditions.length],
        'chiefComplaint': [
          'Headache',
          'Cough',
          'Body Pain',
          'Fever',
          'Check-up',
          'None',
        ][i % 6],
        'currentSymptoms': i % 5 == 0 ? 'Mild cough, Low-grade fever' : 'None',
        'bodyTemperature': '${36.5 + (i % 2)}',
        'temperatureUnit': 'Celsius',
        'bpSystolic': '${120 + (i % 30)}',
        'bpDiastolic': '${80 + (i % 20)}',
        'heartRate': '${60 + (i % 40)}',
        'respiratoryRate': '${16 + (i % 8)}',
        'oxygenSaturation': '${95 + (i % 5)}',
        'disability': i % 10 == 0 ? 'PWD' : 'None',
        'mentalHealthStatus': [
          'Stable',
          'Stable',
          'Stable',
          'Mild Anxiety',
        ][i % 4],
        'substanceUseHistory': i % 8 == 0 ? 'Smoker' : 'Non-smoker',
        'lastCheckup': DateTime.now()
            .subtract(Duration(days: 30 + (i % 300)))
            .toString()
            .split(' ')[0],
        'nextCheckup': DateTime.now()
            .add(Duration(days: 30 + (i % 90)))
            .toString()
            .split(' ')[0],
        'emergencyContactName':
            '${firstNames[(i + 2) % firstNames.length]} ${surnames[(i + 1) % surnames.length]}',
        'emergencyRelationship': [
          'Spouse',
          'Child',
          'Parent',
          'Sibling',
          'Adjacent',
        ][i % 5],
        'emergencyContactPhone': '09${300000000 + i}',
        'emergencyContactAddress': 'Same Address',
        'smokingStatus': i % 7 == 0
            ? 'Active Smoker'
            : i % 7 == 1
            ? 'Former Smoker'
            : 'Non-smoker',
        'exerciseFrequency': [
          'Daily',
          'Thrice a Week',
          'Once a Week',
          'Rarely',
          'None',
        ][i % 5],
        'alcoholConsumption': [
          'None',
          'Social',
          'Occasional',
          'Regular',
        ][i % 4],
        'dietaryRestrictions': i % 6 == 0 ? 'No salt, Low sugar' : 'None',
        'mentalHealthStatusLifestyle': 'Stable',
        'sleepQuality': ['Good', 'Fair', 'Poor', 'Excellent'][i % 4],
        'morbidityRiskLevel': ['Low', 'Moderate', 'High'][i % 3],
        'numberOfComorbidities': (i % 4).toString(),
        'functionalStatus': [
          'Independent',
          'Needs Assistance',
          'Dependent',
        ][i % 3],
        'mobilityStatus': ['Ambulatory', 'Cane', 'Walker', 'Wheelchair'][i % 4],
        'frailtyIndex': '${(i % 10) * 0.1}',
        'polypharmacyRisk': i > 60 ? 'High' : 'Low',
        'preventiveCareCompliance': ['Good', 'Fair', 'Poor'][i % 3],
        'healthLiteracyLevel': ['High', 'Moderate', 'Low'][i % 3],
        'socialSupportLevel': ['Strong', 'Moderate', 'Weak'][i % 3],
        'economicStatusImpact': [
          'Low Impact',
          'Moderate Impact',
          'High Impact',
        ][i % 3],
        'morbidityNotes': 'Patient consultation notes - ${i + 1}',
        'insuranceProvider': i % 5 == 0
            ? 'PhilHealth'
            : i % 5 == 1
            ? 'Private Insurance'
            : 'None',
        'insuranceNumber': i % 5 == 0 ? 'PH${100000000 + i}' : '',
        'insuranceExpiry': DateTime.now()
            .add(Duration(days: 365))
            .toString()
            .split(' ')[0],
        'monthlyIncome': '${5000 + (i * 100) % 45000}',
        'additionalInfo': 'Additional notes for patient ${i + 1}',
        'educationLevel': [
          'Elementary',
          'High School',
          'Some College',
          'Bachelor',
          'Graduate',
        ][i % 5],
        'preferredLanguage': i % 7 == 0 ? 'English' : 'Tagalog',
        'referralSource': [
          'Walk-in',
          'Referral',
          'Follow-up',
          'Emergency',
        ][i % 4],
        'transportation': [
          'Walking',
          'Tricycle',
          'Jeepney',
          'Car',
          'Bus',
        ][i % 5],
        'consentGiven': 'Yes',
        'registrationDate': DateTime.now()
            .subtract(Duration(days: 365 - (i % 365)))
            .toString()
            .split(' ')[0],
        'registeredBy': 'System Admin',
        'additionalNotes': 'Sample patient record #${i + 1}',
        'status': i % 10 == 0 ? 'Inactive' : 'Active',
      });
    }

    // Insert all samples
    for (var sample in samples) {
      try {
        await insertRecord(sample);
      } catch (e) {
        print('Error inserting sample patient ${sample['id']}: $e');
      }
    }

    print('✅ Successfully seeded 100 sample patient records');
  }
}
