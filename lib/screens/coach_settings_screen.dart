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
  String _selectedModel = 'google/gemini-flash-1.5';
  int _messageFrequency = 3;

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
      _messageFrequency = _coachService.messageFrequency;
    });
  }

  Future<void> _saveSettings() async {
    await _coachService.setMode(_selectedMode);
    await _coachService.setModel(_selectedModel);
    await _coachService.setFrequency(_messageFrequency);

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
                  Row(
                    children: const [
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
                    Row(
                      children: const [
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
                        DropdownMenuItem(
                          value: 'google/gemini-flash-1.5',
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: const [
                              Text('Gemini Flash 1.5'),
                              Text(
                                'Hızlı & Ucuz (~\$0.002/antrenman)',
                                style: TextStyle(fontSize: 12, color: Colors.grey),
                              ),
                            ],
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'meta-llama/llama-3.1-70b-instruct',
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: const [
                              Text('Llama 3.1 70B'),
                              Text(
                                'Ücretsiz - Orta (~\$0.00)',
                                style: TextStyle(fontSize: 12, color: Colors.grey),
                              ),
                            ],
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'anthropic/claude-3-haiku',
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: const [
                              Text('Claude 3 Haiku'),
                              Text(
                                'En Kaliteli (~\$0.005/antrenman)',
                                style: TextStyle(fontSize: 12, color: Colors.grey),
                              ),
                            ],
                          ),
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
                    Row(
                      children: const [
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
                      'Her $_messageFrequency dakikada bir mesaj',
                      style: const TextStyle(fontSize: 16),
                    ),
                    Slider(
                      value: _messageFrequency.toDouble(),
                      min: 1,
                      max: 10,
                      divisions: 9,
                      label: '$_messageFrequency dk',
                      onChanged: (value) {
                        setState(() => _messageFrequency = value.toInt());
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
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

  @override
  void dispose() {
    _apiKeyController.dispose();
    super.dispose();
  }
}
