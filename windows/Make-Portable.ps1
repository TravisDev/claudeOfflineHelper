<#
.SYNOPSIS
    Extracts an MSIX into a portable folder tree. READ THE LIMITATIONS FIRST.

.DESCRIPTION
    This is NOT a supported deployment method and it does NOT give you a working
    Claude Desktop.

    Cowork and Code sessions run their sandbox through CoworkVMService, a Windows
    service that the package manifest registers to run as localSystem, started on
    demand via the named pipe \pipe\cowork-vm-service. The manifest also claims the
    restricted capabilities packagedServices, localSystemServices and
    unvirtualizedResources, and registers machine-wide firewall rules.

    A folder cannot register a service, hold restricted capabilities, or install
    firewall rules. So:

        Chat against Bedrock  ->  expected to work, UNVERIFIED
        Cowork sessions       ->  will NOT work
        Code sessions         ->  will NOT work

    If you want an install that needs no admin rights and is cleanly reversible, use
    Add-AppxPackage instead - it installs into the user profile and is removed with
    Remove-AppxPackage. See docs/05-WINDOWS-INSTALL.md.

    Use this script to inspect the payload or to triage, not to deploy.

.EXAMPLE
    .\Make-Portable.ps1 -MsixPath .\Claude-1.30096.5-x64-offline.msix -OutDir .\Claude-Portable
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$MsixPath,
    [string]$OutDir = '.\Claude-Portable',
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

Write-Host ''
Write-Host '  ============================================================' -ForegroundColor Yellow
Write-Host '   PORTABLE EXTRACTION - LIMITED FUNCTIONALITY' -ForegroundColor Yellow
Write-Host '  ============================================================' -ForegroundColor Yellow
Write-Host '   Cowork and Code sessions will NOT work from a portable folder.'
Write-Host '   They need CoworkVMService, a localSystem Windows service that only'
Write-Host '   a real MSIX installation can register.'
Write-Host ''
Write-Host '   For a no-admin install that actually works:'
Write-Host '     Add-AppxPackage -Path .\Claude-<ver>-x64-offline.msix' -ForegroundColor Cyan
Write-Host '  ============================================================' -ForegroundColor Yellow
Write-Host ''

if (-not (Test-Path $MsixPath)) { throw "Package not found: $MsixPath" }

if (Test-Path $OutDir) {
    if (-not $Force) { throw "$OutDir already exists. Pass -Force to overwrite." }
    Remove-Item -Recurse -Force $OutDir
}
New-Item -ItemType Directory -Force $OutDir | Out-Null
$OutDir = (Resolve-Path $OutDir).Path

Write-Host "  Extracting $(Split-Path $MsixPath -Leaf) ..."
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::OpenRead((Resolve-Path $MsixPath).Path)
$total = $zip.Entries.Count
$i = 0
foreach ($entry in $zip.Entries) {
    $i++
    if ($i % 250 -eq 0) { Write-Progress -Activity 'Extracting' -Status "$i / $total" -PercentComplete ($i / $total * 100) }

    # Skip package metadata that means nothing outside an installed package.
    if ($entry.FullName -match '^(AppxSignature\.p7x|AppxBlockMap\.xml|\[Content_Types\])') { continue }
    if ($entry.FullName.EndsWith('/')) { continue }

    $dest = Join-Path $OutDir ($entry.FullName -replace '/', '\')
    $parent = Split-Path $dest -Parent
    if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Force $parent | Out-Null }
    [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $dest, $true)
}
Write-Progress -Activity 'Extracting' -Completed
$zip.Dispose()

$exe = Join-Path $OutDir 'app\Claude.exe'
if (-not (Test-Path $exe)) { throw "Extraction finished but app\Claude.exe is missing." }

# Launcher: keep all user data inside the portable folder.
$launcher = @'
@echo off
REM Portable launcher for Claude Desktop.
REM Chat may work. Cowork and Code will not - see Make-Portable.ps1 for why.

setlocal
set "PORTABLE_ROOT=%~dp0"
set "LOCALAPPDATA=%PORTABLE_ROOT%data\LocalAppData"
set "APPDATA=%PORTABLE_ROOT%data\AppData"
set "USERPROFILE=%PORTABLE_ROOT%data\UserProfile"

if not exist "%LOCALAPPDATA%" mkdir "%LOCALAPPDATA%"
if not exist "%APPDATA%"      mkdir "%APPDATA%"
if not exist "%USERPROFILE%"  mkdir "%USERPROFILE%"

start "" "%PORTABLE_ROOT%app\Claude.exe" %*
endlocal
'@
Set-Content -Path (Join-Path $OutDir 'Claude-Portable.cmd') -Value $launcher -Encoding ASCII

$readme = @'
Claude Desktop - portable extraction
====================================

WHAT WORKS
  Chat against Bedrock: expected to work, but UNVERIFIED.

WHAT DOES NOT WORK
  Cowork sessions.  Code sessions.

WHY
  Both run their sandbox through CoworkVMService, a Windows service the MSIX
  manifest registers to run as localSystem, triggered on the named pipe
  \pipe\cowork-vm-service. The package also declares the restricted capabilities
  packagedServices, localSystemServices and unvirtualizedResources, and registers
  machine-wide firewall rules for Claude.exe and cowork-svc.exe.

  A copied folder registers no service, holds no restricted capabilities, and
  installs no firewall rules. Nothing here can bring that service into existence.

  Anthropic's own docs make the same point from the other direction: fleets
  provisioned with the legacy .exe (non-MSIX) installer get Claude Desktop
  WITHOUT Cowork.

RUN IT
  Claude-Portable.cmd

  User data is redirected into .\data\ so this does not touch your real profile.

CONFIGURATION
  With LOCALAPPDATA redirected, local config lives at:
    .\data\LocalAppData\Claude-3p\configLibrary\

  Machine policy at HKLM\SOFTWARE\Policies\Claude still applies - the registry is
  not redirected by the launcher.

WHAT YOU PROBABLY WANT INSTEAD
  MSIX installs into the user profile and normally needs no admin rights:

    Add-AppxPackage -Path .\Claude-<ver>-x64-offline.msix

  Remove it just as cleanly:

    Get-AppxPackage -Name Claude | Remove-AppxPackage

  That leaves nothing in Program Files and is fully reversible, which is usually
  what "portable" is actually asking for.
'@
Set-Content -Path (Join-Path $OutDir 'README.txt') -Value $readme -Encoding UTF8

$size = (Get-ChildItem $OutDir -Recurse -File | Measure-Object -Property Length -Sum).Sum / 1GB
Write-Host ''
Write-Host ("  Extracted to {0} ({1:N2} GB)" -f $OutDir, $size) -ForegroundColor Green
Write-Host '  Launch: .\Claude-Portable.cmd'
Write-Host '  Read README.txt in that folder before relying on any of it.'
Write-Host ''
