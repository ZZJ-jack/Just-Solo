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

Write-Host "正在编译..." -ForegroundColor Cyan
& "E:\Program Files\CMake\bin\cmake.exe" --build build --config Release
if ($LASTEXITCODE -ne 0) {
    Write-Host "编译失败！" -ForegroundColor Red
    Read-Host "按回车键退出"
    exit 1
}

Write-Host "正在部署 Qt 依赖..." -ForegroundColor Cyan
& "C:\Qt\6.8.3\msvc2022_64\bin\windeployqt.exe" --qmldir "src\qml" "build\bin\Release\JustSolo.exe" 2>&1 | Out-Null

Write-Host "启动程序..." -ForegroundColor Cyan
Start-Process "build\bin\Release\JustSolo.exe" -ArgumentList "--develop"

Write-Host "完成！" -ForegroundColor Green
