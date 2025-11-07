/// Completed activity data for export
class ActivityData {
  final String workoutName;
  final DateTime startTime;
  final DateTime endTime;
  final int durationSeconds;
  final int ftp;

  // Heart rate data
  final List<HeartRateDataPoint> heartRateData;
  final int avgHeartRate;
  final int maxHeartRate;

  // Power data (estimated/manual)
  final List<PowerDataPoint> powerData;
  final double avgPower;
  final double maxPower;
  final double normalizedPower;

  // Cadence data (target values)
  final List<CadenceDataPoint> cadenceData;
  final int avgCadence;
  final int maxCadence;

  // Metrics
  final double tss;
  final double intensityFactor;
  final double kilojoules;

  ActivityData({
    required this.workoutName,
    required this.startTime,
    required this.endTime,
    required this.durationSeconds,
    required this.ftp,
    required this.heartRateData,
    required this.avgHeartRate,
    required this.maxHeartRate,
    required this.powerData,
    required this.avgPower,
    required this.maxPower,
    required this.normalizedPower,
    required this.cadenceData,
    required this.avgCadence,
    required this.maxCadence,
    required this.tss,
    required this.intensityFactor,
    required this.kilojoules,
  });

  // Format duration as HH:MM:SS
  String get formattedDuration {
    final duration = Duration(seconds: durationSeconds);
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '${hours}h ${minutes}m ${seconds}s';
    }
    return '${minutes}m ${seconds}s';
  }

  Map<String, dynamic> toJson() => {
    'workoutName': workoutName,
    'startTime': startTime.toIso8601String(),
    'endTime': endTime.toIso8601String(),
    'durationSeconds': durationSeconds,
    'ftp': ftp,
    'heartRateData': heartRateData.map((d) => d.toJson()).toList(),
    'avgHeartRate': avgHeartRate,
    'maxHeartRate': maxHeartRate,
    'powerData': powerData.map((d) => d.toJson()).toList(),
    'avgPower': avgPower,
    'maxPower': maxPower,
    'normalizedPower': normalizedPower,
    'cadenceData': cadenceData.map((d) => d.toJson()).toList(),
    'avgCadence': avgCadence,
    'maxCadence': maxCadence,
    'tss': tss,
    'intensityFactor': intensityFactor,
    'kilojoules': kilojoules,
  };
}

/// Heart rate data point
class HeartRateDataPoint {
  final int timestamp;  // seconds from start
  final int bpm;

  HeartRateDataPoint(this.timestamp, this.bpm);

  Map<String, dynamic> toJson() => {
    'timestamp': timestamp,
    'bpm': bpm,
  };
}

/// Power data point
class PowerDataPoint {
  final int timestamp;  // seconds from start
  final double watts;   // target power

  PowerDataPoint(this.timestamp, this.watts);

  Map<String, dynamic> toJson() => {
    'timestamp': timestamp,
    'watts': watts,
  };
}

/// Cadence data point
class CadenceDataPoint {
  final int timestamp;  // seconds from start
  final int rpm;        // target cadence

  CadenceDataPoint(this.timestamp, this.rpm);

  Map<String, dynamic> toJson() => {
    'timestamp': timestamp,
    'rpm': rpm,
  };
}
