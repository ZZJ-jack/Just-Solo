$ts = Get-Date -Format 'yyyyMMddHHmmss'

# 获取本机唯一标识 (MachineGuid)
$machineId = ""
try {
    $guid = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Cryptography" -Name "MachineGuid" -ErrorAction Stop).MachineGuid
    # 取 GUID 前 8 位作为短标识
    $machineId = $guid.Substring(0, 8)
} catch {
    # 备选：用计算机名
    $machineId = $env:COMPUTERNAME
}

$version = "$machineId-$ts"
$content = "// auto-generated`n#define BUILD_VERSION L`"$version`"`n"
Set-Content -Path "$PSScriptRoot\..\src\version.h" -Value $content -Encoding UTF8
Write-Host "Version: $version"
