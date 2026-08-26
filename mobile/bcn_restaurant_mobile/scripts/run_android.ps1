param(
    [string]$BaseUrl = "https://bcndemo-restaurant.nvi.frappe.cloud",
    [string]$DeviceId = ""
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $PSScriptRoot
Set-Location $ProjectRoot

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    throw "Flutter is not available in PATH."
}
if (-not (Test-Path "android")) {
    throw "Android platform files are missing. Run scripts/setup_android.ps1 first."
}

try {
    $uri = [Uri]$BaseUrl
} catch {
    throw "BaseUrl is not a valid URL: $BaseUrl"
}
if ($uri.Scheme -ne "https") {
    throw "BCN Restaurant mobile requires an HTTPS BaseUrl. Received: $BaseUrl"
}

Write-Host "Target ERPNext site: $BaseUrl" -ForegroundColor Cyan
flutter devices

$flutterArgs = @("run", "--dart-define=BASE_URL=$BaseUrl")
if (-not [string]::IsNullOrWhiteSpace($DeviceId)) {
    $flutterArgs += @("-d", $DeviceId)
}

& flutter @flutterArgs
if ($LASTEXITCODE -ne 0) {
    throw "flutter run failed with exit code $LASTEXITCODE"
}
