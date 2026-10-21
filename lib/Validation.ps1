$script:WPSRequiredToolProperties = @(
    'Id', 'Name', 'Category', 'Description', 'Script', 'RequiresAdmin',
    'RequiresConfirmation', 'SupportsReadOnlyMode', 'Enabled', 'Visible',
    'Favourite', 'Version', 'Author', 'Source', 'Tags', 'RestartBehaviour',
    'TimeoutSeconds'
)

function Test-WPSToolDefinition {
    param(
        [Parameter(Mandatory = $true)]$Tool,
        [Parameter(Mandatory = $true)][string]$RootPath,
        [switch]$Custom
    )

    $errors = New-Object System.Collections.Generic.List[string]
    if ($null -eq $Tool) {
        $errors.Add('Tooldefinitie is leeg.')
        return [pscustomobject]@{ Valid = $false; Errors = $errors.ToArray() }
    }
    foreach ($property in $script:WPSRequiredToolProperties) {
        if ($null -eq $Tool.PSObject.Properties[$property]) {
            $errors.Add(('Eigenschap ontbreekt: {0}.' -f $property))
        }
    }
    if ($errors.Count -gt 0) { return [pscustomobject]@{ Valid = $false; Errors = $errors.ToArray() } }
    if ($Tool.Id -isnot [string] -or -not (Test-WPSToolId ([string]$Tool.Id))) { $errors.Add('Tool-ID is ongeldig; gebruik kleine letters, cijfers en koppeltekens.') }
    foreach ($name in @('Name', 'Category', 'Description', 'Script', 'Version', 'Author')) {
        if ($Tool.$name -isnot [string] -or [string]::IsNullOrWhiteSpace($Tool.$name)) {
            $errors.Add(('Eigenschap {0} moet een niet-lege tekstwaarde zijn.' -f $name))
        }
    }
    foreach ($name in @('RequiresAdmin', 'RequiresConfirmation', 'SupportsReadOnlyMode', 'Enabled', 'Visible', 'Favourite')) {
        if ($Tool.$name -isnot [bool]) { $errors.Add(('Eigenschap {0} moet true of false zijn.' -f $name)) }
    }
    if ($Tool.Tags -isnot [array] -or @($Tool.Tags | Where-Object { $_ -isnot [string] }).Count -gt 0) {
        $errors.Add('Tags moet een lijst met tekstwaarden zijn.')
    }
    if ($Tool.Source -notin @('BuiltIn', 'Custom') -or ($Custom -and $Tool.Source -ne 'Custom')) {
        $errors.Add('Source moet BuiltIn of Custom zijn en bij maatwerk Custom.')
    }
    if ($Tool.RestartBehaviour -notin @('None', 'Recommended', 'Required')) {
        $errors.Add('RestartBehaviour moet None, Recommended of Required zijn.')
    }
    if ($Tool.TimeoutSeconds -isnot [int] -or $Tool.TimeoutSeconds -lt 10 -or $Tool.TimeoutSeconds -gt 7200) {
        $errors.Add('TimeoutSeconds moet een geheel getal van 10 t/m 7200 zijn.')
    }
    if ($Tool.Category -notmatch '^[\p{L}\p{N}][\p{L}\p{N} &_-]{0,49}$') {
        $errors.Add('Categorie bevat ongeldige tekens.')
    }
    if ($Tool.Script -is [string]) {
        try {
            $null = Resolve-WPSRelativePath -RelativePath $Tool.Script -RootPath $RootPath -RequireExisting
            if ([IO.Path]::GetExtension($Tool.Script) -ine '.ps1') { $errors.Add('Alleen PowerShell .ps1-scripts zijn toegestaan.') }
        } catch {
            $errors.Add(('Ongeldig scriptpad: {0}' -f $_.Exception.Message))
        }
    }
    if ($Custom -and ($null -eq $Tool.PSObject.Properties['Sha256'] -or [string]$Tool.Sha256 -notmatch '^[a-fA-F0-9]{64}$')) {
        $errors.Add('De SHA-256-hash van de aangepaste tool ontbreekt of is ongeldig.')
    }
    return [pscustomobject]@{ Valid = ($errors.Count -eq 0); Errors = $errors.ToArray() }
}

function Test-WPSSettings {
    param([Parameter(Mandatory = $true)]$Settings)
    $errors = New-Object System.Collections.Generic.List[string]
    if ($null -eq $Settings) {
        $errors.Add('Instellingen zijn leeg.')
        return [pscustomobject]@{ Valid = $false; Errors = $errors.ToArray() }
    }
    $checks = @{
        InstallScope = @('CurrentUser', 'AllUsers', 'Portable')
        Theme = @('Light')
        DefaultView = @('Cards', 'List')
        Language = @('nl-NL')
    }
    foreach ($property in $checks.Keys) {
        if ($null -eq $Settings.PSObject.Properties[$property] -or $Settings.$property -notin $checks[$property]) {
            $errors.Add(('Ongeldige instelling: {0}.' -f $property))
        }
    }
    if ($null -eq $Settings.PSObject.Properties['LogRetentionDays'] -or $Settings.LogRetentionDays -isnot [int] -or $Settings.LogRetentionDays -lt 1 -or $Settings.LogRetentionDays -gt 3650) {
        $errors.Add('LogRetentionDays moet tussen 1 en 3650 liggen.')
    }
    if ($null -eq $Settings.PSObject.Properties['DefaultTimeoutSeconds'] -or $Settings.DefaultTimeoutSeconds -isnot [int] -or $Settings.DefaultTimeoutSeconds -lt 10 -or $Settings.DefaultTimeoutSeconds -gt 7200) {
        $errors.Add('DefaultTimeoutSeconds moet tussen 10 en 7200 liggen.')
    }
    foreach ($property in @('ConfirmAdministratorTools', 'CheckCustomToolHashes', 'ShowDisabledTools', 'EnableToolTimeout')) {
        if ($null -eq $Settings.PSObject.Properties[$property] -or $Settings.$property -isnot [bool]) {
            $errors.Add(('Instelling {0} moet true of false zijn.' -f $property))
        }
    }
    if ($null -eq $Settings.PSObject.Properties['PreferredEditor'] -or $Settings.PreferredEditor -isnot [string] -or [string]::IsNullOrWhiteSpace($Settings.PreferredEditor)) {
        $errors.Add('PreferredEditor moet een niet-lege tekstwaarde zijn.')
    }
    if ($null -eq $Settings.PSObject.Properties['ApplicationId'] -or $Settings.ApplicationId -ne 'WPS.PowerAddons') {
        $errors.Add('ApplicationId moet WPS.PowerAddons zijn.')
    }
    if ($null -eq $Settings.PSObject.Properties['ApplicationVersion'] -or $Settings.ApplicationVersion -isnot [string]) {
        $errors.Add('ApplicationVersion moet tekst zijn.')
    }
    foreach ($property in @('FavouriteToolIds', 'RecentToolIds')) {
        if ($null -eq $Settings.PSObject.Properties[$property] -or $Settings.$property -isnot [array] -or @($Settings.$property | Where-Object { $_ -isnot [string] }).Count -gt 0) {
            $errors.Add(('Instelling {0} moet een lijst zijn.' -f $property))
        }
    }
    return [pscustomobject]@{ Valid = ($errors.Count -eq 0); Errors = $errors.ToArray() }
}
