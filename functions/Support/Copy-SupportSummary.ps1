[CmdletBinding()]
param([switch]$ReadOnly)
$ErrorActionPreference = 'Stop'
try {
    Add-Type -AssemblyName System.Windows.Forms
    $computer = Get-CimInstance Win32_ComputerSystem
    $bios = Get-CimInstance Win32_BIOS
    $os = Get-CimInstance Win32_OperatingSystem
    $ips = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -notlike '169.254.*' -and $_.IPAddress -ne '127.0.0.1' } | Select-Object -ExpandProperty IPAddress)
    $text = @(
        'WPS-PowerAddons - Supportoverzicht'
        ('Computer: {0}' -f $env:COMPUTERNAME)
        ('Gebruiker: {0}' -f [Security.Principal.WindowsIdentity]::GetCurrent().Name)
        ('Model: {0} {1}' -f $computer.Manufacturer, $computer.Model)
        ('Serienummer: {0}' -f $bios.SerialNumber)
        ('Windows: {0} ({1}, build {2})' -f $os.Caption, $os.Version, $os.BuildNumber)
        ('IP-adressen: {0}' -f ($ips -join ', '))
        ('Laatste start: {0}' -f $os.LastBootUpTime)
    ) -join [Environment]::NewLine
    [Windows.Forms.Clipboard]::SetText($text)
    Write-Output 'Supportoverzicht is naar het klembord gekopieerd.'
    Write-Output $text
    exit 0
} catch { Write-Error ('Kopiëren is mislukt: {0}' -f $_.Exception.Message); exit 1 }
