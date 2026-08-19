import 'package:flutter_test/flutter_test.dart';
import 'package:mycapstone_project/app/shared/widgets/ocr_record_action.dart';

void main() {
  group('OcrExtraction.fromText content-based parsing', () {
    test('maps labeled fields by content regardless of spacing/formatting', () {
      const text = '''
        Full Name:    Juan Dela Cruz
        Date of Birth - 1990-05-14
        Contact Number:0917 123 4567
        Email:   juan.delacruz@example.com
        Address:  123 Rizal St, Brgy. Uno, Quezon City
      ''';

      final extraction = OcrExtraction.fromText(text);

      expect(extraction.fields['fullName']?.value, 'Juan Dela Cruz');
      expect(extraction.fields['dateOfBirth']?.value, '1990-05-14');
      expect(extraction.fields['contactNumber']?.value, '09171234567');
      expect(extraction.fields['email']?.value, 'juan.delacruz@example.com');
      expect(
        extraction.fields['address']?.value,
        '123 Rizal St, Brgy. Uno, Quezon City',
      );
      for (final field in extraction.fields.values) {
        expect(
          field.requiresManualReview,
          isFalse,
          reason: '${field.key} should be trusted at default confidence',
        );
      }
    });

    test('is not dependent on line order or extra whitespace/misalignment', () {
      const shuffled = '''


          Email:juan@example.com

               Full Name :   Juan Dela Cruz
        Contact Number : 09171234567
      ''';

      final extraction = OcrExtraction.fromText(shuffled);

      expect(extraction.fields['email']?.value, 'juan@example.com');
      expect(extraction.fields['fullName']?.value, 'Juan Dela Cruz');
      expect(extraction.fields['contactNumber']?.value, '09171234567');
    });

    test('recognizes fields by context even without an explicit label', () {
      const text = '''
        Patient intake sheet
        Reach the patient at juan.delacruz@example.com for follow-up.
        Emergency contact can call 0917-123-4567 anytime.
      ''';

      final extraction = OcrExtraction.fromText(text);

      expect(extraction.fields['email']?.value, 'juan.delacruz@example.com');
      expect(extraction.fields['contactNumber']?.value, '09171234567');
    });

    test('normalizes assorted date formats to ISO 8601', () {
      final extraction = OcrExtraction.fromText('Date of Birth: 05/14/1990');
      expect(extraction.fields['dateOfBirth']?.value, '1990-05-14');
    });

    test('normalizes a +63 mobile number to the local 0-prefixed format', () {
      final extraction = OcrExtraction.fromText(
        'Contact Number: +63 917 123 4567',
      );
      expect(extraction.fields['contactNumber']?.value, '09171234567');
    });

    test('handles labels without punctuation and values on the next line', () {
      final extraction = OcrExtraction.fromText('''
        Patient Name Juan Dela Cruz
        Dateofbirth
        May 14, 1990
        Sex F
        Brgy. 07
      ''');

      expect(extraction.fields['fullName']?.value, 'Juan Dela Cruz');
      expect(extraction.fields['dateOfBirth']?.value, '1990-05-14');
      expect(extraction.fields['gender']?.value, 'Female');
      expect(extraction.fields['barangay']?.value, 'Barangay 07');
    });

    test(
      'prefers an explicitly labeled value over a heading that starts with '
      'the same field keyword',
      () {
        final extraction = OcrExtraction.fromText('''
        Barangay Health Intake Form
        Full Name: Juan Dela Cruz
        Barangay: Barangay 03
      ''');

        expect(extraction.fields['barangay']?.value, 'Barangay 03');
      },
    );

    test('normalizes compact Philippine mobile numbers', () {
      final extraction = OcrExtraction.fromText('Phone 9171234567');
      expect(extraction.fields['contactNumber']?.value, '09171234567');
    });

    test('derives the form patient name from separate name fields', () {
      final extraction = OcrExtraction.fromText('''
        First Name: Maria
        Surname: Santos
      ''');

      expect(extraction.toFormSeed()['patientName'], 'Maria Santos');
    });

    test('separates multiple explicitly labeled fields on one line', () {
      final extraction = OcrExtraction.fromText(
        'Full Name: Ana Cruz DOB: 05/14/1990 Sex: F',
      );

      expect(extraction.fields['fullName']?.value, 'Ana Cruz');
      expect(extraction.fields['dateOfBirth']?.value, '1990-05-14');
      expect(extraction.fields['gender']?.value, 'Female');
    });

    test('maps a visit date without confusing it with birth date', () {
      final extraction = OcrExtraction.fromText('Visit Date: 2025-02-03');

      expect(extraction.fields['date']?.value, '2025-02-03');
      expect(extraction.fields.containsKey('dateOfBirth'), isFalse);
    });
  });

  group('OcrExtraction validation and confidence gating', () {
    test('flags a malformed email as low-confidence and needing review', () {
      final extraction = OcrExtraction.fromText('Email: not-an-email');

      final field = extraction.fields['email'];
      expect(field, isNotNull);
      expect(field!.requiresManualReview, isTrue);
      expect(field.confidence, lessThan(OcrExtraction.manualReviewThreshold));
    });

    test('flags an implausible age as needing manual review', () {
      final extraction = OcrExtraction.fromText('Age: 999');

      final field = extraction.fields['age'];
      expect(field, isNotNull);
      expect(field!.requiresManualReview, isTrue);
    });

    test('accepts a plausible age at default confidence', () {
      final extraction = OcrExtraction.fromText('Age: 34');

      final field = extraction.fields['age'];
      expect(field, isNotNull);
      expect(field!.requiresManualReview, isFalse);
    });

    test('low ML Kit line confidence still forces manual review', () {
      const line = 'Full Name: Juan Dela Cruz';
      final extraction = OcrExtraction.fromText(
        line,
        lineConfidence: {line: 0.4},
      );

      final field = extraction.fields['fullName'];
      expect(field, isNotNull);
      expect(field!.requiresManualReview, isTrue);
    });

    test('empty/unreadable text yields no fields and zero confidence', () {
      final extraction = OcrExtraction.fromText('   \n  \n ');
      expect(extraction.fields, isEmpty);
      expect(extraction.overallConfidence, 0.0);
    });
  });

  group('OcrExtraction.toFormSeed', () {
    test('only seeds validated, high-confidence fields into the form', () {
      const text = '''
        Full Name: Juan Dela Cruz
        Email: not-an-email
        Age: 34
      ''';
      final extraction = OcrExtraction.fromText(text);
      final seed = extraction.toFormSeed();

      expect(seed['fullName'], 'Juan Dela Cruz');
      expect(seed['patientName'], 'Juan Dela Cruz');
      expect(seed['age'], '34');
      expect(seed.containsKey('email'), isFalse);
      expect(seed['_ocrNeedsManualReview'], contains('email'));
    });

    test(
      'copyWithFields recomputes overall confidence from accepted edits',
      () {
        final extraction = OcrExtraction.fromText('Email: not-an-email');
        final field = extraction.fields['email']!;
        final corrected = extraction.copyWithFields({
          'email': field.copyWith(value: 'juan@example.com', confidence: 0.9),
        });

        expect(corrected.fields['email']?.requiresManualReview, isFalse);
        expect(corrected.overallConfidence, 0.9);
      },
    );
  });

  group('Handwritten form OCR accuracy and disambiguation', () {
    test('corrects common handwritten numeric character substitutions', () {
      const text = '''
        Pt. Name: _JUAN DELA CRUZ_
        Age: 2S yo
        BP: 12O/8O
        Temp: 36,5 C
        HR: 7S bpm
        RR: l8 cpm
        SpO2: 98%
        Weight: 5S kg
        Height: 16O cm
        Contact: O9171234567
        DOB: O5/14/199O
        Sex: [x] Male
        Civil Status: Single
        Barangay: Brgy 3
      ''';

      final extraction = OcrExtraction.fromText(text);

      expect(extraction.fields['fullName']?.value, 'Juan Dela Cruz');
      expect(extraction.fields['age']?.value, '25');
      expect(extraction.fields['bloodPressure']?.value, '120/80');
      expect(extraction.fields['temperature']?.value, '36.5');
      expect(extraction.fields['heartRate']?.value, '75');
      expect(extraction.fields['respiratoryRate']?.value, '18');
      expect(extraction.fields['oxygenSaturation']?.value, '98');
      expect(extraction.fields['weight']?.value, '55');
      expect(extraction.fields['height']?.value, '160');
      expect(extraction.fields['contactNumber']?.value, '09171234567');
      expect(extraction.fields['dateOfBirth']?.value, '1990-05-14');
      expect(extraction.fields['gender']?.value, 'Male');
      expect(extraction.fields['civilStatus']?.value, 'Single');
      expect(extraction.fields['barangay']?.value, 'Barangay 03');
    });

    test('parses Filipino clinical shorthand labels', () {
      const text = '''
        Pangalan: Maria Santos
        Edad: 32
        Kasarian: Babae
        Tirahan: Brgy. 05, Makati
        Presyon: 110/70
        Timbang: 52
        Taas: 155
        Reklamo: Lagnat at ubo
        Karamdaman: Acute URI
      ''';

      final extraction = OcrExtraction.fromText(text);

      expect(extraction.fields['fullName']?.value, 'Maria Santos');
      expect(extraction.fields['age']?.value, '32');
      expect(extraction.fields['gender']?.value, 'Female');
      expect(extraction.fields['address']?.value, 'Brgy. 05, Makati');
      expect(extraction.fields['bloodPressure']?.value, '110/70');
      expect(extraction.fields['weight']?.value, '52');
      expect(extraction.fields['height']?.value, '155');
      expect(extraction.fields['symptoms']?.value, 'Lagnat at ubo');
      expect(extraction.fields['disease']?.value, 'Acute URI');
    });

    test('extracts multiple fields from a single handwritten intake line', () {
      final extraction = OcrExtraction.fromText(
        'Pt: Pedro Reyes Age: 40 Sex: M BP: 130/90 Temp: 37.0',
      );

      expect(extraction.fields['fullName']?.value, 'Pedro Reyes');
      expect(extraction.fields['age']?.value, '40');
      expect(extraction.fields['gender']?.value, 'Male');
      expect(extraction.fields['bloodPressure']?.value, '130/90');
      expect(extraction.fields['temperature']?.value, '37.0');
    });

    test('maps scanned form fields automatically to all system form seed aliases', () {
      const formText = '''
        FORM: CHK-2026
        Full Name: Juan Dela Cruz
        Patient ID: PAT-2026-001
        Age: 35
        Sex: Male
        Date of Birth: 1991-04-20
        Civil Status: Married
        Address: 123 Main St, Brgy. 01
        Barangay: Barangay 01
        Contact Number: 09171234567
        Blood Pressure: 120/80
        Body Temp: 36.6
        Pulse Rate: 72
        Resp. Rate: 18
        Oxygen Sat: 99
        Weight: 65
        Height: 170
        Chief Complaint: Fever and mild cough
        Diagnosis: Upper Respiratory Tract Infection
        Treatment Plan: Paracetamol 500mg TID, Hydration
        Date of Visit: 2026-08-15
      ''';

      final extraction = OcrExtraction.fromText(formText);
      final seed = extraction.toFormSeed();

      expect(seed['patientName'], 'Juan Dela Cruz');
      expect(seed['patient'], 'Juan Dela Cruz');
      expect(seed['fullName'], 'Juan Dela Cruz');
      expect(seed['patientId'], 'PAT-2026-001');
      expect(seed['age'], '35');
      expect(seed['gender'], 'Male');
      expect(seed['sex'], 'Male');
      expect(seed['dateOfBirth'], '1991-04-20');
      expect(seed['civilStatus'], 'Married');
      expect(seed['contactNumber'], '09171234567');
      expect(seed['bloodPressure'], '120/80');
      expect(seed['bp'], '120/80');
      expect(seed['temperature'], '36.6');
      expect(seed['temp'], '36.6');
      expect(seed['heartRate'], '72');
      expect(seed['hr'], '72');
      expect(seed['respiratoryRate'], '18');
      expect(seed['rr'], '18');
      expect(seed['oxygenSaturation'], '99');
      expect(seed['spo2'], '99');
      expect(seed['weight'], '65');
      expect(seed['wt'], '65');
      expect(seed['height'], '170');
      expect(seed['ht'], '170');
      expect(seed['symptoms'], 'Fever and mild cough');
      expect(seed['chiefComplaint'], 'Fever and mild cough');
      expect(seed['disease'], 'Upper Respiratory Tract Infection');
      expect(seed['diagnosis'], 'Upper Respiratory Tract Infection');
      expect(seed['date'], '2026-08-15');
      expect(seed['visitDate'], '2026-08-15');
    });

    test('accurately extracts and seeds realistic scanned Check-Up Form (CHK-2026) with stacked layout, hint instructions, and tabular vital signs', () {
      const realisticScannedCheckup = '''
        REPUBLIC OF THE PHILIPPINES
        PROVINCE OF CAVITE - BARANGAY HEALTH CENTER
        BARANGAY HEALTH CHECK-UP INTAKE FORM
        FORM: CHK-2026

        1. Patient Demographic Information
        Full Name (Last Name, First Name, Middle Name)
        Dela Cruz, Juan M.
        Patient ID (PAT-YYYY-XXXX)
        PAT-2026-0105
        Date of Birth (YYYY-MM-DD)
        1992-05-18
        Age (yrs/mos)
        34
        Sex
        [X] Male  [ ] Female
        Civil Status
        [ ] Single  [X] Married  [ ] Widowed  [ ] Separated
        Contact Number (09XX-XXX-XXXX)
        0917-888-9900
        Residential Address (House / Street / Zone / Sitio)
        45 Rizal Ave, Purok 3
        Barangay (e.g. Barangay 01)
        Barangay 01

        2. Vital Signs & Clinical Measurements
        Blood Pressure (BP) Body Temp (T) Pulse Rate (HR) Resp. Rate (RR) Oxygen Sat (SpO2) Weight (WT) Height (HT)
        mmHg (e.g. 120/80) °C (e.g. 36.5) bpm cpm % (e.g. 98) kg cm
        120/80 36.7 74 18 98 68 172

        3. Chief Complaint & Subjective Symptoms
        Chief Complaint / Reason for Visit / Symptoms
        (Describe onset, duration, severity, and associated symptoms)
        High fever for 3 days, body aches, and persistent dry cough
        
        4. Clinical Assessment & Diagnosis (Dx)
        Clinical Diagnosis / Disease Condition (Dx)
        (Primary diagnosis, ICD-10 or clinical impression)
        Acute Viral Upper Respiratory Tract Infection

        5. Treatment Plan, Medication (Rx) & Management
        Treatment Plan / Prescribed Medications (Rx) / Home Care Advice
        (Drug name, dosage, frequency, duration, precautions)
        Paracetamol 500mg tab every 4 hours PRN, increase oral hydration, rest for 3 days

        6. Encounter Metadata & Verification
        Date of Visit (YYYY-MM-DD)
        2026-08-18
        Encounter Status
        [X] Completed  [ ] Follow-Up Needed  [ ] Referred to Hospital
        Next Visit Date (YYYY-MM-DD)
        2026-08-25
      ''';

      final extraction = OcrExtraction.fromText(realisticScannedCheckup);
      final seed = extraction.toFormSeed();

      expect(seed['fullName'], 'Dela Cruz, Juan M.');
      expect(seed['patientName'], 'Dela Cruz, Juan M.');
      expect(seed['patientId'], 'PAT-2026-0105');
      expect(seed['dateOfBirth'], '1992-05-18');
      expect(seed['age'], '34');
      expect(seed['gender'], 'Male');
      expect(seed['sex'], 'Male');
      expect(seed['civilStatus'], 'Married');
      expect(seed['contactNumber'], '09178889900');
      expect(seed['address'], '45 Rizal Ave, Purok 3');
      expect(seed['barangay'], 'Barangay 01');
      expect(seed['bloodPressure'], '120/80');
      expect(seed['bp'], '120/80');
      expect(seed['temperature'], '36.7');
      expect(seed['temp'], '36.7');
      expect(seed['heartRate'], '74');
      expect(seed['hr'], '74');
      expect(seed['respiratoryRate'], '18');
      expect(seed['rr'], '18');
      expect(seed['oxygenSaturation'], '98');
      expect(seed['spo2'], '98');
      expect(seed['weight'], '68');
      expect(seed['wt'], '68');
      expect(seed['height'], '172');
      expect(seed['ht'], '172');
      expect(seed['symptoms'], 'High fever for 3 days, body aches, and persistent dry cough');
      expect(seed['chiefComplaint'], 'High fever for 3 days, body aches, and persistent dry cough');
      expect(seed['disease'], 'Acute Viral Upper Respiratory Tract Infection');
      expect(seed['diagnosis'], 'Acute Viral Upper Respiratory Tract Infection');
      expect(seed['treatment'], 'Paracetamol 500mg tab every 4 hours PRN, increase oral hydration, rest for 3 days');
      expect(seed['plan'], 'Paracetamol 500mg tab every 4 hours PRN, increase oral hydration, rest for 3 days');
      expect(seed['date'], '2026-08-18');
      expect(seed['visitDate'], '2026-08-18');
      expect(seed['nextVisitDate'], '2026-08-25');
      expect(seed['followUpDate'], '2026-08-25');
    });

    test('accurately extracts and seeds scanned Prenatal Care Form (PNC-2026)', () {
      const prenatalText = '''
        FORM: PNC-2026
        Maternal Full Name: Maria Santos Cruz
        Patient ID: PAT-2026-042
        Age: 27
        Date of Birth: 1999-03-12
        Civil Status: Married
        Contact Number: 0918-987-6543
        PhilHealth ID / No.: 12-345678901-2
        Residence Address: Zone 4, Sitio Riverside
        Barangay: Barangay 02
        Gravida (G): 2
        Para (P): 1
        Full Term (FT): 1
        Premature (PT): 0
        Abortion (AB): 0
        Living Children (LC): 1
        LMP: 2026-01-10
        EDD: 2026-10-17
        AOG: 31
        Blood Type: O+
        Pregnancy Risk Assessment Level: Low Risk
        Fundal Height (FH): 28
        Fetal Heart Beat (FHB): 142
        Tetanus Toxoid (TT) Dose: TT3
        Registration Date: 2026-08-16
      ''';

      final extraction = OcrExtraction.fromText(prenatalText);
      final seed = extraction.toFormSeed();

      expect(seed['patientName'], 'Maria Santos Cruz');
      expect(seed['patientId'], 'PAT-2026-042');
      expect(seed['age'], '27');
      expect(seed['dateOfBirth'], '1999-03-12');
      expect(seed['contactNumber'], '09189876543');
      expect(seed['philhealthNumber'], '12-345678901-2');
      expect(seed['philhealth'], '12-345678901-2');
      expect(seed['barangay'], 'Barangay 02');
      expect(seed['gravida'], '2');
      expect(seed['para'], '1');
      expect(seed['fullTerm'], '1');
      expect(seed['premature'], '0');
      expect(seed['abortion'], '0');
      expect(seed['livingChildren'], '1');
      expect(seed['lmpDate'], '2026-01-10');
      expect(seed['eddDate'], '2026-10-17');
      expect(seed['aog'], '31');
      expect(seed['gestationalAge'], '31');
      expect(seed['bloodType'], 'O+');
      expect(seed['riskLevel'], 'Low Risk');
      expect(seed['fh'], '28');
      expect(seed['dhb'], '142');
      expect(seed['fhb'], '142');
      expect(seed['tcb'], 'TT3');
      expect(seed['registrationDate'], '2026-08-16');
    });

    test('accurately extracts and seeds scanned Immunization Form (IMZ-2026)', () {
      const imzText = '''
        FORM: IMZ-2026
        Patient / Child Full Name: Baby Gabriel Reyes
        Patient ID: PAT-2026-088
        Date of Birth: 2026-02-14
        Age: 6
        Sex: Male
        Mother / Father / Guardian Full Name: Elena Reyes
        Contact Number: 0920-555-1234
        Residence Address: Purok 2, Brgy. 03
        Barangay: Barangay 03
        Vaccine / Antigen Type: Pentavalent
        Dose Number: 2nd Dose
        Batch / Lot Number: BATCH-PENTA-992
        Expiration Date: 2027-12-31
        Date Administered: 2026-08-14
        Vaccinator Name & Title: Maria Dela Cruz BHW
      ''';

      final extraction = OcrExtraction.fromText(imzText);
      final seed = extraction.toFormSeed();

      expect(seed['patientName'], 'Baby Gabriel Reyes');
      expect(seed['childName'], 'Baby Gabriel Reyes');
      expect(seed['patientId'], 'PAT-2026-088');
      expect(seed['dateOfBirth'], '2026-02-14');
      expect(seed['gender'], 'Male');
      expect(seed['sex'], 'Male');
      expect(seed['guardianName'], 'Elena Reyes');
      expect(seed['parentName'], 'Elena Reyes');
      expect(seed['contactNumber'], '09205551234');
      expect(seed['barangay'], 'Barangay 03');
      expect(seed['vaccine'], 'Pentavalent');
      expect(seed['antigen'], 'Pentavalent');
      expect(seed['dose'], '2nd Dose');
      expect(seed['doseNumber'], '2nd Dose');
      expect(seed['batchNumber'], 'BATCH-PENTA-992');
      expect(seed['lotNumber'], 'BATCH-PENTA-992');
      expect(seed['expirationDate'], '2027-12-31');
      expect(seed['administrationDate'], '2026-08-14');
      expect(seed['registeredBy'], 'Maria Dela Cruz BHW');
      expect(seed['administeredBy'], 'Maria Dela Cruz BHW');
    });

    test('accurately extracts and seeds scanned Mortality Form (MOR-2026)', () {
      const morText = '''
        FORM: MOR-2026
        Full Name of Deceased: Pedro Alvarez Cruz
        Patient / Record ID: REC-2026-104
        Date of Birth: 1952-11-20
        Age at Death: 73
        Sex: Male
        Civil Status: Widowed
        Occupation: Retired Farmer
        Usual Residence Address: Zone 1, Brgy. 04
        Barangay: Barangay 04
        Date of Death: 2026-08-12
        Time of Death: 04:30 PM
        Place of Death: Home / Residence
        Immediate Cause of Death: Acute Myocardial Infarction
        Reported By: Nurse Jane Santos
      ''';

      final extraction = OcrExtraction.fromText(morText);
      final seed = extraction.toFormSeed();

      expect(seed['patientName'], 'Pedro Alvarez Cruz');
      expect(seed['name'], 'Pedro Alvarez Cruz');
      expect(seed['patientId'], 'REC-2026-104');
      expect(seed['dateOfBirth'], '1952-11-20');
      expect(seed['age'], '73');
      expect(seed['gender'], 'Male');
      expect(seed['civilStatus'], 'Widowed');
      expect(seed['occupation'], 'Retired Farmer');
      expect(seed['barangay'], 'Barangay 04');
      expect(seed['dateOfDeath'], '2026-08-12');
      expect(seed['dateTimeOfDeath'], '2026-08-12');
      expect(seed['timeOfDeath'], '04:30 PM');
      expect(seed['placeOfDeath'], 'Home / Residence');
      expect(seed['causeOfDeath'], 'Acute Myocardial Infarction');
      expect(seed['cause'], 'Acute Myocardial Infarction');
      expect(seed['reportedBy'], 'Nurse Jane Santos');
    });

    test('accurately extracts and seeds scanned Morbidity Form (MBD-2026)', () {
      const mbdText = '''
        FORM: MBD-2026
        Patient Full Name: Ana Theresa Lim
        Patient ID: PAT-2026-215
        Date of Birth: 2005-09-08
        Age: 20
        Sex: Female
        Contact Number: 0917-234-5678
        PhilHealth No.: 22-998877665-0
        Residence Address: Street 3, Brgy. 05
        Barangay: Barangay 05
        Disease / Diagnosis (Dx): Dengue Fever
        Date of Onset of Symptoms: 2026-08-10
        Symptoms / Chief Complaints: High grade fever, retro-orbital pain, skin petechiae
        Treatment Plan: Oral Rehydration Therapy, close platelet monitoring
        Date Reported: 2026-08-14
        Reported By: Health Worker Roy
      ''';

      final extraction = OcrExtraction.fromText(mbdText);
      final seed = extraction.toFormSeed();

      expect(seed['patientName'], 'Ana Theresa Lim');
      expect(seed['patientId'], 'PAT-2026-215');
      expect(seed['dateOfBirth'], '2005-09-08');
      expect(seed['age'], '20');
      expect(seed['gender'], 'Female');
      expect(seed['contactNumber'], '09172345678');
      expect(seed['philhealthNumber'], '22-998877665-0');
      expect(seed['barangay'], 'Barangay 05');
      expect(seed['disease'], 'Dengue Fever');
      expect(seed['diagnosis'], 'Dengue Fever');
      expect(seed['dateOfOnset'], '2026-08-10');
      expect(seed['symptoms'], 'High grade fever, retro-orbital pain, skin petechiae');
      expect(seed['treatment'], 'Oral Rehydration Therapy, close platelet monitoring');
      expect(seed['dateReported'], '2026-08-14');
      expect(seed['reportedBy'], 'Health Worker Roy');
    });
  });
}
