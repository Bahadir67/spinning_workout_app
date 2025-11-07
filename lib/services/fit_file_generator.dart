import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import '../models/activity_data.dart';

/// FIT file generator for Strava/Garmin upload
/// Simplified implementation - for full production use 'fit_tool' package
class FitFileGenerator {

  /// Generate FIT file and return file path
  static Future<String> generateFitFile(ActivityData activity) async {
    try {
      // Validate activity data
      if (activity.heartRateData.isEmpty && activity.powerData.isEmpty) {
        throw Exception('No workout data available');
      }

      final directory = await getApplicationDocumentsDirectory();
      final timestamp = activity.startTime.millisecondsSinceEpoch;
      final filePath = '${directory.path}/workout_$timestamp.fit';

      // Create FIT binary data
      final fitData = _createFitData(activity);
      final file = File(filePath);
      await file.writeAsBytes(fitData);

      print('FIT file created: $filePath (${fitData.length} bytes)');
      return filePath;
    } on FileSystemException catch (e) {
      throw Exception('File system error: ${e.message}');
    } catch (e, stackTrace) {
      print('FIT creation error: $e');
      print('Stack trace: $stackTrace');
      throw Exception('FIT file creation error: $e');
    }
  }

  /// Create FIT binary data
  static Uint8List _createFitData(ActivityData activity) {
    final buffer = BytesBuilder();

    // FIT File Header (14 bytes)
    buffer.addByte(14);  // Header size
    buffer.addByte(0x20); // Protocol version 2.0
    buffer.add(_uint16ToBytes(2135)); // Profile version 21.35

    // Calculate data size later
    final dataSizePlaceholder = buffer.length;
    buffer.add(_uint32ToBytes(0)); // Data size placeholder

    buffer.add([0x2E, 0x46, 0x49, 0x54]); // ".FIT"
    buffer.add(_uint16ToBytes(0)); // Header CRC (optional, set to 0)

    final dataStart = buffer.length;

    // Add messages
    buffer.add(_createFileIdMessage(activity));
    buffer.add(_createFileCreatorMessage());
    buffer.add(_createActivityMessage(activity));
    buffer.add(_createSessionMessage(activity));
    buffer.add(_createLapMessage(activity));

    // Add record messages (one per second)
    for (var i = 0; i < activity.heartRateData.length; i++) {
      buffer.add(_createRecordMessage(activity, i));
    }

    // Calculate and update data size
    final dataSize = buffer.length - dataStart;
    final bytes = buffer.toBytes();

    // Convert to mutable list
    final mutableBytes = List<int>.from(bytes);

    final sizeBytes = _uint32ToBytes(dataSize);
    mutableBytes[4] = sizeBytes[0];
    mutableBytes[5] = sizeBytes[1];
    mutableBytes[6] = sizeBytes[2];
    mutableBytes[7] = sizeBytes[3];

    // Add file CRC
    final crc = _calculateCRC(mutableBytes);
    mutableBytes.addAll(_uint16ToBytes(crc));

    return Uint8List.fromList(mutableBytes);
  }

  /// File ID Message (Message #0)
  static List<int> _createFileIdMessage(ActivityData activity) {
    final data = BytesBuilder();

    // Message header (definition + data)
    data.addByte(0x40); // Definition message, local message 0
    data.addByte(0); // Reserved
    data.addByte(0); // Architecture (little endian)
    data.add(_uint16ToBytes(0)); // Global message number (File ID)
    data.addByte(4); // Number of fields

    // Field definitions
    data.add([0, 1, 0x00]); // Field 0: type (enum, 1 byte)
    data.add([1, 2, 0x84]); // Field 1: manufacturer (uint16)
    data.add([2, 2, 0x84]); // Field 2: product (uint16)
    data.add([5, 4, 0x86]); // Field 5: time_created (uint32)

    // Data message
    data.addByte(0x00); // Data message, local 0
    data.addByte(4); // Type: activity
    data.add(_uint16ToBytes(1)); // Manufacturer: Garmin
    data.add(_uint16ToBytes(0)); // Product: 0
    data.add(_uint32ToBytes(_toFitTime(activity.startTime)));

    return data.toBytes();
  }

  /// File Creator Message
  static List<int> _createFileCreatorMessage() {
    final data = BytesBuilder();

    data.addByte(0x41); // Definition, local message 1
    data.addByte(0);
    data.addByte(0);
    data.add(_uint16ToBytes(49)); // Message: file_creator
    data.addByte(2);

    data.add([0, 2, 0x84]); // software_version
    data.add([1, 1, 0x00]); // hardware_version

    data.addByte(0x01); // Data message
    data.add(_uint16ToBytes(100)); // Software version
    data.addByte(1); // Hardware version

    return data.toBytes();
  }

  /// Activity Message (#34)
  static List<int> _createActivityMessage(ActivityData activity) {
    final data = BytesBuilder();

    data.addByte(0x42); // Definition, local 2
    data.addByte(0);
    data.addByte(0);
    data.add(_uint16ToBytes(34)); // Message: activity
    data.addByte(3);

    data.add([253, 4, 0x86]); // timestamp
    data.add([0, 4, 0x86]); // total_timer_time
    data.add([1, 1, 0x00]); // type

    data.addByte(0x02); // Data message
    data.add(_uint32ToBytes(_toFitTime(activity.startTime)));
    data.add(_uint32ToBytes(activity.durationSeconds * 1000)); // milliseconds
    data.addByte(0); // Manual activity

    return data.toBytes();
  }

