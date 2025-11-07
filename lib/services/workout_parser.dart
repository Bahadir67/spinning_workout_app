import 'dart:io';
import 'package:xml/xml.dart';
import '../models/workout.dart';

/// Workout parser for ZWO files and preset workouts
class WorkoutParser {

  /// Parse ZWO (Zwift workout) file
  static Future<Workout> parseZWOFile(String filePath) async {
    try {
      final file = File(filePath);
      final contents = await file.readAsString();
      final document = XmlDocument.parse(contents);

      final root = document.findElements('workout_file').first;

      final name = root.findElements('name').first.innerText;
      final author = root.findElements('author').first.innerText;
      final description = root.findElements('description').first.innerText;

      // FTP opsiyonel - yoksa 0 kullan (sonra kullanıcının FTP'si atanacak)
      int ftp = 0;
      final ftpElements = root.findElements('ftp');
      if (ftpElements.isNotEmpty) {
        ftp = int.parse(ftpElements.first.innerText);
      }

      final List<WorkoutSegment> segments = [];
      final workoutElement = root.findElements('workout').first;

      for (var element in workoutElement.children.whereType<XmlElement>()) {
        segments.addAll(_parseSegment(element));
      }

      return Workout(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: name,
        author: author,
        description: description,
        ftp: ftp,
        segments: segments,
      );
    } catch (e) {
      throw Exception('ZWO dosyası parse hatası: $e');
    }
  }

  /// Parse individual segment from XML
  static List<WorkoutSegment> _parseSegment(XmlElement element) {
    final segments = <WorkoutSegment>[];

    switch (element.name.local.toLowerCase()) {
      case 'warmup':
        segments.add(WorkoutSegment(
          type: SegmentType.warmup,
          durationSeconds: int.parse(element.getAttribute('Duration')!),
          powerLow: double.parse(element.getAttribute('PowerLow')!),
          powerHigh: double.parse(element.getAttribute('PowerHigh')!),
          cadence: int.parse(element.getAttribute('Cadence') ?? '80'),
          name: 'Warmup',
        ));
        break;

      case 'ramp':
        // Ramp - power değişir (warmup veya cooldown gibi)
        final powerLow = double.parse(element.getAttribute('PowerLow')!);
        final powerHigh = double.parse(element.getAttribute('PowerHigh')!);

        // Düşüyor mu yükseliyor mu?
        final isWarmup = powerHigh > powerLow;

        segments.add(WorkoutSegment(
          type: isWarmup ? SegmentType.warmup : SegmentType.cooldown,
          durationSeconds: int.parse(element.getAttribute('Duration')!),
          powerLow: powerLow,
          powerHigh: powerHigh,
          cadence: int.parse(element.getAttribute('Cadence') ?? '80'),
          name: isWarmup ? 'Ramp Up' : 'Ramp Down',
        ));
        break;

      case 'steadystate':
        segments.add(WorkoutSegment(
          type: SegmentType.steadyState,
          durationSeconds: int.parse(element.getAttribute('Duration')!),
          powerLow: double.parse(element.getAttribute('Power')!),
          powerHigh: double.parse(element.getAttribute('Power')!),
          cadence: int.parse(element.getAttribute('Cadence') ?? '85'),
          name: element.getAttribute('Name'),
        ));
        break;

      case 'intervals':
        final repeat = int.parse(element.getAttribute('Repeat')!);
        final onDuration = int.parse(element.getAttribute('OnDuration')!);
        final offDuration = int.parse(element.getAttribute('OffDuration')!);
        final onPower = double.parse(element.getAttribute('OnPower')!);
        final offPower = double.parse(element.getAttribute('OffPower')!);
        final cadence = int.parse(element.getAttribute('Cadence') ?? '90');

        segments.add(WorkoutSegment(
          type: SegmentType.interval,
          durationSeconds: (onDuration + offDuration) * repeat,
          powerLow: offPower,
          powerHigh: onPower,
          cadence: cadence,
          name: 'Intervals',
          repeatCount: repeat,
          onDuration: onDuration,
          offDuration: offDuration,
          onPower: onPower,
          offPower: offPower,
        ));
        break;

      case 'cooldown':
        segments.add(WorkoutSegment(
          type: SegmentType.cooldown,
          durationSeconds: int.parse(element.getAttribute('Duration')!),
          powerLow: double.parse(element.getAttribute('PowerLow')!),
          powerHigh: double.parse(element.getAttribute('PowerHigh')!),
          cadence: int.parse(element.getAttribute('Cadence') ?? '70'),
          name: 'Cooldown',
        ));
        break;

      case 'freeride':
        segments.add(WorkoutSegment(
          type: SegmentType.freeRide,
          durationSeconds: int.parse(element.getAttribute('Duration')!),
          powerLow: 0.5,
          powerHigh: 1.0,
          cadence: int.parse(element.getAttribute('Cadence') ?? '85'),
          name: 'Free Ride',
        ));
        break;
    }

    return segments;
  }

