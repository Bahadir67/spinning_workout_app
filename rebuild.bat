@echo off
echo Cleaning project...
cd /d "C:\projects\spinning_workout_app"
flutter clean

echo.
echo Getting dependencies...
flutter pub get

echo.
echo Building APK...
flutter build apk --release

if %ERRORLEVEL% EQU 0 (
    echo.
    echo ========================================
    echo BUILD SUCCESS!
    echo ========================================
    echo.
    echo APK Location:
    echo C:\projects\spinning_workout_app\build\app\outputs\flutter-apk\app-release.apk
    echo.
) else (
    echo.
    echo ========================================
    echo BUILD FAILED!
    echo ========================================
    echo.
)

pause
