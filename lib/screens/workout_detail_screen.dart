import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:screenshot/screenshot.dart';
import '../models/workout.dart';
import '../models/activity_data.dart';
import '../models/workout_state.dart' show WorkoutState, SavedHRPoint;
import '../models/coach_message.dart';
import '../services/bluetooth_service.dart';
import '../services/ai_coach_service.dart';
import '../widgets/coach_message_overlay.dart';
import 'workout_summary_screen.dart';
import 'sensor_connection_screen.dart';

class WorkoutDetailScreen extends StatefulWidget {
  final Workout workout;

  const WorkoutDetailScreen({super.key, required this.workout});

  @override
  State<WorkoutDetailScreen> createState() => _WorkoutDetailScreenState();
}

class _WorkoutDetailScreenState extends State<WorkoutDetailScreen> {
  // Antrenman durumu
  bool _isRunning = false;
  bool _isPaused = false;
  int _elapsedSeconds = 0;
  Timer? _timer;
  DateTime? _startTime;

  // HR verileri (Bluetooth'tan)
  int _currentHR = 0;
  List<HeartRatePoint> _hrHistory = [];
  final BluetoothService _bluetoothService = BluetoothService();
  StreamSubscription<int>? _hrSubscription;
  bool _isHRConnected = false;

  // Power verileri (Bluetooth'tan veya hedef değerler)
  int _currentPower = 0; // Gerçek power (sensörden)
  List<PowerPoint> _powerHistory = []; // Gerçek power history
  StreamSubscription<int>? _powerSubscription;
  bool _isPowerConnected = false;

  // Cadence verileri (Bluetooth'tan veya hedef değerler)
  int _currentCadence = 0; // Gerçek cadence (sensörden)
  StreamSubscription<int>? _cadenceSubscription;
  bool _isCadenceConnected = false;

  // Target değerler (segment'ten)
  double _currentTargetPower = 0;
  int _currentTargetCadence = 0;

  // TTS için
  final FlutterTts _tts = FlutterTts();
  int? _lastAnnouncedPower;
  int? _lastAnnouncedCadence;
  int _currentSegmentIndex = -1;
  int _currentSegmentRemainingSeconds = 0;

  // Audio player için beep sesi
  final AudioPlayer _audioPlayer = AudioPlayer();
  int _lastBeepSecond = -1; // Son beep çalınan saniye

  // Slide menu için
  bool _isMenuVisible = false;

  // Zoom için
  double _minX = 0;
  double _maxX = 0;
  double _chartWidth = 0;
  double _lastScale = 1.0;
  double _lastPanX = 0;

  // Screenshot için
  final ScreenshotController _screenshotController = ScreenshotController();

  // AI Coach
  final AICoachService _coachService = AICoachService();
  CoachMessage? _currentCoachMessage;
  int _lastCoachCheckSecond = -1;

  // WorkoutMetrics için
  WorkoutType? _workoutType;              // Workout tipi (başlangıçta tespit)
  List<double> _powerHistoryForNP = [];   // NP hesaplama için (30s rolling)
  double _averagePower = 0;               // Anlık average power
  double _averageCadence = 0;             // Anlık average cadence

  @override
  void initState() {
    super.initState();
    // Landscape modunu zorla
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    // Sistem UI'yi gizle (immersive mode)
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    // Ekranı açık tut
    WakelockPlus.enable();

    // Audio player ayarları (beep için)
    _setupAudioPlayer();

    // TTS ayarları
    _initTts();

    // AI Coach servisini başlat
    _coachService.initialize();

    // Zoom başlangıç değerleri
    _maxX = widget.workout.durationSeconds.toDouble();
    _chartWidth = _maxX;

    // Bluetooth HR sensörünü başlat
    _initBluetooth();

    // Kaydedilmiş durum kontrolü
    _checkSavedState();

    // AI Coach'ı başlat
    _coachService.initialize();

    // Workout tipini tespit et (AI için kritik!)
    _workoutType = widget.workout.detectWorkoutType();
  }

  /// Bluetooth sensörlerini başlat (HR, Power, Cadence)
  Future<void> _initBluetooth() async {
    // HR stream'ini dinle
    _hrSubscription = _bluetoothService.heartRateStream.listen((hr) {
      setState(() {
        _currentHR = hr;
        _isHRConnected = true;
      });
    });

    // Power stream'ini dinle
    _powerSubscription = _bluetoothService.powerStream.listen((watts) {
      setState(() {
        _currentPower = watts;
        _isPowerConnected = true;
      });
    });

    // Cadence stream'ini dinle
    _cadenceSubscription = _bluetoothService.cadenceStream.listen((rpm) {
      setState(() {
        _currentCadence = rpm;
        _isCadenceConnected = true;
      });
    });

    // Bağlantı durumlarını kontrol et
    setState(() {
      _isHRConnected = _bluetoothService.isHRConnected;
      _isPowerConnected = _bluetoothService.isPowerConnected;
      _isCadenceConnected = _bluetoothService.isCadenceConnected;
    });
  }

