<#
.SYNOPSIS
    Downloads the current Claude Desktop offline installers on a connected machine.

.DESCRIPTION
    Run this on a machine with open internet, then publish the output as a GitHub
    release for the isolated side to pull.

    Note the User-Agent handling: claude.ai's download endpoints return HTTP 403 to
    clients that do not send a browser UA. This script sends one.

.EXAMPLE
    .\Fetch-Latest.ps1 -CheckOnly

.EXAMPLE
    .\Fetch-Latest.ps1 -OutDir .\_staging -Include WindowsX64,LinuxAmd64
#>
[CmdletBinding()]
param(
    [string]$OutDir = '.\_staging',

    [ValidateSet('WindowsX64', 'WindowsArm64', 'LinuxAmd64', 'LinuxArm64', 'MacArm64', 'MacX64')]
    [string[]]$Include = @('WindowsX64', 'LinuxAmd64', 'LinuxArm64'),

    # Report the current version without downloading anything.
    [switch]$CheckOnly,

    # Skip creating .zip wrappers.
    [switch]$NoZip
)

$ErrorActionPreference = 'Stop'
$UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36'

$targets = @{
    WindowsX64   = @{ Url = 'https://claude.ai/api/desktop/win32/x64/offline/latest/redirect';   Name = 'Claude-{0}-x64-offline.msix';   Offline = $true  }
    WindowsArm64 = @{ Url = 'https://claude.ai/api/desktop/win32/arm64/offline/latest/redirect'; Name = 'Claude-{0}-arm64-offline.msix'; Offline = $true  }
    MacArm64     = @{ Url = 'https://claude.ai/api/desktop/darwin/arm64/offline/latest/redirect'; Name = 'Claude-{0}-arm64-offline.dmg'; Offline = $true  }
    MacX64       = @{ Url = 'https://claude.ai/api/desktop/darwin/x64/offline/latest/redirect';   Name = 'Claude-{0}-x64-offline.dmg';   Offline = $true  }
    LinuxAmd64   = @{ Url = 'https://claude.ai/api/desktop/linux/x64/deb/latest/redirect';        Name = 'claude-desktop_{0}_amd64.deb'; Offline = $false }
    LinuxArm64   = @{ Url = 'https://claude.ai/api/desktop/linux/arm64/deb/latest/redirect';      Name = 'claude-desktop_{0}_arm64.deb'; Offline = $false }
}

function Get-RedirectTarget([string]$Url) {
    # Resolve without downloading the body, so a version check is nearly free.
    $req = [System.Net.HttpWebRequest]::Create($Url)
    $req.UserAgent         = $UA
    $req.AllowAutoRedirect = $false
    $req.Method            = 'GET'
    try {
        $resp = $req.GetResponse()
        $loc  = $resp.Headers['Location']
        $resp.Close()
        return $loc
    } catch [System.Net.WebException] {
        $r = $_.Exception.Response
        if ($r) {
            $loc = $r.Headers['Location']
            $code = [int]$r.StatusCode
            $r.Close()
            if ($loc) { return $loc }
            throw "HTTP $code from $Url"
        }
        throw
    }
}

Write-Host "`n  Claude Desktop - fetch current installers`n  ========================================`n"

$plan = @()
foreach ($key in $Include) {
    $t = $targets[$key]
    Write-Host "  $key ..." -NoNewline
    try {
        $loc = Get-RedirectTarget $t.Url
        if (-not $loc) { Write-Host ' no redirect' -ForegroundColor Yellow; continue }
        $version = if ($loc -match '/(\d+\.\d+\.\d+)/') { $Matches[1] } else { 'unknown' }
        Write-Host " $version" -ForegroundColor Green
        $plan += [pscustomobject]@{
            Key = $key; Version = $version; Url = $loc
            FileName = ($t.Name -f $version); Offline = $t.Offline
        }
    } catch {
        Write-Host " FAILED - $($_.Exception.Message)" -ForegroundColor Red
    }
}

if (-not $plan) { Write-Host "`n  Nothing resolved.`n" -ForegroundColor Red; exit 1 }

Write-Host ''
$plan | Format-Table Key, Version, FileName -AutoSize

if ($CheckOnly) {
    Write-Host "  -CheckOnly: nothing downloaded.`n"
    exit 0
}

if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Force $OutDir | Out-Null }
$OutDir = (Resolve-Path $OutDir).Path

foreach ($p in $plan) {
    $dest = Join-Path $OutDir $p.FileName
    Write-Host "  Downloading $($p.FileName) ..."
    try {
        # curl.exe streams to disk and shows progress; these are up to ~2 GB.
        & curl.exe -sSL -A $UA -o $dest $p.Url
        if ($LASTEXITCODE -ne 0) { throw "curl exited $LASTEXITCODE" }
    } catch {
        Write-Host "    FAILED: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host '    If this is a 404, the offline build for that version is not published yet.' -ForegroundColor Yellow
        Write-Host '    Keep your last known-good installer and retry later.' -ForegroundColor Yellow
        continue
    }
    $mb = (Get-Item $dest).Length / 1MB
    Write-Host ("    {0:N1} MB" -f $mb) -ForegroundColor Green
}

Write-Host "`n  SHA256`n  ------"
Get-ChildItem $OutDir -File | Where-Object { $_.Extension -in '.msix', '.deb', '.dmg' } | ForEach-Object {
    $h = (Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLower()
    Write-Host "  $h  $($_.Name)"
}

if (-not $NoZip) {
    Write-Host "`n  Zipping for release upload..."
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    Add-Type -AssemblyName System.IO.Compression
    Get-ChildItem $OutDir -File | Where-Object { $_.Extension -in '.msix', '.deb', '.dmg' } | ForEach-Object {
        $zipPath = "$($_.FullName).zip"
        if (Test-Path $zipPath) { Remove-Item -Force $zipPath }
        $fs = [System.IO.File]::Open($zipPath, [System.IO.FileMode]::CreateNew)
        $ar = New-Object System.IO.Compression.ZipArchive($fs, [System.IO.Compression.ZipArchiveMode]::Create)
        $en = $ar.CreateEntry($_.Name, [System.IO.Compression.CompressionLevel]::Fastest)
        $es = $en.Open(); $in = [System.IO.File]::OpenRead($_.FullName)
        $in.CopyTo($es, 1MB); $in.Close(); $es.Close(); $ar.Dispose(); $fs.Close()
        Write-Host ("    {0}  ({1:N1} MB)" -f (Split-Path $zipPath -Leaf), ((Get-Item $zipPath).Length / 1MB))
    }
    Write-Host '    (these are already-compressed containers, so the zip saves almost nothing)' -ForegroundColor DarkGray
}

$ver = ($plan | Select-Object -First 1).Version
Write-Host @"

  Next:
    gh release create v$ver --repo <you>/claudeOfflineHelper ``
      --title "Claude Desktop $ver" $OutDir\*.zip

  Then update CHECKSUMS.md with the hashes above and commit.

"@
