import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mycapstone_project/web/features/auth/public_auth_background.dart';

void main() {
  testWidgets('public auth backdrop uses the supplied background asset', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: PublicAuthBackdrop(child: Center(child: Text('Public surface'))),
      ),
    );

    expect(find.text('Public surface'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Image &&
            widget.image is AssetImage &&
            (widget.image as AssetImage).assetName == 'assets/newbg.png',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
