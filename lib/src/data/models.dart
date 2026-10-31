class AppUser {
  AppUser({
    this.id,
    required this.username,
    required this.fullName,
    required this.role,
    required this.createdAt,
  });

  final int? id;
  final String username;
  final String fullName;
  final String role;
  final DateTime createdAt;

  static const String roleFieldWorker = 'field_worker';
  static const String roleHealthOfficial = 'health_official';
  static const String roleAdmin = 'admin';

  Map<String, Object?> toMap() => <String, Object?>{
    if (id != null) 'id': id,
    'username': username,
    'full_name': fullName,
    'role': role,
    'created_at': createdAt.toIso8601String(),
  };

  factory AppUser.fromMap(Map<String, Object?> map) => AppUser(
    id: map['id'] as int?,
    username: map['username'] as String,
    fullName: map['full_name'] as String,
    role: map['role'] as String,
    createdAt: DateTime.parse(map['created_at'] as String),
  );
}

class WeeklySurveillance {
  WeeklySurveillance({
    this.id,
    required this.year,
    required this.weekNumber,
    required this.weekStart,
    required this.weekEnd,
    required this.barangay,
    this.aedesAlbopictusCount = 0,
    this.aedesAegyptiCount = 0,
    this.culexCount = 0,
    this.anophelesCount = 0,
    required this.updatedAt,
  });

  final int? id;
  final int year;
  final int weekNumber;
  final DateTime weekStart;
  final DateTime weekEnd;
  final String barangay;
  final int aedesAlbopictusCount;
  final int aedesAegyptiCount;
  final int culexCount;
  final int anophelesCount;
  final DateTime updatedAt;

  int get totalCount =>
      aedesAlbopictusCount + aedesAegyptiCount + culexCount + anophelesCount;

  String get label => '$year - W${weekNumber.toString().padLeft(2, '0')}';

