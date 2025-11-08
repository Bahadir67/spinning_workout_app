import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;
import 'package:permission_handler/permission_handler.dart';

/// Bluetooth sensor service for HR, Power, and Cadence
class BluetoothService {
  static final BluetoothService _instance = BluetoothService._internal();
  factory BluetoothService() => _instance;
  BluetoothService._internal();

  // Standard Service UUIDs
  static final fbp.Guid HR_SERVICE_UUID = fbp.Guid("0000180d-0000-1000-8000-00805f9b34fb");
  static final fbp.Guid HR_CHARACTERISTIC_UUID = fbp.Guid("00002a37-0000-1000-8000-00805f9b34fb");

  static final fbp.Guid POWER_SERVICE_UUID = fbp.Guid("00001818-0000-1000-8000-00805f9b34fb");
  static final fbp.Guid POWER_CHARACTERISTIC_UUID = fbp.Guid("00002a63-0000-1000-8000-00805f9b34fb");

  static final fbp.Guid CSC_SERVICE_UUID = fbp.Guid("00001816-0000-1000-8000-00805f9b34fb");
  static final fbp.Guid CSC_CHARACTERISTIC_UUID = fbp.Guid("00002a5b-0000-1000-8000-00805f9b34fb");

  fbp.BluetoothDevice? _hrDevice;
  fbp.BluetoothDevice? _powerDevice;
  fbp.BluetoothDevice? _cadenceDevice;

  fbp.BluetoothCharacteristic? _hrCharacteristic;
  fbp.BluetoothCharacteristic? _powerCharacteristic;
  fbp.BluetoothCharacteristic? _cadenceCharacteristic;

  final _heartRateController = StreamController<int>.broadcast();
  final _powerController = StreamController<int>.broadcast();
  final _cadenceController = StreamController<int>.broadcast();

  Stream<int> get heartRateStream => _heartRateController.stream;
  Stream<int> get powerStream => _powerController.stream;
  Stream<int> get cadenceStream => _cadenceController.stream;

  bool get isHRConnected => _hrDevice != null;
  bool get isPowerConnected => _powerDevice != null;
  bool get isCadenceConnected => _cadenceDevice != null;

  String? get hrDeviceName => _hrDevice?.platformName;
  String? get powerDeviceName => _powerDevice?.platformName;
  String? get cadenceDeviceName => _cadenceDevice?.platformName;

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

  /// Scan for all cycling sensors (HR, Power, Cadence)
  Future<Map<String, List<fbp.BluetoothDevice>>> scanForAllSensors() async {
    final hasPermission = await requestPermissions();
    if (!hasPermission) {
      throw Exception('Bluetooth izinleri verilmedi');
    }

    if (await fbp.FlutterBluePlus.isSupported == false) {
      throw Exception('Bu cihaz Bluetooth desteklemiyor');
    }

    final Map<String, List<fbp.BluetoothDevice>> devices = {
      'hr': [],
      'power': [],
      'cadence': [],
    };

    // Listen for scan results
    final subscription = fbp.FlutterBluePlus.scanResults.listen((results) {
      for (fbp.ScanResult r in results) {
        // Check HR
        if (r.advertisementData.serviceUuids.contains(HR_SERVICE_UUID)) {
          if (!devices['hr']!.any((d) => d.remoteId == r.device.remoteId)) {
            devices['hr']!.add(r.device);
          }
        }
        // Check Power
        if (r.advertisementData.serviceUuids.contains(POWER_SERVICE_UUID)) {
          if (!devices['power']!.any((d) => d.remoteId == r.device.remoteId)) {
            devices['power']!.add(r.device);
          }
        }
        // Check Cadence
        if (r.advertisementData.serviceUuids.contains(CSC_SERVICE_UUID)) {
          if (!devices['cadence']!.any((d) => d.remoteId == r.device.remoteId)) {
            devices['cadence']!.add(r.device);
          }
        }
      }
    });

    try {
      await fbp.FlutterBluePlus.startScan(
        withServices: [HR_SERVICE_UUID, POWER_SERVICE_UUID, CSC_SERVICE_UUID],
        timeout: const Duration(seconds: 8),
      );

      await Future.delayed(const Duration(seconds: 8));
      await fbp.FlutterBluePlus.stopScan();
      subscription.cancel();

      return devices;
    } catch (e) {
      subscription.cancel();
      throw Exception('Tarama hatası: $e');
    }
  }

  /// Scan for HR devices only (backward compatibility)
  Future<List<fbp.BluetoothDevice>> scanForHRDevices() async {
    final allDevices = await scanForAllSensors();
    return allDevices['hr'] ?? [];
  }

  /// Connect to HR device
  Future<bool> connectToDevice(fbp.BluetoothDevice device) async {
    return connectToHRDevice(device);
  }

  /// Connect to HR device
  Future<bool> connectToHRDevice(fbp.BluetoothDevice device) async {
    try {
      await disconnectHR();

      await device.connect(
        timeout: const Duration(seconds: 10),
        autoConnect: false,
      );

      _hrDevice = device;

      List<fbp.BluetoothService> services = await device.discoverServices();

      for (fbp.BluetoothService service in services) {
        if (service.uuid == HR_SERVICE_UUID) {
          for (fbp.BluetoothCharacteristic characteristic in service.characteristics) {
            if (characteristic.uuid == HR_CHARACTERISTIC_UUID) {
              _hrCharacteristic = characteristic;
              await characteristic.setNotifyValue(true);
              characteristic.lastValueStream.listen(_parseHeartRateData);
              return true;
            }
          }
        }
      }

      throw Exception('HR servisi bulunamadı');
    } catch (e) {
      _hrDevice = null;
      _hrCharacteristic = null;
      throw Exception('HR bağlantı hatası: $e');
    }
  }

