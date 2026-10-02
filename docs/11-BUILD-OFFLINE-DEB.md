# 11 — Building an offline Debian package

Anthropic ships an offline installer for Windows and macOS but not for Linux. This
document explains how to build one yourself, why it works, and what you are taking on by
doing it.

> **This is unsupported.** You are modifying a vendor package. Anthropic did not publish
> this configuration and will not support it. Read [Risks](#risks--read-before-deploying)
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
`claude-desktop_1.30096.5_amd64.deb` (identifier names are minifier output and change
between builds; the logic did not change in 2.19675.0):

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

Three sets of files have to line up exactly with the app build. All of it is compiled
into the application, so it is different for every version.

### VM bundle

The app resolves its bundle from an embedded manifest, taking the newest entry:

```js
var xV = { sha: $Zt.sha, files: $Zt.files };                       // $Zt = manifest.versions[0]
function tq(){ return process.arch === `x64` ? `x64` : `arm64` }
function sen(){ return `https://downloads.claude.ai/vms/linux/${tq()}/${xV.sha}` }
```

| App | Bundle sha | Published |
|---|---|---|
| 1.30096.5 | `6d1538ba6fecc4e5c5583993c4b30bb1875f0f5a` | 2026-06-10 |
| **2.19675.0** | `882518393ed4ce89020bd48d99d5daf114999773` | 2026-09-11 |

Linux uses `rootfs.img`; Windows uses `rootfs.vhdx`. Files are served and staged
zstd-compressed. For **2.19675.0 on Linux x64**:

| File | SHA256 of the `.zst` | Size |
|---|---|---|
| `rootfs.img.zst` | `1c3e856d002d52df2246446ce0e3ae21fb65fdd81451f29a8e908305697a52c0` | 1,290,205,884 |
| `vmlinuz.zst` | `3118616ef6ba3866652284b8b4c224a96876c56091724c35c93caf1ccb9b50a9` | 14,758,684 |
| `initrd.zst` | `c12df253f5ddac9f7f7cdf317c7257586d262eabd9336c1ce001301399fbe56a` | 28,022,397 |
| `initrd-micro.zst` | `e8a5fa87ae465403ae5e8261e64c952527eb411828759d421086e14f05858531` | 1,739,088 |

**`initrd-micro` is new in 2.x** - 1.30096.5 needed only the first three. A package that
omits it would have looked complete and then fallen back to downloading it.

`vmlinuz` and `initrd` are byte-identical to the copies inside the Windows offline MSIX
(verified), so those two can be taken from either place.

> **The checksums are over the compressed `.zst` artifacts, not the decompressed
> contents.** Decompressing first and hashing that gives a mismatch and will send you
> chasing a problem that does not exist.

### Claude CLI

App 2.19675.0 expects CLI **2.1.286** (1.30096.5 expected 2.1.229), from an embedded
manifest with `baseUrl: https://downloads.claude.ai/claude-code-releases`:

| Platform | SHA256 | Size |
|---|---|---|
| `linux-x64` | `a14d80443473126e40cbc50eb78899f43e8f4d4336095863f8089a6b9ca02a97` | 84,909,116 |
| `linux-arm64` | `fb24324439bcca9575083f06af6a351a7f9f25066fcf370372b5e829287ef1ee` | 84,176,167 |

Convenient shortcut: the **Windows offline MSIX already contains
`preseed/claude-code/linux-x64.zst`**, byte-identical to the above, because the Cowork
guest is Linux regardless of host. If you have the Windows offline package you can lift
the Linux CLI straight out of it. (It is a ZIP; any ZIP tool works.)

### claude-ssh (optional)

A new component in the 2.x official offline installers, used by the remote-SSH feature.
Cowork does not need it; it is included for parity with what Anthropic ships on Windows.

| Platform | SHA256 | Size |
|---|---|---|
| `linux-amd64` | `fadfb069d2b8e3e304541c6b2ec0c0b87c71e081a8a3d6dfa4a511ba9217eb11` | 2,740,309 |
| `linux-arm64` | `ea0b8663e8aa93a2ca3e27187102d92b8c3df6b0fa5de13ace8f93e93330643a` | 2,444,580 |

The 1.30096.5 official offline installer did not ship it, so that build's manifest omits
it. `inspect-deb-manifests.py --with-ssh` includes it.

## Target layout

```
/usr/lib/claude-desktop/resources/preseed/
├── vm_bundle/
│   ├── rootfs.img.zst
│   ├── vmlinuz.zst
│   ├── initrd.zst
│   └── initrd-micro.zst
├── claude-code/
│   └── linux-x64.zst
└── claude-ssh/
    └── linux-amd64.zst
```

Compare with the Windows offline MSIX, which uses the same structure:

```
app/resources/preseed/vm_bundle/rootfs.vhdx.zst
app/resources/preseed/vm_bundle/{initrd,vmlinuz}.zst
app/resources/preseed/claude-code/{win32-x64,linux-x64,linux-arm64}.zst
app/resources/preseed/claude-ssh/{linux-amd64,linux-arm64}.zst
```

---

## Build it

The build is **manifest-driven**. The expected checksums live in
`manifests/<version>.<arch>.preseed.sha256`, and `build-offline-deb.sh` injects exactly
the files listed there after verifying each one. Supporting a new version means writing a
new manifest, not editing the script. Manifests exist for 1.30096.5 and 2.19675.0 (amd64).

### 1. Fetch the components

On a machine with internet (note the browser `User-Agent` - these endpoints return
**HTTP 403** without one):

```bash
UA='Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36'
SHA=882518393ed4ce89020bd48d99d5daf114999773
BASE="https://downloads.claude.ai/vms/linux/x64/$SHA"

mkdir -p _preseed/2.19675.0/{vm_bundle,claude-code,claude-ssh}
for f in vmlinuz initrd initrd-micro rootfs.img; do
  curl -sSL -A "$UA" -o "_preseed/2.19675.0/vm_bundle/$f.zst" "$BASE/$f.zst"
done
```

Then lift `claude-code/linux-x64.zst` and `claude-ssh/linux-amd64.zst` out of the Windows
offline MSIX into the same tree. Verify everything before building:

```bash
cd _preseed/2.19675.0
grep -vE '^[[:space:]]*(#|$)' ../../manifests/2.19675.0.amd64.preseed.sha256 | sha256sum -c -
```

### 2. Build

You also need the stock package, at `_staging/v2.19675.0/claude-desktop_2.19675.0_amd64.deb`
(or in `linux/`).

```bash
docker run --rm -v "$PWD:/work" -e VERSION=2.19675.0 debian:12 \
    bash /work/scripts/build-offline-deb.sh
```

The script refuses to build if any checksum fails, if the manifest is missing, or if the
stock package's version is not the `VERSION` you asked for. It unpacks with
`dpkg-deb -R`, injects the tree, updates `Version` and `Installed-Size`, regenerates
`DEBIAN/md5sums`, and rebuilds with `dpkg-deb -Zxz -z1` (level 1 because the payload is
already compressed - higher levels cost many minutes and save almost nothing).

Output: `_release/v2.19675.0/claude-desktop_2.19675.0+offline1_amd64.deb` (about 1.5 GB).
Override `ARCH` and `SUFFIX` for other builds.

### 3. Test the package

```bash
docker run --rm -v "$PWD:/work" -e VERSION=2.19675.0 debian:12 \
    bash /work/scripts/test-offline-deb.sh
```

This installs the package in a clean Debian 12 container with real dependency resolution,
re-verifies every injected file against the same manifest, fails if the tree contains
anything the manifest does not list, and runs `dpkg --verify`. It proves the package is
**well-formed and installs**. It does not prove the app runs offline.

> Do not move or rename files under `_release/` while it runs. The package is read
> through a bind mount; moving it mid-install makes apt fail with a misleading
> `cannot stat pathname` error.

### 4. Install and confirm on a real machine

```bash
sudo apt install ./claude-desktop_2.19675.0+offline1_amd64.deb
```

The proof is in the log - start a Cowork session and watch:

```bash
tail -f ~/.config/Claude-3p/logs/main.log | grep -i preseed
```

or run `scripts/check-preseed-live.sh`. Success looks like:

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

This has been tested once against a real change: going from 1.30096.5 to 2.19675.0 (a
major version) the staging logic kept the same shape - `preseed/vm_bundle/<name>.zst` and
`preseed/claude-code/<platform>.zst`, verified over compressed bytes - and the differences
were additions (a fourth VM file, a new CLI version, a new `claude-ssh` component). That
is encouraging, not a guarantee. One thing to watch: 2.19675.0's embedded Claude CLI
manifest carries a field that 1.30096.5's did not, `"manifestSignatureEnforcement":"flag"`.
What it controls has not been established here. Fields like that tend to precede stricter
verification, so look at it first if a future build stops honouring the preseed tree.

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

The whole procedure is written up, with the commands, in
[09 - Updating](09-UPDATING.md#update-procedure). In short:

1. Download the new stock `.deb` by its versioned URL.
2. `python3 scripts/inspect-deb-manifests.py <deb>` to read what that build expects.
3. `... --emit amd64 --with-ssh > manifests/<ver>.amd64.preseed.sha256`.
4. Fetch the components it lists, verify them with `sha256sum -c`.
5. Run `build-offline-deb.sh`, then `test-offline-deb.sh`.

Do not assume the previous version's layout still applies. Step 2 is the point: the app
states its own requirements, and they changed between 1.30096.5 and 2.19675.0.
