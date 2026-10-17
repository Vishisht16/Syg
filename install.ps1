# Installs syg on Windows: https://syg.vishisht.tech/install.html
#
#   irm https://syg.vishisht.tech/install.ps1 | iex
#
# Downloads the release archive for this CPU, checks it against the
# release's SHA256SUMS, and puts syg.exe in $env:SYG_INSTALL_DIR (default
# %LOCALAPPDATA%\Programs\syg), which it adds to the user's PATH.
#   $env:SYG_VERSION = "1.0.0"   a version instead of the latest
$ErrorActionPreference = "Stop"
$repo = "vishisht16/syg"
$base = if ($env:SYG_DOWNLOAD_BASE) { $env:SYG_DOWNLOAD_BASE } else { "https://github.com/$repo/releases/download" }
$dir = if ($env:SYG_INSTALL_DIR) { $env:SYG_INSTALL_DIR } else { Join-Path $env:LOCALAPPDATA "Programs\syg" }
$arch = if ([System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture -eq "Arm64") { "arm64" } else { "amd64" }

$version = $env:SYG_VERSION
if (-not $version) {
    $version = (Invoke-RestMethod "https://api.github.com/repos/$repo/releases/latest").tag_name
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
