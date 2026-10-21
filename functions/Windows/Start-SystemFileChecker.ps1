[CmdletBinding()]
param([switch]$ReadOnly)
$ErrorActionPreference = 'Stop'
try {
    if ($ReadOnly) { & sfc.exe /verifyonly 2>&1 }
    else { & sfc.exe /scannow 2>&1 }
    $code = $LASTEXITCODE
    if ($code -ne 0) { throw ('SFC is geëindigd met exitcode {0}.' -f $code) }
    Write-Output 'De controle van systeembestanden is voltooid.'
    exit 0
} catch { Write-Error ('Systeembestandscontrole mislukt: {0}' -f $_.Exception.Message); exit 1 }
