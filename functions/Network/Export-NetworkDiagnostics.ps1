[CmdletBinding()]
param([switch]$ReadOnly)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
try {
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('WPS-PowerAddons - Netwerkdiagnose')
    $lines.Add(('Datum: {0}' -f (Get-Date -Format o)))
    $lines.Add(('Computer: {0}' -f $env:COMPUTERNAME))
    $lines.Add(('Gebruiker: {0}' -f [Security.Principal.WindowsIdentity]::GetCurrent().Name))
    $lines.Add('')
    $lines.Add('=== ipconfig /all ===')
    $lines.AddRange([string[]]@(& ipconfig.exe /all 2>&1 | ForEach-Object { [string]$_ }))
    $lines.Add('')
    $lines.Add('=== Netwerkadapters ===')
    foreach ($adapter in @(Get-NetAdapter -ErrorAction SilentlyContinue)) {
        $lines.Add(('{0} | {1} | {2} | {3}' -f $adapter.Name, $adapter.InterfaceDescription, $adapter.Status, $adapter.MacAddress))
        $configuration = Get-NetIPConfiguration -InterfaceIndex $adapter.ifIndex -ErrorAction SilentlyContinue
        if ($configuration) {
            $lines.Add(('  IP: {0}' -f (@($configuration.IPv4Address.IPAddress) + @($configuration.IPv6Address.IPAddress) -join ', ')))
            $lines.Add(('  Gateway: {0}' -f (@($configuration.IPv4DefaultGateway.NextHop) -join ', ')))
            $lines.Add(('  DNS: {0}' -f (@($configuration.DnsServer.ServerAddresses) -join ', ')))
        }
    }
    $lines.Add('')
    $lines.Add('=== Routetabel ===')
    $lines.AddRange([string[]]@(& route.exe print 2>&1 | ForEach-Object { [string]$_ }))
    $lines.Add('')
    $lines.Add('=== Proxy ===')
    $lines.AddRange([string[]]@(& netsh.exe winhttp show proxy 2>&1 | ForEach-Object { [string]$_ }))
    $lines.Add(('Gebruikersproxy: {0}' -f (Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -Name ProxyEnable, ProxyServer -ErrorAction SilentlyContinue | Out-String).Trim()))
    $lines.Add('')
    foreach ($hostName in @('login.microsoftonline.com', 'office.com')) {
        $lines.Add(('=== DNS {0} ===' -f $hostName))
        try { $lines.AddRange([string[]]@(Resolve-DnsName -Name $hostName -ErrorAction Stop | ForEach-Object { $_.IPAddress })) }
        catch { $lines.Add(('DNS-test mislukt: {0}' -f $_.Exception.Message)) }
        try {
            $ping = Test-Connection -ComputerName $hostName -Count 1 -Quiet -ErrorAction Stop
            $lines.Add(('Ping: {0}' -f $(if ($ping) { 'bereikbaar' } else { 'geen antwoord' })))
        } catch { $lines.Add('Ping: niet beschikbaar of geblokkeerd') }
    }
    try {
        $tcp = New-Object Net.Sockets.TcpClient
        $async = $tcp.BeginConnect('login.microsoftonline.com', 443, $null, $null)
        $connected = $async.AsyncWaitHandle.WaitOne(5000, $false) -and $tcp.Connected
        $tcp.Close()
        $lines.Add(('TCP 443 login.microsoftonline.com: {0}' -f $(if ($connected) { 'verbonden' } else { 'niet verbonden' })))
    } catch { $lines.Add(('TCP 443-test mislukt: {0}' -f $_.Exception.Message)) }
    if (-not $ReadOnly) {
        $desktop = [Environment]::GetFolderPath('Desktop')
        $path = Join-Path $desktop ('WPS-PowerAddons-Netwerkdiagnose-{0}.txt' -f (Get-Date -Format yyyyMMdd-HHmmss))
        Set-Content -LiteralPath $path -Value $lines -Encoding UTF8
        Write-Output ('Diagnose opgeslagen: {0}' -f $path)
    } else { Write-Output 'Alleen-lezencontrole voltooid.' }
    $lines
    exit 0
} catch { Write-Error ('Netwerkdiagnose mislukt: {0}' -f $_.Exception.Message); exit 1 }
