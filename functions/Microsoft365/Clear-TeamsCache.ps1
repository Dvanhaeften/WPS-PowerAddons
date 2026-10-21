[CmdletBinding()]
param([switch]$ReadOnly)
$ErrorActionPreference = 'Stop'
try {
    $locations = @(
        (Join-Path $env:APPDATA 'Microsoft\Teams\Cache')
        (Join-Path $env:APPDATA 'Microsoft\Teams\blob_storage')
        (Join-Path $env:APPDATA 'Microsoft\Teams\databases')
        (Join-Path $env:APPDATA 'Microsoft\Teams\GPUCache')
        (Join-Path $env:APPDATA 'Microsoft\Teams\IndexedDB')
        (Join-Path $env:APPDATA 'Microsoft\Teams\Local Storage')
        (Join-Path $env:LOCALAPPDATA 'Packages\MSTeams_8wekyb3d8bbwe\LocalCache\Microsoft\MSTeams\EBWebView\Default\Cache')
        (Join-Path $env:LOCALAPPDATA 'Packages\MSTeams_8wekyb3d8bbwe\LocalCache\Microsoft\MSTeams\EBWebView\Default\Code Cache')
    )
    $existing = @($locations | Where-Object { Test-Path -LiteralPath $_ -PathType Container } | Select-Object -Unique)
    if ($existing.Count -eq 0) { Write-Output 'Geen bekende Teams-cachelocaties gevonden.'; exit 0 }
    $totalBytes = 0
    foreach ($folder in $existing) {
        $bytes = (Get-ChildItem -LiteralPath $folder -File -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
        if ($bytes) { $totalBytes += $bytes }
        Write-Output ('Cachemap: {0} ({1:N1} MB)' -f $folder, (($bytes) / 1MB))
    }
    Write-Output ('Totale gedetecteerde cache: {0:N1} MB' -f ($totalBytes / 1MB))
    if ($ReadOnly) { exit 0 }
    if (Get-Process -Name ms-teams, Teams -ErrorAction SilentlyContinue) {
        throw 'Teams is geopend. Sluit Teams handmatig en voer de tool daarna opnieuw uit; WPS-PowerAddons sluit Teams niet automatisch.'
    }
    Add-Type -AssemblyName System.Windows.Forms
    $answer = [Windows.Forms.MessageBox]::Show(('Alleen de bovenstaande cachemappen worden opgeschoond ({0:N1} MB). Doorgaan?' -f ($totalBytes / 1MB)), 'WPS-PowerAddons - Teams-cache', [Windows.Forms.MessageBoxButtons]::YesNo, [Windows.Forms.MessageBoxIcon]::Warning)
    if ($answer -ne [Windows.Forms.DialogResult]::Yes) { Write-Output 'Opschonen geannuleerd.'; exit 2 }
    foreach ($folder in $existing) {
        Get-ChildItem -LiteralPath $folder -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction Stop
    }
    Write-Output 'De gedetecteerde Teams-cachebestanden zijn verwijderd. Gebruikersdocumenten zijn niet benaderd.'
    exit 0
} catch { Write-Error ('Teams-cache opschonen mislukt: {0}' -f $_.Exception.Message); exit 1 }