  WeeklySurveillance copyWith({
    int? aedesAlbopictusCount,
    int? aedesAegyptiCount,
    int? culexCount,
    int? anophelesCount,
    DateTime? updatedAt,
  }) {
    return WeeklySurveillance(
      id: id,
      year: year,
      weekNumber: weekNumber,
      weekStart: weekStart,
      weekEnd: weekEnd,
      barangay: barangay,
      aedesAlbopictusCount: aedesAlbopictusCount ?? this.aedesAlbopictusCount,
      aedesAegyptiCount: aedesAegyptiCount ?? this.aedesAegyptiCount,
      culexCount: culexCount ?? this.culexCount,
      anophelesCount: anophelesCount ?? this.anophelesCount,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toMap() => <String, Object?>{
    if (id != null) 'id': id,
    'year': year,
    'week_number': weekNumber,
    'week_start': weekStart.toIso8601String(),
    'week_end': weekEnd.toIso8601String(),
    'barangay': barangay,
    'aedes_albopictus_count': aedesAlbopictusCount,
    'aedes_aegypti_count': aedesAegyptiCount,
    'culex_count': culexCount,
    'anopheles_count': anophelesCount,
    'updated_at': updatedAt.toIso8601String(),
  };

  factory WeeklySurveillance.fromMap(Map<String, Object?> map) =>
      WeeklySurveillance(
        id: map['id'] as int?,
        year: map['year'] as int,
        weekNumber: map['week_number'] as int,
        weekStart: DateTime.parse(map['week_start'] as String),
        weekEnd: DateTime.parse(map['week_end'] as String),
        barangay: map['barangay'] as String,
        aedesAlbopictusCount: map['aedes_albopictus_count'] as int,
        aedesAegyptiCount: map['aedes_aegypti_count'] as int,
        culexCount: map['culex_count'] as int,
        anophelesCount: map['anopheles_count'] as int,
        updatedAt: DateTime.parse(map['updated_at'] as String),
      );
}

class SurveillanceSession {
  SurveillanceSession({
    this.id,
    this.userId,
    this.barangay,
    required this.startedAt,
    this.endedAt,
    this.notes,
  });

  final int? id;
  final int? userId;
  final String? barangay;
  final DateTime startedAt;
  final DateTime? endedAt;
  final String? notes;

  Map<String, Object?> toMap() => <String, Object?>{
    if (id != null) 'id': id,
    'user_id': userId,
    'barangay': barangay,
    'started_at': startedAt.toIso8601String(),
    'ended_at': endedAt?.toIso8601String(),
    'notes': notes,
  };

  factory SurveillanceSession.fromMap(Map<String, Object?> map) =>
      SurveillanceSession(
        id: map['id'] as int?,
        userId: map['user_id'] as int?,
        barangay: map['barangay'] as String?,
        startedAt: DateTime.parse(map['started_at'] as String),
        endedAt: map['ended_at'] == null
            ? null
            : DateTime.parse(map['ended_at'] as String),
        notes: map['notes'] as String?,
      );
}

class SurveillanceRecord {
  SurveillanceRecord({
    this.id,
    required this.sessionId,
    this.weekId,
    required this.imagePath,
    required this.barangay,
    required this.captureTimestamp,
    this.aedesAlbopictusCount = 0,
    this.aedesAegyptiCount = 0,
    this.culexCount = 0,
    this.anophelesCount = 0,
    required this.speciesCode,
    this.totalDetections = 0,
    this.avgConfidence,
    this.processingStatus = 'processed',
    required this.createdAt,
  });

  final int? id;
  final int sessionId;
  final int? weekId;
  final String imagePath;
  final String barangay;
  final DateTime captureTimestamp;
  final int aedesAlbopictusCount;
  final int aedesAegyptiCount;
  final int culexCount;
  final int anophelesCount;
  final String speciesCode;
  final int totalDetections;
  final double? avgConfidence;
  final String processingStatus;
  final DateTime createdAt;

  int get totalClassified =>
      aedesAlbopictusCount + aedesAegyptiCount + culexCount + anophelesCount;

  Map<String, Object?> toMap() => <String, Object?>{
    if (id != null) 'id': id,
    'session_id': sessionId,
    'week_id': weekId,
    'image_path': imagePath,
    'barangay': barangay,
    'capture_timestamp': captureTimestamp.toIso8601String(),
    'species_code': speciesCode,
    'aedes_albopictus_count': aedesAlbopictusCount,
    'aedes_aegypti_count': aedesAegyptiCount,
    'culex_count': culexCount,
    'anopheles_count': anophelesCount,
    'total_detections': totalDetections,
    'avg_confidence': avgConfidence,
    'processing_status': processingStatus,
    'created_at': createdAt.toIso8601String(),
  };

  factory SurveillanceRecord.fromMap(Map<String, Object?> map) =>
      SurveillanceRecord(
        id: map['id'] as int?,
        sessionId: map['session_id'] as int,
        weekId: map['week_id'] as int?,
        imagePath: map['image_path'] as String,
        barangay: map['barangay'] as String,
        captureTimestamp: DateTime.parse(map['capture_timestamp'] as String),
        aedesAlbopictusCount: map['aedes_albopictus_count'] as int,
        aedesAegyptiCount: map['aedes_aegypti_count'] as int,
        culexCount: map['culex_count'] as int,
        anophelesCount: map['anopheles_count'] as int,
        speciesCode: map['species_code'] as String,
        totalDetections: map['total_detections'] as int,
        avgConfidence: (map['avg_confidence'] as num?)?.toDouble(),
        processingStatus: map['processing_status'] as String,
        createdAt: DateTime.parse(map['created_at'] as String),
      );
}

class PredictionResult {
  PredictionResult({
    this.id,
    this.weekId,
    this.trainingStart,
    this.trainingEnd,
    required this.latestObserved,
    required this.predictedCount,
    required this.predictedChange,
    required this.increaseLikely,
    required this.createdAt,
  });

  final int? id;
  final int? weekId;
  final DateTime? trainingStart;
  final DateTime? trainingEnd;
  final int latestObserved;
  final double predictedCount;
  final double predictedChange;
  final bool increaseLikely;
  final DateTime createdAt;

  Map<String, Object?> toMap() => <String, Object?>{
    if (id != null) 'id': id,
    'week_id': weekId,
    'training_start': trainingStart?.toIso8601String(),
    'training_end': trainingEnd?.toIso8601String(),
    'latest_observed': latestObserved,
    'predicted_count': predictedCount,
    'predicted_change': predictedChange,
    'increase_likely': increaseLikely ? 1 : 0,
    'created_at': createdAt.toIso8601String(),
  };

  factory PredictionResult.fromMap(Map<String, Object?> map) =>
      PredictionResult(
        id: map['id'] as int?,
        weekId: map['week_id'] as int?,
        trainingStart: map['training_start'] == null
            ? null
            : DateTime.parse(map['training_start'] as String),
        trainingEnd: map['training_end'] == null
            ? null
            : DateTime.parse(map['training_end'] as String),
        latestObserved: map['latest_observed'] as int,
        predictedCount: (map['predicted_count'] as num).toDouble(),
        predictedChange: (map['predicted_change'] as num).toDouble(),
        increaseLikely: (map['increase_likely'] as int) == 1,
        createdAt: DateTime.parse(map['created_at'] as String),
      );
}
