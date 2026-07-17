param(
    [string]$Version = ""
)

$ts = Get-Date -Format 'yyyyMMddHHmmss'

# 获取本机唯一标识 (MachineGuid)
$machineId = ""
try {
    $guid = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Cryptography" -Name "MachineGuid" -ErrorAction Stop).MachineGuid
    $machineId = $guid.Substring(0, 8)
} catch {
    $machineId = $env:COMPUTERNAME
}

$suffix = if ($Version) { "-$Version" } else { "" }
$buildVersion = "$ts-$machineId$suffix"

$content = "// auto-generated`n#define BUILD_VERSION L`"$buildVersion`"`n"
Set-Content -Path "$PSScriptRoot\..\src\version.h" -Value $content -Encoding UTF8
Write-Host "Build version: $buildVersion"
