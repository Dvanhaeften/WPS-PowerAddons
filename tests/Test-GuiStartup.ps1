[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
foreach ($library in @('Security.ps1', 'Validation.ps1', 'Logging.ps1', 'Configuration.ps1', 'ToolExecution.ps1', 'ToolManager.ps1', 'Application.ps1')) {
    . (Join-Path $root ('lib\{0}' -f $library))
}
Add-Type -AssemblyName System.Windows.Forms
$timer = New-Object Windows.Forms.Timer
$timer.Interval = 1600
$timer.Add_Tick({
    $timer.Stop()
    $form = [Windows.Forms.Application]::OpenForms | Where-Object Text -eq 'WPS-PowerAddons' | Select-Object -First 1
    if ($form) { $form.Close() }
}.GetNewClosure())
$timer.Start()
Start-WPSApplication -RootPath $root
$timer.Dispose()
Write-Output 'Windows Forms-dashboard startte en sloot gecontroleerd.'
