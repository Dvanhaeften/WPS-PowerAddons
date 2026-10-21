[CmdletBinding()]
param([switch]$ReadOnly)
$ErrorActionPreference = 'Stop'
try {
    & DISM.exe /Online /Cleanup-Image /ScanHealth 2>&1
    $code = $LASTEXITCODE
    if ($code -ne 0) { throw ('DISM is geëindigd met exitcode {0}.' -f $code) }
    Write-Output 'DISM ScanHealth is voltooid.'
    exit 0
} catch { Write-Error ('DISM ScanHealth mislukt: {0}' -f $_.Exception.Message); exit 1 }
