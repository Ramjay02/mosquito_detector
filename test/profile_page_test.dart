import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosquito_detector/src/auth/auth_controller.dart';
import 'package:mosquito_detector/src/profile_page.dart';

void main() {
  testWidgets('profile replaces sample card with account actions', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: ProfilePage()));
    await tester.drag(find.byType(ListView), const Offset(0, -900));
    await tester.pumpAndSettle();
    expect(find.text('Not signed in'), findsOneWidget);
    expect(find.text('Refresh status'), findsOneWidget);
    expect(find.text('Sign out'), findsOneWidget);
  });

  testWidgets('profile shows real account details', (
    WidgetTester tester,
  ) async {
    final AuthController controller = AuthController();
    controller.currentUser = const AuthUser(
      id: 7,
      fullName: 'Maria Santos',
      email: 'maria@example.com',
      role: 'field_worker',
      status: 'active',
    );
    await tester.pumpWidget(
      MaterialApp(home: ProfilePage(controller: controller)),
    );
    expect(find.text('Maria Santos'), findsOneWidget);
    expect(find.text('maria@example.com'), findsOneWidget);
    expect(find.text('Field worker'), findsOneWidget);
    controller.dispose();
  });
}
