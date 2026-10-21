[CmdletBinding()]
param(
    [ValidateSet('CurrentUser', 'AllUsers', 'Portable')]
    [string]$Scope = 'CurrentUser',
    [string]$PackagePath,
    [string]$PackageUrl,
    [string]$ExpectedSha256,
    [switch]$ElevatedWorker
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

function Test-BootstrapAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Resolve-BootstrapProjectRoot {
    param([string]$Path)
    $required = @('WPS-PowerAddons.ps1', 'config\tools.json', 'lib\Security.ps1', 'bootstrap.ps1')
    foreach ($file in $required) {
        if (-not (Test-Path -LiteralPath (Join-Path $Path $file) -PathType Leaf)) {
            throw ('Verplicht projectbestand ontbreekt: {0}' -f $file)
        }
    }
    return [IO.Path]::GetFullPath($Path)
}

function Expand-BootstrapZipSafely {
    param([string]$ArchivePath, [string]$Destination)
    Add-Type -AssemblyName System.IO.Compression
    $archive = [IO.Compression.ZipFile]::OpenRead($ArchivePath)
    try {
        $destinationRoot = [IO.Path]::GetFullPath($Destination).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
        foreach ($entry in $archive.Entries) {
            $name = $entry.FullName.Replace('\', '/')
            if ($name.StartsWith('/') -or $name -match '(^|/)\.\.(/|$)' -or $name -match '^[a-zA-Z]:') {
                throw ('Onveilig pad in ZIP-pakket: {0}' -f $entry.FullName)
            }
            $target = [IO.Path]::GetFullPath((Join-Path $Destination $entry.FullName))
            if (-not $target.StartsWith($destinationRoot, [StringComparison]::OrdinalIgnoreCase)) {
                throw ('ZIP-pad valt buiten de tijdelijke map: {0}' -f $entry.FullName)
            }
        }
        [IO.Compression.ZipFile]::ExtractToDirectory($ArchivePath, $Destination)
    } finally {
        $archive.Dispose()
    }
}

function Get-BootstrapProjectRoot {
    param([string]$ExtractionPath)
    if (Test-Path -LiteralPath (Join-Path $ExtractionPath 'WPS-PowerAddons.ps1') -PathType Leaf) {
        return Resolve-BootstrapProjectRoot -Path $ExtractionPath
    }
    $matches = @(Get-ChildItem -LiteralPath $ExtractionPath -Filter 'WPS-PowerAddons.ps1' -File -Recurse -ErrorAction Stop |
        Where-Object { Test-Path -LiteralPath (Join-Path $_.DirectoryName 'config\tools.json') -PathType Leaf } |
        Select-Object -First 2)
    if ($matches.Count -ne 1) { throw 'Het ZIP-pakket bevat niet exact één geldige WPS-PowerAddons-projectmap.' }
    return Resolve-BootstrapProjectRoot -Path $matches[0].DirectoryName
}

function Start-BootstrapElevated {
    param([string]$ScriptPath, [string]$PackagePath, [string]$PackageUrl, [string]$ExpectedSha256)
    Add-Type -AssemblyName System.Windows.Forms
    $answer = [Windows.Forms.MessageBox]::Show('AllUsers installeert WPS-PowerAddons voor alle gebruikers onder ProgramData. Windows vraagt hiervoor administratorbevestiging. Doorgaan?', 'WPS-PowerAddons - Machinebrede installatie', [Windows.Forms.MessageBoxButtons]::YesNo, [Windows.Forms.MessageBoxIcon]::Warning, [Windows.Forms.MessageBoxDefaultButton]::Button2)
    if ($answer -ne [Windows.Forms.DialogResult]::Yes) { Write-Output 'Installatie geannuleerd.'; exit 2 }
    $escapedScript = $ScriptPath.Replace("'", "''")
    $call = "& '$escapedScript' -Scope AllUsers -ElevatedWorker"
    foreach ($pair in @(@('-PackagePath', $PackagePath), @('-PackageUrl', $PackageUrl), @('-ExpectedSha256', $ExpectedSha256))) {
        if (-not [string]::IsNullOrWhiteSpace($pair[1])) { $call += (' {0} ''{1}''' -f $pair[0], $pair[1].Replace("'", "''")) }
    }
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($call))
    try {
        $process = Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList ('-STA -NoProfile -ExecutionPolicy Bypass -EncodedCommand {0}' -f $encoded) -Verb RunAs -Wait -PassThru -ErrorAction Stop
        return $process.ExitCode
    } catch [System.ComponentModel.Win32Exception] {
        if ($_.Exception.NativeErrorCode -eq 1223) {
            Write-Output 'UAC-verzoek geannuleerd. Er zijn geen administratorreferenties opgeslagen.'
            return 2
        }
        throw
    }
}

$temporaryRoot = $null
try {
    if ($Scope -eq 'AllUsers' -and -not (Test-BootstrapAdministrator)) {
        $elevationResult = Start-BootstrapElevated -ScriptPath $MyInvocation.MyCommand.Path -PackagePath $PackagePath -PackageUrl $PackageUrl -ExpectedSha256 $ExpectedSha256
        if ($elevationResult -ne 0) { exit $elevationResult }
        $installedMain = Join-Path $env:ProgramData 'WPS-PowerAddons\WPS-PowerAddons.ps1'
        Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList ('-STA -NoProfile -ExecutionPolicy Bypass -File "{0}"' -f $installedMain)
        Write-Output 'WPS-PowerAddons is geïnstalleerd en gestart als de aangemelde gebruiker.'
        exit 0
    }
    if ($PackagePath -and $PackageUrl) { throw 'Gebruik PackagePath of PackageUrl, niet beide tegelijk.' }
    $sourcePath = $null
    if ($PackageUrl) {
        if ($PackageUrl -notmatch '^https://') { throw 'Pakketten mogen alleen via HTTPS worden opgehaald.' }
        $temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) ('WPS-PowerAddons-{0}' -f [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $temporaryRoot | Out-Null
        $archivePath = Join-Path $temporaryRoot 'WPS-PowerAddons.zip'
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $PackageUrl -OutFile $archivePath -UseBasicParsing -ErrorAction Stop
        $PackagePath = $archivePath
    }
    if ($PackagePath) {
        if (-not (Test-Path -LiteralPath $PackagePath -PathType Leaf) -or [IO.Path]::GetExtension($PackagePath) -ine '.zip') {
            throw 'PackagePath moet verwijzen naar een bestaand ZIP-bestand.'
        }
        if ($ExpectedSha256) {
            if ($ExpectedSha256 -notmatch '^[A-Fa-f0-9]{64}$') { throw 'ExpectedSha256 moet een SHA-256-hexwaarde van 64 tekens zijn.' }
            $hash = (Get-FileHash -LiteralPath $PackagePath -Algorithm SHA256).Hash
            if ($hash -ine $ExpectedSha256) { throw ('SHA-256-validatie mislukt. Verwacht {0}; ontvangen {1}.' -f $ExpectedSha256, $hash) }
        }
        if (-not $temporaryRoot) {
            $temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) ('WPS-PowerAddons-{0}' -f [Guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $temporaryRoot | Out-Null
        }
        $extractionPath = Join-Path $temporaryRoot 'extracted'
        New-Item -ItemType Directory -Path $extractionPath | Out-Null
        Expand-BootstrapZipSafely -ArchivePath $PackagePath -Destination $extractionPath
        $sourcePath = Get-BootstrapProjectRoot -ExtractionPath $extractionPath
    } else {
        $sourcePath = Resolve-BootstrapProjectRoot -Path (Split-Path -Parent $MyInvocation.MyCommand.Path)
    }

    if ($Scope -eq 'Portable') {
        if ($PackagePath) {
            $portableRoot = Join-Path (Get-Location).Path 'WPS-PowerAddons-Portable'
            if (Test-Path -LiteralPath $portableRoot) { throw ('Portable doelmap bestaat al: {0}' -f $portableRoot) }
            Copy-Item -LiteralPath $sourcePath -Destination $portableRoot -Recurse
            $sourcePath = $portableRoot
        }
        $settingsPath = Join-Path $sourcePath 'config\settings.json'
        if (Test-Path -LiteralPath $settingsPath) {
            $settings = Get-Content -LiteralPath $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $settings.InstallScope = 'Portable'
            $settings | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $settingsPath -Encoding UTF8
        }
        Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList ('-STA -NoProfile -ExecutionPolicy Bypass -File "{0}"' -f (Join-Path $sourcePath 'WPS-PowerAddons.ps1'))
        Write-Output 'WPS-PowerAddons is gestart in portable modus.'
        exit 0
    }

    if ($Scope -eq 'CurrentUser') {
        $target = Join-Path $env:LOCALAPPDATA 'WPS-PowerAddons'
    } else {
        if (-not $env:ProgramData) { throw 'ProgramData is niet beschikbaar.' }
        $target = Join-Path $env:ProgramData 'WPS-PowerAddons'
    }
    $parent = Split-Path -Parent $target
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    $stage = Join-Path $parent ('.WPS-PowerAddons-stage-{0}' -f [Guid]::NewGuid().ToString('N'))
    $previous = Join-Path $parent ('.WPS-PowerAddons-previous-{0}' -f [Guid]::NewGuid().ToString('N'))
    try {
        Copy-Item -LiteralPath $sourcePath -Destination $stage -Recurse
        if (Test-Path -LiteralPath $target -PathType Container) {
            foreach ($preserved in @('config\settings.json', 'custom-tools', 'logs', 'Logs', 'user-preferences.json')) {
                $oldPath = Join-Path $target $preserved
                $newPath = Join-Path $stage $preserved
                if (Test-Path -LiteralPath $oldPath) {
                    $newParent = Split-Path -Parent $newPath
                    if (-not (Test-Path -LiteralPath $newParent)) { New-Item -ItemType Directory -Path $newParent -Force | Out-Null }
                    if (Test-Path -LiteralPath $newPath) { Remove-Item -LiteralPath $newPath -Recurse -Force }
                    Copy-Item -LiteralPath $oldPath -Destination $newPath -Recurse -Force
                }
            }
            [IO.Directory]::Move($target, $previous)
        }
        try {
            [IO.Directory]::Move($stage, $target)
        } catch {
            if (Test-Path -LiteralPath $previous -PathType Container -and -not (Test-Path -LiteralPath $target)) {
                [IO.Directory]::Move($previous, $target)
            }
            throw
        }
        if (Test-Path -LiteralPath $previous) { Remove-Item -LiteralPath $previous -Recurse -Force }
        $settingsFile = Join-Path $target 'config\settings.json'
        $settings = Get-Content -LiteralPath $settingsFile -Raw -Encoding UTF8 | ConvertFrom-Json
        $settings.InstallScope = $Scope
        $settings | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $settingsFile -Encoding UTF8
        if (-not $ElevatedWorker) {
            Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList ('-STA -NoProfile -ExecutionPolicy Bypass -File "{0}"' -f (Join-Path $target 'WPS-PowerAddons.ps1'))
            Write-Output ('WPS-PowerAddons is geïnstalleerd en gestart voor scope {0}.' -f $Scope)
        } else {
            Write-Output 'WPS-PowerAddons is machinebreed geïnstalleerd. De niet-verhoogde aanroeper start de GUI.'
        }
    } finally {
        if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue }
        if (Test-Path -LiteralPath $previous) { Remove-Item -LiteralPath $previous -Recurse -Force -ErrorAction SilentlyContinue }
    }
} catch {
    $message = 'WPS-PowerAddons installatie mislukt: {0}' -f $_.Exception.Message
    Write-Error $message
    try {
        Add-Type -AssemblyName System.Windows.Forms
        [Windows.Forms.MessageBox]::Show($message, 'WPS-PowerAddons - Installatiefout', 'OK', 'Error') | Out-Null
    } catch { Write-Warning ('GUI-melding kon niet worden geopend: {0}' -f $_.Exception.Message) }
    exit 1
} finally {
    if ($temporaryRoot -and (Test-Path -LiteralPath $temporaryRoot)) {
        Remove-Item -LiteralPath $temporaryRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
