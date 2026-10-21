[CmdletBinding()]
param([switch]$ReadOnly)
$ErrorActionPreference = 'Stop'
try {
    $paths = @(
        (Join-Path $env:LOCALAPPDATA 'Microsoft\OneDrive\OneDrive.exe')
        (Join-Path $env:ProgramFiles 'Microsoft OneDrive\OneDrive.exe')
        (Join-Path ${env:ProgramFiles(x86)} 'Microsoft OneDrive\OneDrive.exe')
    )
    foreach ($key in @('HKCU:\Software\Microsoft\OneDrive', 'HKLM:\SOFTWARE\Microsoft\OneDrive')) {
        if (Test-Path -LiteralPath $key) {
            $location = (Get-ItemProperty -LiteralPath $key -ErrorAction SilentlyContinue).InstallPath
            if ($location) { $paths += Join-Path $location 'OneDrive.exe' }
        }
    }
    $exe = $paths | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
    if (-not $exe) { throw 'OneDrive.exe is niet gevonden.' }
    if ($ReadOnly) { Write-Output ('Gevonden: {0}' -f $exe); exit 0 }
    $running = @(Get-Process -Name OneDrive -ErrorAction SilentlyContinue)
    if ($running.Count -gt 0) {
        Add-Type -AssemblyName System.Windows.Forms
        $answer = [Windows.Forms.MessageBox]::Show('OneDrive draait. Voor reset moet alleen OneDrive worden afgesloten. Doorgaan?', 'WPS-PowerAddons - OneDrive', [Windows.Forms.MessageBoxButtons]::YesNo, [Windows.Forms.MessageBoxIcon]::Warning)
        if ($answer -ne [Windows.Forms.DialogResult]::Yes) { Write-Output 'Reset geannuleerd; OneDrive is niet gestopt.'; exit 2 }
        $running | Stop-Process -ErrorAction Stop
        Start-Sleep -Seconds 2
    }
    $reset = Start-Process -FilePath $exe -ArgumentList '/reset' -Wait -PassThru -ErrorAction Stop
    Start-Sleep -Seconds 3
    if (-not (Get-Process -Name OneDrive -ErrorAction SilentlyContinue)) {
        Start-Process -FilePath $exe -ErrorAction Stop | Out-Null
    }
    Write-Output ('OneDrive-reset gestart (procescode {0}); controleer de synchronisatiestatus.' -f $reset.ExitCode)
    exit 0
} catch { Write-Error ('OneDrive-reset mislukt: {0}' -f $_.Exception.Message); exit 1 }
