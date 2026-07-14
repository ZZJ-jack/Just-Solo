$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

# ============================================================
# 配置区 — 按实际路径修改
# ============================================================
$CMakePath     = "E:\Program Files\CMake\bin\cmake.exe"
$QtBinDir      = "C:\Qt\6.8.3\msvc2022_64\bin"
$BuildDir      = "build"
$AppName       = "JustSolo"
$OutputDir     = "release"

# ============================================================
# 1. 编译 Release
# ============================================================
Write-Host "[1/3] 编译 Release..." -ForegroundColor Cyan
& $CMakePath --build $BuildDir --config Release
if ($LASTEXITCODE -ne 0) {
    Write-Host "编译失败！" -ForegroundColor Red
    Read-Host "按回车键退出"
    exit 1
}

# ============================================================
# 2. 准备输出目录
# ============================================================
Write-Host "[2/3] 准备输出目录..." -ForegroundColor Cyan
if (Test-Path $OutputDir) {
    Remove-Item -Recurse -Force $OutputDir
}
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

# 复制 exe
$ExePath = "$BuildDir\bin\Release\$AppName.exe"
if (-not (Test-Path $ExePath)) {
    Write-Host "找不到 $ExePath" -ForegroundColor Red
    Read-Host "按回车键退出"
    exit 1
}
Copy-Item $ExePath $OutputDir

# ============================================================
# 3. windeployqt
# ============================================================
Write-Host "[3/3] 部署 Qt 依赖..." -ForegroundColor Cyan
$DeployExe = "$OutputDir\$AppName.exe"
& "$QtBinDir\windeployqt.exe" --qmldir "src\qml" $DeployExe
if ($LASTEXITCODE -ne 0) {
    Write-Host "windeployqt 失败！" -ForegroundColor Red
    Read-Host "按回车键退出"
    exit 1
}

# ============================================================
# 完成
# ============================================================
Write-Host ""
Write-Host "打包完成！" -ForegroundColor Green
Write-Host "  输出目录: $(Resolve-Path $OutputDir)"
Read-Host "按回车键退出"
