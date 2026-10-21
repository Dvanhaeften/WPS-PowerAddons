function New-WPSToolResult {
    param($Tool, [int]$ExitCode, [string]$Status, [string]$Message, [datetime]$StartTime, [datetime]$EndTime, [bool]$WasElevated)
    return [pscustomobject]@{
        ToolId = [string]$Tool.Id; ToolName = [string]$Tool.Name
        StartTime = $StartTime.ToString('o'); EndTime = $EndTime.ToString('o')
        Duration = [Math]::Round(($EndTime - $StartTime).TotalSeconds, 2)
        ExitCode = $ExitCode; Status = $Status; Message = $Message
        RequiresRestart = ($ExitCode -in @(5, 6))
        LogPath = ''; WasElevated = $WasElevated; Output = ''
    }
}

function Invoke-WPSPowerAddonTool {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Tool,
        [Parameter(Mandatory = $true)][string]$RootPath,
        [Parameter(Mandatory = $true)][string]$LogDirectory,
        [Parameter(Mandatory = $true)]$Settings,
        [string]$CommandText,
        [switch]$ReadOnly,
        [switch]$Confirmed
    )
    $start = Get-Date
    $admin = ([bool]$Tool.RequiresAdmin -and -not $ReadOnly)
    $scriptPath = $null
    try {
        if (-not $Tool.Enabled) { throw 'Deze tool is uitgeschakeld.' }
        if ($ReadOnly -and -not $Tool.SupportsReadOnlyMode) { throw 'Alleen controleren wordt niet ondersteund door deze tool.' }
        $scriptPath = Resolve-WPSRelativePath -RelativePath $Tool.Script -RootPath $RootPath -RequireExisting
    } catch {
        $result = New-WPSToolResult $Tool 7 'ValidationFailed' $_.Exception.Message $start (Get-Date) $false
        Write-WPSToolExecutionLog -Result $result -Tool $Tool -LogDirectory $LogDirectory
        return $result
    }

    if ($Tool.Source -eq 'Custom' -and $Settings.CheckCustomToolHashes) {
        try { $actualHash = Get-WPSFileSha256 -LiteralPath $scriptPath }
        catch { $actualHash = '' }
        if (-not $actualHash -or $actualHash -ine [string]$Tool.Sha256) {
            $result = New-WPSToolResult $Tool 9 'ScriptHashChanged' 'De SHA-256-hash wijkt af. Controleer of het script sinds registratie is gewijzigd.' $start (Get-Date) $false
            Write-WPSToolExecutionLog -Result $result -Tool $Tool -LogDirectory $LogDirectory
            return $result
        }
    }
    if ($Tool.RequiresConfirmation -and -not $Confirmed) {
        $result = New-WPSToolResult $Tool 2 'Cancelled' 'De vereiste bevestiging is niet gegeven.' $start (Get-Date) $false
        Write-WPSToolExecutionLog -Result $result -Tool $Tool -LogDirectory $LogDirectory
        return $result
    }
    if ($admin -and -not (Test-WPSAdministrator)) {
        # This function is invoked by the GUI only after its Dutch confirmation prompt.
    }

    $timeout = [int]$Tool.TimeoutSeconds
    if (-not $Settings.EnableToolTimeout) { $timeout = 0 }
    $outputFile = Join-Path $env:TEMP ('WPS-PowerAddons-{0}.out' -f [Guid]::NewGuid().ToString('N'))
    $escapedScript = $scriptPath.Replace("'", "''")
    $runner = '$ErrorActionPreference = ''Continue''; & ' + "'" + $escapedScript + "'"
    if ($ReadOnly) { $runner += ' -ReadOnly' }
    if ($Tool.Id -eq 'powershell-command') {
        if ([string]::IsNullOrWhiteSpace($CommandText)) {
            $result = New-WPSToolResult $Tool 7 'ValidationFailed' 'Voer een PowerShell-opdracht in.' $start (Get-Date) $false
            Write-WPSToolExecutionLog -Result $result -Tool $Tool -LogDirectory $LogDirectory
            return $result
        }
        $runner += " -CommandText '" + $CommandText.Replace("'", "''") + "'"
    }
    $runner += " *> '$($outputFile.Replace("'", "''"))'; if (`$LASTEXITCODE -is [int]) { exit `$LASTEXITCODE }"
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($runner))
    $arguments = '-STA -NoProfile -ExecutionPolicy Bypass -EncodedCommand {0}' -f $encoded
    $process = $null
    $wasElevated = $false
    try {
        if ($admin -and -not (Test-WPSAdministrator)) {
            $process = Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList $arguments -Verb RunAs -PassThru -ErrorAction Stop
            $wasElevated = $true
        } else {
            $process = Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList $arguments -PassThru -ErrorAction Stop
        }
        if ($timeout -gt 0) {
            if (-not $process.WaitForExit($timeout * 1000)) {
                try { $process.Kill() } catch { }
                $result = New-WPSToolResult $Tool 8 'Timeout' ('De time-out van {0} seconden is overschreden. De PowerShell-runner is gestopt; een al gestart extern proces kan nog actief zijn.' -f $timeout) $start (Get-Date) $wasElevated
            } elseif ($code -eq 2) {
                $result = New-WPSToolResult $Tool 2 'Cancelled' 'De tool of gebruiker heeft de actie geannuleerd.' $start (Get-Date) $wasElevated
            } elseif ($code -eq 4) {
                $result = New-WPSToolResult $Tool 4 'PrerequisiteMissing' 'Een vereiste voor de tool ontbreekt.' $start (Get-Date) $wasElevated
            } elseif ($code -eq 3) {
                $result = New-WPSToolResult $Tool 3 'AdministratorRightsUnavailable' 'Administratorrechten zijn niet beschikbaar.' $start (Get-Date) $wasElevated
            } elseif ($code -eq 7) {
                $result = New-WPSToolResult $Tool 7 'ValidationFailed' 'De tool heeft de validatie afgewezen.' $start (Get-Date) $wasElevated
            } elseif ($code -eq 8) {
                $result = New-WPSToolResult $Tool 8 'Timeout' 'De tool meldde zelf een time-out.' $start (Get-Date) $wasElevated
            } elseif ($code -eq 9) {
                $result = New-WPSToolResult $Tool 9 'ScriptHashChanged' 'De tool meldde een afwijkende script-hash.' $start (Get-Date) $wasElevated
            } elseif ($code -eq 5) {
                $result = New-WPSToolResult $Tool 5 'RestartRecommended' 'De tool is uitgevoerd; een herstart wordt aanbevolen.' $start (Get-Date) $wasElevated
            } elseif ($code -eq 6) {
                $result = New-WPSToolResult $Tool 6 'RestartRequired' 'De tool is uitgevoerd; een herstart is vereist.' $start (Get-Date) $wasElevated
            } else {
                $message = 'De tool is uitgevoerd. Uitvoer is alleen in dit resultaatvenster zichtbaar en niet in het log opgeslagen.'
                if (Test-Path -LiteralPath $outputFile -PathType Leaf) {
                    $outputText = Get-Content -LiteralPath $outputFile -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
                    if ($outputText.Length -gt 12000) { $outputText = $outputText.Substring($outputText.Length - 12000) }
                } else { $outputText = '' }
                $code = $process.ExitCode
                if ($code -eq 0 -and $Tool.RestartBehaviour -eq 'Required') {
                    $result = New-WPSToolResult $Tool 6 'RestartRequired' 'Uitgevoerd. Een herstart is vereist; deze wordt niet automatisch gestart.' $start (Get-Date) $wasElevated
                } elseif ($code -eq 0 -and $Tool.RestartBehaviour -eq 'Recommended') {
                    $result = New-WPSToolResult $Tool 5 'RestartRecommended' 'Uitgevoerd. Een herstart wordt aanbevolen.' $start (Get-Date) $wasElevated
                } elseif ($code -eq 0) {
                    $result = New-WPSToolResult $Tool 0 'Success' $message $start (Get-Date) $wasElevated
                } else {
                    $result = New-WPSToolResult $Tool 1 'GeneralError' ('Script afgesloten met code {0}. {1}' -f $code, $message) $start (Get-Date) $wasElevated
                }
                $result.Output = $outputText
            }
        } else {
            $process.WaitForExit()
            $code = $process.ExitCode
            $outputText = ''
            if (Test-Path -LiteralPath $outputFile -PathType Leaf) { $outputText = Get-Content -LiteralPath $outputFile -Raw -Encoding UTF8 -ErrorAction SilentlyContinue }
            if ($code -eq 0) { $result = New-WPSToolResult $Tool 0 'Success' 'De tool is uitgevoerd.' $start (Get-Date) $wasElevated }
            elseif ($code -eq 2) { $result = New-WPSToolResult $Tool 2 'Cancelled' 'De tool of gebruiker heeft de actie geannuleerd.' $start (Get-Date) $wasElevated }
            elseif ($code -eq 4) { $result = New-WPSToolResult $Tool 4 'PrerequisiteMissing' 'Een vereiste voor de tool ontbreekt.' $start (Get-Date) $wasElevated }
            elseif ($code -eq 3) { $result = New-WPSToolResult $Tool 3 'AdministratorRightsUnavailable' 'Administratorrechten zijn niet beschikbaar.' $start (Get-Date) $wasElevated }
            elseif ($code -eq 7) { $result = New-WPSToolResult $Tool 7 'ValidationFailed' 'De tool heeft de validatie afgewezen.' $start (Get-Date) $wasElevated }
            elseif ($code -eq 8) { $result = New-WPSToolResult $Tool 8 'Timeout' 'De tool meldde zelf een time-out.' $start (Get-Date) $wasElevated }
            elseif ($code -eq 9) { $result = New-WPSToolResult $Tool 9 'ScriptHashChanged' 'De tool meldde een afwijkende script-hash.' $start (Get-Date) $wasElevated }
            elseif ($code -eq 5) { $result = New-WPSToolResult $Tool 5 'RestartRecommended' 'De tool is uitgevoerd; een herstart wordt aanbevolen.' $start (Get-Date) $wasElevated }
            elseif ($code -eq 6) { $result = New-WPSToolResult $Tool 6 'RestartRequired' 'De tool is uitgevoerd; een herstart is vereist.' $start (Get-Date) $wasElevated }
            else { $result = New-WPSToolResult $Tool 1 'GeneralError' ('Script afgesloten met code {0}.' -f $code) $start (Get-Date) $wasElevated }
            $result.Output = $outputText
        }
    } catch [System.ComponentModel.Win32Exception] {
        if ($_.Exception.NativeErrorCode -eq 1223) {
            $result = New-WPSToolResult $Tool 2 'Cancelled' 'UAC-verzoek geannuleerd; de toepassing blijft geopend.' $start (Get-Date) $false
        } else {
            $result = New-WPSToolResult $Tool 3 'AdministratorRightsUnavailable' ('De afzonderlijke tool kon niet worden gestart: {0}' -f $_.Exception.Message) $start (Get-Date) $false
        }
    } catch {
        $result = New-WPSToolResult $Tool 1 'GeneralError' ('Uitvoeren mislukt: {0}' -f $_.Exception.Message) $start (Get-Date) $wasElevated
    } finally {
        if (Test-Path -LiteralPath $outputFile -PathType Leaf) { Remove-Item -LiteralPath $outputFile -Force -ErrorAction SilentlyContinue }
        if ($process) { $process.Dispose() }
    }
    Write-WPSToolExecutionLog -Result $result -Tool $Tool -LogDirectory $LogDirectory
    return $result
}
