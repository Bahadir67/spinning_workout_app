import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:vibration/vibration.dart';
import 'package:audioplayers/audioplayers.dart';

/// Notification service for workout alerts
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  final AudioPlayer _audioPlayer = AudioPlayer();

  bool _initialized = false;

  /// Initialize notification service
  Future<void> initialize() async {
    if (_initialized) return;

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestSoundPermission: true,
      requestBadgePermission: true,
      requestAlertPermission: true,
    );

    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notifications.initialize(settings);
    _initialized = true;
  }

  /// Show notification
  Future<void> showNotification({
    required String title,
    required String body,
    bool playSound = true,
    bool vibrate = true,
  }) async {
    if (!_initialized) await initialize();

    // Vibrate if supported
    if (vibrate && await Vibration.hasVibrator() == true) {
      Vibration.vibrate(duration: 500, amplitude: 128);
    }

    // Play sound
    if (playSound) {
      try {
        // You can use a custom sound file from assets
        // For now, using system notification sound
        await _audioPlayer.play(AssetSource('sounds/notification.mp3'));
      } catch (e) {
        print('Sound play error: $e');
      }
    }

    // Show notification
    const androidDetails = AndroidNotificationDetails(
      'workout_channel',
      'Workout Notifications',
      channelDescription: 'Notifications during workout',
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notifications.show(
      DateTime.now().millisecond,
      title,
      body,
      details,
    );
  }

  /// Notify interval start
  Future<void> notifyIntervalStart({
    required String intervalName,
    required int targetPower,
    required int targetCadence,
  }) async {
    await showNotification(
      title: 'Interval Start: $intervalName',
      body: 'Target: ${targetPower}W @ ${targetCadence} RPM',
      vibrate: true,
      playSound: true,
    );
  }

  /// Notify interval change
  Future<void> notifyIntervalChange({
    required String fromInterval,
    required String toInterval,
    required int targetPower,
    required int targetCadence,
  }) async {
    await showNotification(
      title: 'Next: $toInterval',
      body: 'Target: ${targetPower}W @ ${targetCadence} RPM',
      vibrate: true,
      playSound: true,
    );
  }

  /// Notify workout complete
  Future<void> notifyWorkoutComplete() async {
    await showNotification(
      title: 'Workout Complete!',
      body: 'Great job! Check your summary.',
      vibrate: true,
      playSound: true,
    );

    // Longer vibration for completion
    if (await Vibration.hasVibrator() == true) {
      Vibration.vibrate(
        pattern: [0, 200, 100, 200, 100, 500],
        intensities: [0, 128, 0, 128, 0, 255],
      );
    }
  }

  /// Notify workout paused
  Future<void> notifyWorkoutPaused() async {
    await showNotification(
      title: 'Workout Paused',
      body: 'Take a break. Resume when ready.',
      vibrate: false,
      playSound: false,
    );
  }

  /// Simple vibration (for button presses, etc.)
  Future<void> hapticFeedback() async {
    if (await Vibration.hasVibrator() == true) {
      Vibration.vibrate(duration: 50);
    }
  }

  /// Dispose resources
  void dispose() {
    _audioPlayer.dispose();
  }
}
