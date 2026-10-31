import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../auth_controller.dart';
import 'register_page.dart';
import 'account_created_page.dart';

class VerifyEmailPage extends StatefulWidget {
  const VerifyEmailPage({
    super.key,
    required this.controller,
    required this.email,
    this.passwordInMemory,
    this.initialResendSeconds = 60,
  });

  final AuthController controller;
  final String email;
  final String? passwordInMemory;
  final int initialResendSeconds;

  @override
  State<VerifyEmailPage> createState() => _VerifyEmailPageState();
}

class _VerifyEmailPageState extends State<VerifyEmailPage> {
  final TextEditingController _code = TextEditingController();
  Timer? _timer;
  late int _remaining;
  bool _loading = false;
  String? _error;
  String? _passwordInMemory;

  @override
  void initState() {
    super.initState();
    _remaining = widget.initialResendSeconds;
    _passwordInMemory =
        widget.controller.registrationPassword ?? widget.passwordInMemory;
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        if (_remaining > 0) _remaining--;
      });
      if (_remaining == 0) _timer?.cancel();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _code.dispose();
    _passwordInMemory = null;
    widget.controller.clearRegistrationPassword();
    super.dispose();
  }

  Future<void> _verify() async {
    if (_loading) return;
    if (_code.text.length != 6) {
      setState(() => _error = 'Enter the 6-digit code.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    final AuthResult result = await widget.controller.verifyEmail(
      email: widget.email,
      code: _code.text,
    );
    if (!mounted) return;
    setState(() => _loading = false);
    if (!result.success) {
      final String message = switch (result.code) {
        'invalid_code' =>
          'That code is not valid. Check it or request a new one.',
        'code_expired' => 'That code has expired. Request a new one.',
        'too_many_attempts' => 'Too many wrong codes. Request a new code.',
        'rate_limited' || 'resend_too_soon' =>
          'Please wait ${result.retryAfter ?? 60} seconds before trying again.',
        'network' => 'No internet connection.',
        _ =>
          result.message.isNotEmpty
              ? result.message
              : 'Something went wrong. Please try again.',
      };
      setState(() => _error = message);
      return;
    }
    final String? password = _passwordInMemory;
    _passwordInMemory = null;
    widget.controller.clearRegistrationPassword();
    bool signedIn = false;
    if (password != null && password.isNotEmpty) {
      final AuthResult login = await widget.controller.login(
        widget.email,
        password,
      );
      if (!mounted) return;
      signedIn = login.success;
    }
    widget.controller.showAccountCreatedScreen();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(
        builder: (_) => AccountCreatedPage(
          controller: widget.controller,
          signedIn: signedIn,
        ),
      ),
      (_) => false,
    );
  }

  Future<void> _resend() async {
    final AuthResult result = await widget.controller.resendVerification(
      widget.email,
    );
    if (!mounted) return;
    if (result.success) {
      final dynamic resendValue = result.data?['resend_after_seconds'];
      final int seconds =
          result.retryAfter ?? (resendValue is int ? resendValue : null) ?? 60;
      setState(() => _remaining = seconds);
      _startTimer();
    } else {
      setState(() {
        _error = result.message;
        if (result.retryAfter != null) _remaining = result.retryAfter!;
      });
      _startTimer();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Verify e-mail')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  'We sent a 6-digit code to ${widget.email}',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                TextField(
                  key: const ValueKey<String>('verify-code-field'),
                  controller: _code,
                  enabled: !_loading,
                  autofillHints: const <String>[AutofillHints.oneTimeCode],
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  maxLength: 6,
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(6),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Verification code',
                  ),
                ),
                if (_error != null) ...<Widget>[
                  const SizedBox(height: 8),
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                FilledButton(
                  key: const ValueKey<String>('verify-submit'),
                  onPressed: _loading ? null : _verify,
                  child: _loading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Verify'),
                ),
                TextButton(
                  onPressed: _remaining == 0 ? _resend : null,
                  child: Text(
                    _remaining == 0
                        ? 'Resend code'
                        : 'Resend code in $_remaining s',
                  ),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            RegisterPage(controller: widget.controller),
                      ),
                      (_) => false,
                    );
                  },
                  child: const Text('Use a different e-mail'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
