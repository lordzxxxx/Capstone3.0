import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:get/get.dart';
import 'package:mycapstone_project/web/features/auth/landing.dart';
import 'package:mycapstone_project/web/roles/bhw/checkups/checkup.dart';
import 'package:mycapstone_project/web/roles/bhw/prenatal/prenatal.dart';
import 'package:mycapstone_project/web/roles/bhw/surveillance/morbidity.dart';
import 'package:mycapstone_project/web/roles/bhw/surveillance/mortality.dart';
import 'package:mycapstone_project/firebase_helper.dart';
import 'package:mycapstone_project/firebase_app_check_bootstrap.dart';
import 'package:mycapstone_project/web/shared/theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (kIsWeb) {
    // Firebase options for web
    await Firebase.initializeApp(
      options: const FirebaseOptions(
        apiKey: "AIzaSyCi_JVTayAfb5cjS1CuYvZeB8Q6HyxBWfY",
        authDomain: "capstone-c98f9.firebaseapp.com",
        projectId: "capstone-c98f9",
        databaseURL: "https://capstone-c98f9-default-rtdb.firebaseio.com",
        storageBucket: "capstone-c98f9.firebasestorage.app",
        messagingSenderId: "628319595773",
        appId: "1:628319595773:web:afe9520590fad2a3192294",
        measurementId: "G-DFQ4GMPTHP",
      ),
    );

    await activateFirebaseAppCheck();

    final firestore = getFirestoreInstance();
    firestore.settings = const Settings(
      persistenceEnabled: false,
      webExperimentalForceLongPolling: true,
      webExperimentalAutoDetectLongPolling: false,
    );
    await firestore.enableNetwork().timeout(const Duration(seconds: 6));
  } else {
    // Mobile platforms use google-services.json/GoogleService-Info.plist
    await Firebase.initializeApp();
    await activateFirebaseAppCheck();
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'AI-DSUHIS',
      theme: AppTheme.light(isWeb: true),
      home: const LandingPage(),
      getPages: [
        GetPage(name: '/aidsuhis', page: () => const LandingPage()),
        GetPage(name: '/', page: () => const LandingPage()),
        GetPage(name: '/checkups', page: () => const CheckUpPage()),
        GetPage(name: '/prenatal', page: () => const PrenatalPage()),
        GetPage(name: '/morbidity', page: () => const MorbidityPage()),
        GetPage(name: '/mortality', page: () => const MortalityPage()),
      ],
    );
  }
}
