[CmdletBinding()]
param([switch]$ReadOnly)
$ErrorActionPreference = 'Stop'
try {
    $battery = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue
    if (-not $battery) { Write-Output 'Er is geen batterij gedetecteerd; dit apparaat is mogelijk een desktop.'; exit 0 }
    $path = Join-Path ([Environment]::GetFolderPath('Desktop')) ('WPS-PowerAddons-Batterijrapport-{0}.html' -f (Get-Date -Format yyyyMMdd-HHmmss))
    $output = & powercfg.exe /batteryreport /output $path 2>&1
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw ('powercfg kon het rapport niet maken: {0}' -f ($output -join ' '))
    }
    Write-Output ('Batterijrapport opgeslagen: {0}' -f $path)
    Start-Process -FilePath $path -ErrorAction Stop
    exit 0
} catch { Write-Error ('Batterijrapport mislukt: {0}' -f $_.Exception.Message); exit 1 }
