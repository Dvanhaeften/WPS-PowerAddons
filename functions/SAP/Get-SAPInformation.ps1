[CmdletBinding()]
param([switch]$ReadOnly)
$ErrorActionPreference = 'Stop'
try {
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('SAP GUI-informatie')
    $processes = @(Get-Process -Name saplogon -ErrorAction SilentlyContinue)
    $lines.Add(('SAP Logon actief: {0}' -f $(if ($processes.Count) { 'ja' } else { 'nee' })))
    foreach ($process in $processes) { try { $lines.Add(('Procespad: {0}' -f $process.Path)) } catch { } }
    $locations = @(
        (Join-Path $env:ProgramFiles 'SAP\FrontEnd\SAPgui\saplogon.exe')
        (Join-Path ${env:ProgramFiles(x86)} 'SAP\FrontEnd\SAPgui\saplogon.exe')
        (Join-Path $env:ProgramFiles 'SAP\FrontEnd\SAPgui')
        (Join-Path ${env:ProgramFiles(x86)} 'SAP\FrontEnd\SAPgui')
    )
    foreach ($location in $locations | Select-Object -Unique) {
        if (Test-Path -LiteralPath $location) {
            $item = Get-Item -LiteralPath $location
            $lines.Add(('Locatie: {0}' -f $location))
            if (-not $item.PSIsContainer) { $lines.Add(('Versie: {0}' -f $item.VersionInfo.FileVersion)) }
        }
    }
    foreach ($key in @('HKLM:\SOFTWARE\SAP', 'HKLM:\SOFTWARE\WOW6432Node\SAP')) {
        if (Test-Path -LiteralPath $key) { $lines.Add(('SAP-registersleutel: {0}' -f $key)) }
    }
    $appEnforce = 'C:\Windows\CCM\Logs\AppEnforce.log'
    if (Test-Path -LiteralPath $appEnforce -PathType Leaf) {
        $matches = @(Select-String -LiteralPath $appEnforce -Pattern 'SAP' -SimpleMatch -ErrorAction SilentlyContinue | Select-Object -Last 20)
        $lines.Add(('SAP-verwijzingen in AppEnforce.log: {0}' -f $matches.Count))
        foreach ($match in $matches) { $lines.Add(('  regel {0}: {1}' -f $match.LineNumber, $match.Line.Trim())) }
    } else { $lines.Add('AppEnforce.log niet gevonden of niet toegankelijk.') }
    $lines
    exit 0
} catch { Write-Error ('SAP-informatie ophalen mislukt: {0}' -f $_.Exception.Message); exit 1 }
