[CmdletBinding()]
param([switch]$ReadOnly)
$ErrorActionPreference = 'Stop'
try {
    foreach ($hostName in @('login.microsoftonline.com', 'office.com', 'outlook.office.com')) {
        Write-Output ('=== {0} ===' -f $hostName)
        try {
            $dns = @(Resolve-DnsName -Name $hostName -ErrorAction Stop)
            Write-Output ('DNS: OK ({0})' -f (($dns | Where-Object IPAddress | Select-Object -ExpandProperty IPAddress -Unique) -join ', '))
        } catch { Write-Output ('DNS: MISLUKT ({0})' -f $_.Exception.Message); continue }
        $tcpOk = $false
        $client = New-Object Net.Sockets.TcpClient
        try {
            $async = $client.BeginConnect($hostName, 443, $null, $null)
            $tcpOk = $async.AsyncWaitHandle.WaitOne(5000, $false) -and $client.Connected
        } catch { $tcpOk = $false } finally { $client.Close() }
        Write-Output ('TCP 443: {0}' -f $(if ($tcpOk) { 'OK' } else { 'MISLUKT of geblokkeerd' }))
        try {
            $request = [Net.HttpWebRequest]::Create(('https://{0}/' -f $hostName))
            $request.Method = 'HEAD'
            $request.Timeout = 7000
            $request.AllowAutoRedirect = $true
            $response = $request.GetResponse()
            Write-Output ('HTTP/HTTPS: bereikbaar (status {0})' -f [int]$response.StatusCode)
            $response.Close()
        } catch [Net.WebException] {
            if ($_.Exception.Response) {
                Write-Output ('HTTP/HTTPS: server antwoordde met status {0}' -f [int]$_.Exception.Response.StatusCode)
                $_.Exception.Response.Close()
            } else { Write-Output ('HTTP/HTTPS: mislukt ({0})' -f $_.Exception.Status) }
        }
    }
    exit 0
} catch { Write-Error ('Verbindingstest mislukt: {0}' -f $_.Exception.Message); exit 1 }
