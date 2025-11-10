import 'dart:convert';

/// Workout segment types
enum SegmentType {
  warmup,
  steadyState,
  interval,
  cooldown,
  freeRide,
}

/// Workout type based on dominant zone
enum WorkoutType {
  recovery,    // <55% FTP dominant
  endurance,   // 55-75% FTP (Z2)
  tempo,       // 76-90% FTP
  sweetSpot,   // 88-94% FTP
  threshold,   // 91-105% FTP
  vo2max,      // >106% FTP
  mixed,       // No single dominant zone
}

/// Single workout segment
class WorkoutSegment {
  final SegmentType type;
  final int durationSeconds;
  final double powerLow;   // % of FTP (0.0 - 2.0)
  final double powerHigh;  // % of FTP (0.0 - 2.0)
  final int cadence;       // Target RPM
  final String? name;

  // For intervals
  final int? repeatCount;
  final int? onDuration;
  final int? offDuration;
  final double? onPower;
  final double? offPower;

  WorkoutSegment({
    required this.type,
    required this.durationSeconds,
    required this.powerLow,
    required this.powerHigh,
    required this.cadence,
    this.name,
    this.repeatCount,
    this.onDuration,
    this.offDuration,
    this.onPower,
    this.offPower,
  });

  // Get color based on power zone
  int getZoneColor() {
    final avgPower = (powerLow + powerHigh) / 2;

    if (avgPower < 0.55) return 0xFF9E9E9E;      // Gray - Recovery
    if (avgPower < 0.75) return 0xFF2196F3;      // Blue - Endurance
    if (avgPower < 0.90) return 0xFF4CAF50;      // Green - Tempo
    if (avgPower < 1.05) return 0xFFFFC107;      // Yellow - Threshold
    return 0xFFFF5722;                            // Orange - VO2Max
  }

  // Get zone name
  String getZoneName() {
    final avgPower = (powerLow + powerHigh) / 2;

    if (avgPower < 0.55) return 'Recovery';
    if (avgPower < 0.75) return 'Endurance';
    if (avgPower < 0.90) return 'Tempo';
    if (avgPower < 1.05) return 'Threshold';
    return 'VO2Max';
  }

  Map<String, dynamic> toJson() => {
    'type': type.toString(),
    'durationSeconds': durationSeconds,
    'powerLow': powerLow,
    'powerHigh': powerHigh,
    'cadence': cadence,
    'name': name,
    'repeatCount': repeatCount,
    'onDuration': onDuration,
    'offDuration': offDuration,
    'onPower': onPower,
    'offPower': offPower,
  };

  factory WorkoutSegment.fromJson(Map<String, dynamic> json) {
    return WorkoutSegment(
      type: SegmentType.values.firstWhere(
        (e) => e.toString() == json['type'],
      ),
      durationSeconds: json['durationSeconds'],
      powerLow: json['powerLow'],
      powerHigh: json['powerHigh'],
      cadence: json['cadence'],
      name: json['name'],
      repeatCount: json['repeatCount'],
      onDuration: json['onDuration'],
      offDuration: json['offDuration'],
      onPower: json['onPower'],
      offPower: json['offPower'],
    );
  }
}

/// Complete workout
class Workout {
  final String id;
  final String name;
  final String author;
  final String description;
  final int ftp;                    // Functional Threshold Power (watts)
  final List<WorkoutSegment> segments;
  final DateTime createdAt;

