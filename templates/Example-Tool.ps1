[CmdletBinding()]
param(
    [switch]$ReadOnly,
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

try {
    Write-Output 'WPS-PowerAddons voorbeeldtool gestart.'
    if (-not (Get-Command -Name Get-CimInstance -ErrorAction SilentlyContinue)) {
        throw 'De vereiste opdracht Get-CimInstance is niet beschikbaar.'
    }

    $computer = Get-CimInstance -ClassName Win32_ComputerSystem
    Write-Output ('Computer: {0}' -f $computer.Name)
    if (-not $ReadOnly) {
        if ([string]::IsNullOrWhiteSpace($OutputPath)) {
            $OutputPath = Join-Path ([Environment]::GetFolderPath('Desktop')) 'WPS-PowerAddons-voorbeeld.txt'
        }
        $parent = Split-Path -Parent $OutputPath
        if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
            New-Item -ItemType Directory -Path $parent -Force | Out-Null
        }
        Set-Content -LiteralPath $OutputPath -Value ('Computer: {0}' -f $computer.Name) -Encoding UTF8
        Write-Output ('Bestand opgeslagen: {0}' -f $OutputPath)
    } else {
        Write-Output 'Alleen-lezenmodus: er zijn geen bestanden gewijzigd.'
    }
    exit 0
} catch {
    Write-Error ('De voorbeeldtool is mislukt: {0}' -f $_.Exception.Message)
    exit 1
}
