import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mycapstone_project/app/shared/widgets/ocr_record_action.dart';

void main() {
  testWidgets('record creation actions expose OCR and manual entry', (
    tester,
  ) async {
    var manualCreateCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          floatingActionButton: RecordCreationFabGroup(
            moduleLabel: 'Check-up test',
            manualLabel: 'New Check-up',
            onManualCreate: () => manualCreateCount++,
          ),
        ),
      ),
    );

    expect(find.text('OCR'), findsOneWidget);
    expect(find.byIcon(Icons.document_scanner_outlined), findsOneWidget);
    expect(find.text('New Check-up'), findsOneWidget);

    await tester.tap(find.text('New Check-up'));
    await tester.pump();
    expect(manualCreateCount, 1);
  });
}
