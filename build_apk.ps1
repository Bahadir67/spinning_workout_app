Write-Host "Building APK..." -ForegroundColor Green
Set-Location "C:\projects\spinning_workout_app"

$env:FLUTTER_ROOT = "C:\flutter"
$env:PATH = "C:\flutter\bin;$env:PATH"

Write-Host "Running flutter build apk --release..." -ForegroundColor Yellow

& "C:\flutter\bin\flutter" build apk --release

if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "=======================================" -ForegroundColor Green
    Write-Host "BUILD SUCCESS!" -ForegroundColor Green
    Write-Host "=======================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "APK Location:" -ForegroundColor Cyan
    Write-Host "C:\projects\spinning_workout_app\build\app\outputs\flutter-apk\app-release.apk" -ForegroundColor White
    Write-Host ""
} else {
    Write-Host ""
    Write-Host "=======================================" -ForegroundColor Red
    Write-Host "BUILD FAILED!" -ForegroundColor Red
    Write-Host "=======================================" -ForegroundColor Red
    Write-Host ""
}

Read-Host "Press Enter to exit"
