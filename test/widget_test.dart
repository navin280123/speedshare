// This is a basic Flutter widget test for SpeedShare.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speedshare/main.dart';

void main() {
  testWidgets('SpeedShare app launches correctly', (WidgetTester tester) async {
    // Set up a mock SharedPreferences instance
    SharedPreferences.setMockInitialValues({
      'darkMode': false,
      'deviceName': 'Test Device',
    });
    
    // Build our app and trigger a frame
    await tester.pumpWidget(MyApp(darkMode: false));
    await tester.pumpAndSettle(); // Wait for animations to complete

    // Verify that the app title is displayed
    expect(find.text('SpeedShare'), findsOneWidget);
    
    // Verify the welcome text is shown
    expect(find.text('Welcome to SpeedShare'), findsOneWidget);
    
    // Verify that the main action buttons are present
    expect(find.text('Send Files'), findsAtLeastNWidgets(1));
    expect(find.text('Receive Files'), findsAtLeastNWidgets(1));
    
    // Verify that the sidebar options exist
    expect(find.text('Send'), findsOneWidget);
    expect(find.text('Receive'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);

    // Verify that the user information is shown
    
    // Test navigation to Send screen
    await tester.tap(find.text('Send').first);
    await tester.pumpAndSettle();
    expect(find.text('Select File'), findsOneWidget);
    
    // Note: Further interaction tests would be added in a real test suite,
    // but many operations require actual file system access or network
    // connections which are difficult to mock in widget tests.
  });
}