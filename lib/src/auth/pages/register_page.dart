import 'dart:convert';

import 'package:flutter/material.dart';

import '../auth_controller.dart';
import 'verify_email_page.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key, required this.controller});

  final AuthController controller;

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _name = TextEditingController();
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final TextEditingController _confirm = TextEditingController();
  bool _consent = false;
  bool _loading = false;
  bool _obscure = true;
  String? _error;

  int _utf8Bytes(String value) => utf8.encode(value).length;

  String? _passwordError(String? value) {
    final String password = value ?? '';
    final int bytes = _utf8Bytes(password);
    if (bytes < 8) return 'Password must be at least 8 characters.';
    if (bytes > 72) return 'Password must be 72 UTF-8 bytes or fewer.';
    if (password == _email.text.trim().toLowerCase()) {
      return 'Password must not equal the e-mail address.';
    }
    return null;
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_consent) {
      setState(() => _error = 'Consent is required.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    final AuthResult result = await widget.controller.register(
      fullName: _name.text.trim(),
      email: _email.text.trim().toLowerCase(),
      password: _password.text,
    );
    if (!mounted) return;
    setState(() => _loading = false);
    if (!result.success) {
      setState(() => _error = result.message);
      return;
    }
    if (!mounted) return;
    widget.controller.setRegistrationPassword(_password.text);
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => VerifyEmailPage(
          controller: widget.controller,
          email: _email.text.trim().toLowerCase(),
          passwordInMemory: _password.text,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Register')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  TextFormField(
                    controller: _name,
                    decoration: const InputDecoration(labelText: 'Full name'),
                    validator: (String? value) {
                      final int length = value?.trim().length ?? 0;
                      if (length < 2 || length > 120) {
                        return 'Enter a full name between 2 and 120 characters.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const <String>[AutofillHints.email],
                    decoration: const InputDecoration(labelText: 'E-mail'),
                    validator: (String? value) {
                      final String email = value?.trim() ?? '';
                      if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                          .hasMatch(email)) {
                        return 'Enter a valid e-mail address.';
                      }
                      return null;
                    },
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _password,
                    obscureText: _obscure,
                    autofillHints: const <String>[AutofillHints.newPassword],
                    decoration: InputDecoration(
                      labelText: 'Password',
                      suffixIcon: IconButton(
                        onPressed: () => setState(() => _obscure = !_obscure),
                        icon: Icon(
                          _obscure ? Icons.visibility : Icons.visibility_off,
                        ),
                      ),
                    ),
                    validator: _passwordError,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _confirm,
                    obscureText: _obscure,
                    decoration: const InputDecoration(
                      labelText: 'Confirm password',
                    ),
                    validator: (String? value) => value != _password.text
                        ? 'Passwords do not match.'
                        : null,
                  ),
                  CheckboxListTile(
                    value: _consent,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    onChanged: (bool? value) =>
                        setState(() => _consent = value ?? false),
                    title: const Text(
                      'My name and e-mail are collected only to manage access to this surveillance system.',
                    ),
                  ),
                  if (_error != null)
                    Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: _loading ? null : _register,
                    child: _loading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Register'),
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
