import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;
import 'package:permission_handler/permission_handler.dart';

/// Bluetooth HR sensor service
class BluetoothService {
  static final BluetoothService _instance = BluetoothService._internal();
  factory BluetoothService() => _instance;
  BluetoothService._internal();

  // Standard Heart Rate Service UUID
  static final fbp.Guid HR_SERVICE_UUID = fbp.Guid("0000180d-0000-1000-8000-00805f9b34fb");
  static final fbp.Guid HR_CHARACTERISTIC_UUID = fbp.Guid("00002a37-0000-1000-8000-00805f9b34fb");

  fbp.BluetoothDevice? _connectedDevice;
  fbp.BluetoothCharacteristic? _hrCharacteristic;

  final _heartRateController = StreamController<int>.broadcast();
  Stream<int> get heartRateStream => _heartRateController.stream;

  bool get isConnected => _connectedDevice != null;
  String? get connectedDeviceName => _connectedDevice?.platformName;

  /// Request Bluetooth permissions
  Future<bool> requestPermissions() async {
    if (await Permission.bluetoothScan.isGranted &&
        await Permission.bluetoothConnect.isGranted) {
      return true;
    }

    final statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location, // Required for Android 12+
    ].request();

    return statuses[Permission.bluetoothScan]!.isGranted &&
           statuses[Permission.bluetoothConnect]!.isGranted;
  }

  /// Scan for HR devices (5 seconds)
  Future<List<fbp.BluetoothDevice>> scanForHRDevices() async {
    final hasPermission = await requestPermissions();
    if (!hasPermission) {
      throw Exception('Bluetooth izinleri verilmedi');
    }

    // Check if Bluetooth is on
    if (await fbp.FlutterBluePlus.isSupported == false) {
      throw Exception('Bu cihaz Bluetooth desteklemiyor');
    }

    final List<fbp.BluetoothDevice> devices = [];
    final completer = Completer<List<fbp.BluetoothDevice>>();

    // Listen for scan results
    final subscription = fbp.FlutterBluePlus.scanResults.listen((results) {
      for (fbp.ScanResult r in results) {
        // Check if device has HR service
        if (r.advertisementData.serviceUuids.contains(HR_SERVICE_UUID)) {
          if (!devices.any((d) => d.remoteId == r.device.remoteId)) {
            devices.add(r.device);
          }
        }
      }
    });

    // Start scanning
    try {
      await fbp.FlutterBluePlus.startScan(
        withServices: [HR_SERVICE_UUID],
        timeout: const Duration(seconds: 5),
      );

      // Wait for scan to complete
      await Future.delayed(const Duration(seconds: 5));

      await fbp.FlutterBluePlus.stopScan();
      subscription.cancel();

      return devices;
    } catch (e) {
      subscription.cancel();
      throw Exception('Tarama hatası: $e');
    }
  }

  /// Connect to a specific device
  Future<bool> connectToDevice(fbp.BluetoothDevice device) async {
    try {
      // Disconnect from current device if any
      await disconnect();

      // Connect
      await device.connect(
        timeout: const Duration(seconds: 10),
        autoConnect: false,
      );

      _connectedDevice = device;

      // Discover services
      List<fbp.BluetoothService> services = await device.discoverServices();

      // Find HR service and characteristic
      for (fbp.BluetoothService service in services) {
        if (service.uuid == HR_SERVICE_UUID) {
          for (fbp.BluetoothCharacteristic characteristic in service.characteristics) {
            if (characteristic.uuid == HR_CHARACTERISTIC_UUID) {
              _hrCharacteristic = characteristic;

              // Enable notifications
              await characteristic.setNotifyValue(true);

              // Listen to HR data
              characteristic.lastValueStream.listen(_parseHeartRateData);

              return true;
            }
          }
        }
      }

      throw Exception('HR servisi bulunamadı');
    } catch (e) {
      _connectedDevice = null;
      _hrCharacteristic = null;
      throw Exception('Bağlantı hatası: $e');
    }
  }

  /// Parse heart rate data from characteristic
  void _parseHeartRateData(List<int> value) {
    if (value.isEmpty) return;

    // Heart Rate Measurement format:
    // Byte 0: Flags
    //   Bit 0: 0 = uint8, 1 = uint16
    // Byte 1-2: Heart Rate Value

    final flags = value[0];
    final is16Bit = (flags & 0x01) != 0;

    int heartRate;
    if (is16Bit) {
      heartRate = value[1] + (value[2] << 8);
    } else {
      heartRate = value[1];
    }

    if (heartRate > 0 && heartRate < 250) {
      _heartRateController.add(heartRate);
    }
  }

  /// Disconnect from device
  Future<void> disconnect() async {
    if (_connectedDevice != null) {
      try {
        await _connectedDevice!.disconnect();
      } catch (e) {
        print('Disconnect error: $e');
      }
      _connectedDevice = null;
      _hrCharacteristic = null;
    }
  }

  /// Dispose resources
  void dispose() {
    disconnect();
    _heartRateController.close();
  }
}
