import 'package:flutter_test/flutter_test.dart';
import 'package:mosquito_detector/src/inference_engine.dart';

void main() {
  group('InferenceEngine.softmax', () {
    test('returns probabilities that sum to 1 and stay within [0,1]', () {
      // Verify stable normalization of classifier scores.
      final List<double> probs = InferenceEngine.softmax(<double>[
        7.33,
        0.4,
        -1.2,
        0.1,
      ]);
      expect(probs.length, 4);
      expect(probs.fold<double>(0, (a, b) => a + b), closeTo(1.0, 1e-9));
      for (final double p in probs) {
        expect(p, greaterThanOrEqualTo(0.0));
        expect(p, lessThanOrEqualTo(1.0));
        expect(p * 100, lessThanOrEqualTo(100.0));
      }
    });

    test('preserves the argmax of the logits', () {
      final List<double> logits = <double>[0.1, 5.0, -3.0, 0.2];
      final List<double> probs = InferenceEngine.softmax(logits);
      int argmaxLogits = 0;
      int argmaxProbs = 0;
      for (int i = 1; i < logits.length; i++) {
        if (logits[i] > logits[argmaxLogits]) {
          argmaxLogits = i;
        }
        if (probs[i] > probs[argmaxProbs]) {
          argmaxProbs = i;
        }
      }
      expect(argmaxProbs, argmaxLogits);
    });

    test('is numerically stable for very large logits', () {
      final List<double> probs = InferenceEngine.softmax(<double>[
        1000.0,
        0.0,
        -1000.0,
        -5.0,
      ]);
      expect(probs[0], closeTo(1.0, 1e-9));
      expect(probs[1], closeTo(0.0, 1e-9));
      expect(probs[2], closeTo(0.0, 1e-9));
      expect(probs.any((double p) => p.isNaN), isFalse);
    });

    test('returns uniform probabilities for equal logits', () {
      final List<double> probs = InferenceEngine.softmax(<double>[
        2.0,
        2.0,
        2.0,
        2.0,
      ]);
      for (final double p in probs) {
        expect(p, closeTo(1 / 4, 1e-9));
      }
    });

    test('handles the empty case', () {
      expect(InferenceEngine.softmax(const <double>[]), isEmpty);
    });
  });
}
