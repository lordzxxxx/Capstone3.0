import 'package:flutter_test/flutter_test.dart';
import 'package:mycapstone_project/app/shared/services/clinical_form_pdf_service.dart';
import 'package:mycapstone_project/web/shared/utils/checkup_pdf.dart';
import 'package:mycapstone_project/web/shared/utils/mortality_pdf.dart';
import 'package:mycapstone_project/web/shared/utils/morbidity_pdf.dart';
import 'package:mycapstone_project/web/shared/utils/prenatal_pdf.dart';
import 'package:mycapstone_project/web/shared/utils/immunization_pdf.dart';
import 'package:mycapstone_project/web/shared/utils/patient_pdf.dart';

int getPdfPageCount(List<int> bytes) {
  final content = String.fromCharCodes(bytes);
  final matches = RegExp(r'/Type\s*/Page\b').allMatches(content);
  return matches.length;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final sampleCheckup = {
    'id': 'CHK-2026-001',
    'patient': 'Juan Miguel Dela Cruz',
    'patientId': 'PAT-2026-0105',
    'age': '34',
    'address': 'Purok 4, Sayre Highway, Casisang',
    'barangay': 'Casisang',
    'datetime': '2026-08-24 10:30 AM',
    'diseaseType': 'General Outpatient',
    'status': 'Completed',
    'followup': '2026-09-01',
    'vitalsigns': 'BP: 120/80 mmHg, HR: 74 bpm, Temp: 36.8 C, RR: 18 cpm, SpO2: 98%',
    'symptoms': 'Fever for 3 days, dry cough, and mild headache',
    'plan': 'Paracetamol 500mg TID, Salbutamol syrup, increased oral fluids',
    'details': 'Patient advised to rest and monitor temperature daily.',
    // Mobile fields:
    'dateOfBirth': '1992-05-18',
    'gender': 'Male',
    'civilStatus': 'Married',
    'contactNumber': '09178889900',
    'philhealthNumber': '12-345678901-2',
    'diagnosis': 'Upper Respiratory Tract Infection (URTI)',
    'treatment': 'Paracetamol 500mg TID, Salbutamol syrup, increased oral fluids',
    'recordType': 'General Outpatient',
    'visitDate': '2026-08-24',
    'attendingPhysician': 'Dr. Ramon Reyes, MD',
  };

  final sampleMortality = {
    'id': 'MOR-2026-001',
    'patientId': 'PAT-2026-0210',
    'name': 'Pedro Alvarez Cruz',
    'deceasedName': 'Pedro Alvarez Cruz',
    'patient': 'Pedro Alvarez Cruz',
    'date': '2026-08-23',
    'dateTimeOfDeath': '2026-08-23 14:35',
    'timeOfDeath': '14:35',
    'age': '72',
    'gender': 'Male',
    'civilStatus': 'Widowed',
    'ageRange': '60+ Senior',
    'barangay': 'Laguitas',
    'address': 'Purok 3, Madasigon, Laguitas',
    'causeCategory': 'Cardiovascular',
    'causeOfDeath': 'Acute Myocardial Infarction',
    'immediateCause': 'Acute Myocardial Infarction',
    'antecedentCause': 'Coronary Artery Disease (CAD)',
    'underlyingCause': 'Hypertensive Cardiovascular Disease',
    'reason': 'Natural Causes',
    'explanation': 'Sudden cardiac arrest at home',
    'purok': 'Purok 3',
    'place': 'Home / Residence',
    'reportedBy': 'Teresa Cruz Villanueva',
    'verification': 'Verified by CHO Medical Officer',
    'dateReported': '2026-08-24',
    'month': 'August 2026',
  };

  final sampleMorbidity = {
    'id': 'MBD-2026-001',
    'patientId': 'PAT-2026-0177',
    'patientName': 'Ana Theresa Lim',
    'name': 'Ana Theresa Lim',
    'patient': 'Ana Theresa Lim',
    'age': '19',
    'gender': 'Female',
    'address': 'Purok 6, Central Park, Aglayan',
    'barangay': 'Aglayan',
    'contactNumber': '09391112233',
    'disease': 'Dengue Fever (Non-Severe)',
    'diseaseType': 'Infectious / Notifiable',
    'severity': 'Warning Signs Present',
    'symptoms': 'High grade fever (39.2 C), retro-orbital pain, myalgia, petechial rash',
    'diagnosis': 'Dengue Fever with Warning Signs',
    'plan': 'Admitted / Under Observation at CHO Isolation Center, IV hydration',
    'status': 'Active Surveillance',
    'reportedDate': '2026-08-24 09:15 AM',
    'reportedBy': 'Dr. Antonio Garcia, MD',
    'remarks': 'Close platelet count monitoring every 12 hours.',
  };

  final samplePrenatal = {
    'id': 'PNC-2026-001',
    'patientId': 'PAT-2026-0042',
    'firstName': 'Maria',
    'surname': 'Cruz',
    'patientName': 'Maria Santos Cruz',
    'patient': 'Maria Santos Cruz',
    'age': '28',
    'civilStatus': 'Married',
    'spouseName': 'Eduardo Cruz',
    'address': 'Zone 2, Capitol Drive, Kalasungay',
    'barangay': 'Kalasungay',
    'contactNumber': '09187776655',
    'religion': 'Roman Catholic',
    'philhealthNumber': '03-987654321-0',
    'philhealthMember': 'Yes - Dependent',
    'gestationalAge': '32 weeks',
    'aog': '32 weeks',
    'lmpDate': '2026-01-10',
    'eddDate': '2026-10-17',
    'dueDate': '2026-10-17',
    'lastDeliveryDate': '2023-04-15',
    'gravida': '2',
    'para': '1',
    'riskLevel': 'Low Risk',
    'bloodType': 'O+',
    'allergies': 'None',
    'preExistingConditions': 'None',
    'previousComplications': 'None',
    'wt': '58 kg',
    'at': 'None',
    'temp': '36.5 C',
    'bp': '110/70 mmHg',
    'bmi': '22.8',
    'fh': '30 cm',
    'dhb': '142 bpm',
    'tcb': 'Normal',
    'registrationDate': '2026-08-24',
    'registeredBy': 'BHW Elena Bautista, RM',
    'status': 'Active',
    'additionalNote': 'Normal fetal growth. Next prenatal visit in 2 weeks.',
  };

  final sampleImmunization = {
    'id': 'IMZ-2026-001',
    'patientId': 'PAT-2026-0088',
    'patientName': 'Gabriel Santos Reyes',
    'childName': 'Gabriel Santos Reyes',
    'patient': 'Gabriel Santos Reyes',
    'middleName': 'Santos',
    'dateOfBirth': '2026-03-15',
    'dob': '2026-03-15',
    'age': '5 months',
    'sex': 'Male',
    'gender': 'Male',
    'bloodType': 'O+',
    'contactNumber': '09223334455',
    'parentGuardianName': 'Carmela Santos Reyes',
    'address': 'Purok 1, Riverside, San Jose',
    'barangay': 'San Jose',
    'vaccine': 'Pentavalent Vaccine (DTP-HepB-Hib)',
    'vaccineBrand': 'Pentashield',
    'batchNumber': 'LOT-PNT-2026-09',
    'expirationDate': '2027-06-30',
    'administrationDate': '2026-08-24 09:30 AM',
    'administrationTime': '09:30 AM',
    'doseNumber': '3rd Dose',
    'dose': '3rd Dose',
    'routeOfAdministration': 'Intramuscular',
    'injectionSite': 'Anterolateral Thigh',
    'administeredBy': 'Nurse Kristine Joyce Flores, RN',
    'adverseEvents': 'None reported',
    'nextDoseDueDate': '2026-12-15',
    'nextVisitDate': '2026-12-15',
    'status': 'Completed',
  };

  final samplePatient = {
    'id': 'PAT-2026-0105',
    'firstName': 'Juan Miguel',
    'middleName': 'Santos',
    'surname': 'Dela Cruz',
    'mothersMaidenName': 'Santos',
    'dateOfBirth': '1992-05-18',
    'age': '34',
    'gender': 'Male',
    'civilStatus': 'Married',
    'nationality': 'Filipino',
    'religion': 'Roman Catholic',
    'occupation': 'Public Transport Driver',
    'educationalAttainment': 'High School Graduate',
    'employeeStatus': 'Self-Employed',
    'status': 'Active',
    'phoneNumber': '09178889900',
    'alternativePhone': '09223334455',
    'emailAddress': 'juan.delacruz@example.com',
    'guardian': 'Maria Dela Cruz',
    'street': 'Purok 4, Sayre Highway',
    'barangay': 'Casisang',
    'municipality': 'Malaybalay City',
    'province': 'Bukidnon',
    'height': '170 cm',
    'weight': '68 kg',
    'bmi': '23.5',
    'bloodType': 'O+',
    'allergies': 'Penicillin',
    'immunizationStatus': 'Fully Immunized',
    'familyMedicalHistory': 'Hypertension (Father)',
    'pastMedicalHistory': 'Asthma in childhood',
    'currentMedications': 'Amlodipine 5mg OD',
    'chronicConditions': 'Hypertension Stage 1',
    'bodyTemperature': '36.8',
    'temperatureUnit': 'C',
    'bpSystolic': '120',
    'bpDiastolic': '80',
    'heartRate': '74 bpm',
    'respiratoryRate': '18 cpm',
    'oxygenSaturation': '98%',
    'emergencyContactName': 'Maria Elena Dela Cruz',
    'emergencyRelationship': 'Spouse',
    'emergencyContactPhone': '09179991122',
    'emergencyContactAddress': 'Purok 4, Sayre Highway, Casisang',
    'smokingStatus': 'Non-Smoker',
    'exerciseFrequency': 'Moderate (walking daily)',
    'alcoholConsumption': 'Occasional',
    'dietaryRestrictions': 'Low sodium',
    'morbidityRiskLevel': 'Low Risk',
    'functionalStatus': 'Independent',
    'placeOfBirth': 'Malaybalay City',
    'chiefComplaint': 'Routine health check-up',
    'currentSymptoms': 'None reported',
    'disability': 'None',
    'mentalHealthStatus': 'Normal',
    'substanceUseHistory': 'None',
    'lastCheckup': '2026-05-10',
    'nextCheckup': '2026-11-10',
    'mentalHealthStatusLifestyle': 'Good',
    'sleepQuality': '7-8 hours restful',
    'numberOfComorbidities': '0',
    'mobilityStatus': 'Fully Mobile',
    'frailtyIndex': '0.05 (Robust)',
    'polypharmacyRisk': 'Low',
    'preventiveCareCompliance': 'High',
    'healthLiteracyLevel': 'Adequate',
    'socialSupportLevel': 'Strong',
    'economicStatusImpact': 'Moderate',
    'morbidityNotes': 'Patient is healthy and compliant with annual check-ups.',
    'insuranceProvider': 'PhilHealth',
    'insuranceNumber': '12-345678901-2',
    'insuranceExpiry': '2027-12-31',
    'monthlyIncome': 'Php 18,000',
    'educationLevel': 'High School',
    'preferredLanguage': 'Bisaya / English',
    'referralSource': 'Self-referred / Walk-in',
    'transportation': 'Motorcycle',
    'consentGiven': 'Yes',
    'registrationDate': '2026-08-24',
    'additionalInfo': 'PhilHealth primary care benefit registered.',
  };

  test('Check current page counts for Web PDFs', () async {
    final checkupPdf = await buildCheckupPdfBytes(sampleCheckup);
    final mortalityPdf = await buildMortalityPdfBytes(sampleMortality);
    final morbidityPdf = await buildMorbidityPdfBytes(sampleMorbidity);
    final prenatalPdf = await buildPrenatalPdfBytes(samplePrenatal);
    final immunizationPdf = await buildImmunizationPdfBytes(sampleImmunization);
    final patientPdf = await buildPatientPdfBytes(samplePatient);

    expect(getPdfPageCount(checkupPdf), 1);
    expect(getPdfPageCount(mortalityPdf), 1);
    expect(getPdfPageCount(morbidityPdf), 1);
    expect(getPdfPageCount(prenatalPdf), 1);
    expect(getPdfPageCount(immunizationPdf), 1);
    expect(getPdfPageCount(patientPdf), 1);
  });

  test('Check current page counts for App PDFs', () async {
    final checkupPdf = await ClinicalFormPdfService.generateFormPdfBytes(
      formType: ClinicalFormType.checkup,
      record: sampleCheckup,
    );
    final mortalityPdf = await ClinicalFormPdfService.generateFormPdfBytes(
      formType: ClinicalFormType.mortality,
      record: sampleMortality,
    );
    final morbidityPdf = await ClinicalFormPdfService.generateFormPdfBytes(
      formType: ClinicalFormType.morbidity,
      record: sampleMorbidity,
    );
    final prenatalPdf = await ClinicalFormPdfService.generateFormPdfBytes(
      formType: ClinicalFormType.prenatal,
      record: samplePrenatal,
    );
    final immunizationPdf = await ClinicalFormPdfService.generateFormPdfBytes(
      formType: ClinicalFormType.immunization,
      record: sampleImmunization,
    );
    final patientPdf = await ClinicalFormPdfService.generateFormPdfBytes(
      formType: ClinicalFormType.patientRegistration,
      record: samplePatient,
    );

    expect(getPdfPageCount(checkupPdf), 1);
    expect(getPdfPageCount(mortalityPdf), 1);
    expect(getPdfPageCount(morbidityPdf), 1);
    expect(getPdfPageCount(prenatalPdf), 1);
    expect(getPdfPageCount(immunizationPdf), 1);
    expect(getPdfPageCount(patientPdf), 1);
  });
}
