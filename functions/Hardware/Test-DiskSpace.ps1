[CmdletBinding()]
param([switch]$ReadOnly)
$ErrorActionPreference = 'Stop'
try {
    foreach ($disk in @(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3')) {
        if (-not $disk.Size) { continue }
        $freePercent = [Math]::Round(($disk.FreeSpace / $disk.Size) * 100, 1)
        $level = if ($freePercent -gt 20) { 'GROEN' } elseif ($freePercent -ge 10) { 'ORANJE' } else { 'ROOD' }
        Write-Output ('{0} [{1}]: totaal {2:N1} GB, gebruikt {3:N1} GB, beschikbaar {4:N1} GB ({5}% vrij)' -f $disk.DeviceID, $level, ($disk.Size / 1GB), (($disk.Size - $disk.FreeSpace) / 1GB), ($disk.FreeSpace / 1GB), $freePercent)
    }
    exit 0
} catch { Write-Error ('Schijfruimtecontrole mislukt: {0}' -f $_.Exception.Message); exit 1 }
