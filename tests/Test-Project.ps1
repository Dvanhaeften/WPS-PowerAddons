[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
$root = Split-Path -Parent $PSScriptRoot
$failures = New-Object System.Collections.Generic.List[string]

function Assert-WPS {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { $failures.Add($Message) }
}

foreach ($required in @('WPS-PowerAddons.ps1', 'bootstrap.ps1', 'install.ps1', 'Start-WPS-PowerAddons.cmd', 'README.md', 'CHANGELOG.md', 'LICENSE.txt', 'config\tools.json', 'config\settings.json')) {
    Assert-WPS (Test-Path -LiteralPath (Join-Path $root $required) -PathType Leaf) ('Bestand ontbreekt: {0}' -f $required)
}

foreach ($scriptFile in @(Get-ChildItem -LiteralPath $root -Filter '*.ps1' -File -Recurse)) {
    $tokens = $null
    $parseErrors = $null
    [Management.Automation.Language.Parser]::ParseFile($scriptFile.FullName, [ref]$tokens, [ref]$parseErrors) | Out-Null
    foreach ($errorRecord in $parseErrors) { $failures.Add(('{0}:{1}: {2}' -f $scriptFile.FullName, $errorRecord.Extent.StartLineNumber, $errorRecord.Message)) }
    $source = Get-Content -LiteralPath $scriptFile.FullName -Raw
    Assert-WPS ($source -notmatch '(?m)^\s*#Requires\s+-RunAsAdministrator') ('Administratordirective gevonden: {0}' -f $scriptFile.FullName)
}

try {
    $toolData = ConvertFrom-Json -InputObject (Get-Content -LiteralPath (Join-Path $root 'config\tools.json') -Raw -Encoding UTF8) -ErrorAction Stop
    $tools = @($toolData | ForEach-Object { $_ })
}
catch { $failures.Add(('tools.json: {0}' -f $_.Exception.Message)); $tools = @() }
try { $settings = ConvertFrom-Json -InputObject (Get-Content -LiteralPath (Join-Path $root 'config\settings.json') -Raw -Encoding UTF8) -ErrorAction Stop }
catch { $failures.Add(('settings.json: {0}' -f $_.Exception.Message)); $settings = $null }
Assert-WPS (@($tools | Select-Object -ExpandProperty Id -Unique).Count -eq $tools.Count) 'Tool-ID''s zijn niet uniek.'
foreach ($tool in $tools) {
    $scriptPath = [IO.Path]::GetFullPath((Join-Path $root $tool.Script))
    Assert-WPS ($scriptPath.StartsWith(($root.TrimEnd('\') + '\'), [StringComparison]::OrdinalIgnoreCase)) ('Scriptpad ontsnapt uit root: {0}' -f $tool.Id)
    Assert-WPS (Test-Path -LiteralPath $scriptPath -PathType Leaf) ('Toolscript ontbreekt: {0}' -f $tool.Script)
    Assert-WPS ($tool.Script -notmatch '(^|[\\/])\.\.([\\/]|$)') ('Traversalsegment gevonden: {0}' -f $tool.Id)
    Assert-WPS ($tool.Script -notmatch '^[A-Za-z]:|^[/\\]') ('Absoluut scriptpad gevonden: {0}' -f $tool.Id)
}
Assert-WPS (@($tools).Count -ge 21) 'Niet alle initiële tools zijn geregistreerd.'

. (Join-Path $root 'lib\Security.ps1')
. (Join-Path $root 'lib\Validation.ps1')
. (Join-Path $root 'lib\Logging.ps1')
. (Join-Path $root 'lib\Configuration.ps1')
. (Join-Path $root 'lib\ToolManager.ps1')
$settingsCheck = Test-WPSSettings -Settings $settings
Assert-WPS $settingsCheck.Valid ('settings.json faalt validatie: {0}' -f ($settingsCheck.Errors -join ' '))
$configuration = Read-WPSConfiguration -RootPath $root
Assert-WPS ($configuration.Tools.Count -eq $tools.Count) ('Configuratie laadde {0} van {1} ingebouwde tools.' -f $configuration.Tools.Count, $tools.Count)
Assert-WPS ($configuration.Errors.Count -eq 0) ('Validatiefouten in toolconfiguratie: {0}' -f ($configuration.Errors -join ' '))
Assert-WPS (Test-WPSToolId 'network-diagnostics') 'Geldige ID werd afgewezen.'
Assert-WPS (-not (Test-WPSToolId '..\escape')) 'Onveilige ID werd geaccepteerd.'
try {
    Resolve-WPSRelativePath -RelativePath '..\escape.ps1' -RootPath $root | Out-Null
    $failures.Add('Padvalidatie accepteerde ..')
} catch { }

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Error $_ }
    exit 1
}
Write-Output ('Projectvalidatie geslaagd: {0} PowerShell-bestanden, {1} ingebouwde tools.' -f @(Get-ChildItem -LiteralPath $root -Filter '*.ps1' -File -Recurse).Count, $tools.Count)
