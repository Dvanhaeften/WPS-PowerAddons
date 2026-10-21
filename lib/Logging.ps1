function Get-WPSLogDirectory {
    param([string]$RootPath, [string]$InstallScope)
    if ($InstallScope -eq 'CurrentUser') {
        $path = Join-Path $env:LOCALAPPDATA 'WPS-PowerAddons\Logs'
    } elseif ($InstallScope -eq 'AllUsers') {
        $path = Join-Path $env:ProgramData 'WPS-PowerAddons\Logs'
    } else {
        $path = Join-Path $RootPath 'logs'
    }
    try {
        if (-not (Test-Path -LiteralPath $path -PathType Container)) {
            New-Item -ItemType Directory -Path $path -Force -ErrorAction Stop | Out-Null
        }
        $probe = Join-Path $path ('.write-test-{0}' -f [Guid]::NewGuid().ToString('N'))
        [IO.File]::WriteAllText($probe, '')
        Remove-Item -LiteralPath $probe -Force
        return $path
    } catch {
        $fallback = Join-Path $RootPath 'logs'
        if (-not (Test-Path -LiteralPath $fallback -PathType Container)) {
            New-Item -ItemType Directory -Path $fallback -Force | Out-Null
        }
        Write-WPSApplicationLog -Message ('Logmap niet schrijfbaar; lokale map gebruikt. {0}' -f $_.Exception.Message) -RootPath $RootPath -LogDirectory $fallback
        return $fallback
    }
}

function Write-WPSApplicationLog {
    param([Parameter(Mandatory = $true)][string]$Message, [string]$Level = 'INFO', [string]$RootPath, [string]$LogDirectory)
    if (-not $LogDirectory) { $LogDirectory = Join-Path $RootPath 'logs' }
    if (-not (Test-Path -LiteralPath $LogDirectory -PathType Container)) {
        New-Item -ItemType Directory -Path $LogDirectory -Force | Out-Null
    }
    $line = '{0} [{1}] [{2}] {3}' -f [DateTime]::Now.ToString('o'), $Level, $env:COMPUTERNAME, $Message
    Add-Content -LiteralPath (Join-Path $LogDirectory ('WPS-PowerAddons-{0}.log' -f [DateTime]::Now.ToString('yyyy-MM-dd')) ) -Value $line -Encoding UTF8
}

function Write-WPSToolExecutionLog {
    param([Parameter(Mandatory = $true)]$Result, [Parameter(Mandatory = $true)]$Tool, [string]$LogDirectory)
    if (-not (Test-Path -LiteralPath $LogDirectory -PathType Container)) {
        New-Item -ItemType Directory -Path $LogDirectory -Force | Out-Null
    }
    $document = [ordered]@{
        Timestamp = [DateTime]::Now.ToString('o')
        ApplicationVersion = '1.0.0'
        ComputerName = $env:COMPUTERNAME
        Username = [Security.Principal.WindowsIdentity]::GetCurrent().Name
        ProcessId = $PID
        ToolId = $Tool.Id
        ToolName = $Tool.Name
        ToolVersion = $Tool.Version
        ExecutionMode = $(if ($Result.WasElevated) { 'Elevated child process' } else { 'Current user' })
        WasElevated = [bool]$Result.WasElevated
        StartTime = $Result.StartTime
        FinishTime = $Result.EndTime
        DurationSeconds = $Result.Duration
        ExitCode = $Result.ExitCode
        Status = $Result.Status
        OutputSummary = $Result.Message
        ErrorMessage = $(if ($Result.Status -eq 'Success') { '' } else { $Result.Message })
        RequiresRestart = $Result.RequiresRestart
    }
    $path = Join-Path $LogDirectory ('{0}-{1}.json' -f $Tool.Id, [DateTime]::Now.ToString('yyyyMMdd-HHmmss-fff'))
    $document | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $path -Encoding UTF8
    $Result.LogPath = $path
    $index = Join-Path $LogDirectory 'index.json'
    $entry = [pscustomobject]@{ Timestamp = $document.Timestamp; ToolId = $Tool.Id; ToolName = $Tool.Name; Status = $Result.Status; ExitCode = $Result.ExitCode; LogPath = $path }
    $entries = @()
    if (Test-Path -LiteralPath $index -PathType Leaf) {
        try {
            $entryData = ConvertFrom-Json -InputObject (Get-Content -LiteralPath $index -Raw -Encoding UTF8)
            $entries = @($entryData | ForEach-Object { $_ })
        } catch {
            Write-WPSApplicationLog -RootPath $LogDirectory -LogDirectory $LogDirectory -Level WARN -Message ('Logindex is ongeldig: {0}' -f $_.Exception.Message)
            $entries = @()
        }
    }
    @($entry) + @($entries | Select-Object -First 4999) | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $index -Encoding UTF8
}