  Workout({
    required this.id,
    required this.name,
    required this.author,
    required this.description,
    required this.ftp,
    required this.segments,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  // Total duration
  int get durationSeconds {
    return segments.fold(0, (sum, seg) {
      if (seg.type == SegmentType.interval && seg.repeatCount != null) {
        return sum + (seg.onDuration! + seg.offDuration!) * seg.repeatCount!;
      }
      return sum + seg.durationSeconds;
    });
  }

  // Average power (watts)
  double getAveragePower() {
    double totalPowerTime = 0;
    int totalTime = 0;

    for (var segment in segments) {
      final avgPower = (segment.powerLow + segment.powerHigh) / 2;
      final duration = segment.durationSeconds;
      totalPowerTime += (avgPower * ftp * duration);
      totalTime += duration;
    }

    return totalTime > 0 ? totalPowerTime / totalTime : 0;
  }

  // Training Stress Score
  double calculateTSS() {
    final np = calculateNP();
    final duration = durationSeconds / 3600.0; // hours
    final intensity = np / ftp;
    return (duration * np * intensity / ftp) * 100;
  }

  // Intensity Factor
  double calculateIF() {
    return calculateNP() / ftp;
  }

  // Normalized Power (simplified)
  double calculateNP() {
    return getAveragePower();
  }

  // Kilojoules
  double calculateKilojoules() {
    return getAveragePower() * durationSeconds / 1000;
  }

  /// Detect workout type based on time-weighted zone analysis
  WorkoutType detectWorkoutType() {
    // Calculate time spent in each zone
    final Map<WorkoutType, int> zoneTime = {
      WorkoutType.recovery: 0,
      WorkoutType.endurance: 0,
      WorkoutType.tempo: 0,
      WorkoutType.sweetSpot: 0,
      WorkoutType.threshold: 0,
      WorkoutType.vo2max: 0,
    };

    for (var segment in segments) {
      // Skip warmup/cooldown for type detection
      if (segment.type == SegmentType.warmup ||
          segment.type == SegmentType.cooldown) {
        continue;
      }

      final avgPowerPercent = ((segment.powerLow + segment.powerHigh) / 2) * 100;
      int duration = segment.durationSeconds;

      // For intervals, calculate total interval time
      if (segment.type == SegmentType.interval && segment.repeatCount != null) {
        duration = segment.onDuration! * segment.repeatCount!;
      }

      // Classify into zones
      if (avgPowerPercent < 55) {
        zoneTime[WorkoutType.recovery] = zoneTime[WorkoutType.recovery]! + duration;
      } else if (avgPowerPercent >= 88 && avgPowerPercent <= 94) {
        // Sweet Spot is specific range
        zoneTime[WorkoutType.sweetSpot] = zoneTime[WorkoutType.sweetSpot]! + duration;
      } else if (avgPowerPercent >= 55 && avgPowerPercent < 76) {
        zoneTime[WorkoutType.endurance] = zoneTime[WorkoutType.endurance]! + duration;
      } else if (avgPowerPercent >= 76 && avgPowerPercent < 91) {
        zoneTime[WorkoutType.tempo] = zoneTime[WorkoutType.tempo]! + duration;
      } else if (avgPowerPercent >= 91 && avgPowerPercent <= 105) {
        zoneTime[WorkoutType.threshold] = zoneTime[WorkoutType.threshold]! + duration;
      } else if (avgPowerPercent > 105) {
        zoneTime[WorkoutType.vo2max] = zoneTime[WorkoutType.vo2max]! + duration;
      }
    }

    // Find dominant zone (>50% of working time)
    final totalWorkTime = zoneTime.values.reduce((a, b) => a + b);
    if (totalWorkTime == 0) return WorkoutType.recovery;

    WorkoutType? dominantType;
    int maxTime = 0;

    zoneTime.forEach((type, time) {
      if (time > maxTime) {
        maxTime = time;
        dominantType = type;
      }
    });

    // Check if dominant (>50%)
    if (maxTime > totalWorkTime * 0.5) {
      return dominantType!;
    }

    return WorkoutType.mixed;
  }

  /// Get workout type name in Turkish
  String getWorkoutTypeName() {
    final type = detectWorkoutType();
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

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'author': author,
    'description': description,
    'ftp': ftp,
    'segments': segments.map((s) => s.toJson()).toList(),
    'createdAt': createdAt.toIso8601String(),
  };

  factory Workout.fromJson(Map<String, dynamic> json) {
    return Workout(
      id: json['id'],
      name: json['name'],
      author: json['author'],
      description: json['description'],
      ftp: json['ftp'],
      segments: (json['segments'] as List)
          .map((s) => WorkoutSegment.fromJson(s))
          .toList(),
      createdAt: DateTime.parse(json['createdAt']),
    );
  }
}

/// Heart rate point for graphing
class HeartRatePoint {
  final int seconds;
  final int bpm;

  HeartRatePoint(this.seconds, this.bpm);
}

/// Power point for graphing
class PowerPoint {
  final int seconds;
  final int watts;

  PowerPoint(this.seconds, this.watts);
}
