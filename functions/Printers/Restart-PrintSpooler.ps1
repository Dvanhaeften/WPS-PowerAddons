[CmdletBinding()]
param([switch]$ReadOnly)
$ErrorActionPreference = 'Stop'
try {
    $service = Get-Service -Name Spooler -ErrorAction Stop
    if ($ReadOnly) {
        Write-Output ('Printerwachtrijservice: {0}' -f $service.Status)
        exit 0
    }
    Restart-Service -Name Spooler -Force -ErrorAction Stop
    $service = Get-Service -Name Spooler -ErrorAction Stop
    if ($service.Status -ne [ServiceProcess.ServiceControllerStatus]::Running) {
        $service.WaitForStatus([ServiceProcess.ServiceControllerStatus]::Running, [TimeSpan]::FromSeconds(30))
        $service.Refresh()
    }
    if ($service.Status -ne [ServiceProcess.ServiceControllerStatus]::Running) { throw 'De Spooler-service draait na de herstart niet.' }
    Write-Output 'De printerwachtrijservice draait weer.'
    exit 0
} catch { Write-Error ('Herstarten van de printerwachtrijservice mislukt: {0}' -f $_.Exception.Message); exit 1 }
