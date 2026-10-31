import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import 'app_navigation.dart';
import 'constants.dart';
import 'data/surveillance_repository.dart';
import 'inference_engine.dart';
import 'preprocess.dart';
import 'yolo_decoder.dart';

class ResultPage extends StatefulWidget {
  const ResultPage({
    super.key,
    required this.engine,
    required this.repository,
    required this.jpeg,
    required this.oriented,
    this.processedFrame,
    required this.detections,
    required this.capturedAt,
    required this.barangay,
    this.userId,
  });

  final InferenceEngine engine;
  final SurveillanceRepository repository;
  final Uint8List jpeg;
  final img.Image oriented;
  final Processed640? processedFrame;
  final List<Detection> detections;
  final DateTime capturedAt;
  final String barangay;
  final int? userId;

  @override
  State<ResultPage> createState() => _ResultPageState();
}

class _ResultPageState extends State<ResultPage> {
  final List<CropResult?> _cropResults = <CropResult?>[];
  bool _classificationComplete = false;
  bool _saving = false;
  bool _saved = false;
  bool _discardDialogOpen = false;

  Detection? get _bestDetection =>
      widget.detections.isEmpty ? null : widget.detections.first;

  CropResult? get _bestResult =>
      _cropResults.isEmpty ? null : _cropResults.first;

  bool get _isValidResult =>
      _classificationComplete &&
      widget.detections.length == 1 &&
      _bestResult != null &&
      _bestResult!.confidence >= kClsConfMin;

  bool get _canSave {
    return _isValidResult && !_saving && !_saved;
  }

  bool get _shouldConfirmDiscard => _isValidResult && !_saved && !_saving;

  Future<void> _requestLeave() async {
    if (_saving || _discardDialogOpen) {
      return;
    }
    if (!_shouldConfirmDiscard) {
      if (mounted) {
        Navigator.of(context).pop();
      }
      return;
    }

    _discardDialogOpen = true;
    final bool? discard = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Discard this result?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    _discardDialogOpen = false;
    if (discard == true && mounted) {
      Navigator.of(context).pop();
    }
  }

  void _onPopInvoked(bool didPop, Object? result) {
    if (!didPop && _shouldConfirmDiscard) {
      _requestLeave();
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _runClassifier());
  }

