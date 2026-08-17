# 07 — Staging Linux dependencies for an air-gapped machine

Only relevant if the target machine cannot reach **its own distro's** archives
(`archive.ubuntu.com`, `deb.debian.org`, or an internal mirror). Blocking Anthropic does
not affect apt; blocking all outbound package traffic does.

Check first — this is often a non-problem:

```bash
sudo apt update && echo "archives reachable, skip this document"
```

---

## What has to be staged

**Depends** (install fails without these):

```
libgtk-3-0 libnotify4 libnss3 xdg-utils libatspi2.0-0 libdrm2 libgbm1
libxcb-dri3-0 libsecret-1-0 libc6 libxtst6 libuuid1 xdg-desktop-portal
xdg-desktop-portal-gtk | xdg-desktop-portal-gnome | xdg-desktop-portal-kde
```

**Recommends** (install succeeds, Cowork then fails):

```
qemu-system-x86 ovmf virtiofsd
```

Do not skip the Recommends. They back the sandbox VM, and their absence produces a
working-looking app whose agent sessions fail — a failure that reads like a network
problem and wastes hours.

---

## Method 1: download the dependency closure on a connected machine

On a machine running **the same distro release and architecture** as the target:

```bash
mkdir -p ~/claude-deps && cd ~/claude-deps

sudo apt update
sudo apt install --download-only --reinstall -y \
  libgtk-3-0 libnotify4 libnss3 xdg-utils libatspi2.0-0 libdrm2 libgbm1 \
  libxcb-dri3-0 libsecret-1-0 libxtst6 libuuid1 \
  xdg-desktop-portal xdg-desktop-portal-gtk \
  qemu-system-x86 ovmf virtiofsd

cp /var/cache/apt/archives/*.deb .
```

That grabs the named packages but **not their transitive dependencies** if those are
already installed on the connected machine. For a genuine full closure, resolve it
against the target's actual package state.

Best approach: get `dpkg --get-selections` from the target, replicate that state in a
container matching the target release, and download there:

```bash
# on the target
dpkg --get-selections > target-selections.txt

# on the connected machine, in a matching container
docker run --rm -it -v "$PWD:/out" ubuntu:22.04 bash -c '
  apt update
  # replicate target state so apt resolves the true delta
  apt install -y --download-only \
    libgtk-3-0 libnotify4 libnss3 xdg-utils libatspi2.0-0 libdrm2 libgbm1 \
    libxcb-dri3-0 libsecret-1-0 libxtst6 libuuid1 \
    xdg-desktop-portal xdg-desktop-portal-gtk \
    qemu-system-x86 ovmf virtiofsd
  cp /var/cache/apt/archives/*.deb /out/
'
```

Match the container image to the target release exactly. Packages built for Ubuntu 24.04
will not satisfy dependencies on 22.04.

Bundle it up:

```bash
tar czf claude-deps-$(lsb_release -cs)-$(dpkg --print-architecture).tar.gz *.deb
```

Then on the target:

```bash
tar xzf claude-deps-*.tar.gz
sudo dpkg -i *.deb || sudo apt install -f --no-download
sudo apt install ./claude-desktop_1.30096.5_amd64.deb
```

The `dpkg -i` then `apt install -f` sequence handles ordering — `dpkg` does not resolve
order itself, so the first pass leaves some packages unconfigured and the second pass
settles them.

---

## Method 2: a local apt repository (better for more than one machine)

Turn the staged `.deb` files into a real repo so apt resolves dependencies properly:

```bash
sudo apt install dpkg-dev
mkdir -p /srv/claude-repo && cd /srv/claude-repo
cp ~/claude-deps/*.deb .
cp claude-desktop_1.30096.5_amd64.deb .
dpkg-scanpackages . /dev/null | gzip -9c > Packages.gz
```

Point apt at it on the target:

```bash
echo "deb [trusted=yes] file:/srv/claude-repo ./" | \
  sudo tee /etc/apt/sources.list.d/claude-local.list
sudo apt update
sudo apt install claude-desktop
```

`[trusted=yes]` skips signature verification — acceptable for a local directory you
control and populated yourself, not acceptable for anything reached over a network.

To serve it to several machines, put the directory behind any static HTTP server and use
`deb [trusted=yes] http://<host>/claude-repo ./` instead. Sign the repo properly if it
crosses a network you do not fully control.

---

## Verify before declaring victory

```bash
# no unmet dependencies
sudo apt-get check

# the VM backing packages are actually present
dpkg -l qemu-system-x86 ovmf virtiofsd | grep '^ii'

# hardware virtualization is available
grep -Eoc '(vmx|svm)' /proc/cpuinfo   # >0 on x86
ls -l /dev/kvm                         # must exist and be accessible
```

If `/dev/kvm` is missing, Cowork cannot start regardless of packages. On a VM, that means
nested virtualization is off at the hypervisor. On bare metal, it is disabled in
firmware.

Check that your user can actually use it:

```bash
ls -l /dev/kvm            # typically root:kvm
groups | grep -q kvm && echo "in kvm group" || echo "NOT in kvm group"
sudo usermod -aG kvm "$USER"   # then log out and back in
```

---

## Remember the other half

Staging apt dependencies solves the *install*. It does not solve the *session start* —
on Linux the app still needs `downloads.claude.ai` for the VM workspace bundle and CLI,
because there is no Linux offline installer. See
[06 — Linux install](06-LINUX-INSTALL.md#the-constraint-there-is-no-linux-offline-installer).

A fully air-gapped Linux deployment with working Cowork is not achievable today. A fully
air-gapped **Windows** deployment is.
