# 🚴 Spinning Workout App

Professional spinning bike workout application with **HR sensor support**, **TrainerRoad-style graphics**, **Strava integration**, and **workout notifications**.

Perfect for spinning bikes with Bluetooth HR sensors (no power meter or smart trainer required).

---

## ✨ Features

### Core Functionality
- 📊 **TrainerRoad-Style Graphics** - Visual workout profile with power zones, HR line, cadence targets, and progress indicator
- ❤️ **Bluetooth HR Sensor** - Real-time heart rate monitoring with automatic device connection
- 🎯 **Manual Resistance Control** - Target power/cadence display for manual bike adjustment
- 🔔 **Workout Notifications** - Sound and vibration alerts for interval changes
- 📱 **Android APK** - One-click installation on Android devices

### Workout Types
- ⚡ **HIIT** - 20min high-intensity interval training
- 🏃 **Endurance** - 45min steady aerobic base building
- 📈 **Sweet Spot** - 60min intervals at 88-93% FTP
- 📊 **Pyramid** - 40min progressive intensity workout
- 📁 **ZWO Import** - Zwift workout file support

### Data & Export
- 📈 **Advanced Metrics** - TSS, IF, NP, Kilojoules calculation
- 🏆 **Strava Integration** - FIT file generation and direct upload
- 💾 **Workout History** - Save and manage your workouts

---

## 🚀 Quick Start

### Prerequisites
- Flutter SDK (3.0+)
- Android Studio or VS Code
- Android device or emulator
- Bluetooth HR sensor (optional but recommended)

### Installation

1. **Clone and setup**
   ```bash
   cd spinning_workout_app
   flutter pub get
   ```

2. **Build APK**
   ```bash
   flutter build apk --release
   ```
   APK location: `build/app/outputs/flutter-apk/app-release.apk`

3. **Or run directly**
   ```bash
   flutter run
   ```

---

## 📱 Usage Guide

### First Time Setup

1. **Set Your FTP**
   - Tap settings icon (⚙️) in top-right
   - Enter your FTP (Functional Threshold Power) in watts
   - Default is 220W if unknown

2. **Add a Workout**
   - **Preset**: Tap "+" button → Choose HIIT/Endurance/Sweet Spot/Pyramid
   - **Custom**: Tap "↑" button → Select ZWO file from device

### During Workout

1. **Start**
   - Select workout from list
   - App will scan for HR sensor automatically
   - Review workout graph
   - Tap "Start" button

2. **Follow the Graph**
   - **Power bars** show target intensity (color-coded zones)
   - **Red line** displays real-time heart rate
   - **Blue line** shows target cadence
   - **Green vertical line** indicates current position

3. **Manual Adjustment**
   - Adjust bike resistance to match target power
   - Maintain cadence (RPM) at target value
   - Notifications alert you to interval changes

4. **Finish**
   - Complete workout or tap "Stop"
   - View summary with metrics
   - Upload to Strava (if configured)

### HR Sensor Connection

- App automatically scans on workout start
- Connects to first available HR sensor
- Supports standard Bluetooth Heart Rate Service
- LED indicator shows connection status

---

## 🎨 Power Zones

| Zone | Color | % FTP | Purpose |
|------|-------|-------|---------|
| Recovery | 🩶 Gray | <55% | Active recovery |
| Endurance | 🔵 Blue | 55-75% | Aerobic base |
| Tempo | 🟢 Green | 75-90% | Tempo training |
| Threshold | 🟡 Yellow | 90-105% | FTP work |
| VO2Max | 🟠 Orange | >105% | High intensity |

---

## 🔧 Strava Setup

1. Create Strava API application: https://www.strava.com/settings/api

2. Configure your app:
   - **Application Name**: Spinning Workout
   - **Category**: Training
   - **Authorization Callback Domain**: `spinworkout://oauth`

3. Update `lib/services/strava_service.dart`:
   ```dart
   static const String CLIENT_ID = 'YOUR_CLIENT_ID';
   static const String CLIENT_SECRET = 'YOUR_CLIENT_SECRET';
   ```

4. In app:
   - Complete a workout
   - Tap "Upload to Strava" in summary
   - Authorize on first use
   - Subsequent uploads are automatic

---

## 📂 Project Structure

```
spinning_workout_app/
├── lib/
│   ├── main.dart                      # App entry point
│   ├── models/
│   │   ├── workout.dart               # Workout & segment models
│   │   └── activity_data.dart         # Activity data for export
│   ├── services/
│   │   ├── bluetooth_service.dart     # HR sensor connection
│   │   ├── workout_parser.dart        # ZWO parser & presets
│   │   ├── fit_file_generator.dart    # FIT file creation
│   │   ├── strava_service.dart        # Strava OAuth & upload
│   │   └── notification_service.dart  # Workout notifications
│   └── screens/
│       ├── workout_list_screen.dart   # Main list & presets
│       ├── workout_detail_screen.dart # Workout execution
│       └── workout_summary_screen.dart# Post-workout summary
├── android/
│   └── app/src/main/AndroidManifest.xml  # Permissions
├── assets/
│   └── sounds/                        # Notification sounds
├── pubspec.yaml                       # Dependencies
└── README.md                          # This file
```

