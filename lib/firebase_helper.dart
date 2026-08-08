import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';

const String kFirestoreDatabaseId = 'capstone-c98f9';
const String kRealtimeDatabaseUrl =
  'https://capstone-c98f9-default-rtdb.asia-southeast1.firebasedatabase.app';

/// Helper to get the correct Firestore instance with the proper database ID.
///
/// For the capstone project, the database ID is 'capstone-c98f9' (not 'default').
/// This ensures all Firestore operations use the correct database.
FirebaseFirestore getFirestoreInstance() {
  // Always specify the database ID for both web and mobile
  return FirebaseFirestore.instanceFor(
    app: Firebase.app(),
    databaseId: kFirestoreDatabaseId,
  );
}

FirebaseDatabase getRealtimeDatabaseInstance() {
  return FirebaseDatabase.instanceFor(
    app: Firebase.app(),
    databaseURL: kRealtimeDatabaseUrl,
  );
}
