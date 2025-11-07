import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;
import '../services/bluetooth_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HRConnectionScreen extends StatefulWidget {
  const HRConnectionScreen({super.key});

  @override
  State<HRConnectionScreen> createState() => _HRConnectionScreenState();
}

class _HRConnectionScreenState extends State<HRConnectionScreen> {
  final BluetoothService _bluetoothService = BluetoothService();
  List<fbp.BluetoothDevice> _devices = [];
  bool _isScanning = false;
  bool _isConnecting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _checkCurrentConnection();
  }

  /// Mevcut bağlantıyı kontrol et
  Future<void> _checkCurrentConnection() async {
    if (_bluetoothService.isConnected) {
      setState(() {});
    } else {
      // Kaydedilmiş cihaz var mı kontrol et
      final prefs = await SharedPreferences.getInstance();
      final savedDeviceId = prefs.getString('hr_device_id');

      if (savedDeviceId != null) {
        // Otomatik bağlanmayı dene
        _showAutoConnectDialog(savedDeviceId);
      }
    }
  }

  /// Otomatik bağlantı dialog'u
  Future<void> _showAutoConnectDialog(String deviceId) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('HR Sensörü'),
        content: Text('Son kullanılan HR sensörüne bağlanılsın mı?\n\nCihaz ID: ${deviceId.substring(0, 8)}...'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hayır'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Bağlan'),
          ),
        ],
      ),
    );

    if (result == true && mounted) {
      _reconnectToSavedDevice(deviceId);
    }
  }

  /// Kaydedilmiş cihaza tekrar bağlan
  Future<void> _reconnectToSavedDevice(String deviceId) async {
    setState(() {
      _isConnecting = true;
      _error = null;
    });

    try {
      // Scan yap ve cihazı bul
      final devices = await _bluetoothService.scanForHRDevices();
      final device = devices.firstWhere(
        (d) => d.remoteId.toString() == deviceId,
        orElse: () => throw Exception('Cihaz bulunamadı'),
      );

      await _bluetoothService.connectToDevice(device);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('HR sensörüne başarıyla bağlandı!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      setState(() {
        _error = 'Otomatik bağlantı hatası: $e';
        _isConnecting = false;
      });
    }
  }

  /// Cihazları tara
  Future<void> _scanForDevices() async {
    setState(() {
      _isScanning = true;
      _error = null;
      _devices = [];
    });

    try {
      final devices = await _bluetoothService.scanForHRDevices();
      setState(() {
        _devices = devices;
        _isScanning = false;
      });

      if (devices.isEmpty) {
        setState(() {
          _error = 'HR sensörü bulunamadı. Sensörünüzün açık ve yakında olduğundan emin olun.';
        });
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isScanning = false;
      });
    }
  }

  /// Cihaza bağlan
  Future<void> _connectToDevice(fbp.BluetoothDevice device) async {
    setState(() {
      _isConnecting = true;
      _error = null;
    });

    try {
      await _bluetoothService.connectToDevice(device);

      // Cihaz ID'sini kaydet
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('hr_device_id', device.remoteId.toString());

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${device.platformName} bağlandı!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      setState(() {
        _error = 'Bağlantı hatası: $e';
        _isConnecting = false;
      });
    }
  }

  /// Bağlantıyı kes
  Future<void> _disconnect() async {
    await _bluetoothService.disconnect();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bağlantı kesildi'),
          backgroundColor: Colors.orange,
        ),
      );
      Navigator.pop(context, false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('HR Sensörü Bağlantısı'),
        actions: [
          if (_bluetoothService.isConnected)
            IconButton(
              icon: const Icon(Icons.bluetooth_disabled),
              tooltip: 'Bağlantıyı Kes',
              onPressed: _disconnect,
            ),
        ],
      ),
      body: Column(
        children: [
          // Mevcut bağlantı durumu
          if (_bluetoothService.isConnected)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              color: Colors.green.withOpacity(0.2),
              child: Row(
                children: [
                  const Icon(Icons.bluetooth_connected, color: Colors.green),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Bağlı',
                          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green),
                        ),
                        Text(
                          _bluetoothService.connectedDeviceName ?? 'Bilinmeyen Cihaz',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

          // Hata mesajı
          if (_error != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              color: Colors.red.withOpacity(0.2),
              child: Row(
                children: [
                  const Icon(Icons.error, color: Colors.red),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                ],
              ),
            ),

          // Tarama butonu
          Padding(
            padding: const EdgeInsets.all(16),
            child: ElevatedButton.icon(
              onPressed: _isScanning || _isConnecting ? null : _scanForDevices,
              icon: _isScanning
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.search),
              label: Text(_isScanning ? 'Taranıyor...' : 'HR Sensörü Tara'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
                minimumSize: const Size(double.infinity, 50),
              ),
            ),
          ),

          // Cihaz listesi
          Expanded(
            child: _devices.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.bluetooth_searching, size: 64, color: Colors.grey[600]),
                        const SizedBox(height: 16),
                        Text(
                          'HR sensörü bulunamadı',
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Tarama butonuna basarak cihazları arayın',
                          style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: _devices.length,
                    itemBuilder: (context, index) {
                      final device = _devices[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: ListTile(
                          leading: const Icon(Icons.favorite, color: Colors.red, size: 32),
                          title: Text(
                            device.platformName.isNotEmpty
                                ? device.platformName
                                : 'Bilinmeyen Cihaz',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            device.remoteId.toString(),
                            style: const TextStyle(fontSize: 10),
                          ),
                          trailing: _isConnecting
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.chevron_right),
                          onTap: _isConnecting ? null : () => _connectToDevice(device),
                        ),
                      );
                    },
                  ),
          ),

          // Bağlanma durumu göstergesi
          if (_isConnecting)
            Container(
              padding: const EdgeInsets.all(16),
              color: Colors.blue.withOpacity(0.2),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Bağlanıyor...',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),

          // Bilgilendirme
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.grey[900],
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'İpuçları:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                ),
                SizedBox(height: 8),
                Text(
                  '• HR sensörünüzün açık ve yakınınızda olduğundan emin olun',
                  style: TextStyle(fontSize: 11),
                ),
                Text(
                  '• Garmin, Polar, Wahoo gibi standart BLE HR sensörleri desteklenir',
                  style: TextStyle(fontSize: 11),
                ),
                Text(
                  '• İlk taramada bulunamazsa birkaç kez tekrar deneyin',
                  style: TextStyle(fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
