# ============================================================
# flutter_ink_folio (ebook_reader) 平台目录自动初始化脚本
#
# 用途：新环境 / 重新检出后，补齐缺失的 android / web 平台目录，
#       并完成依赖安装与首次构建校验。
#
# 用法（PowerShell，在项目根目录执行）：
#   .\init.ps1              # 常规初始化
#   .\init.ps1 -Force       # 已存在时也强制重新生成（慎用，会覆盖原生定制）
# ============================================================
param(
    [switch]$Force
)

$ErrorActionPreference = "Stop"

# ---- 项目配置（与 pubspec.yaml / build.gradle.kts 保持一致）----
$ProjectName = "ebook_reader"
$Org         = "com.inkscreen.reader"
$Platforms   = @("android", "web")

# ---- 原生定制文件清单：重新生成 android/ 前必须确认已备份 ----
$AndroidCustomFiles = @(
    "android/app/src/main/kotlin/com/inkscreen/reader/EpdRefreshPlugin.kt",
    "android/app/src/main/kotlin/com/inkscreen/reader/MainActivity.kt",
    "android/app/build.gradle.kts",
    "android/app/src/main/AndroidManifest.xml"
)

function Write-Step { param($msg) Write-Host "`n==> $msg" -ForegroundColor Cyan }

# 0. 环境检查
Write-Step "检查 Flutter 环境"
flutter --version | Select-Object -First 1
if ($LASTEXITCODE -ne 0) { throw "flutter 不可用，请先安装 Flutter 并配置 PATH" }

# 1. 判断缺失的平台目录
$missing = @()
foreach ($p in $Platforms) {
    if ($Force -or -not (Test-Path $p)) { $missing += $p }
}

if ($missing.Count -eq 0) {
    Write-Step "android / web 目录均已存在，跳过生成（-Force 可强制重建）"
} else {
    if ($missing -contains "android") {
        $existingCustom = $AndroidCustomFiles | Where-Object { Test-Path $_ }
        if ($existingCustom.Count -gt 0 -and -not $Force) {
            Write-Host "以下原生定制文件已存在，重新生成会覆盖它们：" -ForegroundColor Yellow
            $existingCustom | ForEach-Object { Write-Host "  $_" }
            $answer = Read-Host "确认继续？(y/N)"
            if ($answer -ne "y") { throw "已取消。请先备份后重试，或使用 -Force。" }
        }
    }

    Write-Step "生成缺失平台目录：$($missing -join ', ')"
    $platformArg = $missing -join ","
    flutter create --platforms $platformArg --org $Org --project-name $ProjectName .
    if ($LASTEXITCODE -ne 0) { throw "flutter create 失败" }

    Write-Host "注意：重建的 android/ 不包含墨水屏定制代码（EpdRefreshPlugin 等）。" -ForegroundColor Yellow
    Write-Host "请从版本库恢复或重新应用原生定制文件后再构建。" -ForegroundColor Yellow
}

# 2. 依赖
Write-Step "flutter pub get"
flutter pub get
if ($LASTEXITCODE -ne 0) { throw "pub get 失败" }

# 3. 校验
Write-Step "静态分析（flutter analyze）"
flutter analyze
if ($LASTEXITCODE -ne 0) { Write-Warning "analyze 有告警，请检查" }

Write-Step "单元/组件测试（flutter test）"
flutter test
if ($LASTEXITCODE -ne 0) { throw "测试未通过" }

Write-Host "`n初始化完成 ✔  构建命令：" -ForegroundColor Green
Write-Host "  Android: flutter build apk --release"
Write-Host "  Web:     flutter build web --release"
