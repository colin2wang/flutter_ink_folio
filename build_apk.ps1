# Build the Android APK (release by default).
#
# Note: this file is intentionally ASCII-only. PowerShell 5.1 decodes BOM-less
# .ps1 files as GBK, which mangles any non-ASCII text (see AGENTS.md).
#
# This script does NOT rebuild the web engine. Run .\build_web.ps1 separately
# when something under web_engine/src changes.
param(
    [ValidateSet('release', 'debug', 'profile')]
    [string]$Flavor = 'release'
)

$ErrorActionPreference = "Stop"
$exitCode = 0

Push-Location $PSScriptRoot
try {
    flutter pub get
    # Native commands do not honour $ErrorActionPreference: check the exit code explicitly.
    if ($LASTEXITCODE -ne 0) {
        $exitCode = $LASTEXITCODE
        Write-Host "flutter pub get failed (exit $exitCode)." -ForegroundColor Red
    } else {
        Write-Host "building APK ($Flavor)..." -ForegroundColor Cyan
        flutter build apk --$Flavor
        if ($LASTEXITCODE -ne 0) {
            $exitCode = $LASTEXITCODE
            Write-Host "flutter build apk failed (exit $exitCode)." -ForegroundColor Red
        }
    }
}
finally {
    Pop-Location
}

if ($exitCode -ne 0) { exit $exitCode }

$apkDir = Join-Path $PSScriptRoot 'build\app\outputs\flutter-apk'
$apk = Get-ChildItem -Path $apkDir -Filter '*.apk' -File -ErrorAction SilentlyContinue |
       Sort-Object LastWriteTime -Descending | Select-Object -First 1

Write-Host "APK built." -ForegroundColor Green
if ($apk) {
    Write-Host ("  {0}" -f $apk.FullName)
    Write-Host ("  {0:N1} MB" -f ($apk.Length / 1MB))
} else {
    Write-Host "  no APK found under $apkDir" -ForegroundColor Yellow
}
