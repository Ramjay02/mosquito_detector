import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'auth_config.dart';

class NetworkFailure implements Exception {
  const NetworkFailure();
}

class ServerAnswer {
  const ServerAnswer({
    required this.statusCode,
    required this.ok,
    required this.code,
    required this.message,
    required this.data,
    this.retryAfter,
  });

  final int statusCode;
  final bool ok;
  final String code;
  final String message;
  final Map<String, dynamic>? data;
  final int? retryAfter;
}

class AuthApi {
  AuthApi({http.Client? client, this.baseUrl = AuthConfig.baseUrl})
    : _client = client ?? http.Client();

  final http.Client _client;
  final String baseUrl;

  Future<ServerAnswer> register({
    required String fullName,
    required String email,
    required String password,
  }) {
    return _post('/api/register.php', <String, dynamic>{
      'full_name': fullName,
      'email': email,
      'password': password,
      'confirm_password': password,
      'consent': true,
    }, AuthConfig.registerTimeout);
  }

  Future<ServerAnswer> verifyEmail({
    required String email,
    required String code,
  }) {
    return _post('/api/verify_email.php', <String, dynamic>{
      'email': email,
      'code': code,
    }, AuthConfig.verifyTimeout);
  }

  Future<ServerAnswer> resendVerification({required String email}) {
    return _post('/api/resend_verification.php', <String, dynamic>{
      'email': email,
    }, AuthConfig.verifyTimeout);
  }

  Future<ServerAnswer> login({
    required String email,
    required String password,
  }) {
    return _post('/api/login.php', <String, dynamic>{
      'email': email,
      'password': password,
      'client': 'app',
      'device_label': AuthConfig.deviceLabel,
    }, AuthConfig.loginTimeout);
  }

  Future<ServerAnswer> me(String token) {
    return _get('/api/me.php', token, AuthConfig.meTimeout);
  }

  Future<ServerAnswer> logout(String token) {
    return _post(
      '/api/logout.php',
      <String, dynamic>{},
      AuthConfig.logoutTimeout,
      token: token,
    );
  }

  Future<ServerAnswer> _post(
    String path,
    Map<String, dynamic> body,
    Duration timeout, {
    String? token,
  }) async {
    return _send(() {
      return _client.post(
        Uri.parse('$baseUrl$path'),
        headers: <String, String>{
          'Accept': 'application/json',
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
        body: jsonEncode(body),
      );
    }, timeout);
  }

  Future<ServerAnswer> _get(String path, String token, Duration timeout) async {
    return _send(() {
      return _client.get(
        Uri.parse('$baseUrl$path'),
        headers: <String, String>{
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
    }, timeout);
  }

  Future<ServerAnswer> _send(
    Future<http.Response> Function() request,
    Duration timeout,
  ) async {
    try {
      final http.Response response = await request().timeout(timeout);
      final int? retryAfter = int.tryParse(
        response.headers['retry-after'] ?? '',
      );
      dynamic decoded;
      try {
        decoded = jsonDecode(response.body);
      } catch (_) {
        return ServerAnswer(
          statusCode: response.statusCode,
          ok: false,
          code: 'server_error',
          message: '',
          data: null,
          retryAfter: retryAfter,
        );
      }
      if (decoded is! Map<String, dynamic>) {
        return ServerAnswer(
          statusCode: response.statusCode,
          ok: false,
          code: 'server_error',
          message: '',
          data: null,
          retryAfter: retryAfter,
        );
      }
      final dynamic data = decoded['data'];
      return ServerAnswer(
        statusCode: response.statusCode,
        ok: decoded['ok'] == true,
        code: decoded['code'] is String
            ? decoded['code'] as String
            : 'server_error',
        message: decoded['message'] is String
            ? decoded['message'] as String
            : '',
        data: data is Map<String, dynamic> ? data : null,
        retryAfter: retryAfter,
      );
    } on SocketException {
      throw const NetworkFailure();
    } on TimeoutException {
      throw const NetworkFailure();
    } on TlsException {
      throw const NetworkFailure();
    } on http.ClientException {
      throw const NetworkFailure();
    }
  }
}
