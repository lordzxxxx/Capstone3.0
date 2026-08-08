import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:mycapstone_project/firebase_helper.dart';
import 'package:mycapstone_project/shared/user_access_scope.dart';
import 'package:mycapstone_project/web/shared/services/user_access_scope_service.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;
  bool _connectivityListenerStarted = false;
  bool _isConnectivitySyncRunning = false;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('checkup_records.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 6,
      onCreate: _createDB,
      onUpgrade: _onUpgrade,
    );
  }

  Future _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      try {
        await db.execute(
          'ALTER TABLE checkup_records ADD COLUMN diseaseType TEXT DEFAULT "General"',
        );
      } catch (e) {
        print('Error adding diseaseType column: $e');
      }
    }

    if (oldVersion < 3) {
      // Add new columns for version 3
      try {
        await db.execute('ALTER TABLE checkup_records ADD COLUMN address TEXT');
      } catch (e) {
        print('Error adding address column: $e');
      }

      try {
        await db.execute(
          'ALTER TABLE checkup_records ADD COLUMN vitalsigns TEXT',
        );
      } catch (e) {
        print('Error adding vitalsigns column: $e');
      }

      try {
        await db.execute(
          'ALTER TABLE checkup_records ADD COLUMN symptoms TEXT',
        );
      } catch (e) {
        print('Error adding symptoms column: $e');
      }

      try {
        await db.execute(
          'ALTER TABLE checkup_records ADD COLUMN followup TEXT',
        );
      } catch (e) {
        print('Error adding followup column: $e');
      }

      try {
        await db.execute('ALTER TABLE checkup_records ADD COLUMN age TEXT');
      } catch (e) {
        print('Error adding age column: $e');
      }
    }

    if (oldVersion < 4) {
      // Recreate table without NOT NULL constraints for version 4
      try {
        // Create a temporary table with new schema
        await db.execute('''
          CREATE TABLE checkup_records_new (
            id TEXT PRIMARY KEY,
            datetime TEXT,
            type TEXT,
            diseaseType TEXT DEFAULT 'General',
            patient TEXT,
            details TEXT,
            plan TEXT,
            status TEXT,
            address TEXT,
            vitalsigns TEXT,
            symptoms TEXT,
            followup TEXT,
            age TEXT,
            synced INTEGER DEFAULT 0
          )
        ''');

        // Copy existing data
        await db.execute('''
          INSERT INTO checkup_records_new 
          SELECT id, datetime, type, diseaseType, patient, details, plan, status,
                 address, vitalsigns, symptoms, followup, age, synced
          FROM checkup_records
        ''');

        // Drop old table
        await db.execute('DROP TABLE checkup_records');

        // Rename new table
        await db.execute(
          'ALTER TABLE checkup_records_new RENAME TO checkup_records',
        );

        print('✅ Database upgraded to version 4: Removed NOT NULL constraints');
      } catch (e) {
        print('Error upgrading to version 4: $e');
      }
    }

    if (oldVersion < 5) {
      // Add new columns for version 5
      try {
        await db.execute(
          'ALTER TABLE checkup_records ADD COLUMN createdBy TEXT',
        );
      } catch (e) {
        print('Error adding createdBy column: $e');
      }

      try {
        await db.execute(
          'ALTER TABLE checkup_records ADD COLUMN testRecord INTEGER DEFAULT 0',
        );
      } catch (e) {
        print('Error adding testRecord column: $e');
      }
    }

    if (oldVersion < 6) {
      // Add AI classification columns for version 6
      try {
        await db.execute(
          'ALTER TABLE checkup_records ADD COLUMN ai_category TEXT',
        );
      } catch (e) {
        print('Error adding ai_category column: $e');
      }

      try {
        await db.execute(
          'ALTER TABLE checkup_records ADD COLUMN ai_severity TEXT',
        );
      } catch (e) {
        print('Error adding ai_severity column: $e');
      }

      try {
        await db.execute(
          'ALTER TABLE checkup_records ADD COLUMN ai_confidence TEXT',
        );
      } catch (e) {
        print('Error adding ai_confidence column: $e');
      }

      try {
        await db.execute(
          'ALTER TABLE checkup_records ADD COLUMN ai_method TEXT',
        );
      } catch (e) {
        print('Error adding ai_method column: $e');
      }

      try {
        await db.execute(
          'ALTER TABLE checkup_records ADD COLUMN ai_keywords TEXT',
        );
      } catch (e) {
        print('Error adding ai_keywords column: $e');
      }

      try {
        await db.execute(
          'ALTER TABLE checkup_records ADD COLUMN ai_recovery_plan TEXT',
        );
      } catch (e) {
        print('Error adding ai_recovery_plan column: $e');
      }

      print(
        '✅ Database upgraded to version 6: Added AI classification columns',
      );
    }
  }

  Future _createDB(Database db, int version) async {
    const idType = 'TEXT PRIMARY KEY';
    const textType = 'TEXT';
    const intType = 'INTEGER';

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
        address TEXT,
        vitalsigns TEXT,
        symptoms TEXT,
        followup TEXT,
        age TEXT,
        createdBy TEXT,
        testRecord $intType DEFAULT 0,
        synced $intType DEFAULT 0,
        ai_category TEXT,
        ai_severity TEXT,
        ai_confidence TEXT,
        ai_method TEXT,
        ai_keywords TEXT,
        ai_recovery_plan TEXT
      )
    ''');
  }

  String _normalizeScopeCode(String value) {
    return value.trim().toUpperCase();
  }

  Map<String, dynamic> _applyAccessScopeToFirestoreData(
    Map<String, dynamic> source,
    UserAccessScope accessScope, {
    String? currentUserId,
  }) {
    final scoped = Map<String, dynamic>.from(source);
    final scopeCode = _normalizeScopeCode(accessScope.barangayCode);
    final scopeBarangay = accessScope.barangay.trim();
    final scopeDistrict = accessScope.barangayDistrict.trim();

    if (scopeCode.isNotEmpty) {
      scoped['barangayCode'] = scopeCode;
    }
    if (scopeBarangay.isNotEmpty) {
      scoped['barangay'] = scopeBarangay;
    }
    if (scopeDistrict.isNotEmpty) {
      scoped['barangayDistrict'] = scopeDistrict;
    }

    if ((scoped['createdBy'] ?? '').toString().trim().isEmpty &&
        currentUserId != null &&
        currentUserId.isNotEmpty) {
      scoped['createdBy'] = currentUserId;
    }

    return scoped;
  }

  Future<List<Map<String, dynamic>>> _loadRemoteScopedRecords(
    UserAccessScope accessScope,
  ) async {
    final firestore = getFirestoreInstance();
    final merged = <String, Map<String, dynamic>>{};

    Future<void> collect(
      String source,
      Query<Map<String, dynamic>> query,
    ) async {
      try {
        final snapshot = await query.get();
        for (final doc in snapshot.docs) {
          merged[doc.id] = {
            ...Map<String, dynamic>.from(doc.data()),
            'id': doc.id,
          };
        }
      } catch (e) {
        print('Skipping $source query: $e');
      }
    }

    if (accessScope.canViewAllBarangays) {
      await collect(
        'collectionGroup',
        firestore.collectionGroup('checkup_records'),
      );
      return merged.values.toList(growable: false);
    }

    final rawScopeCode = accessScope.barangayCode.trim();
    final normalizedScopeCode = _normalizeScopeCode(rawScopeCode);
    final scopeBarangay = accessScope.barangay.trim();

    if (normalizedScopeCode.isNotEmpty) {
      await collect(
        'nested normalized barangayCode',
        firestore
            .collection('barangays')
            .doc(normalizedScopeCode)
            .collection('checkup_records'),
      );
    }

    if (rawScopeCode.isNotEmpty && rawScopeCode != normalizedScopeCode) {
      await collect(
        'nested raw barangayCode',
        firestore
            .collection('barangays')
            .doc(rawScopeCode)
            .collection('checkup_records'),
      );
    }

    if (normalizedScopeCode.isEmpty && scopeBarangay.isNotEmpty) {
      String resolvedCode = '';

      try {
        final snapshot = await firestore
            .collection('barangays')
            .where('barangay', isEqualTo: scopeBarangay)
            .limit(1)
            .get();
        if (snapshot.docs.isNotEmpty) {
          final doc = snapshot.docs.first;
          resolvedCode = _normalizeScopeCode(
            (doc.data()['barangayCode'] ?? doc.id).toString(),
          );
        }
      } catch (e) {
        print('Skipping barangay code lookup by barangay: $e');
      }

      if (resolvedCode.isEmpty) {
        try {
          final snapshot = await firestore
              .collection('barangays')
              .where('name', isEqualTo: scopeBarangay)
              .limit(1)
              .get();
          if (snapshot.docs.isNotEmpty) {
            final doc = snapshot.docs.first;
            resolvedCode = _normalizeScopeCode(
              (doc.data()['barangayCode'] ?? doc.id).toString(),
            );
          }
        } catch (e) {
          print('Skipping barangay code lookup by name: $e');
        }
      }

      if (resolvedCode.isNotEmpty) {
        await collect(
          'nested resolved barangayCode',
          firestore
              .collection('barangays')
              .doc(resolvedCode)
              .collection('checkup_records'),
        );
      }
    }

    return merged.values.toList(growable: false);
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
        final recordWithId = {...record, 'id': id};
        await getFirestoreInstance()
            .collection('checkup_records')
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

    // Convert ai_recovery_plan from Map to JSON string for SQLite
    final recordForDb = Map<String, dynamic>.from(record);
    if (recordForDb['ai_recovery_plan'] is Map) {
      recordForDb['ai_recovery_plan'] = jsonEncode(
        recordForDb['ai_recovery_plan'],
      );
    }

    final recordWithId = {...recordForDb, 'id': id, 'synced': 0};

    // Save to local database first
    await db.insert(
      'checkup_records',
      recordWithId,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    // If online, immediately save to Firestore
    if (hasInternet) {
      try {
        final firestoreData = Map<String, dynamic>.from(recordWithId);
        firestoreData.remove('synced'); // Don't save synced flag to Firestore

        UserAccessScope accessScope = UserAccessScope.unauthenticated;
        try {
          accessScope = await UserAccessScopeService.instance
              .loadCurrentScope();
        } catch (_) {}

        final scopedData = _applyAccessScopeToFirestoreData(
          firestoreData,
          accessScope,
          currentUserId: FirebaseAuth.instance.currentUser?.uid,
        );

        await getFirestoreInstance()
            .collection('checkup_records')
            .doc(id)
            .set(scopedData);

        await db.update(
          'checkup_records',
          {'synced': 1},
          where: 'id = ?',
          whereArgs: [id],
        );

        print('✅ Record $id saved to Firestore immediately');
      } catch (e) {
        print('⚠️ Failed to save to Firestore, will retry later: $e');
        // Mark as unsynced so it will retry later
        await db.update(
          'checkup_records',
          {'synced': 0},
          where: 'id = ?',
          whereArgs: [id],
        );
      }
    } else {
      print('📴 Offline: Record $id saved locally, will sync when online');
    }

    return id;
  }

  // Get real-time stream of records (for live updates)
  Stream<List<Map<String, dynamic>>> getRecordsStream() {
    // On web, use Firestore real-time listener
    if (kIsWeb) {
      return getFirestoreInstance()
          .collection('checkup_records')
          .orderBy('datetime', descending: true)
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
    // This is a simple implementation - for better real-time sync,
    // you might want to use Firestore snapshots and merge with local data
    return Stream.periodic(const Duration(seconds: 2)).asyncMap((_) async {
      return await getAllRecords();
    });
  }

  // Get all records (one-time fetch)
  Future<List<Map<String, dynamic>>> getAllRecords() async {
    // On web, use Firebase directly
    if (kIsWeb) {
      try {
        final snapshot = await getFirestoreInstance()
            .collection('checkup_records')
            .orderBy('datetime', descending: true)
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
    final result = await db.query('checkup_records', orderBy: 'datetime DESC');

    return result.map((record) {
      final map = Map<String, dynamic>.from(record);
      map.remove('synced'); // Remove synced flag from UI data

      // Decode ai_recovery_plan from JSON string to Map
      if (map['ai_recovery_plan'] is String &&
          (map['ai_recovery_plan'] as String).isNotEmpty) {
        try {
          map['ai_recovery_plan'] = jsonDecode(map['ai_recovery_plan']);
        } catch (e) {
          // Silently provide a safe default recovery plan format
          map['ai_recovery_plan'] = {
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
        }
      }

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
            .collection('checkup_records')
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
    final recordForDb = Map<String, dynamic>.from(record);
    if (recordForDb['ai_recovery_plan'] is Map) {
      recordForDb['ai_recovery_plan'] = jsonEncode(
        recordForDb['ai_recovery_plan'],
      );
    }
    final updatedRecord = {
      ...recordForDb,
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
        await getFirestoreInstance()
            .collection('checkup_records')
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
        print('Error deleting from Firebase: $e');
      }
    }

    return await db.delete('checkup_records', where: 'id = ?', whereArgs: [id]);
  }

  // Delete multiple records
  Future<void> deleteRecords(List<String> ids) async {
    // On web, delete directly from Firebase
    if (kIsWeb) {
      for (String id in ids) {
        try {
          await getFirestoreInstance()
              .collection('checkup_records')
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
    // On web, data is already in Firebase
    if (kIsWeb) return;

    try {
      final connectivityResult = await Connectivity().checkConnectivity();
      if (connectivityResult.contains(ConnectivityResult.none)) {
        print('No internet connection. Will sync later.');
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

          UserAccessScope accessScope = UserAccessScope.unauthenticated;
          try {
            accessScope = await UserAccessScopeService.instance
                .loadCurrentScope();
          } catch (_) {}

          final scopedData = _applyAccessScopeToFirestoreData(
            recordData,
            accessScope,
            currentUserId: FirebaseAuth.instance.currentUser?.uid,
          );

          await getFirestoreInstance()
              .collection('checkup_records')
              .doc(id)
              .set(scopedData, SetOptions(merge: true));

          // Mark as synced
          await db.update(
            'checkup_records',
            {'synced': 1},
            where: 'id = ?',
            whereArgs: [id],
          );

          print('Synced record: $id');
        } catch (e) {
          print('Error syncing record: $e');
        }
      }
    } catch (e) {
      print('Error during sync: $e');
    }
  }

  // Pull data from Firebase (for initial sync or when logging in)
  Future<void> syncFromFirebase() async {
    // On web, data is already from Firebase
    if (kIsWeb) return;

    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        print('No authenticated user. Skipping Firebase sync.');
        return;
      }

      final accessScope = await UserAccessScopeService.instance
          .loadCurrentScope();
      if (!accessScope.isAuthenticated) {
        print('No authenticated access scope. Skipping Firebase sync.');
        return;
      }
      if (!accessScope.canViewAllBarangays &&
          accessScope.barangayCode.trim().isEmpty &&
          accessScope.barangay.trim().isEmpty) {
        print('No barangay scope loaded. Skipping Firebase sync.');
        return;
      }

      final connectivityResult = await Connectivity().checkConnectivity();
      if (connectivityResult.contains(ConnectivityResult.none)) {
        print('No internet connection. Using offline data.');
        return;
      }

      final records = await _loadRemoteScopedRecords(accessScope);

      final db = await database;
      final tableColumns = await _getTableColumns(db, 'checkup_records');

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
          'checkup_records',
          insertData,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      print('Synced ${records.length} records from Firebase');
    } catch (e) {
      print('Error syncing from Firebase: $e');
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
    await db.delete('checkup_records');
  }

  // Start listening for connectivity changes
  void startConnectivityListener() {
    // On web, no need for sync listener
    if (kIsWeb || _connectivityListenerStarted) return;

    _connectivityListenerStarted = true;
    _runConnectivitySync();

    Connectivity().onConnectivityChanged.listen((result) async {
      if (!result.contains(ConnectivityResult.none)) {
        print('Internet connected! Syncing data...');
        await _runConnectivitySync();
      }
    });
  }

  // Migrate recovery plans from old UTF-8 format to safe ASCII format
  Future<void> migrateRecoveryPlans() async {
    if (kIsWeb) return; // Skip migration on web

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
        'checkup_records',
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
              'checkup_records',
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
          '✓ Migrated $migratedCount recovery plan records to ASCII-safe format',
        );
      }
    } catch (e) {
      // Migration is non-critical, silently fail
    }
  }

  // Seed 100 sample checkup records
  Future<void> seedSampleCheckupData() async {
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
      final rr = 16 + (i % 8); // Respiratory rate 16-24
      final o2 = 95 + (i % 5); // Oxygen saturation 95-99%
      final weight = 50 + (i % 35); // Weight 50-85 kg
      final height = 150 + (i % 35); // Height 150-185 cm

      // Always set followup date - 7 days after record date for consistency
      final followupDate = recordTime
          .add(const Duration(days: 7))
          .toString()
          .split(' ')[0];

      samples.add({
        'id': 'checkup_${random}_$i',
        'datetime': recordTime.toString(),
        'type': checkupTypes[i % checkupTypes.length],
        'diseaseType': diseaseTypes[i % diseaseTypes.length],
        'patient': patientNames[i % patientNames.length],
        'details':
            'Patient complained of $symp. Examined and treated accordingly.',
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
            'Temp: ${temp.toStringAsFixed(1)}°C | BP: $bp | HR: $hr bpm | RR: $rr brpm | O2: $o2% | Weight: $weight kg | Height: $height cm',
        'symptoms': symp,
        'followup': followupDate,
        'age': '${20 + (i * 3) % 60}',
        'createdBy': 'Healthcare Worker',
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
        'ai_keywords': '$symp, temperature, vital signs',
        'ai_recovery_plan':
            'Rest, hydration, and medication as prescribed. Monitor symptoms closely.',
        'synced': 1,
      });
    }

    // Insert all samples
    try {
      final db = await database;
      int inserted = 0;

      for (var sample in samples) {
        try {
          await db.insert(
            'checkup_records',
            sample,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          inserted++;
        } catch (e) {
          print('Error inserting sample checkup ${sample['id']}: $e');
        }
      }

      print('✅ Successfully seeded $inserted sample checkup records');

      // Sync to Firestore if online
      final connectivityResult = await Connectivity().checkConnectivity();
      if (!connectivityResult.contains(ConnectivityResult.none)) {
        try {
          final firestore = getFirestoreInstance();
          for (var sample in samples) {
            final firestoreData = Map<String, dynamic>.from(sample);
            firestoreData.remove('synced');
            await firestore
                .collection('checkup_records')
                .doc(sample['id'])
                .set(firestoreData);
          }
          print('✅ Synced sample checkup records to Firestore');
        } catch (e) {
          print('⚠️ Could not sync to Firestore: $e');
        }
      }
    } catch (e) {
      print('❌ Error seeding checkup data: $e');
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

  // Seed 100 sample communicable disease records
  Future<void> seedSampleCommunicableData() async {
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

    final List<String> communicableDiseases = [
      'Influenza',
      'COVID-19',
      'Dengue Fever',
      'Measles',
      'Chickenpox',
      'Common Cold',
      'Tuberculosis',
      'Pneumonia',
      'Whooping Cough',
      'Mumps',
      'Rubella',
      'Scarlet Fever',
      'Strep Throat',
      'Hepatitis A',
      'Hepatitis B',
      'Typhoid Fever',
      'Dysentery',
      'Cholera',
      'Leptospirosis',
      'Malaria',
      'Tick-Borne Fever',
      'Foodborne Illness',
      'Hand Foot and Mouth Disease',
      'Viral Gastroenteritis',
      'Bacterial Infection',
    ];

    final List<String> symptoms = [
      'High Fever',
      'Persistent Cough',
      'Difficulty Breathing',
      'Muscle Aches',
      'Loss of Taste/Smell',
      'Sore Throat',
      'Rash',
      'Joint Pain',
      'Body Weakness',
      'Headache',
      'Nausea and Vomiting',
      'Diarrhea',
      'Chills',
      'Fatigue',
      'Lymph Node Swelling',
      'Abdominal Pain',
      'Bleeding',
      'Conjunctivitis',
      'Skin Lesions',
      'Night Sweats',
    ];

    final List<String> statuses = [
      'Active Case',
      'Under Treatment',
      'Recovering',
      'Recovered',
      'Monitoring',
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

    final List<String> treatments = [
      'Antiviral medication and supportive care',
      'Antibiotics and rest',
      'Quarantine and monitoring',
      'Fever management and hydration',
      'Hospitalization if severe',
      'Specialized treatment protocol',
      'Contact tracing initiated',
      'Isolation precautions enforced',
    ];

    final samples = <Map<String, dynamic>>[];
    final random = DateTime.now().millisecondsSinceEpoch;

    for (int i = 0; i < 100; i++) {
      final daysAgo = i % 150; // Spread over 5 months
      final recordDate = DateTime.now().subtract(Duration(days: daysAgo));
      final recordTime = DateTime(
        recordDate.year,
        recordDate.month,
        recordDate.day,
        8 + (i % 9),
        (i * 7) % 60,
      );

      final disease = communicableDiseases[i % communicableDiseases.length];
      final symptom = symptoms[i % symptoms.length];
      final temp = 37.5 + (i % 3).toDouble();
      final bp = '${120 + (i % 20)}/${80 + (i % 15)}';
      final hr = 80 + (i % 40);

      samples.add({
        'id': 'communicable_${random}_$i',
        'datetime': recordTime.toString(),
        'type': 'Disease Investigation',
        'diseaseType': 'Communicable',
        'patient': patientNames[i % patientNames.length],
        'details':
            'Confirmed case of $disease. Patient presents with $symptom. Contact tracing status: ${i % 3 == 0
                ? "Completed"
                : i % 3 == 1
                ? "In Progress"
                : "Pending"}.',
        'plan': treatments[i % treatments.length],
        'status': statuses[i % statuses.length],
        'address': addresses[i % addresses.length],
        'vitalsigns':
            'Temp: ${temp.toStringAsFixed(1)}°C | BP: $bp | HR: $hr bpm',
        'symptoms': symptom,
        'followup': recordTime
            .add(Duration(days: 3 + (i % 5)))
            .toString()
            .split(' ')[0],
        'age': '${5 + (i * 2) % 75}',
        'createdBy': 'Disease Surveillance Officer',
        'ai_category': 'Communicable Disease',
        'ai_severity': ['Mild', 'Moderate', 'Severe', 'Critical'][(i % 4)],
        'ai_confidence': '${85 + (i % 15)}%',
        'ai_method': 'Epidemiological Analysis',
        'ai_keywords': '$disease, transmissible, isolation, contact tracing',
        'ai_recovery_plan':
            'Complete isolation protocol. Daily monitoring. Isolation to be lifted after negative test or 14 days symptom-free.',
        'synced': 1,
      });
    }

    try {
      final db = await database;
      int inserted = 0;

      for (var sample in samples) {
        try {
          await db.insert(
            'checkup_records',
            sample,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          inserted++;
        } catch (e) {
          print('Error inserting sample communicable ${sample['id']}: $e');
        }
      }

      print(
        '✅ Successfully seeded $inserted sample communicable disease records',
      );

      // Sync to Firestore if online
      final connectivityResult = await Connectivity().checkConnectivity();
      if (!connectivityResult.contains(ConnectivityResult.none)) {
        try {
          final firestore = getFirestoreInstance();
          for (var sample in samples) {
            final firestoreData = Map<String, dynamic>.from(sample);
            firestoreData.remove('synced');
            await firestore
                .collection('checkup_records')
                .doc(sample['id'])
                .set(firestoreData);
          }
          print('✅ Synced sample communicable disease records to Firestore');
        } catch (e) {
          print('⚠️ Could not sync to Firestore: $e');
        }
      }
    } catch (e) {
      print('❌ Error seeding communicable data: $e');
      rethrow;
    }
  }

  // Seed 100 sample non-communicable disease records
  Future<void> seedSampleNonCommunicableData() async {
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

    final List<String> nonCommunicableDiseases = [
      'Hypertension',
      'Type 2 Diabetes',
      'Coronary Heart Disease',
      'Stroke',
      'Asthma',
      'COPD',
      'Osteoarthritis',
      'Rheumatoid Arthritis',
      'Depression',
      'Anxiety Disorder',
      'Obesity',
      'Dyslipidemia',
      'Chronic Kidney Disease',
      'Liver Disease',
      'Thyroid Disease',
      'Parkinson\'s Disease',
      'Alzheimer\'s Disease',
      'Cancer',
      'Chronic Pain Syndrome',
      'GERD',
      'Inflammatory Bowel Disease',
      'Psoriasis',
      'Melanoma',
      'Type 1 Diabetes',
      'Osteoporosis',
    ];

    final List<String> symptoms = [
      'High Blood Pressure',
      'Elevated Blood Sugar',
      'Chest Pain',
      'Shortness of Breath',
      'Joint Pain',
      'Chronic Cough',
      'Weight Gain',
      'Persistent Fatigue',
      'Memory Problems',
      'Sleep Disorders',
      'Muscle Weakness',
      'Tremors',
      'Mood Swings',
      'Loss of Appetite',
      'Swelling in Legs',
      'Persistent Headache',
      'Skin Lesions',
      'Difficulty Walking',
      'Heart Palpitations',
      'Abdominal Bloating',
    ];

    final List<String> treatments = [
      'ACE inhibitor prescribed. Daily monitoring of BP required. Lifestyle modification recommended.',
      'Metformin and dietary management. Blood glucose monitoring at home.',
      'Statin therapy initiated. Cardiac rehab program recommended.',
      'Aspirin regimen and BP control. Speech therapy if needed.',
      'Inhaler medication. Pulmonary function tests scheduled.',
      'COPD management plan. Oxygen therapy assessment.',
      'Physical therapy and NSAIDs. Activity modification advised.',
      'Immunosuppressants and PT. Long-term disease management.',
      'Antidepressants and counseling. Follow-up in 2 weeks.',
      'Anxiolytic medication. Cognitive behavioral therapy recommended.',
      'Weight management program. Nutrition consultation scheduled.',
      'Cholesterol management. Dietary changes advised.',
      'Renal function monitoring. Nephrology referral pending.',
      'Hepatoprotective medications. Alcohol cessation advised.',
      'Thyroid hormone replacement. Regular TSH monitoring.',
      'Dopamine agonists. Neurological follow-up scheduled.',
      'Cognitive assessment. Memory care program.',
      'Oncology consultation. Treatment plan to be determined.',
      'Pain management therapy. Multidisciplinary approach.',
      'PPI medication. Dietary modifications.',
    ];

    final List<String> statuses = [
      'Stable',
      'Under Treatment',
      'Symptomatic',
      'Controlled',
      'Monitoring',
      'Recovering',
      'Needs Adjustment',
      'Well Managed',
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
      final daysAgo = i % 180; // Spread over 6 months
      final recordDate = DateTime.now().subtract(Duration(days: daysAgo));
      final recordTime = DateTime(
        recordDate.year,
        recordDate.month,
        recordDate.day,
        8 + (i % 9),
        (i * 7) % 60,
      );

      final disease =
          nonCommunicableDiseases[i % nonCommunicableDiseases.length];
      final symptom = symptoms[i % symptoms.length];
      final temp = 36.5 + (i % 1).toDouble();
      final bp = '${130 + (i % 40)}/${80 + (i % 25)}';
      final hr = 70 + (i % 30);
      final age = 40 + (i % 45);

      samples.add({
        'id': 'ncd_${random}_$i',
        'datetime': recordTime.toString(),
        'type': 'Chronic Disease Management',
        'diseaseType': 'Non-Communicable',
        'patient': patientNames[i % patientNames.length],
        'details':
            'Age: $age. Diagnosed with $disease. Current symptoms: $symptom. Disease duration: ${1 + (i % 20)} years.',
        'plan': treatments[i % treatments.length],
        'status': statuses[i % statuses.length],
        'address': addresses[i % addresses.length],
        'vitalsigns':
            'Temp: ${temp.toStringAsFixed(1)}°C | BP: $bp | HR: $hr bpm | BMI: ${18 + (i % 15)}',
        'symptoms': symptom,
        'followup': recordTime
            .add(Duration(days: 14 + (i % 30)))
            .toString()
            .split(' ')[0],
        'age': '$age',
        'createdBy': 'Healthcare Provider',
        'ai_category': [
          'Metabolic',
          'Cardiovascular',
          'Respiratory',
          'Mental Health',
          'Musculoskeletal',
        ][i % 5],
        'ai_severity': ['Low', 'Moderate', 'High', 'Critical'][(i % 4)],
        'ai_confidence': '${80 + (i % 18)}%',
        'ai_method': 'Clinical Assessment and Risk Stratification',
        'ai_keywords':
            '$disease, chronic, long-term management, comorbidity screening',
        'ai_recovery_plan':
            'Long-term disease management with regular follow-ups. Lifestyle modifications including diet, exercise, and medication compliance. Monitor for complications. Annual comprehensive screening.',
        'synced': 1,
      });
    }

    try {
      final db = await database;
      int inserted = 0;

      for (var sample in samples) {
        try {
          await db.insert(
            'checkup_records',
            sample,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          inserted++;
        } catch (e) {
          print('Error inserting sample non-communicable ${sample['id']}: $e');
        }
      }

      print(
        '✅ Successfully seeded $inserted sample non-communicable disease records',
      );

      // Sync to Firestore if online
      final connectivityResult = await Connectivity().checkConnectivity();
      if (!connectivityResult.contains(ConnectivityResult.none)) {
        try {
          final firestore = getFirestoreInstance();
          for (var sample in samples) {
            final firestoreData = Map<String, dynamic>.from(sample);
            firestoreData.remove('synced');
            await firestore
                .collection('checkup_records')
                .doc(sample['id'])
                .set(firestoreData);
          }
          print(
            '✅ Synced sample non-communicable disease records to Firestore',
          );
        } catch (e) {
          print('⚠️ Could not sync to Firestore: $e');
        }
      }
    } catch (e) {
      print('❌ Error seeding non-communicable data: $e');
      rethrow;
    }
  }
}
