<#
.SYNOPSIS
    Publishes this repo and its installer assets to a PRIVATE GitHub repo.

.DESCRIPTION
    Everything except GitHub authentication is already done. This script:
      1. authenticates gh (opens your browser once)
      2. creates TravisDev/claudeOfflineHelper as PRIVATE if it does not exist
      3. pushes the docs and scripts
      4. uploads the zipped installers as release assets under tag v1.30096.5

    The installers are ~2.1 GB total, so step 4 takes a while on a home connection.

.EXAMPLE
    .\PUSH-TO-GITHUB.ps1

.EXAMPLE
    .\PUSH-TO-GITHUB.ps1 -Repo myOfflineBundle -SkipAssets
#>
[CmdletBinding()]
param(
    [string]$Repo    = 'claudeOfflineHelper',
    [string]$Tag     = 'v1.30096.5',
    [string]$Version = '1.30096.5',
    [string]$AssetDir = '.\_release',
    [switch]$SkipAssets
)

$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

function Step ($m) { Write-Host "`n  $m" -ForegroundColor Cyan }
function Ok   ($m) { Write-Host "  [ ok ] $m" -ForegroundColor Green }
function Die  ($m) { Write-Host "  [FAIL] $m" -ForegroundColor Red; exit 1 }

$gh = "$env:ProgramFiles\GitHub CLI\gh.exe"
if (-not (Test-Path $gh)) { $gh = (Get-Command gh -ErrorAction SilentlyContinue).Source }
if (-not $gh) { Die 'GitHub CLI not found.  winget install --id GitHub.cli' }
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { Die 'git not found.' }

Write-Host "`n  Publish Claude Desktop offline bundle" -ForegroundColor White
Write-Host   "  ====================================="

# --- 1. auth ---------------------------------------------------------------
Step '[1/5] Authenticating with GitHub...'
& $gh auth status 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host '  A browser window will open. Enter the one-time code it shows.'
    & $gh auth login --hostname github.com --git-protocol https --web
    if ($LASTEXITCODE -ne 0) { Die 'Authentication failed.' }
}
$user = (& $gh api user --jq .login).Trim()
if (-not $user) { Die 'Could not determine your GitHub username.' }
Ok "Authenticated as $user"

# --- 2. repo ---------------------------------------------------------------
Step '[2/5] Ensuring the repository exists (private)...'
& $gh repo view "$user/$Repo" 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) {
    & $gh repo create "$user/$Repo" --private `
        --description 'Offline install bundles and Bedrock configuration docs for Claude Desktop'
    if ($LASTEXITCODE -ne 0) { Die "Could not create $user/$Repo." }
    Ok "Created $user/$Repo (private)"
    $branch = 'main'
} else {
    $vis = (& $gh repo view "$user/$Repo" --json visibility --jq .visibility).Trim()
    Ok "Found $user/$Repo [$vis]"
    if ($vis -ne 'PRIVATE') {
        Write-Host '  WARNING: this repository is NOT private.' -ForegroundColor Yellow
        $ans = Read-Host '  Continue anyway? (y/N)'
        if ($ans -notmatch '^[Yy]') { Die 'Stopped.' }
    }
    $branch = (& $gh repo view "$user/$Repo" --json defaultBranchRef --jq .defaultBranchRef.name).Trim()
    if (-not $branch) { $branch = 'main' }
}

# --- 3. commit -------------------------------------------------------------
Step '[3/5] Committing...'
if (-not (Test-Path .git)) { git init -b $branch | Out-Null }
git remote get-url origin 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) { git remote add origin "https://github.com/$user/$Repo.git" }

git add -A
git -c user.name="$user" -c user.email="$user@users.noreply.github.com" `
    commit -q -m "Claude Desktop $Version offline bundle: offline installer, Bedrock config, docs" 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) { Write-Host '  (nothing new to commit)' }

$tracked = (git ls-files | Measure-Object).Count
Ok "$tracked files tracked"