  /// Create sample ZWO file content
  static String createSampleZWO({String name = '30min Sub-Threshold'}) {
    return '''<?xml version="1.0" encoding="UTF-8"?>
<workout_file>
    <name>$name</name>
    <author>Spinning Workout App</author>
    <description>Sub-threshold intervals for aerobic endurance</description>
    <ftp>220</ftp>
    <workout>
        <Warmup Duration="300" PowerLow="0.5" PowerHigh="0.7" Cadence="80"/>
        <SteadyState Duration="180" Power="0.65" Cadence="85"/>
        <Intervals Repeat="5" OnDuration="30" OffDuration="30"
                   OnPower="0.89" OffPower="0.65" Cadence="90"/>
        <SteadyState Duration="180" Power="0.65" Cadence="85"/>
        <Cooldown Duration="300" PowerHigh="0.65" PowerLow="0.5" Cadence="70"/>
    </workout>
</workout_file>''';
  }

  /// Generate HIIT workout preset
  static Workout createHIITWorkout({int ftp = 220}) {
    return Workout(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: '20min HIIT',
      author: 'Spinning Workout App',
      description: 'High intensity interval training for power and speed',
      ftp: ftp,
      segments: [
        WorkoutSegment(
          type: SegmentType.warmup,
          durationSeconds: 300,
          powerLow: 0.5,
          powerHigh: 0.7,
          cadence: 80,
          name: 'Warmup',
        ),
        WorkoutSegment(
          type: SegmentType.interval,
          durationSeconds: 600, // 10 x (30s on + 30s off)
          powerLow: 0.5,
          powerHigh: 1.2,
          cadence: 95,
          name: 'HIIT Intervals',
          repeatCount: 10,
          onDuration: 30,
          offDuration: 30,
          onPower: 1.2,
          offPower: 0.5,
        ),
        WorkoutSegment(
          type: SegmentType.cooldown,
          durationSeconds: 300,
          powerLow: 0.4,
          powerHigh: 0.6,
          cadence: 70,
          name: 'Cooldown',
        ),
      ],
    );
  }

  /// Generate Endurance workout preset
  static Workout createEnduranceWorkout({int ftp = 220}) {
    return Workout(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: '45min Endurance',
      author: 'Spinning Workout App',
      description: 'Steady aerobic base building workout',
      ftp: ftp,
      segments: [
        WorkoutSegment(
          type: SegmentType.warmup,
          durationSeconds: 300,
          powerLow: 0.5,
          powerHigh: 0.65,
          cadence: 75,
          name: 'Warmup',
        ),
        WorkoutSegment(
          type: SegmentType.steadyState,
          durationSeconds: 2400, // 40 minutes
          powerLow: 0.65,
          powerHigh: 0.65,
          cadence: 85,
          name: 'Endurance',
        ),
        WorkoutSegment(
          type: SegmentType.cooldown,
          durationSeconds: 300,
          powerLow: 0.5,
          powerHigh: 0.65,
          cadence: 70,
          name: 'Cooldown',
        ),
      ],
    );
  }

