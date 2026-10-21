[CmdletBinding()]
param([switch]$ReadOnly)
$ErrorActionPreference = 'Stop'
try {
    if ($ReadOnly) {
        Get-DnsClientServerAddress -ErrorAction Stop | Where-Object { $_.ServerAddresses.Count -gt 0 } |
            ForEach-Object { Write-Output ('{0}: {1}' -f $_.InterfaceAlias, ($_.ServerAddresses -join ', ')) }
        exit 0
    }
    if (-not (Get-Command Clear-DnsClientCache -ErrorAction SilentlyContinue)) { throw 'Clear-DnsClientCache is niet beschikbaar op deze Windows-versie.' }
    Clear-DnsClientCache -ErrorAction Stop
    Write-Output 'De DNS-resolvercache is gewist en de controle is geslaagd.'
    exit 0
} catch { Write-Error ('DNS-cache wissen mislukt: {0}' -f $_.Exception.Message); exit 1 }
