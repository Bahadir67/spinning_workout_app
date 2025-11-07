@echo off
echo Building APK...
cd /d C:\projects\spinning_workout_app
C:\flutter\bin\flutter.bat build apk --release
if %ERRORLEVEL% EQU 0 (
    echo.
    echo ========================================
    echo BUILD SUCCESS!
    echo ========================================
    echo.
    echo APK Location:
    echo C:\projects\spinning_workout_app\build\app\outputs\flutter-apk\app-release.apk
    echo.
    pause
) else (
    echo.
    echo ========================================
    echo BUILD FAILED!
    echo ========================================
    echo.
    pause
)
