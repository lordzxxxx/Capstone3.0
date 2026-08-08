import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:mycapstone_project/firebase_helper.dart';
import 'package:mycapstone_project/shared/barangay_scope_utils.dart';
import 'package:mycapstone_project/web/shared/services/user_access_scope_service.dart';

class BarangaySeedResult {
  final int recordCount;
  final String barangay;

  const BarangaySeedResult({required this.recordCount, required this.barangay});
}

/// Creates deterministic Firebase test records for the signed-in user's
/// assigned barangay. Owner-specific IDs prevent other datasets from being
/// overwritten.
class BarangayTestDataSeeder {
  BarangayTestDataSeeder._();

  static Future<BarangaySeedResult> seed() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('Sign in before seeding barangay test data.');
    }

    final firestore = getFirestoreInstance();
    final profileSnapshot = await firestore
        .collection('users')
        .doc(user.uid)
        .get();
    final profile = profileSnapshot.data() ?? <String, dynamic>{};
    final creatorName = _profileName(profile, user);

    final scope = await UserAccessScopeService.instance.loadCurrentScope(
      forceRefresh: true,
    );
    final barangayCode = normalizeStoredBarangayCode(scope.barangayCode);
    if (!scope.isAuthenticated || barangayCode.isEmpty) {
      throw StateError(
        'Your account must have an assigned barangay before data can be seeded.',
      );
    }

    final now = DateTime.now();
    final records = <String, List<Map<String, dynamic>>>{
      'patient_records': _patients(now),
      'checkup_records': [
        ..._checkups(now),
        ..._communicable(now),
        ..._nonCommunicable(now),
      ],
      'morbidity_records': _morbidity(now),
      'prenatal_records': _prenatal(now),
      'immunization_records': _immunization(now),
      'mortality_records': _mortality(now),
    };

    final batch = firestore.batch();
    var count = 0;
    for (final collectionEntry in records.entries) {
      for (var index = 0; index < collectionEntry.value.length; index++) {
        final id = 'barangay-test-${user.uid}-${collectionEntry.key}-$index';
        final scoped = applyBarangayScopeToRecord(<String, dynamic>{
          ...collectionEntry.value[index],
          'id': id,
          'createdBy': user.uid,
          'createdByUid': user.uid,
          'createdByName': creatorName,
          'isTestData': true,
          'testDataOwnerUid': user.uid,
          'createdAt': Timestamp.fromDate(now),
          'updatedAt': Timestamp.fromDate(now),
        }, accessScope: scope);
        final reference = firestore
            .collection('barangays')
            .doc(barangayCode)
            .collection(collectionEntry.key)
            .doc(id);
        batch.set(reference, scoped, SetOptions(merge: true));
        count++;
      }
    }

    await batch.commit();
    return BarangaySeedResult(
      recordCount: count,
      barangay: scope.barangay.isEmpty ? barangayCode : scope.barangay,
    );
  }

  static String _profileName(Map<String, dynamic> profile, User user) {
    for (final value in [
      profile['fullName'],
      profile['displayName'],
      profile['username'],
      profile['name'],
      user.displayName,
      user.email?.split('@').first,
    ]) {
      final name = (value ?? '').toString().trim();
      if (name.isNotEmpty) return name;
    }
    return 'Assigned Health Worker';
  }

  static DateTime _date(DateTime now, int index, {int spread = 180}) =>
      now.subtract(Duration(days: (index * 9) % spread));

  static List<Map<String, dynamic>> _patients(DateTime now) {
    const firstNames = ['Maria', 'Juan', 'Ana', 'Carlo', 'Liza', 'Ramon'];
    const surnames = [
      'Santos',
      'Reyes',
      'Cruz',
      'Garcia',
      'Flores',
      'Dela Peña',
    ];
    return List.generate(24, (i) {
      final birthDate = DateTime(
        now.year - (18 + i % 55),
        1 + i % 12,
        1 + i % 24,
      );
      return {
        'firstName': firstNames[i % firstNames.length],
        'surname': surnames[i % surnames.length],
        'patientName':
            '${firstNames[i % firstNames.length]} ${surnames[i % surnames.length]}',
        'patientId': 'TEST-P-${1001 + i}',
        'dateOfBirth': birthDate.toIso8601String(),
        'age': '${18 + i % 55}',
        'gender': i.isEven ? 'Female' : 'Male',
        'civilStatus': i % 3 == 0 ? 'Single' : 'Married',
        'phoneNumber': '0917${(1000000 + i).toString()}',
        'bloodType': const ['O+', 'A+', 'B+', 'AB+'][i % 4],
        'height': '${150 + i % 30}',
        'weight': '${48 + i % 38}',
        'bmi': '${19 + i % 13}.2',
        'immunizationStatus': i % 4 == 0 ? 'Partial' : 'Complete',
        'chronicConditions': i % 5 == 0 ? 'Hypertension' : 'None',
        'registrationDate': _date(now, i).toIso8601String(),
      };
    });
  }

  static List<Map<String, dynamic>> _checkups(DateTime now) {
    const symptoms = ['Cough', 'Fever', 'Headache', 'Body pain', 'Dizziness'];
    return List.generate(30, (i) {
      final date = _date(now, i, spread: 330);
      return {
        'datetime': date.toIso8601String(),
        'type': i % 3 == 0 ? 'Follow Up' : 'General Consultation',
        'diseaseType': 'General',
        'patient': 'Test Patient ${i + 1}',
        'patientId': 'TEST-P-${1001 + i % 24}',
        'details': 'Consultation for ${symptoms[i % symptoms.length]}',
        'plan': 'Medication, hydration, and scheduled follow-up.',
        'status': const ['Completed', 'Pending', 'On Follow Up'][i % 3],
        'vitalsigns':
            'Temp: ${36 + i % 3}.5 C | BP: ${110 + i % 35}/${70 + i % 20}',
        'symptoms': symptoms[i % symptoms.length],
        'followup': date.add(const Duration(days: 7)).toIso8601String(),
        'age': '${18 + i % 60}',
        'gender': i.isEven ? 'Female' : 'Male',
        'ai_category': const ['Respiratory', 'General', 'Neurological'][i % 3],
        'ai_severity': const ['Low', 'Moderate', 'High'][i % 3],
      };
    });
  }

  static List<Map<String, dynamic>> _communicable(DateTime now) {
    const diseases = [
      'Dengue',
      'Tuberculosis',
      'Influenza',
      'COVID-19',
      'Measles',
    ];
    const statuses = [
      'Active',
      'Recovered',
      'Recovered',
      'Monitoring',
      'Death',
    ];
    return List.generate(30, (i) {
      final date = _date(now, i + 2, spread: 330);
      final disease = diseases[i % diseases.length];
      return {
        'datetime': date.toIso8601String(),
        'type': disease,
        'condition': disease,
        'diseaseType': 'Communicable',
        'patient': 'Communicable Patient ${i + 1}',
        'patientId': 'TEST-C-${1001 + i}',
        'details': 'Confirmed $disease case for surveillance.',
        'status': statuses[i % statuses.length],
        'age': '${3 + i * 3 % 75}',
        'gender': i.isEven ? 'Male' : 'Female',
        'vaccinationCoverage': const ['High', 'Medium', 'Low'][i % 3],
        'populationDensity': 900 + i % 4 * 350,
        'ai_category': disease,
        'ai_severity': const ['Mild', 'Moderate', 'Severe'][i % 3],
      };
    });
  }

  static List<Map<String, dynamic>> _nonCommunicable(DateTime now) {
    const diseases = [
      'Hypertension',
      'Diabetes Mellitus',
      'Heart Disease',
      'Chronic Kidney Disease',
      'Asthma',
    ];
    return List.generate(30, (i) {
      final date = _date(now, i + 4, spread: 330);
      final disease = diseases[i % diseases.length];
      return {
        'datetime': date.toIso8601String(),
        'type': disease,
        'condition': disease,
        'diseaseType': 'Non-Communicable',
        'patient': 'NCD Patient ${i + 1}',
        'patientId': 'TEST-N-${1001 + i}',
        'details': 'Ongoing management for $disease.',
        'status': const [
          'Controlled',
          'Under Monitoring',
          'Uncontrolled',
        ][i % 3],
        'age': '${25 + i * 2 % 60}',
        'gender': i.isEven ? 'Female' : 'Male',
        'ai_category': disease,
        'ai_severity': const ['Mild', 'Moderate', 'Severe'][i % 3],
        'followupStatus': const ['Completed', 'Pending', 'Missed'][i % 3],
        'medicationAdherence': const ['Regular', 'Irregular', 'Stopped'][i % 3],
        'referralOutcome': const [
          'Managed at Barangay',
          'Referred to Hospital',
          'Emergency Referral',
        ][i % 3],
        'riskFactors': const [
          'Smoking',
          'Obesity',
          'Physical Inactivity',
          'High Cholesterol',
        ][i % 4],
        'bmi': '${21 + i % 15}',
        'bloodPressure': i % 3 == 0 ? '150/95' : '125/80',
      };
    });
  }

  static List<Map<String, dynamic>> _morbidity(DateTime now) {
    const diseases = [
      'Dengue',
      'Pneumonia',
      'Influenza',
      'Diabetes',
      'Hypertension',
    ];
    return List.generate(30, (i) {
      final date = _date(now, i, spread: 330);
      return {
        'patientName': 'Morbidity Patient ${i + 1}',
        'patientId': 'TEST-M-${1001 + i}',
        'age': '${8 + i * 3 % 75}',
        'gender': i.isEven ? 'Male' : 'Female',
        'disease': diseases[i % diseases.length],
        'severity': const ['Mild', 'Moderate', 'Severe', 'Critical'][i % 4],
        'status': const ['Active', 'Recovered', 'Under Treatment'][i % 3],
        'healthFacility': 'Barangay Health Center',
        'reportedBy': 'Assigned Health Worker',
        'treatment': 'Standard treatment and monitoring',
        'dateReported': date.toIso8601String(),
        'date': date.toIso8601String(),
        'time': date.toIso8601String(),
      };
    });
  }

  static List<Map<String, dynamic>> _prenatal(DateTime now) {
    const risks = ['Low Risk', 'Low Risk', 'Moderate Risk', 'High Risk'];
    return List.generate(30, (i) {
      final visit = _date(now, i, spread: 300);
      final lmp = now.subtract(Duration(days: 45 + i * 6 % 210));
      final due = lmp.add(const Duration(days: 280));
      return {
        'patientName': 'Prenatal Mother ${i + 1}',
        'patientId': 'TEST-PR-${1001 + i}',
        'age': '${17 + i % 25}',
        'registrationDate': visit.toIso8601String(),
        'lmpDate': lmp.toIso8601String(),
        'eddDate': due.toIso8601String(),
        'dueDate': due.toIso8601String(),
        'gestationalAge': '${8 + i % 30} weeks',
        'aog': '${8 + i % 30} weeks',
        'riskLevel': risks[i % risks.length],
        'status': const [
          'Active',
          'Follow-up',
          'Completed',
          'Missed Visits',
        ][i % 4],
        'bp': i % 5 == 0 ? '145/95' : '115/75',
        'bmi': '${20 + i % 12}.4',
        'gravida': '${1 + i % 5}',
        'para': '${i % 4}',
        'preExistingConditions': i % 5 == 0 ? 'Hypertension' : 'None',
        'previousComplications': i % 6 == 0 ? 'Anemia' : 'None',
        'referralStatus': const ['Not Referred', 'Pending', 'Completed'][i % 3],
        'ai_severity': const ['Low', 'Moderate', 'High'][i % 3],
        'registeredBy': 'Assigned Health Worker',
      };
    });
  }

  static List<Map<String, dynamic>> _immunization(DateTime now) {
    const vaccines = ['BCG', 'Hepatitis B', 'Pentavalent', 'OPV', 'MMR'];
    return List.generate(30, (i) {
      final date = _date(now, i, spread: 300);
      return {
        'patientName': 'Immunization Child ${i + 1}',
        'patientId': 'TEST-I-${1001 + i}',
        'age': '${2 + i % 58} months',
        'contactNumber': '0918${1000000 + i}',
        'vaccine': vaccines[i % vaccines.length],
        'vaccineBrand': 'DOH Vaccine',
        'batchNumber': 'TEST-B-${100 + i}',
        'expirationDate': now.add(const Duration(days: 365)).toIso8601String(),
        'administrationDate': date.toIso8601String(),
        'administrationTime': '09:00 AM',
        'doseNumber': '${1 + i % 3}',
        'routeOfAdministration': i.isEven ? 'Intramuscular' : 'Oral',
        'injectionSite': 'Left arm',
        'administeredBy': 'Assigned Health Worker',
        'adverseEvents': const ['None', 'Fever', 'Swelling', 'Rash'][i % 4],
        'nextDoseDueDate': date.add(const Duration(days: 30)).toIso8601String(),
        'status': const [
          'Fully Immunized',
          'Partially Immunized',
          'Not Yet Immunized',
        ][i % 3],
        'date': date.toIso8601String(),
        'riskLevel': const ['Low', 'Medium', 'High'][i % 3],
        'stockRemaining': 40 + i % 110,
      };
    });
  }

  static List<Map<String, dynamic>> _mortality(DateTime now) {
    const causes = [
      'Heart Disease',
      'Stroke',
      'Pneumonia',
      'Cancer',
      'Diabetes',
    ];
    const places = ['Hospital', 'Home', 'Health Center', 'Other'];
    return List.generate(30, (i) {
      final date = _date(now, i, spread: 330);
      return {
        'name': 'Mortality Record ${i + 1}',
        'date': date.toIso8601String(),
        'month': '${date.month}',
        'age': '${i % 7 == 0 ? i % 12 : 25 + i * 3 % 70}',
        'ageRange': const [
          '<1 year',
          '1-14',
          '15-24',
          '25-44',
          '45-64',
          '65+',
        ][i % 6],
        'gender': i.isEven ? 'Male' : 'Female',
        'causeOfDeath': causes[i % causes.length],
        'diseaseCategory': const [
          'Cardiovascular',
          'Respiratory',
          'Cancer',
          'Infectious Diseases',
        ][i % 4],
        'place': places[i % places.length],
        'reportedBy': 'Assigned Health Worker',
        'verification': const ['Verified', 'Pending'][i % 2],
        'dateReported': date.toIso8601String(),
        'population': 6500,
      };
    });
  }
}
