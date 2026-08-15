# OCR workflow

The mobile app uses Google ML Kit Text Recognition through the shared
`RecordCreationFabGroup` and `OcrRecordCapture` flow. OCR is available in the
Android/iOS mobile app; the web UI keeps manual entry available.

## User flow

1. The worker chooses **Create with OCR** from a supported record module.
2. The app explains why camera or photo permission is needed, immediately
   before the operating-system permission request.
3. The worker captures a form or chooses an existing image.
4. ML Kit returns recognized text. The app closes the recognizer after use.
5. `OcrExtraction.fromRecognizedText` parses labeled fields by content rather
   than by screen position.
6. The review screen shows every detected field, confidence, raw text, and
   fields requiring manual review.
7. The worker edits or confirms the values and continues to the ordinary form.
8. Normal validation and the existing local/Firestore save path complete the
   record. OCR never bypasses required-field or data-format validation.

## Safety and privacy behavior

- Low-confidence or invalid values are not silently seeded into the form.
- A denied camera/gallery permission gives a recovery message and manual-entry
  option; it is not treated as an application failure.
- The camera is not opened at startup and no background camera/gallery access
  is requested.
- OCR is data-entry assistance, not clinical interpretation or diagnosis.

## Code and test evidence

- Implementation: `lib/app/shared/widgets/ocr_record_action.dart`
- Parser tests: `test/app/ocr_extraction_test.dart`
- Action/widget test: `test/app/ocr_record_action_test.dart`
- Form validation tests: `test/app/add_patient_modal_validation_test.dart` and
  `test/app/morbidity_new_record_test.dart`
- Field-level accuracy status: `docs/OCR_ACCURACY_TABLE.md`
