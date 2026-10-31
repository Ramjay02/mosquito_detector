import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosquito_detector/src/app_navigation.dart';
import 'package:mosquito_detector/src/app_shell.dart';
import 'package:mosquito_detector/src/data/models.dart';
import 'package:mosquito_detector/src/data/surveillance_repository.dart';
import 'package:mosquito_detector/src/records_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppNavigation navigation;
  late _FakeRepository repository;

  setUp(() {
    navigation = AppNavigation();
    repository = _FakeRepository();
  });

  testWidgets('navigation bar has four icon-only accessible destinations', (
    WidgetTester tester,
  ) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    await _pumpShell(tester, navigation, repository);

    final NavigationBar bar = tester.widget(find.byType(NavigationBar));
    expect(bar.destinations, hasLength(4));
    expect(bar.labelBehavior, NavigationDestinationLabelBehavior.alwaysHide);

    final List<NavigationDestination> destinations = bar.destinations
        .cast<NavigationDestination>()
        .toList();
    expect(
      destinations.map((NavigationDestination item) => item.tooltip),
      <String>['Home', 'Surveillance records', 'Prediction', 'Profile'],
    );
    expect(
      destinations.map((NavigationDestination item) => item.label),
      <String>['Home', 'Surveillance records', 'Prediction', 'Profile'],
    );
    expect(find.bySemanticsLabel(RegExp(r'^Home')), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp(r'^Surveillance records')),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel(RegExp(r'^Prediction')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp(r'^Profile')), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('tab switches and selected barangay survives a round trip', (
    WidgetTester tester,
  ) async {
    await _pumpShell(tester, navigation, repository);
    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Aguada (Pob.)').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Profile'));
    await tester.pumpAndSettle();
    expect(find.text('Not signed in'), findsOneWidget);
    await tester.tap(find.byTooltip('Home'));
    await tester.pumpAndSettle();

    expect(find.text('Aguada (Pob.)'), findsOneWidget);
  });

  testWidgets('system back returns to Home, then exits the shell route', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (BuildContext context) => TextButton(
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      AppShell(navigation: navigation, repository: repository),
                ),
              ),
              child: const Text('Open shell'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open shell'));
    await tester.pumpAndSettle();
    navigation.selectTab(2);
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(navigation.selectedTab.value, 0);
    expect(find.text('Active Surveillance Area'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Open shell'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('camera route covers the bottom navigation bar', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AppShell(
          navigation: navigation,
          repository: repository,
          cameraPageBuilder: (BuildContext context, String barangay) =>
              const Scaffold(body: Center(child: Text('Camera full screen'))),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Aguada (Pob.)').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('SCAN LARVAE'));
    await tester.pumpAndSettle();

    expect(find.text('Camera full screen'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('See all selects Records and recordsVersion triggers reload', (
    WidgetTester tester,
  ) async {
    await _pumpShell(tester, navigation, repository);

    await tester.tap(find.text('See all'));
    await tester.pumpAndSettle();
    expect(navigation.selectedTab.value, 1);
    expect(find.byType(RecordsPage), findsOneWidget);
    final int afterSelect = repository.recentQueries;
    expect(afterSelect, greaterThan(1));

    navigation.notifyRecordsChanged();
    await tester.pumpAndSettle();
    expect(repository.recentQueries, afterSelect + 1);
  });
}

Future<void> _pumpShell(
  WidgetTester tester,
  AppNavigation navigation,
  _FakeRepository repository,
) async {
  tester.view.physicalSize = const Size(900, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: AppShell(navigation: navigation, repository: repository),
    ),
  );
  await tester.pumpAndSettle();
}

class _FakeRepository extends SurveillanceRepository {
  int recentQueries = 0;

  @override
  Future<List<SurveillanceRecord>> getRecentRecords({int limit = 5}) async {
    recentQueries++;
    return <SurveillanceRecord>[];
  }

  @override
  Future<List<SurveillanceRecord>> recentRecords({int limit = 100}) async {
    recentQueries++;
    return <SurveillanceRecord>[];
  }

  @override
  Future<List<WeeklySurveillance>> weeklySeries({int limit = 52}) async =>
      <WeeklySurveillance>[];

  @override
  Future<int> recordCount() async => 0;
}
