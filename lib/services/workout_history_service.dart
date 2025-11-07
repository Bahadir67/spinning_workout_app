import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/activity_data.dart';

/// Service for managing workout history
class WorkoutHistoryService {
  static const String HISTORY_KEY = 'workout_history';
  static const int MAX_HISTORY_ITEMS = 100;

  /// Save completed workout to history
  Future<void> saveWorkout(ActivityData activity) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final historyJson = prefs.getString(HISTORY_KEY);

      List<Map<String, dynamic>> history = [];
      if (historyJson != null) {
        final decoded = jsonDecode(historyJson) as List;
        history = decoded.map((e) => e as Map<String, dynamic>).toList();
      }

      // Add new workout at the beginning
      history.insert(0, activity.toJson());

      // Limit history size
      if (history.length > MAX_HISTORY_ITEMS) {
        history = history.sublist(0, MAX_HISTORY_ITEMS);
      }

      // Save back to prefs
      await prefs.setString(HISTORY_KEY, jsonEncode(history));
    } catch (e) {
      print('Error saving workout history: $e');
    }
  }

  /// Get all workout history
  Future<List<ActivityData>> getHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final historyJson = prefs.getString(HISTORY_KEY);

      if (historyJson == null) {
        return [];
      }

      final decoded = jsonDecode(historyJson) as List;
      return decoded.map((json) => ActivityData.fromJson(json)).toList();
    } catch (e) {
      print('Error loading workout history: $e');
      return [];
    }
  }

  /// Delete a workout from history
  Future<void> deleteWorkout(String workoutId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final historyJson = prefs.getString(HISTORY_KEY);

      if (historyJson == null) return;

      final decoded = jsonDecode(historyJson) as List;
      List<Map<String, dynamic>> history = decoded.map((e) => e as Map<String, dynamic>).toList();

      // Remove workout with matching start time (used as ID)
      history.removeWhere((item) {
        final startTime = DateTime.parse(item['startTime']);
        return startTime.toIso8601String() == workoutId;
      });

      await prefs.setString(HISTORY_KEY, jsonEncode(history));
    } catch (e) {
      print('Error deleting workout: $e');
    }
  }

  /// Clear all history
  Future<void> clearHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(HISTORY_KEY);
    } catch (e) {
      print('Error clearing history: $e');
    }
  }

  /// Get statistics
  Future<Map<String, dynamic>> getStatistics() async {
    final history = await getHistory();

    if (history.isEmpty) {
      return {
        'totalWorkouts': 0,
        'totalDuration': 0,
        'totalKilojoules': 0.0,
        'avgPower': 0.0,
        'avgHeartRate': 0,
      };
    }

    int totalDuration = 0;
    double totalKilojoules = 0.0;
    double totalAvgPower = 0.0;
    int totalAvgHR = 0;

    for (var activity in history) {
      totalDuration += activity.durationSeconds;
      totalKilojoules += activity.kilojoules;
      totalAvgPower += activity.avgPower;
      totalAvgHR += activity.avgHeartRate;
    }

    return {
      'totalWorkouts': history.length,
      'totalDuration': totalDuration,
      'totalKilojoules': totalKilojoules,
      'avgPower': totalAvgPower / history.length,
      'avgHeartRate': totalAvgHR ~/ history.length,
    };
  }
}