  Future<void> _runClassifier() async {
    try {
      for (final Detection extra in widget.detections.skip(1)) {
        if (kDebugMode && extra.confidence >= EXTRA_LARVA_CONF) {
          debugPrint(
            'EXTRA_DETECTION: ${extra.code} confidence=${extra.confidence}',
          );
        }
      }
      final List<CropResult?> results = widget.detections.isEmpty
          ? <CropResult?>[]
          : <CropResult?>[
              widget.engine.classify(widget.jpeg, widget.detections.first),
            ];
      if (!mounted) {
        return;
      }
      setState(() {
        _cropResults
          ..clear()
          ..addAll(results);
        _classificationComplete = true;
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Analysis failed: $error')));
      }
    }
  }

  Future<void> _save() async {
    if (_saving || _saved || !_canSave) {
      return;
    }
    final CropResult result = _bestResult!;
    setState(() => _saving = true);
    try {
      await widget.repository.saveObservation(
        imageBytes: widget.jpeg,
        capturedAt: widget.capturedAt,
        barangay: widget.barangay,
        speciesCode: result.code,
        avgConfidence: result.confidence,
        userId: widget.userId,
      );
      if (!mounted) {
        return;
      }
      appNavigation.notifyRecordsChanged();
      setState(() => _saved = true);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Saved: ${result.fullName}')));
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Save failed: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final int w = widget.oriented.width;
    final int h = widget.oriented.height;
    return PopScope<Object?>(
      canPop: !_isValidResult || _saved,
      onPopInvokedWithResult: _onPopInvoked,
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'Back',
            icon: const Icon(Icons.arrow_back),
            onPressed: _requestLeave,
          ),
          title: const Text('Analysis'),
        ),
        body: Column(
          children: [
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final double areaW = constraints.maxWidth;
                  final double areaH = constraints.maxHeight;
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      FittedBox(
                        fit: BoxFit.contain,
                        child: SizedBox(
                          width: w.toDouble(),
                          height: h.toDouble(),
                          child: Image.memory(widget.jpeg, fit: BoxFit.fill),
                        ),
                      ),
                      CustomPaint(
                        painter: _BoxPainter(
                          imageW: w.toDouble(),
                          imageH: h.toDouble(),
                          areaW: areaW,
                          areaH: areaH,
                          detections: widget.detections,
                          cropResults: _cropResults,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: FilledButton(
                  key: const ValueKey<String>('result-save'),
                  onPressed: _canSave ? _save : null,
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Save'),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: _resultPanel(),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton(
                  key: const ValueKey<String>('result-retake'),
                  onPressed: _saving ? null : _requestLeave,
                  child: const Text('Retake'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _resultPanel() {
    if (widget.detections.isEmpty) {
      return const Text(
        'No larva detected - retake photo',
        textAlign: TextAlign.center,
      );
    }
    if (widget.detections.length > 1) {
      return const Text(
        'More than one larva detected. Photograph them one at a time.',
        textAlign: TextAlign.center,
      );
    }
    if (!_classificationComplete) {
      return const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    final CropResult? result = _bestResult;
    final Detection detector = _bestDetection!;
    if (result == null || result.confidence < kClsConfMin) {
      final String guess = result == null
          ? 'Uncertain - retake photo'
          : 'Guess: ${result.fullName} '
                '(${(result.confidence * 100).toStringAsFixed(1)}%)';
      return Text(
        result == null ? guess : 'Uncertain - retake photo\n$guess',
        textAlign: TextAlign.center,
      );
    }

    final String detectorName = _speciesName(detector.code);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '${result.fullName} — '
          '${(result.confidence * 100).toStringAsFixed(1)}%',
          textAlign: TextAlign.center,
        ),
        Text(
          'Detector class: $detectorName (${detector.code})'
          '${detector.code == result.code ? '' : '\nDetector and classifier disagree'}',
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  String _speciesName(String code) {
    final int index = kSpeciesCodes.indexOf(code);
    return index < 0 ? code : kSpeciesFullNames[index];
  }
}

class _BoxPainter extends CustomPainter {
  _BoxPainter({
    required this.imageW,
    required this.imageH,
    required this.areaW,
    required this.areaH,
    required this.detections,
    required this.cropResults,
  });

  final double imageW;
  final double imageH;
  final double areaW;
  final double areaH;
  final List<Detection> detections;
  final List<CropResult?> cropResults;

  @override
  void paint(Canvas canvas, Size size) {
    final double scale = (areaW / imageW) < (areaH / imageH)
        ? areaW / imageW
        : areaH / imageH;
    final double drawW = imageW * scale;
    final double drawH = imageH * scale;
    final double offX = (areaW - drawW) / 2;
    final double offY = (areaH - drawH) / 2;

    for (int i = 0; i < detections.length; i++) {
      final Detection d = detections[i];
      final CropResult? cr = i < cropResults.length ? cropResults[i] : null;
      final String label = cr?.fullName ?? d.code;
      final double conf = cr?.confidence ?? d.confidence;

      final Rect rect = Rect.fromLTRB(
        offX + d.x1 * scale,
        offY + d.y1 * scale,
        offX + d.x2 * scale,
        offY + d.y2 * scale,
      );

      final Paint border = Paint()
        ..color = const Color(0xFF00E5FF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5;
      canvas.drawRect(rect, border);

      final TextPainter tp = TextPainter(
        text: TextSpan(
          text: '$label ${(conf * 100).toStringAsFixed(0)}%',
          style: const TextStyle(
            color: Colors.black,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final Offset labelPos = Offset(rect.left, rect.top - tp.height);
      if (labelPos.dy >= 0) {
        canvas.drawRect(
          Rect.fromLTWH(rect.left, labelPos.dy, tp.width, tp.height),
          Paint()..color = const Color(0xE000E5FF),
        );
        tp.paint(canvas, labelPos);
      } else {
        canvas.drawRect(
          Rect.fromLTWH(rect.left, rect.top, tp.width, tp.height),
          Paint()..color = const Color(0xE000E5FF),
        );
        tp.paint(canvas, Offset(rect.left, rect.top));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BoxPainter oldDelegate) {
    return oldDelegate.detections != detections ||
        oldDelegate.cropResults != cropResults;
  }
}
