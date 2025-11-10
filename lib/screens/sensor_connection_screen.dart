import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;
import '../services/bluetooth_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum SensorType { hr, power, cadence }

class SensorConnectionScreen extends StatefulWidget {
  const SensorConnectionScreen({super.key});

  @override
  State<SensorConnectionScreen> createState() => _SensorConnectionScreenState();
}

class _SensorConnectionScreenState extends State<SensorConnectionScreen> with SingleTickerProviderStateMixin {
  final BluetoothService _bluetoothService = BluetoothService();
  late TabController _tabController;

  // HR
  List<fbp.BluetoothDevice> _hrDevices = [];
  bool _isHRScanning = false;
  bool _isHRConnecting = false;
  String? _hrError;

  // Power
  List<fbp.BluetoothDevice> _powerDevices = [];
  bool _isPowerScanning = false;
  bool _isPowerConnecting = false;
  String? _powerError;

  // Cadence
  List<fbp.BluetoothDevice> _cadenceDevices = [];
  bool _isCadenceScanning = false;
  bool _isCadenceConnecting = false;
  String? _cadenceError;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _checkCurrentConnections();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// Mevcut bağlantıları kontrol et
  Future<void> _checkCurrentConnections() async {
    setState(() {});

    // Kaydedilmiş cihazları kontrol et
    final prefs = await SharedPreferences.getInstance();

    if (!_bluetoothService.isHRConnected) {
      final savedHRDeviceId = prefs.getString('hr_device_id');
      if (savedHRDeviceId != null && mounted) {
        _showAutoConnectDialog(SensorType.hr, savedHRDeviceId);
      }
    }

    if (!_bluetoothService.isPowerConnected) {
      final savedPowerDeviceId = prefs.getString('power_device_id');
      if (savedPowerDeviceId != null && mounted) {
        _showAutoConnectDialog(SensorType.power, savedPowerDeviceId);
      }
    }

    if (!_bluetoothService.isCadenceConnected) {
      final savedCadenceDeviceId = prefs.getString('cadence_device_id');
      if (savedCadenceDeviceId != null && mounted) {
        _showAutoConnectDialog(SensorType.cadence, savedCadenceDeviceId);
      }
    }
  }

