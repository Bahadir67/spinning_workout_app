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
  String _selectedModel = 'google/gemini-2.0-flash-001';  // Varsayılan: Coaching için en iyi
  int _messageFrequencySeconds = 180; // saniye (varsayılan 3 dakika)

  // Cache (maliyet azaltma)
  final Map<String, CoachMessage> _cache = {};
  DateTime? _lastMessageTime;
  DateTime? _lastSegmentMessageTime;  // Son segment mesajı zamanı
  bool _isGeneratingMessage = false;  // Mesaj oluşturma kilidi

  /// Servisi başlat - ayarları yükle
  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    _apiKey = prefs.getString('openrouter_api_key') ?? _defaultApiKey;
    _mode = CoachMode.values[prefs.getInt('coach_mode') ?? 1]; // Default: ruleBased
    _selectedModel = prefs.getString('coach_model') ?? 'google/gemini-2.0-flash-001';
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
      ).timeout(const Duration(seconds: 60));  // Reasoning modelleri için uzun timeout

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
    required int workoutElapsedSeconds,  // Yeni: Toplam workout süresi
    CoachMessageType? forceType,
    MessageCategory? category,  // Yeni parametre
  }) async {
    // Şu anda bir mesaj oluşturuluyorsa, yeni istek yapma
    if (_isGeneratingMessage) {
      print('🔒 AI Coach: Mesaj oluşturuluyor, yeni istek engellendi');
      return null;
    }

    // KURAL 1: Coach kapalıysa hiç mesaj verme
    if (_mode == CoachMode.off) {
      return null;
    }

    // KURAL 2: İlk 3 dakika (180 saniye) AI Coach tamamen sessiz (FİX SÜRE)
    if (workoutElapsedSeconds < 180) {
      print('⏰ AI Coach: İlk 3 dakika sessiz (${workoutElapsedSeconds}s / 180s)');
      return null;
    }

    // KURAL 3: Segment sonrası 30 saniye AI Coach sessiz
    if (_lastSegmentMessageTime != null) {
      final timeSinceSegment = DateTime.now().difference(_lastSegmentMessageTime!);
      if (timeSinceSegment.inSeconds < 30) {
        print('⏰ AI Coach: Segment sonrası bekleme (${timeSinceSegment.inSeconds}s / 30s)');
        return null;
      }
    }

    // KURAL 4: Normal mesaj frekansı kontrolü (kullanıcı ayarı)
    if (_lastMessageTime != null) {
      final timeSinceLastMessage = DateTime.now().difference(_lastMessageTime!);
      if (timeSinceLastMessage.inSeconds < _messageFrequencySeconds) {
        print('⏰ AI Coach: Frekans bekleme (${timeSinceLastMessage.inSeconds}s / ${_messageFrequencySeconds}s)');
        return null;
      }
    }

    // Cache kontrolü
    final cacheKey = _generateCacheKey(context, forceType);
    if (_cache.containsKey(cacheKey)) {
      _lastMessageTime = DateTime.now();
      print('💾 AI Coach: Cache hit');
      return _cache[cacheKey];
    }

    CoachMessage? message;

    // Lock - mesaj oluşturma başladı
    _isGeneratingMessage = true;

    try {
      // AI modunda ve API key varsa
      if (_mode == CoachMode.aiPowered && isApiKeySet) {
        try {
          print('🤖 AI mesajı oluşturuluyor... (Type: ${forceType ?? "normal"})');
          message = await _generateAIMessage(context, metrics, forceType, category);
          if (message != null) {
            print('✅ AI mesajı başarılı: ${message.message.substring(0, message.message.length > 50 ? 50 : message.message.length)}...');
          }
        } catch (e) {
          print('❌ AI mesaj hatası, kural bazlıya geçiliyor: $e');
          // Fallback: Kural bazlı
          message = _generateRuleBasedMessage(context, forceType, category);
          print('📋 Kural bazlı mesaj kullanıldı: ${message?.message}');
        }
      } else {
        // Kural bazlı
        print('📋 Direkt kural bazlı mod aktif (Type: ${forceType ?? "normal"})');
        message = _generateRuleBasedMessage(context, forceType, category);
      }

      if (message != null) {
        _cache[cacheKey] = message;
        _lastMessageTime = DateTime.now();
        print('✅ AI Coach: Mesaj oluşturuldu, timer güncellendi');

        // Cache'i temizle (max 20 mesaj)
        if (_cache.length > 20) {
          _cache.clear();
        }
      }

      return message;
    } finally {
      // Unlock - mesaj oluşturma bitti
      _isGeneratingMessage = false;
    }
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
        'temperature': 0.9,  // Daha çeşitli ve yaratıcı mesajlar için
        'top_p': 0.95,
        'frequency_penalty': 0.5,  // Tekrarları azalt
        'presence_penalty': 0.3,  // Yeni konulara teşvik et
      }),
    ).timeout(const Duration(seconds: 60));  // Reasoning models için yeterli süre

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
        return '''Sen deneyimli bir bisiklet antrenörüsün. Gerçek bir koç gibi konuş.

KURALLAR:
1. WORKOUT HEDEFLERİNE UYGUN TAVSİYE - Hedef kadans 80 ise 90 söyleyemezsin!
2. TEK BİR cümle yaz. Bir fikir, bir mesaj.
3. 5-30 kelime arası olsun.
4. Cümlelerini tamamla.

FARKLI MESAJ TİPLERİ (biri seç):
- Kısa motivasyon: "Harika gidiyorsun!", "Kadansı koru, süper!", "Çok iyi!"
- Teknik tavsiye: "Kadansı yükselt, derin nefes al."
- Bilimsel bilgi: "Sweet Spot aerobik kapasitenin temelini atar."
- Performans analizi: "IF'in mükemmel, FTP'yi geliştiriyorsun!"

KONULAR:
Kadans, güç, kalp atışı, nefes, pozisyon, FTP, enerji, tempo.

HER MESAJ FARKLI OLSUN!''';

      case MessageCategory.cyclingHistory:
        return '''Sen bisiklet tarihine aşina spor yazarısın.

TEK BİR bisiklet tarihi gerçeği ver. 15-35 kelime.
Efsane tırmanışlar, yarışlar, rekorlar, bisikletçiler.

HER MESAJ FARKLI, cümleler tamamlanmış olsun.''';

      case MessageCategory.currentEvents:
        return '''Sen bisiklet gazetecisisin.

TEK BİR güncel haber ver. 15-30 kelime.
Grand Tour, Klasikler, Dünya Şampiyonası, transferler.

Bugün 2025 Kasım. Doğru tarihler ver! HER MESAJ FARKLI!''';

      case MessageCategory.motivation:
        return '''Sen esprili ve destekleyici bir antrenörsün.

TEK BİR motivasyon mesajı ver. 5-25 kelime arası.
- Bazen ÇOK KISA: "Süpersin!", "Devam et!", "İyi gidiyorsun!"
- Bazen esprili: "Bacaklar yanarsa, yağlar yanar!"
- Bazen cesaretlendirici: "Zor kısım geride kaldı, şimdi topla!"

SADECE BİR CÜMLE, liste değil. Doğal ve samimi konuş.''';
    }
  }

  /// Kategori bazlı user prompt oluştur
  String _buildUserPrompt(CoachContext context, WorkoutMetrics metrics, MessageCategory category) {
    final buffer = StringBuffer();

    switch (category) {
      case MessageCategory.technicalFeedback:
        // Durum analizi
        final powerDiff = metrics.currentPower - context.targetPower;
        final cadenceDiff = metrics.currentCadence.toInt() - context.targetCadence;

        buffer.writeln('Mevcut Durum:');
        buffer.writeln('- Güç: ${metrics.currentPower.toInt()}W / Hedef: ${context.targetPower.toInt()}W (${powerDiff > 0 ? '+' : ''}${powerDiff.toInt()}W)');
        buffer.writeln('- Kadans: ${metrics.currentCadence.toInt()} rpm / Hedef: ${context.targetCadence} rpm (${cadenceDiff > 0 ? '+' : ''}$cadenceDiff)');
        buffer.writeln('- IF: ${metrics.intensityFactor.toStringAsFixed(2)} | NP: ${metrics.normalizedPower.toInt()}W');
        if (metrics.currentHeartRate != null) {
          buffer.writeln('- Kalp: ${metrics.currentHeartRate} bpm (${context.hrZone ?? "Unknown"} zone)');
        }
        buffer.writeln('- Power Zone: ${context.powerZone}');
        buffer.writeln('');

        // Durum değerlendirmesi
        if (powerDiff.abs() < 10 && cadenceDiff.abs() < 5) {
          buffer.writeln('Durum: Performans iyi!');
        } else if (powerDiff.abs() > 20 || cadenceDiff.abs() > 10) {
          buffer.writeln('Durum: Hedeflerden sapma var.');
        } else {
          buffer.writeln('Durum: Normal.');
        }

        buffer.writeln('');
        buffer.writeln('Görev: Genel mesaj ver (segment ile ilgisiz). Duruma uygun motivasyon veya teknik tavsiye. Her mesaj farklı!');
        break;

      case MessageCategory.cyclingHistory:
        buffer.writeln('Bir bisiklet tarihi bilgisi ver. Her seferinde farklı konu seç!');
        break;

      case MessageCategory.currentEvents:
        buffer.writeln('2024-2025 sezonundan bir yarış haberi ver. Her seferinde farklı haber!');
        break;

      case MessageCategory.motivation:
        buffer.writeln('Kısa ve samimi motivasyon mesajı ver. Bazen çok kısa (5 kelime), bazen biraz uzun. Her mesaj farklı!');
        break;
    }

    return buffer.toString();
  }

  /// Kategori bazlı max token
  int _getMaxTokens(MessageCategory category) {
    switch (category) {
      case MessageCategory.technicalFeedback:
        return 200;  // Çeşitli uzunluklar: kısa motivasyon veya orta teknik tavsiye
      case MessageCategory.cyclingHistory:
      case MessageCategory.currentEvents:
        return 120;  // Orta uzunlukta bilgi
      case MessageCategory.motivation:
        return 80;  // Kısa ve öz motivasyon
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

  /// Workout başlangıcında genel bakış ve analiz mesajı oluştur
  Future<CoachMessage?> generateWorkoutOverview({
    required String workoutName,
    required String workoutDescription,
    required int totalDurationMinutes,
    required double avgPower,
    required double normalizedPower,
    required int ftp,
    required List<String> segmentTypes,  // ['Warmup', 'SteadyState', 'Interval', 'Cooldown']
    required String workoutStructure,  // Detaylı yapı açıklaması
  }) async {
    print('🤖 generateWorkoutOverview çağrıldı. Mode: $_mode, API Key: ${isApiKeySet ? "VAR" : "YOK"}');

    // Kapalıysa veya kural bazlıysa overview verme
    if (_mode == CoachMode.off || _mode == CoachMode.ruleBased) {
      print('⚠️ Overview atlandı: Mode $_mode');
      return null;
    }

    // AI modunda ve API key varsa
    if (_mode == CoachMode.aiPowered && !isApiKeySet) {
      print('❌ Overview atlandı: API key yok!');
      return null;
    }

    // Mesaj oluşturma kilidi varsa bekle
    if (_isGeneratingMessage) {
      print('⚠️ Overview atlandı: Başka bir mesaj oluşturuluyor');
      return null;
    }

    // Lock set
    _isGeneratingMessage = true;

    try {
      final systemPrompt = '''
Sen deneyimli bir bisiklet antrenörüsün. Workout başlamadan önce kısa bir analiz yapıyorsun.

MESAJ STİLİ:
- 30-50 kelime arası, öz ve motive edici
- Workout'un ana hedefini vurgula
- Bilimsel temelleri basitçe açıkla
- Pozitif ve heyecan verici ol

KONULAR:
- Bu workout ne kazandırır? (FTP, VO2 max, dayanıklılık, güç, vb.)
- Hangi enerji sistemlerini çalıştırır?
- Beklenen fizyolojik gelişme nedir?

Cümlelerini tamamla. Samimi ve profesyonel ol.
''';

      final userPrompt = '''
Workout: $workoutName
Açıklama: $workoutDescription
Süre: $totalDurationMinutes dk | Ort Güç: ${avgPower.toInt()}W (FTP'nin ${(avgPower / ftp * 100).toInt()}%)
Yapı: ${segmentTypes.join(', ')}

$workoutStructure

Bu workout'u kısaca analiz et ve motivasyonla açıkla.
''';

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
            {'role': 'system', 'content': systemPrompt},
            {'role': 'user', 'content': userPrompt},
          ],
          'max_tokens': 500,  // Uzun açıklama için
          'temperature': 0.7,
        }),
      ).timeout(const Duration(seconds: 60));  // Reasoning models için yeterli süre

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final messageText = data['choices'][0]['message']['content'].trim();

        // Timer'ı güncelle
        _lastMessageTime = DateTime.now();

        return CoachMessage(
          message: messageText,
          type: CoachMessageType.information,
          category: MessageCategory.technicalFeedback,
        );
      }
    } catch (e) {
      print('Workout overview hatası: $e');
    } finally {
      // Unlock
      _isGeneratingMessage = false;
    }

    return null;
  }

  /// OpenAI TTS ile ses oluştur (MP3 olarak döner)
  Future<List<int>?> generateSpeech(String text) async {
    if (!isApiKeySet) {
      print('⚠️ TTS için API key yok');
      return null;
    }

    try {
      print('🔊 OpenAI TTS çağrılıyor: ${text.substring(0, 30)}...');

      final response = await http.post(
        Uri.parse('https://api.openai.com/v1/audio/speech'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_apiKey',
        },
        body: jsonEncode({
          'model': 'tts-1',  // tts-1-hd daha kaliteli ama yavaş
          'input': text,
          'voice': 'nova',  // alloy, echo, fable, onyx, nova, shimmer
          'speed': 1.0,
        }),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        print('✅ TTS başarılı: ${response.bodyBytes.length} bytes');
        return response.bodyBytes;
      } else {
        print('❌ TTS hatası: ${response.statusCode} - ${response.body}');
        return null;
      }
    } catch (e) {
      print('❌ TTS exception: $e');
      return null;
    }
  }

  /// Segment değişimini bildir (TTS anonsu yapıldığında çağrılır)
  void notifySegmentChange() {
    _lastSegmentMessageTime = DateTime.now();
    print('🔔 AI Coach: Segment değişti, 30 saniye sessiz');
  }

  /// Servisi sıfırla (yeni antrenman için)
  void reset() {
    _cache.clear();
    _lastMessageTime = null;
    _lastSegmentMessageTime = null;
    _isGeneratingMessage = false;
  }
}
