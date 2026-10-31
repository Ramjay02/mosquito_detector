import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:mosquito_detector/src/data/app_database.dart';
import 'package:mosquito_detector/src/data/surveillance_repository.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    sqfliteFfiInit();
    tempDir = await Directory.systemTemp.createTemp('wayawaya_schema_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('upgrade deletes old records and images, preserving users', () async {
    final String oldImageOne = p.join(tempDir.path, 'old_one.jpg');
    final String oldImageTwo = p.join(tempDir.path, 'old_two.jpg');
    await File(oldImageOne).writeAsBytes(<int>[1, 2, 3]);
    await File(oldImageTwo).writeAsBytes(<int>[4, 5, 6]);

    final String dbPath = p.join(tempDir.path, AppDatabase.fileName);
    final Database oldDb = await databaseFactoryFfi.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 2,
        onCreate: (Database db, int version) async => _createVersion2Schema(db),
      ),
    );
    await _insertVersion2Rows(oldDb, oldImageOne, oldImageTwo);
    await oldDb.close();

    final AppDatabase appDb = AppDatabase(
      factoryOverride: databaseFactoryFfi,
      databasesPathOverride: () async => tempDir.path,
    );
    try {
      final Database upgraded = await appDb.database;
      expect(
        (await upgraded.rawQuery('PRAGMA user_version')).single['user_version'],
        AppDatabase.schemaVersion,
      );

      expect(await upgraded.query('users'), hasLength(1));
      expect(
        (await upgraded.query('users')).single['username'],
        'field_worker',
      );
      expect(await upgraded.query('weekly_surveillance'), isEmpty);
      expect(await upgraded.query('surveillance_sessions'), isEmpty);
      expect(await upgraded.query('surveillance_records'), isEmpty);
      expect(await upgraded.query('prediction_results'), isEmpty);
      expect(await File(oldImageOne).exists(), isFalse);
      expect(await File(oldImageTwo).exists(), isFalse);

      _expectCurrentSchema(await _schemaColumns(upgraded));
      await _expectCurrentConstraints(upgraded);
    } finally {
      await appDb.close();
    }
  });

  test('fresh install creates the same schema as an upgrade', () async {
    final Directory upgradedDir = Directory(p.join(tempDir.path, 'upgrade'));
    final Directory freshDir = Directory(p.join(tempDir.path, 'fresh'));
    await upgradedDir.create();
    await freshDir.create();

    final Database oldDb = await databaseFactoryFfi.openDatabase(
      p.join(upgradedDir.path, AppDatabase.fileName),
      options: OpenDatabaseOptions(
        version: 2,
        onCreate: (Database db, int version) async => _createVersion2Schema(db),
      ),
    );
    await oldDb.close();

    final AppDatabase upgradedDb = AppDatabase(
      factoryOverride: databaseFactoryFfi,
      databasesPathOverride: () async => upgradedDir.path,
    );
    final AppDatabase freshDb = AppDatabase(
      factoryOverride: databaseFactoryFfi,
      databasesPathOverride: () async => freshDir.path,
    );
    try {
      final Database upgraded = await upgradedDb.database;
      final Database fresh = await freshDb.database;
      _expectCurrentSchema(await _schemaColumns(upgraded));
      _expectCurrentSchema(await _schemaColumns(fresh));
      await _expectCurrentConstraints(upgraded);
      await _expectCurrentConstraints(fresh);
    } finally {
      await upgradedDb.close();
      await freshDb.close();
    }
  });

  test('species counts upsert per ISO week and barangay', () async {
    final AppDatabase appDb = AppDatabase(
      factoryOverride: databaseFactoryFfi,
      databasesPathOverride: () async => tempDir.path,
    );
    final SurveillanceRepository repository = SurveillanceRepository(
      db: appDb,
      store: (Uint8List bytes, DateTime capturedAt, String speciesCode) async =>
          p.join(
            tempDir.path,
            '${capturedAt.microsecondsSinceEpoch}_$speciesCode.jpg',
          ),
    );
    try {
      final DateTime capturedAt = DateTime(2026, 10, 16, 12);
      for (final String code in <String>['AB', 'AG', 'AN', 'CQ', 'AB']) {
        await repository.saveObservation(
          imageBytes: Uint8List.fromList(<int>[code.codeUnitAt(0)]),
          capturedAt: capturedAt,
          barangay: 'Aguada (Pob.)',
          speciesCode: code,
        );
      }

      final Database db = await appDb.database;
      final List<Map<String, Object?>> weekRows = await db.query(
        'weekly_surveillance',
        where: 'year = ? AND week_number = ? AND barangay = ?',
        whereArgs: <Object?>[2026, 42, 'Aguada (Pob.)'],
      );
      expect(weekRows, hasLength(1));
      final Map<String, Object?> week = weekRows.single;
      expect(week['aedes_albopictus_count'], 2);
      expect(week['aedes_aegypti_count'], 1);
      expect(week['culex_count'], 1);
      expect(week['anopheles_count'], 1);

      final List<Map<String, Object?>> records = await db.query(
        'surveillance_records',
      );
      expect(records, hasLength(5));
      for (final Map<String, Object?> record in records) {
        final String code = record['species_code'] as String;
        expect(record['aedes_albopictus_count'], code == 'AB' ? 1 : 0);
        expect(record['aedes_aegypti_count'], code == 'AG' ? 1 : 0);
        expect(record['culex_count'], code == 'CQ' ? 1 : 0);
        expect(record['anopheles_count'], code == 'AN' ? 1 : 0);
      }

      await repository.saveObservation(
        imageBytes: Uint8List.fromList(<int>[7]),
        capturedAt: capturedAt,
        barangay: 'Bacolod',
        speciesCode: 'AN',
      );
      expect(await db.query('weekly_surveillance'), hasLength(2));
    } finally {
      await appDb.close();
    }
  });
}

