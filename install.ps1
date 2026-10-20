# Installs syg on Windows: https://syg.vishisht.tech/install.html
#
#   irm https://syg.vishisht.tech/install.ps1 | iex
#
# Downloads the release archive for this CPU, checks it against the
# release's SHA256SUMS, and puts syg.exe in $env:SYG_INSTALL_DIR (default
# %LOCALAPPDATA%\Programs\syg), which it adds to the user's PATH.
#   $env:SYG_VERSION = "1.0.0"   a version instead of the latest
$ErrorActionPreference = "Stop"
# Windows PowerShell 5.1 may offer only TLS 1.0, which GitHub refuses.
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
$repo = "vishisht16/syg"
$base = if ($env:SYG_DOWNLOAD_BASE) { $env:SYG_DOWNLOAD_BASE } else { "https://github.com/$repo/releases/download" }
$dir = if ($env:SYG_INSTALL_DIR) { $env:SYG_INSTALL_DIR } else { Join-Path $env:LOCALAPPDATA "Programs\syg" }
$arch = if ([System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture -eq "Arm64") { "arm64" } else { "amd64" }

$version = $env:SYG_VERSION
if (-not $version) {
    # The newest release, from where releases/latest redirects to: unlike
    # GitHub's API, it has no hourly limit per address.
    $req = [System.Net.HttpWebRequest]::Create("https://github.com/$repo/releases/latest")
    $req.AllowAutoRedirect = $false
    $req.Method = "HEAD"
    $res = $req.GetResponse()
    try { $location = $res.Headers["Location"] } finally { $res.Close() }
    if ($location -match "/releases/?$") {
        # Where it leads when there is no release yet, only release candidates.
        throw "Syg has no final release yet, only release candidates: install one with `$env:SYG_VERSION = `"VERSION`", from https://github.com/$repo/releases"
    }
    if ($location -notmatch "/releases/tag/v([^/?#]+)$") { throw "could not find the latest release" }
    $version = $Matches[1]
}
$version = $version.TrimStart("v")
$archive = "syg_${version}_windows_${arch}.zip"
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("syg-" + [guid]::NewGuid())
New-Item -ItemType Directory -Path $tmp | Out-Null
try {
    Write-Host "syg-install: downloading syg $version for windows/$arch"
    Invoke-WebRequest "$base/v$version/$archive" -OutFile (Join-Path $tmp $archive) -UseBasicParsing
    Invoke-WebRequest "$base/v$version/SHA256SUMS" -OutFile (Join-Path $tmp "SHA256SUMS") -UseBasicParsing
    $line = Get-Content (Join-Path $tmp "SHA256SUMS") | Where-Object { $_ -match ("  \*?" + [regex]::Escape($archive) + "$") }
    if (-not $line) { throw "$archive is not listed in SHA256SUMS" }
    $want = ($line -split "\s+")[0].ToLower()
    $got = (Get-FileHash (Join-Path $tmp $archive) -Algorithm SHA256).Hash.ToLower()
    if ($got -ne $want) { throw "checksum mismatch for ${archive}: expected $want, got $got" }
    Write-Host "syg-install: checksum verified"
    Expand-Archive (Join-Path $tmp $archive) -DestinationPath $tmp -Force
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    Move-Item (Join-Path $tmp "syg.exe") (Join-Path $dir "syg.exe") -Force
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    if (($userPath -split ";") -notcontains $dir) {
        [Environment]::SetEnvironmentVariable("Path", "$userPath;$dir", "User")
        Write-Host "syg-install: added $dir to your PATH (open a new terminal)"
    }
    Write-Host "syg-install: installed $(Join-Path $dir 'syg.exe')"
} finally {
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
