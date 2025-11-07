import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../models/coach_message.dart';

/// AI Coach mesajlarını gösteren overlay widget
class CoachMessageOverlay extends StatefulWidget {
  final CoachMessage? message;
  final VoidCallback? onDismiss;
  final Duration displayDuration;

  const CoachMessageOverlay({
    Key? key,
    this.message,
    this.onDismiss,
    this.displayDuration = const Duration(seconds: 8),
  }) : super(key: key);

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

  @override
  void didUpdateWidget(CoachMessageOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Yeni mesaj geldi mi?
    if (widget.message != null &&
        widget.message != oldWidget.message &&
        widget.message!.message != _lastSpokenMessage) {
      _showMessage();
    }
  }

  Future<void> _initTts() async {
    _tts = FlutterTts();
    await _tts!.setLanguage('tr-TR');
    await _tts!.setPitch(1.0);
    await _tts!.setSpeechRate(0.5);
  }

  Future<void> _showMessage() async {
    if (widget.message == null) return;

    // Animasyon başlat
    _controller.forward(from: 0);

    // Sesli oku
    if (_tts != null && widget.message!.message != _lastSpokenMessage) {
      _lastSpokenMessage = widget.message!.message;
      try {
        await _tts!.speak(widget.message!.message);
      } catch (e) {
        print('TTS hatası: $e');
      }
    }

    // Otomatik kapat
    Future.delayed(widget.displayDuration, () {
      if (mounted) {
        _hideMessage();
      }
    });
  }

  Future<void> _hideMessage() async {
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
              child: Row(
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

                  // Mesaj
                  Expanded(
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
          ),
        ),
      ),
    );
  }
}

/// Basit kullanım için overlay manager
class CoachMessageManager {
  static OverlayEntry? _currentOverlay;
  static CoachMessage? _currentMessage;

  /// Mesaj göster
  static void show(BuildContext context, CoachMessage message) {
    // Aynı mesaj tekrar gösterilmesin
    if (_currentMessage?.message == message.message) return;

    // Önceki mesajı kapat
    hide();

    _currentMessage = message;
    _currentOverlay = OverlayEntry(
      builder: (context) => CoachMessageOverlay(
        message: message,
        onDismiss: hide,
      ),
    );

    Overlay.of(context).insert(_currentOverlay!);
  }

  /// Mesajı kapat
  static void hide() {
    _currentOverlay?.remove();
    _currentOverlay = null;
    _currentMessage = null;
  }
}