  /// Otomatik bağlantı dialog'u
  Future<void> _showAutoConnectDialog(SensorType type, String deviceId) async {
    final sensorName = _getSensorName(type);

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$sensorName Sensörü'),
        content: Text('Son kullanılan $sensorName sensörüne bağlanılsın mı?\n\nCihaz ID: ${deviceId.substring(0, 8)}...'),
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
      _reconnectToSavedDevice(type, deviceId);
    }
  }

  /// Kaydedilmiş cihaza tekrar bağlan
  Future<void> _reconnectToSavedDevice(SensorType type, String deviceId) async {
    setState(() {
      _setConnecting(type, true);
      _setError(type, null);
    });

    try {
      List<fbp.BluetoothDevice> devices;

      switch (type) {
        case SensorType.hr:
          devices = await _bluetoothService.scanForHRDevices();
          break;
        case SensorType.power:
          devices = await _bluetoothService.scanForPowerDevices();
          break;
        case SensorType.cadence:
          devices = await _bluetoothService.scanForCadenceDevices();
          break;
      }

      final device = devices.firstWhere(
        (d) => d.remoteId.toString() == deviceId,
        orElse: () => throw Exception('Cihaz bulunamadı'),
      );

      await _connectToDevice(type, device);
    } catch (e) {
      setState(() {
        _setError(type, 'Otomatik bağlantı hatası: $e');
        _setConnecting(type, false);
      });
    }
  }

  /// Cihazları tara
  Future<void> _scanForDevices(SensorType type) async {
    setState(() {
      _setScanning(type, true);
      _setError(type, null);
      _setDevices(type, []);
    });

    try {
      List<fbp.BluetoothDevice> devices;

      switch (type) {
        case SensorType.hr:
          devices = await _bluetoothService.scanForHRDevices();
          break;
        case SensorType.power:
          devices = await _bluetoothService.scanForPowerDevices();
          break;
        case SensorType.cadence:
          devices = await _bluetoothService.scanForCadenceDevices();
          break;
      }

      setState(() {
        _setDevices(type, devices);
        _setScanning(type, false);
      });

      if (devices.isEmpty) {
        setState(() {
          _setError(type, '${_getSensorName(type)} sensörü bulunamadı. Sensörünüzün açık ve yakında olduğundan emin olun.');
        });
      }
    } catch (e) {
      setState(() {
        _setError(type, e.toString());
        _setScanning(type, false);
      });
    }
  }

  /// Cihaza bağlan
  Future<void> _connectToDevice(SensorType type, fbp.BluetoothDevice device) async {
    setState(() {
      _setConnecting(type, true);
      _setError(type, null);
    });

    try {
      switch (type) {
        case SensorType.hr:
          await _bluetoothService.connectToDevice(device);
          break;
        case SensorType.power:
          await _bluetoothService.connectToPowerDevice(device);
          break;
        case SensorType.cadence:
          await _bluetoothService.connectToCadenceDevice(device);
          break;
      }

      // Cihaz ID'sini kaydet
      final prefs = await SharedPreferences.getInstance();
      final prefKey = _getPrefKey(type);
      await prefs.setString(prefKey, device.remoteId.toString());

      if (mounted) {
        setState(() {
          _setConnecting(type, false);
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${device.platformName} bağlandı!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      setState(() {
        _setError(type, 'Bağlantı hatası: $e');
        _setConnecting(type, false);
      });
    }
  }

  /// Bağlantıyı kes
  Future<void> _disconnect(SensorType type) async {
    switch (type) {
      case SensorType.hr:
        await _bluetoothService.disconnect();
        break;
      case SensorType.power:
        await _bluetoothService.disconnectPower();
        break;
      case SensorType.cadence:
        await _bluetoothService.disconnectCadence();
        break;
    }

    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${_getSensorName(type)} bağlantısı kesildi'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  // Helper methods
  String _getSensorName(SensorType type) {
    switch (type) {
      case SensorType.hr:
        return 'Kalp Atışı';
      case SensorType.power:
        return 'Güç';
      case SensorType.cadence:
        return 'Kadans';
    }
  }

  IconData _getSensorIcon(SensorType type) {
    switch (type) {
      case SensorType.hr:
        return Icons.favorite;
      case SensorType.power:
        return Icons.flash_on;
      case SensorType.cadence:
        return Icons.speed;
    }
  }

  Color _getSensorColor(SensorType type) {
    switch (type) {
      case SensorType.hr:
        return Colors.red;
      case SensorType.power:
        return Colors.yellow;
      case SensorType.cadence:
        return Colors.blue;
    }
  }

  String _getPrefKey(SensorType type) {
    switch (type) {
      case SensorType.hr:
        return 'hr_device_id';
      case SensorType.power:
        return 'power_device_id';
      case SensorType.cadence:
        return 'cadence_device_id';
    }
  }

  bool _isConnected(SensorType type) {
    switch (type) {
      case SensorType.hr:
        return _bluetoothService.isHRConnected;
      case SensorType.power:
        return _bluetoothService.isPowerConnected;
      case SensorType.cadence:
        return _bluetoothService.isCadenceConnected;
    }
  }

  String? _getDeviceName(SensorType type) {
    switch (type) {
      case SensorType.hr:
        return _bluetoothService.hrDeviceName;
      case SensorType.power:
        return _bluetoothService.powerDeviceName;
      case SensorType.cadence:
        return _bluetoothService.cadenceDeviceName;
    }
  }

  void _setDevices(SensorType type, List<fbp.BluetoothDevice> devices) {
    switch (type) {
      case SensorType.hr:
        _hrDevices = devices;
        break;
      case SensorType.power:
        _powerDevices = devices;
        break;
      case SensorType.cadence:
        _cadenceDevices = devices;
        break;
    }
  }

  List<fbp.BluetoothDevice> _getDevices(SensorType type) {
    switch (type) {
      case SensorType.hr:
        return _hrDevices;
      case SensorType.power:
        return _powerDevices;
      case SensorType.cadence:
        return _cadenceDevices;
    }
  }

  void _setScanning(SensorType type, bool value) {
    switch (type) {
      case SensorType.hr:
        _isHRScanning = value;
        break;
      case SensorType.power:
        _isPowerScanning = value;
        break;
      case SensorType.cadence:
        _isCadenceScanning = value;
        break;
    }
  }

  bool _isScanning(SensorType type) {
    switch (type) {
      case SensorType.hr:
        return _isHRScanning;
      case SensorType.power:
        return _isPowerScanning;
      case SensorType.cadence:
        return _isCadenceScanning;
    }
  }

  void _setConnecting(SensorType type, bool value) {
    switch (type) {
      case SensorType.hr:
        _isHRConnecting = value;
        break;
      case SensorType.power:
        _isPowerConnecting = value;
        break;
      case SensorType.cadence:
        _isCadenceConnecting = value;
        break;
    }
  }

  bool _isConnecting(SensorType type) {
    switch (type) {
      case SensorType.hr:
        return _isHRConnecting;
      case SensorType.power:
        return _isPowerConnecting;
      case SensorType.cadence:
        return _isCadenceConnecting;
    }
  }

  void _setError(SensorType type, String? error) {
    switch (type) {
      case SensorType.hr:
        _hrError = error;
        break;
      case SensorType.power:
        _powerError = error;
        break;
      case SensorType.cadence:
        _cadenceError = error;
        break;
    }
  }

  String? _getError(SensorType type) {
    switch (type) {
      case SensorType.hr:
        return _hrError;
      case SensorType.power:
        return _powerError;
      case SensorType.cadence:
        return _cadenceError;
    }
  }

  Widget _buildSensorTab(SensorType type) {
    final devices = _getDevices(type);
    final isScanning = _isScanning(type);
    final isConnecting = _isConnecting(type);
    final error = _getError(type);
    final isConnected = _isConnected(type);
    final deviceName = _getDeviceName(type);
    final sensorName = _getSensorName(type);
    final sensorIcon = _getSensorIcon(type);
    final sensorColor = _getSensorColor(type);

    return Column(
      children: [
        // Mevcut bağlantı durumu
        if (isConnected)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: Colors.green.withValues(alpha: 0.2),
            child: Row(
              children: [
                Icon(Icons.bluetooth_connected, color: Colors.green),
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
                        deviceName ?? 'Bilinmeyen Cihaz',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.bluetooth_disabled, color: Colors.red),
                  tooltip: 'Bağlantıyı Kes',
                  onPressed: () => _disconnect(type),
                ),
              ],
            ),
          ),

        // Hata mesajı
        if (error != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: Colors.red.withValues(alpha: 0.2),
            child: Row(
              children: [
                const Icon(Icons.error, color: Colors.red),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    error,
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
            onPressed: isScanning || isConnecting ? null : () => _scanForDevices(type),
            icon: isScanning
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.search),
            label: Text(isScanning ? 'Taranıyor...' : '$sensorName Sensörü Tara'),
            style: ElevatedButton.styleFrom(
              backgroundColor: sensorColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
              minimumSize: const Size(double.infinity, 50),
            ),
          ),
        ),

        // Cihaz listesi
        Expanded(
          child: devices.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.bluetooth_searching, size: 64, color: Colors.grey[600]),
                      const SizedBox(height: 16),
                      Text(
                        '$sensorName sensörü bulunamadı',
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
                  itemCount: devices.length,
                  itemBuilder: (context, index) {
                    final device = devices[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: ListTile(
                        leading: Icon(sensorIcon, color: sensorColor, size: 32),
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
                        trailing: isConnecting
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.chevron_right),
                        onTap: isConnecting ? null : () => _connectToDevice(type, device),
                      ),
                    );
                  },
                ),
        ),

        // Bağlanma durumu göstergesi
        if (isConnecting)
          Container(
            padding: const EdgeInsets.all(16),
            color: sensorColor.withValues(alpha: 0.2),
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'İpuçları:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
              const SizedBox(height: 8),
              Text(
                '• $sensorName sensörünüzün açık ve yakınınızda olduğundan emin olun',
                style: const TextStyle(fontSize: 11),
              ),
              Text(
                '• Garmin, Polar, Wahoo gibi standart BLE sensörler desteklenir',
                style: const TextStyle(fontSize: 11),
              ),
              const Text(
                '• İlk taramada bulunamazsa birkaç kez tekrar deneyin',
                style: TextStyle(fontSize: 11),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sensör Bağlantıları'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.favorite), text: 'Kalp Atışı'),
            Tab(icon: Icon(Icons.flash_on), text: 'Güç'),
            Tab(icon: Icon(Icons.speed), text: 'Kadans'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildSensorTab(SensorType.hr),
          _buildSensorTab(SensorType.power),
          _buildSensorTab(SensorType.cadence),
        ],
      ),
    );
  }
}
