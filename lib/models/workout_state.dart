import 'dart:convert';
import 'workout.dart';
import 'activity_data.dart';

/// Saved HR point (to avoid name conflict with workout.dart)
class SavedHRPoint {
  final int seconds;
  final int bpm;

  SavedHRPoint(this.seconds, this.bpm);

  Map<String, dynamic> toJson() => {'seconds': seconds, 'bpm': bpm};

  factory SavedHRPoint.fromJson(Map<String, dynamic> json) {
    return SavedHRPoint(json['seconds'], json['bpm']);
  }
}

/// Antrenman durumunu kaydetmek için model
class WorkoutState {
  final Workout workout;
  final int elapsedSeconds;
  final DateTime startTime;
  final List<SavedHRPoint> hrHistory;
  final bool isPaused;
  final DateTime saveTime;

  WorkoutState({
    required this.workout,
    required this.elapsedSeconds,
    required this.startTime,
    required this.hrHistory,
    required this.isPaused,
    required this.saveTime,
  });

  /// JSON'a dönüştür
  Map<String, dynamic> toJson() {
    return {
      'workout': workout.toJson(),
      'elapsedSeconds': elapsedSeconds,
      'startTime': startTime.toIso8601String(),
      'hrHistory': hrHistory.map((h) => h.toJson()).toList(),
      'isPaused': isPaused,
      'saveTime': saveTime.toIso8601String(),
    };
  }

  /// JSON'dan oluştur
  factory WorkoutState.fromJson(Map<String, dynamic> json) {
    return WorkoutState(
      workout: Workout.fromJson(json['workout']),
      elapsedSeconds: json['elapsedSeconds'],
      startTime: DateTime.parse(json['startTime']),
      hrHistory: (json['hrHistory'] as List)
          .map((h) => SavedHRPoint.fromJson(h))
          .toList(),
      isPaused: json['isPaused'],
      saveTime: DateTime.parse(json['saveTime']),
    );
  }

  /// String'e dönüştür (SharedPreferences için)
  String toJsonString() {
    return jsonEncode(toJson());
  }

  /// String'den oluştur
  static WorkoutState? fromJsonString(String jsonString) {
    try {
      final json = jsonDecode(jsonString);
      return WorkoutState.fromJson(json);
    } catch (e) {
      print('WorkoutState parse error: $e');
      return null;
    }
  }

  /// Durumun geçerli olup olmadığını kontrol et
  /// (Örn: 24 saatten eski kayıtları reddet)
  bool isValid() {
    final now = DateTime.now();
    final diff = now.difference(saveTime);
    return diff.inHours < 24; // 24 saat içinde kaydedilmiş olmalı
  }
}

