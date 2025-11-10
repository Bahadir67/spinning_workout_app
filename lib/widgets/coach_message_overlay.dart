import 'dart:collection';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/coach_message.dart';

/// AI Coach mesajlarını gösteren overlay widget
class CoachMessageOverlay extends StatefulWidget {
  final CoachMessage? message;
  final VoidCallback? onDismiss;
  final Duration displayDuration;

  const CoachMessageOverlay({
    super.key,
    this.message,
    this.onDismiss,
    this.displayDuration = const Duration(seconds: 8),
  });

  @override
  State<CoachMessageOverlay> createState() => _CoachMessageOverlayState();
}

class _CoachMessageOverlayState extends State<CoachMessageOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  FlutterTts? _tts;
  String? _lastSpokenMessage;
  bool _isSpeaking = false;
  bool _isShowing = false;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );

    // TTS başlat
    _initTts();

    if (widget.message != null) {
      _showMessage();
    }
  }

  Future<void> _initTts() async {
    _tts = FlutterTts();
    await _tts!.setLanguage('tr-TR');

    // Kaydedilmiş ses ayarlarını yükle
    try {
      final prefs = await SharedPreferences.getInstance();

      // Ses parametrelerini yükle (varsayılanlar: rate=0.55, pitch=1.0, volume=1.0)
      final savedRate = prefs.getDouble('tts_rate') ?? 0.55;
      final savedPitch = prefs.getDouble('tts_pitch') ?? 1.0;
      final savedVolume = prefs.getDouble('tts_volume') ?? 1.0;

      await _tts!.setSpeechRate(savedRate);
      await _tts!.setPitch(savedPitch);
      await _tts!.setVolume(savedVolume);

      // Kaydedilmiş sesi yükle (varsa)
      final savedVoiceName = prefs.getString('tts_voice_name');
      final savedVoiceLocale = prefs.getString('tts_voice_locale');

      if (savedVoiceName != null && savedVoiceLocale != null) {
        await Future.delayed(const Duration(milliseconds: 300));
        await _tts!.setVoice({"name": savedVoiceName, "locale": savedVoiceLocale});
      }
    } catch (e) {
      // Hata varsa varsayılan değerleri kullan
      await _tts!.setSpeechRate(0.55);
      await _tts!.setPitch(1.0);
      await _tts!.setVolume(1.0);
    }

    // TTS completion callbacks
    _tts!.setCompletionHandler(() {
      if (mounted) {
        setState(() {
          _isSpeaking = false;
        });
      }
    });

    _tts!.setStartHandler(() {
      if (mounted) {
        setState(() {
          _isSpeaking = true;
        });
      }
    });

    _tts!.setErrorHandler((msg) {
      if (mounted) {
        setState(() {
          _isSpeaking = false;
        });
      }
    });
  }

  @override
  void didUpdateWidget(CoachMessageOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Yeni mesaj geldi mi ve şu an konuşmuyor mu?
    if (widget.message != null &&
        widget.message != oldWidget.message &&
        widget.message!.message != _lastSpokenMessage &&
        !_isSpeaking &&
        !_isShowing) {
      _showMessage();
    }
  }

  Future<void> _showMessage() async {
    if (widget.message == null || _isShowing) return;

    _isShowing = true;

    // Animasyon başlat
    _controller.forward(from: 0);

    // Segment mesajları için özel süre (daha kısa)
    final isSegmentMessage = widget.message!.type == CoachMessageType.segmentStart ||
                             widget.message!.type == CoachMessageType.segmentEnd;

    Duration displayDuration;

    if (isSegmentMessage) {
      // Segment mesajları: Mesaj uzunluğuna göre, minimum 6 saniye, maksimum 12 saniye
      final messageLength = widget.message!.message.length;
      final estimatedTtsDuration = (messageLength / 8).ceil();
      displayDuration = Duration(
        seconds: (estimatedTtsDuration + 2).clamp(6, 12),
      );
    } else {
      // Normal mesajlar: Mesaj uzunluğuna göre dinamik süre
      // TTS hızı 0.5 olduğu için, Türkçe'de ortalama 4 karakter/saniye
      // + Okuma için ekstra %50 süre
      final messageLength = widget.message!.message.length;
      final estimatedTtsDuration = (messageLength / 4).ceil();
      final readingBuffer = (estimatedTtsDuration * 0.5).ceil();
      displayDuration = Duration(
        seconds: (estimatedTtsDuration + readingBuffer).clamp(15, 90),  // Min 15s, Max 90s
      );
    }

    // Sesli oku
    if (_tts != null && widget.message!.message != _lastSpokenMessage) {
      _lastSpokenMessage = widget.message!.message;
      _isSpeaking = true;
      try {
        // Emojileri ve özel karakterleri temizle
        final cleanText = _cleanTextForTTS(widget.message!.message);

        await _tts!.speak(cleanText);
      } catch (e) {
        print('TTS hatası: $e');
        _isSpeaking = false;
      }
    }

    // TTS'in bitmesini bekle (completion handler _isSpeaking'i false yapacak)
    // Maksimum displayDuration kadar bekle, ama TTS biterse erken çık
    final startTime = DateTime.now();
    while (_isSpeaking && DateTime.now().difference(startTime) < displayDuration) {
      await Future.delayed(const Duration(milliseconds: 100));
    }

    // TTS bittikten sonra kullanıcının okuyabilmesi için 3 saniye daha bekle
    if (mounted) {
      await Future.delayed(const Duration(seconds: 3));
    }

    // Otomatik kapat
    if (mounted) {
      await _hideMessage();
    }

    _isShowing = false;
  }

  /// Metni TTS için temizle (emoji, markdown ve özel karakterleri çıkar)
  String _cleanTextForTTS(String text) {
    // Emoji regex pattern (tüm emoji aralıklarını kapsar)
    final emojiRegex = RegExp(
      r'[\u{1F600}-\u{1F64F}]|' // Emoticons
      r'[\u{1F300}-\u{1F5FF}]|' // Symbols & Pictographs
      r'[\u{1F680}-\u{1F6FF}]|' // Transport & Map
      r'[\u{1F700}-\u{1F77F}]|' // Alchemical
      r'[\u{1F780}-\u{1F7FF}]|' // Geometric Shapes Extended
      r'[\u{1F800}-\u{1F8FF}]|' // Supplemental Arrows-C
      r'[\u{1F900}-\u{1F9FF}]|' // Supplemental Symbols and Pictographs
      r'[\u{1FA00}-\u{1FA6F}]|' // Chess Symbols
      r'[\u{1FA70}-\u{1FAFF}]|' // Symbols and Pictographs Extended-A
      r'[\u{2600}-\u{26FF}]|'   // Miscellaneous Symbols
      r'[\u{2700}-\u{27BF}]',   // Dingbats
      unicode: true,
    );

    // Emojileri temizle
    String cleaned = text.replaceAll(emojiRegex, '');

    // Markdown formatlarını temizle
    cleaned = cleaned.replaceAll(RegExp(r'\*\*'), '');  // Bold (**text**)
    cleaned = cleaned.replaceAll(RegExp(r'\*'), '');    // Italic (*text*)
    cleaned = cleaned.replaceAll(RegExp(r'__'), '');    // Bold (__text__)
    cleaned = cleaned.replaceAll(RegExp(r'_'), '');     // Italic (_text_)
    cleaned = cleaned.replaceAll(RegExp(r'~~'), '');    // Strikethrough (~~text~~)
    cleaned = cleaned.replaceAll(RegExp(r'`'), '');     // Code (`text`)
    cleaned = cleaned.replaceAll(RegExp(r'#+ '), '');   // Headers (# Header)

    // Birden fazla boşluğu teke indir
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ');

    // Baş ve sondaki boşlukları temizle
    cleaned = cleaned.trim();

    return cleaned;
  }

  Future<void> _hideMessage() async {
    // TTS'i durdur
    _isSpeaking = false;
    try {
      await _tts?.stop();
    } catch (e) {
      print('TTS durdurma hatası: $e');
    }

    await _controller.reverse();
    if (mounted) {
      widget.onDismiss?.call();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _tts?.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.message == null) {
      return const SizedBox.shrink();
    }

    return Positioned(
      top: 16,
      left: 16,
      right: 16,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: SlideTransition(
          position: _slideAnimation,
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.85),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: widget.message!.color.withOpacity(0.5),
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: widget.message!.color.withOpacity(0.3),
                    blurRadius: 12,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // AI Badge (eğer AI mesajı ise)
                  if (widget.message!.isAIGenerated)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.purple.shade700,
                            Colors.blue.shade600,
                          ],
                        ),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.purple.withOpacity(0.5),
                            blurRadius: 8,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.psychology,
                            color: Colors.white,
                            size: 16,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'AI Coach',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Mesaj içeriği
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // İkon
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: widget.message!.color.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            widget.message!.icon,
                            color: widget.message!.color,
                            size: 28,
                          ),
                        ),
                        const SizedBox(width: 12),

                        // Mesaj (kaydırılabilir)
                        Expanded(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 120),
                            child: SingleChildScrollView(
                              child: Text(
                                widget.message!.message,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ),
                        ),

                        // Kapat butonu
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white70),
                          iconSize: 20,
                          onPressed: _hideMessage,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ],
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
}

