@echo off
echo Building APK using Dart directly...
cd /d "C:\projects\spinning_workout_app"

set FLUTTER_ROOT=C:\flutter
set DART_SDK=%FLUTTER_ROOT%\bin\cache\dart-sdk
set PUB_CACHE=%LOCALAPPDATA%\Pub\Cache

"%DART_SDK%\bin\dart.exe" "%FLUTTER_ROOT%\packages\flutter_tools\bin\flutter_tools.dart" build apk --release

if %ERRORLEVEL% EQU 0 (
    echo.
    echo BUILD SUCCESS!
    echo APK: C:\projects\spinning_workout_app\build\app\outputs\flutter-apk\app-release.apk
) else (
    echo.
    echo BUILD FAILED - Error code: %ERRORLEVEL%
)

pause
