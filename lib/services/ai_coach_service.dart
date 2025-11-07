import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/coach_message.dart';

/// AI Coach modu
enum CoachMode {
  off,           // Kapalı
  ruleBased,     // Kural bazlı (offline)
  aiPowered,     // AI destekli (OpenRouter)
}

/// AI Coach servisi - Singleton
class AICoachService {
  static final AICoachService _instance = AICoachService._internal();
  factory AICoachService() => _instance;
  AICoachService._internal();

  // OpenRouter API
  static const String _apiUrl = 'https://openrouter.ai/api/v1/chat/completions';
  String? _apiKey;

  // Ayarlar
  CoachMode _mode = CoachMode.ruleBased;
  String _selectedModel = 'google/gemini-flash-1.5';
  int _messageFrequency = 3; // dakika

  // Cache (maliyet azaltma)
  final Map<String, CoachMessage> _cache = {};
  DateTime? _lastMessageTime;

  /// Servisi başlat - ayarları yükle
  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    _apiKey = prefs.getString('openrouter_api_key');
    _mode = CoachMode.values[prefs.getInt('coach_mode') ?? 1]; // Default: ruleBased
    _selectedModel = prefs.getString('coach_model') ?? 'google/gemini-flash-1.5';
    _messageFrequency = prefs.getInt('coach_frequency') ?? 3;
  }

  /// API key kaydet
  Future<void> setApiKey(String apiKey) async {
    _apiKey = apiKey;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('openrouter_api_key', apiKey);
  }

  /// Coach modu ayarla
  Future<void> setMode(CoachMode mode) async {
    _mode = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('coach_mode', mode.index);
  }

  /// Model seç
  Future<void> setModel(String model) async {
    _selectedModel = model;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('coach_model', model);
  }

  /// Mesaj sıklığı ayarla (dakika)
  Future<void> setFrequency(int minutes) async {
    _messageFrequency = minutes;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('coach_frequency', minutes);
  }

  CoachMode get mode => _mode;
  String get selectedModel => _selectedModel;
  int get messageFrequency => _messageFrequency;
  bool get isApiKeySet => _apiKey != null && _apiKey!.isNotEmpty;

  /// Mesaj oluştur
  Future<CoachMessage?> generateMessage({
    required CoachContext context,
    CoachMessageType? forceType,
  }) async {
    // Kapalıysa mesaj üretme
    if (_mode == CoachMode.off) return null;

    // Çok sık mesaj gönderme kontrolü
    if (forceType == null && _lastMessageTime != null) {
      final timeSinceLastMessage = DateTime.now().difference(_lastMessageTime!);
      if (timeSinceLastMessage.inMinutes < _messageFrequency) {
        return null;
      }
    }

    // Cache kontrolü
    final cacheKey = _generateCacheKey(context, forceType);
    if (_cache.containsKey(cacheKey)) {
      _lastMessageTime = DateTime.now();
      return _cache[cacheKey];
    }

    CoachMessage? message;

    // AI modunda ve API key varsa
    if (_mode == CoachMode.aiPowered && isApiKeySet) {
      try {
        message = await _generateAIMessage(context, forceType);
      } catch (e) {
        print('AI mesaj hatası, kural bazlıya geçiliyor: $e');
        // Fallback: Kural bazlı
        message = _generateRuleBasedMessage(context, forceType);
      }
    } else {
      // Kural bazlı
      message = _generateRuleBasedMessage(context, forceType);
    }

    if (message != null) {
      _cache[cacheKey] = message;
      _lastMessageTime = DateTime.now();

      // Cache'i temizle (max 20 mesaj)
      if (_cache.length > 20) {
        _cache.clear();
      }
    }

    return message;
  }

  /// OpenRouter API ile mesaj oluştur
  Future<CoachMessage> _generateAIMessage(
    CoachContext context,
    CoachMessageType? forceType,
  ) async {
    final prompt = _buildPrompt(context, forceType);

    final response = await http.post(
      Uri.parse(_apiUrl),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_apiKey',
        'HTTP-Referer': 'com.spinworkout.spinning_workout_app',
        'X-Title': 'Spinning Workout App',
      },
      body: jsonEncode({
        'model': _selectedModel,
        'messages': [
          {
            'role': 'system',
            'content': 'Sen profesyonel bir bisiklet antrenörüsün. Kısa (max 2 cümle), motive edici, bilimsel ve Türkçe mesajlar veriyorsun. Samimi ve destekleyici bir tonla konuş.',
          },
          {
            'role': 'user',
            'content': prompt,
          },
        ],
        'max_tokens': 100,
        'temperature': 0.7,
      }),
    ).timeout(const Duration(seconds: 5));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final messageText = data['choices'][0]['message']['content'].trim();

      return CoachMessage(
        message: messageText,
        type: forceType ?? _determineMessageType(context),
      );
    } else {
      throw Exception('API error: ${response.statusCode}');
    }
  }

  /// Prompt oluştur
  String _buildPrompt(CoachContext context, CoachMessageType? forceType) {
    final buffer = StringBuffer();
    buffer.writeln('Antrenman bilgileri:');
    buffer.writeln('- Segment: ${context.segmentName} (${context.segmentType})');
    buffer.writeln('- İlerleme: ${(context.segmentProgress * 100).toInt()}% (${context.segmentElapsedSeconds}/${context.segmentDurationSeconds}s)');
    buffer.writeln('- FTP: ${context.ftp}W');
    buffer.writeln('- Güç: ${context.currentPower.toInt()}W (Hedef: ${context.targetPower.toInt()}W, Zone: ${context.powerZone})');
    buffer.writeln('- Kadans: ${context.currentCadence} rpm (Hedef: ${context.targetCadence} rpm)');

    if (context.currentHeartRate != null) {
      buffer.writeln('- Kalp Hızı: ${context.currentHeartRate} bpm (Ort: ${context.averageHeartRate}, Zone: ${context.hrZone})');
    }

    if (forceType != null) {
      buffer.writeln('\nMesaj tipi: ${_messageTypeToTurkish(forceType)}');
    }

    buffer.writeln('\nKısa ve motive edici bir mesaj ver.');

    return buffer.toString();
  }

  /// Kural bazlı mesaj oluştur
  CoachMessage _generateRuleBasedMessage(
    CoachContext context,
    CoachMessageType? forceType,
  ) {
    final type = forceType ?? _determineMessageType(context);
    final message = _selectRuleBasedMessage(context, type);

    return CoachMessage(
      message: message,
      type: type,
    );
  }

  /// Mesaj tipini belirle (context'e göre)
  CoachMessageType _determineMessageType(CoachContext context) {
    // Segment bitişi yakın
    if (context.segmentProgress > 0.9) {
      return CoachMessageType.segmentEnd;
    }

    // Segment başlangıcı
    if (context.segmentProgress < 0.1) {
      return CoachMessageType.segmentStart;
    }

    // HR uyarısı
    if (context.currentHeartRate != null && context.maxHeartRate != null) {
      final hrPercentage = (context.currentHeartRate! / context.maxHeartRate!) * 100;
      if (hrPercentage > 95) {
        return CoachMessageType.warning;
      }
    }

    // Rastgele (ağırlıklı)
    final random = Random();
    final value = random.nextInt(100);
    if (value < 40) return CoachMessageType.motivation;
    if (value < 70) return CoachMessageType.performance;
    return CoachMessageType.information;
  }

  /// Kural bazlı mesaj seç
  String _selectRuleBasedMessage(CoachContext context, CoachMessageType type) {
    final random = Random();

    switch (type) {
      case CoachMessageType.motivation:
        final messages = [
          'Harika gidiyorsun! Böyle devam et!',
          'Mükemmel performans gösteriyorsun!',
          'Sen yaparsın! Tüm gücünle devam et!',
          'Süper! Hedefine yaklaşıyorsun!',
          'İnanılmaz bir tempoda gidiyorsun!',
          'Gurur duymalısın! Harika iş çıkarıyorsun!',
        ];
        return messages[random.nextInt(messages.length)];

      case CoachMessageType.performance:
        if (context.currentHeartRate != null) {
          final hrDiff = context.currentHeartRate! - (context.averageHeartRate ?? context.currentHeartRate!);
          if (hrDiff > 5) {
            return 'Kalp hızın ortalamadan ${hrDiff} bpm yüksek. ${context.hrZone} bölgesindesin.';
          } else if (hrDiff < -5) {
            return 'Kalp hızın ortalamadan düşük. Temponu biraz artırabilirsin.';
          }
        }

        final powerDiff = ((context.currentPower - context.targetPower) / context.targetPower * 100).toInt();
        if (powerDiff.abs() < 5) {
          return 'Mükemmel! Hedef güçte kalmayı başarıyorsun.';
        } else if (powerDiff > 10) {
          return 'Güç hedefin üzerinde. Temponu biraz düşürebilirsin.';
        } else if (powerDiff < -10) {
          return 'Güç hedefin altında. Biraz daha bastırabilirsin!';
        }
        return '${context.powerZone} bölgesinde çalışıyorsun. Harika tempo!';

      case CoachMessageType.warning:
        if (context.currentHeartRate != null && context.maxHeartRate != null) {
          final hrPercentage = (context.currentHeartRate! / context.maxHeartRate!) * 100;
          if (hrPercentage > 95) {
            return 'Kalp hızın çok yükseldi! Temponu kontrol et.';
          }
        }
        if (context.currentCadence < 60) {
          return 'Kadansın düşük. ${context.targetCadence} rpm hedefine çık!';
        }
        return 'Dikkatli ol! Temponu kontrol altında tut.';

      case CoachMessageType.information:
        final powerPercentage = (context.currentPower / context.ftp * 100).toInt();
        if (powerPercentage > 105) {
          return 'VO2 Max bölgesinde çalışıyorsun. Bu anaerobik kapasitenı geliştiriyor.';
        } else if (powerPercentage > 90) {
          return 'Threshold bölgesinde çalışıyorsun. Bu FTP\'ni yükseltiyor.';
        } else if (powerPercentage > 75) {
          return 'Tempo bölgesinde çalışıyorsun. Sürdürülebilir güç geliştiriyorsun.';
        } else if (powerPercentage > 55) {
          return 'Endurance bölgesinde çalışıyorsun. Aerobik kapasiten gelişiyor.';
        }
        return 'Recovery bölgesinde çalışıyorsun. Bu aktif toparlanma için ideal.';

      case CoachMessageType.segmentStart:
        final duration = (context.segmentDurationSeconds / 60).toInt();
        return '${context.segmentName} başlıyor! ${duration} dakika, hedef ${context.targetPower.toInt()}W.';

      case CoachMessageType.segmentEnd:
        final remaining = context.segmentDurationSeconds - context.segmentElapsedSeconds;
        if (remaining < 30) {
          return 'Son ${remaining} saniye! Tüm gücünü ver!';
        }
        return 'Harika! Segment bitiyor, son 1 dakika!';
    }
  }

  /// Cache key oluştur
  String _generateCacheKey(CoachContext context, CoachMessageType? type) {
    return '${type?.toString() ?? 'auto'}_${context.segmentType}_${context.powerZone}_${(context.segmentProgress * 10).toInt()}';
  }

  /// Mesaj tipini Türkçe'ye çevir
  String _messageTypeToTurkish(CoachMessageType type) {
    switch (type) {
      case CoachMessageType.motivation:
        return 'Motivasyon';
      case CoachMessageType.performance:
        return 'Performans analizi';
      case CoachMessageType.warning:
        return 'Uyarı';
      case CoachMessageType.information:
        return 'Bilgilendirme';
      case CoachMessageType.segmentStart:
        return 'Segment başlangıcı';
      case CoachMessageType.segmentEnd:
        return 'Segment bitişi';
    }
  }

  /// Servisi sıfırla (yeni antrenman için)
  void reset() {
    _cache.clear();
    _lastMessageTime = null;
  }
}
