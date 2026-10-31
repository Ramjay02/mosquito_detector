import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class AppDatabase {
  AppDatabase({this.factoryOverride, this.databasesPathOverride});

  static final AppDatabase instance = AppDatabase();

  static const String fileName = 'wayawaya_surveillance.db';
  static const int schemaVersion = 3;

  final DatabaseFactory? factoryOverride;
  final Future<String> Function()? databasesPathOverride;

  Database? _db;

  DatabaseFactory get _dbFactory => factoryOverride ?? databaseFactory;

  Future<Database> get database async {
    final Database? existing = _db;
    if (existing != null && existing.isOpen) {
      return existing;
    }
    final Database opened = await _open();
    _db = opened;
    return opened;
  }

  Future<Database> _open() async {
    final Future<String> Function()? overridePath = databasesPathOverride;
    final Future<String> pathFuture = overridePath != null
        ? overridePath()
        : getDatabasesPath();
    final String dbPath = p.join(await pathFuture, fileName);
    return _dbFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        onConfigure: (Database db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (Database db, int version) async {
          await _createSchema(db);
        },
        onUpgrade: (Database db, int oldVersion, int newVersion) async {
          if (oldVersion < 3) {
            await _upgradeToVersion3(db);
          }
        },
      ),
    );
  }

  Future<void> _upgradeToVersion3(Database db) async {
    final List<Map<String, Object?>> records = await db.query(
      'surveillance_records',
      columns: <String>['image_path'],
    );
    for (final Map<String, Object?> record in records) {
      final String? path = record['image_path'] as String?;
      if (path == null || path.isEmpty) {
        continue;
      }
      try {
        final File file = File(path);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {}
    }

    await db.execute('DROP TABLE IF EXISTS prediction_results');
    await db.execute('DROP TABLE IF EXISTS surveillance_records');
    await db.execute('DROP TABLE IF EXISTS surveillance_sessions');
    await db.execute('DROP TABLE IF EXISTS weekly_surveillance');
    await _createSchema(db);
  }

  Future<void> _createSchema(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        username TEXT NOT NULL UNIQUE,
        full_name TEXT NOT NULL,
        role TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS weekly_surveillance (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        year INTEGER NOT NULL,
        week_number INTEGER NOT NULL,
        week_start TEXT NOT NULL,
        week_end TEXT NOT NULL,
        barangay TEXT NOT NULL,
        aedes_albopictus_count INTEGER NOT NULL DEFAULT 0,
        aedes_aegypti_count INTEGER NOT NULL DEFAULT 0,
        culex_count INTEGER NOT NULL DEFAULT 0,
        anopheles_count INTEGER NOT NULL DEFAULT 0,
        updated_at TEXT NOT NULL,
        UNIQUE(year, week_number, barangay)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS surveillance_sessions (
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
      CREATE TABLE IF NOT EXISTS surveillance_records (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id INTEGER NOT NULL,
        week_id INTEGER,
        image_path TEXT NOT NULL,
        barangay TEXT NOT NULL,
        capture_timestamp TEXT NOT NULL,
        species_code TEXT NOT NULL,
        aedes_albopictus_count INTEGER NOT NULL DEFAULT 0,
        aedes_aegypti_count INTEGER NOT NULL DEFAULT 0,
        culex_count INTEGER NOT NULL DEFAULT 0,
        anopheles_count INTEGER NOT NULL DEFAULT 0,
        total_detections INTEGER NOT NULL DEFAULT 0,
        avg_confidence REAL,
        processing_status TEXT NOT NULL DEFAULT 'processed',
        created_at TEXT NOT NULL,
        FOREIGN KEY(session_id) REFERENCES surveillance_sessions(id) ON DELETE CASCADE,
        FOREIGN KEY(week_id) REFERENCES weekly_surveillance(id) ON DELETE SET NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS prediction_results (
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

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_records_session ON surveillance_records(session_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_records_week ON surveillance_records(week_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_records_timestamp ON surveillance_records(capture_timestamp)',
    );
  }

  Future<void> close() async {
    final Database? db = _db;
    _db = null;
    await db?.close();
  }

  Future<void> deleteAll() async {
    final Database db = await database;
    await db.delete('prediction_results');
    await db.delete('surveillance_records');
    await db.delete('surveillance_sessions');
    await db.delete('weekly_surveillance');
    await db.delete('users');
  }
}
