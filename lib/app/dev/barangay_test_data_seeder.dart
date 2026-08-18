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
      'Dengue Fever',
      'Tuberculosis',
      'Influenza',
      'COVID-19',
      'Measles',
      'Chickenpox',
      'Pneumonia',
      'Acute Gastroenteritis',
      'Hepatitis A',
      'Hepatitis B',
      'Typhoid Fever',
      'Cholera',
      'Leptospirosis',
      'Hand Foot and Mouth Disease',
      'Rabies Exposure',
      'Scarlet Fever',
      'Pertussis',
      'Mumps',
      'Malaria',
      'Amoebiasis',
    ];
    const statuses = [
      'Active',
      'Recovered',
      'Under Treatment',
      'Monitoring',
      'Death',
      'Recovered',
      'Active',
      'Completed',
    ];
    const symptomsList = [
      'High Fever and Joint Pain',
      'Chronic Cough and Night Sweats',
      'Fever, Chills, and Sore Throat',
      'Loss of Smell and Fatigue',
      'Koplik Spots and Skin Rash',
      'Itchy Blisters and Low-grade Fever',
      'Chest Congestion and Productive Cough',
      'Watery Diarrhea and Abdominal Cramps',
      'Jaundice and Right Upper Quadrant Pain',
      'Malaise and Dark Urine',
      'Step-ladder Fever and Rose Spots',
      'Rice-water Stools and Dehydration',
      'Calf Muscle Pain and Conjunctival Suffusion',
      'Oral Ulcers and Vesicles on Palms',
      'Animal Bite Wound with Paresthesia',
      'Strawberry Tongue and Sandpaper Rash',
      'Paroxysmal Whooping Cough Spells',
      'Painful Parotid Gland Swelling',
      'Cyclical Fever and Shivering Chills',
      'Mucoid Stool and Tenesmus',
    ];
    const vaccinationStatuses = [
      'Up to date',
      'High',
      'Medium',
      'Low',
      'Not Vaccinated',
    ];
    const severities = ['Mild', 'Moderate', 'Severe', 'Critical'];
    const barangayList = [
      'Poblacion',
      'Barangay 1',
      'Barangay 2',
      'Casisang',
      'Sumpong',
      'San Jose',
      'Kalasungay',
      'Dalwangan',
    ];

    return List.generate(60, (i) {
      // Seasonal distribution: spread evenly across 12 months with recent clustering
      final daysAgo = (i * 6) % 360;
      final date = now.subtract(Duration(days: daysAgo));
      final disease = diseases[i % diseases.length];
      final symptom = symptomsList[i % symptomsList.length];
      final status = statuses[i % statuses.length];
      final severity = severities[i % severities.length];
      final age = (i % 6 == 0)
          ? 1 + (i % 5) // 0-5 pediatric
          : (i % 5 == 1)
              ? 6 + (i % 12) // 6-17 teen
              : (i % 4 == 0)
                  ? 18 + (i % 27) // 18-44 young adult
                  : (i % 3 == 0)
                      ? 45 + (i % 20) // 45-64 middle age
                      : 65 + (i % 18); // 65+ senior
      final gender = i.isEven ? 'Male' : 'Female';
      final barangay = barangayList[i % barangayList.length];
      final temp = 37.4 + (i % 4) * 0.5;
      final bp = '${110 + (i % 25)}/${70 + (i % 15)}';
      final hr = 78 + (i % 35);
      final nextVisitDate = date.add(Duration(days: 3 + (i % 14)));

      return {
        'datetime': date.toIso8601String(),
        'date': date.toIso8601String(),
        'time': date.toIso8601String(),
        'type': disease,
        'condition': disease,
        'diagnosis': disease,
        'disease': disease,
        'diseaseType': 'Communicable',
        'patient': 'Communicable Patient ${i + 1}',
        'patientName': 'Communicable Patient ${i + 1}',
        'patientId': 'TEST-C-${1001 + i}',
        'details':
            'Confirmed $disease case. Patient presents with $symptom. Severity: $severity. Vital signs: Temp ${temp.toStringAsFixed(1)}°C, BP $bp, HR $hr bpm.',
        'plan':
            'Prescribed targeted antimicrobial therapy, isolation precautions, hydration protocol, and scheduled follow-up on ${nextVisitDate.toIso8601String().split('T')[0]}.',
        'status': status,
        'currentStatus': status,
        'symptoms': symptom,
        'age': '$age',
        'gender': gender,
        'sex': gender,
        'vitalsigns': 'Temp: ${temp.toStringAsFixed(1)}°C | BP: $bp | HR: $hr bpm',
        'vaccinationCoverage': vaccinationStatuses[i % vaccinationStatuses.length],
        'populationDensity': 850 + (i % 5) * 320,
        'ai_category': disease,
        'ai_severity': severity,
        'ai_confidence': '${82 + (i % 16)}%',
        'ai_method': 'Epidemiological Surveillance and Clinical Triage',
        'ai_recovery_plan':
            'Standard isolation protocol, hydration therapy, daily symptom logging, and post-recovery clearance check.',
        'followup': nextVisitDate.toIso8601String().split('T')[0],
        'nextVisit': nextVisitDate.toIso8601String().split('T')[0],
        'lastVisit': date.toIso8601String().split('T')[0],
        'address': '$barangay, Malaybalay City',
        'barangay': barangay,
        'reportedBy': 'Assigned Surveillance Officer',
      };
    });
  }

  static List<Map<String, dynamic>> _nonCommunicable(DateTime now) {
    const diseases = [
      'Hypertension',
      'Type 2 Diabetes Mellitus',
      'Coronary Heart Disease',
      'Stroke',
      'Bronchial Asthma',
      'COPD',
      'Osteoarthritis',
      'Rheumatoid Arthritis',
      'Chronic Kidney Disease',
      'Dyslipidemia',
      'Gouty Arthritis',
      'Hypothyroidism',
      'Hyperthyroidism',
      'Breast Cancer Follow-up',
      'Obesity',
      'Diabetic Neuropathy',
      'Heart Failure',
      'Chronic Low Back Pain',
    ];
    const statuses = [
      'Controlled',
      'Under Monitoring',
      'Uncontrolled',
      'Stable',
      'Under Monitoring',
      'Controlled',
      'Needs Adjustment',
    ];
    const riskFactorsList = [
      'Smoking, High Cholesterol',
      'Obesity, Physical Inactivity',
      'Physical Inactivity, High Sodium Diet',
      'High Cholesterol, Family History',
      'Alcohol Consumption, Smoking',
      'Obesity, High Sodium Diet',
      'Family History, Physical Inactivity',
    ];
    const bloodPressures = [
      '120/80',
      '130/85',
      '140/90',
      '155/95',
      '165/100',
      '125/82',
      '138/88',
      '148/94',
      '170/105',
    ];
    const bmis = ['21.8', '24.2', '26.7', '28.9', '31.4', '33.8', '35.2', '23.0', '27.5'];
    const followups = ['Completed', 'Pending', 'Missed', 'Completed', 'Pending'];
    const adherence = ['Regular', 'Regular', 'Irregular', 'Stopped', 'Regular'];
    const referralOutcomes = [
      'Managed at Barangay',
      'Managed at Barangay',
      'Referred to Hospital',
      'Emergency Referral',
      'Managed at Barangay',
    ];
    const severities = ['Mild', 'Moderate', 'Severe', 'Critical'];
    const barangayList = [
      'Poblacion',
      'Barangay 1',
      'Barangay 2',
      'Casisang',
      'Sumpong',
      'San Jose',
      'Kalasungay',
      'Dalwangan',
    ];

    return List.generate(60, (i) {
      final daysAgo = (i * 6 + 3) % 360;
      final date = now.subtract(Duration(days: daysAgo));
      final disease = diseases[i % diseases.length];
      final status = statuses[i % statuses.length];
      final bp = bloodPressures[i % bloodPressures.length];
      final bmi = bmis[i % bmis.length];
      final risk = riskFactorsList[i % riskFactorsList.length];
      final severity = severities[i % severities.length];
      final followupStatus = followups[i % followups.length];
      final medAdherence = adherence[i % adherence.length];
      final outcome = referralOutcomes[i % referralOutcomes.length];
      final barangay = barangayList[i % barangayList.length];
      final age = 22 + (i * 3) % 58; // 22 to 80 years old
      final gender = i.isEven ? 'Female' : 'Male';
      final nextVisitDate = date.add(Duration(days: 14 + (i % 30)));

      return {
        'datetime': date.toIso8601String(),
        'date': date.toIso8601String(),
        'time': date.toIso8601String(),
        'type': disease,
        'condition': disease,
        'diagnosis': disease,
        'disease': disease,
        'diseaseType': 'Non-Communicable',
        'patient': 'NCD Patient ${i + 1}',
        'patientName': 'NCD Patient ${i + 1}',
        'patientId': 'TEST-N-${1001 + i}',
        'details':
            'Diagnosed with $disease. Status: $status. Risk factors: $risk. Blood pressure: $bp, BMI: $bmi. Adherence: $medAdherence.',
        'plan':
            'Maintenance pharmacotherapy, sodium-restricted diet, routine ambulatory monitoring, and scheduled consultation on ${nextVisitDate.toIso8601String().split('T')[0]}.',
        'status': status,
        'currentStatus': status,
        'symptoms': 'Chronic management for $disease',
        'age': '$age',
        'gender': gender,
        'sex': gender,
        'bloodPressure': bp,
        'bmi': bmi,
        'vitalsigns': 'BP: $bp | BMI: $bmi | HR: ${68 + (i % 25)} bpm | Temp: 36.6°C',
        'riskFactors': risk,
        'followupStatus': followupStatus,
        'medicationAdherence': medAdherence,
        'referralOutcome': outcome,
        'ai_category': disease,
        'ai_severity': severity,
        'ai_confidence': '${84 + (i % 14)}%',
        'ai_method': 'Chronic Disease Risk Stratification',
        'ai_keywords': '$disease, chronic care, lifestyle intervention, medication compliance',
        'ai_recovery_plan':
            'Structured lifestyle modification, adherence counseling, routine glycemic/BP tracking, and periodic complication screenings.',
        'followup': nextVisitDate.toIso8601String().split('T')[0],
        'nextVisit': nextVisitDate.toIso8601String().split('T')[0],
        'lastVisit': date.toIso8601String().split('T')[0],
        'address': '$barangay, Malaybalay City',
        'barangay': barangay,
        'reportedBy': 'Assigned Health Worker',
      };
    });
  }

  static List<Map<String, dynamic>> _morbidity(DateTime now) {
    const communicableDiseases = [
      'Dengue Fever',
      'Pneumonia',
      'Influenza',
      'Tuberculosis',
      'Acute Gastroenteritis',
      'COVID-19',
      'Measles',
      'Chickenpox',
    ];
    const nonCommunicableDiseases = [
      'Hypertension',
      'Type 2 Diabetes Mellitus',
      'Coronary Heart Disease',
      'Bronchial Asthma',
      'Chronic Kidney Disease',
      'Osteoarthritis',
      'COPD',
      'Stroke',
    ];
    const severities = ['Mild', 'Moderate', 'Severe', 'Critical'];
    const statuses = ['Active', 'Recovered', 'Under Treatment', 'Controlled'];
    const barangays = [
      'Poblacion',
      'Barangay 1',
      'Barangay 2',
      'Casisang',
      'Sumpong',
      'San Jose',
      'Kalasungay',
      'Dalwangan',
    ];

    return List.generate(60, (i) {
      final daysAgo = (i * 6) % 360;
      final date = now.subtract(Duration(days: daysAgo));
      final isCommunicable = i.isEven;
      final disease = isCommunicable
          ? communicableDiseases[(i ~/ 2) % communicableDiseases.length]
          : nonCommunicableDiseases[(i ~/ 2) % nonCommunicableDiseases.length];
      final classification = isCommunicable ? 'communicable' : 'non_communicable';
      final diseaseType = isCommunicable ? 'Communicable' : 'Non-Communicable';
      final severity = severities[i % severities.length];
      final status = statuses[i % statuses.length];
      final barangay = barangays[i % barangays.length];
      final age = 5 + (i * 3) % 72;
      final gender = i % 3 == 0 ? 'Female' : 'Male';

      return {
        'patientName': 'Morbidity Patient ${i + 1}',
        'patientId': 'TEST-M-${1001 + i}',
        'age': '$age',
        'gender': gender,
        'sex': gender,
        'disease': disease,
        'condition': disease,
        'diagnosis': disease,
        'type': disease,
        'classification': classification,
        'diseaseType': diseaseType,
        'severity': severity,
        'ai_severity': severity,
        'status': status,
        'currentStatus': status,
        'healthFacility': 'Barangay Health Center',
        'reportedBy': 'Assigned Health Worker',
        'treatment': 'Standard protocol treatment and monitoring for $disease',
        'dateReported': date.toIso8601String(),
        'date': date.toIso8601String(),
        'datetime': date.toIso8601String(),
        'time': date.toIso8601String(),
        'address': '$barangay, Malaybalay City',
        'barangay': barangay,
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
