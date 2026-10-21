[CmdletBinding()]
param([switch]$ReadOnly)
$ErrorActionPreference = 'Stop'
try {
    if ($ReadOnly) {
        & netsh.exe winsock show catalog 2>&1
        if ($LASTEXITCODE -ne 0) { throw ('netsh is geëindigd met code {0}.' -f $LASTEXITCODE) }
        exit 0
    }
    & netsh.exe winsock reset 2>&1
    if ($LASTEXITCODE -ne 0) { throw ('netsh winsock reset is geëindigd met code {0}.' -f $LASTEXITCODE) }
    Write-Output 'Winsock is opnieuw ingesteld. Een herstart kan nodig zijn; er wordt niet automatisch herstart.'
    exit 0
} catch { Write-Error ('Winsock opnieuw instellen mislukt: {0}' -f $_.Exception.Message); exit 1 }
