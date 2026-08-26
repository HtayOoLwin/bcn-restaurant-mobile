$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $PSScriptRoot
Set-Location $ProjectRoot

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    throw "Flutter is not available in PATH. Run 'flutter doctor' after installing Flutter."
}

flutter create . --project-name bcn_restaurant_mobile --org com.bcn.restaurant --platforms android
flutter pub get
flutter analyze
flutter test
