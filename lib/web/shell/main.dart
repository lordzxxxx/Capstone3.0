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

// Custom Color Palette
const Color _primaryAqua = Color(0xFF8ED7DA);
const Color _secondaryIceBlue = Color(0xFFC6D4E1);
const Color _darkDeepTeal = Color(0xFF0E2F34);
const Color _mutedCoolGray = Color(0xFF8A8FA3);
const Color _lightOffWhite = Color(0xFFF1F1EE);

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
      title: 'Health Monitoring System',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.light(
          primary: _primaryAqua,
          onPrimary: _darkDeepTeal,
          secondary: _secondaryIceBlue,
          onSecondary: _darkDeepTeal,
          surface: _lightOffWhite,
          onSurface: _darkDeepTeal,
          outline: _mutedCoolGray,
          outlineVariant: _mutedCoolGray,
          error: const Color(0xFFD32F2F),
          onError: Colors.white,
        ),
        scaffoldBackgroundColor: _lightOffWhite,
        appBarTheme: AppBarTheme(
          backgroundColor: _darkDeepTeal,
          foregroundColor: _lightOffWhite,
          elevation: 0,
          centerTitle: false,
          toolbarHeight: 70,
          iconTheme: const IconThemeData(color: _lightOffWhite),
          titleTextStyle: const TextStyle(
            color: _lightOffWhite,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: _primaryAqua,
            foregroundColor: _darkDeepTeal,
            elevation: 2,
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            textStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: _primaryAqua,
            side: const BorderSide(color: _primaryAqua, width: 2),
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            textStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: _primaryAqua,
            textStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          margin: const EdgeInsets.all(8),
        ),
        inputDecorationTheme: InputDecorationTheme(
          fillColor: Colors.white,
          filled: true,
          contentPadding: const EdgeInsets.symmetric(
            vertical: 16,
            horizontal: 16,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _mutedCoolGray),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _mutedCoolGray),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _primaryAqua, width: 2),
          ),
          labelStyle: const TextStyle(color: _darkDeepTeal),
          hintStyle: const TextStyle(color: _mutedCoolGray),
          prefixIconColor: _mutedCoolGray,
          suffixIconColor: _mutedCoolGray,
        ),
        textTheme: const TextTheme(
          displayLarge: TextStyle(
            color: _darkDeepTeal,
            fontSize: 32,
            fontWeight: FontWeight.bold,
          ),
          displayMedium: TextStyle(
            color: _darkDeepTeal,
            fontSize: 28,
            fontWeight: FontWeight.bold,
          ),
          displaySmall: TextStyle(
            color: _darkDeepTeal,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
          headlineMedium: TextStyle(
            color: _darkDeepTeal,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
          headlineSmall: TextStyle(
            color: _darkDeepTeal,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
          titleLarge: TextStyle(
            color: _darkDeepTeal,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
          titleMedium: TextStyle(
            color: _darkDeepTeal,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
          bodyLarge: TextStyle(color: _darkDeepTeal, fontSize: 16),
          bodyMedium: TextStyle(color: _darkDeepTeal, fontSize: 14),
          bodySmall: TextStyle(color: _mutedCoolGray, fontSize: 12),
          labelSmall: TextStyle(color: _mutedCoolGray, fontSize: 11),
        ),
        bottomNavigationBarTheme: BottomNavigationBarThemeData(
          backgroundColor: _darkDeepTeal,
          selectedItemColor: _primaryAqua,
          unselectedItemColor: _secondaryIceBlue,
          elevation: 8,
          type: BottomNavigationBarType.fixed,
        ),
        floatingActionButtonTheme: FloatingActionButtonThemeData(
          backgroundColor: _primaryAqua,
          foregroundColor: _darkDeepTeal,
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        dividerColor: _mutedCoolGray,
        iconTheme: const IconThemeData(color: _darkDeepTeal),
      ),
      home: const LandingPage(),
      getPages: [
        GetPage(name: '/', page: () => const LandingPage()),
        GetPage(name: '/checkups', page: () => const CheckUpPage()),
        GetPage(name: '/prenatal', page: () => const PrenatalPage()),
        GetPage(name: '/morbidity', page: () => const MorbidityPage()),
        GetPage(name: '/mortality', page: () => const MortalityPage()),
      ],
    );
  }
}
