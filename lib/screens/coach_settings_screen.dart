import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/ai_coach_service.dart';

/// AI Coach ayarları ekranı
class CoachSettingsScreen extends StatefulWidget {
  const CoachSettingsScreen({super.key});

  @override
  State<CoachSettingsScreen> createState() => _CoachSettingsScreenState();
}

class _CoachSettingsScreenState extends State<CoachSettingsScreen> {
  final AICoachService _coachService = AICoachService();
  final TextEditingController _apiKeyController = TextEditingController();

  CoachMode _selectedMode = CoachMode.ruleBased;
  String _selectedModel = 'google/gemini-2.0-flash-001';  // Varsayılan: Hızlı, Türkçe, güncel
  int _messageFrequencySeconds = 180; // Varsayılan 3 dakika = 180 saniye

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    await _coachService.initialize();
    setState(() {
      _selectedMode = _coachService.mode;
      _selectedModel = _coachService.selectedModel;
      _messageFrequencySeconds = _coachService.messageFrequencySeconds;
    });
  }

  Future<void> _saveSettings() async {
    await _coachService.setMode(_selectedMode);
    await _coachService.setModel(_selectedModel);
    await _coachService.setFrequencySeconds(_messageFrequencySeconds);

    if (_apiKeyController.text.isNotEmpty) {
      await _coachService.setApiKey(_apiKeyController.text);
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ayarlar kaydedildi!')),
      );
      Navigator.pop(context);
    }
  }

  Future<void> _testApiConnection() async {
    // Önce geçici olarak ayarları kaydet
    if (_apiKeyController.text.isNotEmpty) {
      await _coachService.setApiKey(_apiKeyController.text);
    }
    await _coachService.setModel(_selectedModel);

    if (mounted) {
      // Loading göster
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    try {
      final result = await _coachService.testApiConnection();

      if (mounted) {
        Navigator.pop(context); // Loading kapat

        // Sonucu göster
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Row(
              children: [
                Icon(
                  result['success'] ? Icons.check_circle : Icons.error,
                  color: result['success'] ? Colors.green : Colors.red,
                ),
                const SizedBox(width: 8),
                Text(result['success'] ? 'Başarılı!' : 'Hata'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(result['message']),
                if (result['model'] != null) ...[
                  const SizedBox(height: 8),
                  Text('Model: ${result['model']}', style: const TextStyle(fontSize: 12)),
                ],
                if (result['response'] != null) ...[
                  const SizedBox(height: 8),
                  Text('Yanıt: "${result['response']}"', style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic)),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Tamam'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Loading kapat
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.error, color: Colors.red),
                SizedBox(width: 8),
                Text('Hata'),
              ],
            ),
            content: Text('Test sırasında hata: $e'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Tamam'),
              ),
            ],
          ),
        );
      }
    }
  }

  void _improveTTS() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.volume_up, color: Colors.orange),
            SizedBox(width: 8),
            Text('TTS Kalitesini İyileştir'),
          ],
        ),
        content: const SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Daha doğal ve kaliteli ses için Google Text-to-Speech yükleyin:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 16),
              Text('1. Play Store\'u aç'),
              SizedBox(height: 8),
              Text('2. "Google Text-to-Speech" ara'),
              SizedBox(height: 8),
              Text('3. Uygulamayı yükle/güncelle'),
              SizedBox(height: 8),
              Text('4. Ayarlar → Sistem → Diller ve giriş → Metin okuma'),
              SizedBox(height: 8),
              Text('5. "Google Text-to-Speech" seç'),
              SizedBox(height: 8),
              Text('6. Türkçe ses dosyasını indir'),
              SizedBox(height: 16),
              Text(
                'Sonra uygulamayı yeniden başlatın!',
                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Kapat'),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              // Play Store'da Google TTS'i aç
              final Uri url = Uri.parse('market://details?id=com.google.android.tts');
              if (await canLaunchUrl(url)) {
                await launchUrl(url);
              } else {
                // Market app yoksa web'i aç
                await launchUrl(Uri.parse('https://play.google.com/store/apps/details?id=com.google.android.tts'));
              }
            },
            icon: const Icon(Icons.open_in_new),
            label: const Text('Play Store\'da Aç'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Coach Ayarları'),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _saveSettings,
            tooltip: 'Kaydet',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Coach Modu
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.psychology, color: Colors.blue),
                      SizedBox(width: 8),
                      Text(
                        'Coach Modu',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  RadioListTile<CoachMode>(
                    title: const Text('Kapalı'),
                    subtitle: const Text('AI Coach mesajları gösterilmez'),
                    value: CoachMode.off,
                    groupValue: _selectedMode,
                    onChanged: (value) {
                      setState(() => _selectedMode = value!);
                    },
                  ),
                  RadioListTile<CoachMode>(
                    title: const Text('Kural Bazlı'),
                    subtitle: const Text('Offline çalışır, ücretsiz'),
                    value: CoachMode.ruleBased,
                    groupValue: _selectedMode,
                    onChanged: (value) {
                      setState(() => _selectedMode = value!);
                    },
                  ),
                  RadioListTile<CoachMode>(
                    title: const Text('AI Destekli'),
                    subtitle: const Text('OpenRouter API (internet gerekli)'),
                    value: CoachMode.aiPowered,
                    groupValue: _selectedMode,
                    onChanged: (value) {
                      setState(() => _selectedMode = value!);
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // AI Model Seçimi (sadece AI mode'da)
          if (_selectedMode == CoachMode.aiPowered) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.memory, color: Colors.purple),
                        SizedBox(width: 8),
                        Text(
                          'AI Modeli',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      value: _selectedModel,
                      decoration: const InputDecoration(
                        labelText: 'Model Seç',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        // ⭐ EN İYİ TAVSİYELER (Coaching İçin)
                        const DropdownMenuItem<String>(
                          value: 'anthropic/claude-3.5-sonnet',
                          child: Text('Claude 3.5 Sonnet ⭐ (Mükemmel coaching, Türkçe iyi)'),
                        ),
                        const DropdownMenuItem<String>(
                          value: 'google/gemini-2.0-flash-001',
                          child: Text('Gemini 2.0 Flash ⭐ (Hızlı, güncel bilgi, Türkçe)'),
                        ),
                        const DropdownMenuItem<String>(
                          value: 'qwen/qwen-2.5-72b-instruct',
                          child: Text('Qwen 2.5 72B ⭐ (Çok ucuz, Türkçe iyi)'),
                        ),

                        // Anthropic Claude Serisi
                        const DropdownMenuItem<String>(
                          value: 'anthropic/claude-haiku-4.5',
                          child: Text('Claude Haiku 4.5 (Hızlı, ucuz, thinking)'),
                        ),
                        const DropdownMenuItem<String>(
                          value: 'anthropic/claude-3-opus',
                          child: Text('Claude 3 Opus (En güçlü, pahalı)'),
                        ),

                        // Google Gemini Serisi
                        const DropdownMenuItem<String>(
                          value: 'google/gemini-2.5-flash-preview-09-2025',
                          child: Text('Gemini 2.5 Flash (1M context, thinking)'),
                        ),
                        const DropdownMenuItem<String>(
                          value: 'google/gemini-pro-1.5',
                          child: Text('Gemini Pro 1.5 (Güçlü, detaylı)'),
                        ),

                        // OpenAI GPT Serisi
                        const DropdownMenuItem<String>(
                          value: 'openai/gpt-4o-mini',
                          child: Text('GPT-4o Mini (Ucuz, hızlı, dengeli)'),
                        ),
                        const DropdownMenuItem<String>(
                          value: 'openai/gpt-4o',
                          child: Text('GPT-4o (Güçlü, genel bilgi)'),
                        ),
                        const DropdownMenuItem<String>(
                          value: 'openai/o1-mini',
                          child: Text('O1 Mini (Reasoning odaklı)'),
                        ),

                        // Qwen Serisi (Alibaba - Türkçe İyi)
                        const DropdownMenuItem<String>(
                          value: 'qwen/qwen-turbo',
                          child: Text('Qwen Turbo (Hızlı, Türkçe destekli)'),
                        ),
                        const DropdownMenuItem<String>(
                          value: 'qwen/qwen-max',
                          child: Text('Qwen Max (En güçlü, translation iyi)'),
                        ),

                        // DeepSeek Serisi (Çok Ucuz)
                        const DropdownMenuItem<String>(
                          value: 'deepseek/deepseek-chat',
                          child: Text('DeepSeek Chat (Çok ucuz, reasoning)'),
                        ),
                        const DropdownMenuItem<String>(
                          value: 'deepseek/deepseek-v3',
                          child: Text('DeepSeek v3 (Yeni, güçlü)'),
                        ),

                        // Meta Llama Serisi (Ücretsiz)
                        const DropdownMenuItem<String>(
                          value: 'meta-llama/llama-3.1-405b-instruct:free',
                          child: Text('Llama 3.1 405B (Ücretsiz, güçlü)'),
                        ),
                        const DropdownMenuItem<String>(
                          value: 'meta-llama/llama-3.2-90b-vision-instruct:free',
                          child: Text('Llama 3.2 90B (Ücretsiz, genel)'),
                        ),

                        // Ücretsiz Alternatifler
                        const DropdownMenuItem<String>(
                          value: 'minimax/minimax-m2:free',
                          child: Text('Minimax M2 (Ücretsiz, coding agent)'),
                        ),
                        const DropdownMenuItem<String>(
                          value: 'meituan/longcat-flash-chat:free',
                          child: Text('LongCat Flash (Ücretsiz, multi-language)'),
                        ),
                        const DropdownMenuItem<String>(
                          value: 'openrouter/polaris-alpha',
                          child: Text('Polaris Alpha (Ücretsiz, genel)'),
                        ),

                        // Ultra Budget (Süper Ucuz)
                        const DropdownMenuItem<String>(
                          value: 'nvidia/nemotron-nano-9b-v2',
                          child: Text('Nvidia Nemotron Nano (100x ucuz, reasoning)'),
                        ),
                      ],
                      onChanged: (value) {
                        setState(() => _selectedModel = value!);
                      },
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _apiKeyController,
                      decoration: InputDecoration(
                        labelText: 'OpenRouter API Key',
                        hintText: 'sk-or-v1-...',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.info_outline),
                          onPressed: () {
                            showDialog(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: const Text('OpenRouter API Key'),
                                content: const Text(
                                  'OpenRouter API key almak için:\n\n'
                                  '1. https://openrouter.ai adresine git\n'
                                  '2. Kayıt ol / Giriş yap\n'
                                  '3. "Keys" bölümünden API key oluştur\n'
                                  '4. Key\'i buraya yapıştır\n\n'
                                  'İlk \$5 ücretsiz kredi veriliyor!',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(context),
                                    child: const Text('Tamam'),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                      obscureText: true,
                    ),
                    const SizedBox(height: 16),
                    // Test API Connection Button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _testApiConnection,
                        icon: const Icon(Icons.cloud_sync),
                        label: const Text('API Bağlantısını Test Et'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    // TTS İyileştirme Bölümü
                    const Divider(),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        const Icon(Icons.record_voice_over, color: Colors.orange),
                        const SizedBox(width: 8),
                        const Text(
                          'Ses Kalitesi',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Daha iyi ses kalitesi için Google TTS yükleyin:',
                      style: TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _improveTTS,
                        icon: const Icon(Icons.volume_up),
                        label: const Text('TTS İyileştir (Google TTS)'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Mesaj Sıklığı
          if (_selectedMode != CoachMode.off) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.schedule, color: Colors.orange),
                        SizedBox(width: 8),
                        Text(
                          'Mesaj Sıklığı',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _messageFrequencySeconds == 20
                          ? '20 saniyede bir mesaj'
                          : 'Her ${_messageFrequencySeconds ~/ 60} dakikada bir mesaj',
                      style: const TextStyle(fontSize: 16),
                    ),
                    Slider(
                      value: _getSliderValue().toDouble(),
                      min: 0,
                      max: 10,
                      divisions: 10,
                      label: _getSliderLabel(),
                      onChanged: (value) {
                        setState(() => _messageFrequencySeconds = _getSecondsFromSlider(value.toInt()));
                      },
                    ),
                    const Text(
                      '* Segment başlangıç/bitiş ve uyarılar her zaman gösterilir',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),
          ],

          const SizedBox(height: 24),

          // Bilgi Kutusu
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blue.withOpacity(0.3)),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.info, color: Colors.blue),
                    SizedBox(width: 8),
                    Text(
                      'AI Coach Nasıl Çalışır?',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 12),
                Text(
                  'AI Coach, antrenman sırasında:\n\n'
                  '• Kalp hızınızı ve güç verilerinizi analiz eder\n'
                  '• Performansınız hakkında bilgi verir\n'
                  '• Bilimsel tavsiyeler sunar\n'
                  '• Motivasyon mesajları gönderir\n'
                  '• Segment değişimlerinde bilgilendirme yapar\n\n'
                  'Mesajlar ekranda görünür ve sesli olarak okunur.',
                  style: TextStyle(height: 1.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Slider helper metodları
  int _getSliderValue() {
    if (_messageFrequencySeconds == 20) return 0;
    return _messageFrequencySeconds ~/ 60; // Dakikaya çevir
  }

  String _getSliderLabel() {
    if (_messageFrequencySeconds == 20) return '20sn';
    return '${_messageFrequencySeconds ~/ 60}dk';
  }

  int _getSecondsFromSlider(int sliderValue) {
    if (sliderValue == 0) return 20;
    return sliderValue * 60; // Dakikayı saniyeye çevir
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    super.dispose();
  }
}
