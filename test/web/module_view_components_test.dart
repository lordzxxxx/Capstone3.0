import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mycapstone_project/web/shared/components/module_view_components.dart';
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
}
