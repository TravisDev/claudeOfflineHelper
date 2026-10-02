#!/usr/bin/env bash
# Installer for Claude Desktop on Debian/Ubuntu, from the packages in this repo's release.
#
#   chmod +x install.sh && ./install.sh
#
# Environment:
#   PKG=auto|offline|stock   which package to install (default auto: the offline build
#                            if it is present, otherwise the stock one)
#   SKIP_REPO=1              suppress Anthropic apt repo registration (recommended offline)
#   SKIP_SUMS=1              skip checksum verification (use for a locally rebuilt package)
#
# See ../docs/06-LINUX-INSTALL.md and ../docs/11-BUILD-OFFLINE-DEB.md
set -euo pipefail
cd "$(dirname "$0")"

VERSION="2.19675.0"

# Checksums of the published files. The offline package's hash is valid for the
# released file only: dpkg-deb output is not byte-reproducible, so a package you rebuild
# yourself will differ (use SKIP_SUMS=1 and let the preseed check below vouch for it).
SHA_STOCK_AMD64="da476cf5b4f77f209cca4ab3558b94622b1c9dc6808bf1d9022352b9a1da8f9b"
SHA_STOCK_ARM64="55171972a988324fe6bcb6405506ff4deb42524d7e3cfefd88a6f85ce4660d5f"
SHA_OFFLINE_AMD64="5fe9ad09dfec9066eccc9458616396ae042e597e982360fc02483d696fe26a54"

say()  { printf '  %s\n' "$*"; }
ok()   { printf '  \033[32m[ ok ]\033[0m %s\n' "$*"; }
warn() { printf '  \033[33m[warn]\033[0m %s\n' "$*"; }
die()  { printf '  \033[31m[FAIL]\033[0m %s\n' "$*" >&2; exit 1; }

echo
echo "  Claude Desktop ${VERSION} - install"
echo "  =================================="
echo

# --- locate the package ----------------------------------------------------
ARCH=$(dpkg --print-architecture)
STOCK_DEB="claude-desktop_${VERSION}_${ARCH}.deb"
OFFLINE_DEB="claude-desktop_${VERSION}+offline1_${ARCH}.deb"

DEB=""; KIND=""
case "${PKG:-auto}" in
  offline) [ -f "$OFFLINE_DEB" ] && { DEB="$OFFLINE_DEB"; KIND=offline; } ;;
  stock)   [ -f "$STOCK_DEB" ]   && { DEB="$STOCK_DEB";   KIND=stock; } ;;
  auto)
    if   [ -f "$OFFLINE_DEB" ]; then DEB="$OFFLINE_DEB"; KIND=offline
    elif [ -f "$STOCK_DEB" ];   then DEB="$STOCK_DEB";   KIND=stock
    fi ;;
  *) die "PKG must be auto, offline or stock" ;;
esac

if [ -z "$DEB" ]; then
  die "No ${PKG:-auto} claude-desktop package for ${ARCH} found next to this script.
       Looked for: $OFFLINE_DEB / $STOCK_DEB
       Unzip the release asset first, e.g.:  unzip ${STOCK_DEB}.zip"
fi

say "Host architecture : $ARCH"
say "Package           : $DEB  ($KIND build)"
if [ -f "$OFFLINE_DEB" ] && [ -f "$STOCK_DEB" ] && [ "${PKG:-auto}" = auto ]; then
  say "(both builds present; installing the offline one - PKG=stock to override)"
fi
echo

# --- checksum --------------------------------------------------------------
if [ "${SKIP_SUMS:-0}" = "1" ]; then
  warn "Checksum verification skipped (SKIP_SUMS=1)."
else
  case "$DEB" in
    "claude-desktop_${VERSION}+offline1_amd64.deb") WANT="$SHA_OFFLINE_AMD64" ;;
    "claude-desktop_${VERSION}_amd64.deb")          WANT="$SHA_STOCK_AMD64" ;;
    "claude-desktop_${VERSION}_arm64.deb")          WANT="$SHA_STOCK_ARM64" ;;
    *)                                               WANT="" ;;
  esac

  if [ -n "$WANT" ]; then
    GOT=$(sha256sum "$DEB" | awk '{print $1}')
    if [ "$GOT" != "$WANT" ]; then
      echo "    expected : $WANT" >&2
      echo "    actual   : $GOT"  >&2
      die "Checksum mismatch. Do not install this file. Re-download it.
       (If you rebuilt the package yourself this is expected: use SKIP_SUMS=1.)"
    fi
    ok "Checksum matches."
  else
    warn "No published checksum for $DEB. Skipping."
  fi
fi

# --- repo signing key ------------------------------------------------------
if command -v gpg >/dev/null 2>&1 && [ -f claude-desktop-archive-keyring.asc ]; then
  say "Bundled apt repo signing key:"
  gpg --show-keys claude-desktop-archive-keyring.asc 2>/dev/null | sed 's/^/    /' || true
  say "Expected fingerprint: 31DD DE24 DDFA B679 F42D  7BD2 BAA9 29FF 1A7E CACE"
  echo
