$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

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
Start-Process "build\bin\Release\JustSolo.exe"

Write-Host "完成！" -ForegroundColor Green