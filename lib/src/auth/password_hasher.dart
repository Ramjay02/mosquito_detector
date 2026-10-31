import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

class PasswordHashResult {
  const PasswordHashResult({
    required this.saltBase64,
    required this.hashBase64,
    required this.iterations,
    this.duration,
  });

  final String saltBase64;
  final String hashBase64;
  final int iterations;
  final Duration? duration;
}

class PasswordHashRequest {
  const PasswordHashRequest({
    required this.password,
    required this.salt,
    required this.iterations,
  });

  final String password;
  final List<int> salt;
  final int iterations;
}

String _base64(List<int> bytes) => base64Encode(bytes);
List<int> _decode(String value) => base64Decode(value);

Future<List<int>> _derive(PasswordHashRequest request) async {
  final Pbkdf2 algorithm = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: request.iterations,
    bits: 256,
  );
  final SecretKey key = await algorithm.deriveKey(
    secretKey: SecretKey(utf8.encode(request.password)),
    nonce: request.salt,
  );
  return await key.extractBytes();
}

Future<PasswordHashResult> hashPassword(
  String password, {
  int iterations = 150000,
}) async {
  final List<int> salt = List<int>.generate(
    16,
    (_) => Random.secure().nextInt(256),
  );
  final Stopwatch stopwatch = Stopwatch()..start();
  final List<int> bytes = await compute(
    _derive,
    PasswordHashRequest(password: password, salt: salt, iterations: iterations),
  );
  stopwatch.stop();
  return PasswordHashResult(
    saltBase64: _base64(salt),
    hashBase64: _base64(bytes),
    iterations: iterations,
    duration: stopwatch.elapsed,
  );
}

Future<bool> verifyPassword({
  required String password,
  required String saltBase64,
  required String hashBase64,
  required int iterations,
}) async {
  final PasswordHashResult? result = await _verifyWithTiming(
    password,
    saltBase64,
    hashBase64,
    iterations,
  );
  return result != null;
}

Future<PasswordHashResult?> _verifyWithTiming(
  String password,
  String saltBase64,
  String hashBase64,
  int iterations,
) async {
  final List<int> salt = _decode(saltBase64);
  final List<int> calculated = await compute(
    _derive,
    PasswordHashRequest(password: password, salt: salt, iterations: iterations),
  );
  final List<int> expected = _decode(hashBase64);
  int difference = calculated.length ^ expected.length;
  final int length = calculated.length < expected.length
      ? calculated.length
      : expected.length;
  for (int index = 0; index < length; index++) {
    difference |= calculated[index] ^ expected[index];
  }
  if (difference != 0) {
    return null;
  }
  return PasswordHashResult(
    saltBase64: saltBase64,
    hashBase64: _base64(calculated),
    iterations: iterations,
  );
}
