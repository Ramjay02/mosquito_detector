import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import 'constants.dart';
import 'preprocess.dart';
import 'yolo_decoder.dart';

class CropResult {
  CropResult({
    required this.genus,
    required this.code,
    required this.fullName,
    required this.confidence,
    required this.classId,
    required this.probabilities,
  });

  final String genus;
  final String code;
  final String fullName;
  final double confidence;
  final int classId;
  final List<double> probabilities;

  String get speciesCode => code;
}

class InferenceEngine {
  static const String detAsset = 'assets/models/yolov8n.tflite';
  static const String clsAsset = 'assets/models/mobilenetv3.tflite';

  Interpreter? _detector;
  Interpreter? _classifier;
  String? _loadError;

  List<int>? _detInShape;
  List<int>? _detOutShape;
  List<int>? _clsInShape;
  List<int>? _clsOutShape;

  TensorType? _detInType;
  TensorType? _detOutType;
  TensorType? _clsInType;
  TensorType? _clsOutType;

  bool get detectorLoaded => _detector != null;
  bool get classifierLoaded => _classifier != null;
  String? get loadError => _loadError;
  bool get ready =>
      _detector != null && _classifier != null && _loadError == null;

  Processed640? _lastProcessedFrame;
  Uint8List? _lastProcessedPhoto;

  Future<void> load() async {
    _detector?.close();
    _classifier?.close();
    _detector = null;
    _classifier = null;
    _loadError = null;
    final List<String> errors = <String>[];
    try {
      _detector = await _open(detAsset);
      _detInShape = _detector!.getInputTensor(0).shape;
      _detOutShape = _detector!.getOutputTensor(0).shape;
      _detInType = _detector!.getInputTensor(0).type;
      _detOutType = _detector!.getOutputTensor(0).type;
      debugPrint('DET_IN:$_detInShape:$_detInType');
      debugPrint('DET_OUT:$_detOutShape:$_detOutType');
    } catch (error) {
      _detector?.close();
      _detector = null;
      errors.add('$detAsset: $error');
    }

    try {
      _classifier = await _open(clsAsset);
      _clsInShape = _classifier!.getInputTensor(0).shape;
      _clsOutShape = _classifier!.getOutputTensor(0).shape;
      _clsInType = _classifier!.getInputTensor(0).type;
      _clsOutType = _classifier!.getOutputTensor(0).type;
      if (!listEquals(_clsInShape, const <int>[1, 224, 224, 3]) ||
          !listEquals(_clsOutShape, const <int>[1, 4]) ||
          _clsInType != TensorType.float32 ||
          _clsOutType != TensorType.float32) {
        throw StateError(
          'expected float32 input [1,224,224,3] and output [1,4]; '
          'found $_clsInType $_clsInShape -> $_clsOutType $_clsOutShape',
        );
      }
      debugPrint('CLS_IN:$_clsInShape:$_clsInType');
      debugPrint('CLS_OUT:$_clsOutShape:$_clsOutType');
    } catch (error) {
      _classifier?.close();
      _classifier = null;
      errors.add('$clsAsset: $error');
    }
    _loadError = errors.isEmpty ? null : errors.join('\n');
  }

  Future<Interpreter> _open(String asset) async {
    final List<String> attempts = <String>[];
    try {
      final ByteData bytes = await rootBundle.load(asset);
      attempts.add('asset ${bytes.lengthInBytes}');
      return Interpreter.fromBuffer(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      );
    } catch (e) {
      attempts.add('asset failed: $e');
    }
    try {
      final Directory dir = await getApplicationDocumentsDirectory();
      final File file = File('${dir.path}/${asset.split('/').last}');
      if (await file.exists()) {
        attempts.add('docs ${await file.length()}');
        return Interpreter.fromFile(file);
      }
      attempts.add('no docs file');
    } catch (e) {
      attempts.add('docs failed: $e');
    }
    throw StateError('unable to load model (${attempts.join('; ')})');
  }

  Future<Processed640> preprocessInIsolate(Uint8List jpeg) async {
    final List<Object> msg = <Object>[jpeg];
    final result = await compute(_preprocessIsolate, msg);
    final Map<String, Object> map = result;
    final Processed640 frame = Processed640(
      processedRgbUint8: map['rgb'] as Uint8List,
      yoloInputFloat: map['yolo'] as Float32List,
      origW: map['ow'] as int,
      origH: map['oh'] as int,
      focusScore: map['focus'] as double,
    );
    _lastProcessedFrame = frame;
    _lastProcessedPhoto = jpeg;
    return frame;
  }

  static Map<String, Object> _preprocessIsolate(List<Object> msg) {
    final Uint8List jpeg = msg[0] as Uint8List;
    final Processed640 frame = Preprocessor.processOnce(jpeg);
    return <String, Object>{
      'rgb': frame.processedRgbUint8,
      'yolo': frame.yoloInputFloat,
      'ow': frame.origW,
      'oh': frame.origH,
      'focus': frame.focusScore,
    };
  }

  bool? _boxesAreNormalized;

  void setBoxFormat(bool? normalized) {
    _boxesAreNormalized = normalized;
  }

