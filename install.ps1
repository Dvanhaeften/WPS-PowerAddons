$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$repository = 'Dvanhaeften/WPS-PowerAddons'
$branch = 'main'
$temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) ('WPS-PowerAddons-install-{0}' -f [Guid]::NewGuid().ToString('N'))

try {
    if ($PSVersionTable.PSVersion.Major -ne 5 -or $PSVersionTable.PSVersion.Minor -lt 1) {
        throw 'WPS-PowerAddons vereist Windows PowerShell 5.1.'
    }

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    New-Item -ItemType Directory -Path $temporaryRoot -Force | Out-Null

    $bootstrapPath = Join-Path $temporaryRoot 'bootstrap.ps1'
    $packagePath = Join-Path $temporaryRoot 'WPS-PowerAddons.zip'
    $bootstrapUrl = 'https://raw.githubusercontent.com/{0}/{1}/bootstrap.ps1' -f $repository, $branch
    $packageUrl = 'https://github.com/{0}/archive/refs/heads/{1}.zip' -f $repository, $branch

    Invoke-WebRequest -Uri $bootstrapUrl -OutFile $bootstrapPath -UseBasicParsing -ErrorAction Stop
    Invoke-WebRequest -Uri $packageUrl -OutFile $packagePath -UseBasicParsing -ErrorAction Stop

    & (Join-Path $PSHOME 'powershell.exe') -NoProfile -ExecutionPolicy Bypass -File $bootstrapPath -Scope CurrentUser -PackagePath $packagePath
    if ($LASTEXITCODE -ne 0) {
        throw ('WPS-PowerAddons-installatie is mislukt met exitcode {0}.' -f $LASTEXITCODE)
    }
} catch {
    Write-Error ('WPS-PowerAddons kon niet worden geïnstalleerd: {0}' -f $_.Exception.Message)
    throw
} finally {
    if (Test-Path -LiteralPath $temporaryRoot) {
        Remove-Item -LiteralPath $temporaryRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
