function Get-WPSDefaultSettings {
    return [pscustomobject]@{
        ApplicationId = 'WPS.PowerAddons'; ApplicationVersion = '1.0.0'; Language = 'nl-NL'; Theme = 'Light'; DefaultView = 'Cards'
        InstallScope = 'Portable'; LogRetentionDays = 30; ConfirmAdministratorTools = $true
        CheckCustomToolHashes = $true; ShowDisabledTools = $false; PreferredEditor = 'notepad.exe'
        EnableToolTimeout = $true; DefaultTimeoutSeconds = 300
        FavouriteToolIds = @('copy-support-summary', 'disk-space', 'm365-connectivity'); RecentToolIds = @()
    }
}

function Backup-WPSConfiguration {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        $backup = '{0}.{1}.bak' -f $Path, [DateTime]::Now.ToString('yyyyMMdd-HHmmss')
        Copy-Item -LiteralPath $Path -Destination $backup -Force
        return $backup
    }
    return $null
}

function Save-WPSJsonAtomic {
    param([Parameter(Mandatory = $true)]$Value, [Parameter(Mandatory = $true)][string]$Path, [switch]$Backup)
    $directory = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    if ($Backup) { $null = Backup-WPSConfiguration -Path $Path }
    $temp = Join-Path $directory ('.{0}.{1}.tmp' -f [IO.Path]::GetFileName($Path), [Guid]::NewGuid().ToString('N'))
    try {
        $json = ConvertTo-Json -InputObject $Value -Depth 12
        [IO.File]::WriteAllText($temp, $json, (New-Object Text.UTF8Encoding($false)))
        $null = Get-Content -LiteralPath $temp -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
        if (Test-Path -LiteralPath $Path -PathType Leaf) {
            try { [IO.File]::Replace($temp, $Path, $null) }
            catch {
                $staged = '{0}.replace' -f $Path
                Move-Item -LiteralPath $Path -Destination $staged -Force
                try { Move-Item -LiteralPath $temp -Destination $Path -Force; Remove-Item -LiteralPath $staged -Force }
                catch { if (-not (Test-Path -LiteralPath $Path) -and (Test-Path -LiteralPath $staged)) { Move-Item -LiteralPath $staged -Destination $Path -Force }; throw }
            }
        } else {
            Move-Item -LiteralPath $temp -Destination $Path -Force
        }
    } finally {
        if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue }
    }
}

function Get-WPSUserPreferences {
    param($Settings)
    $path = Join-Path $env:LOCALAPPDATA 'WPS-PowerAddons\user-preferences.json'
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        return [pscustomobject]@{ FavouriteToolIds = @($Settings.FavouriteToolIds); RecentToolIds = @($Settings.RecentToolIds) }
    }
    try {
        $preferences = ConvertFrom-Json -InputObject (Get-Content -LiteralPath $path -Raw -Encoding UTF8) -ErrorAction Stop
        foreach ($property in @('FavouriteToolIds', 'RecentToolIds')) {
            if ($null -eq $preferences.PSObject.Properties[$property] -or $preferences.$property -isnot [array] -or @($preferences.$property | Where-Object { $_ -isnot [string] }).Count -gt 0) {
                throw ('Gebruikersvoorkeur {0} is ongeldig.' -f $property)
            }
        }
        return $preferences
    } catch {
        Write-WPSApplicationLog -RootPath (Split-Path -Parent $path) -Level WARN -Message ('Gebruikersvoorkeuren konden niet worden gelezen: {0}' -f $_.Exception.Message)
        return [pscustomobject]@{ FavouriteToolIds = @($Settings.FavouriteToolIds); RecentToolIds = @($Settings.RecentToolIds) }
    }
}

function Save-WPSUserPreferences {
    param($Settings)
    $path = Join-Path $env:LOCALAPPDATA 'WPS-PowerAddons\user-preferences.json'
    $preferences = [pscustomobject]@{
        FavouriteToolIds = @($Settings.FavouriteToolIds)
        RecentToolIds = @($Settings.RecentToolIds)
    }
    Save-WPSJsonAtomic -Value $preferences -Path $path
}

