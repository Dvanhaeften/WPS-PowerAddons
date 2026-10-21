[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
foreach ($library in @('Security.ps1', 'Validation.ps1', 'Logging.ps1', 'Configuration.ps1', 'ToolExecution.ps1')) {
    . (Join-Path $root ('lib\{0}' -f $library))
}
$state = Read-WPSConfiguration -RootPath $root
$tool = $state.Tools | Where-Object Id -eq 'powershell-command' | Select-Object -First 1
if (-not $tool) { throw 'PowerShell-opdrachttool is niet geladen.' }
if ($tool.RequiresAdmin -or -not $tool.RequiresConfirmation) {
    throw 'De opdrachttool moet bevestiging vereisen en zonder administratorrechten draaien.'
}
$logDirectory = Join-Path $env:TEMP ('WPS-PowerAddons-command-{0}' -f [Guid]::NewGuid().ToString('N'))
$command = "Write-Output 'WPS-COMMAND-OUTPUT'; Write-Output 'WPS-COMMAND-SECRET'"
try {
    $result = Invoke-WPSPowerAddonTool -Tool $tool -RootPath $root -LogDirectory $logDirectory -Settings $state.Settings -CommandText $command -Confirmed
    if ($result.Status -ne 'Success' -or $result.ExitCode -ne 0) {
        throw ('Commanduitvoering faalde: {0} ({1})' -f $result.Status, $result.Message)
    }
    if ($result.Output -notmatch 'WPS-COMMAND-OUTPUT' -or $result.Output -notmatch 'WPS-COMMAND-SECRET') {
        throw 'Commanduitvoer ontbreekt in het resultaatvenster.'
    }
    $logs = @(Get-ChildItem -LiteralPath $logDirectory -File | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw })
    if (($logs -join "`n").Contains('WPS-COMMAND-SECRET') -or ($logs -join "`n").Contains($command)) {
        throw 'De opdracht of uitvoer is in een logboek opgeslagen.'
    }
    Write-Output 'PowerShell-opdracht uitgevoerd als huidige gebruiker; uitvoer was zichtbaar en opdracht/uitvoer zijn niet gelogd.'
} finally {
    if (Test-Path -LiteralPath $logDirectory) { Remove-Item -LiteralPath $logDirectory -Recurse -Force }
}
