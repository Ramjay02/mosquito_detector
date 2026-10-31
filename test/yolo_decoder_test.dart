import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:mosquito_detector/src/yolo_decoder.dart';

void main() {
  test('automatically decodes normalized channel-first boxes', () {
    _expectLarvaForBoxUnits(normalized: true);
  });

  test('automatically decodes pixel channel-first boxes', () {
    _expectLarvaForBoxUnits(normalized: false);
  });

  test('YoloDecoder empty output yields no detections', () {
    const int anchors = 8400;
    const List<int> outputShape = <int>[1, 8, anchors];
    final detections = YoloDecoder.decode(
      Float32List(8 * anchors),
      outputShape,
      origW: 640,
      origH: 640,
      detectSize: 640,
      boxesAreNormalized: false,
    );
    expect(detections, isEmpty);
  });

  test('YoloDecoder detects high-confidence object', () {
    const int anchors = 8400;
    const List<int> outputShape = <int>[1, 8, anchors];
    final data = Float32List(8 * anchors);
    final anchor = 1234;
    data[anchor] = 320;
    data[anchors + anchor] = 320;
    data[2 * anchors + anchor] = 100;
    data[3 * anchors + anchor] = 120;
    data[5 * anchors + anchor] = 0.9;

    final detections = YoloDecoder.decode(
      data,
      outputShape,
      origW: 640,
      origH: 640,
      detectSize: 640,
      boxesAreNormalized: false,
      confThreshold: 0.25,
      iouThreshold: 0.45,
    );
    expect(detections, hasLength(1));
    expect(detections.first.classId, 1);
    expect(detections.first.confidence, closeTo(0.9, 1e-6));
    expect(detections.first.x1, closeTo(270, 1e-3));
    expect(detections.first.y1, closeTo(260, 1e-3));
  });
}

void _expectLarvaForBoxUnits({required bool normalized}) {
  const int anchors = 8400;
  const List<int> outputShape = <int>[1, 8, anchors];
  final Float32List raw = Float32List(8 * anchors);

  void setAnchor(int anchor, double score, double offsetX) {
    raw[anchor] = normalized ? 0.5 + offsetX / 640 : 320 + offsetX;
    raw[anchors + anchor] = normalized ? 0.5 : 320;
    raw[2 * anchors + anchor] = normalized ? 200 / 640 : 200;
    raw[3 * anchors + anchor] = normalized ? 300 / 640 : 300;
    raw[5 * anchors + anchor] = score;
  }

  setAnchor(0, 0.9, 0);
  setAnchor(1, 0.8, 1);
  setAnchor(2, 0.2, 0);

  final List<Detection> detections = YoloDecoder.decode(
    raw,
    outputShape,
    origW: 1280,
    origH: 960,
    detectSize: 640,
  );

  expect(detections, hasLength(1));
  final Detection detection = detections.single;
  expect(detection.classId, 1);
  expect(detection.x1, closeTo(440, 1));
  expect(detection.x2, closeTo(840, 1));
  expect(detection.y1, closeTo(255, 1));
  expect(detection.y2, closeTo(705, 1));
}
