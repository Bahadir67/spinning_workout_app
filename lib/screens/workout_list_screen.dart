import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'dart:io';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import '../models/workout.dart';
import '../models/workout_state.dart';
import '../services/workout_parser.dart';
import '../services/bluetooth_service.dart';
import 'workout_detail_screen.dart';
import 'sensor_connection_screen.dart';
import 'workout_history_screen.dart';
import 'coach_settings_screen.dart';

class WorkoutListScreen extends StatefulWidget {
  const WorkoutListScreen({super.key});

  @override
  State<WorkoutListScreen> createState() => _WorkoutListScreenState();
}

class _WorkoutListScreenState extends State<WorkoutListScreen> {
  List<Workout> _workouts = [];
  bool _isLoading = false;
  int _ftp = 220; // Default FTP
  final BluetoothService _bluetoothService = BluetoothService();
  bool _isHRConnected = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadWorkouts();
    _checkHRConnection();
    _checkSavedWorkoutState();
  }

  /// Kaydedilmiş workout state kontrolü
  Future<void> _checkSavedWorkoutState() async {
    final prefs = await SharedPreferences.getInstance();
    final savedStateJson = prefs.getString('workout_state');

    if (savedStateJson != null) {
      final savedState = WorkoutState.fromJsonString(savedStateJson);

      if (savedState != null && savedState.isValid()) {
        // Build tamamlandıktan sonra dialog göster
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _showResumeWorkoutDialog(savedState);
          }
        });
      } else {
        // Geçersiz kayıt - temizle
        await prefs.remove('workout_state');
      }
    }
  }

  /// Kaydedilmiş workout'a devam et dialog'u
  Future<void> _showResumeWorkoutDialog(WorkoutState savedState) async {
    final minutes = savedState.elapsedSeconds ~/ 60;
    final seconds = savedState.elapsedSeconds % 60;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Devam Eden Antrenman'),
        content: Text(
          'Tamamlanmamış bir antrenman bulundu:\n\n'
          '${savedState.workout.name}\n'
          'Geçen süre: $minutes:${seconds.toString().padLeft(2, '0')}\n'
          'Kayıt: ${_formatTimeDiff(savedState.saveTime)}\n\n'
          'Kaldığınız yerden devam etmek ister misiniz?',
        ),
        actions: [
          TextButton(
            onPressed: () async {
              // İptal - kaydı temizle
              final prefs = await SharedPreferences.getInstance();
              await prefs.remove('workout_state');
              Navigator.pop(context, false);
            },
            child: const Text('İptal Et'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Devam Et'),
          ),
        ],
      ),
    );

    if (result == true && mounted) {
      // Workout detail screen'e git
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => WorkoutDetailScreen(workout: savedState.workout),
        ),
      );
    }
  }

  /// Zaman farkını formatla
  String _formatTimeDiff(DateTime dateTime) {
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

  /// HR bağlantı durumunu kontrol et
  void _checkHRConnection() {
    setState(() {
      _isHRConnected = _bluetoothService.isConnected;
    });
  }

  /// HR bağlantı ekranını aç
  Future<void> _openHRConnection() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const SensorConnectionScreen()),
    );

    // Geri dönünce durumu her zaman güncelle
    _checkHRConnection();
  }

  /// Load user settings (FTP)
  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _ftp = prefs.getInt('user_ftp') ?? 220;
    });
  }

  /// Save FTP setting
  Future<void> _saveFTP(int ftp) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('user_ftp', ftp);
    setState(() {
      _ftp = ftp;
    });
  }

  /// Load saved workouts
  Future<void> _loadWorkouts() async {
    setState(() => _isLoading = true);

    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/workouts.json');

      if (await file.exists()) {
        final contents = await file.readAsString();
        final List<dynamic> jsonData = jsonDecode(contents);
        _workouts = jsonData.map((json) => Workout.fromJson(json)).toList();
      } else {
        // İlk açılışta örnek workout'lar ekle
        _workouts = _getDefaultWorkouts();
        await _saveWorkouts();
      }
    } catch (e) {
      print('Workout yükleme hatası: $e');
      _workouts = _getDefaultWorkouts();
    }

    setState(() => _isLoading = false);
  }

  /// Save workouts
  Future<void> _saveWorkouts() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/workouts.json');
      final jsonData = _workouts.map((w) => w.toJson()).toList();
      await file.writeAsString(jsonEncode(jsonData));
    } catch (e) {
      print('Workout kaydetme hatası: $e');
    }
  }

  /// Import ZWO file
  Future<void> _importWorkout() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
      );

      if (result == null || result.files.isEmpty) {
        return;
      }

      final filePath = result.files.first.path;
      if (filePath == null) {
        throw Exception('Dosya yolu bulunamadı');
      }

      // Check file extension
      if (!filePath.toLowerCase().endsWith('.zwo') && !filePath.toLowerCase().endsWith('.xml')) {
        throw Exception('Sadece .zwo veya .xml dosyaları desteklenir');
      }

      // Parse ZWO file
      var workout = await WorkoutParser.parseZWOFile(filePath);

      // Create new workout with current FTP
      workout = Workout(
        id: workout.id,
        name: workout.name,
        author: workout.author,
        description: workout.description,
        ftp: _ftp,
        segments: workout.segments,
      );

      // Add to workouts list
      setState(() {
        _workouts.insert(0, workout);
      });

      await _saveWorkouts();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${workout.name} içe aktarıldı!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('İçe aktarma hatası: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Örnek workout'ları döndür
  List<Workout> _getDefaultWorkouts() {
    return [
      Workout(
        id: '1',
        name: 'HIIT 20min',
        description: 'High intensity interval training',
        author: 'Spinning Workout',
        ftp: _ftp,
        segments: [
          WorkoutSegment(type: SegmentType.warmup, durationSeconds: 300, powerLow: 0.5, powerHigh: 0.5, cadence: 85),
          WorkoutSegment(type: SegmentType.interval, durationSeconds: 120, powerLow: 1.2, powerHigh: 1.2, cadence: 100),
          WorkoutSegment(type: SegmentType.steadyState, durationSeconds: 120, powerLow: 0.5, powerHigh: 0.5, cadence: 75),
          WorkoutSegment(type: SegmentType.interval, durationSeconds: 120, powerLow: 1.2, powerHigh: 1.2, cadence: 100),
          WorkoutSegment(type: SegmentType.steadyState, durationSeconds: 120, powerLow: 0.5, powerHigh: 0.5, cadence: 75),
          WorkoutSegment(type: SegmentType.cooldown, durationSeconds: 300, powerLow: 0.5, powerHigh: 0.5, cadence: 75),
        ],
      ),
      Workout(
        id: '2',
        name: 'Endurance 30min',
        description: 'Steady endurance ride',
        author: 'Spinning Workout',
        ftp: _ftp,
        segments: [
          WorkoutSegment(type: SegmentType.warmup, durationSeconds: 300, powerLow: 0.5, powerHigh: 0.7, cadence: 80),
          WorkoutSegment(type: SegmentType.steadyState, durationSeconds: 1200, powerLow: 0.7, powerHigh: 0.7, cadence: 85),
          WorkoutSegment(type: SegmentType.cooldown, durationSeconds: 300, powerLow: 0.5, powerHigh: 0.5, cadence: 75),
        ],
      ),
      Workout(
        id: '3',
        name: 'Sweet Spot 45min',
        description: '88-93% FTP intervals',
        author: 'Spinning Workout',
        ftp: _ftp,
        segments: [
          WorkoutSegment(type: SegmentType.warmup, durationSeconds: 600, powerLow: 0.5, powerHigh: 0.7, cadence: 80),
          WorkoutSegment(type: SegmentType.interval, durationSeconds: 600, powerLow: 0.88, powerHigh: 0.93, cadence: 90),
          WorkoutSegment(type: SegmentType.steadyState, durationSeconds: 180, powerLow: 0.6, powerHigh: 0.6, cadence: 75),
          WorkoutSegment(type: SegmentType.interval, durationSeconds: 600, powerLow: 0.88, powerHigh: 0.93, cadence: 90),
          WorkoutSegment(type: SegmentType.cooldown, durationSeconds: 300, powerLow: 0.5, powerHigh: 0.5, cadence: 75),
        ],
      ),
    ];
  }

  /// Show preset workout menu (devre dışı - zaten default workoutlar yüklenmiş)
  Future<void> _showPresetMenu() async {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Örnek workout\'lar zaten yüklü!')),
      );
    }
  }

  /// Delete workout
  Future<void> _deleteWorkout(int index) async {
    final workout = _workouts[index];

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Workout'),
        content: Text('Delete ${workout.name}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() {
        _workouts.removeAt(index);
      });
      await _saveWorkouts();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${workout.name} deleted')),
        );
      }
    }
  }

  /// Start workout
  void _startWorkout(Workout workout) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => WorkoutDetailScreen(workout: workout),
      ),
    );
  }

  /// Show voice settings
  Future<void> _showVoiceSettings() async {
    final tts = FlutterTts();
    await tts.setLanguage("tr-TR");

    // Mevcut sesleri al
    final voices = await tts.getVoices;
    if (voices == null || voices.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sesler yüklenemedi')),
        );
      }
      return;
    }

    // Türkçe sesleri filtrele
    final turkishVoices = voices.where((voice) {
      final locale = voice['locale'].toString().toLowerCase();
      return locale.startsWith('tr');
    }).toList();

    if (turkishVoices.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Türkçe ses bulunamadı')),
        );
      }
      return;
    }

    // Ses seçim dialogu
    if (!mounted) return;

    // Mevcut seçili sesi oku
    final prefs = await SharedPreferences.getInstance();

    // Mevcut ayarları yükle
    String? currentVoiceName = prefs.getString('tts_voice_name');
    String? currentVoiceLocale = prefs.getString('tts_voice_locale');
    double currentRate = prefs.getDouble('tts_rate') ?? 0.55;
    double currentPitch = prefs.getDouble('tts_pitch') ?? 1.0;
    double currentVolume = prefs.getDouble('tts_volume') ?? 1.0;

    // Seçili sesi bul
    Map<dynamic, dynamic>? selectedVoice;
    if (currentVoiceName != null) {
      selectedVoice = turkishVoices.firstWhere(
        (v) => v['name'] == currentVoiceName,
        orElse: () => turkishVoices[0],
      );
    } else {
      selectedVoice = turkishVoices[0];
    }

    await showDialog(
      context: context,
      builder: (context) => _VoiceSettingsDialog(
        voices: turkishVoices,
        initialVoice: selectedVoice!,
        initialRate: currentRate,
        initialPitch: currentPitch,
        initialVolume: currentVolume,
        tts: tts,
      ),
    );
  }

  /// Show FTP settings
  Future<void> _showFTPSettings() async {
    final controller = TextEditingController(text: _ftp.toString());

    final newFTP = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Set FTP'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'FTP (Watts)',
            hintText: '220',
            helperText: 'Your Functional Threshold Power',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final ftp = int.tryParse(controller.text);
              if (ftp != null && ftp > 0) {
                Navigator.pop(context, ftp);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (newFTP != null) {
      await _saveFTP(newFTP);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('FTP set to $newFTP W')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Spinning Workouts'),
        actions: [
          // History butonu
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'Antrenman Geçmişi',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const WorkoutHistoryScreen(),
                ),
              );
            },
          ),
          // AI Coach Ayarları
          IconButton(
            icon: const Icon(Icons.psychology),
            tooltip: 'AI Coach Ayarları',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const CoachSettingsScreen(),
                ),
              );
            },
          ),
          // HR Sensörü butonu
          Stack(
            children: [
              IconButton(
                icon: Icon(
                  Icons.favorite,
                  color: _isHRConnected ? Colors.red : null,
                ),
                tooltip: _isHRConnected ? 'HR Bağlı' : 'HR Sensörü Bağla',
                onPressed: _openHRConnection,
              ),
              if (_isHRConnected)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.green,
                    ),
                  ),
                ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.record_voice_over),
            tooltip: 'Ses Ayarları',
            onPressed: _showVoiceSettings,
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Settings (FTP)',
            onPressed: _showFTPSettings,
          ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Add Preset',
            onPressed: _showPresetMenu,
          ),
          IconButton(
            icon: const Icon(Icons.file_upload),
            tooltip: 'Import ZWO',
            onPressed: _importWorkout,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _workouts.isEmpty
              ? _buildEmptyState()
              : _buildWorkoutList(),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.directions_bike, size: 80, color: Colors.grey[600]),
          const SizedBox(height: 24),
          Text(
            'No workouts yet',
            style: TextStyle(fontSize: 20, color: Colors.grey[400]),
          ),
          const SizedBox(height: 8),
          Text(
            'FTP: $_ftp W',
            style: TextStyle(fontSize: 16, color: Colors.grey[500]),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _showPresetMenu,
            icon: const Icon(Icons.add),
            label: const Text('Add Preset Workout'),
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: _importWorkout,
            icon: const Icon(Icons.file_upload),
            label: const Text('Import ZWO File'),
          ),
        ],
      ),
    );
  }

  Widget _buildWorkoutList() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _workouts.length,
      itemBuilder: (context, index) {
        final workout = _workouts[index];
        return _buildWorkoutCard(workout, index);
      },
    );
  }

  Widget _buildWorkoutCard(Workout workout, int index) {
    final duration = Duration(seconds: workout.durationSeconds);
    final minutes = duration.inMinutes;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => _startWorkout(workout),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          workout.name,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          workout.author,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[400],
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    onPressed: () => _deleteWorkout(index),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                workout.description,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[300],
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildInfoChip(Icons.timer, '$minutes min'),
                  _buildInfoChip(
                      Icons.bolt, '${workout.getAveragePower().round()}W'),
                  _buildInfoChip(
                      Icons.trending_up, 'TSS ${workout.calculateTSS().round()}'),
                  _buildInfoChip(
                      Icons.show_chart, 'IF ${workout.calculateIF().toStringAsFixed(2)}'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.blue.withOpacity(0.2),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.blue),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: Colors.blue),
          ),
        ],
      ),
    );
  }
}

