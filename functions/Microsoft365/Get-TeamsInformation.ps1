[CmdletBinding()]
param([switch]$ReadOnly)
$ErrorActionPreference = 'Stop'
try {
    $locations = @(
        (Join-Path $env:APPDATA 'Microsoft\Teams')
        (Join-Path $env:LOCALAPPDATA 'Microsoft\Teams')
        (Join-Path $env:LOCALAPPDATA 'Packages\MSTeams_8wekyb3d8bbwe\LocalCache\Microsoft\MSTeams')
        (Join-Path $env:LOCALAPPDATA 'Packages\MSTeams_8wekyb3d8bbwe\LocalCache\Microsoft\MSTeams\EBWebView')
    )
    Write-Output ('Nieuwe Teams-pakketlocatie toegankelijk: {0}' -f (Test-Path -LiteralPath (Join-Path $env:LOCALAPPDATA 'Packages\MSTeams_8wekyb3d8bbwe')))
    foreach ($process in @(Get-Process -Name ms-teams, Teams -ErrorAction SilentlyContinue)) {
        try { Write-Output ('Proces: {0}, pad: {1}' -f $process.ProcessName, $process.Path) }
        catch { Write-Output ('Proces actief: {0}' -f $process.ProcessName) }
    }
    foreach ($location in $locations | Select-Object -Unique) {
        if (Test-Path -LiteralPath $location -PathType Container) {
            $item = Get-Item -LiteralPath $location
            Write-Output ('Cachelocatie: {0}; aangepast: {1}' -f $location, $item.LastWriteTime)
        }
    }
    exit 0
} catch { Write-Error ('Teams-informatie mislukt: {0}' -f $_.Exception.Message); exit 1 }
