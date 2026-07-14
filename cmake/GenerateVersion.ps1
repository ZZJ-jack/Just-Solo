$ts = Get-Date -Format 'yyMMddHHmmss'
$content = "// auto-generated`n#define BUILD_VERSION L`"$ts`"`n"
Set-Content -Path "$PSScriptRoot\..\src\version.h" -Value $content -Encoding UTF8
Write-Host "Version: $ts"
