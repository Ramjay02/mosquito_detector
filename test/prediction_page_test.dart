import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mosquito_detector/src/app_navigation.dart';
import 'package:mosquito_detector/src/constants.dart';
import 'package:mosquito_detector/src/prediction/aedes_activity_repository.dart';
import 'package:mosquito_detector/src/prediction/aedes_logistic_predictor.dart';
import 'package:mosquito_detector/src/prediction/aedes_prediction_page.dart';

void main() {
  testWidgets('uses the 51 barangays and displays model outputs', (
    WidgetTester tester,
  ) async {
    final _FakeActivityRepository repository = _FakeActivityRepository();
    await tester.pumpWidget(
      MaterialApp(home: AedesPredictionPage(repository: repository)),
    );
    await tester.pumpAndSettle();

    expect(kOzamizBarangays, hasLength(51));
    final DropdownButton<String> dropdown = tester.widget(
      find.descendant(
        of: find.byKey(const ValueKey<String>('prediction-barangay')),
        matching: find.byType(DropdownButton<String>),
      ),
    );
    expect(dropdown.items, hasLength(51));
    expect(find.text('P(Increase): 65.0%'), findsOneWidget);
    expect(find.text('Predicted direction: Increase'), findsOneWidget);
    expect(find.text('Lag_1: 0.400000'), findsOneWidget);
    expect(
      find.text('4 weeks before: 1/10 positive/observed days (10.0%)'),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.textContaining('selected barangay may not have been represented'),
      300,
    );
    expect(
      find.textContaining('selected barangay may not have been represented'),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.textContaining('92 eligible rows from 13 barangays'),
      300,
    );
    expect(
      find.textContaining('92 eligible rows from 13 barangays'),
      findsOneWidget,
    );
  });

  testWidgets('refreshes when selected and when saved records change', (
    WidgetTester tester,
  ) async {
    final AppNavigation navigation = AppNavigation();
    final _FakeActivityRepository repository = _FakeActivityRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: AedesPredictionPage(
          navigation: navigation,
          repository: repository,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(repository.calls, 0);

    navigation.selectTab(2);
    await tester.pumpAndSettle();
    expect(repository.calls, 1);

    navigation.notifyRecordsChanged();
    await tester.pumpAndSettle();
    expect(repository.calls, 2);

    navigation.selectTab(1);
    await tester.pumpAndSettle();
    navigation.notifyRecordsChanged();
    await tester.pumpAndSettle();
    expect(repository.calls, 2);
  });

  testWidgets('an incomplete history displays Insufficient data', (
    WidgetTester tester,
  ) async {
    final _FakeActivityRepository repository = _FakeActivityRepository(
      insufficient: true,
    );
    await tester.pumpWidget(
      MaterialApp(home: AedesPredictionPage(repository: repository)),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Insufficient data.'), findsOneWidget);
    expect(
      find.textContaining('Missing weeks are not treated as zero'),
      findsOneWidget,
    );
  });

  testWidgets('a barangay with no observations displays an empty state', (
    WidgetTester tester,
  ) async {
    final _FakeActivityRepository repository = _FakeActivityRepository(
      insufficient: true,
      hasObservations: false,
    );
    await tester.pumpWidget(
      MaterialApp(home: AedesPredictionPage(repository: repository)),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining('No saved processed observations'),
      findsOneWidget,
    );
    expect(find.textContaining('Insufficient data.'), findsNothing);
  });
}

class _FakeActivityRepository extends AedesActivityRepository {
  _FakeActivityRepository({
    bool insufficient = false,
    this.hasObservations = true,
  }) : result = insufficient ? null : _samplePrediction(),
       super(predictor: _predictor);

  static final AedesLogisticPredictor _predictor =
      AedesLogisticPredictor.fromJson(<String, Object?>{
        'features': <String>[
          'Lag_1',
          'Lag_2',
          'Lag_3',
          'Lag_4',
          'Current_Activity',
        ],
        'scaler_mean': <double>[0, 0, 0, 0, 0],
        'scaler_scale': <double>[1, 1, 1, 1, 1],
        'coefficients': <double>[1, 1, 1, 1, 1],
        'intercept': 0,
        'classes': <int>[0, 1],
      });

  final BarangayPrediction? result;
  final bool hasObservations;
  int calls = 0;

  @override
  Future<BarangayPrediction?> predictForBarangay(
    String barangay, {
    DateTime? referenceDate,
    bool saveResult = true,
  }) async {
    calls++;
    return result;
  }

  @override
  Future<bool> hasObservationsForBarangay(
    String barangay, {
    DateTime? referenceDate,
  }) async => hasObservations;
}

BarangayPrediction _samplePrediction() {
  final DateTime currentStart = DateTime(2026, 6, 15);
  return BarangayPrediction(
    barangay: '50th District (Pob.)',
    currentWeekStart: currentStart,
    weeks: List<WeeklyActivity>.generate(
      5,
      (int index) => WeeklyActivity(
        weekStart: currentStart.subtract(Duration(days: 28 - 7 * index)),
        positiveDays: index + 1,
        observedDays: 10,
      ),
    ),
    prediction: const AedesPrediction(
      logit: 0.619,
      probabilityIncrease: 0.65,
      probabilityDecrease: 0.35,
      predictedClass: 1,
    ),
  );
}
