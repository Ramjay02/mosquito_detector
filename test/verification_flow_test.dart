import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mosquito_detector/src/auth/auth_controller.dart';
import 'package:mosquito_detector/src/auth/auth_api.dart';
import 'package:mosquito_detector/src/auth/pages/account_created_page.dart';
import 'package:mosquito_detector/src/auth/pages/login_page.dart';
import 'package:mosquito_detector/src/auth/pages/verify_email_page.dart';
import 'package:mosquito_detector/src/app_shell.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'verify button disables and sends one request for repeated taps',
    (WidgetTester tester) async {
      final Completer<http.Response> response = Completer<http.Response>();
      int requestCount = 0;
      final AuthController controller = AuthController(
        api: AuthApi(
          client: MockClient((http.Request request) async {
            requestCount++;
            return response.future;
          }),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: VerifyEmailPage(
            controller: controller,
            email: 'test@example.com',
            passwordInMemory: 'Password123',
          ),
        ),
      );
      await tester.enterText(
        find.byKey(const ValueKey<String>('verify-code-field')),
        '123456',
      );
      await tester.tap(find.byKey(const ValueKey<String>('verify-submit')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey<String>('verify-submit')));
      await tester.pump();
      expect(requestCount, 1);
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey<String>('verify-code-field')),
            )
            .enabled,
        isFalse,
      );
      response.complete(
        http.Response(
          jsonEncode(<String, dynamic>{
            'ok': false,
            'code': 'invalid_code',
            'message': '',
            'data': null,
          }),
          400,
          headers: <String, String>{'content-type': 'application/json'},
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('That code is not valid. Check it or request a new one.'),
        findsOneWidget,
      );
    },
  );

  testWidgets('successful verification replaces with account created page', (
    WidgetTester tester,
  ) async {
    final AuthController controller = AuthController(
      api: AuthApi(
        client: MockClient((http.Request request) async {
          return http.Response(
            jsonEncode(<String, dynamic>{
              'ok': true,
              'code': 'ok',
              'message': '',
              'data': <String, dynamic>{'status': 'active'},
            }),
            200,
            headers: <String, String>{'content-type': 'application/json'},
          );
        }),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: VerifyEmailPage(
          controller: controller,
          email: 'test@example.com',
        ),
      ),
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('verify-code-field')),
      '123456',
    );
    await tester.tap(find.byKey(const ValueKey<String>('verify-submit')));
    await tester.pumpAndSettle();
    expect(find.text('Your e-mail is verified.'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('account-created-go-login')),
      findsOneWidget,
    );
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Your e-mail is verified.'), findsOneWidget);
  });

  testWidgets('account created start scanning clears success flag', (
    WidgetTester tester,
  ) async {
    final AuthController controller = AuthController();
    controller.status = AuthStatus.signedIn;
    await tester.pumpWidget(
      MaterialApp(
        home: AccountCreatedPage(controller: controller, signedIn: true),
      ),
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('account-created-start-scanning')),
    );
    await tester.pumpAndSettle();
    expect(controller.showingAccountCreated, isFalse);
    expect(find.byType(AppShell), findsOneWidget);
  });

  testWidgets('email_not_verified login opens verification with email', (
    WidgetTester tester,
  ) async {
    final AuthController controller = AuthController(
      api: AuthApi(
        client: MockClient((http.Request request) async {
          return http.Response(
            jsonEncode(<String, dynamic>{
              'ok': false,
              'code': 'email_not_verified',
              'message': '',
              'data': null,
            }),
            403,
            headers: <String, String>{'content-type': 'application/json'},
          );
        }),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(home: LoginPage(controller: controller)),
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'E-mail'),
      'verify@example.com',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Password'),
      'Password123',
    );
    await tester.tap(find.byKey(const ValueKey<String>('login-submit')));
    await tester.pumpAndSettle();
    expect(find.byType(VerifyEmailPage), findsOneWidget);
    final VerifyEmailPage verify = tester.widget<VerifyEmailPage>(
      find.byType(VerifyEmailPage),
    );
    expect(verify.email, 'verify@example.com');
  });
}