Future<Map<String, List<String>>> _schemaColumns(Database db) async {
  const List<String> tables = <String>[
    'users',
    'weekly_surveillance',
    'surveillance_sessions',
    'surveillance_records',
    'prediction_results',
  ];
  final Map<String, List<String>> result = <String, List<String>>{};
  for (final String table in tables) {
    final List<Map<String, Object?>> columns = await db.rawQuery(
      'PRAGMA table_info($table)',
    );
    result[table] = columns
        .map((Map<String, Object?> column) => column['name'] as String)
        .toList();
  }
  return result;
}

void _expectCurrentSchema(Map<String, List<String>> schema) {
  expect(schema, <String, List<String>>{
    'users': <String>['id', 'username', 'full_name', 'role', 'created_at'],
    'weekly_surveillance': <String>[
      'id',
      'year',
      'week_number',
      'week_start',
      'week_end',
      'barangay',
      'aedes_albopictus_count',
      'aedes_aegypti_count',
      'culex_count',
      'anopheles_count',
      'updated_at',
    ],
    'surveillance_sessions': <String>[
      'id',
      'user_id',
      'barangay',
      'started_at',
      'ended_at',
      'notes',
    ],
    'surveillance_records': <String>[
      'id',
      'session_id',
      'week_id',
      'image_path',
      'barangay',
      'capture_timestamp',
      'species_code',
      'aedes_albopictus_count',
      'aedes_aegypti_count',
      'culex_count',
      'anopheles_count',
      'total_detections',
      'avg_confidence',
      'processing_status',
      'created_at',
    ],
    'prediction_results': <String>[
      'id',
      'week_id',
      'training_start',
      'training_end',
      'latest_observed',
      'predicted_count',
      'predicted_change',
      'increase_likely',
      'created_at',
    ],
  });
}

Future<void> _expectCurrentConstraints(Database db) async {
  final List<Map<String, Object?>> recordColumns = await db.rawQuery(
    'PRAGMA table_info(surveillance_records)',
  );
  final Map<String, Map<String, Object?>> recordsByName =
      <String, Map<String, Object?>>{
        for (final Map<String, Object?> column in recordColumns)
          column['name'] as String: column,
      };
  expect(recordsByName['species_code']!['notnull'], 1);

  for (final String table in <String>[
    'weekly_surveillance',
    'surveillance_records',
  ]) {
    final List<Map<String, Object?>> columns = await db.rawQuery(
      'PRAGMA table_info($table)',
    );
    for (final Map<String, Object?> column in columns) {
      if ((column['name'] as String).endsWith('_count')) {
        expect(column['notnull'], 1);
        expect(column['dflt_value'], '0');
      }
    }
  }
}

