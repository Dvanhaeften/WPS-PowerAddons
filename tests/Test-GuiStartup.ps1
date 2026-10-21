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
    if (-not $form) { throw 'WPS-PowerAddons hoofdvenster is niet geopend.' }
    $sidebar = $form.Controls | Where-Object Name -eq 'WPSSidebar' | Select-Object -First 1
    $main = $form.Controls | Where-Object Name -eq 'WPSMainContent' | Select-Object -First 1
    if (-not $sidebar -or -not $main) { throw 'Navigatiebalk of hoofdvlak ontbreekt.' }
    if ($main.Left -lt $sidebar.Right) {
        throw ('Hoofdvlak overlapt de navigatiebalk (main.Left={0}, sidebar.Right={1}).' -f $main.Left, $sidebar.Right)
    }
    if ($main.Width -le 0 -or $main.Right -gt $form.ClientSize.Width) {
        throw 'Hoofdvlak valt buiten het zichtbare clientgebied.'
    }
    $form.Close()
}.GetNewClosure())
$timer.Start()
Start-WPSApplication -RootPath $root
$timer.Dispose()
Write-Output 'Windows Forms-dashboard startte, hoofdvlak staat naast de navigatiebalk en sloot gecontroleerd.'
