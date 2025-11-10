import 'package:flutter/material.dart';
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
  String _selectedModel = 'minimax/minimax-m2';
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
                        // Önerilen Modeller
                        const DropdownMenuItem<String>(
                          value: 'minimax/minimax-m2',
                          child: Text('Minimax M2 (Önerilen)'),
                        ),
                        const DropdownMenuItem<String>(
                          value: 'anthropic/claude-haiku-4.5',
                          child: Text('Claude Haiku 4.5 (Kaliteli & Hızlı)'),
                        ),

                        // Google Gemini Serisi
                        const DropdownMenuItem<String>(
                          value: 'google/gemini-2.5-flash-preview-09-2025',
                          child: Text('Gemini 2.5 Flash (Yeni)'),
                        ),
                        const DropdownMenuItem<String>(
                          value: 'google/gemini-2.5-flash-lite',
                          child: Text('Gemini 2.5 Flash Lite (Hızlı)'),
                        ),
                        const DropdownMenuItem<String>(
                          value: 'google/gemini-2.5-flash-lite-preview-09-2025',
                          child: Text('Gemini 2.5 Flash Lite Preview'),
                        ),
                        const DropdownMenuItem<String>(
                          value: 'google/gemini-2.5-flash-lite-preview-06-17',
                          child: Text('Gemini 2.5 Flash Lite (06-17)'),
                        ),

                        // OpenAI GPT Serisi
                        const DropdownMenuItem<String>(
                          value: 'openai/gpt-5-mini',
                          child: Text('GPT-5 Mini (Yeni)'),
                        ),
                        const DropdownMenuItem<String>(
                          value: 'openai/gpt-5-nano',
                          child: Text('GPT-5 Nano (Ultra Hızlı)'),
                        ),
                        const DropdownMenuItem<String>(
                          value: 'openai/gpt-oss-120b',
                          child: Text('GPT OSS 120B'),
                        ),
                        const DropdownMenuItem<String>(
                          value: 'openai/gpt-4.1-mini',
                          child: Text('GPT-4.1 Mini'),
                        ),
                        const DropdownMenuItem<String>(
                          value: 'openai/gpt-4o-mini',
                          child: Text('GPT-4o Mini (Ucuz)'),
                        ),

                        // DeepSeek Serisi
                        const DropdownMenuItem<String>(
                          value: 'deepseek/deepseek-v3.2-exp',
                          child: Text('DeepSeek v3.2 (Deneysel)'),
                        ),
                        const DropdownMenuItem<String>(
                          value: 'deepseek/deepseek-v3.1-terminus',
                          child: Text('DeepSeek v3.1 Terminus'),
                        ),

                        // Meta Llama Serisi
                        const DropdownMenuItem<String>(
                          value: 'meta-llama/llama-4-maverick',
                          child: Text('Llama 4 Maverick'),
                        ),
                        const DropdownMenuItem<String>(
                          value: 'meta-llama/llama-4-maverick:free',
                          child: Text('Llama 4 Maverick (Ücretsiz)'),
                        ),
                        const DropdownMenuItem<String>(
                          value: 'meta-llama/llama-3.3-70b-instruct',
                          child: Text('Llama 3.3 70B'),
                        ),

                        // Diğer Modeller
                        const DropdownMenuItem<String>(
                          value: 'mistralai/voxtral-small-24b-2507',
                          child: Text('Mistral Voxtral 24B'),
                        ),
                        const DropdownMenuItem<String>(
                          value: 'qwen/qwen3-vl-8b-instruct',
                          child: Text('Qwen3 VL 8B'),
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
