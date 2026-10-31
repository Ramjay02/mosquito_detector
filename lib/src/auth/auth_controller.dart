import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'auth_api.dart';
import 'auth_config.dart';
import 'auth_messages.dart';
import 'password_hasher.dart';
import 'secure_store.dart';

enum AuthStatus { splash, signedOut, signedIn, pending }

class AuthUser {
  const AuthUser({
    required this.id,
    required this.fullName,
    required this.email,
    required this.role,
    required this.status,
    this.authType,
  });

  final dynamic id;
  final String fullName;
  final String email;
  final String role;
  final String status;
  final String? authType;

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    return AuthUser(
      id: json['id'],
      fullName: json['full_name']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      role: json['role']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      authType: json['auth_type']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'full_name': fullName,
    'email': email,
    'role': role,
    'status': status,
    if (authType != null) 'auth_type': authType,
  };
}

class AuthResult {
  const AuthResult({
    required this.success,
    required this.message,
    this.code,
    this.user,
    this.data,
    this.retryAfter,
  });

  final bool success;
  final String message;
  final String? code;
  final AuthUser? user;
  final Map<String, dynamic>? data;
  final int? retryAfter;
}

class AuthController extends ChangeNotifier {
  AuthController({SecureStore? store, AuthApi? api, DateTime Function()? clock})
    : store = store ?? FlutterSecureStore(),
      api = api ?? AuthApi(),
      _clock = clock ?? DateTime.now;

  final SecureStore store;
  final AuthApi api;
  final DateTime Function() _clock;

  static const String keyToken = 'auth.token';
  static const String keyTokenExpiresAt = 'auth.token_expires_at';
  static const String keyUser = 'auth.user';
  static const String keyEmail = 'auth.email';
  static const String keySalt = 'auth.password_salt';
  static const String keyHash = 'auth.password_hash';
  static const String keyIterations = 'auth.password_iterations';
  static const String keyLastOnline = 'auth.last_online_verified_at';
  static const String keyMaxSeen = 'auth.max_seen_device_time';
  static const String keyFailedAttempts = 'auth.failed_offline_attempts';
  static const String keyLockoutUntil = 'auth.lockout_until';

  AuthStatus status = AuthStatus.splash;
  AuthUser? currentUser;
  String? currentToken;
  String? currentEmail;
  DateTime? lastOnlineVerifiedAt;
  DateTime? tokenExpiresAt;
  bool isOfflineMode = false;
  String? notice;
  DateTime? lastMeCheck;
  Duration? lastPasswordHashDuration;

  static const List<String> _allKeys = <String>[
    keyToken,
    keyTokenExpiresAt,
    keyUser,
    keyEmail,
    keySalt,
    keyHash,
    keyIterations,
    keyLastOnline,
    keyMaxSeen,
    keyFailedAttempts,
    keyLockoutUntil,
  ];

  Future<void> bootstrap() async {
    status = AuthStatus.splash;
    notifyListeners();
    try {
      await _updateMaxSeen();
      final String? token = await store.read(keyToken);
      final String? userJson = await store.read(keyUser);
      if (token == null || token.isEmpty || userJson == null) {
        await _clearSession();
        status = AuthStatus.signedOut;
        notifyListeners();
        return;
      }
      currentToken = token;
      currentEmail = await store.read(keyEmail);
      currentUser = AuthUser.fromJson(
        jsonDecode(userJson) as Map<String, dynamic>,
      );
      tokenExpiresAt = _parseDate(await store.read(keyTokenExpiresAt));
      lastOnlineVerifiedAt = _parseDate(await store.read(keyLastOnline));

      if (!_offlinePolicyAllows()) {
        notice = 'An online check is required.';
        await _clearSession();
        status = AuthStatus.signedOut;
        notifyListeners();
        return;
      }

      isOfflineMode = true;
      status = currentUser!.status == 'pending'
          ? AuthStatus.pending
          : AuthStatus.signedIn;
      notifyListeners();
      await checkMeInBackground();
    } catch (_) {
      await _clearSession();
      status = AuthStatus.signedOut;
      notifyListeners();
    }
  }