/// Ses ayarları dialog'u
class _VoiceSettingsDialog extends StatefulWidget {
  final List<dynamic> voices;
  final Map<dynamic, dynamic> initialVoice;
  final double initialRate;
  final double initialPitch;
  final double initialVolume;
  final dynamic tts;

  const _VoiceSettingsDialog({
    required this.voices,
    required this.initialVoice,
    required this.initialRate,
    required this.initialPitch,
    required this.initialVolume,
    required this.tts,
  });

  @override
  State<_VoiceSettingsDialog> createState() => _VoiceSettingsDialogState();
}

class _VoiceSettingsDialogState extends State<_VoiceSettingsDialog> {
  late Map<dynamic, dynamic> _selectedVoice;
  late double _rate;
  late double _pitch;
  late double _volume;

  @override
  void initState() {
    super.initState();
    _selectedVoice = widget.initialVoice;
    _rate = widget.initialRate;
    _pitch = widget.initialPitch;
    _volume = widget.initialVolume;
  }

  Future<void> _testVoice() async {
    try {
      // TTS'i başlat
      await widget.tts.setLanguage("tr-TR");

      // Kısa bekleme - engine'in hazır olması için
      await Future.delayed(const Duration(milliseconds: 300));

      // Ayarları uygula - String'e cast et
      await widget.tts.setVoice({
        "name": _selectedVoice['name'].toString(),
        "locale": _selectedVoice['locale'].toString()
      });
      await widget.tts.setSpeechRate(_rate);
      await widget.tts.setPitch(_pitch);
      await widget.tts.setVolume(_volume);

      // Test mesajını oku
      await widget.tts.speak("Merhaba, bu ses ayarlarını test ediyorum");
    } catch (e) {
      print('Test voice hatası: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ses testi başarısız: $e')),
        );
      }
    }
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('tts_voice_name', _selectedVoice['name']);
    await prefs.setString('tts_voice_locale', _selectedVoice['locale']);
    await prefs.setDouble('tts_rate', _rate);
    await prefs.setDouble('tts_pitch', _pitch);
    await prefs.setDouble('tts_volume', _volume);

    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ses ayarları kaydedildi!')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Ses Ayarları'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Ses seçimi (ComboBox)
            const Text('Ses:', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            DropdownButtonFormField<Map<dynamic, dynamic>>(
              value: _selectedVoice,
              isExpanded: true,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              items: widget.voices.map<DropdownMenuItem<Map<dynamic, dynamic>>>((voice) {
                final name = voice['name'].toString();
                final locale = voice['locale'].toString();

                // Kadın/erkek tahmini
                String gender = '';
                if (name.contains('female') || name.contains('-f-') || name.contains('ama')) {
                  gender = '👩 ';
                } else if (name.contains('male') || name.contains('-m-')) {
                  gender = '👨 ';
                }

                return DropdownMenuItem<Map<dynamic, dynamic>>(
                  value: voice,
                  child: Text('$gender$locale', overflow: TextOverflow.ellipsis),
                );
              }).toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() => _selectedVoice = value);
                }
              },
            ),

            const SizedBox(height: 24),

            // Hız slider
            const Text('Hız:', style: TextStyle(fontWeight: FontWeight.bold)),
            Row(
              children: [
                const Text('Yavaş', style: TextStyle(fontSize: 12)),
                Expanded(
                  child: Slider(
                    value: _rate,
                    min: 0.3,
                    max: 1.0,
                    divisions: 14,
                    label: _rate.toStringAsFixed(2),
                    onChanged: (value) => setState(() => _rate = value),
                  ),
                ),
                const Text('Hızlı', style: TextStyle(fontSize: 12)),
              ],
            ),

            const SizedBox(height: 16),

            // Ses tonu slider
            const Text('Ses Tonu:', style: TextStyle(fontWeight: FontWeight.bold)),
            Row(
              children: [
                const Text('Kalın', style: TextStyle(fontSize: 12)),
                Expanded(
                  child: Slider(
                    value: _pitch,
                    min: 0.5,
                    max: 2.0,
                    divisions: 15,
                    label: _pitch.toStringAsFixed(1),
                    onChanged: (value) => setState(() => _pitch = value),
                  ),
                ),
                const Text('İnce', style: TextStyle(fontSize: 12)),
              ],
            ),

            const SizedBox(height: 16),

            // Ses şiddeti slider
            const Text('Ses Şiddeti:', style: TextStyle(fontWeight: FontWeight.bold)),
            Row(
              children: [
                const Text('Sessiz', style: TextStyle(fontSize: 12)),
                Expanded(
                  child: Slider(
                    value: _volume,
                    min: 0.0,
                    max: 1.0,
                    divisions: 10,
                    label: _volume.toStringAsFixed(1),
                    onChanged: (value) => setState(() => _volume = value),
                  ),
                ),
                const Text('Yüksek', style: TextStyle(fontSize: 12)),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('İptal'),
        ),
        const SizedBox(width: 8),
        ElevatedButton.icon(
          onPressed: _testVoice,
          icon: const Icon(Icons.volume_up),
          label: const Text('Test Et'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue,
            foregroundColor: Colors.white,
          ),
        ),
        const SizedBox(width: 8),
        ElevatedButton.icon(
          onPressed: _saveSettings,
          icon: const Icon(Icons.check),
          label: const Text('Kaydet'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
          ),
        ),
      ],
    );
  }
}
