<#
.SYNOPSIS
    Installs Claude Desktop from an offline MSIX package, with pre-flight checks.

.DESCRIPTION
    Verifies the package checksum, confirms the machine can actually run Cowork,
    warns if managed configuration is not in place, then installs.

    Deploy your managed configuration BEFORE running this. See docs/03-BEDROCK-CONFIG.md.

.EXAMPLE
    .\Install-Claude.ps1 -MsixPath .\Claude-1.30096.5-x64-offline.msix

.EXAMPLE
    .\Install-Claude.ps1 -MsixPath .\Claude.msix -SkipChecksum -AllUsers
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$MsixPath,

    # SHA256 of the 1.30096.5 x64 offline package. Override for other versions.
    [string]$ExpectedSha256 = 'c2ae7281a3d10e74abfdd430359da813ada90fd5b9eefb0db2212e574ac0895a',

    [switch]$SkipChecksum,

    # Provision for every user on the machine (requires elevation).
    [switch]$AllUsers
)

$ErrorActionPreference = 'Stop'

function Say  ($m) { Write-Host "  $m" }
function Ok   ($m) { Write-Host "  [ ok ] $m"   -ForegroundColor Green }
function Warn ($m) { Write-Host "  [warn] $m"   -ForegroundColor Yellow }
function Die  ($m) { Write-Host "  [FAIL] $m"   -ForegroundColor Red; exit 1 }

Write-Host "`n  Claude Desktop offline installer`n  ===============================`n"

# --- package present -------------------------------------------------------
if (-not (Test-Path $MsixPath)) { Die "Package not found: $MsixPath" }
$pkg = Get-Item $MsixPath
Say ("Package : {0} ({1:N1} MB)" -f $pkg.Name, ($pkg.Length / 1MB))

# --- checksum --------------------------------------------------------------
if ($SkipChecksum) {
    Warn 'Checksum verification skipped (-SkipChecksum).'
} else {
    Say 'Verifying SHA256 (this reads the whole file, give it a moment)...'
    $actual = (Get-FileHash $MsixPath -Algorithm SHA256).Hash.ToLower()
    if ($actual -ne $ExpectedSha256.ToLower()) {
        Write-Host "    expected : $($ExpectedSha256.ToLower())" -ForegroundColor Red
        Write-Host "    actual   : $actual"                      -ForegroundColor Red
        Die 'Checksum mismatch. Do not install this file. Re-download it.'
    }
    Ok 'Checksum matches.'
}

# --- offline vs standard package -------------------------------------------
try {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [System.IO.Compression.ZipFile]::OpenRead($pkg.FullName)
    $hasPreseed = $null -ne ($zip.Entries | Where-Object { $_.FullName -like '*preseed/vm_bundle/rootfs.vhdx.zst' })
    $zip.Dispose()
    if ($hasPreseed) {
        Ok 'Offline package confirmed (VM bundle + CLI are built in).'
    } else {
        Warn 'This looks like the STANDARD package, not the offline one.'
        Warn 'It will need downloads.claude.ai at session start. See docs/05-WINDOWS-INSTALL.md.'
    }
} catch {
    Warn "Could not inspect package contents: $($_.Exception.Message)"
}

# --- OS build --------------------------------------------------------------
$build = [int](Get-CimInstance Win32_OperatingSystem).BuildNumber
if ($build -lt 19041) {
    Die "Windows build $build is too old. Cowork needs build 19041 (version 2004) or later."
}
Ok "Windows build $build."

# --- S Mode ----------------------------------------------------------------
try {
    $sMode = Get-ItemPropertyValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\CI\Policy' `
                                   -Name 'SkuPolicyRequired' -ErrorAction Stop
    if ($sMode -eq 1) { Die 'Windows is in S Mode. MSIX sideloading is blocked until S Mode is turned off.' }
} catch { }
Ok 'S Mode not detected.'

# --- virtualization --------------------------------------------------------
try {
    $ci = Get-ComputerInfo -Property HyperVRequirementVirtualizationFirmwareEnabled, HyperVisorPresent -ErrorAction Stop
    if ($ci.HyperVisorPresent) {
        Ok 'Hypervisor present.'
    } elseif ($ci.HyperVRequirementVirtualizationFirmwareEnabled -eq $false) {
        Warn 'Hardware virtualization appears DISABLED in firmware. Cowork sessions will not start.'
        Warn 'Enable VT-x / AMD-V in BIOS/UEFI.'
    } else {
        Ok 'Virtualization available.'
    }
} catch {
    Warn 'Could not determine virtualization state.'
}

# --- managed configuration -------------------------------------------------
$policy = 'HKLM:\SOFTWARE\Policies\Claude'
if (Test-Path $policy) {
    $provider = (Get-ItemProperty $policy -ErrorAction SilentlyContinue).inferenceProvider
    if ($provider) {
        Ok "Managed config found: inferenceProvider = $provider"
        $bad = Get-Item $policy | ForEach-Object { $_.GetValueNames() } | Where-Object {
            (Get-Item $policy).GetValueKind($_) -ne 'String'
        }
        if ($bad) {
            Warn "These values are not REG_SZ and the app may ignore the whole hive: $($bad -join ', ')"
        }
    } else {
        Warn "$policy exists but has no inferenceProvider value."
    }
} else {
    Warn 'No managed configuration at HKLM\SOFTWARE\Policies\Claude.'
    Warn 'The app will show the claude.ai sign-in screen. Import a .reg from windows\config\ first.'
}

# --- install ---------------------------------------------------------------
Write-Host ''
Say 'Installing...'
try {
    if ($AllUsers) {
        $elevated = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
                    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        if (-not $elevated) { Die '-AllUsers requires an elevated PowerShell session.' }
        Add-AppxProvisionedPackage -Online -PackagePath $pkg.FullName -SkipLicense | Out-Null
        Ok 'Provisioned for all users.'
    } else {
        Add-AppxPackage -Path $pkg.FullName
        Ok 'Installed for the current user.'
    }
} catch {
    Write-Host ''
    Die @"
Install failed: $($_.Exception.Message)

Common causes:
  * Signature validation  - stale certificate store; install the DigiCert Trusted Root G4 chain.
  * S Mode                - must be turned off.
  * Sideloading disabled  - Settings > System > For developers.
"@
}

# --- verify ----------------------------------------------------------------
$installed = Get-AppxPackage -Name Claude -ErrorAction SilentlyContinue
if ($installed) {
    Write-Host ''
    Ok "Claude $($installed.Version) installed."
    Say "Location: $($installed.InstallLocation)"
    Write-Host ''
    Say 'Next: launch Claude, then Help > Troubleshooting > Copy Managed Configuration Report'
    Say 'to confirm the Bedrock configuration was actually read.'
    Write-Host ''
} else {
    Die 'Install reported success but the package is not registered.'
}
