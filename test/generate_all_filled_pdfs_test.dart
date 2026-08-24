import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mycapstone_project/app/shared/services/clinical_form_pdf_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('generates all 6 filled category PDF forms and saves to test_forms/', () async {
    final outputDir = Directory('test_forms');
    if (!outputDir.existsSync()) {
      outputDir.createSync(recursive: true);
    }

    // 1. Check-Up Form (CHK-2026)
    final checkupRecord = {
      'patient': 'Juan Miguel Dela Cruz',
      'patientId': 'PAT-2026-0105',
      'dateOfBirth': '1992-05-18',
      'age': '34',
      'gender': 'Male',
      'civilStatus': 'Married',
      'contactNumber': '09178889900',
      'philhealthNumber': '12-345678901-2',
      'address': 'Purok 4, Sayre Highway',
      'barangay': 'Casisang',
      'bloodPressure': '120/80 mmHg',
      'temperature': '36.8 C',
      'heartRate': '74 bpm',
      'respiratoryRate': '18 cpm',
      'oxygenSaturation': '98 %',
      'weight': '68 kg',
      'height': '170 cm',
      'bmi': '23.5 kg/m2',
      'symptoms': 'Fever for 3 days, dry cough, and mild headache',
      'diagnosis': 'Upper Respiratory Tract Infection (URTI)',
      'treatment': 'Paracetamol 500mg TID, Salbutamol syrup, increased oral fluids',
      'recordType': 'General Outpatient',
      'visitDate': '2026-08-24',
      'attendingPhysician': 'Dr. Ramon Reyes, MD',
    };
    final checkupBytes = await ClinicalFormPdfService.generateFormPdfBytes(
      formType: ClinicalFormType.checkup,
      record: checkupRecord,
      isBlank: false,
    );
    await File('${outputDir.path}/CHK_2026_checkup_filled.pdf').writeAsBytes(checkupBytes);

    // 2. Prenatal Care Form (PNC-2026)
    final prenatalRecord = {
      'patientName': 'Maria Santos Cruz',
      'patientId': 'PAT-2026-0042',
      'age': '28',
      'civilStatus': 'Married',
      'spouseName': 'Eduardo Cruz',
      'address': 'Zone 2, Capitol Drive',
      'barangay': 'Kalasungay',
      'contactNumber': '09187776655',
      'philhealthNumber': '03-987654321-0',
      'gravida': '2',
      'para': '1',
      'fullTerm': '1',
      'premature': '0',
      'abortions': '0',
      'livingChildren': '1',
      'lmp': '2026-01-10',
      'edd': '2026-10-17',
      'ageOfGestation': '32 weeks',
      'fundicHeight': '30 cm',
      'fetalHeartTone': '142 bpm',
      'fetalPresentation': 'Cephalic',
      'bloodPressure': '110/70 mmHg',
      'weight': '58 kg',
      'temperature': '36.5 C',
      'riskLevel': 'Low Risk',
      'tdVaccine': 'TD2 Completed',
      'supplements': 'Ferrous Sulfate + Folic Acid 1 tab OD, Calcium Carbonate 500mg BID',
      'remarks': 'Normal fetal growth and maternal weight gain. Next visit in 2 weeks.',
      'visitDate': '2026-08-24',
      'attendingMidwife': 'BHW Elena Bautista, RM',
    };
    final prenatalBytes = await ClinicalFormPdfService.generateFormPdfBytes(
      formType: ClinicalFormType.prenatal,
      record: prenatalRecord,
      isBlank: false,
    );
    await File('${outputDir.path}/PNC_2026_prenatal_filled.pdf').writeAsBytes(prenatalBytes);

    // 3. Immunization Record Form (IMZ-2026)
    final immunizationRecord = {
      'childName': 'Gabriel Santos Reyes',
      'patientId': 'PAT-2026-0088',
      'dateOfBirth': '2026-03-15',
      'age': '5 months',
      'gender': 'Male',
      'motherName': 'Carmela Santos Reyes',
      'fatherName': 'Michael Angelo Reyes',
      'address': 'Purok 1, Riverside',
      'barangay': 'San Jose',
      'contactNumber': '09223334455',
      'philhealthNumber': '18-555444333-1',
      'vaccine': 'Pentavalent Vaccine (DTP-HepB-Hib)',
      'dose': '3rd Dose',
      'batchLotNumber': 'LOT-PNT-2026-09',
      'routeSite': 'Intramuscular / Anterolateral Thigh',
      'administeredBy': 'Nurse Kristine Joyce Flores, RN',
      'weight': '7.2 kg',
      'height': '65 cm',
      'temperature': '36.6 C',
      'bcgGiven': 'Yes (2026-03-16)',
      'hepaBGiven': 'Yes (2026-03-16)',
      'opvDoses': 'OPV 1, OPV 2, OPV 3 Completed',
      'nextDueDate': '2026-12-15 (Measles-MMR 1st Dose)',
      'visitDate': '2026-08-24',
    };
    final immunizationBytes = await ClinicalFormPdfService.generateFormPdfBytes(
      formType: ClinicalFormType.immunization,
      record: immunizationRecord,
      isBlank: false,
    );
    await File('${outputDir.path}/IMZ_2026_immunization_filled.pdf').writeAsBytes(immunizationBytes);

    // 4. Morbidity Surveillance Form (MBD-2026)
    final morbidityRecord = {
      'patientName': 'Ana Theresa Lim',
      'patientId': 'PAT-2026-0177',
      'age': '19',
      'gender': 'Female',
      'civilStatus': 'Single',
      'address': 'Purok 6, Central Park',
      'barangay': 'Aglayan',
      'contactNumber': '09391112233',
      'disease': 'Dengue Fever (Non-Severe)',
      'icdCode': 'A90',
      'onsetDate': '2026-08-21',
      'dateReported': '2026-08-24',
      'signsSymptoms': 'High grade fever (39.2 C), retro-orbital pain, myalgia, petechial rash, positive tourniquet test',
      'laboratoryResults': 'NS1 Antigen: Positive | Platelet Count: 125,000/uL | Hematocrit: 40%',
      'severity': 'Warning Signs Present',
      'outcome': 'Admitted / Under Observation at CHO Isolation Center',
      'reportingUnit': 'Barangay Aglayan Health Station',
      'reportingOfficer': 'Dr. Antonio Garcia, MD (Surveillance Officer)',
    };
    final morbidityBytes = await ClinicalFormPdfService.generateFormPdfBytes(
      formType: ClinicalFormType.morbidity,
      record: morbidityRecord,
      isBlank: false,
    );
    await File('${outputDir.path}/MBD_2026_morbidity_filled.pdf').writeAsBytes(morbidityBytes);

    // 5. Mortality Notification Form (MOR-2026)
    final mortalityRecord = {
      'deceasedName': 'Pedro Alvarez Cruz',
      'patientId': 'PAT-2026-0210',
      'age': '72',
      'gender': 'Male',
      'civilStatus': 'Widowed',
      'address': 'Purok 3, Madasigon',
      'barangay': 'Laguitas',
      'dateOfDeath': '2026-08-23',
      'timeOfDeath': '14:35',
      'placeOfDeath': 'Home / Residence',
      'immediateCause': 'Acute Myocardial Infarction',
      'antecedentCause': 'Coronary Artery Disease (CAD)',
      'underlyingCause': 'Hypertensive Cardiovascular Disease (15 years duration)',
      'otherSignificantConditions': 'Type 2 Diabetes Mellitus',
      'autopsyPerformed': 'No',
      'attendingPhysician': 'Dr. Vicente Gomez, MD',
      'informantName': 'Teresa Cruz Villanueva (Daughter)',
      'informantRelation': 'Daughter',
      'certificationDate': '2026-08-24',
    };
    final mortalityBytes = await ClinicalFormPdfService.generateFormPdfBytes(
      formType: ClinicalFormType.mortality,
      record: mortalityRecord,
      isBlank: false,
    );
    await File('${outputDir.path}/MOR_2026_mortality_filled.pdf').writeAsBytes(mortalityBytes);

    // 6. Patient Master Registration Form (PAT-2026)
    final patientRecord = {
      'patientName': 'Rodrigo Garcia Fernandez',
      'patientId': 'PAT-2026-0350',
      'dateOfBirth': '1985-11-20',
      'age': '40',
      'gender': 'Male',
      'civilStatus': 'Married',
      'bloodType': 'O Positive',
      'occupation': 'Secondary School Teacher',
      'contactNumber': '09285551234',
      'email': 'rodrigo.fernandez@deped.gov.ph',
      'philhealthNumber': '15-098712345-6',
      'address': 'Block 12 Lot 5, Villa Corina Subd.',
      'barangay': 'Sumpong',
      'municipality': 'City of Malaybalay',
      'province': 'Bukidnon',
      'emergencyContactName': 'Lucia Fernandez (Spouse)',
      'emergencyContactRelationship': 'Spouse',
      'emergencyContactNumber': '09176667890',
      'allergies': 'Penicillin, Shellfish',
      'chronicConditions': 'Essential Hypertension (controlled on Amlodipine 5mg)',
      'registrationDate': '2026-08-24',
      'registeredBy': 'BHW Carmen Delgado',
    };
    final patientBytes = await ClinicalFormPdfService.generateFormPdfBytes(
      formType: ClinicalFormType.patientRegistration,
      record: patientRecord,
      isBlank: false,
    );
    await File('${outputDir.path}/PAT_2026_patient_registration_filled.pdf').writeAsBytes(patientBytes);

    expect(checkupBytes.isNotEmpty, isTrue);
    expect(prenatalBytes.isNotEmpty, isTrue);
    expect(immunizationBytes.isNotEmpty, isTrue);
    expect(morbidityBytes.isNotEmpty, isTrue);
    expect(mortalityBytes.isNotEmpty, isTrue);
    expect(patientBytes.isNotEmpty, isTrue);
  });
}
