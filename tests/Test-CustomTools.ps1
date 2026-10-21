[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
$root = Split-Path -Parent $PSScriptRoot
$scratch = Join-Path $env:TEMP ('WPS-PowerAddons-customtest-{0}' -f [Guid]::NewGuid().ToString('N'))
$packageRoot = Join-Path $scratch 'package'
$fixtureRoot = Join-Path $scratch 'fixture'
$packagePath = Join-Path $scratch 'custom-tool.zip'
$traversalPath = Join-Path $scratch 'traversal.zip'
$sentinel = Join-Path $scratch 'executed.txt'
foreach ($library in @('Security.ps1', 'Validation.ps1', 'Logging.ps1', 'Configuration.ps1', 'ToolExecution.ps1', 'ToolManager.ps1')) {
    . (Join-Path $root ('lib\{0}' -f $library))
}

try {
    foreach ($folder in @('config', 'custom-tools')) { New-Item -ItemType Directory -Path (Join-Path $fixtureRoot $folder) -Force | Out-Null }
    Set-Content -LiteralPath (Join-Path $fixtureRoot 'config\tools.json') -Value '[]' -Encoding UTF8
    Copy-Item -LiteralPath (Join-Path $root 'config\settings.json') -Destination (Join-Path $fixtureRoot 'config\settings.json')
    Set-Content -LiteralPath (Join-Path $fixtureRoot 'custom-tools\custom-tools.json') -Value '[]' -Encoding UTF8
    New-Item -ItemType Directory -Path $packageRoot -Force | Out-Null
    $scriptText = @'
[CmdletBinding()]
param([switch]$ReadOnly)
Set-Content -LiteralPath '__SENTINEL__' -Value 'Executed'
Write-Output 'Import must not execute this script.'
'@.Replace('__SENTINEL__', $sentinel.Replace("'", "''"))
    $sourceScript = Join-Path $packageRoot 'payload.ps1'
    Set-Content -LiteralPath $sourceScript -Value $scriptText -Encoding UTF8
    $tool = [pscustomobject]@{
        Id = 'custom-import-test'; Name = 'Importtest'; Category = 'Support'
        Description = 'Test voor veilige maatwerkimport.'; Script = 'payload.ps1'
        RequiresAdmin = $false; RequiresConfirmation = $false; SupportsReadOnlyMode = $true
        Enabled = $true; Visible = $true; Favourite = $false; Version = '1.0.0'
        Author = 'Tests'; Source = 'Custom'; Tags = @('test')
        RestartBehaviour = 'None'; TimeoutSeconds = 30
        Sha256 = Get-WPSFileSha256 -LiteralPath $sourceScript
    }
    $tool | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $packageRoot 'metadata.json') -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $packageRoot 'README.txt') -Value 'Veilige importtest.' -Encoding UTF8
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [IO.Compression.ZipFile]::CreateFromDirectory($packageRoot, $packagePath)
    $imported = Import-WPSCustomToolPackage -PackagePath $packagePath -RootPath $fixtureRoot
    if ($imported.Id -ne 'custom-import-test') { throw 'De toolmetadata is niet correct geïmporteerd.' }
    if (Test-Path -LiteralPath $sentinel) { throw 'Het geïmporteerde script is uitgevoerd.' }
    $state = Read-WPSConfiguration -RootPath $fixtureRoot
    if ($state.Tools.Count -ne 1 -or $state.Tools[0].Sha256 -ine $tool.Sha256) { throw 'De geïmporteerde tool of hash is niet geregistreerd.' }
    $validCustom = $state.Tools[0]
    $invalid = $validCustom | Select-Object *
    $invalid.Id = 'missing-script-test'
    $invalid.Script = 'custom-tools\missing-script-test\missing.ps1'
    $customPath = Join-Path $fixtureRoot 'custom-tools\custom-tools.json'
    Save-WPSJsonAtomic -Value @($validCustom, $invalid) -Path $customPath
    $partialState = Read-WPSConfiguration -RootPath $fixtureRoot
    if ($partialState.Tools.Count -ne 1 -or $partialState.Errors.Count -eq 0) {
        throw 'Een ongeldige maatwerktool verhinderde niet dat geldige configuratie werd geladen.'
    }
    Save-WPSJsonAtomic -Value @($validCustom) -Path $customPath
    $state = Read-WPSConfiguration -RootPath $fixtureRoot
    $exportPath = Join-Path $scratch 'export.zip'
    Export-WPSCustomTool -Tool $state.Tools[0] -RootPath $fixtureRoot -Destination $exportPath
    $export = [IO.Compression.ZipFile]::OpenRead($exportPath)
    try {
        $names = @($export.Entries | Select-Object -ExpandProperty FullName)
        foreach ($required in @('metadata.json', 'README.txt', 'payload.ps1')) {
            if ($required -notin $names) { throw ('Export mist {0}.' -f $required) }
        }
    } finally { $export.Dispose() }

    $installedScript = Join-Path $fixtureRoot $state.Tools[0].Script
    Add-Content -LiteralPath $installedScript -Value '# Modified after registration'
    $hashResult = Invoke-WPSPowerAddonTool -Tool $state.Tools[0] -RootPath $fixtureRoot -LogDirectory $state.LogDirectory -Settings $state.Settings
    if ($hashResult.ExitCode -ne 9 -or $hashResult.Status -ne 'ScriptHashChanged' -or (Test-Path -LiteralPath $sentinel)) {
        throw 'Een gewijzigde script-hash werd niet vóór uitvoering geblokkeerd.'
    }
    $definition = $state.Tools[0] | Select-Object *
    $definition.Id = 'custom-import-renamed'
    $definition.Name = 'Importtest gewijzigd'
    $definition.Category = 'Beheer'
    $definition.Enabled = $false
    $updated = Set-WPSCustomTool -ExistingTool $state.Tools[0] -Definition $definition -RootPath $fixtureRoot
    $state = Read-WPSConfiguration -RootPath $fixtureRoot
    if ($state.Tools.Count -ne 1 -or $state.Tools[0].Id -ne 'custom-import-renamed' -or $state.Tools[0].Enabled) {
        throw 'Aangepaste tool kon niet veilig worden hernoemd, gewijzigd of uitgeschakeld.'
    }

    $stream = [IO.File]::Open($traversalPath, [IO.FileMode]::CreateNew)
    $archive = New-Object IO.Compression.ZipArchive($stream, [IO.Compression.ZipArchiveMode]::Create)
    $entry = $archive.CreateEntry('../outside.txt')
    $writer = New-Object IO.StreamWriter($entry.Open())
    $writer.Write('not extracted'); $writer.Dispose(); $archive.Dispose()
    $rejected = $false
    try { Import-WPSCustomToolPackage -PackagePath $traversalPath -RootPath $fixtureRoot | Out-Null }
    catch { $rejected = $true }
    if (-not $rejected) { throw 'ZIP-padtraversal is niet afgewezen.' }
    if (Test-Path -LiteralPath (Join-Path $scratch 'outside.txt')) { throw 'ZIP-inhoud is buiten de validatiemap geschreven.' }

    Remove-WPSCustomTool -Tool $updated -RootPath $fixtureRoot -DeleteScript
    $afterDelete = Read-WPSConfiguration -RootPath $fixtureRoot
    if ($afterDelete.Tools.Count -ne 0) { throw 'De verwijderde tool staat nog in de registry.' }
    if (Test-Path -LiteralPath (Join-Path $fixtureRoot 'custom-tools\custom-import-test')) { throw 'Scriptmap bleef bestaan na expliciete verwijdering.' }
    Write-Output 'Maatwerkimport/export, SHA-256, niet-uitvoeren, wijzigen/uitschakelen, ZIP-traversal en verwijdering geslaagd.'
} finally {
    if (Test-Path -LiteralPath $scratch) { Remove-Item -LiteralPath $scratch -Recurse -Force }
}
