import 'package:flutter/material.dart';

import 'src/app_shell.dart';
import 'src/auth/auth_controller.dart';
import 'src/auth/pages/login_page.dart';
import 'src/auth/pages/account_created_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MosquitoDetectorApp());
}

class MosquitoDetectorApp extends StatelessWidget {
  const MosquitoDetectorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return _AuthApp();
  }
}

class _AuthApp extends StatefulWidget {
  const _AuthApp();

  @override
  State<_AuthApp> createState() => _AuthAppState();
}

class _AuthAppState extends State<_AuthApp> with WidgetsBindingObserver {
  late final AuthController _auth = AuthController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _auth.bootstrap();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _auth.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        _auth.status == AuthStatus.signedIn) {
      final DateTime? last = _auth.lastMeCheck;
      if (last == null ||
          DateTime.now().toUtc().difference(last).inMinutes >= 60) {
        _auth.checkMeInBackground();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _auth,
      builder: (BuildContext context, Widget? child) {
        Widget home;
        if (_auth.showingAccountCreated) {
          home = AccountCreatedPage(
            controller: _auth,
            signedIn: _auth.status == AuthStatus.signedIn,
          );
        } else {
          switch (_auth.status) {
            case AuthStatus.splash:
              home = const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
              break;
            case AuthStatus.signedIn:
              home = AppShell(authController: _auth);
              break;
            case AuthStatus.signedOut:
              home = LoginPage(controller: _auth);
              break;
          }
        }
        return MaterialApp(
          title: 'Waya-waya Scanner',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            brightness: Brightness.dark,
            colorSchemeSeed: const Color(0xFF00BFA5),
            useMaterial3: true,
          ),
          home: home,
        );
      },
    );
  }
}
