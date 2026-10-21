[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

try {
    $rootPath = Split-Path -Parent $MyInvocation.MyCommand.Path
    foreach ($library in @('Security.ps1', 'Validation.ps1', 'Logging.ps1', 'Configuration.ps1', 'ToolExecution.ps1', 'ToolManager.ps1', 'Application.ps1')) {
        $libraryPath = Join-Path $rootPath ('lib\{0}' -f $library)
        if (-not (Test-Path -LiteralPath $libraryPath -PathType Leaf)) { throw ('Bibliotheekbestand ontbreekt: {0}' -f $library) }
        . $libraryPath
    }
    Start-WPSApplication -RootPath $rootPath
} catch {
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
    $message = 'WPS-PowerAddons kan niet worden gestart: {0}' -f $_.Exception.Message
    try { [Windows.Forms.MessageBox]::Show($message, 'WPS-PowerAddons - Fout', 'OK', 'Error') | Out-Null }
    catch { Write-Error $message }
    exit 1
}