---

## 🎯 Workout Presets

### 20min HIIT
- 5min warmup (50-70% FTP)
- 10x (30s @ 120% + 30s @ 50%)
- 5min cooldown
- **Best for**: Power and speed gains

### 45min Endurance
- 5min warmup
- 40min steady @ 65% FTP
- 5min cooldown
- **Best for**: Aerobic base building

### 60min Sweet Spot
- 10min warmup
- 3x (12min @ 88% FTP + 5min recovery)
- 10min cooldown
- **Best for**: FTP improvement

### 40min Pyramid
- 5min warmup
- 1min @ 85% → 2min @ 90% → 3min @ 95%
- 2min recovery
- 3min @ 95% → 2min @ 90% → 1min @ 85%
- 5min cooldown
- **Best for**: Progressive overload

---

## 📝 ZWO File Format

Example Zwift workout file:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<workout_file>
    <name>Custom Workout</name>
    <author>Your Name</author>
    <description>Description here</description>
    <ftp>220</ftp>
    <workout>
        <Warmup Duration="300" PowerLow="0.5" PowerHigh="0.7" Cadence="80"/>
        <SteadyState Duration="600" Power="0.85" Cadence="90"/>
        <Intervals Repeat="5" OnDuration="60" OffDuration="60"
                   OnPower="0.95" OffPower="0.65" Cadence="92"/>
        <Cooldown Duration="300" PowerHigh="0.65" PowerLow="0.5" Cadence="70"/>
    </workout>
</workout_file>
```

---

## 🔍 Troubleshooting

### Bluetooth Issues

**Problem**: HR sensor not found
- Ensure sensor is active (LED blinking)
- Check battery level
- Enable Location services (Android 12+ requirement)
- Grant Bluetooth permissions in app settings

**Problem**: Connection drops during workout
- Keep phone close to sensor (<3 meters)
- Ensure sensor strap is tight and moist
- Close other apps using Bluetooth

### App Issues

**Problem**: Notifications not showing
- Grant notification permission in Android settings
- Check "Do Not Disturb" mode is off

**Problem**: Strava upload fails
- Verify CLIENT_ID and CLIENT_SECRET are set
- Re-authenticate (logout and login again)
- Check internet connection

---

## 🛠️ Development

### Dependencies

- `flutter_blue_plus` - Bluetooth HR sensor
- `fl_chart` - TrainerRoad-style charts
- `flutter_local_notifications` - Interval alerts
- `audioplayers` - Sound notifications
- `vibration` - Haptic feedback
- `oauth2` - Strava authentication
- `file_picker` - ZWO import
- `xml` - ZWO parsing

### Build Commands

```bash
# Debug build
flutter run --debug

# Release APK
flutter build apk --release

# Install to device
flutter install

# View logs
flutter logs
```

---

## 🚧 Known Limitations

- **Manual resistance** - No automatic trainer control
- **Indoor only** - No GPS tracking
- **Android only** - iOS requires Mac for development
- **FIT files** - Simplified format (works with Strava/Garmin)
- **HR sensor selection** - Auto-connects to first found device

---

## 🎓 Future Enhancements

- [ ] HR sensor selection screen
- [ ] Manual cadence input during workout
- [ ] Workout builder/editor
- [ ] FTP test mode (20min protocol)
- [ ] Power zone distribution analysis
- [ ] Dark/light theme toggle
- [ ] Lap markers for intervals
- [ ] Export to TCX format
- [ ] Training calendar

---

## 📄 License

MIT License - Feel free to use and modify

---

## 🤝 Contributing

Issues and pull requests welcome!

For bugs or feature requests, please open an issue on GitHub.

---

## 💡 Tips

1. **Determine your FTP**:
   - 20min all-out test: Average power × 0.95 = FTP
   - Or use estimate: 220W for beginners, 280W for intermediate, 320W+ for advanced

2. **HR Sensor Setup**:
   - Moisten contact area before use
   - Ensure snug but comfortable fit
   - Most Bluetooth chest straps work (Polar, Garmin, Wahoo, etc.)

3. **Manual Resistance**:
   - Start with light resistance and increase gradually
   - Use RPE (Rate of Perceived Exertion) as guide
   - Target power is a goal, not requirement

4. **Workout Selection**:
   - New to spinning: Start with Endurance
   - Building fitness: Sweet Spot 2x per week
   - Performance gains: HIIT 1x per week
   - Mix different workout types

---

**Happy Training! 🚴💪**

For questions or support, open an issue or check the documentation.
