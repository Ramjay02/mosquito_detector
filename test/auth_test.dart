import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mosquito_detector/src/auth/auth_api.dart';
import 'package:mosquito_detector/src/auth/auth_controller.dart';
import 'package:mosquito_detector/src/auth/password_hasher.dart';
import 'package:mosquito_detector/src/auth/secure_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('password hash round trip and wrong password', () async {
    final PasswordHashResult hash = await hashPassword('StrongPassword!1');
    expect(
      await verifyPassword(
        password: 'StrongPassword!1',
        saltBase64: hash.saltBase64,
        hashBase64: hash.hashBase64,
        iterations: hash.iterations,
      ),
      isTrue,
    );
    expect(
      await verifyPassword(
        password: 'WrongPassword!1',
        saltBase64: hash.saltBase64,
        hashBase64: hash.hashBase64,
        iterations: hash.iterations,
      ),
      isFalse,
    );
  });

  test('online login stores account and offline login succeeds', () async {
    final InMemorySecureStore store = InMemorySecureStore();
    final MockClient client = MockClient((http.Request request) async {
      return http.Response(
        jsonEncode(<String, dynamic>{
          'ok': true,
          'code': 'ok',
          'message': '',
          'data': <String, dynamic>{
            'token': 'token-1',
            'token_type': 'Bearer',
            'expires_in_days': 30,
            'token_expires_at': '2026-12-31T00:00:00Z',
            'server_time': '2026-10-31T00:00:00Z',
            'user': <String, dynamic>{
              'id': 1,
              'full_name': 'Test User',
              'email': 'test@example.com',
              'role': 'field_worker',
              'status': 'active',
            },
          },
        }),
        200,
        headers: <String, String>{'content-type': 'application/json'},
      );
    });
    final AuthController controller = AuthController(
      store: store,
      api: AuthApi(client: client),
      clock: () => DateTime.utc(2026, 10, 31),
    );
    final AuthResult online = await controller.login(
      'test@example.com',
      'StrongPassword!1',
    );
    expect(online.success, isTrue);
    expect(await store.read(AuthController.keyToken), 'token-1');

    final AuthController offline = AuthController(
      store: store,
      api: AuthApi(
        client: MockClient((http.Request request) async {
          throw http.ClientException('offline');
        }),
      ),
      clock: () => DateTime.utc(2026, 10, 31, 1),
    );
    final AuthResult result = await offline.login(
      'test@example.com',
      'StrongPassword!1',
    );
    expect(result.success, isTrue);
  });

  test('server invalid credentials does not fall back offline', () async {
    final InMemorySecureStore store = InMemorySecureStore();
    await store.write(AuthController.keyEmail, 'test@example.com');
    await store.write(AuthController.keyLastOnline, '2026-10-31T00:00:00Z');
    await store.write(AuthController.keySalt, 'c2FsdA==');
    await store.write(AuthController.keyHash, 'aGFzaA==');
    await store.write(AuthController.keyIterations, '150000');
    final AuthController controller = AuthController(
      store: store,
      api: AuthApi(
        client: MockClient((http.Request request) async {
          return http.Response(
            jsonEncode(<String, dynamic>{
              'ok': false,
              'code': 'invalid_credentials',
              'message': '',
              'data': null,
            }),
            401,
            headers: <String, String>{'content-type': 'application/json'},
          );
        }),
      ),
      clock: () => DateTime.utc(2026, 10, 31),
    );
    final AuthResult result = await controller.login(
      'test@example.com',
      'WrongPassword',
    );
    expect(result.code, 'invalid_credentials');
  });

  test('offline failures persist and trigger lockout', () async {
    final InMemorySecureStore store = InMemorySecureStore();
    final PasswordHashResult hash = await hashPassword('CorrectPassword');
    await store.write(AuthController.keyEmail, 'test@example.com');
    await store.write(AuthController.keyLastOnline, '2026-10-31T00:00:00Z');
    await store.write(AuthController.keyMaxSeen, '2026-10-31T00:00:00Z');
    await store.write(AuthController.keySalt, hash.saltBase64);
    await store.write(AuthController.keyHash, hash.hashBase64);
    await store.write(AuthController.keyIterations, '${hash.iterations}');
    final AuthController controller = AuthController(
      store: store,
      api: AuthApi(
        client: MockClient((http.Request request) async {
          throw http.ClientException('offline');
        }),
      ),
      clock: () => DateTime.utc(2026, 10, 31, 1),
    );
    for (int attempt = 0; attempt < 5; attempt++) {
      await controller.login('test@example.com', 'WrongPassword');
    }
    final String? lockout = await store.read(AuthController.keyLockoutUntil);
    expect(lockout, isNotNull);
  });
}
