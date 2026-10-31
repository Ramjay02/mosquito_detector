import 'package:flutter/material.dart';

import '../auth_controller.dart';

class AwaitingApprovalPage extends StatelessWidget {
  const AwaitingApprovalPage({super.key, required this.controller});

  final AuthController controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Account approval')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.hourglass_top_outlined, size: 64),
              const SizedBox(height: 16),
              const Text(
                'Your account is waiting for administrator approval.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => controller.refreshStatus(),
                child: const Text('Check again'),
              ),
              TextButton(
                onPressed: () => controller.signOut(callServer: false),
                child: const Text('Back to sign in'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
