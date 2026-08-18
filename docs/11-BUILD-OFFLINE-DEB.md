# 11 — Building an offline Debian package

Anthropic ships an offline installer for Windows and macOS but not for Linux. This
document explains how to build one yourself, why it works, and what you are taking on by
doing it.

> **This is unsupported.** You are modifying a vendor package. Anthropic did not publish
> this configuration and will not support it. Read [Risks](#risks-read-before-deploying)
> before putting it on a fleet.
>
> **If you are redistributing the result publicly**, note that the rebuilt package keeps
> Anthropic's `Package:` name and `Maintainer: Anthropic PBC <support@anthropic.com>`
> field, so anyone who installs it sees Anthropic as the maintainer of software Anthropic
> did not build. The `+offline1` version suffix is the only marker distinguishing it.
> Consider whether redistributing a proprietary vendor's installers — modified or not —
> is something you have the right to do, and make the provenance unmissable to anyone who
> finds the download. Support requests for a rebuilt package are not Anthropic's to
> answer.

---

## Why this works

The Linux build already contains the entire offline code path. Anthropic simply does not
ship a package with the data files populated. From `resources/app.asar` in
`claude-desktop_1.30096.5_amd64.deb`:

```js
var x2t = `preseed`, S2t = `vm_bundle`, AU = `claude-code`;
function jU(){ return path.join(process.resourcesPath, x2t) }   // resources/preseed

// stages the VM bundle out of the package instead of downloading it
D.info(`[preseed] staging VM bundle cache ${r}.zst from package`);

// installs the Claude CLI out of the package
D.info(`[preseed] installing Claude CLI ${e.platform} from package`);
```

At session start the app looks in `resources/preseed/` first. If the files are there it
stages them into its cache and never contacts `downloads.claude.ai`. If they are absent
it falls back to downloading. Putting the right files in the right place is the whole
technique — no patching, no binary modification, no signature bypass.

## What the app expects

Two things have to line up exactly: the **VM bundle version** and the **Claude CLI
version**. Both are compiled into the application.

### VM bundle

The app resolves its bundle from an embedded manifest, taking the newest entry:

```js
var xV = { sha: $Zt.sha, files: $Zt.files };                       // $Zt = manifest.versions[0]
function tq(){ return process.arch === `x64` ? `x64` : `arm64` }
function sen(){ return `https://downloads.claude.ai/vms/linux/${tq()}/${xV.sha}` }
```

For app **1.30096.5** that is bundle `6d1538ba6fecc4e5c5583993c4b30bb1875f0f5a`
(published 2026-06-10). Linux uses `rootfs.img`; Windows uses `rootfs.vhdx`. Files are
served and staged zstd-compressed.

| File | SHA256 of the `.zst` | Size |
|---|---|---|
| `rootfs.img.zst` | `bc64e0dbc039c30ce986ad3edd2d0cb38d57d78450be72b3a5d4e747c54bf482` | 1,336,156,211 |
| `initrd.zst` | `20214efcd451b3b74dc53ed80218c6e616bb2a101cafb18bc2c9bc91e559926b` | 74,332,074 |
| `vmlinuz.zst` | `1bb4bc3aa0c0c797a2ca6134d2b7034a196e05d4deea7bb20f064ee353781f3b` | 14,745,575 |

> **The checksums are over the compressed `.zst` artifacts, not the decompressed
> contents.** Decompressing first and hashing that gives a mismatch and will send you
> chasing a problem that does not exist.

### Claude CLI

App 1.30096.5 expects CLI **2.1.229**, from an embedded manifest with
`baseUrl: https://downloads.claude.ai/claude-code-releases`:

| Platform | SHA256 | Size |
|---|---|---|
| `linux-x64` | `c39722950b2cb1ceb2e1ffe4027fa89121150e3853b4f4f27a34e80a6e09cdbe` | 68,644,044 |
| `linux-arm64` | `8ea9c7c217a6a8d1a8bf8c58288285a70c88ddd14c4b5a47d7c0c6ca3a4fdb63` | 67,495,276 |

Convenient shortcut: the **Windows offline MSIX already contains
`preseed/claude-code/linux-x64.zst`**, byte-identical to the above, because the Cowork
guest is Linux regardless of host. If you have the Windows offline package you can lift
the Linux CLI straight out of it.

## Target layout

```
/usr/lib/claude-desktop/resources/preseed/
├── vm_bundle/
│   ├── rootfs.img.zst
│   ├── initrd.zst
│   └── vmlinuz.zst
└── claude-code/
    └── linux-x64.zst
```

Compare with the Windows offline MSIX, which uses the identical structure:

```
app/resources/preseed/vm_bundle/rootfs.vhdx.zst
app/resources/preseed/vm_bundle/{initrd,vmlinuz}.zst
app/resources/preseed/claude-code/{win32-x64,linux-x64}.zst
```

---

## Build it

### 1. Fetch the components

On a machine with internet (note the browser `User-Agent` — these endpoints return
**HTTP 403** without one):

```bash
UA='Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36'
SHA=6d1538ba6fecc4e5c5583993c4b30bb1875f0f5a
BASE="https://downloads.claude.ai/vms/linux/x64/$SHA"

mkdir -p _preseed/vm_bundle _preseed/claude-code
for f in vmlinuz.zst initrd.zst rootfs.img.zst; do
  curl -sSL -A "$UA" -o "_preseed/vm_bundle/$f" "$BASE/$f"
done
```

For the CLI, either extract `preseed/claude-code/linux-x64.zst` from the Windows offline
MSIX (it is a ZIP), or pull it from `claude-code-releases`.

Verify everything before building:

```bash
sha256sum -c <<'EOF'
bc64e0dbc039c30ce986ad3edd2d0cb38d57d78450be72b3a5d4e747c54bf482  _preseed/vm_bundle/rootfs.img.zst
20214efcd451b3b74dc53ed80218c6e616bb2a101cafb18bc2c9bc91e559926b  _preseed/vm_bundle/initrd.zst
1bb4bc3aa0c0c797a2ca6134d2b7034a196e05d4deea7bb20f064ee353781f3b  _preseed/vm_bundle/vmlinuz.zst
c39722950b2cb1ceb2e1ffe4027fa89121150e3853b4f4f27a34e80a6e09cdbe  _preseed/claude-code/linux-x64.zst
EOF
```

### 2. Build

```bash
docker run --rm -v "$PWD:/work" debian:12 bash /work/scripts/build-offline-deb.sh
```

The script re-verifies every checksum and refuses to build on a mismatch, unpacks with
`dpkg-deb -R`, injects the preseed tree, updates `Version` and `Installed-Size`,
regenerates `DEBIAN/md5sums`, and rebuilds with `dpkg-deb -Zxz -z1` (level 1 because the
payload is already compressed — higher levels cost many minutes and save almost nothing).

Output: `_release/claude-desktop_1.30096.5+offline1_amd64.deb`.

Override with `ARCH`, `VERSION`, `SUFFIX` env vars for arm64 or other builds.

### 3. Install and confirm

```bash
sudo apt install ./claude-desktop_1.30096.5+offline1_amd64.deb
```

The proof is in the log — start a Cowork session and watch:

```bash
tail -f ~/.config/Claude-3p/logs/main.log | grep -i preseed
```

Success looks like:

```
[preseed] staging VM bundle cache rootfs.img.zst from package
[preseed] installing Claude CLI linux-x64 from package
```

If instead you see downloads starting, the preseed tree was not found or its version does
not match what the app expects.

The honest test is to **block `downloads.claude.ai` at the firewall and then start a
Cowork session**. Anything less is not evidence that it works offline.

---

## Risks — read before deploying

**This has not been runtime-tested by whoever wrote this document.** The checksums and
paths are verified against the shipping binary; the end-to-end behaviour on a real
air-gapped Debian box is not. Pilot it before you commit.

**You lose vendor provenance.** The rebuilt `.deb` is not the file Anthropic signed. Its
contents are individually checksum-verified against values compiled into the application,
which is a meaningful integrity property, but it is not a vendor signature. In a
regulated environment this is a governance decision, not a technical one — raise it with
whoever owns software provenance rather than quietly shipping it.

**It is pinned to one app version.** The VM bundle sha and CLI checksums come from
manifests compiled into a specific build. Every Claude Desktop update needs the preseed
tree rebuilt against that build's expectations. Set `disableAutoUpdates: true` so a
background update never desynchronises the app from its preseed data.

**It may stop working.** Nothing here is a public interface. Anthropic can change the
preseed layout, the manifest format, or add stricter verification in any release.

**Sign it if you distribute it internally.** Either sign the package with your
organisation's key, or serve it from an internal apt repo you control and sign the repo
metadata. Do not pass an unsigned rebuilt vendor package around by hand.

### The alternative worth weighing

Getting `downloads.claude.ai` allowlisted is one hostname, supported, and survives every
update with no work. For a Bedrock deployment you can leave `api.anthropic.com`,
`claude.ai`, and `platform.claude.com` blocked. **Try that route first.** Build this only
when the answer is a firm no.

---

## Updating for a new Claude Desktop version

1. Download the new `.deb`.
2. Extract `resources/app.asar` from it.
3. Find the new bundle sha — search the asar for `vmBundleManifest` and read
   `versions[0].sha`, plus the `unix/<arch>` file checksums.
4. Find the new CLI version and `linux-x64` checksum — search for
   `claude-code-releases`.
5. Download the new components, update the checksums at the top of
   `scripts/build-offline-deb.sh`, rebuild.

`scripts/inspect-deb-manifests.py` automates steps 2–4.
