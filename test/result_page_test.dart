import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mosquito_detector/src/data/models.dart';
import 'package:mosquito_detector/src/data/surveillance_repository.dart';
import 'package:mosquito_detector/src/inference_engine.dart';
import 'package:mosquito_detector/src/result_page.dart';
import 'package:mosquito_detector/src/yolo_decoder.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Save availability', () {
    testWidgets('Save is disabled when no larva is detected', (
      WidgetTester tester,
    ) async {
      final _FakeRepository repository = _FakeRepository();
      await _openResult(
        tester,
        detections: <Detection>[],
        repository: repository,
      );

      expect(_saveButton(tester).onPressed, isNull);
      expect(find.text('No larva detected - retake photo'), findsOneWidget);
      expect(repository.calls, 0);
    });

    testWidgets('Save is disabled when another larva is detected', (
      WidgetTester tester,
    ) async {
      final _FakeRepository repository = _FakeRepository();
      await _openResult(
        tester,
        detections: <Detection>[_detection(), _detection(confidence: 0.6)],
        repository: repository,
      );

      expect(_saveButton(tester).onPressed, isNull);
      expect(
        find.text(
          'More than one larva detected. Photograph them one at a time.',
        ),
        findsOneWidget,
      );
      expect(repository.calls, 0);
    });

    testWidgets('Save is disabled for uncertain classification', (
      WidgetTester tester,
    ) async {
      final _FakeRepository repository = _FakeRepository();
      await _openResult(
        tester,
        repository: repository,
        classifierConfidence: 0.69,
      );

      expect(_saveButton(tester).onPressed, isNull);
      expect(find.textContaining('Uncertain - retake photo'), findsOneWidget);
      expect(find.textContaining('Aedes albopictus'), findsOneWidget);
      expect(repository.calls, 0);
    });

    testWidgets('Save is enabled for one confident detection', (
      WidgetTester tester,
    ) async {
      final _FakeRepository repository = _FakeRepository();
      final _FakeEngine engine = _FakeEngine();
      await _openResult(tester, repository: repository, engine: engine);

      expect(_saveButton(tester).onPressed, isNotNull);
      expect(find.text('Aedes albopictus — 91.0%'), findsOneWidget);
      expect(find.textContaining('Detector class:'), findsOneWidget);
      expect(repository.calls, 0);
      expect(engine.classifyCalls, 1);
    });
  });

  testWidgets('two quick Save taps write and count one record once', (
    WidgetTester tester,
  ) async {
    final Completer<void> saveGate = Completer<void>();
    final _FakeRepository repository = _FakeRepository(gate: saveGate);
    final _FakeEngine engine = _FakeEngine();
    await _openResult(tester, repository: repository, engine: engine);

    await tester.tap(find.byKey(const ValueKey<String>('result-save')));
    await tester.tap(find.byKey(const ValueKey<String>('result-save')));
    await tester.pump();

    expect(repository.calls, 1);
    expect(engine.classifyCalls, 1);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    saveGate.complete();
    await tester.pumpAndSettle();

    expect(repository.calls, 1);
    expect(repository.records, hasLength(1));
    expect(repository.counts, <String, int>{'AB': 1});
    expect(find.text('Camera page'), findsOneWidget);
    expect(find.text('Saved: Aedes albopictus'), findsOneWidget);
    expect(find.text('Discard this result?'), findsNothing);
  });

  testWidgets('failed save re-enables Save and keeps result visible', (
    WidgetTester tester,
  ) async {
    final _FakeRepository repository = _FakeRepository(
      failure: StateError('write failed'),
    );
    await _openResult(tester, repository: repository);

    await tester.tap(find.byKey(const ValueKey<String>('result-save')));
    await tester.pumpAndSettle();

    expect(repository.calls, 1);
    expect(_saveButton(tester).onPressed, isNotNull);
    expect(find.text('Aedes albopictus — 91.0%'), findsOneWidget);
    expect(
      find.textContaining('Save failed: Bad state: write failed'),
      findsOneWidget,
    );
    expect(find.text('Camera page'), findsNothing);
  });

  testWidgets('Retake and app-bar back ask before discarding valid result', (
    WidgetTester tester,
  ) async {
    await _openResult(tester);

    await tester.tap(find.byKey(const ValueKey<String>('result-retake')));
    await tester.pumpAndSettle();
    expect(find.text('Discard this result?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Aedes albopictus — 91.0%'), findsOneWidget);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Discard this result?'), findsOneWidget);
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(find.text('Camera page'), findsOneWidget);
  });

  testWidgets('system back asks before discarding valid result', (
    WidgetTester tester,
  ) async {
    await _openResult(tester);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Discard this result?'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Aedes albopictus — 91.0%'), findsOneWidget);
  });

  testWidgets('invalid result leaves by Retake without a dialog', (
    WidgetTester tester,
  ) async {
    await _openResult(tester, detections: <Detection>[]);

    await tester.tap(find.byKey(const ValueKey<String>('result-retake')));
    await tester.pumpAndSettle();

    expect(find.text('Camera page'), findsOneWidget);
    expect(find.text('Discard this result?'), findsNothing);
  });
}

