@echo off
echo Full rebuild starting...
cd /d "C:\projects\spinning_workout_app"

echo.
echo Step 1: Deleting build folders...
if exist build rmdir /s /q build
if exist .dart_tool rmdir /s /q .dart_tool
if exist android\.gradle rmdir /s /q android\.gradle
if exist android\app\build rmdir /s /q android\app\build

echo.
echo Step 2: Flutter clean...
flutter clean

echo.
echo Step 3: Flutter pub get...
flutter pub get

echo.
echo Step 4: Building APK...
flutter build apk --release --verbose

if %ERRORLEVEL% EQU 0 (
    echo.
    echo ========================================
    echo BUILD SUCCESS!
    echo ========================================
    echo.
    echo APK: build\app\outputs\flutter-apk\app-release.apk
) else (
    echo.
    echo ========================================
    echo BUILD FAILED - Check errors above
    echo ========================================
)

pause
