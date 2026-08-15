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
  });
}
