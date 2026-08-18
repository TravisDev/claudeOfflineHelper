# 09 — Updating the offline bundle

An offline deployment means **you own the update pipeline.** Anthropic pairs the offline
installer with `disableAutoUpdates: true` for exactly this reason: the app cannot reach
the update feed, so leaving the updater enabled just adds a failing network call at
startup.

---

## Turn the updater off

```json
{ "disableAutoUpdates": true }
```

Worth knowing about the default behavior you are switching off: with auto-update enabled,
if the app has not restarted within 72 hours of downloading an update, **it restarts
itself**, after waiting for 10 minutes of user inactivity. That enforcement is always on
and there is no in-app prompt to defer it. `autoUpdaterEnforcementHours` (1–72) tunes the
window rather than enabling it — and setting it also makes the window *strict*, firing as
soon as it elapses without waiting for an activity pause.

---

## Refresh the bundle

On a machine with open internet, from the repo root:

```powershell
.\scripts\Fetch-Latest.ps1 -OutDir .\_staging
```

It downloads the current Windows offline MSIX and both Linux `.deb` packages, prints
SHA256 for each, and zips them for upload.

Check for a new version without downloading gigabytes — the redirect's `Location` header
carries the version number:

```powershell
.\scripts\Fetch-Latest.ps1 -CheckOnly
```

### By hand

The `User-Agent` matters. These endpoints return **HTTP 403** to clients that do not send
a browser UA:

```bash
UA='Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36'

# check the current version without downloading
curl -sI -A "$UA" https://claude.ai/api/desktop/win32/x64/offline/latest/redirect | grep -i location

# download
curl -sSL -A "$UA" -o Claude-x64-offline.msix \
  https://claude.ai/api/desktop/win32/x64/offline/latest/redirect

curl -sSL -A "$UA" -o claude-desktop_amd64.deb \
  https://claude.ai/api/desktop/linux/x64/deb/latest/redirect
```

---

## All download URLs

These are fixed and always serve the current release.

| Artifact | URL |
|---|---|
| Windows x64 **offline** | `https://claude.ai/api/desktop/win32/x64/offline/latest/redirect` |
| Windows Arm64 **offline** | `https://claude.ai/api/desktop/win32/arm64/offline/latest/redirect` |
| macOS Apple silicon **offline** | `https://claude.ai/api/desktop/darwin/arm64/offline/latest/redirect` |
| macOS Intel **offline** | `https://claude.ai/api/desktop/darwin/x64/offline/latest/redirect` |
| Windows x64 standard | `https://claude.ai/api/desktop/win32/x64/msix/latest/redirect` |
| Windows Arm64 standard | `https://claude.ai/api/desktop/win32/arm64/msix/latest/redirect` |
| Linux x64 `.deb` | `https://claude.ai/api/desktop/linux/x64/deb/latest/redirect` |
| Linux arm64 `.deb` | `https://claude.ai/api/desktop/linux/arm64/deb/latest/redirect` |
| Readiness check (Win x64) | `https://claude.ai/api/desktop/win32/x64/cowork-readiness-check/latest/redirect` |
| Readiness check (Win Arm64) | `https://claude.ai/api/desktop/win32/arm64/cowork-readiness-check/latest/redirect` |
| Readiness check (macOS) | `https://claude.ai/api/desktop/darwin/universal/cowork-readiness-check/latest/redirect` |

**No Linux offline variant exists** — `linux/*/offline` returns HTTP 400.

### Rollout timing gotcha

New versions roll out to connected devices gradually, and these URLs serve the newest
version whose rollout has **completed**. Right after a new version appears in the
`Location` header, its offline installer may not be built yet — the download then fails
with **HTTP 404 rather than falling back to the previous version**.

Keep the installer you last downloaded and retry later. Do not delete a known-good
offline installer until its replacement is downloaded and checksummed.

---

## Publish a new release

```bash
VER=1.30097.0

gh release create "v$VER" --repo TravisDev/claudeOfflineHelper \
  --title "Claude Desktop $VER" \
  --notes-file RELEASE-NOTES.md \
  _staging/*.zip
```

To replace assets on an existing tag:

```bash
gh release upload "v$VER" --repo TravisDev/claudeOfflineHelper _staging/*.zip --clobber
```

Then update [CHECKSUMS.md](../CHECKSUMS.md) with the new hashes and commit. **The
checksums are the deliverable** — an offline bundle whose hashes nobody verified is just
a large file of unknown provenance that crossed a network boundary.

---

## Roll it out

1. Download and checksum on the connected machine.
2. Publish the release.
3. Pull on the target side:

```bash
gh release download v1.30097.0 --repo TravisDev/claudeOfflineHelper --pattern "*.zip"
./scripts/verify-checksums.sh
```

4. Install over the existing version — MSIX and `.deb` both upgrade in place:

```powershell
Add-AppxPackage -Path .\Claude-<ver>-x64-offline.msix
```

```bash
sudo apt install ./claude-desktop_<ver>_amd64.deb
```

Managed configuration survives an upgrade; it lives in the registry or
`/etc/claude-desktop/`, not in the package.

5. Keep the previous version's installer until the new one is confirmed working on a
   pilot machine. Rolling back an offline fleet means reinstalling the old package, and
   you cannot re-download it — these URLs only ever serve *current*.

---

## Version pinning reality

The `latest/redirect` URLs move without warning. On 2026-08-17 they served 1.30096.5 in
the morning and **1.32352.0** by the evening — same URLs, different release, no notice.
If you re-run a download expecting to reproduce an earlier bundle, you will silently get
a newer one whose checksums do not match anything you recorded.

**Versioned paths remain hosted and are the way to pin.** Once you know a release's
version and commit hash, these keep working:

```
https://downloads.claude.ai/releases-offline/win32/x64/<version>/Claude-<commit>-offline.msix
https://downloads.claude.ai/releases/win32/x64/<version>/Claude-<commit>.msix
https://downloads.claude.ai/releases/linux/<x64|arm64>/<version>/Claude-<commit>.deb
https://downloads.claude.ai/vms/linux/<x64|arm64>/<bundle-sha>/<file>.zst
```

For 1.30096.5 the commit hash is `6e13464cbd9c3dc0501fe5ecb0568e3d3e9ea77a`. Read it from
any build with `scripts/inspect-deb-manifests.py`, or from the `Location` header of a
`latest/redirect` request while that version is current.

Two consequences worth planning around:

1. **Record the version and commit hash the moment you download**, not later. It is the
   only way back to that exact build.
2. **Your GitHub release is your version archive.** Do not prune old releases to save
   space — and never mix artifacts pulled at different times into one release without
   re-verifying, since `latest` may have moved between them.