  Future<AuthResult> login(String email, String password) async {
    email = email.trim().toLowerCase();
    try {
      final ServerAnswer answer = await api.login(
        email: email,
        password: password,
      );
      final Map<String, dynamic>? data = answer.data;
      if (answer.statusCode == 200 && answer.ok && data != null) {
        final Map<String, dynamic> userJson =
            data['user'] as Map<String, dynamic>;
        final AuthUser user = AuthUser.fromJson(userJson);
        if (user.status == 'pending') {
          await _storeOnlineLogin(email, password, data, user);
          status = AuthStatus.pending;
          isOfflineMode = false;
          return AuthResult(
            success: false,
            code: 'account_pending',
            message: authMessage('account_pending'),
            user: user,
          );
        }
        await _storeOnlineLogin(email, password, data, user);
        status = AuthStatus.signedIn;
        isOfflineMode = false;
        notice = null;
        notifyListeners();
        return AuthResult(success: true, message: '', user: user);
      }
      final String code = answer.code;
      return AuthResult(
        success: false,
        code: code,
        message: answer.message.isNotEmpty
            ? answer.message
            : authMessage(code, retryAfter: answer.retryAfter),
        data: data,
        retryAfter: answer.retryAfter,
      );
    } on NetworkFailure {
      return _loginOffline(email, password);
    } catch (_) {
      return const AuthResult(
        success: false,
        code: 'server_error',
        message: 'Something went wrong. Please try again.',
      );
    }
  }

  Future<AuthResult> _loginOffline(String email, String password) async {
    final DateTime now = _clock();
    await _updateMaxSeen();
    final String? lockoutText = await store.read(keyLockoutUntil);
    final DateTime? lockoutUntil = _parseDate(lockoutText);
    if (lockoutUntil != null && now.isBefore(lockoutUntil)) {
      return AuthResult(
        success: false,
        code: 'lockout',
        message: 'Please wait before trying again.',
      );
    }
    final String? storedEmail = await store.read(keyEmail);
    if (storedEmail == null || storedEmail.toLowerCase() != email) {
      return AuthResult(
        success: false,
        code: 'network',
        message: 'First sign-in, or a sign-in after 30 days offline, needs an internet connection.',
      );
    }
    final DateTime? lastOnline = _parseDate(await store.read(keyLastOnline));
    if (lastOnline == null ||
        now.isAfter(lastOnline.add(AuthConfig.offlineWindow))) {
      return AuthResult(
        success: false,
        code: 'network',
        message: 'First sign-in, or a sign-in after 30 days offline, needs an internet connection.',
      );
    }
    final String? maxSeenText = await store.read(keyMaxSeen);
    final DateTime? maxSeen = _parseDate(maxSeenText);
    if (maxSeen != null &&
        now.isBefore(maxSeen.subtract(const Duration(minutes: 5)))) {
      return AuthResult(
        success: false,
        code: 'clock_moved_back',
        message: 'Your device time appears to have moved backwards. Correct the time and try again.',
      );
    }
    final String? salt = await store.read(keySalt);
    final String? hash = await store.read(keyHash);
    final String? iterationsText = await store.read(keyIterations);
    if (salt == null || hash == null || iterationsText == null) {
      return AuthResult(
        success: false,
        code: 'network',
        message: 'First sign-in, or a sign-in after 30 days offline, needs an internet connection.',
      );
    }
    final bool matches = await verifyPassword(
      password: password,
      saltBase64: salt,
      hashBase64: hash,
      iterations: int.tryParse(iterationsText) ?? AuthConfig.pbkdf2Iterations,
    );
    if (!matches) {
      await _recordOfflineFailure();
      return const AuthResult(
        success: false,
        code: 'invalid_credentials',
        message: 'Invalid e-mail or password.',
      );
    }
    await store.write(keyFailedAttempts, '0');
    await store.delete(keyLockoutUntil);
    final String? userJson = await store.read(keyUser);
    if (userJson == null) {
      return const AuthResult(
        success: false,
        code: 'network',
        message: 'First sign-in, or a sign-in after 30 days offline, needs an internet connection.',
      );
    }
    currentUser = AuthUser.fromJson(
      jsonDecode(userJson) as Map<String, dynamic>,
    );
    currentToken = await store.read(keyToken);
    currentEmail = email;
    tokenExpiresAt = _parseDate(await store.read(keyTokenExpiresAt));
    lastOnlineVerifiedAt = lastOnline;
    isOfflineMode = true;
    status = currentUser!.status == 'pending'
        ? AuthStatus.pending
        : AuthStatus.signedIn;
    notice = null;
    notifyListeners();
    return AuthResult(success: true, message: '', user: currentUser);
  }

