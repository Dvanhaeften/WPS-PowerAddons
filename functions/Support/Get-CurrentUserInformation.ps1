[CmdletBinding()]
param([switch]$ReadOnly)
$ErrorActionPreference = 'Stop'
try {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    $admin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    $session = Get-Process -Id $PID
    $lines = @(
        ('Gebruikersnaam: {0}' -f $identity.Name)
        ('Domein/accountcontext: {0}' -f $(if ($env:USERDOMAIN -eq $env:COMPUTERNAME) { 'lokaal account' } else { 'domein- of organisatieaccount' }))
        ('Profielpad: {0}' -f $env:USERPROFILE)
        ('Sessienaam: {0}' -f $env:SESSIONNAME)
        ('Sessie-ID: {0}' -f $session.SessionId)
        ('Beheerderscontext: {0}' -f $(if ($admin) { 'administrator' } else { 'standaardgebruiker' }))
    )
    $lines
    exit 0
} catch { Write-Error ('Gebruikersinformatie mislukt: {0}' -f $_.Exception.Message); exit 1 }