function Read-WPSConfiguration {
    param([Parameter(Mandatory = $true)][string]$RootPath)
    $settingsPath = Join-Path $RootPath 'config\settings.json'
    if (-not (Test-Path -LiteralPath $settingsPath -PathType Leaf)) {
        $settings = Get-WPSDefaultSettings
        Save-WPSJsonAtomic -Value $settings -Path $settingsPath
    } else {
        try { $settings = Get-Content -LiteralPath $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop }
        catch {
            Write-WPSApplicationLog -RootPath $RootPath -Level ERROR -Message ('settings.json is ongeldig: {0}' -f $_.Exception.Message)
            throw ('Instellingen kunnen niet worden gelezen: {0}' -f $_.Exception.Message)
        }
    }
    $settingsCheck = Test-WPSSettings -Settings $settings
    if (-not $settingsCheck.Valid) {
        throw ('Instellingen ongeldig: {0}' -f ($settingsCheck.Errors -join ' '))
    }
    $preferences = Get-WPSUserPreferences -Settings $settings
    $settings.FavouriteToolIds = @($preferences.FavouriteToolIds)
    $settings.RecentToolIds = @($preferences.RecentToolIds)

    $logDirectory = Get-WPSLogDirectory -RootPath $RootPath -InstallScope $settings.InstallScope
    $builtInPath = Join-Path $RootPath 'config\tools.json'
    try {
        $builtInData = ConvertFrom-Json -InputObject (Get-Content -LiteralPath $builtInPath -Raw -Encoding UTF8) -ErrorAction Stop
        if ($builtInData -isnot [array]) { throw 'De registry-root moet een JSON-lijst zijn.' }
        $builtIns = @($builtInData | ForEach-Object { $_ })
    }
    catch {
        Write-WPSApplicationLog -RootPath $RootPath -LogDirectory $logDirectory -Level ERROR -Message ('tools.json is ongeldig: {0}' -f $_.Exception.Message)
        throw ('De ingebouwde toolconfiguratie is ongeldig: {0}' -f $_.Exception.Message)
    }
    $customPath = Join-Path $RootPath 'custom-tools\custom-tools.json'
    $custom = @()
    $errors = New-Object System.Collections.Generic.List[string]
    if (Test-Path -LiteralPath $customPath -PathType Leaf) {
        try {
            $customData = ConvertFrom-Json -InputObject (Get-Content -LiteralPath $customPath -Raw -Encoding UTF8) -ErrorAction Stop
            if ($customData -isnot [array]) { throw 'De maatwerkregistry-root moet een JSON-lijst zijn.' }
            $custom = @($customData | ForEach-Object { $_ })
        }
        catch {
            Write-WPSApplicationLog -RootPath $RootPath -LogDirectory $logDirectory -Level ERROR -Message ('custom-tools.json is ongeldig: {0}' -f $_.Exception.Message)
            $errors.Add(('custom-tools.json kan niet worden geparseerd: {0}' -f $_.Exception.Message))
            $custom = @()
        }
    }
    $valid = New-Object System.Collections.Generic.List[object]
    $seen = @{}
    foreach ($record in @($builtIns) + @($custom)) {
        if ($null -eq $record) {
            $message = 'Ongeldige lege tooldefinitie in configuratie.'
            $errors.Add($message)
            Write-WPSApplicationLog -RootPath $RootPath -LogDirectory $logDirectory -Level ERROR -Message $message
            continue
        }
        $toolId = ''
        $sourceValue = ''
        if ($null -ne $record.PSObject.Properties['Id']) { $toolId = [string]$record.Id }
        if ($null -ne $record.PSObject.Properties['Source']) { $sourceValue = [string]$record.Source }
        $isCustom = ($sourceValue -eq 'Custom')
        $check = Test-WPSToolDefinition -Tool $record -RootPath $RootPath -Custom:$isCustom
        foreach ($errorText in $check.Errors) {
            $message = 'Tool {0}: {1}' -f $(if ($toolId) { $toolId } else { '<onbekend>' }), $errorText
            $errors.Add($message)
            Write-WPSApplicationLog -RootPath $RootPath -LogDirectory $logDirectory -Level ERROR -Message $message
        }
        if ($toolId -and $seen.ContainsKey($toolId)) {
            $message = 'Dubbele tool-ID gevonden: {0}.' -f $toolId
            $errors.Add($message)
            Write-WPSApplicationLog -RootPath $RootPath -LogDirectory $logDirectory -Level ERROR -Message $message
            continue
        }
        if ($toolId) { $seen[$toolId] = $true }
        if ($check.Valid) { $valid.Add($record) }
    }
    return [pscustomobject]@{ Settings = $settings; Tools = $valid.ToArray(); Errors = $errors.ToArray(); LogDirectory = $logDirectory }
}
