# Checksums

Claude Desktop **1.30096.5**. Everything here was pulled directly from Anthropic's
official release endpoints on 2026-08-17.

Release assets are distributed as `.zip`. Verify the zip, unzip, then verify the
payload — the inner checksum is the one that matters, because it is what you actually
install.

## Zipped release assets (what you download from Releases)

| SHA256 | File | Size |
|---|---|---|
| `230935a518402b1a35b7783ed224d4a53dc436046b319f1aa11667b8ff16c066` | `Claude-1.30096.5-x64-offline.msix.zip` | 1839 MB |
| `48c8dad8ab19652063b6eca8f271e83d047458f486988aa082166289f5979d02` | `claude-desktop_1.30096.5+offline1_amd64.deb.zip` | 1612.9 MB |
| `1c4b9ba49063fa8c3c5558003d7bf40ca9e2d93c95c3e5fdfca4a68fed6ed2b0` | `claude-desktop_1.30096.5_amd64.deb.zip` | 164.6 MB |
| `eacba1ad5ebc011847e5da04fa861bae1639d0348b6d10d9cdb3ab13d4a8d1e0` | `claude-desktop_1.30096.5_arm64.deb.zip` | 157.1 MB |

> The zip layer saves essentially nothing (0.1%, 0%, −0.1%). MSIX is a ZIP container
> already and `.deb` payloads are zstd-compressed, so there is nothing left to squeeze.
> The zips exist for packaging consistency, not size.

## Unzipped payloads (what you install)

| SHA256 | File | Size |
|---|---|---|
| `c2ae7281a3d10e74abfdd430359da813ada90fd5b9eefb0db2212e574ac0895a` | `Claude-1.30096.5-x64-offline.msix` | 1841.7 MB |
| `faa804b7feb2d3e90960b4f1e078057bb4ca270f4b9466c943bd90f90846c94f` | `claude-desktop_1.30096.5+offline1_amd64.deb` | 1612.8 MB |
| `e699763dd0e33bd831a1c771ea2684ead894f2680f02c71693a4e345046bd8f5` | `claude-desktop_1.30096.5_amd64.deb` | 164.6 MB |
| `9de0fbb5300d80bbf91dc7e4a4d066bfd6bead3830a0d7ae6c8b0a8529cf59ea` | `claude-desktop_1.30096.5_arm64.deb` | 157.0 MB |

### The rebuilt offline `.deb`

`claude-desktop_1.30096.5+offline1_amd64.deb` is **built by this repo, not by Anthropic**
— see [docs/11](docs/11-BUILD-OFFLINE-DEB.md). Its hash is for the build produced on
2026-08-17; `dpkg-deb` output is not byte-reproducible (tar timestamps, xz threading), so
rebuilding gives a different hash for identical content. What is stable and verifiable is
the four injected components:

| SHA256 (compressed `.zst`) | Component |
|---|---|
| `bc64e0dbc039c30ce986ad3edd2d0cb38d57d78450be72b3a5d4e747c54bf482` | `preseed/vm_bundle/rootfs.img.zst` |
| `20214efcd451b3b74dc53ed80218c6e616bb2a101cafb18bc2c9bc91e559926b` | `preseed/vm_bundle/initrd.zst` |
| `1bb4bc3aa0c0c797a2ca6134d2b7034a196e05d4deea7bb20f064ee353781f3b` | `preseed/vm_bundle/vmlinuz.zst` |
| `c39722950b2cb1ceb2e1ffe4027fa89121150e3853b4f4f27a34e80a6e09cdbe` | `preseed/claude-code/linux-x64.zst` |

These come from VM bundle `6d1538ba6fecc4e5c5583993c4b30bb1875f0f5a` and Claude CLI
`2.1.229`, which are the versions compiled into app 1.30096.5. `build-offline-deb.sh`
refuses to build if any of them fails to match. Verify them on an installed machine:

```bash
cd /usr/lib/claude-desktop/resources/preseed && sha256sum vm_bundle/*.zst claude-code/*.zst
```

## Verify

**Linux / macOS**

```bash
sha256sum -c <<'EOF'
c2ae7281a3d10e74abfdd430359da813ada90fd5b9eefb0db2212e574ac0895a  Claude-1.30096.5-x64-offline.msix
e699763dd0e33bd831a1c771ea2684ead894f2680f02c71693a4e345046bd8f5  claude-desktop_1.30096.5_amd64.deb
9de0fbb5300d80bbf91dc7e4a4d066bfd6bead3830a0d7ae6c8b0a8529cf59ea  claude-desktop_1.30096.5_arm64.deb
EOF
```

Or use the bundled script, which skips files you did not download:

```bash
./scripts/verify-checksums.sh
```

**Windows**

```powershell
(Get-FileHash .\Claude-1.30096.5-x64-offline.msix -Algorithm SHA256).Hash.ToLower()
```

Compare against the table. `Install-Claude.ps1` does this automatically and refuses to
install on a mismatch.

## Source URLs

These are fixed URLs that always serve the current version, so they will eventually
serve something newer than 1.30096.5 and the checksums above will no longer match.
That is expected — see [docs/09-UPDATING.md](docs/09-UPDATING.md).

| Artifact | URL |
|---|---|
| Windows x64 offline | `https://claude.ai/api/desktop/win32/x64/offline/latest/redirect` |
| Windows Arm64 offline | `https://claude.ai/api/desktop/win32/arm64/offline/latest/redirect` |
| Windows x64 standard | `https://claude.ai/api/desktop/win32/x64/msix/latest/redirect` |
| macOS Apple silicon offline | `https://claude.ai/api/desktop/darwin/arm64/offline/latest/redirect` |
| macOS Intel offline | `https://claude.ai/api/desktop/darwin/x64/offline/latest/redirect` |
| Linux x64 `.deb` | `https://claude.ai/api/desktop/linux/x64/deb/latest/redirect` |
| Linux arm64 `.deb` | `https://claude.ai/api/desktop/linux/arm64/deb/latest/redirect` |

> **Gotcha:** these endpoints return **HTTP 403** to clients that do not send a browser
> `User-Agent`. `curl` with default settings gets a 403; add a browser UA and it returns
> a 307 redirect. `scripts/Fetch-Latest.ps1` handles this.

There is **no** Linux offline URL. `linux/x64/offline` and `linux/arm64/offline` return
HTTP 400.
