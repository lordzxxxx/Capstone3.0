import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mycapstone_project/app/features/surveillance/morbidity/morbidity.dart';

Future<void> _openNewMorbidityModal(WidgetTester tester) async {
  await tester.pumpWidget(const MaterialApp(home: MorbidityPage()));
  await tester.pump();

  await tester.tap(find.byKey(const ValueKey('manual-Morbidity')));
  await tester.pumpAndSettle();

  expect(find.text('New Morbidity Record'), findsOneWidget);
}

void main() {
  testWidgets('save is blocked when required fields are empty', (tester) async {
    await _openNewMorbidityModal(tester);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
    await tester.pump();

    expect(find.text('Patient name is required'), findsOneWidget);
    expect(find.text('Age is required'), findsOneWidget);
    expect(find.text('Disease is required'), findsOneWidget);
    // Dialog stays open so the user can correct the form.
    expect(find.text('New Morbidity Record'), findsOneWidget);
  });

  testWidgets('save is blocked when age is not a valid number', (tester) async {
    await _openNewMorbidityModal(tester);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Patient Name'),
      'Juan Dela Cruz',
    );
    await tester.enterText(find.widgetWithText(TextFormField, 'Age'), 'twenty');
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Disease'),
      'Dengue',
    );

    await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
    await tester.pump();

    expect(find.text('Enter a valid age (0-130)'), findsOneWidget);
    expect(find.text('New Morbidity Record'), findsOneWidget);
  });

  testWidgets('a valid form passes validation and does not close the dialog '
      'before the save resolves', (tester) async {
    await _openNewMorbidityModal(tester);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Patient Name'),
      'Juan Dela Cruz',
    );
    await tester.enterText(find.widgetWithText(TextFormField, 'Age'), '34');
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Disease'),
      'Dengue',
    );

    await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
    await tester.pumpAndSettle();

    // No validation errors: the form passed and the save path was invoked.
    expect(find.text('Patient name is required'), findsNothing);
    expect(find.text('Age is required'), findsNothing);
    expect(find.text('Disease is required'), findsNothing);

    // The sqflite/connectivity plugins have no handler under flutter_test, so
    // the insert never resolves here. The dialog must therefore still be open
    // with the typed input intact: it may only close once the save completes.
    expect(find.text('New Morbidity Record'), findsOneWidget);
    expect(find.text('Juan Dela Cruz'), findsOneWidget);
    expect(find.text('Record added successfully'), findsNothing);
  });
}
