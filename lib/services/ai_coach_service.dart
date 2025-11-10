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

  // 🔑 OpenRouter API Key (varsayılan)
  static const String? _defaultApiKey = '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';

  String? _apiKey;

  // Ayarlar
  CoachMode _mode = CoachMode.ruleBased;
  String _selectedModel = 'minimax/minimax-m2';
  int _messageFrequencySeconds = 180; // saniye (varsayılan 3 dakika)

  // Cache (maliyet azaltma)
  final Map<String, CoachMessage> _cache = {};
  DateTime? _lastMessageTime;

  /// Servisi başlat - ayarları yükle
  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    _apiKey = prefs.getString('openrouter_api_key') ?? _defaultApiKey;
    _mode = CoachMode.values[prefs.getInt('coach_mode') ?? 1]; // Default: ruleBased
    _selectedModel = prefs.getString('coach_model') ?? 'minimax/minimax-m2';
    _messageFrequencySeconds = prefs.getInt('coach_frequency_seconds') ?? 180; // Default: 3 dakika
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

  /// Mesaj sıklığı ayarla (saniye)
  Future<void> setFrequencySeconds(int seconds) async {
    _messageFrequencySeconds = seconds;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('coach_frequency_seconds', seconds);
  }

  CoachMode get mode => _mode;
  String get selectedModel => _selectedModel;
  int get messageFrequencySeconds => _messageFrequencySeconds;
  bool get isApiKeySet => _apiKey != null && _apiKey!.isNotEmpty;

  /// API bağlantısını test et
  Future<Map<String, dynamic>> testApiConnection() async {
    if (!isApiKeySet) {
      return {
        'success': false,
        'message': 'API key girilmemiş',
      };
    }

    try {
      final response = await http.post(
        Uri.parse(_apiUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_apiKey',
          'HTTP-Referer': 'https://spinning-workout-app.com',
          'X-Title': 'Spinning Workout App',
        },
        body: jsonEncode({
          'model': _selectedModel,
          'messages': [
            {'role': 'user', 'content': 'Merhaba! Bu bir test mesajıdır. Lütfen "Bağlantı başarılı!" diye yanıt ver.'}
          ],
          'max_tokens': 50,
        }),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        print('API Response: ${response.body}'); // Debug

        String responseText = 'Yanıt yok';
        if (data['choices'] != null && data['choices'].isNotEmpty) {
          final choice = data['choices'][0];
          if (choice['message'] != null && choice['message']['content'] != null) {
            responseText = choice['message']['content'].toString().trim();
          }
        }

        return {
          'success': true,
          'message': 'API bağlantısı başarılı! ✅',
          'model': _selectedModel,
          'response': responseText,
        };
      } else {
        final error = jsonDecode(response.body);
        return {
          'success': false,
          'message': 'API hatası: ${error['error']?['message'] ?? response.statusCode}',
          'statusCode': response.statusCode,
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Bağlantı hatası: ${e.toString()}',
      };
    }
  }

  /// Mesaj oluştur (kategori bazlı)
  Future<CoachMessage?> generateMessage({
    required CoachContext context,
    required WorkoutMetrics metrics,  // Yeni parametre
    CoachMessageType? forceType,
    MessageCategory? category,  // Yeni parametre
  }) async {
    // Kapalıysa sadece segment bilgilendirmeleri göster
    if (_mode == CoachMode.off) {
      // Sadece segment başlangıç/bitiş bilgilendirmeleri
      if (forceType == CoachMessageType.segmentStart ||
          forceType == CoachMessageType.segmentEnd) {
        return _generateSegmentInfoMessage(context, forceType!);
      }
      // Diğer tüm mesajları engelle (tarihçe, güncel olaylar, motivasyon vs.)
      return null;
    }

    // Çok sık mesaj gönderme kontrolü
    // Segment başlangıç/bitiş mesajları her zaman gösterilir
    if (forceType != CoachMessageType.segmentStart &&
        forceType != CoachMessageType.segmentEnd &&
        _lastMessageTime != null) {
      final timeSinceLastMessage = DateTime.now().difference(_lastMessageTime!);
      // Normal mesajlar için ayarlanan frekans kadar ara
      if (timeSinceLastMessage.inSeconds < _messageFrequencySeconds) {
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
        message = await _generateAIMessage(context, metrics, forceType, category);
      } catch (e) {
        print('AI mesaj hatası, kural bazlıya geçiliyor: $e');
        // Fallback: Kural bazlı
        message = _generateRuleBasedMessage(context, forceType, category);
      }
    } else {
      // Kural bazlı
      message = _generateRuleBasedMessage(context, forceType, category);
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

  /// Sadece segment bilgilendirme mesajı (Coach kapalıyken)
  CoachMessage _generateSegmentInfoMessage(CoachContext context, CoachMessageType type) {
    String message;

    if (type == CoachMessageType.segmentStart) {
      final duration = (context.segmentDurationSeconds / 60).toInt();
      message = '${context.segmentName} başlıyor! ${duration}dk, ${context.targetPower.toInt()}W';
    } else {
      final remaining = context.segmentDurationSeconds - context.segmentElapsedSeconds;
      if (remaining < 30) {
        message = 'Son ${remaining} saniye!';
      } else {
        message = 'Son 1 dakika!';
      }
    }

    return CoachMessage(
      message: message,
      type: type,
      category: MessageCategory.technicalFeedback,
    );
  }

  /// OpenRouter API ile mesaj oluştur (kategori bazlı)
  Future<CoachMessage> _generateAIMessage(
    CoachContext context,
    WorkoutMetrics metrics,
    CoachMessageType? forceType,
    MessageCategory? category,
  ) async {
    // Kategori belirtilmemişse otomatik seç
    final selectedCategory = category ?? _selectCategory();

    final systemPrompt = _buildSystemPrompt(selectedCategory);
    final userPrompt = _buildUserPrompt(context, metrics, selectedCategory);

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
            'content': systemPrompt,
          },
          {
            'role': 'user',
            'content': userPrompt,
          },
        ],
        'max_tokens': _getMaxTokens(selectedCategory),
        'temperature': 0.7,
        'stop': ['\n\n', '...', ' -'],  // Yarım cümle engelleme
      }),
    ).timeout(const Duration(seconds: 5));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final messageText = data['choices'][0]['message']['content'].trim();

      return CoachMessage(
        message: messageText,
        type: forceType ?? _determineMessageType(context),
        category: selectedCategory,
      );
    } else {
      throw Exception('API error: ${response.statusCode}');
    }
  }

  /// Kategori bazlı system prompt oluştur
  String _buildSystemPrompt(MessageCategory category) {
    switch (category) {
      case MessageCategory.technicalFeedback:
        return 'Sen bilimsel araştırmalara dayanan profesyonel bisiklet antrenörüsün.\n'
            'ÖNEMLİ KURALLAR:\n'
            '1. WORKOUT HEDEF DEĞERLERİNİ DİKKATE AL - Hedef kadans 80 rpm ise, 90 rpm yapmasını söyleyemezsin!\n'
            '2. Sadece workout parametreleri içinde tavsiyelerde bulun.\n'
            '3. Bu workout tipi için bilimsel araştırma bulgularını paylaş.\n'
            '4. Teknik tavsiye ver: Kadans, güç, nefes, pedal tekniği, pozisyon.\n'
            '5. Mesaj uzunluğu serbest, kullanıcı scroll edebilir.\n'
            '6. Cümleleri MUTLAKA tamamla, yarım bırakma.\n'
            '\nÖrnek: "HIIT antremanları için 2019 Journal of Applied Physiology araştırması, 30 saniyelik maksimum eforların VO2 max artışında etkili olduğunu gösterdi. Hedef kadansını korumaya çalış!"';

      case MessageCategory.cyclingHistory:
        return 'Bisiklet tarihçisi ve spor yazarısın.\n'
            'Enteresan bisiklet tarihi bilgisi ver: Yarışlar, tırmanışlar, rekorlar, efsane bisikletçiler.\n'
            'Mesaj uzunluğu serbest. Cümlelerini tamamla.';

      case MessageCategory.currentEvents:
        return 'Bisiklet gazetecisisin.\n'
            'ÖNEMLİ: Bugün 2025 Kasım. Sadece 2024-2025 sezonundan DOĞRU tarihlerde olan olayları paylaş.\n'
            'Güncel yarış haberi ver: Tour, Giro, Vuelta, klasikler.\n'
            'Mesaj uzunluğu serbest. Cümlelerini tamamla.';

      case MessageCategory.motivation:
        return 'Esprili ve arkadaşça antrenörsün.\n'
            'Esprili motivasyon mesajı ver.\n'
            'Mesaj uzunluğu serbest. Cümlelerini tamamla.';
    }
  }

  /// Kategori bazlı user prompt oluştur
  String _buildUserPrompt(CoachContext context, WorkoutMetrics metrics, MessageCategory category) {
    final buffer = StringBuffer();

    switch (category) {
      case MessageCategory.technicalFeedback:
        buffer.writeln('WORKOUT TİPİ: ${metrics.workoutType.toString().split('.').last}');
        buffer.writeln('Segment: ${context.segmentName} (${context.segmentType})');
        buffer.writeln('\nMevcut Metrikler:');
        buffer.writeln('- Güç: ${metrics.currentPower.toInt()}W (Ort: ${metrics.averagePower.toInt()}W, NP: ${metrics.normalizedPower.toInt()}W)');
        buffer.writeln('- IF: ${metrics.intensityFactor.toStringAsFixed(2)}');
        buffer.writeln('- Kadans: ${metrics.currentCadence.toInt()} rpm (Ort: ${metrics.averageCadence.toInt()} rpm)');
        if (metrics.currentHeartRate != null) {
          buffer.writeln('- HR: ${metrics.currentHeartRate} bpm (Ort: ${metrics.averageHeartRate} bpm)');
        }
        buffer.writeln('\nWorkout Hedefleri (BU DEĞERLERİ AŞMA!):');
        buffer.writeln('- Hedef Güç: ${context.targetPower.toInt()}W');
        buffer.writeln('- Hedef Kadans: ${context.targetCadence} rpm');
        buffer.writeln('- Power Zone: ${context.powerZone}');
        buffer.writeln('\nGörev: Bu workout tipi için bilimsel araştırma bilgisi ver ve hedefler dahilinde teknik tavsiyelerde bulun.');
        break;

      case MessageCategory.cyclingHistory:
        buffer.writeln('Bisiklet tarihinden enteresan bir bilgi ver (yarış, tırmanış, rekor, efsane bisikletçi).');
        break;

      case MessageCategory.currentEvents:
        buffer.writeln('Bugün 2025 Kasım. 2024-2025 sezonundan güncel ve doğru tarihli yarış haberi ver.');
        break;

      case MessageCategory.motivation:
        buffer.writeln('Esprili ve arkadaşça motivasyon mesajı ver.');
        break;
    }

    return buffer.toString();
  }

  /// Kategori bazlı max token
  int _getMaxTokens(MessageCategory category) {
    switch (category) {
      case MessageCategory.technicalFeedback:
        return 300;  // Bilimsel araştırma + teknik tavsiyeleri için uzun mesajlar
      case MessageCategory.cyclingHistory:
      case MessageCategory.currentEvents:
        return 150;  // Tarih ve güncel olaylar için orta uzunluk
      case MessageCategory.motivation:
        return 100;  // Motivasyon için kısa-orta uzunluk
    }
  }

  /// Rastgele kategori seç (dağılım: %85 teknik, %5 tarih, %5 güncel, %5 motivasyon)
  MessageCategory _selectCategory() {
    final random = Random();
    final value = random.nextInt(100);
    if (value < 85) return MessageCategory.technicalFeedback;
    if (value < 90) return MessageCategory.cyclingHistory;
    if (value < 95) return MessageCategory.currentEvents;
    return MessageCategory.motivation;
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

  /// Kural bazlı mesaj oluştur (kategori bazlı)
  CoachMessage _generateRuleBasedMessage(
    CoachContext context,
    CoachMessageType? forceType,
    MessageCategory? category,
  ) {
    final type = forceType ?? _determineMessageType(context);
    final selectedCategory = category ?? _selectCategory();
    final message = _selectRuleBasedMessage(context, type, selectedCategory);

    return CoachMessage(
      message: message,
      type: type,
      category: selectedCategory,
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

  /// Kural bazlı mesaj seç (kategori bazlı)
  String _selectRuleBasedMessage(CoachContext context, CoachMessageType type, MessageCategory category) {
    final random = Random();

    // Segment mesajları kategori gözetmez
    if (type == CoachMessageType.segmentStart) {
      final duration = (context.segmentDurationSeconds / 60).toInt();
      return '${context.segmentName} başlıyor! ${duration}dk, ${context.targetPower.toInt()}W';
    }

    if (type == CoachMessageType.segmentEnd) {
      final remaining = context.segmentDurationSeconds - context.segmentElapsedSeconds;
      if (remaining < 30) {
        return 'Son ${remaining} saniye! Bastır!';
      }
      return 'Son 1 dakika!';
    }

    // Warning mesajları kategori gözetmez
    if (type == CoachMessageType.warning) {
      if (context.currentHeartRate != null && context.maxHeartRate != null) {
        final hrPercentage = (context.currentHeartRate! / context.maxHeartRate!) * 100;
        if (hrPercentage > 95) {
          return 'Nabız çok yüksek! Yavaşla!';
        }
      }
      if (context.currentCadence < 60) {
        return 'Kadans düşük. ${context.targetCadence} rpm yap!';
      }
      return 'Dikkat! Tempoyu kontrol et.';
    }

    // Kategori bazlı mesajlar
    switch (category) {
      case MessageCategory.technicalFeedback:
        return _getTechnicalMessage(context);

      case MessageCategory.cyclingHistory:
        return _getCyclingHistoryMessage(random);

      case MessageCategory.currentEvents:
        return _getCurrentEventsMessage(random);

      case MessageCategory.motivation:
        return _getMotivationMessage(random);
    }
  }

  /// Teknik geri bildirim mesajları
  String _getTechnicalMessage(CoachContext context) {
    final random = Random();
    final powerPercentage = (context.currentPower / context.ftp * 100).toInt();

    // Güç bölgesi bazlı teknik mesajlar
    if (powerPercentage > 105) {
      final messages = [
        'VO2 Max: Kadansı düşürme, ayakta kal!',
        'VO2 Max: Derin nefes, ritim bozma!',
        'Maksimum güç: Core sıkı, omuz gevşek!',
      ];
      return messages[random.nextInt(messages.length)];
    } else if (powerPercentage > 90) {
      final messages = [
        'Threshold: Derin nefes, sabit tempo!',
        'FTP bölgesi: Kadans yüksek tut!',
        'Eşik: Konuşamıyorsan doğru yoldasın!',
      ];
      return messages[random.nextInt(messages.length)];
    } else if (powerPercentage > 75) {
      final messages = [
        'Tempo: Konuşabileceğin ritimde!',
        'Tempo: Kadans 90+ rpm ideal!',
        'Sürdürülebilir tempo, güzel!',
      ];
      return messages[random.nextInt(messages.length)];
    } else if (powerPercentage > 55) {
      final messages = [
        'Endurance: Yağ yak, kadans yüksek!',
        'Z2: Aerobik temel, sabırlı ol!',
        'Dayanıklılık: Burnu doldurup ağzından ver!',
      ];
      return messages[random.nextInt(messages.length)];
    }

    // Recovery
    final messages = [
      'Recovery: Aktif toparlan, gevşe!',
      'Toparlanma: Kadans hafif, kas temizle!',
      'Düşük güç: Bacak salla, laktik at!',
    ];
    return messages[random.nextInt(messages.length)];
  }

  /// Bisiklet tarihçesi mesajları
  String _getCyclingHistoryMessage(Random random) {
    final messages = [
      'İlk Tour de France 1903\'te 2428 km idi!',
      'Eddy Merckx "Yamyam" lakabıyla 5 Tour kazandı.',
      'Alpe d\'Huez: 21 viraj, 13.8 km, %8.1 eğim.',
      'Lance Armstrong\'un 7 Tour zaferi iptal edildi.',
      'Fausto Coppi ilk Giro-Tour çift kazananı.',
      'Mont Ventoux "Kel Dağ" - rüzgar 90 km/h!',
      '1989 Tour: Greg LeMond 8 saniye farkla kazandı.',
      'İlk kadın profesyonel: Alfonsina Strada, 1924.',
      'Pinarello Dogma: 980 gram, karbon harikası!',
      'Chris Froome 4 Tour de France kazandı.',
    ];
    return messages[random.nextInt(messages.length)];
  }

  /// Güncel yarış/medya mesajları (2024-2025 sezonu)
  String _getCurrentEventsMessage(Random random) {
    final messages = [
      'Pogačar 2024\'te tarihi Giro+Tour çift tacını aldı!',
      'Remco Evenepoel 2024 Vuelta şampiyonu oldu!',
      '2024 Tour de France: Pogačar Nice\'te üçüncü kez şampiyon!',
      '2025 Tour de France 5 Temmuz\'da Grand Départ yapacak!',
      '2025 Giro d\'Italia 9 Mayıs - 1 Haziran tarihleri arasında!',
      'Mathieu van der Poel 2024 Paris-Roubaix\'yi kazandı!',
      'Wout van Aert 2024\'te sakatlıktan döndü!',
      'Primož Roglič 2024 Vuelta\'da 4. şampiyonluğunu hedefliyor!',
      'Jonas Vingegaard 2024\'te sakatlıktan sonra Tour\'da 2. oldu!',
      'Tadej Pogačar UAE Team Emirates\'te 2025 için hazırlanıyor!',
    ];
    return messages[random.nextInt(messages.length)];
  }

  /// Motivasyon/espri mesajları
  String _getMotivationMessage(Random random) {
    final messages = [
      'Bu segmenti geçersen şampiyonsun!',
      'Bu antremanı bitirirsen çay ısmarlarım!',
      'Pedallarına Pogačar gibi bas, şampiyon!',
      'Son 5 dakika! Froome gibi tırman!',
      'Kadansı tut, yoksa bisiklet seni bırakır!',
      'Nabzını kontrol et, Contador değilsin!',
      'Bu tempo ile Tour kazanırsın... belki!',
      'Güç yok mu? Kahve iç, gel devam et!',
      'Son viraj! Van Aert gibi sprint at!',
      'Vazgeçme! Pantani da böyle tırmanırdı!',
    ];
    return messages[random.nextInt(messages.length)];
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
