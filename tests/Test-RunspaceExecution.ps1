[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
foreach ($library in @('Security.ps1', 'Validation.ps1', 'Logging.ps1', 'Configuration.ps1')) {
    . (Join-Path $root ('lib\{0}' -f $library))
}
$state = Read-WPSConfiguration -RootPath $root
$tool = $state.Tools | Where-Object Id -eq 'current-user-information' | Select-Object -First 1
if (-not $tool) { throw 'Veilige niet-admin testtool is niet geladen.' }
$logDirectory = Join-Path $env:TEMP ('WPS-PowerAddons-runspace-{0}' -f [Guid]::NewGuid().ToString('N'))
$runspace = [Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
$powershell = [Management.Automation.PowerShell]::Create()
try {
    $runspace.Open()
    $powershell.Runspace = $runspace
    $paths = @(
        (Join-Path $root 'lib\Security.ps1')
        (Join-Path $root 'lib\Logging.ps1')
        (Join-Path $root 'lib\ToolExecution.ps1')
    )
    $load = ($paths | ForEach-Object { ". '$($_.Replace("'", "''"))'" }) -join '; '
    $powershell.AddScript($load).AddStatement().AddCommand('Invoke-WPSPowerAddonTool').
        AddParameter('Tool', $tool).AddParameter('RootPath', $root).
        AddParameter('LogDirectory', $logDirectory).AddParameter('Settings', $state.Settings).
        AddParameter('ReadOnly', $true).AddParameter('Confirmed') | Out-Null
    $async = $powershell.BeginInvoke()
    if (-not $async.AsyncWaitHandle.WaitOne(30000)) { throw 'Runspace-uitvoering overschreed de testtime-out.' }
    $results = $powershell.EndInvoke($async)
    $result = @($results | Where-Object { $_.ToolId -eq 'current-user-information' } | Select-Object -Last 1)[0]
    if (-not $result -or $result.Status -ne 'Success' -or $result.ExitCode -ne 0) {
        $streamErrors = @($powershell.Streams.Error | ForEach-Object { $_.ToString() }) -join '; '
        throw ('Runspace-tool faalde: {0} {1}' -f $result.Status, $streamErrors)
    }
    Write-Output ('Runspace-uitvoering geslaagd: {0}, exitcode {1}.' -f $result.Status, $result.ExitCode)
} finally {
    $powershell.Dispose()
    $runspace.Dispose()
    if (Test-Path -LiteralPath $logDirectory) { Remove-Item -LiteralPath $logDirectory -Recurse -Force }
}
