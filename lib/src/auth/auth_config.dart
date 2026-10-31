class AuthConfig {
  static const String baseUrl = 'https://larvamonitor.muccsbblock1.com';
  static const Duration loginTimeout = Duration(seconds: 10);
  static const Duration registerTimeout = Duration(seconds: 10);
  static const Duration verifyTimeout = Duration(seconds: 10);
  static const Duration meTimeout = Duration(seconds: 8);
  static const Duration logoutTimeout = Duration(seconds: 8);
  static const Duration offlineWindow = Duration(days: 30);
  static const String deviceLabel = 'Waya-waya Scanner (Android)';
  static const int pbkdf2Iterations = 150000;
}