  /// Connect to Power device
  Future<bool> connectToPowerDevice(fbp.BluetoothDevice device) async {
    try {
      await disconnectPower();

      await device.connect(
        timeout: const Duration(seconds: 10),
        autoConnect: false,
      );

      _powerDevice = device;

      List<fbp.BluetoothService> services = await device.discoverServices();

      for (fbp.BluetoothService service in services) {
        if (service.uuid == POWER_SERVICE_UUID) {
          for (fbp.BluetoothCharacteristic characteristic in service.characteristics) {
            if (characteristic.uuid == POWER_CHARACTERISTIC_UUID) {
              _powerCharacteristic = characteristic;
              await characteristic.setNotifyValue(true);
              characteristic.lastValueStream.listen(_parsePowerData);
              return true;
            }
          }
        }
      }

      throw Exception('Power servisi bulunamadı');
    } catch (e) {
      _powerDevice = null;
      _powerCharacteristic = null;
      throw Exception('Power bağlantı hatası: $e');
    }
  }

  /// Connect to Cadence device
  Future<bool> connectToCadenceDevice(fbp.BluetoothDevice device) async {
    try {
      await disconnectCadence();

      await device.connect(
        timeout: const Duration(seconds: 10),
        autoConnect: false,
      );

      _cadenceDevice = device;

      List<fbp.BluetoothService> services = await device.discoverServices();

      for (fbp.BluetoothService service in services) {
        if (service.uuid == CSC_SERVICE_UUID) {
          for (fbp.BluetoothCharacteristic characteristic in service.characteristics) {
            if (characteristic.uuid == CSC_CHARACTERISTIC_UUID) {
              _cadenceCharacteristic = characteristic;
              await characteristic.setNotifyValue(true);
              characteristic.lastValueStream.listen(_parseCadenceData);
              return true;
            }
          }
        }
      }

      throw Exception('Cadence servisi bulunamadı');
    } catch (e) {
      _cadenceDevice = null;
      _cadenceCharacteristic = null;
      throw Exception('Cadence bağlantı hatası: $e');
    }
  }

  /// Parse heart rate data
  void _parseHeartRateData(List<int> value) {
    if (value.isEmpty) return;

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

  /// Parse power data (Cycling Power Measurement)
  void _parsePowerData(List<int> value) {
    if (value.length < 4) return;

    // Cycling Power Measurement format:
    // Byte 0-1: Flags
    // Byte 2-3: Instantaneous Power (sint16, watts)

    final flags = value[0] + (value[1] << 8);
    final power = value[2] + (value[3] << 8);

    // Handle signed int
    final instantaneousPower = power > 32767 ? power - 65536 : power;

    if (instantaneousPower >= 0 && instantaneousPower < 2000) {
      _powerController.add(instantaneousPower);
    }
  }

  /// Parse cadence data (CSC Measurement)
  int? _lastCrankRevolutions;
  int? _lastCrankEventTime;

  void _parseCadenceData(List<int> value) {
    if (value.length < 7) return;

    // CSC Measurement format:
    // Byte 0: Flags (bit 1 = crank revolution data present)
    // Byte 1-4: Cumulative Crank Revolutions (uint32)
    // Byte 5-6: Last Crank Event Time (uint16, 1/1024s)

    final flags = value[0];
    final hasCrankData = (flags & 0x02) != 0;

    if (!hasCrankData) return;

    final crankRevolutions = value[1] + (value[2] << 8) + (value[3] << 16) + (value[4] << 24);
    final crankEventTime = value[5] + (value[6] << 8);

    if (_lastCrankRevolutions != null && _lastCrankEventTime != null) {
      final revDiff = crankRevolutions - _lastCrankRevolutions!;
      var timeDiff = crankEventTime - _lastCrankEventTime!;

      // Handle rollover
      if (timeDiff < 0) timeDiff += 65536;

      if (timeDiff > 0 && revDiff > 0) {
        // Convert to RPM: (revolutions / time_in_seconds) * 60
        final timeInSeconds = timeDiff / 1024.0;
        final cadence = ((revDiff / timeInSeconds) * 60).round();

        if (cadence > 0 && cadence < 250) {
          _cadenceController.add(cadence);
        }
      }
    }

    _lastCrankRevolutions = crankRevolutions;
    _lastCrankEventTime = crankEventTime;
  }

  /// Disconnect HR
  Future<void> disconnectHR() async {
    if (_hrDevice != null) {
      try {
        await _hrDevice!.disconnect();
      } catch (e) {
        print('HR disconnect error: $e');
      }
      _hrDevice = null;
      _hrCharacteristic = null;
    }
  }

  /// Disconnect Power
  Future<void> disconnectPower() async {
    if (_powerDevice != null) {
      try {
        await _powerDevice!.disconnect();
      } catch (e) {
        print('Power disconnect error: $e');
      }
      _powerDevice = null;
      _powerCharacteristic = null;
    }
  }

  /// Disconnect Cadence
  Future<void> disconnectCadence() async {
    if (_cadenceDevice != null) {
      try {
        await _cadenceDevice!.disconnect();
      } catch (e) {
        print('Cadence disconnect error: $e');
      }
      _cadenceDevice = null;
      _cadenceCharacteristic = null;
      _lastCrankRevolutions = null;
      _lastCrankEventTime = null;
    }
  }

  /// Disconnect all sensors
  Future<void> disconnect() async {
    await disconnectHR();
    await disconnectPower();
    await disconnectCadence();
  }

  /// Dispose resources
  void dispose() {
    disconnect();
    _heartRateController.close();
    _powerController.close();
    _cadenceController.close();
  }
}