  Future<void> _recordOfflineFailure() async {
    final int failed =
        int.tryParse(await store.read(keyFailedAttempts) ?? '0') ?? 0;
    final int next = failed + 1;
    await store.write(keyFailedAttempts, '$next');
    if (next % 5 == 0) {
      final int cycle = next ~/ 5;
      final Duration duration;
      switch (cycle) {
        case 1:
          duration = const Duration(seconds: 30);
          break;
        case 2:
          duration = const Duration(minutes: 1);
          break;
        case 3:
          duration = const Duration(minutes: 5);
          break;
        default:
          duration = const Duration(minutes: 15);
      }
      await store.write(
        keyLockoutUntil,
        _clock().add(duration).toUtc().toIso8601String(),
      );
    }
  }

  Future<void> _storeOnlineLogin(
    String email,
    String password,
    Map<String, dynamic> data,
    AuthUser user,
  ) async {
    final PasswordHashResult hashResult = await hashPassword(password);
    lastPasswordHashDuration = hashResult.duration;
    final String? serverTime = data['server_time']?.toString();
    final String? tokenExpires = data['token_expires_at']?.toString();
    final DateTime lastOnline = _parseDate(serverTime) ?? _clock().toUtc();
    await store.write(keyToken, data['token'].toString());
    await store.write(keyTokenExpiresAt, tokenExpires ?? '');
    await store.write(keyUser, jsonEncode(user.toJson()));
    await store.write(keyEmail, email);
    await store.write(keySalt, hashResult.saltBase64);
    await store.write(keyHash, hashResult.hashBase64);
    await store.write(keyIterations, '${hashResult.iterations}');
    await store.write(keyLastOnline, lastOnline.toUtc().toIso8601String());
    await store.write(keyFailedAttempts, '0');
    await store.delete(keyLockoutUntil);
    await _updateMaxSeen();
    currentToken = data['token'].toString();
    currentEmail = email;
    currentUser = user;
    lastOnlineVerifiedAt = lastOnline;
    tokenExpiresAt = _parseDate(tokenExpires);
  }

  Future<AuthResult> register({
    required String fullName,
    required String email,
    required String password,
  }) async {
    try {
      final ServerAnswer answer = await api.register(
        fullName: fullName,
        email: email.trim().toLowerCase(),
        password: password,
      );
      if (answer.statusCode == 201 && answer.ok) {
        return AuthResult(
          success: true,
          message: '',
          code: answer.code,
          data: answer.data,
        );
      }
      return AuthResult(
        success: false,
        code: answer.code,
        message: answer.message.isNotEmpty
            ? answer.message
            : authMessage(answer.code, retryAfter: answer.retryAfter),
        data: answer.data,
        retryAfter: answer.retryAfter,
      );
    } on NetworkFailure {
      return const AuthResult(
        success: false,
        code: 'network',
        message: 'Registration needs an internet connection.',
      );
    }
  }

  Future<AuthResult> verifyEmail({
    required String email,
    required String code,
  }) async {
    try {
      final ServerAnswer answer = await api.verifyEmail(
        email: email,
        code: code,
      );
      if (answer.statusCode == 200 && answer.ok) {
        return AuthResult(
          success: true,
          message: '',
          code: answer.code,
          data: answer.data,
        );
      }
      return AuthResult(
        success: false,
        code: answer.code,
        message: answer.message.isNotEmpty
            ? answer.message
            : authMessage(answer.code, retryAfter: answer.retryAfter),
        data: answer.data,
        retryAfter: answer.retryAfter,
      );
    } on NetworkFailure {
      return const AuthResult(
        success: false,
        code: 'network',
        message: 'No internet connection.',
      );
    }
  }