Future<void> _createVersion2Schema(Database db) async {
  await db.execute('PRAGMA foreign_keys = ON');
  await db.execute('''
    CREATE TABLE users (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      username TEXT NOT NULL UNIQUE,
      full_name TEXT NOT NULL,
      role TEXT NOT NULL,
      created_at TEXT NOT NULL
    )
  ''');
  await db.execute('''
    CREATE TABLE weekly_surveillance (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      year INTEGER NOT NULL,
      week_number INTEGER NOT NULL,
      week_start TEXT NOT NULL,
      week_end TEXT NOT NULL,
      aedes_count INTEGER NOT NULL DEFAULT 0,
      culex_count INTEGER NOT NULL DEFAULT 0,
      anopheles_count INTEGER NOT NULL DEFAULT 0,
      updated_at TEXT NOT NULL,
      UNIQUE(year, week_number)
    )
  ''');
  await db.execute('''
    CREATE TABLE surveillance_sessions (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      user_id INTEGER,
      barangay TEXT,
      started_at TEXT NOT NULL,
      ended_at TEXT,
      notes TEXT,
      FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE SET NULL
    )
  ''');
  await db.execute('''
    CREATE TABLE surveillance_records (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      session_id INTEGER NOT NULL,
      week_id INTEGER,
      image_path TEXT NOT NULL,
      capture_timestamp TEXT NOT NULL,
      species_code TEXT,
      aedes_count INTEGER NOT NULL DEFAULT 0,
      culex_count INTEGER NOT NULL DEFAULT 0,
      anopheles_count INTEGER NOT NULL DEFAULT 0,
      unknown_count INTEGER NOT NULL DEFAULT 0,
      total_detections INTEGER NOT NULL DEFAULT 0,
      avg_confidence REAL,
      processing_status TEXT NOT NULL DEFAULT 'processed',
      created_at TEXT NOT NULL,
      FOREIGN KEY(session_id) REFERENCES surveillance_sessions(id) ON DELETE CASCADE,
      FOREIGN KEY(week_id) REFERENCES weekly_surveillance(id) ON DELETE SET NULL
    )
  ''');
  await db.execute('''
    CREATE TABLE prediction_results (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      week_id INTEGER,
      training_start TEXT,
      training_end TEXT,
      latest_observed INTEGER NOT NULL,
      predicted_count REAL NOT NULL,
      predicted_change REAL NOT NULL,
      increase_likely INTEGER NOT NULL,
      created_at TEXT NOT NULL,
      FOREIGN KEY(week_id) REFERENCES weekly_surveillance(id) ON DELETE SET NULL
    )
  ''');
}

Future<void> _insertVersion2Rows(
  Database db,
  String oldImageOne,
  String oldImageTwo,
) async {
  await db.insert('users', <String, Object?>{
    'id': 1,
    'username': 'field_worker',
    'full_name': 'Field Worker',
    'role': 'field_worker',
    'created_at': '2026-10-16T08:00:00.000',
  });
  await db.insert('weekly_surveillance', <String, Object?>{
    'id': 10,
    'year': 2026,
    'week_number': 42,
    'week_start': '2026-10-12T00:00:00.000',
    'week_end': '2026-10-18T00:00:00.000',
    'aedes_count': 3,
    'culex_count': 1,
    'anopheles_count': 2,
    'updated_at': '2026-10-16T08:00:00.000',
  });
  await db.insert('surveillance_sessions', <String, Object?>{
    'id': 20,
    'user_id': 1,
    'barangay': 'Aguada (Pob.)',
    'started_at': '2026-10-16T08:00:00.000',
    'ended_at': '2026-10-16T08:00:00.000',
  });
  for (final MapEntry<int, String> row in <MapEntry<int, String>>[
    MapEntry<int, String>(30, oldImageOne),
    MapEntry<int, String>(31, oldImageTwo),
  ]) {
    await db.insert('surveillance_records', <String, Object?>{
      'id': row.key,
      'session_id': 20,
      'week_id': 10,
      'image_path': row.value,
      'capture_timestamp': '2026-10-16T08:00:00.000',
      'species_code': 'AB',
      'aedes_count': 1,
      'culex_count': 0,
      'anopheles_count': 0,
      'unknown_count': 0,
      'total_detections': 1,
      'processing_status': 'processed',
      'created_at': '2026-10-16T08:00:00.000',
    });
  }
  await db.insert('prediction_results', <String, Object?>{
    'week_id': 10,
    'latest_observed': 6,
    'predicted_count': 7,
    'predicted_change': 1,
    'increase_likely': 1,
    'created_at': '2026-10-16T08:00:00.000',
  });
}
