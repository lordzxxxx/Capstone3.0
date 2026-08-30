import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mycapstone_project/app/features/patients/patient.dart';

void main() {
  Finder fieldFor(String label) {
    return find.byWidgetPredicate((widget) {
      if (widget is! TextField) return false;
      final labelText = widget.decoration?.labelText ?? '';
      return labelText.toLowerCase().contains(label.toLowerCase());
    });
  }

  testWidgets(
    'Save is blocked when a required field is empty',
    (tester) async {
      var savedCount = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 1000,
              width: 800,
              child: AddPatientModal(onSaved: (_) async => savedCount++),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final surname = fieldFor('Surname');
      await tester.ensureVisible(surname);
      await tester.enterText(surname, 'Dela Cruz');

      final address = fieldFor('Address');
      await tester.ensureVisible(address);
      await tester.enterText(address, 'Purok 1');

      final brgy = fieldFor('Barangay');
      await tester.ensureVisible(brgy);
      await tester.enterText(brgy, 'Casisang');

      final emName = fieldFor('Emergency Contact Name');
      await tester.ensureVisible(emName);
      await tester.enterText(emName, 'Juan Dela Cruz');

      final emNum = fieldFor('Emergency Contact Number');
      await tester.ensureVisible(emNum);
      await tester.enterText(emNum, '09171234567');

      final registerButton = find.widgetWithText(ElevatedButton, 'Register Patient');
      await tester.ensureVisible(registerButton);

      await tester.runAsync(() async {
        await tester.tap(registerButton);
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(savedCount, 0);
      expect(find.textContaining('Error saving patient'), findsNothing);
      expect(find.text('Add New Patient'), findsOneWidget);
    },
  );

  testWidgets(
    'Save proceeds past validation once all required fields are filled',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 1000,
              width: 800,
              child: AddPatientModal(
                initialValues: {'dateOfBirth': '1995-05-15'},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final firstName = fieldFor('First Name');
      await tester.ensureVisible(firstName);
      await tester.enterText(firstName, 'Maria');

      final surname = fieldFor('Surname');
      await tester.ensureVisible(surname);
      await tester.enterText(surname, 'Dela Cruz');

      final address = fieldFor('Address');
      await tester.ensureVisible(address);
      await tester.enterText(address, 'Purok 4, Casisang');

      final brgy = fieldFor('Barangay');
      await tester.ensureVisible(brgy);
      await tester.enterText(brgy, 'Casisang');

      final emName = fieldFor('Emergency Contact Name');
      await tester.ensureVisible(emName);
      await tester.enterText(emName, 'Juan Dela Cruz');

      final emNum = fieldFor('Emergency Contact Number');
      await tester.ensureVisible(emNum);
      await tester.enterText(emNum, '09171234567');

      final registerButton = find.widgetWithText(ElevatedButton, 'Register Patient');
      await tester.ensureVisible(registerButton);

      await tester.runAsync(() async {
        await tester.tap(registerButton);
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('First Name is required'), findsNothing);
      expect(find.textContaining('Error saving patient'), findsOneWidget);
    },
  );
}