  /// Kaydedilmiş antrenman durumunu kontrol et
  Future<void> _checkSavedState() async {
    final prefs = await SharedPreferences.getInstance();
    final savedStateJson = prefs.getString('workout_state');

    if (savedStateJson != null) {
      final savedState = WorkoutState.fromJsonString(savedStateJson);

      if (savedState != null && savedState.isValid()) {
        // Aynı antrenmansa devam et dialog göster
        if (savedState.workout.id == widget.workout.id) {
          // Build tamamlandıktan sonra dialog göster
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _showResumeDialog(savedState);
            }
          });
        } else {
          // Farklı antrenman - eski kaydı temizle
          await _clearSavedState();
        }
      } else {
        // Geçersiz kayıt - temizle
        await _clearSavedState();
      }
    }
  }

  /// Devam et dialog'u göster
  Future<void> _showResumeDialog(WorkoutState savedState) async {
    final minutes = savedState.elapsedSeconds ~/ 60;
    final seconds = savedState.elapsedSeconds % 60;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Antrenman Devam Ettir'),
        content: Text(
          'Bu antrenman için kaydedilmiş ilerleme bulundu.\n\n'
          'Geçen süre: $minutes:${seconds.toString().padLeft(2, '0')}\n'
          'Kayıt zamanı: ${_formatDateTime(savedState.saveTime)}\n\n'
          'Kaldığınız yerden devam etmek ister misiniz?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Yeni Başla'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Devam Et'),
          ),
        ],
      ),
    );

    if (result == true) {
      // Kaydedilmiş durumu yükle
      _resumeWorkout(savedState);
    } else {
      // Yeni başla - kaydı temizle
      await _clearSavedState();
    }
  }

  /// Antrenmanı devam ettir
  void _resumeWorkout(WorkoutState savedState) {
    // SavedHRPoint'leri HeartRatePoint'e çevir
    final hrHistory = savedState.hrHistory
        .map((h) => HeartRatePoint(h.seconds, h.bpm))
        .toList();

    setState(() {
      _isRunning = true;
      _isPaused = savedState.isPaused;
      _elapsedSeconds = savedState.elapsedSeconds;
      _startTime = savedState.startTime;
      _hrHistory = hrHistory;
    });

    // Timer'ı başlat
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!_isPaused) {
        setState(() {
          _elapsedSeconds++;
          _updateCurrentTargets();
          _recordData();
        });

        // Durumu kaydet
        _saveWorkoutState();

        // AI Coach kontrolü
        _checkCoachMessage();

        // Antrenman bitti mi?
        if (_elapsedSeconds >= widget.workout.durationSeconds) {
          _finishWorkout();
        }
      }
    });
  }

  /// Antrenman durumunu kaydet
  Future<void> _saveWorkoutState() async {
    try {
      // HeartRatePoint'leri SavedHRPoint'e çevir
      final savedHRHistory = _hrHistory
          .map((h) => SavedHRPoint(h.seconds, h.bpm))
          .toList();

      final state = WorkoutState(
        workout: widget.workout,
        elapsedSeconds: _elapsedSeconds,
        startTime: _startTime!,
        hrHistory: savedHRHistory,
        isPaused: _isPaused,
        saveTime: DateTime.now(),
      );

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('workout_state', state.toJsonString());
    } catch (e) {
      print('Workout state kaydetme hatası: $e');
    }
  }

  /// Kaydedilmiş durumu temizle
  Future<void> _clearSavedState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('workout_state');
  }

  /// HR bağlı değilse uyarı dialogu göster
  Future<bool?> _showHRWarningDialog() async {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: const [
            Icon(Icons.warning, color: Colors.orange),
            SizedBox(width: 8),
            Text('HR Sensörü Bağlı Değil'),
          ],
        ),
        content: const Text(
          'Kalp atış hızı sensörü bağlı değil. Antrenman sırasında HR verisi kaydedilmeyecek.\n\n'
          'Yine de devam etmek istiyor musunuz?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('İptal'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context, false);
              // HR bağlama ekranına git
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const SensorConnectionScreen(),
                ),
              );
            },
            child: const Text('HR Bağla'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Devam Et'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
          ),
        ],
      ),
    );
  }

  /// Tarih formatla
  String _formatDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final diff = now.difference(dateTime);

    if (diff.inMinutes < 60) {
      return '${diff.inMinutes} dakika önce';
    } else if (diff.inHours < 24) {
      return '${diff.inHours} saat önce';
    } else {
      return '${dateTime.day}/${dateTime.month} ${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')}';
    }
  }

  /// Audio player'ı yapılandır - müzik durdurmasın
  Future<void> _setupAudioPlayer() async {
    try {
      // Android için audio context ayarla
      await _audioPlayer.setAudioContext(
        AudioContext(
          android: AudioContextAndroid(
            contentType: AndroidContentType.sonification,
            usageType: AndroidUsageType.notificationEvent,
            audioFocus: AndroidAudioFocus.gainTransientMayDuck,
          ),
          iOS: AudioContextIOS(
            category: AVAudioSessionCategory.ambient,
            options: [AVAudioSessionOptions.mixWithOthers],
          ),
        ),
      );
    } catch (e) {
      print('Audio player setup hatası: $e');
    }
  }

  Future<void> _initTts() async {
    try {
      await _tts.setLanguage("tr-TR");

      // Kaydedilmiş ses ayarlarını yükle
      try {
        final prefs = await SharedPreferences.getInstance();

        // Ses parametrelerini yükle (varsayılanlar: rate=0.55, pitch=1.0, volume=1.0)
        final savedRate = prefs.getDouble('tts_rate') ?? 0.55;
        final savedPitch = prefs.getDouble('tts_pitch') ?? 1.0;
        final savedVolume = prefs.getDouble('tts_volume') ?? 1.0;

        await _tts.setSpeechRate(savedRate);
        await _tts.setPitch(savedPitch);
        await _tts.setVolume(savedVolume);

        print('✅ TTS: Ayarlar yüklendi - Rate: $savedRate, Pitch: $savedPitch, Volume: $savedVolume');
      } catch (e) {
        // Hata varsa varsayılan değerleri kullan
        await _tts.setSpeechRate(0.55);
        await _tts.setPitch(1.0);
        await _tts.setVolume(1.0);
        print('⚠️ TTS ayarları yüklenemedi, varsayılanlar kullanılıyor: $e');
      }

      // TTS engine'in hazır olması için kısa bir bekleme
      await Future.delayed(const Duration(milliseconds: 500));

      // Kaydedilmiş ses tercihini yükle (varsa)
      try {
        final prefs = await SharedPreferences.getInstance();
        final savedVoiceName = prefs.getString('tts_voice_name');
        final savedVoiceLocale = prefs.getString('tts_voice_locale');

        if (savedVoiceName != null && savedVoiceLocale != null) {
          // Kullanıcının seçtiği sesi kullan
          await _tts.setVoice({"name": savedVoiceName, "locale": savedVoiceLocale});
          print('✅ TTS: Kaydedilmiş ses yüklendi: $savedVoiceName');
        } else {
          print('ℹ️ TTS: Varsayılan Türkçe ses kullanılıyor');
        }
      } catch (e) {
        print('⚠️ TTS voice setting hatası (varsayılan ses kullanılacak): $e');
        // Ses seçimi başarısız olsa bile devam et - varsayılan sesi kullan
      }
    } catch (e) {
      print('❌ TTS init hatası: $e');
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _hrSubscription?.cancel();
    _powerSubscription?.cancel();
    _cadenceSubscription?.cancel();
    _audioPlayer.dispose();
    // AI Coach overlay ve kuyruğunu temizle
    CoachMessageManager.clearQueue();
    _coachService.reset();
    // Orientation'ı geri al
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    // Sistem UI'yi geri getir
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    // Wakelock'u kapat
    WakelockPlus.disable();
    super.dispose();
  }

  // Antrenmana başla
  void _startWorkout() async {
    // HR bağlı değilse uyarı göster
    if (!_isHRConnected) {
      final shouldContinue = await _showHRWarningDialog();
      if (shouldContinue != true) {
        return; // Kullanıcı iptal etti veya HR bağlamak istiyor
      }
    }

    setState(() {
      _isRunning = true;
      _isPaused = false;
      _startTime = DateTime.now();
    });

    // Workout başladığında AI Coach'a genel bakış için bilgi gönder
    // İlk 3 dakika sonra gönder
    Future.delayed(const Duration(seconds: 180), () {
      if (mounted) {
        _sendWorkoutOverviewToCoach();
      }
    });

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!_isPaused) {
        setState(() {
          _elapsedSeconds++;
          _updateCurrentTargets();
          _recordData();
        });

        // Durumu her saniye kaydet
        _saveWorkoutState();

        // AI Coach kontrolü
        _checkCoachMessage();

        // Antrenman bitti mi?
        if (_elapsedSeconds >= widget.workout.durationSeconds) {
          _finishWorkout();
        }
      }
    });
  }

  // Duraklat
  void _pauseWorkout() {
    setState(() {
      _isPaused = !_isPaused;
    });

    // Duraklat durumunu kaydet
    _saveWorkoutState();
  }

  // Durdur
  void _stopWorkout() {
    _timer?.cancel();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Antrenmanı Bitir'),
        content: const Text('Antrenmanı sonlandırmak istediğinizden emin misiniz?'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              // Timer'ı tekrar başlat
              _startWorkout();
            },
            child: const Text('Devam Et'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await _clearSavedState(); // Kaydı temizle
              _finishWorkout();
            },
            child: const Text('Bitir', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  // Şu anki hedef power ve kadansı güncelle
  void _updateCurrentTargets() {
    int currentTime = 0;
    int segmentIndex = 0;

    for (var segment in widget.workout.segments) {
      if (_elapsedSeconds >= currentTime &&
          _elapsedSeconds < currentTime + segment.durationSeconds) {
        // Bu segment içindeyiz
        double progress = (_elapsedSeconds - currentTime) / segment.durationSeconds;

        // Power (ramp ise interpolate et)
        _currentTargetPower = segment.powerLow +
            (segment.powerHigh - segment.powerLow) * progress;
        _currentTargetCadence = segment.cadence;

        // Segment kalan süre
        _currentSegmentRemainingSeconds = (currentTime + segment.durationSeconds) - _elapsedSeconds;

        // Yeni segmente geçtik mi kontrol et
        if (segmentIndex != _currentSegmentIndex) {
          _currentSegmentIndex = segmentIndex;
          _announceSegmentStart(segment);
        } else {
          // Segment içinde - her watt değişimini bildir
          _announceTargetChange();
        }

        // Segment bitiş beep'i (son 5 saniye)
        _playSegmentCountdownBeep();

        return;
      }
      currentTime += segment.durationSeconds;
      segmentIndex++;
    }
  }

  // Segment başlangıcını sesli bildir
  Future<void> _announceSegmentStart(WorkoutSegment segment) async {
    final targetWatts = (_currentTargetPower * widget.workout.ftp).round();
    _lastAnnouncedPower = targetWatts;
    _lastAnnouncedCadence = _currentTargetCadence;

    // Segment ismini belirle
    String segmentName;
    switch (segment.type) {
      case SegmentType.warmup:
        segmentName = "Isınma";
        break;
      case SegmentType.steadyState:
        segmentName = "Steady";
        break;
      case SegmentType.interval:
        segmentName = "İnterval";
        break;
      case SegmentType.cooldown:
        segmentName = "Soğuma";
        break;
      case SegmentType.freeRide:
        segmentName = "Serbest";
        break;
    }

    // Türkçe bildirim
    final message = "$segmentName, $targetWatts watt, $_currentTargetCadence devir";
    await _tts.speak(message);
  }

  // Hedef değişikliğini sesli bildir
  Future<void> _announceTargetChange() async {
    final targetWatts = (_currentTargetPower * widget.workout.ftp).round();

    // Her watt değişiminde bildir (1W bile olsa)
    if (targetWatts != _lastAnnouncedPower || _currentTargetCadence != _lastAnnouncedCadence) {
      _lastAnnouncedPower = targetWatts;
      _lastAnnouncedCadence = _currentTargetCadence;

      // Türkçe bildirim
      final message = "$targetWatts watt, $_currentTargetCadence devir";
      await _tts.speak(message);
    }
  }

  // Veri kaydet (her saniye)
  void _recordData() {
    if (!_isRunning) return;

    // HR verisini kaydet (Bluetooth'tan gelen)
    if (_currentHR > 0) {
      _hrHistory.add(HeartRatePoint(
        _elapsedSeconds,
        _currentHR,
      ));
    }

    // Power verisini kaydet
    // Sensör bağlıysa gerçek power, yoksa target power kullan
    final powerToRecord = _isPowerConnected && _currentPower > 0
        ? _currentPower
        : (_currentTargetPower * widget.workout.ftp).round();

    if (powerToRecord > 0) {
      _powerHistory.add(PowerPoint(
        _elapsedSeconds,
        powerToRecord,
      ));

      // NP hesaplama için power history tracking (son 30 saniye)
      _powerHistoryForNP.add(powerToRecord.toDouble());
      if (_powerHistoryForNP.length > 30) {
        _powerHistoryForNP.removeAt(0);
      }

      // Average power hesapla (tüm history)
      _averagePower = _powerHistory
          .map((p) => p.watts.toDouble())
          .reduce((a, b) => a + b) / _powerHistory.length;
    }

    // Average cadence hesapla
    // Eğer sensör bağlıysa gerçek cadence kullan
    if (_isCadenceConnected && _currentCadence > 0) {
      _averageCadence = _currentCadence.toDouble();
    } else if (_currentTargetCadence > 0) {
      _averageCadence = _currentTargetCadence.toDouble();
    }
  }

  // AI Coach mesajlarını kontrol et
  Future<void> _checkCoachMessage() async {
    // Çok sık kontrol etme (her saniye değil)
    if (_elapsedSeconds == _lastCoachCheckSecond) return;
    _lastCoachCheckSecond = _elapsedSeconds;

    // Segment bilgilerini bul
    int segmentStartTime = 0;
    WorkoutSegment? currentSegment;
    int segmentElapsed = 0;

    for (var segment in widget.workout.segments) {
      if (_elapsedSeconds >= segmentStartTime &&
          _elapsedSeconds < segmentStartTime + segment.durationSeconds) {
        currentSegment = segment;
        segmentElapsed = _elapsedSeconds - segmentStartTime;
        break;
      }
      segmentStartTime += segment.durationSeconds;
    }

    if (currentSegment == null) return;

    // Segment değişimi kontrolü - force mesaj gönder
    CoachMessageType? forceType;
    bool isSegmentMessage = false;
    if (segmentElapsed == 0) {
      // Segment başlangıcı
      forceType = CoachMessageType.segmentStart;
      isSegmentMessage = true;
    } else if (segmentElapsed == currentSegment.durationSeconds - 30 && currentSegment.durationSeconds > 40) {
      // Segment bitişi (30 saniye kala, eğer segment 40 saniyeden uzunsa)
      forceType = CoachMessageType.segmentEnd;
      isSegmentMessage = true;
    }

    // Coach context oluştur
    // Gerçek verileri kullan, yoksa target değerleri
    final actualPower = _isPowerConnected && _currentPower > 0
        ? _currentPower.toDouble()
        : _currentTargetPower * widget.workout.ftp;
    final actualCadence = _isCadenceConnected && _currentCadence > 0
        ? _currentCadence
        : _currentTargetCadence;

    final coachContext = CoachContext(
      currentHeartRate: _currentHR > 0 ? _currentHR : null,
      averageHeartRate: _hrHistory.isNotEmpty
          ? _hrHistory.map((h) => h.bpm).reduce((a, b) => a + b) ~/ _hrHistory.length
          : null,
      maxHeartRate: 185, // TODO: Kullanıcıdan al
      currentPower: actualPower,
      targetPower: _currentTargetPower * widget.workout.ftp,
      currentCadence: actualCadence,
      targetCadence: _currentTargetCadence,
      segmentType: currentSegment.type.toString().split('.').last,
      segmentName: currentSegment.name ?? currentSegment.type.toString(),
      elapsedSeconds: _elapsedSeconds,
      segmentDurationSeconds: currentSegment.durationSeconds,
      segmentElapsedSeconds: segmentElapsed,
      ftp: widget.workout.ftp,
    );

    // WorkoutMetrics hesapla (yeni sistem!)
    final workoutMetrics = WorkoutMetrics.calculate(
      currentPower: actualPower,
      averagePower: _averagePower,
      currentCadence: actualCadence.toDouble(),
      averageCadence: _averageCadence,
      currentHeartRate: _currentHR > 0 ? _currentHR : null,
      averageHeartRate: _hrHistory.isNotEmpty
          ? _hrHistory.map((h) => h.bpm).reduce((a, b) => a + b) ~/ _hrHistory.length
          : null,
      ftp: widget.workout.ftp,
      workoutType: _workoutType ?? WorkoutType.mixed,
      powerHistory: _powerHistoryForNP,  // Son 30 saniye için NP
    );

    // Mesaj üret
    // ÖNEMLİ: Segment mesajı varsa SADECE onu gönder, başka mesaj üretme
    if (isSegmentMessage) {
      // Sadece segment mesajını gönder
      try {
        final message = await _coachService.generateMessage(
          context: coachContext,
          metrics: workoutMetrics,
          workoutElapsedSeconds: _elapsedSeconds,
          forceType: forceType,  // segmentStart veya segmentEnd
        );

        if (message != null && mounted) {
          setState(() {
            _currentCoachMessage = message;
          });
          CoachMessageManager.enqueue(context, message);
        }
      } catch (e) {
        print('Segment mesaj hatası: $e');
      }
      // Segment mesajı gönderildi, başka mesaj üretme!
      return;
    }

    // Normal AI mesajları (segment mesajı yoksa)
    try {
      final message = await _coachService.generateMessage(
        context: coachContext,
        metrics: workoutMetrics,
        workoutElapsedSeconds: _elapsedSeconds,
        forceType: null,  // Normal AI mesajı
      );

      if (message != null && mounted) {
        setState(() {
          _currentCoachMessage = message;
        });
        CoachMessageManager.enqueue(context, message);
      }
    } catch (e) {
      print('Coach mesaj hatası: $e');
    }
  }

  // Workout başlangıcında genel bakış mesajı gönder
  Future<void> _sendWorkoutOverviewToCoach() async {
    print('🏋️ Workout overview gönderiliyor...');
    try {
      // Segment tiplerini topla
      final segmentTypes = widget.workout.segments
          .map((s) => s.type.toString().split('.').last)
          .toSet()
          .toList();

      // Workout yapısını detaylıca oluştur
      final structureBuffer = StringBuffer();
      for (var i = 0; i < widget.workout.segments.length; i++) {
        final segment = widget.workout.segments[i];
        final duration = (segment.durationSeconds / 60).toStringAsFixed(1);
        final powerRange = segment.powerLow == segment.powerHigh
            ? '${(segment.powerLow * 100).toInt()}% FTP'
            : '${(segment.powerLow * 100).toInt()}-${(segment.powerHigh * 100).toInt()}% FTP';

        structureBuffer.writeln(
          '${i + 1}. ${segment.type.toString().split('.').last}: ${duration}dk @ $powerRange'
        );
      }

      final message = await _coachService.generateWorkoutOverview(
        workoutName: widget.workout.name,
        workoutDescription: widget.workout.description,
        totalDurationMinutes: (widget.workout.durationSeconds / 60).round(),
        avgPower: widget.workout.getAveragePower(),
        normalizedPower: widget.workout.calculateNP(),
        ftp: widget.workout.ftp,
        segmentTypes: segmentTypes,
        workoutStructure: structureBuffer.toString(),
      );

      if (message != null && mounted) {
        print('✅ Workout overview alındı: ${message.message.substring(0, 50)}...');
        setState(() {
          _currentCoachMessage = message;
        });
        // Workout overview mesajını göster
        CoachMessageManager.enqueue(context, message);
      } else {
        print('⚠️ Workout overview mesajı null döndü!');
        // Debug: Ekranda göster
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('⚠️ AI Coach: Workout overview alınamadı. Coach mode ve API key kontrol edin.'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 5),
            ),
          );
        }
      }
    } catch (e) {
      print('❌ Workout overview hatası: $e');
      // Debug: Ekranda göster
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ AI Coach hatası: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  // Antrenmanı bitir
  void _finishWorkout() async {
    _timer?.cancel();

    // Kaydedilmiş durumu temizle
    await _clearSavedState();

    // StartTime yoksa workout hiç başlamamış demektir
    if (_startTime == null) {
      Navigator.pop(context);
      return;
    }

    // Grafik screenshot'ını al
    Uint8List? graphScreenshot;
    try {
      graphScreenshot = await _screenshotController.capture();
    } catch (e) {
      print('Screenshot capture error: $e');
    }

    // Activity data oluştur (HR history boş olsa bile)
    final activityData = _createActivityData(graphScreenshot: graphScreenshot);

    // Özet ekranına git
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => WorkoutSummaryScreen(activity: activityData),
        ),
      );
    }
  }

  // Activity data oluştur
  ActivityData _createActivityData({Uint8List? graphScreenshot}) {
    // Power ve kadans verilerini oluştur
    List<PowerDataPoint> powerData = [];
    List<CadenceDataPoint> cadenceData = [];

    int currentTime = 0;
    for (var segment in widget.workout.segments) {
      for (int i = 0; i < segment.durationSeconds && currentTime < _elapsedSeconds; i++) {
        double progress = i / segment.durationSeconds;
        double powerWatts = (segment.powerLow + (segment.powerHigh - segment.powerLow) * progress) * widget.workout.ftp;

        powerData.add(PowerDataPoint(
          currentTime,
          powerWatts,
        ));

        cadenceData.add(CadenceDataPoint(
          currentTime,
          segment.cadence,
        ));

        currentTime++;
      }
    }

    // Ortalama ve max değerler
    int avgHR = _hrHistory.isNotEmpty
        ? _hrHistory.map((h) => h.bpm).reduce((a, b) => a + b) ~/ _hrHistory.length
        : 0;
    int maxHR = _hrHistory.isNotEmpty
        ? _hrHistory.map((h) => h.bpm).reduce((a, b) => a > b ? a : b)
        : 0;

    // Basitleştirilmiş hesaplamalar
    double avgPower = powerData.isNotEmpty
        ? powerData.map((p) => p.watts).reduce((a, b) => a + b) / powerData.length
        : 0;
    double maxPower = powerData.isNotEmpty
        ? powerData.map((p) => p.watts).reduce((a, b) => a > b ? a : b)
        : 0;

    int avgCadence = cadenceData.isNotEmpty
        ? cadenceData.map((c) => c.rpm).reduce((a, b) => a + b) ~/ cadenceData.length
        : 85;
    int maxCadence = cadenceData.isNotEmpty
        ? cadenceData.map((c) => c.rpm).reduce((a, b) => a > b ? a : b)
        : 85;

    // Kilojoules hesapla
    double kilojoules = avgPower * _elapsedSeconds / 1000;

    // TSS ve IF basitleştirilmiş hesaplama
    double intensityFactor = avgPower / widget.workout.ftp;
    double tss = (_elapsedSeconds * avgPower * intensityFactor) / (widget.workout.ftp * 3600) * 100;

    // Workout tam tamamlanmadıysa ismine belirt
    final isComplete = _elapsedSeconds >= widget.workout.durationSeconds;
    final workoutName = isComplete
        ? widget.workout.name
        : '${widget.workout.name} (Incomplete)';

    return ActivityData(
      startTime: _startTime!,
      endTime: DateTime.now(),
      workoutName: workoutName,
      durationSeconds: _elapsedSeconds,
      ftp: widget.workout.ftp,
      heartRateData: _hrHistory.map((h) => HeartRateDataPoint(h.seconds, h.bpm)).toList(),
      avgHeartRate: avgHR,
      maxHeartRate: maxHR,
      powerData: powerData,
      avgPower: avgPower,
      maxPower: maxPower,
      normalizedPower: avgPower,
      cadenceData: cadenceData,
      avgCadence: avgCadence,
      maxCadence: maxCadence,
      tss: tss,
      intensityFactor: intensityFactor,
      kilojoules: kilojoules,
      graphScreenshot: graphScreenshot,
      plannedPowerData: _generatePlannedPowerData(),
      plannedDurationSeconds: widget.workout.durationSeconds,
    );
  }

  /// Generate planned power data from workout segments
  List<PowerDataPoint> _generatePlannedPowerData() {
    List<PowerDataPoint> planned = [];
    int timestamp = 0;

    for (var segment in widget.workout.segments) {
      // Handle interval segments with repeats
      if (segment.type == SegmentType.interval && segment.repeatCount != null) {
        for (int rep = 0; rep < segment.repeatCount!; rep++) {
          // On phase
          double onPowerWatts = (segment.onPower ?? segment.powerHigh) * widget.workout.ftp;
          planned.add(PowerDataPoint(timestamp, onPowerWatts));
          timestamp += segment.onDuration!;
          planned.add(PowerDataPoint(timestamp, onPowerWatts));

          // Off phase
          double offPowerWatts = (segment.offPower ?? segment.powerLow) * widget.workout.ftp;
          planned.add(PowerDataPoint(timestamp, offPowerWatts));
          timestamp += segment.offDuration!;
          planned.add(PowerDataPoint(timestamp, offPowerWatts));
        }
      } else {
        // Regular segment (steady state or ramp)
        if (segment.powerLow == segment.powerHigh) {
          // Steady state segment
          double powerWatts = segment.powerLow * widget.workout.ftp;
          planned.add(PowerDataPoint(timestamp, powerWatts));
          timestamp += segment.durationSeconds;
          planned.add(PowerDataPoint(timestamp, powerWatts));
        } else {
          // Ramp segment - add points at start and end
          double startPowerWatts = segment.powerLow * widget.workout.ftp;
          double endPowerWatts = segment.powerHigh * widget.workout.ftp;

          planned.add(PowerDataPoint(timestamp, startPowerWatts));
          timestamp += segment.durationSeconds;
          planned.add(PowerDataPoint(timestamp, endPowerWatts));
        }
      }
    }

    return planned;
  }

  @override
  Widget build(BuildContext context) {
    final remainingSeconds = widget.workout.durationSeconds - _elapsedSeconds;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // Ana ekran: Sadece grafik (tam ekran)
            GestureDetector(
              onTap: () {
                // Grafiğe tıklayınca menüyü kapat
                if (_isMenuVisible) {
                  setState(() {
                    _isMenuVisible = false;
                  });
                }
              },
              onHorizontalDragEnd: _chartWidth >= widget.workout.durationSeconds.toDouble()
                ? (details) {
                    // Sadece zoom yapılmadığında menü açma/kapama aktif
                    // Soldan sağa kaydırma - menüyü aç
                    if (details.primaryVelocity! > 0) {
                      setState(() {
                        _isMenuVisible = true;
                      });
                    }
                    // Sağdan sola kaydırma - menüyü kapat
                    else if (details.primaryVelocity! < 0) {
                      setState(() {
                        _isMenuVisible = false;
                      });
                    }
                  }
                : null, // Zoom yapıldığında menü gesture'ı devre dışı
              child: Container(
                color: Colors.black,
                child: Column(
                  children: [
                    // Grafik alanı - 2/3
                    Expanded(
                      flex: 2,
                      child: _buildPowerProfileChart(),
                    ),
                    // Segment bilgisi - 1/3
                    Expanded(
                      flex: 1,
                      child: _buildSegmentInfo(),
                    ),
                  ],
                ),
              ),
            ),

            // Slide menü (overlay)
            AnimatedPositioned(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOut,
              left: _isMenuVisible ? 0 : -200,
              top: 0,
              bottom: 0,
              width: 200,
              child: Container(
                color: Colors.grey.shade900,
                child: Column(
                children: [
                  // Başlık ve kapat butonu
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back, size: 20),
                          tooltip: 'Menüyü Kapat',
                          onPressed: () {
                            setState(() {
                              _isMenuVisible = false;
                            });
                          },
                        ),
                        Expanded(
                          child: Text(
                            widget.workout.name,
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 20),
                          tooltip: 'Antrenmandan Çık',
                          onPressed: () {
                            if (_isRunning) {
                              _stopWorkout();
                            } else {
                              Navigator.pop(context);
                            }
                          },
                        ),
                      ],
                    ),
                  ),

                  const Divider(height: 1, color: Colors.grey),

                  // Metrikler
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildCompactMetric('Geçen', _formatTime(_elapsedSeconds), Icons.timer),
                        const SizedBox(height: 10),
                        _buildCompactMetric('Kalan', _formatTime(remainingSeconds), Icons.timer_outlined),
                        const SizedBox(height: 10),
                        _buildHRMetricWithStatus(),

                        // HR bağlama butonu (HR bağlı değilse göster)
                        if (!_isHRConnected) ...[
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            onPressed: () async {
                              setState(() {
                                _isMenuVisible = false;
                              });
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const SensorConnectionScreen(),
                                ),
                              );
                            },
                            icon: const Icon(Icons.bluetooth, size: 16),
                            label: const Text('HR Bağla', style: TextStyle(fontSize: 12)),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.red,
                              side: const BorderSide(color: Colors.red),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            ),
                          ),
                        ],

                      ],
                    ),
                  ),

                  // Boşluk - butonları alta it
                  const Spacer(),

                  // Kontrol butonları
                  _buildCompactControls(),
                ],
              ),
            ),
          ),

            // Menü göstergesi (sol kenarda küçük çizgi)
            if (!_isMenuVisible)
              Positioned(
                left: 0,
                top: MediaQuery.of(context).size.height / 2 - 30,
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      _isMenuVisible = true;
                    });
                  },
                  child: Container(
                    width: 30,
                    height: 60,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade800.withOpacity(0.7),
                      borderRadius: const BorderRadius.only(
                        topRight: Radius.circular(8),
                        bottomRight: Radius.circular(8),
                      ),
                    ),
                    child: const Icon(Icons.chevron_right, color: Colors.white, size: 24),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _formatTime(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  Widget _buildCompactMetric(String label, String value, IconData icon, {Color? color}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Icon(icon, size: 12, color: color ?? Colors.grey),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(fontSize: 10, color: Colors.grey[400])),
          ],
        ),
        Text(
          value,
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color ?? Colors.white),
        ),
      ],
    );
  }

  Widget _buildHRMetricWithStatus() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Icon(
              Icons.favorite,
              size: 12,
              color: _isHRConnected ? Colors.red : Colors.grey,
            ),
            const SizedBox(width: 6),
            Text(
              'HR',
              style: TextStyle(fontSize: 10, color: Colors.grey[400]),
            ),
            const SizedBox(width: 4),
            // Bağlantı durumu göstergesi
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _isHRConnected ? Colors.green : Colors.grey,
              ),
            ),
          ],
        ),
        Text(
          _currentHR > 0 ? '$_currentHR' : '--',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: _isHRConnected ? Colors.red : Colors.grey,
          ),
        ),
      ],
    );
  }

  // Zaman ve HR bölümü
  Widget _buildTimeAndHRSection(int remainingSeconds) {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Theme.of(context).cardColor,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildTimeDisplay('Geçen', _elapsedSeconds),
          Container(width: 1, height: 40, color: Colors.grey[700]),
          _buildTimeDisplay('Kalan', remainingSeconds),
          Container(width: 1, height: 40, color: Colors.grey[700]),
          _buildHRDisplay(),
        ],
      ),
    );
  }

  Widget _buildTimeDisplay(String label, int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 12, color: Colors.grey[400]),
        ),
        const SizedBox(height: 4),
        Text(
          '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}',
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  Widget _buildHRDisplay() {
    return Column(
      children: [
        Text(
          'HR',
          style: TextStyle(fontSize: 12, color: Colors.grey[400]),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            const Icon(Icons.favorite, color: Colors.red, size: 20),
            const SizedBox(width: 4),
            Text(
              _currentHR > 0 ? '$_currentHR' : '--',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ],
    );
  }

  // Grafik bölümü
  Widget _buildChart() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Hedef power ve kadans göstergesi
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Hedef: ${_currentTargetPower.round()}W @ ${_currentTargetCadence} RPM',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          
          // Grafik
          Expanded(
            child: _buildPowerProfileChart(),
          ),
        ],
      ),
    );
  }

  // Segment bilgisi widget'ı
  Widget _buildSegmentInfo() {
    if (!_isRunning || _currentSegmentIndex < 0) {
      return Container(
        color: Colors.grey.shade900,
        child: Center(
          child: Text(
            'Antrenmana başlamak için menüyü açın',
            style: TextStyle(color: Colors.grey[600], fontSize: 14),
          ),
        ),
      );
    }

    final segment = widget.workout.segments[_currentSegmentIndex];
    final targetWatts = (_currentTargetPower * widget.workout.ftp).round();

    return Container(
      color: Colors.grey.shade900,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          // Segment adı ve tipi
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Segment ${_currentSegmentIndex + 1}/${widget.workout.segments.length}',
                  style: TextStyle(color: Colors.grey[500], fontSize: 12),
                ),
                const SizedBox(height: 4),
                Text(
                  segment.name ?? 'Segment',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),

          // Segment kalan süre (büyük gösterge)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blue.withOpacity(0.5), width: 2),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'SEGMENT KALAN',
                  style: TextStyle(color: Colors.grey[400], fontSize: 10, letterSpacing: 1),
                ),
                const SizedBox(height: 4),
                Text(
                  _formatTime(_currentSegmentRemainingSeconds),
                  style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.blue),
                ),
              ],
            ),
          ),

          // Hedef power ve HR - Kompakt düzen
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // HR Değeri
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.favorite,
                      size: 12,
                      color: _isHRConnected ? Colors.red : Colors.grey,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _currentHR > 0 ? '$_currentHR' : '--',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: _isHRConnected ? Colors.red : Colors.grey,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Divider(height: 1, color: Colors.grey),
                const SizedBox(height: 8),
                // Hedef başlık
                const Text(
                  'HEDEF',
                  style: TextStyle(color: Colors.grey, fontSize: 10),
                ),
                const SizedBox(height: 4),
                // RPM ve Watt yan yana (horizontal) - her biri kendi column'unda
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    // RPM (solda)
                    Column(
                      children: [
                        Text(
                          '${_currentTargetCadence}',
                          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.blue),
                        ),
                        const Text('RPM', style: TextStyle(fontSize: 10, color: Colors.grey)),
                      ],
                    ),
                    const SizedBox(width: 16),
                    // Watt (sağda)
                    Column(
                      children: [
                        Text(
                          '${targetWatts}W',
                          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.yellow),
                        ),
                        const Text('WATT', style: TextStyle(fontSize: 10, color: Colors.grey)),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Power profil grafiği (TrainerRoad benzeri - LineChart ile zoom desteği)
  Widget _buildPowerProfileChart() {
    // Max power'ı segment'lerden hesapla
    double maxPower = widget.workout.segments
        .map((s) => s.powerHigh > s.powerLow ? s.powerHigh : s.powerLow)
        .reduce((a, b) => a > b ? a : b) * widget.workout.ftp;

    return GestureDetector(
      onScaleStart: (details) {
        // Zoom başlangıcı - mevcut değerleri kaydet
        _lastScale = 1.0;
        _lastPanX = details.focalPoint.dx;
      },
      onScaleUpdate: (details) {
        setState(() {
          // Zoom (pinch) işlemi - sadece yatayda
          if (details.pointerCount == 2) {
            // İki parmak - zoom
            double scaleDelta = details.scale / _lastScale;
            double newWidth = _chartWidth / scaleDelta;

            // Minimum ve maksimum zoom limitleri
            if (newWidth < 60) newWidth = 60; // En az 1 dakika
            if (newWidth > widget.workout.durationSeconds.toDouble()) {
              newWidth = widget.workout.durationSeconds.toDouble();
            }

            // Merkez noktasını koru
            double center = (_minX + _maxX) / 2;
            _minX = center - newWidth / 2;
            _maxX = center + newWidth / 2;

            // Sınırları kontrol et
            if (_minX < 0) {
              _minX = 0;
              _maxX = newWidth;
            }
            if (_maxX > widget.workout.durationSeconds) {
              _maxX = widget.workout.durationSeconds.toDouble();
              _minX = _maxX - newWidth;
            }

            _chartWidth = newWidth;
            _lastScale = details.scale;
          }
          // Pan (kaydırma) işlemi - tek parmak, zoom modunda
          else if (details.pointerCount == 1 && _chartWidth < widget.workout.durationSeconds.toDouble()) {
            // Tek parmak - yatay kaydırma
            double dx = details.focalPoint.dx - _lastPanX;
            double deltaX = -dx * (_chartWidth / 1000); // Hassasiyet ayarı

            _minX += deltaX;
            _maxX += deltaX;

            // Sınırları kontrol et
            if (_minX < 0) {
              double diff = -_minX;
              _minX = 0;
              _maxX += diff;
            }
            if (_maxX > widget.workout.durationSeconds) {
              double diff = _maxX - widget.workout.durationSeconds;
              _maxX = widget.workout.durationSeconds.toDouble();
              _minX -= diff;
            }

            _lastPanX = details.focalPoint.dx;
          }
        });
      },
      child: Screenshot(
        controller: _screenshotController,
        child: Container(
          color: Colors.black, // Screenshot için arka plan rengi
          child: LineChart(
            LineChartData(
              minX: _minX,
              maxX: _maxX,
              minY: 0,
              maxY: maxPower * 1.2,
              lineTouchData: LineTouchData(enabled: false),
              titlesData: FlTitlesData(
                show: true,
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    interval: 600, // Her 10 dakika
                    getTitlesWidget: (value, meta) {
                      final minutes = (value / 60).toInt();
                      return Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text('${minutes}\'', style: const TextStyle(fontSize: 10)),
                      );
                    },
                  ),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 40,
                    getTitlesWidget: (value, meta) {
                      return Text('${value.toInt()}W', style: const TextStyle(fontSize: 10));
                    },
                  ),
                ),
                topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              gridData: FlGridData(
                show: true,
                drawVerticalLine: true,
                verticalInterval: 600, // Her 10 dakika dikey çizgi
                horizontalInterval: 50, // Her 50W yatay çizgi
                getDrawingHorizontalLine: (value) {
                  return FlLine(
                    color: Colors.grey.withOpacity(0.2),
                    strokeWidth: 1,
                  );
                },
                getDrawingVerticalLine: (value) {
                  return FlLine(
                    color: Colors.grey.withOpacity(0.2),
                    strokeWidth: 1,
                  );
                },
              ),
              borderData: FlBorderData(
                show: true,
                border: Border.all(color: Colors.grey.shade800),
              ),
              lineBarsData: [
                ..._createColoredSegmentBars(),
                // Power line overlay (TrainerRoad style - real-time power data)
                if (_powerHistory.isNotEmpty) _createPowerLine(),
                // HR line overlay
                if (_hrHistory.isNotEmpty) _createHRLine(maxPower * 1.2),
              ],
              extraLinesData: ExtraLinesData(
                verticalLines: [
                  // Progress line (yeşil dikey çizgi)
                  if (_isRunning)
                    VerticalLine(
                      x: _elapsedSeconds.toDouble(),
                      color: Colors.green,
                      strokeWidth: 3,
                      dashArray: [8, 4],
                      label: VerticalLineLabel(
                        show: true,
                        labelResolver: (line) => '',
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Her segment için renkli bar oluştur
  List<LineChartBarData> _createColoredSegmentBars() {
    List<LineChartBarData> bars = [];
    int currentTime = 0;

    for (var segment in widget.workout.segments) {
      final startPowerWatts = segment.powerLow * widget.workout.ftp;
      final endPowerWatts = segment.powerHigh * widget.workout.ftp;
      final avgPowerPercent = (segment.powerLow + segment.powerHigh) / 2;
      final color = _getPowerZoneColor(avgPowerPercent);

      // Segment başlangıç ve bitiş zamanları
      final segmentStart = currentTime;
      final segmentEnd = currentTime + segment.durationSeconds;

      // Bu segment tamamlanmış mı, kısmi mi, yoksa hiç yapılmamış mı?
      final isFullyCompleted = _elapsedSeconds >= segmentEnd;
      final isPartiallyCompleted = _elapsedSeconds > segmentStart && _elapsedSeconds < segmentEnd;
      final isNotStarted = _elapsedSeconds <= segmentStart;

      if (isFullyCompleted) {
        // Tamamlanmış segment - normal renk
        List<FlSpot> segmentSpots = [
          FlSpot(segmentStart.toDouble(), startPowerWatts),
          FlSpot(segmentEnd.toDouble(), endPowerWatts),
        ];

        bars.add(
          LineChartBarData(
            spots: segmentSpots,
            isCurved: false,
            color: Colors.transparent,
            barWidth: 0,
            dotData: FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: color.withOpacity(0.7),
              cutOffY: 0,
              applyCutOffY: true,
            ),
          ),
        );
      } else if (isPartiallyCompleted) {
        // Segment kısmen tamamlanmış - ikiye böl
        // Tamamlanan kısım (normal renk)
        final completedProgress = (_elapsedSeconds - segmentStart) / segment.durationSeconds;
        final currentPowerWatts = startPowerWatts + (endPowerWatts - startPowerWatts) * completedProgress;

        List<FlSpot> completedSpots = [
          FlSpot(segmentStart.toDouble(), startPowerWatts),
          FlSpot(_elapsedSeconds.toDouble(), currentPowerWatts),
        ];

        bars.add(
          LineChartBarData(
            spots: completedSpots,
            isCurved: false,
            color: Colors.transparent,
            barWidth: 0,
            dotData: FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: color.withOpacity(0.7),
              cutOffY: 0,
              applyCutOffY: true,
            ),
          ),
        );

        // Tamamlanmayan kısım (ghost - soluk renk)
        List<FlSpot> ghostSpots = [
          FlSpot(_elapsedSeconds.toDouble(), currentPowerWatts),
          FlSpot(segmentEnd.toDouble(), endPowerWatts),
        ];

        bars.add(
          LineChartBarData(
            spots: ghostSpots,
            isCurved: false,
            color: Colors.transparent,
            barWidth: 0,
            dotData: FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: color.withOpacity(0.25), // Ghost opacity
              cutOffY: 0,
              applyCutOffY: true,
            ),
          ),
        );
      } else if (isNotStarted) {
        // Hiç başlanmamış segment - tamamı ghost
        List<FlSpot> segmentSpots = [
          FlSpot(segmentStart.toDouble(), startPowerWatts),
          FlSpot(segmentEnd.toDouble(), endPowerWatts),
        ];

        bars.add(
          LineChartBarData(
            spots: segmentSpots,
            isCurved: false,
            color: Colors.transparent,
            barWidth: 0,
            dotData: FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: color.withOpacity(0.25), // Ghost opacity
              cutOffY: 0,
              applyCutOffY: true,
            ),
          ),
        );
      }

      currentTime += segment.durationSeconds;
    }

    return bars;
  }

  // Power profil noktalarını oluştur (kullanılmıyor artık)
  List<FlSpot> _createPowerSpots() {
    List<FlSpot> spots = [];
    int currentTime = 0;

    for (var segment in widget.workout.segments) {
      final startPowerWatts = segment.powerLow * widget.workout.ftp;
      final endPowerWatts = segment.powerHigh * widget.workout.ftp;

      // Segment başlangıcı
      spots.add(FlSpot(currentTime.toDouble(), startPowerWatts));

      // Segment bitişi
      currentTime += segment.durationSeconds;
      spots.add(FlSpot(currentTime.toDouble(), endPowerWatts));
    }

    return spots;
  }

  // Power zone'a göre renk (power zeden % cinsinden FTP'ye göre)
  Color _getPowerZoneColor(double powerPercent) {
    if (powerPercent < 0.55) return Colors.grey;
    if (powerPercent < 0.75) return Colors.blue;
    if (powerPercent < 0.90) return Colors.green;
    if (powerPercent < 1.05) return Colors.yellow;
    return Colors.orange;
  }

  // Power çizgisini oluştur (overlay olarak - TrainerRoad style)
  LineChartBarData _createPowerLine() {
    // Power değerlerini direkt watt cinsinden kullan
    List<FlSpot> powerSpots = _powerHistory.map((powerPoint) {
      return FlSpot(powerPoint.seconds.toDouble(), powerPoint.watts.toDouble());
    }).toList();

    return LineChartBarData(
      spots: powerSpots,
      isCurved: true,
      curveSmoothness: 0.3,
      color: Colors.cyan.withOpacity(0.9),
      barWidth: 3,
      dotData: FlDotData(show: false),
      belowBarData: BarAreaData(show: false),
    );
  }

  // HR çizgisini oluştur (overlay olarak power grafiği üzerinde)
  LineChartBarData _createHRLine(double maxY) {
    // HR değerlerini direkt BPM cinsinden kullan (normalize etme)
    List<FlSpot> hrSpots = _hrHistory.map((hrPoint) {
      return FlSpot(hrPoint.seconds.toDouble(), hrPoint.bpm.toDouble());
    }).toList();

    return LineChartBarData(
      spots: hrSpots,
      isCurved: true,
      curveSmoothness: 0.3,
      color: Colors.red.withOpacity(0.8),
      barWidth: 2,
      dotData: FlDotData(show: false),
      belowBarData: BarAreaData(show: false),
    );
  }

  // Segment countdown beep (son 5 saniye kala bir kez çal)
  void _playSegmentCountdownBeep() async {
    // Sadece 5. saniyede (segment bitişine 5 saniye kala) BİR KEZ çal
    if (_currentSegmentRemainingSeconds == 5 && _lastBeepSecond != 5) {
      _lastBeepSecond = 5;

      try {
        await _audioPlayer.stop();
        await _audioPlayer.setPlaybackRate(1.0); // Normal hız
        await _audioPlayer.setVolume(1.0);
        await _audioPlayer.play(AssetSource('sounds/beep.mp3'));
        // Ses 3.52 saniye sürer, doğal olarak biter (tekrar başlamaz)
      } catch (e) {
        print('Beep sound play error: $e');
      }
    } else if (_currentSegmentRemainingSeconds > 5) {
      // 5 saniyeden uzaksa, beep flag'ini sıfırla (sonraki segment için)
      _lastBeepSecond = -1;
    }
  }

  // Kompakt kontrol butonları (landscape için)
  Widget _buildCompactControls() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade800,
        border: Border(top: BorderSide(color: Colors.grey.shade700)),
      ),
      child: !_isRunning
          ? // Tek buton: Başla
          ElevatedButton(
              onPressed: _startWorkout,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.play_arrow, size: 28),
                  SizedBox(width: 8),
                  Text('Başla', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ],
              ),
            )
          : // Bölünmüş buton: Pause | Stop
          Row(
              children: [
                // Sol yarı: Pause/Resume
                Expanded(
                  child: ElevatedButton(
                    onPressed: _pauseWorkout,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isPaused ? Colors.green : Colors.orange,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(8),
                          bottomLeft: Radius.circular(8),
                        ),
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(_isPaused ? Icons.play_arrow : Icons.pause, size: 24),
                        const SizedBox(height: 4),
                        Text(
                          _isPaused ? 'Devam' : 'Beklet',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),

                // Orta çizgi
                Container(width: 2, height: 60, color: Colors.black),

                // Sağ yarı: Stop
                Expanded(
                  child: ElevatedButton(
                    onPressed: _stopWorkout,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.only(
                          topRight: Radius.circular(8),
                          bottomRight: Radius.circular(8),
                        ),
                      ),
                    ),
                    child: const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.stop, size: 24),
                        SizedBox(height: 4),
                        Text('Dur', style: TextStyle(fontSize: 12)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  // Kontrol butonları (eski - kullanılmıyor artık)
  Widget _buildControls() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            if (!_isRunning)
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _startWorkout,
                  icon: const Icon(Icons.play_arrow, size: 28),
                  label: const Text('Başla', style: TextStyle(fontSize: 16)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              )
            else ...[
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _pauseWorkout,
                  icon: Icon(_isPaused ? Icons.play_arrow : Icons.pause, size: 24),
                  label: Text(
                    _isPaused ? 'Devam' : 'Duraklat',
                    style: const TextStyle(fontSize: 14),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _stopWorkout,
                  icon: const Icon(Icons.stop, size: 24),
                  label: const Text('Bitir', style: TextStyle(fontSize: 14)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
