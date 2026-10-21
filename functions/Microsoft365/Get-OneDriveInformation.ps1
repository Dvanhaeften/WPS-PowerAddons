[CmdletBinding()]
param([switch]$ReadOnly)
$ErrorActionPreference = 'Stop'
try {
    $candidates = New-Object System.Collections.Generic.List[string]
    foreach ($key in @('HKCU:\Software\Microsoft\OneDrive', 'HKLM:\SOFTWARE\Microsoft\OneDrive', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\OneDrive')) {
        if (Test-Path -LiteralPath $key) {
            $value = Get-ItemProperty -LiteralPath $key -ErrorAction SilentlyContinue
            if ($value.InstallPath) { $candidates.Add((Join-Path $value.InstallPath 'OneDrive.exe')) }
        }
    }
    $candidates.Add((Join-Path $env:LOCALAPPDATA 'Microsoft\OneDrive\OneDrive.exe'))
    $candidates.Add((Join-Path $env:ProgramFiles 'Microsoft OneDrive\OneDrive.exe'))
    foreach ($path in $candidates | Select-Object -Unique) {
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            $file = Get-Item -LiteralPath $path
            Write-Output ('OneDrive: {0}, versie {1}' -f $path, $file.VersionInfo.FileVersion)
        }
    }
    $running = @(Get-Process -Name OneDrive -ErrorAction SilentlyContinue)
    Write-Output ('OneDrive actief: {0}' -f ($running.Count -gt 0))
    foreach ($key in @('HKCU:\Software\Microsoft\OneDrive\Accounts\Personal', 'HKCU:\Software\Microsoft\OneDrive\Accounts\Business1', 'HKCU:\Software\Microsoft\OneDrive\Accounts\Business2')) {
        if (Test-Path -LiteralPath $key) {
            $account = Get-ItemProperty -LiteralPath $key -ErrorAction SilentlyContinue
            if ($account.UserFolder -and (Test-Path -LiteralPath $account.UserFolder)) { Write-Output ('Syncmap: {0}' -f $account.UserFolder) }
        }
    }
    exit 0
} catch { Write-Error ('OneDrive-informatie mislukt: {0}' -f $_.Exception.Message); exit 1 }
