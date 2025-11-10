import 'package:flutter/material.dart';
import 'workout.dart';

/// AI Coach mesaj kategorileri
enum MessageCategory {
  technicalFeedback,  // Teknik + antrenman analizi (workout-aware)
  cyclingHistory,     // Bisiklet tarihçesi + enteresan bilgiler
  currentEvents,      // Güncel yarışlar + media + ünlü bisikletçiler
  motivation,         // Esprili motivasyon mesajları
}

/// AI Coach mesaj tipleri
enum CoachMessageType {
  motivation,      // Motivasyon mesajları
  performance,     // Performans analizi
  warning,         // Uyarılar
  information,     // Bilimsel bilgilendirme
  segmentStart,    // Segment başlangıç
  segmentEnd,      // Segment bitişi
}

/// Coach mesajı modeli
class CoachMessage {
  final String message;
  final CoachMessageType type;
  final MessageCategory? category;  // Mesaj kategorisi (AI için)
  final DateTime timestamp;

  CoachMessage({
    required this.message,
    required this.type,
    this.category,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  /// AI tarafından üretilmiş mi?
  bool get isAIGenerated => category != null;

  /// Mesaj tipine göre ikon
  IconData get icon {
    switch (type) {
      case CoachMessageType.motivation:
        return Icons.fitness_center;
      case CoachMessageType.performance:
        return Icons.analytics;
      case CoachMessageType.warning:
        return Icons.warning_amber;
      case CoachMessageType.information:
        return Icons.lightbulb_outline;
      case CoachMessageType.segmentStart:
        return Icons.play_circle_outline;
      case CoachMessageType.segmentEnd:
        return Icons.check_circle_outline;
    }
  }

  /// Mesaj tipine göre renk
  Color get color {
    switch (type) {
      case CoachMessageType.motivation:
        return Colors.green;
      case CoachMessageType.performance:
        return Colors.blue;
      case CoachMessageType.warning:
        return Colors.orange;
      case CoachMessageType.information:
        return Colors.purple;
      case CoachMessageType.segmentStart:
        return Colors.cyan;
      case CoachMessageType.segmentEnd:
        return Colors.teal;
    }
  }
}

/// Antrenman context'i - AI'ya gönderilecek bilgiler
class CoachContext {
  final int? currentHeartRate;
  final int? averageHeartRate;
  final int? maxHeartRate;
  final double currentPower;
  final double targetPower;
  final int currentCadence;
  final int targetCadence;
  final String segmentType;
  final String segmentName;
  final int elapsedSeconds;
  final int segmentDurationSeconds;
  final int segmentElapsedSeconds;
  final int ftp;

  CoachContext({
    this.currentHeartRate,
    this.averageHeartRate,
    this.maxHeartRate,
    required this.currentPower,
    required this.targetPower,
    required this.currentCadence,
    required this.targetCadence,
    required this.segmentType,
    required this.segmentName,
    required this.elapsedSeconds,
    required this.segmentDurationSeconds,
    required this.segmentElapsedSeconds,
    required this.ftp,
  });

  /// HR Zone hesapla (max HR'a göre)
  String? get hrZone {
    if (currentHeartRate == null || maxHeartRate == null) return null;
    final percentage = (currentHeartRate! / maxHeartRate!) * 100;
    if (percentage < 60) return 'Recovery';
    if (percentage < 70) return 'Endurance';
    if (percentage < 80) return 'Tempo';
    if (percentage < 90) return 'Threshold';
    return 'VO2 Max';
  }

  /// Power Zone hesapla (FTP'ye göre)
  String get powerZone {
    final percentage = (currentPower / ftp) * 100;
    if (percentage < 55) return 'Recovery';
    if (percentage < 75) return 'Endurance';
    if (percentage < 90) return 'Tempo';
    if (percentage < 105) return 'Threshold';
    return 'VO2 Max';
  }

  /// Segment ilerleme yüzdesi
  double get segmentProgress {
    return (segmentElapsedSeconds / segmentDurationSeconds).clamp(0.0, 1.0);
  }

  /// JSON formatına çevir (API için)
  Map<String, dynamic> toJson() {
    return {
      'currentHeartRate': currentHeartRate,
      'averageHeartRate': averageHeartRate,
      'maxHeartRate': maxHeartRate,
      'currentPower': currentPower,
      'targetPower': targetPower,
      'currentCadence': currentCadence,
      'targetCadence': targetCadence,
      'segmentType': segmentType,
      'segmentName': segmentName,
      'elapsedSeconds': elapsedSeconds,
      'segmentDurationSeconds': segmentDurationSeconds,
      'segmentElapsedSeconds': segmentElapsedSeconds,
      'ftp': ftp,
      'hrZone': hrZone,
      'powerZone': powerZone,
      'segmentProgress': segmentProgress,
    };
  }
}

/// Gerçek zamanlı workout metrikleri (AI için)
class WorkoutMetrics {
  final double currentPower;
  final double averagePower;
  final double currentCadence;
  final double averageCadence;
  final int? currentHeartRate;
  final int? averageHeartRate;
  final double normalizedPower;  // NP (30s rolling average)
  final double intensityFactor;  // IF = NP / FTP
  final int ftp;
  final WorkoutType workoutType;

  WorkoutMetrics({
    required this.currentPower,
    required this.averagePower,
    required this.currentCadence,
    required this.averageCadence,
    this.currentHeartRate,
    this.averageHeartRate,
    required this.normalizedPower,
    required this.intensityFactor,
    required this.ftp,
    required this.workoutType,
  });

  /// Factory constructor for real-time calculation
  factory WorkoutMetrics.calculate({
    required double currentPower,
    required double averagePower,
    required double currentCadence,
    required double averageCadence,
    int? currentHeartRate,
    int? averageHeartRate,
    required int ftp,
    required WorkoutType workoutType,
    List<double>? powerHistory,  // Last 30 seconds of power data
  }) {
    // Calculate Normalized Power (simplified 30s rolling average)
    double np = averagePower;  // Fallback
    if (powerHistory != null && powerHistory.isNotEmpty) {
      // Take last 30 samples (assuming 1 sample/second)
      final recent = powerHistory.length > 30
          ? powerHistory.sublist(powerHistory.length - 30)
          : powerHistory;

      // Simple rolling average (real NP needs 4th power calculation)
      np = recent.reduce((a, b) => a + b) / recent.length;
    }

    // Calculate Intensity Factor
    final intensityFactor = ftp > 0 ? np / ftp : 0.0;

    return WorkoutMetrics(
      currentPower: currentPower,
      averagePower: averagePower,
      currentCadence: currentCadence,
      averageCadence: averageCadence,
      currentHeartRate: currentHeartRate,
      averageHeartRate: averageHeartRate,
      normalizedPower: np,
      intensityFactor: intensityFactor,
      ftp: ftp,
      workoutType: workoutType,
    );
  }

  /// JSON for AI
  Map<String, dynamic> toJson() {
    return {
      'currentPower': currentPower.toStringAsFixed(0),
      'averagePower': averagePower.toStringAsFixed(0),
      'currentCadence': currentCadence.toStringAsFixed(0),
      'averageCadence': averageCadence.toStringAsFixed(0),
      'currentHeartRate': currentHeartRate,
      'averageHeartRate': averageHeartRate,
      'normalizedPower': normalizedPower.toStringAsFixed(0),
      'intensityFactor': intensityFactor.toStringAsFixed(2),
      'ftp': ftp,
      'workoutType': _workoutTypeToString(workoutType),
    };
  }

  String _workoutTypeToString(WorkoutType type) {
    switch (type) {
      case WorkoutType.recovery:
        return 'Recovery';
      case WorkoutType.endurance:
        return 'Endurance (Z2)';
      case WorkoutType.tempo:
        return 'Tempo';
      case WorkoutType.sweetSpot:
        return 'Sweet Spot';
      case WorkoutType.threshold:
        return 'Threshold';
      case WorkoutType.vo2max:
        return 'VO2 Max';
      case WorkoutType.mixed:
        return 'Mixed';
    }
  }
}
