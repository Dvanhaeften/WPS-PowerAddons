[CmdletBinding()]
param([switch]$ReadOnly)
$ErrorActionPreference = 'Stop'
try {
    $names = @('wuauserv', 'BITS', 'cryptsvc')
    foreach ($name in $names) {
        $service = Get-Service -Name $name -ErrorAction SilentlyContinue
        if ($service) { Write-Output ('{0}: {1}' -f $name, $service.Status) }
    }
    if ($ReadOnly) { exit 0 }
    foreach ($name in $names) {
        $service = Get-Service -Name $name -ErrorAction SilentlyContinue
        if ($service -and $service.Status -eq [ServiceProcess.ServiceControllerStatus]::Running) {
            Restart-Service -Name $name -Force -ErrorAction Stop
        } elseif ($service -and $service.Status -ne [ServiceProcess.ServiceControllerStatus]::Running) {
            Start-Service -Name $name -ErrorAction Stop
        }
    }
    foreach ($name in $names) {
        $service = Get-Service -Name $name -ErrorAction SilentlyContinue
        if ($service -and $service.Status -ne [ServiceProcess.ServiceControllerStatus]::Running) {
            $service.WaitForStatus([ServiceProcess.ServiceControllerStatus]::Running, [TimeSpan]::FromSeconds(30))
            $service.Refresh()
        }
        if (-not $service -or $service.Status -ne [ServiceProcess.ServiceControllerStatus]::Running) {
            throw ('Service {0} draait niet na de controle.' -f $name)
        }
    }
    Write-Output 'De beschikbare Windows Update-services draaien. SoftwareDistribution is niet gewijzigd.'
    exit 0
} catch { Write-Error ('Windows Update-services herstarten mislukt: {0}' -f $_.Exception.Message); exit 1 }
