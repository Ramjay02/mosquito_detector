import 'package:flutter/material.dart';

import 'app_navigation.dart';
import 'data/surveillance_repository.dart';
import 'landing_page.dart';
import 'prediction_page.dart';
import 'profile_page.dart';
import 'records_page.dart';
import 'auth/auth_controller.dart';

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    this.navigation,
    this.repository,
    this.cameraPageBuilder,
    this.authController,
  });

  final AppNavigation? navigation;
  final SurveillanceRepository? repository;
  final Widget Function(BuildContext context, String barangay)?
  cameraPageBuilder;
  final AuthController? authController;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  late final AppNavigation _navigation = widget.navigation ?? appNavigation;
  late final SurveillanceRepository _repository =
      widget.repository ?? SurveillanceRepository();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: _navigation.selectedTab,
      builder: (BuildContext context, int selectedTab, Widget? child) {
        return PopScope<Object?>(
          canPop: selectedTab == 0,
          onPopInvokedWithResult: (bool didPop, Object? result) {
            if (!didPop && selectedTab != 0) {
              _navigation.selectTab(0);
            }
          },
          child: Scaffold(
            body: IndexedStack(
              index: selectedTab,
              children: <Widget>[
                LandingPage(
                  navigation: _navigation,
                  repository: _repository,
                  cameraPageBuilder: widget.cameraPageBuilder,
                ),
                RecordsPage(repository: _repository, navigation: _navigation),
                const PredictionPage(),
                ProfilePage(controller: widget.authController),
              ],
            ),
            bottomNavigationBar: NavigationBar(
              selectedIndex: selectedTab,
              labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
              onDestinationSelected: _navigation.selectTab,
              destinations: const <Widget>[
                NavigationDestination(
                  key: ValueKey<String>('nav-home'),
                  icon: Icon(Icons.home_outlined),
                  selectedIcon: Icon(Icons.home),
                  label: 'Home',
                  tooltip: 'Home',
                ),
                NavigationDestination(
                  key: ValueKey<String>('nav-records'),
                  icon: Icon(Icons.list_alt_outlined),
                  selectedIcon: Icon(Icons.list_alt),
                  label: 'Surveillance records',
                  tooltip: 'Surveillance records',
                ),
                NavigationDestination(
                  key: ValueKey<String>('nav-prediction'),
                  icon: Icon(Icons.insights_outlined),
                  selectedIcon: Icon(Icons.insights),
                  label: 'Prediction',
                  tooltip: 'Prediction',
                ),
                NavigationDestination(
                  key: ValueKey<String>('nav-profile'),
                  icon: Icon(Icons.person_outline),
                  selectedIcon: Icon(Icons.person),
                  label: 'Profile',
                  tooltip: 'Profile',
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
