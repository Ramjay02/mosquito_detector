import 'package:flutter_test/flutter_test.dart';
import 'package:mosquito_detector/src/prediction/aedes_logistic_predictor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('loads the checked-in model and preserves its feature order', () async {
    final AedesLogisticPredictor predictor =
        await AedesLogisticPredictor.load();

    expect(AedesLogisticPredictor.featureOrder, <String>[
      'Lag_1',
      'Lag_2',
      'Lag_3',
      'Lag_4',
      'Current_Activity',
    ]);
    expect(predictor.mean, hasLength(5));
    expect(predictor.scale, hasLength(5));
    expect(predictor.coefficients, hasLength(5));

    final AedesPrediction result = predictor.predict(<double>[
      0.5,
      0.6,
      0.7,
      0.4,
      0.55,
    ]);
    expect(result.probabilityIncrease, inInclusiveRange(0, 1));
    expect(
      result.probabilityDecrease,
      closeTo(1 - result.probabilityIncrease, 1e-12),
    );
    expect(result.predictedClass, result.probabilityIncrease >= 0.5 ? 1 : 0);
    expect(
      result.direction,
      result.predictedClass == 1 ? 'Increase' : 'Decrease',
    );

    // TODO: Compare this probability with scikit-learn predict_proba output (tolerance 1e-6) when provided.
  });

  test(
    'rejects a feature order that differs from the exported model contract',
    () {
      final Map<String, Object?> parameters = _validParameters();
      parameters['features'] = <String>[
        'Lag_2',
        'Lag_1',
        'Lag_3',
        'Lag_4',
        'Current_Activity',
      ];

      expect(
        () => AedesLogisticPredictor.fromJson(parameters),
        throwsA(
          isA<FormatException>().having(
            (FormatException error) => error.message,
            'message',
            contains('feature'),
          ),
        ),
      );
    },
  );

  test('rejects invalid vector dimensions and unsupported class labels', () {
    final Map<String, Object?> invalidVector = _validParameters()
      ..['coefficients'] = <double>[1, 2, 3, 4];
    expect(
      () => AedesLogisticPredictor.fromJson(invalidVector),
      throwsFormatException,
    );

    final Map<String, Object?> invalidClasses = _validParameters()
      ..['classes'] = <int>[1, 0];
    expect(
      () => AedesLogisticPredictor.fromJson(invalidClasses),
      throwsFormatException,
    );
  });

  test('rejects vectors outside the weekly positivity domain', () async {
    final AedesLogisticPredictor predictor =
        await AedesLogisticPredictor.load();
    expect(
      () => predictor.predict(<double>[0, 0, 0, 0, 1.01]),
      throwsArgumentError,
    );
    expect(() => predictor.predict(<double>[0, 0, 0, 0]), throwsArgumentError);
  });
}

Map<String, Object?> _validParameters() => <String, Object?>{
  'features': <String>['Lag_1', 'Lag_2', 'Lag_3', 'Lag_4', 'Current_Activity'],
  'scaler_mean': <double>[0, 0, 0, 0, 0],
  'scaler_scale': <double>[1, 1, 1, 1, 1],
  'coefficients': <double>[1, 1, 1, 1, 1],
  'intercept': 0,
  'classes': <int>[0, 1],
};
