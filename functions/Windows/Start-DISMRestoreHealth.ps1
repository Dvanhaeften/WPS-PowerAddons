[CmdletBinding()]
param([switch]$ReadOnly)
$ErrorActionPreference = 'Stop'
try {
    if ($ReadOnly) { & DISM.exe /Online /Cleanup-Image /ScanHealth 2>&1; exit $LASTEXITCODE }
    & DISM.exe /Online /Cleanup-Image /RestoreHealth 2>&1
    $code = $LASTEXITCODE
    if ($code -ne 0) { throw ('DISM RestoreHealth is geëindigd met exitcode {0}.' -f $code) }
    Write-Output 'DISM RestoreHealth is voltooid. Een herstart kan nodig zijn.'
    exit 0
} catch { Write-Error ('DISM RestoreHealth mislukt: {0}' -f $_.Exception.Message); exit 1 }
