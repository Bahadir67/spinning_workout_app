import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/activity_data.dart';
import '../services/strava_service.dart';

class WorkoutSummaryScreen extends StatefulWidget {
  final ActivityData activity;

  const WorkoutSummaryScreen({super.key, required this.activity});

  @override
  State<WorkoutSummaryScreen> createState() => _WorkoutSummaryScreenState();
}

class _WorkoutSummaryScreenState extends State<WorkoutSummaryScreen> {
  final StravaService _stravaService = StravaService();
  bool _isUploading = false;

  @override
  void initState() {
    super.initState();
    _stravaService.loadSavedTokens();
  }

  Future<void> _uploadToStrava() async {
    setState(() {
      _isUploading = true;
    });

    try {
      // Check if authenticated
      if (!_stravaService.isAuthenticated) {
        // Manual token input dialog
        final result = await _showManualTokenDialog();

        if (result == null) {
          setState(() {
            _isUploading = false;
          });
          return;
        }

        // Try to use the manual token
        final success = await _stravaService.handleAuthCallback(result);

        if (!success) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Token geçersiz. Lütfen tekrar deneyin.'),
                backgroundColor: Colors.red,
              ),
            );
          }
          setState(() {
            _isUploading = false;
          });
          return;
        }
      }

      // Upload activity
      try {
        final activityId = await _stravaService.uploadActivity(widget.activity);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Strava\'ya başarıyla yüklendi! (ID: $activityId)'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 5),
            ),
          );
        }
      } catch (uploadError) {
        if (mounted) {
          // Daha detaylı hata mesajı
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Upload hatası: $uploadError'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 10),
            ),
          );
        }
        rethrow;
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Hata: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 10),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
        });
      }
    }
  }

  Future<String?> _showManualTokenDialog() async {
    final codeController = TextEditingController();

    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Strava Authorization'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('1. Aşağıdaki linke tıklayın:', style: TextStyle(fontSize: 12)),
            const SizedBox(height: 8),
            InkWell(
              onTap: () async {
                final url = Uri.parse('https://www.strava.com/oauth/authorize?client_id=18166&redirect_uri=http://localhost&response_type=code&scope=activity:write,activity:read_all');
                if (await canLaunchUrl(url)) {
                  await launchUrl(url, mode: LaunchMode.externalApplication);
                }
              },
              child: const Text(
                'Strava\'ya Giriş Yap',
                style: TextStyle(color: Colors.blue, decoration: TextDecoration.underline, fontSize: 12),
              ),
            ),
            const SizedBox(height: 12),
            const Text('2. Strava hesabınızla giriş yapın', style: TextStyle(fontSize: 12)),
            const SizedBox(height: 8),
            const Text('3. "Authorize" butonuna basın', style: TextStyle(fontSize: 12)),
            const SizedBox(height: 8),
            const Text('4. Sayfa yüklenmeyecek - NORMAL!', style: TextStyle(fontSize: 12, color: Colors.orange, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text('5. Tarayıcı adres çubuğundaki URL\'yi kopyalayın:', style: TextStyle(fontSize: 12)),
            const SizedBox(height: 8),
            const Text('Örnek URL:', style: TextStyle(fontSize: 10, color: Colors.grey)),
            const Text('http://localhost/?state=&code=abc123xyz...', style: TextStyle(fontSize: 9, color: Colors.grey)),
            const SizedBox(height: 8),
            const Text('6. Sadece "code=" sonrasını yapıştırın:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            TextField(
              controller: codeController,
              decoration: const InputDecoration(
                labelText: 'Authorization Code',
                hintText: 'abc123xyz456...',
                border: OutlineInputBorder(),
                helperText: 'Sadece code= sonrasını yapıştırın',
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal'),
          ),
          TextButton(
            onPressed: () {
              final code = codeController.text.trim();
              if (code.isNotEmpty) {
                Navigator.pop(context, code);
              }
            },
            child: const Text('Tamam'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Antrenman Özeti'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.popUntil(context, (route) => route.isFirst),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Başlık
            Text(
              '🎉 Tebrikler!',
              style: Theme.of(context).textTheme.headlineMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              widget.activity.workoutName,
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            
            // Ana metrikler
            _buildMainMetricsCard(),
            const SizedBox(height: 16),
            
            // Detaylı metrikler
            _buildDetailedMetricsCard(),
            const SizedBox(height: 16),
            
            // HR zone grafiği (opsiyonel)
            _buildHRZonesCard(),
            const SizedBox(height: 24),
            
            // Aksiyon butonları
            _buildActionButtons(),
          ],
        ),
      ),
    );
  }

  Widget _buildMainMetricsCard() {
    final duration = widget.activity.durationSeconds;
    final minutes = duration ~/ 60;
    final seconds = duration % 60;
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildMetric(
                  icon: Icons.timer,
                  label: 'Süre',
                  value: '$minutes:${seconds.toString().padLeft(2, '0')}',
                  color: Colors.blue,
                ),
                _buildMetric(
                  icon: Icons.favorite,
                  label: 'Ort HR',
                  value: '${widget.activity.avgHeartRate}',
                  color: Colors.red,
                ),
                _buildMetric(
                  icon: Icons.favorite_border,
                  label: 'Max HR',
                  value: '${widget.activity.maxHeartRate}',
                  color: Colors.red,
                ),
              ],
            ),
            const Divider(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildMetric(
                  icon: Icons.bolt,
                  label: 'Ort Power',
                  value: '${widget.activity.avgPower.round()}W',
                  color: Colors.yellow,
                ),
                _buildMetric(
                  icon: Icons.speed,
                  label: 'Kadans',
                  value: '${widget.activity.avgCadence} RPM',
                  color: Colors.cyan,
                ),
                _buildMetric(
                  icon: Icons.local_fire_department,
                  label: 'Calories',
                  value: '${widget.activity.kilojoules}',
                  color: Colors.orange,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetric({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Column(
      children: [
        Icon(icon, color: color, size: 32),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[400],
          ),
        ),
      ],
    );
  }

  Widget _buildDetailedMetricsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Gelişmiş Metrikler',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            _buildDetailRow('TSS (Training Stress Score)',
                widget.activity.tss.round().toString()),
            _buildDetailRow('IF (Intensity Factor)', 
                widget.activity.intensityFactor.toStringAsFixed(2)),
            _buildDetailRow('NP (Normalized Power)', 
                '${widget.activity.normalizedPower.round()}W'),
            _buildDetailRow('Max Power', 
                '${widget.activity.maxPower.round()}W'),
            _buildDetailRow('FTP', 
                '${widget.activity.ftp}W'),
            _buildDetailRow('Kilojoules',
                '${widget.activity.kilojoules.round()} kJ'),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(color: Colors.grey[300]),
          ),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildHRZonesCard() {
    // Basitleştirilmiş HR zone gösterimi
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Kalp Atışı Dağılımı',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Text(
              'Ortalama: ${widget.activity.avgHeartRate} bpm',
              style: TextStyle(color: Colors.grey[300]),
            ),
            Text(
              'Maksimum: ${widget.activity.maxHeartRate} bpm',
              style: TextStyle(color: Colors.grey[300]),
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: widget.activity.avgHeartRate / 220,
              backgroundColor: Colors.grey[800],
              color: Colors.red,
              minHeight: 8,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Strava upload butonu
        ElevatedButton.icon(
          onPressed: _isUploading ? null : _uploadToStrava,
          icon: _isUploading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.upload),
          label: Text(_isUploading ? 'Yükleniyor...' : 'Strava\'ya Yükle'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFFC4C02), // Strava orange
            padding: const EdgeInsets.all(16),
          ),
        ),
        const SizedBox(height: 12),

        // Tamam butonu
        ElevatedButton.icon(
          onPressed: () => Navigator.popUntil(context, (route) => route.isFirst),
          icon: const Icon(Icons.check_circle),
          label: const Text('Tamam'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            padding: const EdgeInsets.all(16),
          ),
        ),
      ],
    );
  }
}
