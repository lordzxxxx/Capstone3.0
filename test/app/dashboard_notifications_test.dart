import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:mycapstone_project/app/features/dashboard/widgets/dashboard_notifications_sheet.dart';

void main() {
  setUp(() {
    Get.testMode = true;
  });

  testWidgets('DashboardNotificationsSheet renders filter chips, search, and action buttons', (tester) async {
    bool testNotificationTriggered = false;

    await tester.pumpWidget(
      GetMaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 900,
            width: 500,
            child: DashboardNotificationsSheet(
              onUnreadCountChanged: (_) {},
              onTriggerLocalNotification: ({required String title, required String body}) async {
                testNotificationTriggered = true;
              },
            ),
          ),
        ),
      ),
    );

    // Pump a few frames
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // Verify header and elements render
    expect(find.text('Notifications'), findsOneWidget);
    expect(find.text('Live clinical alerts and announcements'), findsOneWidget);

    // Verify filter chips render
    expect(find.text('All'), findsOneWidget);
    expect(find.text('Alerts'), findsOneWidget);
    expect(find.text('Announcements'), findsOneWidget);
    expect(find.text('Clinical'), findsOneWidget);
    expect(find.text('System'), findsOneWidget);

    // Verify search box renders
    expect(find.byType(TextField), findsOneWidget);

    // Verify action buttons render
    expect(find.text('Test Alert'), findsOneWidget);
    expect(find.text('Refresh'), findsOneWidget);

    // Test Triggering Device Notification
    final testAlertButton = find.widgetWithText(OutlinedButton, 'Test Alert');
    expect(testAlertButton, findsOneWidget);
    await tester.tap(testAlertButton);
    await tester.pump();

    expect(testNotificationTriggered, isTrue);

    // Verify 'Mark all as read' icon button exists
    final markAllButton = find.byTooltip('Mark all as read');
    expect(markAllButton, findsOneWidget);
  });
}
