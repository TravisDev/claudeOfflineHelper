# 06 — Linux install

Read the constraint section before you plan around Linux.

---

## The constraint: there is no Linux offline installer

Anthropic publishes the offline installer variant — the build with the VM workspace
bundle and Claude CLI baked in — for **Windows and macOS only**.

Verified two ways:

1. The offline-installation table in Anthropic's docs lists four rows: Windows x64,
   Windows Arm, macOS Apple silicon, macOS Intel. No Linux row.
2. Probing the release API directly:

```
https://claude.ai/api/desktop/linux/x64/offline/latest/redirect     -> HTTP 400
https://claude.ai/api/desktop/linux/arm64/offline/latest/redirect   -> HTTP 400
https://claude.ai/api/desktop/win32/x64/offline/latest/redirect     -> HTTP 307  (works)
https://claude.ai/api/desktop/linux/x64/deb/latest/redirect         -> HTTP 307  (standard build)
```

The Linux `.deb` in this repo is the **standard** build. It will install cleanly on an
isolated network and then fetch its VM bundle and CLI from `downloads.claude.ai` the
first time a Cowork session starts.

### But the offline code path is present anyway

Anthropic does not *ship* a Linux offline package. The Linux build nonetheless contains
the complete preseed machinery, in `resources/app.asar`:

```js
var x2t = `preseed`, S2t = `vm_bundle`, AU = `claude-code`;
function jU(){ return path.join(process.resourcesPath, x2t) }
D.info(`[preseed] staging VM bundle cache ${r}.zst from package`);
D.info(`[preseed] installing Claude CLI ${e.platform} from package`);
```

At session start the app checks `resources/preseed/` first and only downloads if the
files are absent. So an offline Linux package can be built by putting the right files
there — no patching, no binary modification.

This repo does that: [`scripts/build-offline-deb.sh`](../scripts/build-offline-deb.sh)
produces `claude-desktop_1.30096.5+offline1_amd64.deb` (1.6 GB), with every injected
component verified against checksums compiled into the application. Full method and
risks: [11 — Building an offline `.deb`](11-BUILD-OFFLINE-DEB.md).

### What this means for you

| Situation | Outcome |
|---|---|
| `downloads.claude.ai` allowlisted | Stock `.deb` works. Supported, survives updates for free. **Preferred.** |
| Host blocked, using the rebuilt offline `.deb` | No Anthropic egress. Unsupported; rebuild required on every version bump. |
| Host blocked, using the stock `.deb` | Installs and launches; **Cowork and Code sessions fail to start**. |

In order of practicality:

1. **Get `downloads.claude.ai` allowlisted.** One hostname, supported, zero maintenance.
   For a Bedrock deployment you can leave `api.anthropic.com`, `claude.ai`, and
   `platform.claude.com` blocked — inference and auth go to AWS. That is a far smaller
   request than "unblock Anthropic".
2. **Deploy on Windows** with the official offline MSIX, if Windows is an option at all.
   Supported, zero Anthropic egress.
3. **Build the offline `.deb`** from this repo. Works, but you own the update pipeline
   and you lose the vendor signature.
4. **Use the [Claude Code CLI](10-CLAUDE-CODE-CLI-BEDROCK.md)** — lighter network
   footprint, Bedrock-native, no VM bundle at all.

---

## Packages

| Arch | File | SHA256 |
|---|---|---|
| amd64 | `claude-desktop_1.30096.5_amd64.deb` | `e699763dd0e33bd831a1c771ea2684ead894f2680f02c71693a4e345046bd8f5` |
| arm64 | `claude-desktop_1.30096.5_arm64.deb` | `9de0fbb5300d80bbf91dc7e4a4d066bfd6bead3830a0d7ae6c8b0a8529cf59ea` |

Check your architecture:

```bash
dpkg --print-architecture
```

Requirements: Ubuntu 22.04+ or Debian 12+, x86_64 or arm64.

---

## Install

Unzip, verify, install:

```bash
unzip claude-desktop_1.30096.5_amd64.deb.zip
sha256sum -c <<'EOF'
e699763dd0e33bd831a1c771ea2684ead894f2680f02c71693a4e345046bd8f5  claude-desktop_1.30096.5_amd64.deb
EOF
```

Put the managed configuration in place **first**:

```bash
sudo mkdir -p /etc/claude-desktop
sudo cp config/managed-settings.json /etc/claude-desktop/managed-settings.json
sudo chmod 644 /etc/claude-desktop/managed-settings.json
```

Then:

```bash
chmod +x install.sh && ./install.sh
```

or directly:

```bash
sudo apt install ./claude-desktop_1.30096.5_amd64.deb
```

Launch from your app menu, or run `claude-desktop`.

---

## Suppressing the apt repo registration

The package's `postinst` registers Anthropic's apt repo. On a network that blocks it,
that turns every subsequent `apt update` into a warning. Suppress it before installing:

```bash
echo 'CLAUDE_DESKTOP_ADD_REPO="false"' | sudo tee /etc/default/claude-desktop
```

`install.sh` does this for you when run with `SKIP_REPO=1`:

```bash
SKIP_REPO=1 ./install.sh
```

If you skipped it and want to clean up afterward:

```bash
sudo rm -f /etc/apt/sources.list.d/claude*.list \
           /etc/apt/sources.list.d/anthropic*.list
sudo apt update
```

---

## Dependencies

The `.deb` declares real dependencies, resolved from **your distro's** archives, not
Anthropic's:

```
libgtk-3-0, libnotify4, libnss3, xdg-utils, libatspi2.0-0, libdrm2, libgbm1,
libxcb-dri3-0, libsecret-1-0, libc6 (>= 2.34), libxtst6, libuuid1,
xdg-desktop-portal, xdg-desktop-portal-gtk | xdg-desktop-portal-gnome | xdg-desktop-portal-kde
```

`Recommends` additionally pulls `qemu-system-x86`, `ovmf`, and `virtiofsd` — these back
the sandboxed Cowork VM. **They are Recommends, not Depends, so apt installs them by
default but the package will install without them.** A machine missing them installs
fine and then fails to start Cowork sessions, which looks like a network problem and is
not. Verify explicitly:

```bash
dpkg -l qemu-system-x86 ovmf virtiofsd
```

Blocking Anthropic does not affect dependency resolution. Blocking your distro archives
does — see [07 — Air-gapped Linux deps](07-AIRGAP-LINUX-DEPS.md).

---

## Verify the repo signing key

The bundled `claude-desktop-archive-keyring.asc` is Anthropic's apt repo signing key.

```bash
gpg --show-keys claude-desktop-archive-keyring.asc
```

Expected fingerprint:

```
31DD DE24 DDFA B679 F42D  7BD2 BAA9 29FF 1A7E CACE
```

You only need this if you intend to use the apt repo. For pure offline installation from
the `.deb`, it is informational.

---

## Where things live

| What | Path |
|---|---|
| Managed config | `/etc/claude-desktop/managed-settings.json` |
| Local config | `~/.config/Claude-3p/configLibrary/` |
| Repo suppression | `/etc/default/claude-desktop` |
| Binary | `claude-desktop` on PATH |

---

## Updating

The Linux app does not self-update from this bundle. Re-run
[`scripts/Fetch-Latest.ps1`](../scripts/Fetch-Latest.ps1) (or the plain `curl` in
[09 — Updating](09-UPDATING.md)) on a connected machine, re-upload, reinstall. Set
`disableAutoUpdates: true` so the app does not spend startup time on an update check it
cannot complete.
