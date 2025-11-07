import 'package:flutter/material.dart';

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
  final DateTime timestamp;

  CoachMessage({
    required this.message,
    required this.type,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

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
