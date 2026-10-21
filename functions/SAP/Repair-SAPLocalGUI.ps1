[CmdletBinding()]
param([switch]$ReadOnly)
$ErrorActionPreference = 'Stop'
try {
    $running = @(Get-Process -Name saplogon, excel -ErrorAction SilentlyContinue)
    if ($running.Count -gt 0) {
        $names = ($running | Select-Object -ExpandProperty ProcessName -Unique) -join ', '
        throw ('Sluit SAP GUI en Microsoft Excel handmatig voordat u doorgaat. Actief: {0}' -f $names)
    }
    $cache = 'C:\Windows\ccmcache'
    if (-not (Test-Path -LiteralPath $cache -PathType Container)) { throw 'De SCCM-cachelmap is niet beschikbaar.' }
    $installer = Get-ChildItem -LiteralPath $cache -Filter 'SAPLocalGUI*_Install.ps1' -File -Recurse -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $installer) { throw 'Geen SAPLocalGUI-installatiescript gevonden in de SCCM-cache.' }
    Write-Output ('Nieuwste installatie gevonden: {0}' -f $installer.FullName)
    if ($ReadOnly) { Write-Output 'Alleen controleren: de installatie is niet gestart.'; exit 0 }
    Add-Type -AssemblyName System.Windows.Forms
    $message = "Installatiescript:`r`n$($installer.FullName)`r`n`r`nDit script kan SAP-componenten wijzigen. Doorgaan?"
    $answer = [Windows.Forms.MessageBox]::Show($message, 'WPS-PowerAddons - SAP-herstel', [Windows.Forms.MessageBoxButtons]::YesNo, [Windows.Forms.MessageBoxIcon]::Warning)
    if ($answer -ne [Windows.Forms.DialogResult]::Yes) { Write-Output 'Installatie geannuleerd.'; exit 2 }
    $powershell = Join-Path $PSHOME 'powershell.exe'
    $process = Start-Process -FilePath $powershell -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"{0}"' -f $installer.FullName)) -Wait -PassThru -ErrorAction Stop
    if ($process.ExitCode -ne 0) { throw ('SAP-installatie is geëindigd met exitcode {0}.' -f $process.ExitCode) }
    Write-Output 'SAP-installatie voltooid. Een herstart wordt aanbevolen; er wordt niet automatisch herstart.'
    exit 0
} catch { Write-Error ('SAP-herstel mislukt: {0}' -f $_.Exception.Message); exit 1 }
