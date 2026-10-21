function Test-WPSAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-WPSToolId {
    param([string]$Id)
    return ($Id -cmatch '^[a-z0-9]+(?:-[a-z0-9]+)*$' -and $Id.Length -le 64)
}

function Test-WPSSafeFileName {
    param([string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name) -or $Name -match '[<>:"/\\|?*\x00-\x1F]' -or $Name.EndsWith('.') -or $Name.EndsWith(' ')) {
        return $false
    }
    if ($Name -match '^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(\.|$)') { return $false }
    return $true
}

function Assert-WPSNoReparsePath {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$RootPath
    )
    $root = [IO.Path]::GetFullPath($RootPath).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    $candidate = [IO.Path]::GetFullPath($Path)
    $prefix = $root + [IO.Path]::DirectorySeparatorChar
    if (-not $candidate.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Het pad valt buiten de toepassingsmap.'
    }
    $relative = $candidate.Substring($prefix.Length)
    $current = $root
    foreach ($segment in $relative.Split([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)) {
        if (-not $segment) { continue }
        $current = Join-Path $current $segment
        if (Test-Path -LiteralPath $current) {
            $attributes = [IO.File]::GetAttributes($current)
            if (($attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw 'Paden via symbolische koppelingen of junctions zijn niet toegestaan.'
            }
        }
    }
}

function Resolve-WPSRelativePath {
    param(
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [Parameter(Mandatory = $true)][string]$RootPath,
        [switch]$RequireExisting
    )

    if ([string]::IsNullOrWhiteSpace($RelativePath) -or $RelativePath.Contains(':') -or
        [IO.Path]::IsPathRooted($RelativePath) -or $RelativePath -match '(^|[\\/])\.\.([\\/]|$)') {
        throw 'Het pad moet relatief zijn en mag geen .. of stationsletter bevatten.'
    }
    $root = [IO.Path]::GetFullPath($RootPath).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    $candidate = [IO.Path]::GetFullPath((Join-Path $root $RelativePath))
    $prefix = $root + [IO.Path]::DirectorySeparatorChar
    if (-not $candidate.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Het pad valt buiten de toepassingsmap.'
    }
    Assert-WPSNoReparsePath -Path $candidate -RootPath $root
    if ($RequireExisting -and -not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
        throw 'Het scriptbestand bestaat niet.'
    }
    return $candidate
}

function Get-WPSFileSha256 {
    param([Parameter(Mandatory = $true)][string]$LiteralPath)
    $stream = [IO.File]::OpenRead($LiteralPath)
    try {
        $sha = [Security.Cryptography.SHA256]::Create()
        try {
            return ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-', '').ToLowerInvariant()
        } finally {
            $sha.Dispose()
        }
    } finally {
        $stream.Dispose()
    }
}
