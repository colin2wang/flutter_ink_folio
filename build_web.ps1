# 构建 web_engine 并同步产物到 Flutter assets（Windows）
$ErrorActionPreference = "Stop"
Set-Location (Join-Path $PSScriptRoot "web_engine")

if (Get-Command pnpm -ErrorAction SilentlyContinue) {
  pnpm install
  pnpm build
} else {
  npm install
  npx vite build
}

$dest = Join-Path $PSScriptRoot "assets\web"
if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
New-Item $dest -ItemType Directory | Out-Null
Copy-Item -Path "dist\*" -Destination $dest -Recurse -Force
Write-Host "web_engine 产物已同步到 assets/web/"
Write-Host "下一步：flutter pub get && flutter build apk"
