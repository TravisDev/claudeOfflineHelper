<#
.SYNOPSIS
    Zips a version's installers into release assets and prints every checksum.

.DESCRIPTION
    Takes the four payloads for one Claude Desktop version, wraps each in a .zip, and
    reports SHA256 for both the payload and the zip. Warns if any asset is near
    GitHub's 2 GiB per-asset limit.

    Verify the PAYLOAD hash, not the zip: ZIP stores entry timestamps, so re-zipping
    identical bytes yields a different archive hash every time.

.EXAMPLE
    .\scripts\Package-Release.ps1 -Version 2.19675.0
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Version,
    [string]$Staging = ".\_staging\v$Version",
    [string]$OutDir  = ".\_release\v$Version",
    [string]$OfflineDeb
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
Add-Type -AssemblyName System.IO.Compression

# .NET file APIs resolve relative paths against the PROCESS working directory, which is
# not necessarily PowerShell's current location. Make everything absolute up front.
function Resolve-Abs([string]$p) {
    if ([System.IO.Path]::IsPathRooted($p)) { return $p }
    return [System.IO.Path]::GetFullPath((Join-Path (Get-Location).Path $p))
}
$Staging = Resolve-Abs $Staging
$OutDir  = Resolve-Abs $OutDir
if ($OfflineDeb) { $OfflineDeb = Resolve-Abs $OfflineDeb }

$LIMIT = 2GB   # GitHub: 2 GiB per release asset
if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Force $OutDir | Out-Null }
if (-not $OfflineDeb) { $OfflineDeb = Join-Path $OutDir "claude-desktop_${Version}+offline1_amd64.deb" }

$payloads = @(
    (Join-Path $Staging "Claude-$Version-x64-offline.msix")
    $OfflineDeb
    (Join-Path $Staging "claude-desktop_${Version}_amd64.deb")
    (Join-Path $Staging "claude-desktop_${Version}_arm64.deb")
)

$rows = @()
foreach ($src in $payloads) {
    if (-not (Test-Path $src)) { Write-Host "  MISSING  $src" -ForegroundColor Red; continue }
    $name = Split-Path $src -Leaf
    $zip  = Join-Path $OutDir "$name.zip"
    if (Test-Path $zip) { Remove-Item -Force $zip }
    Write-Host ("  zipping {0} ({1:N1} MB)..." -f $name, ((Get-Item $src).Length / 1MB))

    $fs = [System.IO.File]::Open($zip, [System.IO.FileMode]::CreateNew)
    $ar = New-Object System.IO.Compression.ZipArchive($fs, [System.IO.Compression.ZipArchiveMode]::Create)
    $en = $ar.CreateEntry($name, [System.IO.Compression.CompressionLevel]::Fastest)
    $es = $en.Open(); $in = [System.IO.File]::OpenRead($src)
    $in.CopyTo($es, 1MB); $in.Close(); $es.Close(); $ar.Dispose(); $fs.Close()

    $zlen = (Get-Item $zip).Length
    $rows += [pscustomobject]@{
        Payload    = $name
        PayloadSha = (Get-FileHash $src -Algorithm SHA256).Hash.ToLower()
        Zip        = "$name.zip"
        ZipSha     = (Get-FileHash $zip -Algorithm SHA256).Hash.ToLower()
        ZipBytes   = $zlen
        Headroom   = $LIMIT - $zlen
    }
}

Write-Host "`n=== Payload SHA256 (verify these) ===" -ForegroundColor Cyan
$rows | ForEach-Object { "{0}  {1}" -f $_.PayloadSha, $_.Payload }

Write-Host "`n=== Zip SHA256 (transfer integrity only) ===" -ForegroundColor Cyan
$rows | ForEach-Object { "{0}  {1}  {2:N1} MB" -f $_.ZipSha, $_.Zip, ($_.ZipBytes / 1MB) }

Write-Host "`n=== GitHub 2 GiB asset limit ===" -ForegroundColor Cyan
foreach ($r in $rows) {
    $color = if ($r.Headroom -lt 200MB) { 'Yellow' } else { 'Gray' }
    Write-Host ("  {0,-52} headroom {1,7:N0} MB" -f $r.Zip, ($r.Headroom / 1MB)) -ForegroundColor $color
    if ($r.Headroom -lt 0) { Write-Host "    OVER THE LIMIT - this asset cannot be uploaded; split it." -ForegroundColor Red }
}
$total = ($rows | Measure-Object -Property ZipBytes -Sum).Sum / 1GB
Write-Host ("`n  Total upload: {0:N2} GB across {1} assets`n" -f $total, $rows.Count)
