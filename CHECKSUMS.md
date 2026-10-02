# Checksums

Two releases are published. **v2.19675.0 is current**; v1.30096.5 is kept as the version
archive (see [docs/09](docs/09-UPDATING.md#version-pinning-reality) for why nothing is
ever deleted).

**Verify the payload, not the zip.** Release assets are `.zip` files, but ZIP stores entry
timestamps, so re-packaging identical bytes gives a different archive hash every time. The
zip hashes below identify the specific files attached to each release and are useful only
for confirming a download completed intact. The **payload** hashes are what pin the
software.

---

## v2.19675.0 (current)

Claude Desktop **2.19675.0**, commit `5706e5524dba58b23e105c31c358df8ab0a95852`, built
2026-10-01T05:47:14Z. Embedded components: VM bundle `882518393ed4ce89020bd48d99d5daf114999773`
(2026-09-11), Claude CLI 2.1.286.

### Release assets (zipped)

| SHA256 | File | Size |
|---|---|---|
| `29479abe5ef6c51a337c191e28120d9fbb5fd970476ff69ce75ddfe6284a653d` | `Claude-2.19675.0-x64-offline.msix.zip` | 1,901.1 MB |
| `9651208417843aafb22509bad280b28abbe08b44fc39ce0fdff23fa96667c983` | `claude-desktop_2.19675.0+offline1_amd64.deb.zip` | 1,551.3 MB |
| `0ad7a66eb0d3f5da25a5bf1dbf98322abc125a61a9ea0af6c463be088799906d` | `claude-desktop_2.19675.0_amd64.deb.zip` | 171.1 MB |
| `efa27b07bab390aa7cc26f702f5fabeb5e20cd5133520cc7556d86255153d2a2` | `claude-desktop_2.19675.0_arm64.deb.zip` | 164.8 MB |

> The zip layer saves essentially nothing: MSIX is already a ZIP container and `.deb`
> payloads are xz/zstd compressed. The Windows asset has **147 MB of headroom** under
> GitHub's 2 GiB limit and will not fit as a single asset for much longer; see
> [docs/09](docs/09-UPDATING.md#the-2-gib-asset-limit).

### Payloads (what you install)

| SHA256 | File | Size |
|---|---|---|
| `91c8cf150700331bdf6e87dcb3ac036effa98ce379697999197ddeeb0105687f` | `Claude-2.19675.0-x64-offline.msix` | 1,996,376,338 |
| `5fe9ad09dfec9066eccc9458616396ae042e597e982360fc02483d696fe26a54` | `claude-desktop_2.19675.0+offline1_amd64.deb` | 1,626,527,904 |
| `da476cf5b4f77f209cca4ab3558b94622b1c9dc6808bf1d9022352b9a1da8f9b` | `claude-desktop_2.19675.0_amd64.deb` | 179,359,984 |
| `55171972a988324fe6bcb6405506ff4deb42524d7e3cfefd88a6f85ce4660d5f` | `claude-desktop_2.19675.0_arm64.deb` | 172,800,392 |

The MSIX and the two stock `.deb` files are **unmodified Anthropic artifacts**, fetched
from the pinned versioned URLs below.

### The rebuilt offline `.deb`

`claude-desktop_2.19675.0+offline1_amd64.deb` is **built by this repo, not by Anthropic**
- see [docs/11](docs/11-BUILD-OFFLINE-DEB.md). Its hash above is valid for the file
attached to the release. `dpkg-deb` output is not byte-reproducible (tar timestamps, xz
threading): two builds from identical inputs on 2026-08-17 produced different hashes. So
**do not use the package hash to check a rebuild**. What is stable and verifiable is the
set of injected components, listed in
[`manifests/2.19675.0.amd64.preseed.sha256`](manifests/2.19675.0.amd64.preseed.sha256):

| SHA256 (compressed `.zst`) | Component |
|---|---|
| `1c3e856d002d52df2246446ce0e3ae21fb65fdd81451f29a8e908305697a52c0` | `preseed/vm_bundle/rootfs.img.zst` |
| `3118616ef6ba3866652284b8b4c224a96876c56091724c35c93caf1ccb9b50a9` | `preseed/vm_bundle/vmlinuz.zst` |
| `c12df253f5ddac9f7f7cdf317c7257586d262eabd9336c1ce001301399fbe56a` | `preseed/vm_bundle/initrd.zst` |
| `e8a5fa87ae465403ae5e8261e64c952527eb411828759d421086e14f05858531` | `preseed/vm_bundle/initrd-micro.zst` |
| `a14d80443473126e40cbc50eb78899f43e8f4d4336095863f8089a6b9ca02a97` | `preseed/claude-code/linux-x64.zst` |
| `fadfb069d2b8e3e304541c6b2ec0c0b87c71e081a8a3d6dfa4a511ba9217eb11` | `preseed/claude-ssh/linux-amd64.zst` |

Checksums are over the **compressed** `.zst` files, which is what the app verifies;
hashing the decompressed contents gives a false mismatch. They match values compiled into
app 2.19675.0, and the build refuses to run if any of them fails. Verify them on an
installed machine:

```bash
cd /usr/lib/claude-desktop/resources/preseed
grep -vE '^[[:space:]]*(#|$)' /path/to/repo/manifests/2.19675.0.amd64.preseed.sha256 | sha256sum -c -
```

---

## v1.30096.5 (previous)

Claude Desktop **1.30096.5**, commit `6e13464cbd9c3dc0501fe5ecb0568e3d3e9ea77a`, built
2026-08-14T21:58:49Z. VM bundle `6d1538ba6fecc4e5c5583993c4b30bb1875f0f5a` (2026-06-10),
Claude CLI 2.1.229.

| SHA256 | File |
|---|---|
| `9828bc43cf8cb68b8c7a8d697d5c699321eff8a5a0954da5d5b93c7d792c1bd7` | `Claude-1.30096.5-x64-offline.msix.zip` |
| `18080521d4ca7509be98924f8b78b1b5eb8b6f87b9ca06b497852ed098d1099c` | `claude-desktop_1.30096.5+offline1_amd64.deb.zip` |
| `7a6fa942da37073eec6341ea46e7ab1d6ca4fccf92823cdf0e609e58f76d8f49` | `claude-desktop_1.30096.5_amd64.deb.zip` |
| `0225b559ecb4b5d6df9bd6f82c530797c4cadef421a47bb91b3794a5a4301c12` | `claude-desktop_1.30096.5_arm64.deb.zip` |

| SHA256 (payload) | File |
|---|---|
| `c2ae7281a3d10e74abfdd430359da813ada90fd5b9eefb0db2212e574ac0895a` | `Claude-1.30096.5-x64-offline.msix` |
| `959ed6c39af8110abdd178a3bec45a1986a39854459d11dcc04ae9722334cb0c` | `claude-desktop_1.30096.5+offline1_amd64.deb` |
| `e699763dd0e33bd831a1c771ea2684ead894f2680f02c71693a4e345046bd8f5` | `claude-desktop_1.30096.5_amd64.deb` |
| `9de0fbb5300d80bbf91dc7e4a4d066bfd6bead3830a0d7ae6c8b0a8529cf59ea` | `claude-desktop_1.30096.5_arm64.deb` |

Its injected components are in
[`manifests/1.30096.5.amd64.preseed.sha256`](manifests/1.30096.5.amd64.preseed.sha256)
(three VM files and the CLI; that build predates `initrd-micro` and `claude-ssh`).

---

## Verify

```bash
./scripts/verify-checksums.sh          # checks whatever is present, skips the rest
```

```powershell
(Get-FileHash .\Claude-2.19675.0-x64-offline.msix -Algorithm SHA256).Hash.ToLower()
```

`windows/Install-Claude.ps1` and `linux/install.sh` check automatically and refuse to
install on a mismatch.

## Pinned source URLs

`latest/redirect` moves without warning (it served 1.30096.5, 1.32352.0, 1.32352.1 and
then 2.19675.0 over six weeks), so download from the versioned paths:

| Artifact | URL |
|---|---|
| Windows x64 offline | `https://downloads.claude.ai/releases-offline/win32/x64/2.19675.0/Claude-5706e5524dba58b23e105c31c358df8ab0a95852-offline.msix` |
| Windows x64 standard | `https://downloads.claude.ai/releases/win32/x64/2.19675.0/Claude-5706e5524dba58b23e105c31c358df8ab0a95852.msix` |
| Linux amd64 `.deb` | `https://downloads.claude.ai/releases/linux/x64/2.19675.0/Claude-5706e5524dba58b23e105c31c358df8ab0a95852.deb` |
| Linux arm64 `.deb` | `https://downloads.claude.ai/releases/linux/arm64/2.19675.0/Claude-5706e5524dba58b23e105c31c358df8ab0a95852.deb` |
| VM bundle (Linux x64) | `https://downloads.claude.ai/vms/linux/x64/882518393ed4ce89020bd48d99d5daf114999773/<name>.zst` |

For 1.30096.5 substitute version `1.30096.5` and commit
`6e13464cbd9c3dc0501fe5ecb0568e3d3e9ea77a` (VM bundle `6d1538ba6fecc4e5c5583993c4b30bb1875f0f5a`).

The moving `latest` endpoints, for checking what is current:

| Artifact | URL |
|---|---|
| Windows x64 offline | `https://claude.ai/api/desktop/win32/x64/offline/latest/redirect` |
| Windows Arm64 offline | `https://claude.ai/api/desktop/win32/arm64/offline/latest/redirect` |
| macOS Apple silicon offline | `https://claude.ai/api/desktop/darwin/arm64/offline/latest/redirect` |
| macOS Intel offline | `https://claude.ai/api/desktop/darwin/x64/offline/latest/redirect` |
| Linux x64 `.deb` | `https://claude.ai/api/desktop/linux/x64/deb/latest/redirect` |
| Linux arm64 `.deb` | `https://claude.ai/api/desktop/linux/arm64/deb/latest/redirect` |

> **Gotchas:** these endpoints return **HTTP 403** to clients that do not send a browser
> `User-Agent`, reject `HEAD` with **405** (use `GET`, and do not follow the redirect), and
> can return a transient 403 if you probe several in quick succession. Pause between
> requests. `scripts/Fetch-Latest.ps1` handles the User-Agent.

There is **no** Linux offline URL. `linux/x64/offline` and `linux/arm64/offline` return
HTTP 400.