  /// Generate Sweet Spot workout preset
  static Workout createSweetSpotWorkout({int ftp = 220}) {
    return Workout(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: '60min Sweet Spot',
      author: 'Spinning Workout App',
      description: 'Sweet spot intervals at 88-93% FTP',
      ftp: ftp,
      segments: [
        WorkoutSegment(
          type: SegmentType.warmup,
          durationSeconds: 600,
          powerLow: 0.5,
          powerHigh: 0.7,
          cadence: 80,
          name: 'Warmup',
        ),
        WorkoutSegment(
          type: SegmentType.steadyState,
          durationSeconds: 720, // 12 minutes
          powerLow: 0.88,
          powerHigh: 0.88,
          cadence: 85,
          name: 'Sweet Spot 1',
        ),
        WorkoutSegment(
          type: SegmentType.steadyState,
          durationSeconds: 300,
          powerLow: 0.55,
          powerHigh: 0.55,
          cadence: 75,
          name: 'Recovery',
        ),
        WorkoutSegment(
          type: SegmentType.steadyState,
          durationSeconds: 720, // 12 minutes
          powerLow: 0.88,
          powerHigh: 0.88,
          cadence: 85,
          name: 'Sweet Spot 2',
        ),
        WorkoutSegment(
          type: SegmentType.steadyState,
          durationSeconds: 300,
          powerLow: 0.55,
          powerHigh: 0.55,
          cadence: 75,
          name: 'Recovery',
        ),
        WorkoutSegment(
          type: SegmentType.steadyState,
          durationSeconds: 720, // 12 minutes
          powerLow: 0.88,
          powerHigh: 0.88,
          cadence: 85,
          name: 'Sweet Spot 3',
        ),
        WorkoutSegment(
          type: SegmentType.cooldown,
          durationSeconds: 600,
          powerLow: 0.5,
          powerHigh: 0.7,
          cadence: 70,
          name: 'Cooldown',
        ),
      ],
    );
  }

  /// Generate Pyramid workout preset
  static Workout createPyramidWorkout({int ftp = 220}) {
    return Workout(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: '40min Pyramid',
      author: 'Spinning Workout App',
      description: 'Progressive intensity pyramid intervals',
      ftp: ftp,
      segments: [
        WorkoutSegment(
          type: SegmentType.warmup,
          durationSeconds: 300,
          powerLow: 0.5,
          powerHigh: 0.7,
          cadence: 80,
          name: 'Warmup',
        ),
        // Up the pyramid
        WorkoutSegment(
          type: SegmentType.steadyState,
          durationSeconds: 60,
          powerLow: 0.85,
          powerHigh: 0.85,
          cadence: 90,
          name: '1 min @ 85%',
        ),
        WorkoutSegment(
          type: SegmentType.steadyState,
          durationSeconds: 120,
          powerLow: 0.90,
          powerHigh: 0.90,
          cadence: 92,
          name: '2 min @ 90%',
        ),
        WorkoutSegment(
          type: SegmentType.steadyState,
          durationSeconds: 180,
          powerLow: 0.95,
          powerHigh: 0.95,
          cadence: 95,
          name: '3 min @ 95%',
        ),
        WorkoutSegment(
          type: SegmentType.steadyState,
          durationSeconds: 120,
          powerLow: 0.55,
          powerHigh: 0.55,
          cadence: 75,
          name: 'Recovery',
        ),
        // Down the pyramid
        WorkoutSegment(
          type: SegmentType.steadyState,
          durationSeconds: 180,
          powerLow: 0.95,
          powerHigh: 0.95,
          cadence: 95,
          name: '3 min @ 95%',
        ),
        WorkoutSegment(
          type: SegmentType.steadyState,
          durationSeconds: 120,
          powerLow: 0.90,
          powerHigh: 0.90,
          cadence: 92,
          name: '2 min @ 90%',
        ),
        WorkoutSegment(
          type: SegmentType.steadyState,
          durationSeconds: 60,
          powerLow: 0.85,
          powerHigh: 0.85,
          cadence: 90,
          name: '1 min @ 85%',
        ),
        WorkoutSegment(
          type: SegmentType.cooldown,
          durationSeconds: 300,
          powerLow: 0.5,
          powerHigh: 0.7,
          cadence: 70,
          name: 'Cooldown',
        ),
      ],
    );
  }
}
