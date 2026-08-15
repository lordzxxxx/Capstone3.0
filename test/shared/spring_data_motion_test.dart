import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mycapstone_project/shared/widgets/spring_data_motion.dart';

void main() {
  testWidgets('renders data surfaces without changing their content', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SpringDataMotion(
          dataKey: 'initial',
          child: const Text('Live chart'),
        ),
      ),
    );

    expect(find.text('Live chart'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('Live chart'), findsOneWidget);
  });

  testWidgets('honors reduced-motion settings', (tester) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: MaterialApp(
          home: SpringDataMotion(
            dataKey: 'initial',
            child: const Text('Reduced motion chart'),
          ),
        ),
      ),
    );

    expect(find.text('Reduced motion chart'), findsOneWidget);
  });

  test('creates stable keys for reconstructed chart entries', () {
    expect(
      SpringDataKey.entries(const [
        MapEntry('January', 4),
        MapEntry('February', 7),
      ]),
      'January:4|February:7',
    );
  });
}