$big = git ls-files | Where-Object { (Test-Path $_) -and (Get-Item $_).Length -gt 100MB }
if ($big) { Die "These tracked files exceed GitHub's 100 MB git limit:`n    $($big -join "`n    ")" }

# --- 4. push ---------------------------------------------------------------
Step '[4/5] Pushing...'
git fetch origin $branch 2>$null | Out-Null
if ($LASTEXITCODE -eq 0) {
    git -c user.name="$user" -c user.email="$user@users.noreply.github.com" `
        pull --rebase origin $branch --allow-unrelated-histories
    if ($LASTEXITCODE -ne 0) { Die 'Rebase conflict. Resolve it, then re-run.' }
}
git push -u origin $branch
if ($LASTEXITCODE -ne 0) { Die 'Push failed.' }
Ok 'Pushed'

# --- 5. release assets -----------------------------------------------------
if ($SkipAssets) {
    Write-Host "`n  -SkipAssets: release not touched.`n"
} else {
    Step '[5/5] Uploading installers as release assets...'
    $assets = @(Get-ChildItem $AssetDir -Filter *.zip -ErrorAction SilentlyContinue)
    if (-not $assets) { Die "No .zip files in $AssetDir. Run scripts\Fetch-Latest.ps1 first." }

    $totalGB = ($assets | Measure-Object -Property Length -Sum).Sum / 1GB
    $assets | ForEach-Object { Write-Host ("    {0}  {1:N1} MB" -f $_.Name, ($_.Length / 1MB)) }
    Write-Host ("  {0:N2} GB total - this will take a while." -f $totalGB) -ForegroundColor Yellow

    $paths = $assets | ForEach-Object { $_.FullName }
    & $gh release view $Tag --repo "$user/$Repo" 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) {
        $notes = @"
Claude Desktop $Version offline install bundle.

**Windows** uses Anthropic's official offline installer - the VM workspace bundle and
Claude CLI are built in, so sessions start with no connection to Anthropic. The only
egress needed is your Bedrock endpoint.

**Linux** has no official offline installer, but the Linux build supports the same
preseed mechanism, so this repo builds one: ``claude-desktop_${Version}+offline1_amd64.deb``.
It is a modified vendor package and therefore **unsupported** - read
docs/11-BUILD-OFFLINE-DEB.md before deploying it. The stock .deb is also attached for
anyone who can allowlist downloads.claude.ai (the preferred route).

All assets are zipped. Unzip before installing, and verify against CHECKSUMS.md.

| Payload | SHA256 |
|---|---|
| Claude-$Version-x64-offline.msix | c2ae7281a3d10e74abfdd430359da813ada90fd5b9eefb0db2212e574ac0895a |
| claude-desktop_${Version}+offline1_amd64.deb | 959ed6c39af8110abdd178a3bec45a1986a39854459d11dcc04ae9722334cb0c |
| claude-desktop_${Version}_amd64.deb | e699763dd0e33bd831a1c771ea2684ead894f2680f02c71693a4e345046bd8f5 |
| claude-desktop_${Version}_arm64.deb | 9de0fbb5300d80bbf91dc7e4a4d066bfd6bead3830a0d7ae6c8b0a8529cf59ea |
"@
        & $gh release create $Tag --repo "$user/$Repo" --title "Claude Desktop $Version" --notes $notes @paths
    } else {
        & $gh release upload $Tag --repo "$user/$Repo" @paths --clobber
    }
    if ($LASTEXITCODE -ne 0) { Die 'Asset upload failed. Re-run to resume - existing assets are skipped unless --clobber.' }
    Ok 'Assets uploaded'
}

Write-Host "`n  DONE" -ForegroundColor Green
& $gh repo view "$user/$Repo" --json url,visibility --jq '"  \(.url)  [\(.visibility)]"'
Write-Host @"

  On the target machine:
    gh release download $Tag --repo $user/$Repo --pattern "*.zip"
    ./scripts/verify-checksums.sh

"@
