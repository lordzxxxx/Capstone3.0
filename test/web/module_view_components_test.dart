import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mycapstone_project/web/shared/components/module_view_components.dart';
import 'package:mycapstone_project/web/shared/components/web_data_components.dart';
import 'package:mycapstone_project/web/roles/cho/portal/cho_portal_components.dart';

void main() {
  test('view parser defaults safely to insights', () {
    expect(parseHealthModuleView(null), HealthModuleView.insights);
    expect(parseHealthModuleView('unexpected'), HealthModuleView.insights);
    expect(parseHealthModuleView('records'), HealthModuleView.records);
    expect(parseHealthModuleView('RECORDS'), HealthModuleView.records);
  });

  testWidgets('module view tabs expose and change both views', (tester) async {
    var selected = HealthModuleView.insights;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => HealthModuleViewTabs(
              activeView: selected,
              onChanged: (value) => setState(() => selected = value),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Insights'), findsOneWidget);
    expect(find.text('Records'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('module-view-records')));
    await tester.pump();

    expect(selected, HealthModuleView.records);
  });

  testWidgets('module header stacks controls at narrow web widths', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(520, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HealthModuleViewHeader(
            title: 'Check-up Management',
            description: 'Review insights or manage records.',
            activeView: HealthModuleView.insights,
            onViewChanged: (_) {},
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Check-up Management'), findsOneWidget);
    expect(find.text('Records'), findsOneWidget);
  });

  testWidgets('CHO KPI card grows for narrow, wrapped content', (tester) async {
    tester.view.physicalSize = const Size(280, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(12),
            child: ChoKpiCard(
              label: 'Pending validation records',
              value: '128',
              icon: Icons.fact_check_outlined,
              supportingText:
                  'Submitted records waiting for review from the city health office.',
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('128'), findsOneWidget);
  });

  testWidgets('CHO header and escalation badge remain usable at phone width', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                ChoPageHeader(
                  title: 'Referral review',
                  description:
                      'Review urgent referrals and return incomplete records.',
                  icon: Icons.assignment_turned_in_outlined,
                  actions: [
                    FilledButton(onPressed: () {}, child: const Text('Export')),
                  ],
                ),
                const SizedBox(height: 12),
                const ChoStatusBadge('Urgent referral'),
              ],
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Referral review'), findsOneWidget);
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
  });

  testWidgets('adaptive records use labelled cards instead of a wide table', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: WebAdaptiveRecords(
            table: Text('Desktop table'),
            cards: [Text('Patient record'), Text('Vital signs')],
          ),
        ),
      ),
    );

    expect(find.text('Patient record'), findsOneWidget);
    expect(find.text('Vital signs'), findsOneWidget);
    expect(find.text('Desktop table'), findsNothing);
  });

  testWidgets('loading skeleton announces one clear loading state', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: WebContentLoadingSkeleton(label: 'Loading patient records'),
        ),
      ),
    );

    expect(find.bySemanticsLabel('Loading patient records'), findsOneWidget);
  });

  testWidgets('compact record card exposes one readable record label', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: WebRecordCard(
            label: 'Patient Ana Santos. Status active.',
            child: Text('Ana Santos'),
          ),
        ),
      ),
    );

    expect(find.byType(WebRecordCard), findsOneWidget);
    expect(find.text('Ana Santos'), findsOneWidget);
  });
}
