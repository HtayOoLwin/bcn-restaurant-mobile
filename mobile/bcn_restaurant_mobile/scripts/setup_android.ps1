$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path -Parent $PSScriptRoot
Set-Location $ProjectRoot

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    throw "Flutter is not available in PATH. Install Flutter and reopen PowerShell."
}
if (-not (Get-Command dart -ErrorAction SilentlyContinue)) {
    throw "Dart is not available in PATH. Flutter's bin directory must be in PATH."
}

$dartVersionText = (& dart --version 2>&1 | Out-String)
if ($dartVersionText -notmatch 'Dart SDK version:\s+(?<version>\d+\.\d+\.\d+)') {
    throw "Unable to detect Dart SDK version. Output: $dartVersionText"
}
$dartVersion = [Version]$Matches['version']
if ($dartVersion -lt [Version]'3.12.0') {
    throw "Dart 3.12.0 or newer is required. Current version: $dartVersion"
}

Write-Host "Flutter toolchain:" -ForegroundColor Cyan
flutter --version
Write-Host ""
flutter doctor

if (-not (Test-Path "android")) {
    Write-Host "Creating Android platform files..." -ForegroundColor Cyan
    flutter create . --project-name bcn_restaurant_mobile --org com.bcn.restaurant --platforms android
}
else {
    Write-Host "Android platform files already exist; skipping flutter create." -ForegroundColor DarkGray
}

$manifestPath = Join-Path $ProjectRoot "android/app/src/main/AndroidManifest.xml"
if (-not (Test-Path $manifestPath)) {
    throw "AndroidManifest.xml was not generated at $manifestPath"
}

$manifest = Get-Content $manifestPath -Raw
if ($manifest -notmatch 'android.permission.INTERNET') {
    $manifest = $manifest -replace '(<manifest\b[^>]*>)', ('$1' + [Environment]::NewLine + '    <uses-permission android:name="android.permission.INTERNET" />')
    Set-Content -Path $manifestPath -Value $manifest -Encoding UTF8
    Write-Host "Added Android INTERNET permission to the main manifest." -ForegroundColor Green
}

flutter pub get
flutter analyze
flutter test

Write-Host "Android project setup complete." -ForegroundColor Green
