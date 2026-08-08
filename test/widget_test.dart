import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:mycapstone_project/main.dart';

void main() {
  testWidgets('application shell renders', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    expect(find.byType(GetMaterialApp), findsOneWidget);
  });
}