/// Priority-based mesaj kuyruğu sistemi
class CoachMessageManager {
  // Queue yapısı
  static final Queue<_QueuedMessage> _messageQueue = Queue();
  static OverlayEntry? _currentOverlay;
  static CoachMessage? _currentMessage;
  static DateTime? _lastMessageTime;
  static bool _isShowingMessage = false;
  static BuildContext? _context;

  static const int _maxQueueSize = 5;  // Maksimum kuyruk boyutu
  static const Duration _messageTimeout = Duration(seconds: 60);  // Mesaj geçerlilik süresi

  /// Mesaj kuyruğuna ekle (priority-based)
  static void enqueue(BuildContext context, CoachMessage message) {
    _context = context;

    // Aynı mesaj tekrar eklenmesin
    if (_currentMessage?.message == message.message) return;
    if (_messageQueue.any((q) => q.message.message == message.message)) return;

    // Mesajı priority ile kuyruğa ekle
    final queuedMessage = _QueuedMessage(
      message: message,
      timestamp: DateTime.now(),
      priority: _getPriority(message.type),
    );

    // Kuyruk dolu mu kontrol et
    if (_messageQueue.length >= _maxQueueSize) {
      // En düşük öncelikli mesajı sil
      _removeLowestPriority();
    }

    // Priority'ye göre sıralı ekle
    _insertByPriority(queuedMessage);

    // Eğer mesaj gösterilmiyorsa, hemen göster
    // (Mesaj gösteriliyorsa otomatik olarak onDismiss'te sıradaki gösterilecek)
    if (!_isShowingMessage) {
      _showNext();
    }
  }

