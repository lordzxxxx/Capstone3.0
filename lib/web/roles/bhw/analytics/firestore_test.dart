import 'package:firebase_auth/firebase_auth.dart';
import 'package:mycapstone_project/firebase_helper.dart';

/// Test function to verify Firestore connection and write capability
Future<void> testFirestoreConnection() async {
  print('\n========================================');
  print('🧪 FIRESTORE CONNECTION TEST');
  print('========================================\n');

  // 1. Check Firebase initialization
  print('1️⃣ Checking Firebase initialization...');
  try {
    getFirestoreInstance();
    print('   ✅ Firestore instance created successfully');
    print('   📍 Database ID: capstone-c98f9');
  } catch (e) {
    print('   ❌ Failed to get Firestore instance: $e');
    return;
  }

  // 2. Check authentication
  print('\n2️⃣ Checking authentication status...');
  final currentUser = FirebaseAuth.instance.currentUser;
  if (currentUser != null) {
    print('   ✅ User is authenticated');
    print('   👤 User ID: ${currentUser.uid}');
    print('   📧 Email: ${currentUser.email}');
  } else {
    print('   ⚠️  No user is logged in');
    print('   💡 Note: If using authenticated rules, you must log in first');
    print('   ⏭️  Skipping write test until after authentication');
    return;
  }

  // 3. Try to write a test document
  print('\n3️⃣ Attempting to write test document...');
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

    print('   📝 Writing to collection: checkup_records');
    print('   🆔 Document ID: $testId');

    final startTime = DateTime.now();
    await getFirestoreInstance()
        .collection('checkup_records')
        .doc(testId)
        .set(testData);
    final elapsed = DateTime.now().difference(startTime).inMilliseconds;

    print('   ✅ Write successful! (${elapsed}ms)');
    print('   📍 Document path: checkup_records/$testId');
  } on FirebaseException catch (e) {
    print('   ❌ Firebase error: ${e.code}');
    print('   💬 Message: ${e.message}');

    if (e.code == 'permission-denied') {
      print('\n   🔒 PERMISSION DENIED!');
      print('   Fix: Update your Firestore security rules at:');
      print(
        '   🔗 https://console.firebase.google.com/project/capstone-c98f9/firestore/rules',
      );
      print('\n   Option 1 (Development - allows all access):');
      print('   ----------------------------------------');
      print('   rules_version = \'2\';');
      print('   service cloud.firestore {');
      print('     match /databases/{database}/documents {');
      print('       match /{document=**} {');
      print('         allow read, write: if true;');
      print('       }');
      print('     }');
      print('   }');
    }
    return;
  } catch (e) {
    print('   ❌ Unexpected error: $e');
    print('   Type: ${e.runtimeType}');
    return;
  }

  // 4. Try to read the document back
  print('\n4️⃣ Attempting to read test document back...');
  try {
    final snapshot = await getFirestoreInstance()
        .collection('checkup_records')
        .where('testRecord', isEqualTo: true)
        .limit(5)
        .get();

    print('   ✅ Read successful!');
    print('   📊 Found ${snapshot.docs.length} test record(s)');

    if (snapshot.docs.isNotEmpty) {
      print('\n   📄 Most recent test record:');
      final doc = snapshot.docs.first;
      print('   - ID: ${doc.id}');
      print('   - Patient: ${doc.data()['patient']}');
      print('   - DateTime: ${doc.data()['datetime']}');
    }
  } catch (e) {
    print('   ❌ Read error: $e');
  }

  // 5. Check all checkup_records
  print('\n5️⃣ Counting all checkup_records in Firestore...');
  try {
    final snapshot = await getFirestoreInstance()
        .collection('checkup_records')
        .get();

    print('   ✅ Collection accessed successfully');
    print('   📊 Total documents in checkup_records: ${snapshot.docs.length}');

    if (snapshot.docs.isNotEmpty) {
      print('\n   📋 Recent records:');
      for (var doc in snapshot.docs.take(5)) {
        final data = doc.data();
        print('   - ${doc.id}: ${data['patient']} (${data['datetime']})');
      }
    }
  } catch (e) {
    print('   ❌ Error counting records: $e');
  }

  print('\n========================================');
  print('✅ TEST COMPLETE');
  print('========================================\n');

  print('Next steps:');
  print('1. Check the Firebase Console at:');
  print(
    '   https://console.firebase.google.com/project/capstone-c98f9/firestore/data',
  );
  print(
    '2. Make sure you selected the "capstone-c98f9" database (not "default")',
  );
  print('3. Look for the "checkup_records" collection');
  print('4. You should see documents with timestamps\n');
}
