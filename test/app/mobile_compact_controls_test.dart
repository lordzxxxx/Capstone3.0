import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mycapstone_project/app/shared/widgets/mobile_compact_controls.dart';
import 'package:mycapstone_project/app/shared/widgets/ocr_record_action.dart';
import 'package:mycapstone_project/app/shared/widgets/mobile_record_action_sheet.dart';
import 'package:mycapstone_project/app/theme/app_theme.dart';

void main() {
  testWidgets('compact search control remains usable on a narrow phone', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: AppDesign.theme(),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                const SizedBox(width: 46, height: 46),
                const SizedBox(width: 8),
                Expanded(
                  child: MobileSearchField(
                    controller: controller,
                    hintText: 'Search records',
                    onChanged: (_) {},
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Search records'), findsOneWidget);
  });

  testWidgets('record actions stay compact without layout overflow', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: AppDesign.theme(),
        home: Scaffold(
          floatingActionButton: RecordCreationFabGroup(
            moduleLabel: 'Patient',
            manualLabel: 'New Patient',
            onManualCreate: () {},
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('OCR'), findsOneWidget);
    expect(find.text('New Patient'), findsOneWidget);
    expect(
      tester.getSize(find.text('New Patient')).height,
      lessThanOrEqualTo(44),
    );
  });

  testWidgets('record action sheet stays readable on a narrow phone', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: AppDesign.theme(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => MobileRecordActionSheet.show(
                  context: context,
                  title: 'Angela Garcia Ramos',
                  actions: [
                    MobileRecordAction(
                      label: 'View Patient History',
                      icon: Icons.history_rounded,
                      tone: MobileRecordActionTone.primary,
                      onPressed: () {},
                    ),
                    MobileRecordAction(
                      label: 'Edit Details',
                      icon: Icons.edit_outlined,
                      onPressed: () {},
                    ),
                    MobileRecordAction(
                      label: 'Delete Record',
                      icon: Icons.delete_outline,
                      tone: MobileRecordActionTone.danger,
                      onPressed: () {},
                    ),
                  ],
                ),
                child: const Text('Open actions'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open actions'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Angela Garcia Ramos'), findsOneWidget);
    expect(find.text('View Patient History'), findsOneWidget);
    expect(find.text('Edit Details'), findsOneWidget);
    expect(find.text('Delete Record'), findsOneWidget);
  });
}
