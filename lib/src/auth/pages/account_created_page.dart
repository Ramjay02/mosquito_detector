import 'package:flutter/material.dart';

import '../auth_controller.dart';
import '../../app_shell.dart';
import 'login_page.dart';

class AccountCreatedPage extends StatelessWidget {
  const AccountCreatedPage({
    super.key,
    required this.controller,
    required this.signedIn,
  });

  final AuthController controller;
  final bool signedIn;

  @override
  Widget build(BuildContext context) {
    return PopScope<Object?>(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(
                    Icons.check_circle_outline,
                    size: 80,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Account created successfully',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Your e-mail is verified.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 28),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      key: ValueKey<String>(
                        signedIn
                            ? 'account-created-start-scanning'
                            : 'account-created-go-login',
                      ),
                      onPressed: () async {
                        if (signedIn) {
                          controller.finishAccountCreatedScreen();
                          Navigator.of(context).pushAndRemoveUntil(
                            MaterialPageRoute<void>(
                              builder: (_) =>
                                  AppShell(authController: controller),
                            ),
                            (_) => false,
                          );
                        } else {
                          await controller.signOut(callServer: false);
                          controller.finishAccountCreatedScreen();
                          Navigator.of(context).pushAndRemoveUntil(
                            MaterialPageRoute<void>(
                              builder: (_) => LoginPage(controller: controller),
                            ),
                            (_) => false,
                          );
                        }
                      },
                      child: Text(signedIn ? 'Start scanning' : 'Go to login'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
