import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:mosquito_detector/src/data/app_database.dart';
import 'package:mosquito_detector/src/prediction/aedes_activity_repository.dart';
import 'package:mosquito_detector/src/prediction/aedes_logistic_predictor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late Directory directory;
  late AppDatabase appDatabase;
  late AedesActivityRepository repository;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('aedes-activity-test-');
    appDatabase = AppDatabase(
      factoryOverride: databaseFactoryFfi,
      databasesPathOverride: () async => directory.path,
    );
    repository = AedesActivityRepository(
      appDatabase: appDatabase,
      predictor: AedesLogisticPredictor.fromJson(_modelParameters),
    );
  });

  tearDown(() async {
    await appDatabase.close();
    await directory.delete(recursive: true);
  });

  test(
    'complete five-week history returns a prediction and creates history table',
    () async {
      await _addFiveWeekHistory(appDatabase, referenceDate: _referenceDate);

      final BarangayPrediction? prediction = await repository
          .predictForBarangay('Aguada (Pob.)', referenceDate: _referenceDate);

      expect(prediction, isNotNull);
      expect(prediction!.weeks, hasLength(5));
      expect(
        prediction.weeks.map((week) => week.observedDays),
        everyElement(1),
      );
      expect(prediction.modelInputs, hasLength(5));
      final db = await appDatabase.database;
      final List<Map<String, Object?>> tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
        <Object?>['aedes_direction_predictions'],
      );
      expect(tables, hasLength(1));
    },
  );

  test('a missing exact week returns null instead of zero-filling', () async {
    await _addFiveWeekHistory(
      appDatabase,
      referenceDate: _referenceDate,
      missingWeek: 2,
    );

    expect(
      await repository.predictForBarangay(
        'Aguada (Pob.)',
        referenceDate: _referenceDate,
      ),
      isNull,
    );
  });

  test('records from barangay A never fill barangay B weeks', () async {
    await _addFiveWeekHistory(
      appDatabase,
      referenceDate: _referenceDate,
      barangay: 'Aguada (Pob.)',
    );
    await _insertScan(
      appDatabase,
      date: _referenceDate,
      barangay: 'Bacolod',
      speciesCode: 'AG',
    );

    expect(
      await repository.predictForBarangay(
        'Aguada (Pob.)',
        referenceDate: _referenceDate,
      ),
      isNotNull,
    );
    expect(
      await repository.predictForBarangay(
        'Bacolod',
        referenceDate: _referenceDate,
      ),
      isNull,
    );
  });

  test(
    'multiple scans on one date count once and any AG scan makes it positive',
    () async {
      await _addFiveWeekHistory(appDatabase, referenceDate: _referenceDate);
      final DateTime sameDay = _weekStart(_referenceDate);
      await _insertScan(
        appDatabase,
        date: sameDay,
        barangay: 'Aguada (Pob.)',
        speciesCode: 'CQ',
      );
      await _insertScan(
        appDatabase,
        date: sameDay,
        barangay: 'Aguada (Pob.)',
        speciesCode: 'AG',
      );

      final BarangayPrediction prediction = (await repository
          .predictForBarangay('Aguada (Pob.)', referenceDate: _referenceDate))!;

      expect(prediction.weeks.last.observedDays, 1);
      expect(prediction.weeks.last.positiveDays, 1);
    },
  );

  test('a processed non-AG-only day is observed and negative', () async {
    await _addFiveWeekHistory(
      appDatabase,
      referenceDate: _referenceDate,
      speciesCode: 'CQ',
      currentPositive: false,
    );

    final BarangayPrediction prediction = (await repository.predictForBarangay(
      'Aguada (Pob.)',
      referenceDate: _referenceDate,
    ))!;

    expect(prediction.weeks.last.observedDays, 1);
    expect(prediction.weeks.last.positiveDays, 0);
    expect(prediction.weeks.last.positivity, 0);
  });

  test(
    'prediction history creates its table on first repository use',
    () async {
      final String databasePath =
          '${directory.path}${Platform.pathSeparator}${AppDatabase.fileName}';
      final Database existingVersion3 = await databaseFactoryFfi.openDatabase(
        databasePath,
        options: OpenDatabaseOptions(version: AppDatabase.schemaVersion),
      );
      await existingVersion3.close();

      final List<Map<String, Object?>> history = await repository
          .predictionHistory('Aguada (Pob.)');

      expect(history, isEmpty);
    },
  );
}

final DateTime _referenceDate = DateTime(2026, 6, 17);

final Map<String, Object?> _modelParameters = <String, Object?>{
  'features': <String>['Lag_1', 'Lag_2', 'Lag_3', 'Lag_4', 'Current_Activity'],
  'scaler_mean': <double>[0, 0, 0, 0, 0],
  'scaler_scale': <double>[1, 1, 1, 1, 1],
  'coefficients': <double>[1, 1, 1, 1, 1],
  'intercept': 0,
  'classes': <int>[0, 1],
};

Future<void> _addFiveWeekHistory(
  AppDatabase appDatabase, {
  required DateTime referenceDate,
  String barangay = 'Aguada (Pob.)',
  String speciesCode = 'CQ',
  int? missingWeek,
  bool currentPositive = true,
}) async {
  final DateTime currentStart = _weekStart(referenceDate);
  final DateTime firstStart = currentStart.subtract(const Duration(days: 28));
  for (int week = 0; week < 5; week++) {
    if (week == missingWeek) {
      continue;
    }
    await _insertScan(
      appDatabase,
      date: firstStart.add(Duration(days: week * 7)),
      barangay: barangay,
      speciesCode: week == 4 && currentPositive ? 'AG' : speciesCode,
    );
  }
}

DateTime _weekStart(DateTime date) {
  final DateTime day = DateTime(date.year, date.month, date.day);
  return day.subtract(Duration(days: day.weekday - DateTime.monday));
}

Future<void> _insertScan(
  AppDatabase appDatabase, {
  required DateTime date,
  required String barangay,
  required String speciesCode,
}) async {
  final db = await appDatabase.database;
  final String timestamp = date.toIso8601String();
  final int sessionId = await db.insert(
    'surveillance_sessions',
    <String, Object?>{
      'user_id': null,
      'barangay': barangay,
      'started_at': timestamp,
      'ended_at': timestamp,
      'notes': null,
    },
  );
  await db.insert('surveillance_records', <String, Object?>{
    'session_id': sessionId,
    'week_id': null,
    'image_path': 'test.jpg',
    'barangay': barangay,
    'capture_timestamp': timestamp,
    'species_code': speciesCode,
    'aedes_albopictus_count': 0,
    'aedes_aegypti_count': speciesCode == 'AG' ? 1 : 0,
    'culex_count': speciesCode == 'CQ' ? 1 : 0,
    'anopheles_count': speciesCode == 'AN' ? 1 : 0,
    'total_detections': 1,
    'avg_confidence': 1.0,
    'processing_status': 'processed',
    'created_at': timestamp,
  });
}
