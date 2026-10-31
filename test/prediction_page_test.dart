import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosquito_detector/src/constants.dart';
import 'package:mosquito_detector/src/data/prediction_sample.dart';
import 'package:mosquito_detector/src/prediction_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('sample banner remains visible and dropdown has 51 barangays', (
    WidgetTester tester,
  ) async {
    await _pumpPrediction(tester);

    expect(
      find.textContaining(
        'SAMPLE DATA - the prediction model is not connected yet.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey<String>('prediction-barangay')));
    await tester.pumpAndSettle();
    final DropdownButton<String> dropdown = tester
        .widget<DropdownButton<String>>(
          find.descendant(
            of: find.byKey(const ValueKey<String>('prediction-barangay')),
            matching: find.byType(DropdownButton<String>),
          ),
        );
    expect(dropdown.items, hasLength(51));
  });

  testWidgets('S1-S3 display increase, decrease, and uncertain statuses', (
    WidgetTester tester,
  ) async {
    await _pumpPrediction(tester);
    expect(find.text('Likely increase'), findsOneWidget);
    expect(
      find.text(
        'Limited evidence: this barangay is not well represented in the model\'s training data.',
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('S2'));
    await tester.pumpAndSettle();
    expect(find.text('Likely decrease'), findsOneWidget);

    await tester.tap(find.text('S3'));
    await tester.pumpAndSettle();
    expect(find.text('Uncertain'), findsOneWidget);
  });

  testWidgets('S4 has no outlook probability and identifies missing weeks', (
    WidgetTester tester,
  ) async {
    await _pumpPrediction(tester);
    await tester.tap(find.text('S4'));
    await tester.pumpAndSettle();

    expect(find.text('Insufficient data'), findsOneWidget);
    expect(
      find.text('No probability is available. Missing observations for:'),
      findsOneWidget,
    );
    expect(find.text('• 2 weeks ago'), findsOneWidget);
    expect(find.text('• 3 weeks ago'), findsOneWidget);
    expect(find.text('0%'), findsNothing);
    expect(find.textContaining('No data'), findsNWidgets(2));
  });

  test('sample thresholds and no-observation presence semantics', () {
    expect(likelyIncreaseMin, 0.60);
    expect(likelyDecreaseMax, 0.40);
    expect(highPresenceMin, 0.50);
    expect(aedesOutlookStatus(0.60), 'Likely increase');
    expect(aedesOutlookStatus(0.40), 'Likely decrease');
    expect(aedesOutlookStatus(0.58), 'Uncertain');
    expect(
      const WeekObservation(
        weekLabel: 'empty',
        positiveDays: 0,
        observedDays: 0,
      ).presence,
      isNull,
    );
    expect(kSampleOutlooks, hasLength(4));
    expect(kOzamizBarangays, hasLength(51));
  });
}

Future<void> _pumpPrediction(WidgetTester tester) async {
  tester.view.physicalSize = const Size(900, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(const MaterialApp(home: PredictionPage()));
  await tester.pumpAndSettle();
}
