import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'app_database.dart';
import 'models.dart';

class IsoWeek {
  const IsoWeek({
    required this.year,
    required this.weekNumber,
    required this.start,
    required this.end,
  });

  final int year;
  final int weekNumber;
  final DateTime start;
  final DateTime end;
}

typedef ImageFileStore = Future<String> Function(Uint8List, DateTime, String);

Future<Uint8List> resizePhotoForStorage(Uint8List bytes) =>
    compute(_resizePhotoToJpeg, bytes);

Uint8List _resizePhotoToJpeg(Uint8List bytes) {
  final img.Image? decoded = img.decodeImage(bytes);
  if (decoded == null) {
    throw const FormatException('Unable to decode captured image');
  }

  final img.Image oriented = img.bakeOrientation(decoded);
  final int longestSide = math.max(oriented.width, oriented.height);
  final double scale = math.min(1, 1280 / longestSide);
  final int width = math.max(1, (oriented.width * scale).round());
  final int height = math.max(1, (oriented.height * scale).round());
  final img.Image resized = width == oriented.width && height == oriented.height
      ? oriented
      : img.copyResize(oriented, width: width, height: height);
  return Uint8List.fromList(img.encodeJpg(resized, quality: 90));
}

class SurveillanceRepository {
  SurveillanceRepository({
    AppDatabase? db,
    ImageFileStore? store,
    this.recordsDirectoryPathOverride,
  }) : _db = db ?? AppDatabase.instance,
       _store =
           store ??
           ((Uint8List bytes, DateTime capturedAt, String speciesCode) =>
               storeImageFile(
                 bytes,
                 capturedAt,
                 speciesCode,
                 recordsDirectoryPathOverride: recordsDirectoryPathOverride,
               ));

  final AppDatabase _db;
  final ImageFileStore _store;
  final String? recordsDirectoryPathOverride;

  static Future<String> storeImageFile(
    Uint8List bytes,
    DateTime capturedAt,
    String speciesCode, {
    String? recordsDirectoryPathOverride,
  }) async {
    final Directory dir;
    if (recordsDirectoryPathOverride != null) {
      dir = Directory(recordsDirectoryPathOverride);
    } else {
      final Directory base = await getApplicationDocumentsDirectory();
      dir = Directory(p.join(base.path, 'wayawaya', 'records'));
    }
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final String timestamp = DateFormat('yyyyMMdd_HHmmss').format(capturedAt);
    final String name = '${timestamp}_$speciesCode.jpg';
    final File file = File(p.join(dir.path, name));
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  static IsoWeek isoWeekFor(DateTime date) {
    final DateTime day = DateTime(date.year, date.month, date.day);
    final int weekday = day.weekday;
    final DateTime thursday = day.add(Duration(days: 4 - weekday));
    final int isoYear = thursday.year;
    final DateTime jan1 = DateTime(isoYear, 1, 1);
    final int weekNumber = ((thursday.difference(jan1).inDays) / 7).floor() + 1;
    final DateTime start = day.subtract(Duration(days: weekday - 1));
    final DateTime end = start.add(const Duration(days: 6));
    return IsoWeek(
      year: isoYear,
      weekNumber: weekNumber,
      start: start,
      end: end,
    );
  }

  Future<int> ensureLocalUser({
    String username = 'field_worker',
    String fullName = 'Field Worker',
    String role = AppUser.roleFieldWorker,
  }) async {
    final Database db = await _db.database;
    final List<Map<String, Object?>> rows = await db.query(
      'users',
      columns: <String>['id'],
      where: 'username = ?',
      whereArgs: <Object?>[username],
      limit: 1,
    );
    if (rows.isNotEmpty) {
      return rows.first['id'] as int;
    }
    return db.insert(
      'users',
      AppUser(
        username: username,
        fullName: fullName,
        role: role,
        createdAt: DateTime.now(),
      ).toMap(),
    );
  }

  Future<String> persistImage(
    Uint8List bytes,
    DateTime capturedAt,
    String speciesCode,
  ) async {
    Uint8List storedBytes;
    try {
      storedBytes = await resizePhotoForStorage(bytes);
    } catch (error) {
      debugPrint('Photo re-encoding failed; saving original bytes: $error');
      storedBytes = bytes;
    }
    return _store(storedBytes, capturedAt, speciesCode);
  }

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
    final Map<String, int> speciesCounts = _countsForSpecies(speciesCode);
    final Database db = await _db.database;
    final String imagePath = await persistImage(
      imageBytes,
      capturedAt,
      speciesCode,
    );
    final IsoWeek week = isoWeekFor(capturedAt);
    final DateTime now = DateTime.now();

    return db.transaction<SurveillanceRecord>((Transaction txn) async {
      final int sessionId = await txn.insert(
        'surveillance_sessions',
        SurveillanceSession(
          userId: userId,
          barangay: barangay,
          startedAt: capturedAt,
          endedAt: capturedAt,
          notes: notes,
        ).toMap(),
      );

      final int weekId = await _upsertWeekly(
        txn,
        week,
        now,
        barangay,
        speciesCode,
      );

      final SurveillanceRecord record = SurveillanceRecord(
        sessionId: sessionId,
        weekId: weekId,
        imagePath: imagePath,
        barangay: barangay,
        captureTimestamp: capturedAt,
        speciesCode: speciesCode,
        aedesAlbopictusCount: speciesCounts['aedes_albopictus_count']!,
        aedesAegyptiCount: speciesCounts['aedes_aegypti_count']!,
        culexCount: speciesCounts['culex_count']!,
        anophelesCount: speciesCounts['anopheles_count']!,
        totalDetections: 1,
        avgConfidence: avgConfidence,
        processingStatus: processingStatus,
        createdAt: now,
      );

      final int recordId = await txn.insert(
        'surveillance_records',
        record.toMap(),
      );

      return SurveillanceRecord(
        id: recordId,
        sessionId: sessionId,
        weekId: weekId,
        imagePath: imagePath,
        barangay: barangay,
        captureTimestamp: capturedAt,
        speciesCode: speciesCode,
        aedesAlbopictusCount: speciesCounts['aedes_albopictus_count']!,
        aedesAegyptiCount: speciesCounts['aedes_aegypti_count']!,
        culexCount: speciesCounts['culex_count']!,
        anophelesCount: speciesCounts['anopheles_count']!,
        totalDetections: 1,
        avgConfidence: avgConfidence,
        processingStatus: processingStatus,
        createdAt: now,
      );
    });
  }

