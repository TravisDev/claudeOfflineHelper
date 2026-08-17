# Linux

**Read this before planning a Linux rollout.**

Anthropic publishes no Linux offline installer — the offline variant exists for Windows
and macOS only. The stock `.deb` here therefore fetches its VM workspace bundle and
Claude CLI from `downloads.claude.ai` at session start.

**However, the Linux build contains the full offline code path anyway**, so this repo
builds an offline package by injecting those components into `resources/preseed/`.

| Package | Needs `downloads.claude.ai`? | Supported? |
|---|---|---|
| `claude-desktop_1.30096.5_amd64.deb` (stock) | Yes, at session start | Yes |
| `claude-desktop_1.30096.5+offline1_amd64.deb` (built here) | No | **No** — modified vendor package |

Prefer allowlisting the one hostname if you possibly can; it is supported and needs no
maintenance. Build the offline package only when that answer is a firm no, and read the
risks first: [../docs/11-BUILD-OFFLINE-DEB.md](../docs/11-BUILD-OFFLINE-DEB.md)

Full detail: [../docs/06-LINUX-INSTALL.md](../docs/06-LINUX-INSTALL.md)

---

## Files here

| File | Purpose |
|---|---|
| `install.sh` | Verifies checksum, suppresses the apt repo, installs, checks KVM and VM packages |
| `claude-desktop-archive-keyring.asc` | Anthropic apt repo signing key |
| `config/managed-settings.json` | Bedrock configuration, all four auth methods shown |
| `config/managed-settings-lockeddown.json` | Restrictive profile |

The `.deb` files are release assets, not in git.

---

## Packages

| Arch | File | SHA256 |
|---|---|---|
| amd64 | `claude-desktop_1.30096.5_amd64.deb` | `e699763dd0e33bd831a1c771ea2684ead894f2680f02c71693a4e345046bd8f5` |
| arm64 | `claude-desktop_1.30096.5_arm64.deb` | `9de0fbb5300d80bbf91dc7e4a4d066bfd6bead3830a0d7ae6c8b0a8529cf59ea` |

```bash
dpkg --print-architecture   # which one you need
```

Ubuntu 22.04+ or Debian 12+.

---

## Install

```bash
unzip claude-desktop_1.30096.5_amd64.deb.zip

# configuration first
sudo mkdir -p /etc/claude-desktop
sudo cp config/managed-settings.json /etc/claude-desktop/managed-settings.json
sudo chmod 644 /etc/claude-desktop/managed-settings.json

# then the app; SKIP_REPO=1 stops it registering Anthropic's apt repo
SKIP_REPO=1 ./install.sh
```

Edit `managed-settings.json` for your region and credentials first. Unlike Windows and
macOS, this file uses **native JSON types** — real booleans and arrays, not quoted
strings.

---

## Dependencies

apt resolves this package's dependencies from **your distro's** archives, not Anthropic's.
Blocking Anthropic does not affect that; blocking your distro mirrors does — see
[../docs/07-AIRGAP-LINUX-DEPS.md](../docs/07-AIRGAP-LINUX-DEPS.md).

The catch worth knowing: `qemu-system-x86`, `ovmf`, and `virtiofsd` back the sandbox VM
but are **Recommends, not Depends**. The package installs cleanly without them and then
fails at session start, which looks like a network problem and is not.

```bash
dpkg -l qemu-system-x86 ovmf virtiofsd | grep '^ii'
ls -l /dev/kvm
```

`install.sh` checks both and warns you.
