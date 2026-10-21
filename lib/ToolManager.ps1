function Save-WPSCustomTools {
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()][array]$Tools, [Parameter(Mandatory = $true)][string]$RootPath)
    Assert-WPSNoReparsePath -Path (Join-Path $RootPath 'custom-tools\custom-tools.json') -RootPath $RootPath
    foreach ($tool in $Tools) {
        $check = Test-WPSToolDefinition -Tool $tool -RootPath $RootPath -Custom
        if (-not $check.Valid) { throw ('Tool {0} is ongeldig: {1}' -f $tool.Id, ($check.Errors -join ' ')) }
    }
    $duplicate = @($Tools | Group-Object -Property Id | Where-Object Count -gt 1)
    if ($duplicate.Count -gt 0) { throw ('Dubbele tool-ID: {0}' -f $duplicate[0].Name) }
    Save-WPSJsonAtomic -Value @($Tools) -Path (Join-Path $RootPath 'custom-tools\custom-tools.json') -Backup
}

function New-WPSCustomTool {
    param(
        [Parameter(Mandatory = $true)]$Definition,
        [Parameter(Mandatory = $true)][string]$SourceScript,
        [Parameter(Mandatory = $true)][string]$RootPath
    )
    if (-not (Test-WPSToolId ([string]$Definition.Id))) { throw 'Gebruik voor de tool-ID alleen kleine letters, cijfers en koppeltekens.' }
    if ([IO.Path]::GetExtension($SourceScript) -ine '.ps1' -or -not (Test-Path -LiteralPath $SourceScript -PathType Leaf)) {
        throw 'Selecteer een bestaand .ps1-bestand.'
    }
    $configuration = Read-WPSConfiguration -RootPath $RootPath
    $existing = @($configuration.Tools | Where-Object Id -eq $Definition.Id)
    if ($existing.Count -gt 0) { throw 'Deze tool-ID is al in gebruik.' }
    $iconValue = ''
    if ($null -ne $Definition.PSObject.Properties['Icon']) { $iconValue = [string]$Definition.Icon }
    $folder = Join-Path $RootPath ('custom-tools\{0}' -f $Definition.Id)
    Assert-WPSNoReparsePath -Path $folder -RootPath $RootPath
    $folderExists = Test-Path -LiteralPath $folder
    if ($folderExists) {
        $sourceFull = [IO.Path]::GetFullPath($SourceScript)
        $folderPrefix = [IO.Path]::GetFullPath($folder).TrimEnd('\') + '\'
        if (-not $sourceFull.StartsWith($folderPrefix, [StringComparison]::OrdinalIgnoreCase)) {
            throw 'De doelmap bestaat al. Kies een andere ID of beheer de bestaande tool.'
        }
    } else {
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
    }
    try {
        $scriptName = [IO.Path]::GetFileName($SourceScript)
        if (-not (Test-WPSSafeFileName -Name $scriptName)) { throw 'De bestandsnaam bevat onveilige tekens of een gereserveerde Windows-naam.' }
        $destination = Join-Path $folder $scriptName
        if ([IO.Path]::GetFullPath($SourceScript) -ine [IO.Path]::GetFullPath($destination)) {
            Copy-Item -LiteralPath $SourceScript -Destination $destination -ErrorAction Stop
        }
        $tool = [pscustomobject]@{
            Id = [string]$Definition.Id; Name = [string]$Definition.Name
            Category = [string]$Definition.Category; Description = [string]$Definition.Description
            Script = 'custom-tools\{0}\{1}' -f $Definition.Id, $scriptName
            RequiresAdmin = [bool]$Definition.RequiresAdmin
            RequiresConfirmation = [bool]$Definition.RequiresConfirmation
            SupportsReadOnlyMode = [bool]$Definition.SupportsReadOnlyMode
            Enabled = [bool]$Definition.Enabled; Visible = $true
            Favourite = [bool]$Definition.Favourite; Version = [string]$Definition.Version
            Author = [string]$Definition.Author; Source = 'Custom'; Tags = @($Definition.Tags)
            Icon = $iconValue
            RestartBehaviour = [string]$Definition.RestartBehaviour
            TimeoutSeconds = [int]$Definition.TimeoutSeconds
            Sha256 = Get-WPSFileSha256 -LiteralPath $destination
        }
        $result = Test-WPSToolDefinition -Tool $tool -RootPath $RootPath -Custom
        if (-not $result.Valid) { throw ('Toolconfiguratie is ongeldig: {0}' -f ($result.Errors -join ' ')) }
        $configPath = Join-Path $RootPath 'custom-tools\custom-tools.json'
        $tools = @()
        if (Test-Path -LiteralPath $configPath) {
            $existingData = ConvertFrom-Json -InputObject (Get-Content -LiteralPath $configPath -Raw -Encoding UTF8)
            $tools = @($existingData | ForEach-Object { $_ })
        }
        Save-WPSCustomTools -Tools (@($tools) + @($tool)) -RootPath $RootPath
        return $tool
    } catch {
        if (-not $folderExists -and (Test-Path -LiteralPath $folder)) { Remove-Item -LiteralPath $folder -Recurse -Force }
        throw
    }
}

function New-WPSCustomToolFromTemplate {
    param([string]$Name, [string]$Id, [string]$RootPath, [string]$Editor = 'notepad.exe')
    if (-not (Test-WPSToolId $Id)) { throw 'Tool-ID is ongeldig.' }
    $folder = Join-Path $RootPath ('custom-tools\{0}' -f $Id)
    if (Test-Path -LiteralPath $folder) { throw 'De doelmap bestaat al.' }
    New-Item -ItemType Directory -Path $folder -Force | Out-Null
    $target = Join-Path $folder ('{0}.ps1' -f $Id)
    Copy-Item -LiteralPath (Join-Path $RootPath 'templates\Example-Tool.ps1') -Destination $target
    Start-Process -FilePath $Editor -ArgumentList ('"{0}"' -f $target) -ErrorAction Stop | Out-Null
    return $target
}

function Set-WPSCustomTool {
    param(
        [Parameter(Mandatory = $true)]$ExistingTool,
        [Parameter(Mandatory = $true)]$Definition,
        [string]$SourceScript,
        [Parameter(Mandatory = $true)][string]$RootPath
    )
    if ($ExistingTool.Source -ne 'Custom') { throw 'Ingebouwde tools kunnen niet worden bewerkt.' }
    if (-not (Test-WPSToolId ([string]$Definition.Id))) { throw 'Tool-ID is ongeldig.' }
    $iconValue = ''
    if ($null -ne $Definition.PSObject.Properties['Icon']) { $iconValue = [string]$Definition.Icon }
    $state = Read-WPSConfiguration -RootPath $RootPath
    $conflict = @($state.Tools | Where-Object { $_.Id -eq $Definition.Id -and $_.Id -ne $ExistingTool.Id })
    if ($conflict.Count -gt 0) { throw 'Deze tool-ID is al in gebruik.' }
    if ([string]::IsNullOrWhiteSpace($SourceScript)) {
        $sourceFull = Resolve-WPSRelativePath -RelativePath $ExistingTool.Script -RootPath $RootPath -RequireExisting
    } else {
        if ([IO.Path]::GetExtension($SourceScript) -ine '.ps1' -or -not (Test-Path -LiteralPath $SourceScript -PathType Leaf)) {
            throw 'Selecteer een bestaand .ps1-bestand.'
        }
        $sourceFull = [IO.Path]::GetFullPath($SourceScript)
    }
    $newFolder = Join-Path $RootPath ('custom-tools\{0}' -f $Definition.Id)
    $oldFolder = Join-Path $RootPath ('custom-tools\{0}' -f $ExistingTool.Id)
    Assert-WPSNoReparsePath -Path $newFolder -RootPath $RootPath
    Assert-WPSNoReparsePath -Path $oldFolder -RootPath $RootPath
    if ($Definition.Id -ne $ExistingTool.Id -and (Test-Path -LiteralPath $newFolder)) { throw 'De doelmap bestaat al.' }
    if (-not (Test-Path -LiteralPath $newFolder)) { New-Item -ItemType Directory -Path $newFolder | Out-Null }
    $destination = Join-Path $newFolder ([IO.Path]::GetFileName($sourceFull))
    if (-not (Test-WPSSafeFileName -Name ([IO.Path]::GetFileName($sourceFull)))) { throw 'De bestandsnaam bevat onveilige tekens of een gereserveerde Windows-naam.' }
    $temporary = Join-Path $newFolder ('.{0}.{1}.tmp' -f [IO.Path]::GetFileName($sourceFull), [Guid]::NewGuid().ToString('N'))
    try {
        Copy-Item -LiteralPath $sourceFull -Destination $temporary -Force
        $hash = Get-WPSFileSha256 -LiteralPath $temporary
        if (Test-Path -LiteralPath $destination) {
            $backupDirectory = Join-Path $RootPath 'custom-tools\backups'
            if (-not (Test-Path -LiteralPath $backupDirectory)) { New-Item -ItemType Directory -Path $backupDirectory -Force | Out-Null }
            Copy-Item -LiteralPath $destination -Destination (Join-Path $backupDirectory ('{0}-{1}.ps1' -f $ExistingTool.Id, [DateTime]::Now.ToString('yyyyMMdd-HHmmss')))
            Remove-Item -LiteralPath $destination -Force
        }
        Move-Item -LiteralPath $temporary -Destination $destination -Force
        $updated = [pscustomobject]@{
            Id = [string]$Definition.Id; Name = [string]$Definition.Name; Category = [string]$Definition.Category
            Description = [string]$Definition.Description; Script = ('custom-tools\{0}\{1}' -f $Definition.Id, [IO.Path]::GetFileName($destination))
            RequiresAdmin = [bool]$Definition.RequiresAdmin; RequiresConfirmation = [bool]$Definition.RequiresConfirmation
            SupportsReadOnlyMode = [bool]$Definition.SupportsReadOnlyMode; Enabled = [bool]$Definition.Enabled
            Visible = $true; Favourite = [bool]$Definition.Favourite; Version = [string]$Definition.Version
            Author = [string]$Definition.Author; Source = 'Custom'; Tags = @($Definition.Tags)
            Icon = $iconValue
            RestartBehaviour = [string]$Definition.RestartBehaviour; TimeoutSeconds = [int]$Definition.TimeoutSeconds; Sha256 = $hash
        }
        $remaining = @($state.Tools | Where-Object { $_.Id -ne $ExistingTool.Id -and $_.Source -eq 'Custom' })
        Save-WPSCustomTools -Tools (@($remaining) + @($updated)) -RootPath $RootPath
        if ($Definition.Id -ne $ExistingTool.Id -and (Test-Path -LiteralPath $oldFolder -PathType Container)) {
            $backupRoot = Join-Path $RootPath 'custom-tools\backups'
            if (-not (Test-Path -LiteralPath $backupRoot)) { New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null }
            $backupFolder = Join-Path $backupRoot ('{0}-{1}' -f $ExistingTool.Id, [DateTime]::Now.ToString('yyyyMMdd-HHmmss-fff'))
            Move-Item -LiteralPath $oldFolder -Destination $backupFolder -ErrorAction Stop
        }
        return $updated
    } finally {
        if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue }
    }
}

