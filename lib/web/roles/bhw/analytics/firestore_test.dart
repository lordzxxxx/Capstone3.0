import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:mycapstone_project/firebase_helper.dart';

/// Test function to verify Firestore connection and write capability
Future<void> testFirestoreConnection() async {
  debugPrint('\n========================================');
  debugPrint('🧪 FIRESTORE CONNECTION TEST');
  debugPrint('========================================\n');

  // 1. Check Firebase initialization
  debugPrint('1️⃣ Checking Firebase initialization...');
  try {
    getFirestoreInstance();
    debugPrint('   ✅ Firestore instance created successfully');
    debugPrint('   📍 Database ID: capstone-c98f9');
  } catch (e) {
    debugPrint('   ❌ Failed to get Firestore instance: $e');
    return;
  }

  // 2. Check authentication
  debugPrint('\n2️⃣ Checking authentication status...');
  final currentUser = FirebaseAuth.instance.currentUser;
  if (currentUser != null) {
    debugPrint('   ✅ User is authenticated');
    debugPrint('   👤 User ID: ${currentUser.uid}');
    debugPrint('   📧 Email: ${currentUser.email}');
  } else {
    debugPrint('   ⚠️  No user is logged in');
    debugPrint(
      '   💡 Note: If using authenticated rules, you must log in first',
    );
    debugPrint('   ⏭️  Skipping write test until after authentication');
    return;
  }

  // 3. Try to write a test document
  debugPrint('\n3️⃣ Attempting to write test document...');
  try {
    final testId = 'test_${DateTime.now().millisecondsSinceEpoch}';
    final testData = {
      'id': testId,
      'datetime': DateTime.now().toIso8601String(),
      'type': 'TEST',
      'diseaseType': 'Test',
      'patient': 'Test Patient',
      'details': 'This is a test record',
      'plan': 'Test plan',
      'status': 'completed',
      'createdBy': currentUser.uid,
      'testRecord': true,
    };

    debugPrint('   📝 Writing to collection: checkup_records');
    debugPrint('   🆔 Document ID: $testId');

    final startTime = DateTime.now();
    await getFirestoreInstance()
        .collection('checkup_records')
        .doc(testId)
        .set(testData);
    final elapsed = DateTime.now().difference(startTime).inMilliseconds;

    debugPrint('   ✅ Write successful! (${elapsed}ms)');
    debugPrint('   📍 Document path: checkup_records/$testId');
  } on FirebaseException catch (e) {
    debugPrint('   ❌ Firebase error: ${e.code}');
    debugPrint('   💬 Message: ${e.message}');

    if (e.code == 'permission-denied') {
      debugPrint('\n   🔒 PERMISSION DENIED!');
      debugPrint('   Fix: Update your Firestore security rules at:');
      debugPrint(
        '   🔗 https://console.firebase.google.com/project/capstone-c98f9/firestore/rules',
      );
      debugPrint('\n   Option 1 (Development - allows all access):');
      debugPrint('   ----------------------------------------');
      debugPrint('   rules_version = \'2\';');
      debugPrint('   service cloud.firestore {');
      debugPrint('     match /databases/{database}/documents {');
      debugPrint('       match /{document=**} {');
      debugPrint('         allow read, write: if true;');
      debugPrint('       }');
      debugPrint('     }');
      debugPrint('   }');
    }
    return;
  } catch (e) {
    debugPrint('   ❌ Unexpected error: $e');
    debugPrint('   Type: ${e.runtimeType}');
    return;
  }

  // 4. Try to read the document back
  debugPrint('\n4️⃣ Attempting to read test document back...');
  try {
    final snapshot = await getFirestoreInstance()
        .collection('checkup_records')
        .where('testRecord', isEqualTo: true)
        .limit(5)
        .get();

    debugPrint('   ✅ Read successful!');
    debugPrint('   📊 Found ${snapshot.docs.length} test record(s)');

    if (snapshot.docs.isNotEmpty) {
      debugPrint('\n   📄 Most recent test record:');
      final doc = snapshot.docs.first;
      debugPrint('   - ID: ${doc.id}');
      debugPrint('   - Patient: ${doc.data()['patient']}');
      debugPrint('   - DateTime: ${doc.data()['datetime']}');
    }
  } catch (e) {
    debugPrint('   ❌ Read error: $e');
  }

  // 5. Check all checkup_records
  debugPrint('\n5️⃣ Counting all checkup_records in Firestore...');
  try {
    final snapshot = await getFirestoreInstance()
        .collection('checkup_records')
        .get();

    debugPrint('   ✅ Collection accessed successfully');
    debugPrint(
      '   📊 Total documents in checkup_records: ${snapshot.docs.length}',
    );

    if (snapshot.docs.isNotEmpty) {
      debugPrint('\n   📋 Recent records:');
      for (var doc in snapshot.docs.take(5)) {
        final data = doc.data();
        debugPrint('   - ${doc.id}: ${data['patient']} (${data['datetime']})');
      }
    }
  } catch (e) {
    debugPrint('   ❌ Error counting records: $e');
  }

  debugPrint('\n========================================');
  debugPrint('✅ TEST COMPLETE');
  debugPrint('========================================\n');

  debugPrint('Next steps:');
  debugPrint('1. Check the Firebase Console at:');
  debugPrint(
    '   https://console.firebase.google.com/project/capstone-c98f9/firestore/data',
  );
  debugPrint(
    '2. Make sure you selected the "capstone-c98f9" database (not "default")',
  );
  debugPrint('3. Look for the "checkup_records" collection');
  debugPrint('4. You should see documents with timestamps\n');
}
