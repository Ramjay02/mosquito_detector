import 'dart:typed_data';
import 'dart:math' as math;

import 'constants.dart';

class Detection {
  Detection({
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
    required this.confidence,
    required this.classId,
    required this.classScores,
    required this.code,
  });

  final double x1;
  final double y1;
  final double x2;
  final double y2;
  final double confidence;
  final int classId;
  final List<double> classScores;
  final String code;

  double get width => x2 - x1;
  double get height => y2 - y1;
}

class BoxUnitInfo {
  const BoxUnitInfo({required this.normalized, required this.maxCoordinate});

  final bool normalized;
  final double maxCoordinate;
}

class YoloDecoder {
  static int get numClasses => kNumClasses;

  static BoxUnitInfo detectBoxUnits(
    Float32List raw,
    List<int> outShape, {
    double confThreshold = kDetConf,
  }) {
    final int channels = outShape.length == 3 ? outShape[1] : 8;
    final int anchors = outShape.length == 3 ? outShape[2] : 8400;
    double maxCoordinate = 0;
    for (int i = 0; i < anchors; i++) {
      double bestScore = 0;
      for (int c = 0; c < numClasses && 4 + c < channels; c++) {
        bestScore = math.max(bestScore, raw[(4 + c) * anchors + i]);
      }
      if (bestScore < confThreshold) {
        continue;
      }
      for (int c = 0; c < 4; c++) {
        maxCoordinate = math.max(maxCoordinate, raw[c * anchors + i]);
      }
    }
    return BoxUnitInfo(
      normalized: maxCoordinate <= 1.5,
      maxCoordinate: maxCoordinate,
    );
  }

  static List<Detection> decode(
    Float32List raw,
    List<int> outShape, {
    required int origW,
    required int origH,
    required int detectSize,
    bool? boxesAreNormalized,
    double confThreshold = kDetConf,
    double iouThreshold = kDetIou,
    int maxDetections = kMaxDetections,
  }) {
    // outShape is [1, C, N] or [1,N,C] depending; check - we saw [1,8,8400]
    int channels = 8;
    int anchors = 8400;
    if (outShape.length == 3) {
      channels = outShape[1];
      anchors = outShape[2];
    }
    final bool useNormalizedBoxes =
        boxesAreNormalized ??
        detectBoxUnits(raw, outShape, confThreshold: confThreshold).normalized;
    final List<_Box> boxes = <_Box>[];
    for (int i = 0; i < anchors; i++) {
      // channel-first: raw[a*N + i]
      final double cx = raw[0 * anchors + i];
      final double cy = raw[1 * anchors + i];
      final double w = raw[2 * anchors + i];
      final double h = raw[3 * anchors + i];

      int best = 0;
      double bestScore = 0;
      for (int c = 0; c < numClasses && (4 + c) < channels; c++) {
        final double s = raw[(4 + c) * anchors + i];
        if (s > bestScore) {
          bestScore = s;
          best = c;
        }
      }
      if (bestScore < confThreshold) {
        continue;
      }

      double bx1, by1, bx2, by2;
      if (useNormalizedBoxes) {
        bx1 = (cx - w / 2) * detectSize;
        by1 = (cy - h / 2) * detectSize;
        bx2 = (cx + w / 2) * detectSize;
        by2 = (cy + h / 2) * detectSize;
      } else {
        bx1 = cx - w / 2;
        by1 = cy - h / 2;
        bx2 = cx + w / 2;
        by2 = cy + h / 2;
      }
      // scale from detectSize space to original
      final double scaleX = origW / detectSize;
      final double scaleY = origH / detectSize;
      boxes.add(
        _Box(
          x1: bx1 * scaleX,
          y1: by1 * scaleY,
          x2: bx2 * scaleX,
          y2: by2 * scaleY,
          score: bestScore,
          classId: best,
          classScores: List<double>.unmodifiable(
            List<double>.generate(
              numClasses,
              (c) => (4 + c) < channels ? raw[(4 + c) * anchors + i] : 0.0,
            ),
          ),
          code: kSpeciesCodes[best],
        ),
      );
    }

    final List<_Box> kept = _nms(boxes, iouThreshold);
    kept.sort((a, b) => b.score.compareTo(a.score));
    final List<_Box> limited = kept.take(maxDetections).toList();
    final int maxX = math.max(origW - 1, 0);
    final int maxY = math.max(origH - 1, 0);
    return limited
        .map(
          (b) => Detection(
            x1: b.x1.clamp(0.0, maxX.toDouble()),
            y1: b.y1.clamp(0.0, maxY.toDouble()),
            x2: b.x2.clamp(0.0, maxX.toDouble()),
            y2: b.y2.clamp(0.0, maxY.toDouble()),
            confidence: b.score,
            classId: b.classId,
            classScores: b.classScores,
            code: b.code,
          ),
        )
        .toList();
  }

  static List<_Box> _nms(List<_Box> boxes, double iouThreshold) {
    final List<_Box> sorted = List<_Box>.of(boxes)
      ..sort((a, b) => b.score.compareTo(a.score));
    final List<bool> removed = List<bool>.filled(sorted.length, false);
    final List<_Box> result = <_Box>[];
    for (int i = 0; i < sorted.length; i++) {
      if (removed[i]) {
        continue;
      }
      result.add(sorted[i]);
      for (int j = i + 1; j < sorted.length; j++) {
        if (removed[j]) {
          continue;
        }
        if (_iou(sorted[i], sorted[j]) > iouThreshold) {
          removed[j] = true;
        }
      }
    }
    return result;
  }

  static double _iou(_Box a, _Box b) {
    final double x1 = math.max(a.x1, b.x1);
    final double y1 = math.max(a.y1, b.y1);
    final double x2 = math.min(a.x2, b.x2);
    final double y2 = math.min(a.y2, b.y2);
    final double interW = math.max(0.0, x2 - x1);
    final double interH = math.max(0.0, y2 - y1);
    final double inter = interW * interH;
    final double union = a.width * a.height + b.width * b.height - inter;
    return union <= 0.0 ? 0.0 : inter / union;
  }
}

class _Box {
  _Box({
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
    required this.score,
    required this.classId,
    required this.classScores,
    required this.code,
  });

  final double x1;
  final double y1;
  final double x2;
  final double y2;
  final double score;
  final int classId;
  final List<double> classScores;
  final String code;

  double get width => x2 - x1;
  double get height => y2 - y1;
}