  Future<int> _upsertWeekly(
    Transaction txn,
    IsoWeek week,
    DateTime now,
    String barangay,
    String speciesCode,
  ) async {
    final Map<String, int> speciesCounts = _countsForSpecies(speciesCode);
    const List<String> countColumns = <String>[
      'aedes_albopictus_count',
      'aedes_aegypti_count',
      'culex_count',
      'anopheles_count',
    ];
    final List<Map<String, Object?>> rows = await txn.query(
      'weekly_surveillance',
      columns: <String>['id', ...countColumns],
      where: 'year = ? AND week_number = ? AND barangay = ?',
      whereArgs: <Object?>[week.year, week.weekNumber, barangay],
      limit: 1,
    );
    if (rows.isEmpty) {
      return txn.insert(
        'weekly_surveillance',
        WeeklySurveillance(
          year: week.year,
          weekNumber: week.weekNumber,
          weekStart: week.start,
          weekEnd: week.end,
          barangay: barangay,
          aedesAlbopictusCount: speciesCounts['aedes_albopictus_count']!,
          aedesAegyptiCount: speciesCounts['aedes_aegypti_count']!,
          culexCount: speciesCounts['culex_count']!,
          anophelesCount: speciesCounts['anopheles_count']!,
          updatedAt: now,
        ).toMap(),
      );
    }
    final Map<String, Object?> row = rows.first;
    final int id = row['id'] as int;
    final Map<String, Object?> updates = <String, Object?>{
      'updated_at': now.toIso8601String(),
    };
    for (final String column in countColumns) {
      updates[column] = (row[column] as int) + speciesCounts[column]!;
    }
    await txn.update(
      'weekly_surveillance',
      updates,
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
    return id;
  }

  static Map<String, int> _countsForSpecies(String speciesCode) {
    switch (speciesCode) {
      case 'AB':
        return <String, int>{
          'aedes_albopictus_count': 1,
          'aedes_aegypti_count': 0,
          'culex_count': 0,
          'anopheles_count': 0,
        };
      case 'AG':
        return <String, int>{
          'aedes_albopictus_count': 0,
          'aedes_aegypti_count': 1,
          'culex_count': 0,
          'anopheles_count': 0,
        };
      case 'CQ':
        return <String, int>{
          'aedes_albopictus_count': 0,
          'aedes_aegypti_count': 0,
          'culex_count': 1,
          'anopheles_count': 0,
        };
      case 'AN':
        return <String, int>{
          'aedes_albopictus_count': 0,
          'aedes_aegypti_count': 0,
          'culex_count': 0,
          'anopheles_count': 1,
        };
      default:
        throw ArgumentError.value(
          speciesCode,
          'speciesCode',
          'Expected one of AB, AG, AN, CQ',
        );
    }
  }

  Future<List<SurveillanceRecord>> recentRecords({int limit = 100}) async {
    final Database db = await _db.database;
    final List<Map<String, Object?>> rows = await db.query(
      'surveillance_records',
      orderBy: 'capture_timestamp DESC, id DESC',
      limit: limit,
    );
    return rows.map(SurveillanceRecord.fromMap).toList();
  }

  Future<List<SurveillanceRecord>> getRecentRecords({int limit = 5}) async {
    if (limit < 0) {
      throw ArgumentError.value(limit, 'limit', 'Must not be negative');
    }
    final Database db = await _db.database;
    final List<Map<String, Object?>> rows = await db.query(
      'surveillance_records',
      orderBy: 'capture_timestamp DESC, id DESC',
      limit: limit,
    );
    return rows.map(SurveillanceRecord.fromMap).toList();
  }

  Future<int> recordCount() async {
    final Database db = await _db.database;
    final List<Map<String, Object?>> rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM surveillance_records',
    );
    return (rows.first['c'] as int?) ?? 0;
  }

  Future<List<WeeklySurveillance>> weeklySeries({int limit = 52}) async {
    final Database db = await _db.database;
    final List<Map<String, Object?>> rows = await db.query(
      'weekly_surveillance',
      orderBy: 'year ASC, week_number ASC, barangay ASC',
    );
    final List<WeeklySurveillance> all = rows
        .map(WeeklySurveillance.fromMap)
        .toList();
    if (all.length <= limit) {
      return all;
    }
    return all.sublist(all.length - limit);
  }

  Future<WeeklySurveillance?> latestWeek() async {
    final Database db = await _db.database;
    final List<Map<String, Object?>> rows = await db.query(
      'weekly_surveillance',
      orderBy: 'year DESC, week_number DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : WeeklySurveillance.fromMap(rows.first);
  }

  Future<void> savePrediction(PredictionResult result) async {
    final Database db = await _db.database;
    await db.insert('prediction_results', result.toMap());
  }

  Future<PredictionResult?> latestPrediction() async {
    final Database db = await _db.database;
    final List<Map<String, Object?>> rows = await db.query(
      'prediction_results',
      orderBy: 'created_at DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : PredictionResult.fromMap(rows.first);
  }
}
