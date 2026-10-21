[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
foreach ($library in @('Security.ps1', 'Validation.ps1', 'Logging.ps1', 'Configuration.ps1', 'ToolExecution.ps1', 'ToolManager.ps1', 'Application.ps1')) {
    . (Join-Path $root ('lib\{0}' -f $library))
}
Add-Type -AssemblyName System.Windows.Forms
$script:WPSUi = [pscustomobject]@{ Form = (New-Object Windows.Forms.Form) }
$script:WPSUi.Form.Text = 'PowerShell-dialogtest'
$script:WPSUi.Form.Show()
$script:WPSDialogTestError = $null
$timer = New-Object Windows.Forms.Timer
$timer.Interval = 300
$timer.Add_Tick({
    $dialog = [Windows.Forms.Application]::OpenForms | Where-Object Text -eq 'PowerShell-opdracht uitvoeren' | Select-Object -First 1
    if (-not $dialog) { return }
    $timer.Stop()
    try {
        $commandBox = $dialog.Controls | Where-Object { $_ -is [Windows.Forms.TextBox] } | Select-Object -First 1
        $confirmation = $dialog.Controls | Where-Object { $_ -is [Windows.Forms.CheckBox] } | Select-Object -First 1
        $run = $dialog.Controls | Where-Object { $_ -is [Windows.Forms.FlowLayoutPanel] } | ForEach-Object { $_.Controls } |
            Where-Object { $_ -is [Windows.Forms.Button] -and $_.Text -eq 'Opdracht uitvoeren' } | Select-Object -First 1
        if (-not $commandBox -or -not $confirmation -or -not $run) { throw 'PowerShell-dialogvelden ontbreken.' }
        $commandBox.Text = "Write-Output 'dialog test'"
        if ($run.Enabled) { throw 'Uitvoeren was actief voordat expliciet werd bevestigd.' }
        $confirmation.Checked = $true
        if (-not $run.Enabled) { throw 'Uitvoeren werd niet ingeschakeld na expliciete bevestiging.' }
        $run.PerformClick()
    } catch {
        $script:WPSDialogTestError = $_.Exception.Message
        $dialog.Close()
    }
}.GetNewClosure())
$timer.Start()
try {
    $command = Show-WPSPowerShellCommandDialog
    if ($script:WPSDialogTestError) { throw $script:WPSDialogTestError }
    if ($command -ne "Write-Output 'dialog test'") { throw 'De bevestigde opdracht is niet ongewijzigd teruggegeven.' }
    Write-Output 'PowerShell-invoerdialoog vereist expliciete bevestiging en geeft de gecontroleerde opdracht ongewijzigd door.'
} finally {
    $timer.Stop()
    $timer.Dispose()
    $script:WPSUi.Form.Close()
    $script:WPSUi.Form.Dispose()
}