  /// Priority hesapla (yüksek = öncelikli)
  static int _getPriority(CoachMessageType type) {
    switch (type) {
      case CoachMessageType.segmentStart:
      case CoachMessageType.segmentEnd:
        return 100;  // En yüksek öncelik
      case CoachMessageType.warning:
        return 50;   // Orta öncelik
      case CoachMessageType.motivation:
      case CoachMessageType.performance:
      case CoachMessageType.information:
        return 10;   // Normal öncelik
    }
  }

  /// Priority'ye göre sıralı ekle
  static void _insertByPriority(_QueuedMessage newMessage) {
    if (_messageQueue.isEmpty) {
      _messageQueue.add(newMessage);
      return;
    }

    // Geçici liste oluştur ve sırala
    final list = _messageQueue.toList();
    list.add(newMessage);
    list.sort((a, b) => b.priority.compareTo(a.priority));  // Yüksekten düşüğe

    // Kuyruğu yeniden oluştur
    _messageQueue.clear();
    _messageQueue.addAll(list);
  }

  /// En düşük öncelikli mesajı sil
  static void _removeLowestPriority() {
    if (_messageQueue.isEmpty) return;

    final list = _messageQueue.toList();
    list.sort((a, b) => a.priority.compareTo(b.priority));  // Düşükten yükseğe
    final toRemove = list.first;

    _messageQueue.removeWhere((m) => m == toRemove);
  }

  /// Sıradaki mesajı göster
  static Future<void> _showNext() async {
    if (_messageQueue.isEmpty || _context == null) {
      _isShowingMessage = false;
      return;
    }

    // Timeout olmuş mesajları temizle
    _cleanupExpiredMessages();

    if (_messageQueue.isEmpty) {
      _isShowingMessage = false;
      return;
    }

    // Son mesajdan bu yana geçen süreyi kontrol et
    // Mesajlar arasında minimum 2 saniye bekle
    if (_lastMessageTime != null) {
      final timeSinceLastMessage = DateTime.now().difference(_lastMessageTime!);
      if (timeSinceLastMessage.inSeconds < 2) {
        await Future.delayed(Duration(seconds: 2 - timeSinceLastMessage.inSeconds));
      }
    }

    // En öncelikli mesajı al
    final queuedMessage = _messageQueue.removeFirst();
    final message = queuedMessage.message;

    _isShowingMessage = true;
    _currentMessage = message;
    _lastMessageTime = DateTime.now();

    _currentOverlay = OverlayEntry(
      builder: (context) => CoachMessageOverlay(
        message: message,
        onDismiss: () {
          hide();
          _showNext();  // Mesaj kapandığında sıradakini göster
        },
      ),
    );

    Overlay.of(_context!).insert(_currentOverlay!);
  }

  /// Timeout olmuş mesajları temizle
  static void _cleanupExpiredMessages() {
    final now = DateTime.now();
    _messageQueue.removeWhere((m) {
      return now.difference(m.timestamp) > _messageTimeout;
    });
  }

  /// Mesajı kapat
  static void hide() {
    _currentOverlay?.remove();
    _currentOverlay = null;
    _currentMessage = null;
    _isShowingMessage = false;
  }

  /// Kuyruğu temizle
  static void clearQueue() {
    _messageQueue.clear();
    hide();
  }

  /// Kuyruk durumu (debug için)
  static int get queueLength => _messageQueue.length;
  static bool get isShowingMessage => _isShowingMessage;
}

/// Kuyruktaki mesaj wrapper'ı
class _QueuedMessage {
  final CoachMessage message;
  final DateTime timestamp;
  final int priority;

  _QueuedMessage({
    required this.message,
    required this.timestamp,
    required this.priority,
  });
}
