[CmdletBinding()]
param([string]$OutputPath)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($OutputPath)) { $OutputPath = Join-Path $root 'WPS-PowerAddons.zip' }
$OutputPath = [IO.Path]::GetFullPath($OutputPath)
if (Test-Path -LiteralPath $OutputPath) { throw ('Doelbestand bestaat al; kies een andere locatie of verwijder het bestand bewust: {0}' -f $OutputPath) }
$stage = Join-Path ([IO.Path]::GetTempPath()) ('WPS-PowerAddons-package-{0}' -f [Guid]::NewGuid().ToString('N'))
try {
    New-Item -ItemType Directory -Path $stage | Out-Null
    foreach ($item in Get-ChildItem -LiteralPath $root -Force) {
        if ($item.Name -in @('.git', 'logs', 'WPS-PowerAddons.zip') -or $item.Name.StartsWith('.WPS-PowerAddons-')) { continue }
        if ($item.Name -eq 'custom-tools') {
            $destination = Join-Path $stage 'custom-tools'
            New-Item -ItemType Directory -Path $destination -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $destination 'custom-tools.json') -Value '[]' -Encoding UTF8
            continue
        }
        Copy-Item -LiteralPath $item.FullName -Destination $stage -Recurse -Force
    }
    $required = @('WPS-PowerAddons.ps1', 'bootstrap.ps1', 'install.ps1', 'Start-WPS-PowerAddons.cmd', 'config\tools.json', 'config\settings.json', 'custom-tools\custom-tools.json')
    foreach ($relative in $required) {
        if (-not (Test-Path -LiteralPath (Join-Path $stage $relative) -PathType Leaf)) { throw ('Verplicht pakketbestand ontbreekt: {0}' -f $relative) }
    }
    $null = Get-Content -LiteralPath (Join-Path $stage 'config\tools.json') -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
    $null = Get-Content -LiteralPath (Join-Path $stage 'config\settings.json') -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
    $outputDirectory = Split-Path -Parent $OutputPath
    if (-not (Test-Path -LiteralPath $outputDirectory -PathType Container)) { New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [IO.Compression.ZipFile]::CreateFromDirectory($stage, $OutputPath, [IO.Compression.CompressionLevel]::Optimal, $false)
    $hash = (Get-FileHash -LiteralPath $OutputPath -Algorithm SHA256).Hash
    Write-Output ('Pakket gemaakt: {0}' -f $OutputPath)
    Write-Output ('SHA-256: {0}' -f $hash)
} finally {
    if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
}
