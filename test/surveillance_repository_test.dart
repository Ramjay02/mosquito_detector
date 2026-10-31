import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:mosquito_detector/src/data/app_database.dart';
import 'package:mosquito_detector/src/data/models.dart';
import 'package:mosquito_detector/src/data/surveillance_repository.dart';

void main() {
  group('isoWeekFor', () {
    test('mid-year date maps to the containing Monday-Sunday week', () {
      final IsoWeek week = SurveillanceRepository.isoWeekFor(
        DateTime(2026, 10, 16),
      );
      expect(week.year, 2026);
      expect(week.weekNumber, 42);
      expect(week.start, DateTime(2026, 10, 12));
      expect(week.end, DateTime(2026, 10, 18));
    });

    test('Jan 1 falls in the ISO week 53 of the previous year', () {
      final IsoWeek week = SurveillanceRepository.isoWeekFor(
        DateTime(2027, 1, 1),
      );
      expect(week.year, 2026);
      expect(week.weekNumber, 53);
      expect(week.start, DateTime(2026, 12, 28));
      expect(week.end, DateTime(2027, 1, 3));
    });

    test('Jan 1 of a 53-week year starts week 1', () {
      final IsoWeek week = SurveillanceRepository.isoWeekFor(
        DateTime(2026, 1, 1),
      );
      expect(week.year, 2026);
      expect(week.weekNumber, 1);
      expect(week.start, DateTime(2025, 12, 29));
      expect(week.end, DateTime(2026, 1, 4));
    });
  });

  group('model serialization', () {
    test('SurveillanceRecord round-trips', () {
      final SurveillanceRecord record = SurveillanceRecord(
        id: 7,
        sessionId: 3,
        weekId: 2,
        imagePath: '/tmp/img.jpg',
        barangay: 'Aguada (Pob.)',
        captureTimestamp: DateTime(2026, 10, 16, 8, 30, 15),
        speciesCode: 'AB',
        aedesAlbopictusCount: 1,
        aedesAegyptiCount: 0,
        culexCount: 2,
        totalDetections: 7,
        avgConfidence: 0.91,
        createdAt: DateTime(2026, 10, 16, 8, 31),
      );
      final SurveillanceRecord back = SurveillanceRecord.fromMap(
        record.toMap(),
      );
      expect(back.id, 7);
      expect(back.sessionId, 3);
      expect(back.weekId, 2);
      expect(back.imagePath, '/tmp/img.jpg');
      expect(back.captureTimestamp, record.captureTimestamp);
      expect(back.barangay, 'Aguada (Pob.)');
      expect(back.speciesCode, 'AB');
      expect(back.aedesAlbopictusCount, 1);
      expect(back.aedesAegyptiCount, 0);
      expect(back.culexCount, 2);
      expect(back.totalDetections, 7);
      expect(back.avgConfidence, 0.91);
      expect(back.processingStatus, 'processed');
      expect(back.createdAt, record.createdAt);
    });

    test('WeeklySurveillance round-trips and totals', () {
      final WeeklySurveillance week = WeeklySurveillance(
        id: 5,
        year: 2026,
        weekNumber: 42,
        weekStart: DateTime(2026, 10, 12),
        weekEnd: DateTime(2026, 10, 18),
        barangay: 'Aguada (Pob.)',
        aedesAlbopictusCount: 2,
        aedesAegyptiCount: 4,
        culexCount: 4,
        updatedAt: DateTime(2026, 10, 16, 9),
      );
      final WeeklySurveillance back = WeeklySurveillance.fromMap(week.toMap());
      expect(back.id, 5);
      expect(back.year, 2026);
      expect(back.weekNumber, 42);
      expect(back.weekStart, DateTime(2026, 10, 12));
      expect(back.barangay, 'Aguada (Pob.)');
      expect(back.aedesAlbopictusCount, 2);
      expect(back.aedesAegyptiCount, 4);
      expect(back.culexCount, 4);
      expect(back.totalCount, 10);
      expect(back.label, '2026 - W42');
    });
  });

  group('sqlite storage', () {
    late Directory tempDir;
    late AppDatabase db;
    late SurveillanceRepository repo;

    setUp(() async {
      sqfliteFfiInit();
      tempDir = await Directory.systemTemp.createTemp('wayawaya_test_');
      db = AppDatabase(
        factoryOverride: databaseFactoryFfi,
        databasesPathOverride: () async => tempDir.path,
      );
      repo = SurveillanceRepository(
        db: db,
        store: (
          Uint8List bytes,
          DateTime capturedAt,
          String speciesCode,
        ) async => p.join(tempDir.path, 'img.jpg'),
      );
    });

    tearDown(() async {
      await db.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('creates all five spec tables', () async {
      final Database database = await db.database;
      final List<String> tables = (await database.query(
        "sqlite_master",
        columns: <String>['name'],
        where: "type = 'table'",
      )).map((Map<String, Object?> r) => r['name'] as String).toList();

      expect(tables, contains('users'));
      expect(tables, contains('weekly_surveillance'));
      expect(tables, contains('surveillance_sessions'));
      expect(tables, contains('surveillance_records'));
      expect(tables, contains('prediction_results'));
    });

    test('ensureLocalUser is idempotent', () async {
      final int first = await repo.ensureLocalUser();
      final int second = await repo.ensureLocalUser();
      expect(first, greaterThan(0));
      expect(second, first);
    });

    test(
      'saveObservation stores session, record and aggregates a weekly total',
      () async {
        final SurveillanceRecord r1 = await repo.saveObservation(
          imageBytes: Uint8List.fromList(<int>[1, 2, 3]),
          capturedAt: DateTime(2026, 10, 16, 8, 30),
          barangay: 'Aguada (Pob.)',
          speciesCode: 'AB',
          avgConfidence: 0.88,
        );
        expect(r1.id, isNotNull);
        expect(r1.weekId, isNotNull);

        final SurveillanceRecord r2 = await repo.saveObservation(
          imageBytes: Uint8List.fromList(<int>[4, 5, 6]),
          capturedAt: DateTime(2026, 10, 17, 7, 15),
          barangay: 'Aguada (Pob.)',
          speciesCode: 'AG',
        );

        expect(await repo.recordCount(), 2);
        final List<WeeklySurveillance> weeks = await repo.weeklySeries();
        expect(weeks, hasLength(1));
        expect(weeks.first.weekNumber, 42);
        expect(weeks.first.aedesAlbopictusCount, 1);
        expect(weeks.first.aedesAegyptiCount, 1);
        expect(weeks.first.culexCount, 0);

        final List<SurveillanceRecord> recent = await repo.recentRecords();
        expect(recent, hasLength(2));
        expect(recent.first.id, r2.id);
        expect(recent.first.aedesAegyptiCount, 1);
        expect(recent.last.id, r1.id);
        expect(recent.last.totalDetections, 1);
      },
    );

    test(
      'getRecentRecords respects limit and descending timestamp order',
      () async {
        final List<SurveillanceRecord> saved = <SurveillanceRecord>[];
        for (int minute = 0; minute < 7; minute++) {
          saved.add(
            await repo.saveObservation(
              imageBytes: Uint8List.fromList(<int>[minute]),
              capturedAt: DateTime(2026, 10, 16, 8, minute),
              barangay: 'Aguada (Pob.)',
              speciesCode: 'AB',
            ),
          );
        }

        final List<SurveillanceRecord> recent = await repo.getRecentRecords(
          limit: 5,
        );
        expect(recent, hasLength(5));
        expect(recent.map((SurveillanceRecord record) => record.id), <int?>[
          saved[6].id,
          saved[5].id,
          saved[4].id,
          saved[3].id,
          saved[2].id,
        ]);
      },
    );

    test('records in different weeks create separate weekly rows', () async {
      await repo.saveObservation(
        imageBytes: Uint8List.fromList(<int>[1]),
        capturedAt: DateTime(2026, 10, 16, 8, 30),
        barangay: 'Aguada (Pob.)',
        speciesCode: 'AB',
      );
      await repo.saveObservation(
        imageBytes: Uint8List.fromList(<int>[2]),
        capturedAt: DateTime(2026, 10, 26, 8, 30),
        barangay: 'Aguada (Pob.)',
        speciesCode: 'AB',
      );

      final List<WeeklySurveillance> weeks = await repo.weeklySeries();
      expect(weeks, hasLength(2));
      expect(weeks[0].weekNumber, 42);
      expect(weeks[0].aedesAlbopictusCount, 1);
      expect(weeks[1].weekNumber, 44);
      expect(weeks[1].aedesAlbopictusCount, 1);
    });

    test('latestWeek and latestPrediction work on an empty database', () async {
      expect(await repo.latestWeek(), isNull);
      expect(await repo.latestPrediction(), isNull);
    });

    test('persists a prediction result', () async {
      final PredictionResult prediction = PredictionResult(
        weekId: null,
        latestObserved: 8,
        predictedCount: 10,
        predictedChange: 2,
        increaseLikely: true,
        createdAt: DateTime(2026, 10, 18),
      );
      await repo.savePrediction(prediction);
      final PredictionResult? back = await repo.latestPrediction();
      expect(back, isNotNull);
      expect(back!.latestObserved, 8);
      expect(back.predictedCount, 10);
      expect(back.increaseLikely, isTrue);
    });
  });
}
