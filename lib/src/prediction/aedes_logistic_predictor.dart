import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/services.dart';

/// Offline inference for the trained StandardScaler + LogisticRegression model.
/// Feature order is fixed: Lag_1, Lag_2, Lag_3, Lag_4, Current_Activity.
class AedesLogisticPredictor {
  AedesLogisticPredictor._({
    required this.mean,
    required this.scale,
    required this.coefficients,
    required this.intercept,
  });

  final List<double> mean;
  final List<double> scale;
  final List<double> coefficients;
  final double intercept;

  static const List<String> featureOrder = [
    'Lag_1',
    'Lag_2',
    'Lag_3',
    'Lag_4',
    'Current_Activity',
  ];

  static Future<AedesLogisticPredictor> load({
    String assetPath = 'assets/aedes_model_parameters.json',
  }) async {
    final raw = await rootBundle.loadString(assetPath);
    return AedesLogisticPredictor.fromJson(jsonDecode(raw));
  }

  factory AedesLogisticPredictor.fromJson(Object? decoded) {
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Model parameters must be a JSON object.');
    }
    final Object? rawFeatures = decoded['features'];
    if (rawFeatures is! List<Object?> ||
        rawFeatures.length != featureOrder.length ||
        !List.generate(
          featureOrder.length,
          (int index) => rawFeatures[index] == featureOrder[index],
        ).every((bool matches) => matches)) {
      throw const FormatException(
        'Model features must be ordered [Lag_1, Lag_2, Lag_3, Lag_4, Current_Activity].',
      );
    }

    List<double> readVector(String key) {
      final Object? value = decoded[key];
      if (value is! List<Object?> ||
          value.length != featureOrder.length ||
          value.any((Object? item) => item is! num || !item.isFinite)) {
        throw FormatException(
          'Model parameter "$key" must contain exactly five finite numbers.',
        );
      }
      return value.cast<num>().map((num item) => item.toDouble()).toList();
    }

    final List<double> means = readVector('scaler_mean');
    final List<double> scales = readVector('scaler_scale');
    final List<double> coefficients = readVector('coefficients');
    if (scales.any((double value) => value <= 0)) {
      throw const FormatException(
        'Model scaler_scale values must all be greater than zero.',
      );
    }
    final Object? rawClasses = decoded['classes'];
    if (rawClasses is! List<Object?> ||
        rawClasses.length != 2 ||
        rawClasses[0] != 0 ||
        rawClasses[1] != 1) {
      throw const FormatException(
        'Expected class mapping 0=Decrease, 1=Increase.',
      );
    }
    final Object? rawIntercept = decoded['intercept'];
    if (rawIntercept is! num || !rawIntercept.isFinite) {
      throw const FormatException('Model intercept must be a finite number.');
    }
    return AedesLogisticPredictor._(
      mean: means,
      scale: scales,
      coefficients: coefficients,
      intercept: rawIntercept.toDouble(),
    );
  }

  /// Inputs are weekly positivity values in [0,1].
  /// Values must be ordered [Lag_1, Lag_2, Lag_3, Lag_4, Current_Activity].
  AedesPrediction predict(List<double> values) {
    if (values.length != 5) {
      throw ArgumentError('Exactly five model inputs are required.');
    }
    if (values.any((v) => !v.isFinite || v < 0 || v > 1)) {
      throw ArgumentError(
        'Each weekly positivity input must be between 0 and 1.',
      );
    }
    double logit = intercept;
    for (var i = 0; i < 5; i++) {
      final standardized = (values[i] - mean[i]) / scale[i];
      logit += coefficients[i] * standardized;
    }
    // Numerically stable sigmoid.
    final double probability = logit >= 0
        ? 1 / (1 + math.exp(-logit))
        : math.exp(logit) / (1 + math.exp(logit));
    return AedesPrediction(
      logit: logit,
      probabilityIncrease: probability,
      probabilityDecrease: 1 - probability,
      predictedClass: probability >= 0.5 ? 1 : 0,
    );
  }
}

class AedesPrediction {
  const AedesPrediction({
    required this.logit,
    required this.probabilityIncrease,
    required this.probabilityDecrease,
    required this.predictedClass,
  });

  final double logit;
  final double probabilityIncrease;
  final double probabilityDecrease;
  final int predictedClass;

  String get direction => predictedClass == 1 ? 'Increase' : 'Decrease';
}