  Future<AuthResult> resendVerification(String email) async {
    try {
      final ServerAnswer answer = await api.resendVerification(email: email);
      if (answer.statusCode == 200 && answer.ok) {
        return AuthResult(
          success: true,
          message: '',
          data: answer.data,
          code: answer.code,
          retryAfter: answer.data?['resend_after_seconds'] as int?,
        );
      }
      return AuthResult(
        success: false,
        code: answer.code,
        message: authMessage(answer.code, retryAfter: answer.retryAfter),
        retryAfter: answer.retryAfter,
      );
    } on NetworkFailure {
      return const AuthResult(
        success: false,
        code: 'network',
        message: 'No internet connection.',
      );
    }
  }

  Future<void> checkMeInBackground() async {
    final String? token = currentToken ?? await store.read(keyToken);
    if (token == null) return;
    lastMeCheck = _clock().toUtc();
    try {
      final ServerAnswer answer = await api.me(token);
      if (answer.statusCode == 401 ||
          (answer.statusCode == 403 && answer.code == 'unauthorized')) {
        notice = 'Your session has expired. Please sign in again.';
        await signOut(callServer: false);
        return;
      }
      if (answer.statusCode == 403) {
        final String message = authMessage(answer.code);
        notice = message == 'Something went wrong. Please try again.'
            ? answer.message
            : message;
        await signOut(callServer: false);
        return;
      }
      if (answer.statusCode == 200 && answer.ok && answer.data != null) {
        final AuthUser user = AuthUser.fromJson(answer.data!);
        currentUser = user;
        await store.write(keyUser, jsonEncode(user.toJson()));
        if (answer.data!['token_expires_at'] != null) {
          final DateTime? expires = _parseDate(
            answer.data!['token_expires_at'].toString(),
          );
          tokenExpiresAt = expires;
          await store.write(
            keyTokenExpiresAt,
            expires?.toUtc().toIso8601String() ?? '',
          );
        }
        final DateTime now =
            _parseDate(answer.data!['server_time']?.toString()) ??
            _clock().toUtc();
        lastOnlineVerifiedAt = now;
        await store.write(keyLastOnline, now.toUtc().toIso8601String());
        await _updateMaxSeen();
        isOfflineMode = false;
        status = user.status == 'pending'
            ? AuthStatus.pending
            : AuthStatus.signedIn;
        notifyListeners();
      }
    } on NetworkFailure {
      if (!_offlinePolicyAllows()) {
        notice = 'An online check is required.';
        await _clearSession();
        status = AuthStatus.signedOut;
        notifyListeners();
      } else {
        isOfflineMode = true;
        notifyListeners();
      }
    }
  }

  Future<void> refreshStatus() => checkMeInBackground();

  Future<void> signOut({bool callServer = true}) async {
    if (callServer && currentToken != null) {
      try {
        await api.logout(currentToken!);
      } on NetworkFailure {
        // Sign-out is local even when the server cannot be reached.
      } catch (_) {}
    }
    await _clearSession();
    status = AuthStatus.signedOut;
    isOfflineMode = false;
    notifyListeners();
  }

  Future<void> _clearSession() async {
    await store.deleteAll(_allKeys);
    currentToken = null;
    currentUser = null;
    currentEmail = null;
    lastOnlineVerifiedAt = null;
    tokenExpiresAt = null;
  }

  bool _offlinePolicyAllows() {
    final DateTime now = _clock();
    if (lastOnlineVerifiedAt == null) return false;
    if (now.isAfter(lastOnlineVerifiedAt!.add(AuthConfig.offlineWindow))) {
      return false;
    }
    return true;
  }

  Future<void> _updateMaxSeen() async {
    final DateTime now = _clock().toUtc();
    final DateTime? previous = _parseDate(await store.read(keyMaxSeen));
    final DateTime maxSeen = previous == null || now.isAfter(previous)
        ? now
        : previous;
    await store.write(keyMaxSeen, maxSeen.toIso8601String());
  }

  DateTime? _parseDate(String? value) {
    if (value == null || value.isEmpty) return null;
    return DateTime.tryParse(value)?.toUtc();
  }
}
