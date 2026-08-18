# claudeOfflineHelper

Offline install bundles and configuration docs for **Claude Desktop 1.30096.5**, for
machines on networks that block `anthropic.com` and `claude.ai`, running inference
against **Amazon Bedrock**.


> **Unofficial and unaffiliated.** This repository is not published, endorsed, or
> supported by Anthropic. It redistributes Anthropic's own installers unmodified, plus
> one **rebuilt** Linux package that is not a vendor artifact and carries no vendor
> signature. Anthropic will not support any of it. For official downloads go to
> [claude.com/download](https://claude.com/download); for support, contact Anthropic
> directly, not this repository.

---

## Read this first — the offline installer changes everything

An earlier round of research on this concluded that Claude Desktop *cannot* work on a
network that blocks `claude.ai`, because the app downloads its VM workspace bundle and
Claude CLI binary from `downloads.claude.ai` at session start.

**That conclusion was wrong.** Anthropic publishes a separate **offline installer
variant** with both components built into the installer package and verified against
checksums compiled into the app. With it, sessions start with no connection to
Anthropic at all.

> Standard installs fetch two large runtime components from `downloads.claude.ai` at
> session start: the VM workspace bundle that Cowork sessions run in, and the Claude CLI
> binary. For networks that cannot reach `downloads.claude.ai`, Anthropic publishes an
> offline installer variant with both components built into the installer package.
>
> — [Installation and setup › Offline installation](https://claude.com/docs/third-party/claude-desktop/installation#offline-installation)

This repo ships that offline installer for Windows. Verified by inspecting the package:
it contains `preseed/vm_bundle/rootfs.vhdx.zst` (1.27 GB), the VM kernel and initrd, and
the Claude CLI binaries for both `win32-x64` and `linux-x64`.

**With the offline installer plus the locked-down config in this repo, the only host
your firewall needs to allow is your Bedrock endpoint.** No Anthropic egress at all.

---

## What you need to know per platform

| Platform | Offline installer | Egress needed at runtime |
|---|---|---|
| **Windows x64 / Arm64** | **Official** — shipped here | Bedrock only |
| macOS (Intel / Apple silicon) | Official — not staged here, [URLs in the docs](docs/09-UPDATING.md) | Bedrock only |
| **Linux (amd64)** | **Built here** — Anthropic ships none | Bedrock only (unsupported build) |
| Linux (arm64) | Buildable, not staged | Bedrock only (unsupported build) |

Anthropic publishes offline installers for Windows and macOS only — the Linux offline
endpoints return HTTP 400, and the docs' offline table has no Linux row.

**But the Linux build already contains the entire offline code path.** Anthropic just
doesn't ship a package with the data files populated:

```js
var x2t = `preseed`, S2t = `vm_bundle`, AU = `claude-code`;
function jU(){ return path.join(process.resourcesPath, x2t) }
D.info(`[preseed] staging VM bundle cache ${r}.zst from package`);
D.info(`[preseed] installing Claude CLI ${e.platform} from package`);
```

So this repo builds one: [`scripts/build-offline-deb.sh`](scripts/build-offline-deb.sh)
injects the VM workspace image, kernel, initrd, and Claude CLI into
`resources/preseed/`, each verified against checksums compiled into the application.
The result is `claude-desktop_1.30096.5+offline1_amd64.deb` (1.6 GB).

**This is unsupported** — you are modifying a vendor package and losing its signature.
Read [docs/11-BUILD-OFFLINE-DEB.md](docs/11-BUILD-OFFLINE-DEB.md), especially the risks
section, before deploying it. If you can get `downloads.claude.ai` allowlisted instead,
do that — it is one hostname, supported, and survives updates for free.

The stock Linux `.deb` is also staged here for anyone who *can* reach that host.

---

## Quick start

1. **[docs/01-QUICKSTART.md](docs/01-QUICKSTART.md)** — pick your path, 10 minutes.
2. **[docs/03-BEDROCK-CONFIG.md](docs/03-BEDROCK-CONFIG.md)** — wire it to Bedrock.
3. **[docs/02-NETWORK-EGRESS.md](docs/02-NETWORK-EGRESS.md)** — hand this to the firewall team.

---

## Downloading the installers

The installers are **not in git** — GitHub rejects files over 100 MB, and the Windows
offline installer alone is 1.8 GB. They are attached to the release instead:

**https://github.com/TravisDev/claudeOfflineHelper/releases/tag/v1.30096.5**

| Asset | Size | What it is |
|---|---|---|
| `Claude-1.30096.5-x64-offline.msix.zip` | 1.80 GB | Windows x64, **official offline installer** — no Anthropic egress |
| `claude-desktop_1.30096.5+offline1_amd64.deb.zip` | 1.57 GB | Linux amd64, **offline build from this repo** — no Anthropic egress, [unsupported](docs/11-BUILD-OFFLINE-DEB.md) |
| `claude-desktop_1.30096.5_amd64.deb.zip` | 165 MB | Linux amd64, stock — needs `downloads.claude.ai` at session start |
| `claude-desktop_1.30096.5_arm64.deb.zip` | 157 MB | Linux arm64, stock — needs `downloads.claude.ai` at session start |

### No authentication needed

This repository is public, so the assets download anonymously — no token, no `gh`, no
GitHub account. On the target machine:

```bash
curl -LO https://github.com/TravisDev/claudeOfflineHelper/releases/download/v1.30096.5/claude-desktop_1.30096.5+offline1_amd64.deb.zip
```

```bash
wget https://github.com/TravisDev/claudeOfflineHelper/releases/download/v1.30096.5/Claude-1.30096.5-x64-offline.msix.zip
```

The asset URL pattern is:

```
https://github.com/TravisDev/claudeOfflineHelper/releases/download/v1.30096.5/<asset-name>
```

`curl -L` matters — the first response is a 302 to the storage backend, and without
`-L` you get a zero-byte file that looks like a failed download.

If you have `gh`, it works too and gives you resumable, checksum-friendly transfers:

```bash
gh release download v1.30096.5 --repo TravisDev/claudeOfflineHelper --pattern "*.zip"
```

Pull only what you need — all four assets together are 3.69 GB.

### Then verify

Unzip and check what you got — these files crossed a network boundary:

```bash
unzip 'claude-desktop_1.30096.5+offline1_amd64.deb.zip'
./scripts/verify-checksums.sh
```

The script checks whatever is present and skips the rest, so it is safe to run after a
partial download. Full hash list: [CHECKSUMS.md](CHECKSUMS.md).

---

## Documentation

| Doc | What it covers |
|---|---|
| [01 — Quickstart](docs/01-QUICKSTART.md) | Shortest path to a working Bedrock install |
| [02 — Network and egress](docs/02-NETWORK-EGRESS.md) | Full firewall allowlist; the zero-Anthropic-egress profile |
| [03 — Bedrock configuration](docs/03-BEDROCK-CONFIG.md) | All four auth methods, model IDs, VPC endpoints, GovCloud |
| [04 — Configuration reference](docs/04-CONFIG-REFERENCE.md) | Every managed key, config file paths, value-type rules |
| [05 — Windows install](docs/05-WINDOWS-INSTALL.md) | MSIX install, no-admin options, and the portable question answered |
| [06 — Linux install](docs/06-LINUX-INSTALL.md) | `.deb` install and the missing-offline-installer problem |
| [07 — Air-gapped Linux deps](docs/07-AIRGAP-LINUX-DEPS.md) | Staging apt dependencies with no archive access |
| [08 — Troubleshooting](docs/08-TROUBLESHOOTING.md) | Config not detected, EDR blocks, TLS interception, logs |
| [09 — Updating](docs/09-UPDATING.md) | Re-fetching installers on a connected machine |
| [10 — Claude Code CLI on Bedrock](docs/10-CLAUDE-CODE-CLI-BEDROCK.md) | The lighter-weight fallback path |
| [11 — Building an offline `.deb`](docs/11-BUILD-OFFLINE-DEB.md) | How the preseed injection works, and its risks |

---

## What is in this repo

```
claudeOfflineHelper/
├─ README.md                     you are here
├─ CHECKSUMS.md                  SHA256 for every artifact, raw and zipped
├─ docs/                         all documentation (10 files)
├─ windows/
│  ├─ README.md
│  ├─ Install-Claude.ps1         installs the MSIX, verifies checksum first
│  ├─ Make-Portable.ps1          extracts a portable tree (read the caveats)
│  └─ config/
│     ├─ bedrock-sso.reg         Bedrock via AWS SSO
│     ├─ bedrock-profile.reg     Bedrock via named AWS profile
│     └─ bedrock-lockeddown.reg  zero Anthropic egress
├─ linux/
│  ├─ README.md
│  ├─ install.sh
│  ├─ claude-desktop-archive-keyring.asc
│  └─ config/
│     ├─ managed-settings.json            Bedrock, minimal
│     └─ managed-settings-lockeddown.json zero Anthropic egress
└─ scripts/
   ├─ Fetch-Latest.ps1           re-download current installers (connected machine)
   ├─ verify-checksums.sh        verify what you pulled from Releases
   ├─ build-offline-deb.sh       build the offline Linux package (Docker)
   ├─ test-offline-deb.sh        install it in a container and verify
   └─ inspect-deb-manifests.py   read the bundle/CLI versions a .deb expects
```

Binaries are **not** in git — GitHub rejects files over 100 MB through git, and the
Windows offline installer is 1.8 GB. They are attached to the release instead
(2 GB per-asset limit), zipped.

---

## Versions staged here

| Artifact | Version | Size | Offline? |
|---|---|---|---|
| `Claude-1.30096.5-x64-offline.msix` | 1.30096.5 | 1.80 GB | Yes — official |
| `claude-desktop_1.30096.5+offline1_amd64.deb` | 1.30096.5 | 1.6 GB | Yes — built here, unsupported |
| `claude-desktop_1.30096.5_amd64.deb` | 1.30096.5 | 165 MB | No — stock |
| `claude-desktop_1.30096.5_arm64.deb` | 1.30096.5 | 157 MB | No — stock |

Checksums: [CHECKSUMS.md](CHECKSUMS.md). Verify before installing — these came off the
public internet and crossed a network boundary to get to you.
