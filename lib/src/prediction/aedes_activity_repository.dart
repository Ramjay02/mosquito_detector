import '../data/app_database.dart';
import 'aedes_logistic_predictor.dart';

class WeeklyActivity {
  const WeeklyActivity({
    required this.weekStart,
    required this.positiveDays,
    required this.observedDays,
  });

  final DateTime weekStart;
  final int positiveDays;
  final int observedDays;
  double get positivity => positiveDays / observedDays;
}

class BarangayPrediction {
  const BarangayPrediction({
    required this.barangay,
    required this.currentWeekStart,
    required this.weeks,
    required this.prediction,
  });

  final String barangay;
  final DateTime currentWeekStart;

  /// Oldest to newest: Lag_4, Lag_3, Lag_2, Lag_1, Current_Activity.
  final List<WeeklyActivity> weeks;
  final AedesPrediction prediction;

  List<double> get modelInputs => [
    weeks[3].positivity, // Lag_1
    weeks[2].positivity, // Lag_2
    weeks[1].positivity, // Lag_3
    weeks[0].positivity, // Lag_4
    weeks[4].positivity, // Current_Activity
  ];
}

/// Computes weekly positivity from saved classified scan records.
/// A calendar date is positive when at least one AG (Aedes aegypti) record
/// exists on that date. A date is observed when at least one processed record
/// exists for that barangay on that date.
class AedesActivityRepository {
  AedesActivityRepository({AppDatabase? appDatabase, required this.predictor})
    : _appDatabase = appDatabase ?? AppDatabase.instance;

  final AppDatabase _appDatabase;
  final AedesLogisticPredictor predictor;

  Future<void> ensurePredictionTable() async {
    final db = await _appDatabase.database;
    await db.execute('''
      CREATE TABLE IF NOT EXISTS aedes_direction_predictions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        barangay TEXT NOT NULL,
        current_week_start TEXT NOT NULL,
        lag_1 REAL NOT NULL,
        lag_2 REAL NOT NULL,
        lag_3 REAL NOT NULL,
        lag_4 REAL NOT NULL,
        current_activity REAL NOT NULL,
        probability_increase REAL NOT NULL,
        probability_decrease REAL NOT NULL,
        predicted_class INTEGER NOT NULL,
        model_version TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_aedes_predictions_barangay
      ON aedes_direction_predictions(barangay, current_week_start)
    ''');
  }

  DateTime _monday(DateTime date) {
    final day = DateTime(date.year, date.month, date.day);
    return day.subtract(Duration(days: day.weekday - DateTime.monday));
  }

  Future<bool> hasObservationsForBarangay(
    String barangay, {
    DateTime? referenceDate,
  }) async {
    final db = await _appDatabase.database;
    final currentStart = _monday(referenceDate ?? DateTime.now());
    final firstStart = currentStart.subtract(const Duration(days: 28));
    final endExclusive = currentStart.add(const Duration(days: 7));
    final rows = await db.rawQuery(
      '''
      SELECT 1
      FROM surveillance_records
      WHERE barangay = ?
        AND processing_status = 'processed'
        AND capture_timestamp >= ?
        AND capture_timestamp < ?
      LIMIT 1
    ''',
      [barangay, firstStart.toIso8601String(), endExclusive.toIso8601String()],
    );
    return rows.isNotEmpty;
  }

  Future<BarangayPrediction?> predictForBarangay(
    String barangay, {
    DateTime? referenceDate,
    bool saveResult = true,
  }) async {
    await ensurePredictionTable();
    final db = await _appDatabase.database;
    final currentStart = _monday(referenceDate ?? DateTime.now());
    final firstStart = currentStart.subtract(const Duration(days: 28));
    final endExclusive = currentStart.add(const Duration(days: 7));

    final rows = await db.rawQuery(
      '''
      SELECT capture_timestamp, species_code
      FROM surveillance_records
      WHERE barangay = ?
        AND processing_status = 'processed'
        AND capture_timestamp >= ?
        AND capture_timestamp < ?
      ORDER BY capture_timestamp ASC
    ''',
      [barangay, firstStart.toIso8601String(), endExclusive.toIso8601String()],
    );

    final Map<DateTime, bool> daily = {};
    for (final row in rows) {
      final timestamp = DateTime.parse(row['capture_timestamp'] as String);
      final date = DateTime(timestamp.year, timestamp.month, timestamp.day);
      final isAedesAegypti = row['species_code'] == 'AG';
      daily[date] = (daily[date] ?? false) || isAedesAegypti;
    }

    final List<WeeklyActivity> weeks = [];
    for (var offset = 0; offset < 5; offset++) {
      final start = firstStart.add(Duration(days: 7 * offset));
      var observed = 0;
      var positive = 0;
      for (var day = 0; day < 7; day++) {
        final date = start.add(Duration(days: day));
        if (daily.containsKey(date)) {
          observed++;
          if (daily[date] == true) positive++;
        }
      }
      // A week with zero observations is missing, not zero activity.
      if (observed == 0) return null;
      weeks.add(
        WeeklyActivity(
          weekStart: start,
          positiveDays: positive,
          observedDays: observed,
        ),
      );
    }

    // Preserve feature order expected by the trained Python model.
    final inputs = <double>[
      weeks[3].positivity,
      weeks[2].positivity,
      weeks[1].positivity,
      weeks[0].positivity,
      weeks[4].positivity,
    ];
    final prediction = predictor.predict(inputs);
    final result = BarangayPrediction(
      barangay: barangay,
      currentWeekStart: currentStart,
      weeks: weeks,
      prediction: prediction,
    );

    if (saveResult) {
      await db.insert('aedes_direction_predictions', {
        'barangay': barangay,
        'current_week_start': currentStart.toIso8601String(),
        'lag_1': inputs[0],
        'lag_2': inputs[1],
        'lag_3': inputs[2],
        'lag_4': inputs[3],
        'current_activity': inputs[4],
        'probability_increase': prediction.probabilityIncrease,
        'probability_decrease': prediction.probabilityDecrease,
        'predicted_class': prediction.predictedClass,
        'model_version': 'logistic-regression-v1',
        'created_at': DateTime.now().toIso8601String(),
      });
    }
    return result;
  }

  Future<List<Map<String, Object?>>> predictionHistory(String barangay) async {
    await ensurePredictionTable();
    final db = await _appDatabase.database;
    return db.query(
      'aedes_direction_predictions',
      where: 'barangay = ?',
      whereArgs: [barangay],
      orderBy: 'created_at DESC',
      limit: 30,
    );
  }
}
