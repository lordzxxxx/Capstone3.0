import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mycapstone_project/app/features/patients/patient.dart';

// Regression coverage for the Add Patient modal's Form validation.
//
// The modal is a 10-page PageView wizard, and its 5 required fields
// (First Name, Surname, Phone Number, Emergency Contact Name, Registered
// By) live on 4 different, non-adjacent pages (0, 1, 4 and 9). PageView
// disposes off-screen pages by default, which would silently unregister
// their TextFormFields from the shared Form/_formKey the moment the user
// pages away - making validate() skip them entirely. These tests fill the
// fields across pages exactly like a real user would (typing on each page,
// then tapping Next) and confirm the save flow is still gated correctly by
// the time the user reaches the last page.
//
// There is no sqflite/connectivity/Firebase test scaffolding in this repo,
// so a fully successful save can't be asserted here. Instead, once
// validation passes, _savePatient's try block calls
// PatientDatabaseHelper.instance.insertRecord, which immediately hits the
// (unmocked, in this test environment) connectivity_plus platform channel
// and throws MissingPluginException. That is caught and surfaced as a red
// "Error saving patient: ..." SnackBar. Its presence/absence is used below
// as the signal for "validation passed and the save flow proceeded" vs.
// "validation blocked the save before it ever reached persistence".
void main() {
  Finder fieldFor(String label) {
    final wrapper = find.ancestor(
      of: find.text(label),
      matching: find.byType(Padding),
    ).first;
    return find.descendant(of: wrapper, matching: find.byType(TextFormField));
  }

  Future<void> goToNextPage(WidgetTester tester) async {
    final next = find.widgetWithText(ElevatedButton, 'Next');
    await tester.ensureVisible(next);
    await tester.tap(next);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Save is blocked when a required field on an earlier page is empty',
    (tester) async {
      var savedCount = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: AddPatientModal(onSaved: (_) async => savedCount++),
        ),
      );
      await tester.pumpAndSettle();

      // Page 0 (Personal Details): fill Surname but deliberately leave
      // First Name empty.
      await tester.enterText(fieldFor('Surname'), 'Dela Cruz');
      await goToNextPage(tester);

      // Page 1 (Contact Information): fill Phone Number.
      await tester.enterText(fieldFor('Phone Number'), '09171234567');
      await goToNextPage(tester); // -> page 2
      await goToNextPage(tester); // -> page 3
      await goToNextPage(tester); // -> page 4

      // Page 4 (Emergency Contact): fill Emergency Contact Name.
      await tester.enterText(
        fieldFor('Emergency Contact Name'),
        'Juan Dela Cruz',
      );
      await goToNextPage(tester); // -> page 5
      await goToNextPage(tester); // -> page 6
      await goToNextPage(tester); // -> page 7
      await goToNextPage(tester); // -> page 8
      await goToNextPage(tester); // -> page 9

      // Page 9 (Consent and Registration): give consent and fill Registered
      // By, but First Name (page 0, now scrolled away) is still empty.
      final consentCheckbox = find.byType(Checkbox);
      await tester.ensureVisible(consentCheckbox);
      await tester.tap(consentCheckbox);
      await tester.pump();
      final registeredByField = fieldFor('Registered By');
      await tester.ensureVisible(registeredByField);
      await tester.enterText(registeredByField, 'BHW Reyes');

      final completeButton = find.widgetWithText(ElevatedButton, 'Complete');
      await tester.ensureVisible(completeButton);
      // See the matching runAsync note in the second test below: without
      // stepping outside the FakeAsync zone, a MissingPluginException from
      // reaching persistence would never actually surface here either,
      // which would make the "no DB error" assertion below pass trivially
      // regardless of whether validation really blocked the save.
      await tester.runAsync(() async {
        await tester.tap(completeButton);
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // The save must not have gone through to the database/onSaved
      // callback: the empty First Name field should have blocked it even
      // though its page is no longer the visible one.
      expect(savedCount, 0);
      expect(find.textContaining('Error saving patient'), findsNothing);
      expect(find.text('Add New Patient'), findsOneWidget);
    },
  );

  testWidgets(
    'Save proceeds past validation once all 5 required fields are filled',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: AddPatientModal()));
      await tester.pumpAndSettle();

      // Page 0 (Personal Details).
      await tester.enterText(fieldFor('First Name'), 'Maria');
      await tester.enterText(fieldFor('Surname'), 'Dela Cruz');
      await goToNextPage(tester);

      // Page 1 (Contact Information).
      await tester.enterText(fieldFor('Phone Number'), '09171234567');
      await goToNextPage(tester); // -> page 2
      await goToNextPage(tester); // -> page 3
      await goToNextPage(tester); // -> page 4

      // Page 4 (Emergency Contact).
      await tester.enterText(
        fieldFor('Emergency Contact Name'),
        'Juan Dela Cruz',
      );
      await goToNextPage(tester); // -> page 5
      await goToNextPage(tester); // -> page 6
      await goToNextPage(tester); // -> page 7
      await goToNextPage(tester); // -> page 8
      await goToNextPage(tester); // -> page 9

      // Page 9 (Consent and Registration).
      final consentCheckbox = find.byType(Checkbox);
      await tester.ensureVisible(consentCheckbox);
      await tester.tap(consentCheckbox);
      await tester.pump();
      final registeredByField = fieldFor('Registered By');
      await tester.ensureVisible(registeredByField);
      await tester.enterText(registeredByField, 'BHW Reyes');

      final completeButton = find.widgetWithText(ElevatedButton, 'Complete');
      await tester.ensureVisible(completeButton);
      // runAsync briefly steps outside the FakeAsync test zone: the
      // MissingPluginException from the unmocked platform channel is
      // delivered through a real async gap that plain pump() calls don't
      // resolve. Also deliberately not pumpAndSettle() afterwards: the
      // resulting SnackBar auto-dismisses after a few seconds, and
      // pumpAndSettle() would run that whole show-then-dismiss animation to
      // completion before returning, leaving nothing to assert on.
      await tester.runAsync(() async {
        await tester.tap(completeButton);
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // No inline validation errors, and the save flow reached persistence
      // (surfacing the expected plugin/database error in this offline test
      // environment) instead of being blocked by the Form validator.
      expect(find.text('Required'), findsNothing);
      expect(find.textContaining('Error saving patient'), findsOneWidget);
    },
  );
}
