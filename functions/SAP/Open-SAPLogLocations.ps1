[CmdletBinding()]
param([switch]$ReadOnly)
$ErrorActionPreference = 'Stop'
try {
    $candidates = @(
        'C:\Windows\CCM\Logs\AppEnforce.log'
        'C:\Windows\CCM\Logs'
        (Join-Path $env:APPDATA 'SAP')
        (Join-Path $env:LOCALAPPDATA 'SAP')
        (Join-Path $env:APPDATA 'SAP\Common')
    )
    $available = @($candidates | Where-Object { Test-Path -LiteralPath $_ })
    if ($available.Count -eq 0) { Write-Output 'Geen bekende SAP- of SCCM-loglocaties gevonden.'; exit 0 }
    Write-Output 'Beschikbare SAP- en SCCM-loglocaties:'
    $available | ForEach-Object { Write-Output $_ }
    if (-not $ReadOnly) { Start-Process -FilePath explorer.exe -ArgumentList ('"{0}"' -f (Split-Path -Parent $available[0])) }
    exit 0
} catch { Write-Error ('Loglocaties konden niet worden getoond: {0}' -f $_.Exception.Message); exit 1 }
