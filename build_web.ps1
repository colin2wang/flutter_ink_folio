# Build web_engine and sync the bundle into the Flutter assets (Windows).
#
# Note: this file is intentionally ASCII-only. PowerShell 5.1 decodes BOM-less
# .ps1 files as GBK, which mangles any non-ASCII text (see AGENTS.md).
$ErrorActionPreference = "Stop"

$engine   = Join-Path $PSScriptRoot "web_engine"
$dest     = Join-Path $PSScriptRoot "assets\web"
$exitCode = 0

Push-Location $engine
try {
  if (Get-Command pnpm -ErrorAction SilentlyContinue) {
    pnpm install
    pnpm build
  } else {
    npm install
    npx vite build
  }

  # Native commands do not honour $ErrorActionPreference: check the exit code explicitly,
  # otherwise a tsc failure falls through to the copy step with a misleading "path not found".
  if ($LASTEXITCODE -ne 0) {
    $exitCode = $LASTEXITCODE
  } else {
    if (-not (Test-Path $dest)) { New-Item $dest -ItemType Directory | Out-Null }

    # Keep README.md: it documents the flat/single-entry/classic-script contract
    # that reader_page.dart and web_asset_copier.dart rely on.
    # Everything else is build output and gets fully replaced.
    Get-ChildItem $dest -Exclude README.md | Remove-Item -Recurse -Force
    Copy-Item -Path "dist\*" -Destination $dest -Recurse -Force
  }
}
finally {
  # Always restore: the script must not leave the caller sitting in web_engine/.
  Pop-Location
}

if ($exitCode -ne 0) {
  Write-Host "web_engine build failed (exit $exitCode); assets/web/ left untouched." -ForegroundColor Red
  exit $exitCode
}

Write-Host "web_engine bundle synced to assets/web/" -ForegroundColor Green
Write-Host "next: flutter pub get && flutter build apk"