  /// Session Message (#18)
  static List<int> _createSessionMessage(ActivityData activity) {
    final data = BytesBuilder();

    data.addByte(0x43); // Definition, local 3
    data.addByte(0);
    data.addByte(0);
    data.add(_uint16ToBytes(18)); // Message: session
    data.addByte(10);

    data.add([253, 4, 0x86]); // timestamp
    data.add([2, 4, 0x86]); // start_time
    data.add([7, 4, 0x86]); // total_elapsed_time (ms)
    data.add([8, 4, 0x86]); // total_timer_time (ms)
    data.add([5, 1, 0x00]); // sport
    data.add([6, 1, 0x00]); // sub_sport
    data.add([9, 2, 0x84]); // total_distance (m)
    data.add([11, 2, 0x84]); // total_calories (kcal)
    data.add([16, 1, 0x02]); // avg_heart_rate
    data.add([17, 1, 0x02]); // max_heart_rate

    data.addByte(0x03); // Data message
    data.add(_uint32ToBytes(_toFitTime(activity.endTime)));
    data.add(_uint32ToBytes(_toFitTime(activity.startTime)));
    data.add(_uint32ToBytes(activity.durationSeconds * 1000));
    data.add(_uint32ToBytes(activity.durationSeconds * 1000));
    data.addByte(2); // Cycling
    data.addByte(6); // Indoor cycling
    data.add(_uint16ToBytes(0)); // Distance: 0 (indoor)
    data.add(_uint16ToBytes(activity.kilojoules.round()));
    data.addByte(activity.avgHeartRate);
    data.addByte(activity.maxHeartRate);

    return data.toBytes();
  }

  /// Lap Message (#19)
  static List<int> _createLapMessage(ActivityData activity) {
    final data = BytesBuilder();

    data.addByte(0x44); // Definition, local 4
    data.addByte(0);
    data.addByte(0);
    data.add(_uint16ToBytes(19)); // Message: lap
    data.addByte(6);

    data.add([253, 4, 0x86]); // timestamp
    data.add([2, 4, 0x86]); // start_time
    data.add([7, 4, 0x86]); // total_elapsed_time
    data.add([8, 4, 0x86]); // total_timer_time
    data.add([15, 1, 0x02]); // avg_heart_rate
    data.add([16, 1, 0x02]); // max_heart_rate

    data.addByte(0x04); // Data message
    data.add(_uint32ToBytes(_toFitTime(activity.endTime)));
    data.add(_uint32ToBytes(_toFitTime(activity.startTime)));
    data.add(_uint32ToBytes(activity.durationSeconds * 1000));
    data.add(_uint32ToBytes(activity.durationSeconds * 1000));
    data.addByte(activity.avgHeartRate);
    data.addByte(activity.maxHeartRate);

    return data.toBytes();
  }

  /// Record Message (#20) - one per data point
  static List<int> _createRecordMessage(ActivityData activity, int index) {
    final data = BytesBuilder();

    // Definition (only for first record)
    if (index == 0) {
      data.addByte(0x45); // Definition, local 5
      data.addByte(0);
      data.addByte(0);
      data.add(_uint16ToBytes(20)); // Message: record
      data.addByte(4);

      data.add([253, 4, 0x86]); // timestamp
      data.add([3, 1, 0x02]); // heart_rate
      data.add([4, 1, 0x02]); // cadence
      data.add([7, 2, 0x84]); // power
    }

    // Data message
    data.addByte(0x05);

    final hrPoint = activity.heartRateData[index];
    final timestamp = _toFitTime(activity.startTime) + hrPoint.timestamp;

    data.add(_uint32ToBytes(timestamp));
    data.addByte(hrPoint.bpm);
    data.addByte(index < activity.cadenceData.length
        ? activity.cadenceData[index].rpm
        : 0);
    data.add(_uint16ToBytes(index < activity.powerData.length
        ? activity.powerData[index].watts.round()
        : 0));

    return data.toBytes();
  }

  /// Convert DateTime to FIT timestamp (seconds since 1989-12-31 00:00:00 UTC)
  static int _toFitTime(DateTime dateTime) {
    final fitEpoch = DateTime.utc(1989, 12, 31, 0, 0, 0);
    return dateTime.difference(fitEpoch).inSeconds;
  }

  /// Convert uint16 to bytes (little endian)
  static List<int> _uint16ToBytes(int value) {
    return [value & 0xFF, (value >> 8) & 0xFF];
  }

  /// Convert uint32 to bytes (little endian)
  static List<int> _uint32ToBytes(int value) {
    return [
      value & 0xFF,
      (value >> 8) & 0xFF,
      (value >> 16) & 0xFF,
      (value >> 24) & 0xFF,
    ];
  }

  /// Calculate CRC-16 for FIT file
  static int _calculateCRC(List<int> data) {
    const crcTable = [
      0x0000, 0xCC01, 0xD801, 0x1400, 0xF001, 0x3C00, 0x2800, 0xE401,
      0xA001, 0x6C00, 0x7800, 0xB401, 0x5000, 0x9C01, 0x8801, 0x4400,
    ];

    int crc = 0;
    for (var byte in data) {
      var tmp = crcTable[crc & 0xF];
      crc = (crc >> 4) & 0x0FFF;
      crc = crc ^ tmp ^ crcTable[byte & 0xF];

      tmp = crcTable[crc & 0xF];
      crc = (crc >> 4) & 0x0FFF;
      crc = crc ^ tmp ^ crcTable[(byte >> 4) & 0xF];
    }

    return crc;
  }
}