  CropResult? classify(Uint8List photoBytes, Detection detection) {
    if (!ready) {
      throw StateError(_loadError ?? 'Models are not ready');
    }
    final Processed640? frame = _lastProcessedFrame;
    if (frame == null || !identical(_lastProcessedPhoto, photoBytes)) {
      throw StateError(
        'No processed 640 frame is cached for this photo; preprocess it before classification.',
      );
    }

    final double scaleX = frame.origW / kDetectSize;
    final double scaleY = frame.origH / kDetectSize;
    final double x1 = detection.x1 / scaleX;
    final double y1 = detection.y1 / scaleY;
    final double x2 = detection.x2 / scaleX;
    final double y2 = detection.y2 / scaleY;
    if (x2 - x1 < kMinCropPx || y2 - y1 < kMinCropPx) {
      return null;
    }

    final double marginX = (x2 - x1) * kCropMargin / 2;
    final double marginY = (y2 - y1) * kCropMargin / 2;
    final int cropX1 = (x1 - marginX).toInt().clamp(0, kDetectSize - 1);
    final int cropY1 = (y1 - marginY).toInt().clamp(0, kDetectSize - 1);
    final int cropX2 = (x2 + marginX).toInt().clamp(0, kDetectSize);
    final int cropY2 = (y2 + marginY).toInt().clamp(0, kDetectSize);
    if (cropX2 <= cropX1 || cropY2 <= cropY1) {
      return null;
    }
    final int squareSide = (cropX2 - cropX1) > (cropY2 - cropY1)
        ? cropX2 - cropX1
        : cropY2 - cropY1;

    final Uint8List crop = Preprocessor.cropFromProcessed640(
      frame.processedRgbUint8,
      x1: x1,
      y1: y1,
      x2: x2,
      y2: y2,
    );
    final Float32List input = Float32List(crop.length);
    for (int i = 0; i < crop.length; i++) {
      input[i] = crop[i].toDouble();
    }
    final Float32List output = Float32List(4);
    _classifier!.run(input.buffer, output.buffer);
    final List<double> probabilities = _asProbabilities(output);
    int topClass = 0;
    for (int i = 1; i < probabilities.length; i++) {
      if (probabilities[i] > probabilities[topClass]) {
        topClass = i;
      }
    }
    if (kDebugMode) {
      debugPrint(
        'CLASSIFIER crop=[$cropX1,$cropY1,$cropX2,$cropY2] side=$squareSide, '
        'probs AB=${probabilities[0]} AG=${probabilities[1]} '
        'AN=${probabilities[2]} CQ=${probabilities[3]}, '
        'top=${kSpeciesCodes[topClass]}',
      );
    }
    return CropResult(
      genus: kSpeciesGenus[topClass],
      code: kSpeciesCodes[topClass],
      fullName: kSpeciesFullNames[topClass],
      confidence: probabilities[topClass],
      classId: topClass,
      probabilities: List<double>.unmodifiable(probabilities),
    );
  }

  static List<double> _asProbabilities(Float32List output) {
    final List<double> values = output.toList(growable: false);
    final bool isDistribution =
        values.every((double value) => value >= 0 && value <= 1) &&
        (values.fold<double>(0, (double sum, double value) => sum + value) - 1)
                .abs() <=
            1e-3;
    return isDistribution ? values : softmax(values);
  }

  static List<double> softmax(List<double> values) {
    if (values.isEmpty) {
      return <double>[];
    }
    final double maxValue = values.reduce(
      (double a, double b) => a > b ? a : b,
    );
    final List<double> exponents = values
        .map((double value) => math.exp(value - maxValue))
        .toList(growable: false);
    final double total = exponents.fold<double>(
      0,
      (double sum, double value) => sum + value,
    );
    return exponents.map((double value) => value / total).toList();
  }

  List<Detection> detect(Processed640 frame) {
    final Interpreter interpreter = _detector!;
    final List<int> outShape =
        _detOutShape ?? interpreter.getOutputTensor(0).shape;
    int anchors = 8400;
    if (outShape.length == 3) {
      anchors = outShape[2];
    }
    final Float32List output = Float32List(outShape.reduce((a, b) => a * b));
    // NCHW input
    interpreter.runForMultipleInputs(
      <Object>[frame.yoloInputFloat.buffer],
      <int, Object>{0: output.buffer},
    );
    final BoxUnitInfo unitInfo = YoloDecoder.detectBoxUnits(output, outShape);
    if (kDebugMode && output.isNotEmpty) {
      final List<String> fieldStats = <String>[];
      for (int channel = 0; channel < 8; channel++) {
        double minValue = double.infinity;
        double maxValue = double.negativeInfinity;
        for (int i = 0; i < anchors; i++) {
          final double value = output[channel * anchors + i];
          minValue = value < minValue ? value : minValue;
          maxValue = value > maxValue ? value : maxValue;
        }
        final String label = channel < 4
            ? const <String>['cx', 'cy', 'w', 'h'][channel]
            : const <String>['AB', 'AG', 'AN', 'CQ'][channel - 4];
        fieldStats.add('$label[$minValue..$maxValue]');
      }
      debugPrint('YOLO_STATS: ${fieldStats.join(' ')}');
      debugPrint(
        'BOX_UNITS normalized=${_boxesAreNormalized ?? unitInfo.normalized} max=${unitInfo.maxCoordinate}',
      );
    }
    final List<Detection> detections = YoloDecoder.decode(
      output,
      outShape,
      origW: frame.origW,
      origH: frame.origH,
      detectSize: kDetectSize,
      boxesAreNormalized: _boxesAreNormalized,
    );
    if (kDebugMode) {
      final double scaleX = frame.origW / kDetectSize;
      final double scaleY = frame.origH / kDetectSize;
      for (final Detection detection in detections) {
        debugPrint(
          'DETECTION: ${detection.code} confidence=${detection.confidence} '
          'box640=[${detection.x1 / scaleX},${detection.y1 / scaleY},'
          '${detection.x2 / scaleX},${detection.y2 / scaleY}] '
          'original=[${detection.x1},${detection.y1},'
          '${detection.x2},${detection.y2}]',
        );
      }
    }
    return detections;
  }

  void dispose() {
    _detector?.close();
    _classifier?.close();
    _detector = null;
    _classifier = null;
    _lastProcessedFrame = null;
    _lastProcessedPhoto = null;
  }
}
