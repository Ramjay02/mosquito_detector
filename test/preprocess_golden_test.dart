import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mosquito_detector/src/constants.dart';
import 'package:mosquito_detector/src/preprocess.dart';

void main() {
  test('preprocessing stages match OpenCV reference images', () async {
    final Map<String, dynamic> golden = jsonDecode(
      await File('test/golden/golden.json').readAsString(),
    ) as Map<String, dynamic>;
    final Map<String, dynamic> box =
        golden['box_px_640'] as Map<String, dynamic>;
    final Map<String, dynamic> limits =
        golden['pass_if_mean_abs_diff_at_most'] as Map<String, dynamic>;

    final img.Image input = _readPng('test/golden/sample_input_640.png');
    final Uint8List referenceWhiteBalanced = _rgb(
      _readPng('test/golden/sample_white_balanced.png'),
    );
    final Uint8List referenceClahe = _rgb(
      _readPng('test/golden/sample_clahe.png'),
    );
    final Uint8List referenceUnsharp = _rgb(
      _readPng('test/golden/sample_unsharp.png'),
    );
    final Uint8List referenceCrop = _rgb(
      _readPng('test/golden/sample_crop_224.png'),
    );

    expect(input.width, kDetectSize);
    expect(input.height, kDetectSize);

    final Uint8List whiteBalanced = Preprocessor.grayWorldWhiteBalanceOnly(
      _rgb(input),
    );
    final Uint8List clahe = Preprocessor.claheLabOnly(referenceWhiteBalanced);
    final Uint8List unsharp = Preprocessor.unsharpMaskOnly(referenceClahe);
    final Uint8List crop = Preprocessor.cropFromProcessed640(
      referenceUnsharp,
      x1: (box['x1'] as num).toDouble(),
      y1: (box['y1'] as num).toDouble(),
      x2: (box['x2'] as num).toDouble(),
      y2: (box['y2'] as num).toDouble(),
    );
    final double focusScore = Preprocessor.focusScoreOfImage(input);

    final List<_StageResult> results = <_StageResult>[
      _measure('white balance', whiteBalanced, referenceWhiteBalanced),
      _measure('CLAHE', clahe, referenceClahe),
      _measure('unsharp', unsharp, referenceUnsharp),
      _measure('crop', crop, referenceCrop),
    ];

    print('Stage          Mean abs diff   P99   Max');
    for (final _StageResult result in results) {
      print(
        '${result.name.padRight(14)}'
        '${result.mean.toStringAsFixed(3).padLeft(8)}'
        '${result.p99.toStringAsFixed(1).padLeft(8)}'
        '${result.max.toStringAsFixed(1).padLeft(6)}',
      );
    }
    print('Focus score: ${focusScore.toStringAsFixed(3)}');

    expect(
      results[0].mean,
      lessThanOrEqualTo((limits['white_balanced'] as num).toDouble()),
    );
    expect(
      results[1].mean,
      lessThanOrEqualTo((limits['clahe'] as num).toDouble()),
    );
    expect(
      results[2].mean,
      lessThanOrEqualTo((limits['unsharp'] as num).toDouble()),
    );
    expect(
      results[3].mean,
      lessThanOrEqualTo((limits['crop_224'] as num).toDouble()),
    );
    expect(
      focusScore,
      closeTo((golden['expected_focus_score'] as num).toDouble(), 0.1),
    );
  });
}

img.Image _readPng(String path) {
  final img.Image? decoded = img.decodePng(File(path).readAsBytesSync());
  if (decoded == null) {
    throw FormatException('Could not decode PNG: $path');
  }
  return decoded;
}

Uint8List _rgb(img.Image image) {
  final Uint8List pixels = Uint8List(image.width * image.height * 3);
  for (int y = 0; y < image.height; y++) {
    for (int x = 0; x < image.width; x++) {
      final img.Pixel pixel = image.getPixel(x, y);
      final int offset = (y * image.width + x) * 3;
      pixels[offset] = pixel.r.toInt();
      pixels[offset + 1] = pixel.g.toInt();
      pixels[offset + 2] = pixel.b.toInt();
    }
  }
  return pixels;
}

_StageResult _measure(String name, Uint8List actual, Uint8List expected) {
  if (actual.length != expected.length) {
    throw StateError('$name pixel buffers have different lengths');
  }
  final List<int> differences = List<int>.generate(
    actual.length,
    (int index) => (actual[index] - expected[index]).abs(),
    growable: false,
  )..sort();
  final int total = differences.fold<int>(
    0,
    (int sum, int value) => sum + value,
  );
  final int p99Index = ((differences.length - 1) * 0.99).ceil();
  return _StageResult(
    name: name,
    mean: total / differences.length,
    p99: differences[p99Index].toDouble(),
    max: differences.last.toDouble(),
  );
}

class _StageResult {
  const _StageResult({
    required this.name,
    required this.mean,
    required this.p99,
    required this.max,
  });

  final String name;
  final double mean;
  final double p99;
  final double max;
}
