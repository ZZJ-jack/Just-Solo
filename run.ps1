$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot
# 以下为可选操作，编译失败可以尝试取消注释
# # 强制清掉所有 QML 编译产物
# $qmlDirs = @(
#     (Join-Path $PSScriptRoot "build\.qmlcache"),
#     (Join-Path $PSScriptRoot "build\JustSolo_autogen"),
#     (Join-Path $PSScriptRoot "build\JustSolo_qmlcache")
# )
# foreach ($d in $qmlDirs) {
#     if (Test-Path $d) {
#         Write-Host "清理 $d ..." -ForegroundColor Yellow
#         Remove-Item -Recurse -Force $d -ErrorAction SilentlyContinue
#     }
# }
# # 清 CMake 缓存保证重新 configure
# $cmakeCache = Join-Path $PSScriptRoot "build\CMakeCache.txt"
# if (Test-Path $cmakeCache) {
#     Write-Host "清理 CMake 缓存..." -ForegroundColor Yellow
#     Remove-Item -Force $cmakeCache
#     Remove-Item -Recurse -Force (Join-Path $PSScriptRoot "build\CMakeFiles") -ErrorAction SilentlyContinue
# }

# # 也清理运行时 QML 磁盘缓存
# $appDataQml = Join-Path $env:LOCALAPPDATA "Just Solo\qmlcache"
# if (Test-Path $appDataQml) {
#     Write-Host "清理运行时 QML 缓存..." -ForegroundColor Yellow
#     Remove-Item -Recurse -Force $appDataQml -ErrorAction SilentlyContinue
# }

# Write-Host "CMake 配置..." -ForegroundColor Cyan
# & "E:\Program Files\CMake\bin\cmake.exe" -S . -B build
# if ($LASTEXITCODE -ne 0) {
#     Write-Host "CMake 配置失败！" -ForegroundColor Red
#     Read-Host "按回车键退出"
#     exit 1
# }

# ============================================================
# 配置区 — 支持环境变量覆盖（GitHub Actions 无需修改脚本）
# ============================================================
$CMakePath = if ($env:CMAKE_PATH) { $env:CMAKE_PATH }
             elseif (Get-Command cmake -ErrorAction SilentlyContinue) { "cmake" }
             else { "E:\Program Files\CMake\bin\cmake.exe" }
$QtBinDir  = if ($env:QT_BIN_DIR) { $env:QT_BIN_DIR } else { "C:\Qt\6.8.3\msvc2022_64\bin" }
$BuildDir  = "build"
$AppName   = "JustSolo"

# 首次编译 / CI 全新环境时自动执行 CMake 配置
if (-not (Test-Path "$BuildDir\CMakeCache.txt")) {
    Write-Host "未检测到 CMake 缓存，正在配置..." -ForegroundColor Cyan
    & $CMakePath -S . -B $BuildDir -A x64
    if ($LASTEXITCODE -ne 0) {
        Write-Host "CMake 配置失败！" -ForegroundColor Red
        if (-not $env:CI) { Read-Host "按回车键退出" }
        exit 1
    }
}

Write-Host "正在编译..." -ForegroundColor Cyan
& $CMakePath --build $BuildDir --config Release
if ($LASTEXITCODE -ne 0) {
    Write-Host "编译失败！" -ForegroundColor Red
    if (-not $env:CI) { Read-Host "按回车键退出" }
    exit 1
}

Write-Host "正在部署 Qt 依赖..." -ForegroundColor Cyan
& "$QtBinDir\windeployqt.exe" --qmldir "src\qml" "$BuildDir\bin\Release\$AppName.exe" 2>&1 | Out-Null

# CI 环境下不启动程序，仅产出编译结果
if (-not $env:CI) {
    Write-Host "启动程序..." -ForegroundColor Cyan
    Start-Process "$BuildDir\bin\Release\$AppName.exe" -ArgumentList "--develop"
}

Write-Host "完成！" -ForegroundColor Green