fi

# --- suppress the apt repo -------------------------------------------------
# The postinst registers Anthropic's apt repo. On a network that blocks it, that
# turns every later `apt update` into a warning.
if [ "${SKIP_REPO:-0}" = "1" ]; then
  echo 'CLAUDE_DESKTOP_ADD_REPO="false"' | sudo tee /etc/default/claude-desktop >/dev/null
  ok "Anthropic apt repo registration disabled."
else
  warn "The package will register Anthropic's apt repo."
  warn "On a blocked network, re-run with SKIP_REPO=1 to suppress it."
fi

# --- managed configuration -------------------------------------------------
if [ -f /etc/claude-desktop/managed-settings.json ]; then
  if command -v python3 >/dev/null 2>&1; then
    if python3 -c 'import json,sys; json.load(open("/etc/claude-desktop/managed-settings.json"))' 2>/dev/null; then
      PROV=$(python3 -c 'import json; print(json.load(open("/etc/claude-desktop/managed-settings.json")).get("inferenceProvider","<unset>"))')
      ok "Managed config present: inferenceProvider = $PROV"
    else
      warn "/etc/claude-desktop/managed-settings.json is not valid JSON. The app will ignore it."
    fi
  else
    ok "Managed config present."
  fi
else
  warn "No /etc/claude-desktop/managed-settings.json."
  warn "The app will show the claude.ai sign-in screen. Install config/managed-settings.json first."
fi

# --- install ---------------------------------------------------------------
echo
say "Installing (sudo required)..."
sudo apt install -y "./$DEB"

# --- post-install checks ---------------------------------------------------
echo
case "$ARCH" in
  arm64) VMPKGS="qemu-system-arm qemu-efi-aarch64" ;;
  *)     VMPKGS="qemu-system-x86 ovmf" ;;
esac
MISSING=""
for p in $VMPKGS; do
  dpkg -l "$p" 2>/dev/null | grep -q '^ii' || MISSING="$MISSING $p"
done
if [ -n "$MISSING" ]; then
  warn "Missing VM support packages:$MISSING"
  warn "These are Recommends, not Depends - the app installs without them and then"
  warn "fails to start Cowork sessions. Install them:  sudo apt install$MISSING"
else
  ok "VM support packages present ($VMPKGS)."
fi

# virtiofsd is handled separately: the .deb ships its own copy, and Debian 12 has no
# virtiofsd package at all (so "apt install virtiofsd" would fail there).
BUNDLED_VIRTIOFSD=/usr/lib/claude-desktop/resources/virtiofsd
if dpkg -l virtiofsd 2>/dev/null | grep -q '^ii'; then
  ok "virtiofsd installed as a system package."
elif [ -x "$BUNDLED_VIRTIOFSD" ]; then
  ok "virtiofsd: using the copy bundled with the package ($BUNDLED_VIRTIOFSD)."
else
  warn "No virtiofsd found (neither system package nor bundled copy). If Cowork sessions"
  warn "fail to start, install it where available:  sudo apt install virtiofsd"
fi

if [ -e /dev/kvm ]; then
  if [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
    ok "/dev/kvm accessible."
  else
    warn "/dev/kvm exists but is not accessible to $USER."
    warn "  sudo usermod -aG kvm \"$USER\"   then log out and back in"
  fi
else
  warn "/dev/kvm missing - hardware virtualization is off, or nested virt is"
  warn "disabled on the hypervisor. Cowork sessions cannot start without it."
fi

PRESEED=/usr/lib/claude-desktop/resources/preseed
MANIFEST="../manifests/${VERSION}.${ARCH}.preseed.sha256"
if [ "$KIND" = offline ]; then
  echo
  if [ -f "$MANIFEST" ]; then
    if ( cd "$PRESEED" && grep -vE '^[[:space:]]*(#|$)' "$OLDPWD/$MANIFEST" | sha256sum -c --quiet - ); then
      ok "Preseed tree verified against $(basename "$MANIFEST")."
    else
      warn "Preseed tree does NOT match the manifest. Do not rely on this install offline."
    fi
  else
    warn "Manifest $MANIFEST not found; could not verify the preseed tree."
    warn "  (clone the repo, or run: cd $PRESEED && sha256sum vm_bundle/*.zst claude-code/*.zst)"
  fi
fi

echo
ok "Installed. Launch 'Claude' from your app menu, or run: claude-desktop"
echo
if [ "$KIND" = offline ]; then
  say "This is the offline build: the VM bundle and Claude CLI ship inside the package,"
  say "so sessions should not need downloads.claude.ai. Confirm it - start one Cowork"
  say "session, then run:  ../scripts/check-preseed-live.sh"
  say "It is an unsupported, rebuilt package. See ../docs/11-BUILD-OFFLINE-DEB.md"
else
  say "Reminder: this is the STOCK build. The app fetches its VM bundle and CLI from"
  say "downloads.claude.ai at session start. If that host is blocked, Cowork and Code"
  say "sessions will not start. The offline build avoids this; see ../docs/06-LINUX-INSTALL.md"
fi
echo