function Remove-WPSCustomTool {
    param([Parameter(Mandatory = $true)]$Tool, [string]$RootPath, [switch]$DeleteScript)
    if ($Tool.Source -ne 'Custom') { throw 'Ingebouwde tools kunnen niet worden verwijderd.' }
    $configPath = Join-Path $RootPath 'custom-tools\custom-tools.json'
    $existingData = ConvertFrom-Json -InputObject (Get-Content -LiteralPath $configPath -Raw -Encoding UTF8)
    $tools = @($existingData | ForEach-Object { $_ } | Where-Object Id -ne $Tool.Id)
    $backupDirectory = Join-Path $RootPath 'custom-tools\backups'
    if (-not (Test-Path -LiteralPath $backupDirectory)) { New-Item -ItemType Directory -Path $backupDirectory -Force | Out-Null }
    $backupPath = Join-Path $backupDirectory ('{0}-{1}.json' -f $Tool.Id, [DateTime]::Now.ToString('yyyyMMdd-HHmmss'))
    Copy-Item -LiteralPath $configPath -Destination $backupPath
    Save-WPSCustomTools -Tools $tools -RootPath $RootPath
    if ($DeleteScript) {
        $toolFolder = Join-Path $RootPath ('custom-tools\{0}' -f $Tool.Id)
        $resolved = [IO.Path]::GetFullPath($toolFolder)
        $customRoot = [IO.Path]::GetFullPath((Join-Path $RootPath 'custom-tools')) + [IO.Path]::DirectorySeparatorChar
        if ($resolved.StartsWith($customRoot, [StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $resolved -Recurse -Force
        } else { throw 'Scriptmap valt buiten custom-tools.' }
    }
}

function Export-WPSCustomTool {
    param($Tool, [string]$RootPath, [string]$Destination)
    if ($Tool.Source -ne 'Custom') { throw 'Alleen aangepaste tools kunnen worden geëxporteerd.' }
    $scriptPath = Resolve-WPSRelativePath -RelativePath $Tool.Script -RootPath $RootPath -RequireExisting
    $temporary = Join-Path $env:TEMP ('WPS-PowerAddons-export-{0}' -f [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $temporary | Out-Null
    try {
        Copy-Item -LiteralPath $scriptPath -Destination (Join-Path $temporary ([IO.Path]::GetFileName($scriptPath)))
        $copy = $Tool | Select-Object *
        $copy.Script = [IO.Path]::GetFileName($scriptPath)
        $copy | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $temporary 'metadata.json') -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $temporary 'README.txt') -Value @(
            'WPS-PowerAddons aangepaste tool'
            ('Naam: {0}' -f $Tool.Name)
            ('Versie: {0}' -f $Tool.Version)
            ('SHA-256: {0}' -f $Tool.Sha256)
            'Controleer het script voordat u het importeert of uitvoert.'
        ) -Encoding UTF8
        if (Test-Path -LiteralPath $Destination) { Remove-Item -LiteralPath $Destination -Force }
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [IO.Compression.ZipFile]::CreateFromDirectory($temporary, $Destination)
    } finally {
        Remove-Item -LiteralPath $temporary -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Import-WPSCustomToolPackage {
    param([string]$PackagePath, [string]$RootPath)
    if (-not (Test-Path -LiteralPath $PackagePath -PathType Leaf) -or [IO.Path]::GetExtension($PackagePath) -ine '.zip') {
        throw 'Selecteer een bestaand ZIP-pakket.'
    }
    Add-Type -AssemblyName System.IO.Compression
    $archive = [IO.Compression.ZipFile]::OpenRead($PackagePath)
    $temporary = Join-Path $env:TEMP ('WPS-PowerAddons-import-{0}' -f [Guid]::NewGuid().ToString('N'))
    try {
        foreach ($entry in $archive.Entries) {
            $name = $entry.FullName.Replace('\', '/')
            if ($name.StartsWith('/') -or $name -match '(^|/)\.\.(/|$)' -or $name -match '^[a-zA-Z]:') {
                throw 'ZIP-pakket bevat een onveilig pad.'
            }
        }
        New-Item -ItemType Directory -Path $temporary | Out-Null
        [IO.Compression.ZipFile]::ExtractToDirectory($PackagePath, $temporary)
    } finally {
        $archive.Dispose()
    }
    try {
        $metadataPath = Join-Path $temporary 'metadata.json'
        if (-not (Test-Path -LiteralPath $metadataPath -PathType Leaf)) { throw 'metadata.json ontbreekt in het pakket.' }
        $metadata = Get-Content -LiteralPath $metadataPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
        if (-not (Test-WPSToolId ([string]$metadata.Id))) { throw 'Tool-ID in pakket is ongeldig.' }
        $packageScript = Resolve-WPSRelativePath -RelativePath ([string]$metadata.Script) -RootPath $temporary -RequireExisting
        if ([IO.Path]::GetExtension($packageScript) -ine '.ps1') { throw 'Pakket bevat geen geldig PowerShell-script.' }
        if ($metadata.Sha256 -ine (Get-WPSFileSha256 -LiteralPath $packageScript)) { throw 'SHA-256-controle van het pakket is mislukt.' }
        $definition = $metadata | Select-Object *
        $definition.Source = 'Custom'
        $definition.Script = ''
        $definition.Sha256 = ''
        return New-WPSCustomTool -Definition $definition -SourceScript $packageScript -RootPath $RootPath
    } finally {
        Remove-Item -LiteralPath $temporary -Recurse -Force -ErrorAction SilentlyContinue
    }
}
