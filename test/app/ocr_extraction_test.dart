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

    test('normalizes compact Philippine mobile numbers', () {
      final extraction = OcrExtraction.fromText('Phone 9171234567');
      expect(extraction.fields['contactNumber']?.value, '09171234567');
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
}