FilledButton _saveButton(WidgetTester tester) => tester.widget<FilledButton>(
  find.byKey(const ValueKey<String>('result-save')),
);

Future<void> _openResult(
  WidgetTester tester, {
  _FakeRepository? repository,
  _FakeEngine? engine,
  List<Detection>? detections,
  double classifierConfidence = 0.91,
}) async {
  tester.view.physicalSize = const Size(800, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final img.Image photo = img.Image(width: 8, height: 8);
  final Uint8List jpeg = Uint8List.fromList(img.encodePng(photo));
  final _FakeRepository repo = repository ?? _FakeRepository();
  final _FakeEngine model =
      engine ?? _FakeEngine(confidence: classifierConfidence);
  model.confidence = classifierConfidence;

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (BuildContext context) => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Camera page'),
                TextButton(
                  onPressed: () {
                    Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (_) => ResultPage(
                          engine: model,
                          repository: repo,
                          jpeg: jpeg,
                          oriented: photo,
                          detections: detections ?? <Detection>[_detection()],
                          capturedAt: DateTime(2026, 10, 25, 12),
                          barangay: 'Aguada (Pob.)',
                        ),
                      ),
                    );
                  },
                  child: const Text('Open result'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open result'));
  await tester.pumpAndSettle();
}

Detection _detection({double confidence = 0.93}) => Detection(
  x1: 1,
  y1: 1,
  x2: 6,
  y2: 6,
  confidence: confidence,
  classId: 0,
  classScores: <double>[confidence, 0.01, 0.02, 0.04],
  code: 'AB',
);

class _FakeEngine extends InferenceEngine {
  _FakeEngine({this.confidence = 0.91});

  double confidence;
  int classifyCalls = 0;

  @override
  CropResult classify(Uint8List photoBytes, Detection detection) {
    classifyCalls++;
    return CropResult(
      genus: 'Aedes',
      code: 'AB',
      fullName: 'Aedes albopictus',
      confidence: confidence,
      classId: 0,
      probabilities: <double>[confidence, 0.03, 0.02, 0.04],
    );
  }
}

class _FakeRepository extends SurveillanceRepository {
  _FakeRepository({this.gate, this.failure});

  final Completer<void>? gate;
  final Object? failure;
  final List<SurveillanceRecord> records = <SurveillanceRecord>[];
  final Map<String, int> counts = <String, int>{};
  int calls = 0;

  @override
  Future<SurveillanceRecord> saveObservation({
    required Uint8List imageBytes,
    required DateTime capturedAt,
    required String barangay,
    required String speciesCode,
    double? avgConfidence,
    int? userId,
    String? notes,
    String processingStatus = 'processed',
  }) async {
    calls++;
    await gate?.future;
    if (failure != null) {
      throw failure!;
    }
    counts.update(speciesCode, (int value) => value + 1, ifAbsent: () => 1);
    final SurveillanceRecord record = SurveillanceRecord(
      sessionId: 1,
      imagePath: 'test-image.jpg',
      barangay: barangay,
      captureTimestamp: capturedAt,
      speciesCode: speciesCode,
      aedesAlbopictusCount: speciesCode == 'AB' ? 1 : 0,
      aedesAegyptiCount: speciesCode == 'AG' ? 1 : 0,
      culexCount: speciesCode == 'CQ' ? 1 : 0,
      anophelesCount: speciesCode == 'AN' ? 1 : 0,
      totalDetections: 1,
      avgConfidence: avgConfidence,
      processingStatus: processingStatus,
      createdAt: capturedAt,
    );
    records.add(record);
    return record;
  }
}
