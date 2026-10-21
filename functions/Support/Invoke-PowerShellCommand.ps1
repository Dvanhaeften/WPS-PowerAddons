[CmdletBinding()]
param(
    [switch]$ReadOnly,
    [Parameter(Mandatory = $true)][string]$CommandText
)
$ErrorActionPreference = 'Stop'
try {
    if ([string]::IsNullOrWhiteSpace($CommandText)) {
        throw 'De PowerShell-opdracht mag niet leeg zijn.'
    }
    Invoke-Expression -Command $CommandText -ErrorAction Stop
    exit 0
} catch {
    Write-Error ('PowerShell-opdracht mislukt: {0}' -f $_.Exception.Message)
    exit 1
}
