# ⚡ Quick Start Guide

Get started with Spinning Workout App in 5 minutes!

---

## 📱 Installation (Choose One)

### Option A: Pre-built APK (Fastest)
1. Download `app-release.apk` from releases
2. Transfer to Android device
3. Enable "Install from unknown sources"
4. Install and open

### Option B: Build from Source
```bash
cd spinning_workout_app
flutter pub get
flutter build apk --release
# APK is in: build/app/outputs/flutter-apk/app-release.apk
```

---

## 🚴 First Workout (3 Steps)

### Step 1: Set Your FTP
1. Open app
2. Tap ⚙️ (settings) icon
3. Enter your FTP in watts
   - Don't know? Use 220W as starting point

### Step 2: Add a Workout
1. Tap + (add) button
2. Choose a preset:
   - **HIIT** (20min) - Hard intervals
   - **Endurance** (45min) - Steady pace
   - **Sweet Spot** (60min) - FTP work
   - **Pyramid** (40min) - Progressive

### Step 3: Start Training
1. Tap workout card
2. App scans for HR sensor (optional)
3. Review graph
4. Tap "START"
5. Follow the colored bars:
   - Adjust bike resistance to match target power
   - Keep cadence at shown RPM
6. Get notified when intervals change

---

## ❤️ HR Sensor Setup (Optional)

### Compatible Devices
✅ Any Bluetooth chest strap (Polar, Garmin, Wahoo, etc.)
✅ Bluetooth arm bands
✅ Standard Heart Rate Service UUID

### Connection
1. Put on sensor (moisten contact area)
2. Start workout in app
3. App auto-scans and connects
4. See HR in real-time during workout

**Troubleshooting**:
- Ensure sensor LED is blinking
- Enable Location permission (Android requirement)
- Keep phone within 3 meters

---

## 📊 Understanding the Graph

```
┌─────────────────────────────────────┐
│ ⏱️ 05:23/20:00    ❤️ 152 bpm       │ ← Time & HR
├─────────────────────────────────────┤
│                                     │
│  ███░░███░░███  ← Power bars       │
│  ███░░███░░███    (color = zone)   │
│   ╱╲╱╲╱╲         ← HR line (red)   │
│  ∿∿∿∿∿∿∿         ← Cadence (blue)  │
│     │            ← Progress (green) │
│                                     │
├─────────────────────────────────────┤
│ Target: 195W @ 90 RPM               │
│ [▶ Start] [⏸ Pause] [⏹ Stop]       │
└─────────────────────────────────────┘
```

**Colors Mean**:
- 🩶 Gray = Easy recovery
- 🔵 Blue = Endurance pace
- 🟢 Green = Tempo
- 🟡 Yellow = Threshold (FTP)
- 🟠 Orange = Hard efforts

---

## 🎯 During Workout

### What to Watch
1. **Current target** (bottom of screen)
   - Power: Adjust bike resistance
   - Cadence: Your pedal speed (RPM)

2. **Progress line** (green vertical line)
   - Shows where you are in workout

3. **Heart rate** (red line on graph)
   - Real-time monitoring

### Controls
- **Pause** - Take a break (time stops)
- **Resume** - Continue workout
- **Stop** - End workout early

### Notifications
- 🔔 Sound alert at interval changes
- 📳 Vibration feedback
- 📲 On-screen message with new targets

---

## 📈 After Workout

### Summary Screen Shows:
- Duration, avg/max HR
- Estimated power & cadence
- TSS (Training Stress Score)
- IF (Intensity Factor)
- Kilojoules

### Export Options:
1. **Download FIT** - Save to device
2. **Upload to Strava** - Direct sync (setup required)

---

## 🔧 Strava Integration (5 minutes)

### One-Time Setup
1. Go to: https://www.strava.com/settings/api
2. Create new app:
   - Name: "Spinning Workout"
   - Website: any URL
   - Callback: `spinworkout://oauth`
3. Copy CLIENT_ID and CLIENT_SECRET
4. Edit `lib/services/strava_service.dart`:
   ```dart
   static const String CLIENT_ID = 'YOUR_ID_HERE';
   static const String CLIENT_SECRET = 'YOUR_SECRET_HERE';
   ```
5. Rebuild app

### Using Strava Upload
1. Complete workout
2. Tap "Upload to Strava"
3. Authorize (first time only)
4. Activity appears on Strava!

---

## 📁 Custom Workouts (ZWO Files)

### Import Zwift Workouts
1. Get .zwo file (from Zwift or create your own)
2. Transfer to Android device
3. In app: Tap ↑ (upload) button
4. Select .zwo file
5. Workout added to list!

### ZWO Format Example
```xml
<?xml version="1.0" encoding="UTF-8"?>
<workout_file>
    <name>My Custom Workout</name>
    <author>Me</author>
    <description>Custom intervals</description>
    <ftp>220</ftp>
    <workout>
        <Warmup Duration="300" PowerLow="0.5" PowerHigh="0.7" Cadence="80"/>
        <SteadyState Duration="600" Power="0.85" Cadence="90"/>
        <Cooldown Duration="300" PowerHigh="0.65" PowerLow="0.5" Cadence="70"/>
    </workout>
</workout_file>
```

---

## 💡 Pro Tips

### 1. Find Your FTP
Don't know your FTP? Try this:
- Do 20min HIIT preset
- Note average power feeling "hard but sustainable"
- Multiply by 0.95 = Your FTP
- Update in settings

### 2. Workout Progression
**Week 1-2**: Endurance (45min) 3x/week
**Week 3-4**: Add Sweet Spot 1x/week
**Week 5+**: HIIT 1x/week + rest

### 3. HR Zones (rough guide)
- Zone 1: <60% max HR = Recovery
- Zone 2: 60-70% = Endurance
- Zone 3: 70-80% = Tempo
- Zone 4: 80-90% = Threshold
- Zone 5: >90% = VO2Max

### 4. Manual Resistance Tips
- Start light, add gradually
- "Feel" the target power (effort level)
- Consistency > exact numbers
- Use perceived exertion as guide

---

## ❓ Common Questions

**Q: Do I need a power meter?**
A: No! Just adjust resistance by feel. Target power is a guide.

**Q: What if I don't have HR sensor?**
A: App works fine without. You'll see targets but no HR line.

**Q: Can I use Apple Watch?**
A: Not directly, but some can broadcast as Bluetooth HR sensor.

**Q: Workout too easy/hard?**
A: Adjust your FTP up/down by 5-10W in settings.

**Q: App keeps screen on?**
A: Yes, during workouts to show real-time data.

**Q: Battery drain?**
A: Moderate. Bluetooth + screen = ~15-20% per hour.

---

## 🆘 Need Help?

1. Check README.md for detailed docs
2. Open issue on GitHub
3. Check troubleshooting section in README

---

**Ready? Let's ride! 🚴💨**

Open the app → Set FTP → Add workout → Start training!
