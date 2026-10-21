[CmdletBinding()]
param([switch]$ReadOnly)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
try {
    $computer = Get-CimInstance Win32_ComputerSystem
    $bios = Get-CimInstance Win32_BIOS
    $os = Get-CimInstance Win32_OperatingSystem
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('WPS-PowerAddons - Computerinformatie')
    $lines.Add(('Computer: {0}' -f $env:COMPUTERNAME))
    $lines.Add(('Gebruiker: {0}' -f [Security.Principal.WindowsIdentity]::GetCurrent().Name))
    $lines.Add(('Fabrikant/model: {0} {1}' -f $computer.Manufacturer, $computer.Model))
    $lines.Add(('Serienummer: {0}' -f $bios.SerialNumber))
    $lines.Add(('BIOS: {0}' -f $bios.SMBIOSBIOSVersion))
    $lines.Add(('Windows: {0}, versie {1}, build {2}' -f $os.Caption, $os.Version, $os.BuildNumber))
    $lines.Add(('Laatste start: {0}' -f $os.LastBootUpTime))
    $lines.Add(('Fysiek geheugen: {0:N1} GB' -f ($computer.TotalPhysicalMemory / 1GB)))
    $lines.Add('Schijven:')
    foreach ($disk in @(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3')) {
        $lines.Add(('  {0} {1} GB totaal, {2} GB vrij' -f $disk.DeviceID, [Math]::Round($disk.Size / 1GB, 1), [Math]::Round($disk.FreeSpace / 1GB, 1)))
    }
    $lines.Add('Netwerkadapters:')
    foreach ($nic in @(Get-NetIPConfiguration -ErrorAction SilentlyContinue)) {
        $lines.Add(('  {0}: {1}' -f $nic.InterfaceAlias, (@($nic.IPv4Address.IPAddress) -join ', ')))
    }
    if (-not $ReadOnly) {
        $path = Join-Path ([Environment]::GetFolderPath('Desktop')) ('WPS-PowerAddons-Computerinformatie-{0}.txt' -f (Get-Date -Format yyyyMMdd-HHmmss))
        Set-Content -LiteralPath $path -Value $lines -Encoding UTF8
        Write-Output ('Informatie opgeslagen: {0}' -f $path)
    }
    $lines
    exit 0
} catch { Write-Error ('Computerinformatie kon niet worden verzameld: {0}' -f $_.Exception.Message); exit 1 }
