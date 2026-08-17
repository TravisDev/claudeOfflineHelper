#!/usr/bin/env bash
# Offline installer for Claude Desktop on Debian/Ubuntu.
#
#   chmod +x install.sh && ./install.sh
#
# Environment:
#   SKIP_REPO=1   suppress Anthropic apt repo registration (recommended offline)
#   SKIP_SUMS=1   skip checksum verification
#
# See ../docs/06-LINUX-INSTALL.md
set -euo pipefail
cd "$(dirname "$0")"

VERSION="1.30096.5"
SHA_AMD64="e699763dd0e33bd831a1c771ea2684ead894f2680f02c71693a4e345046bd8f5"
SHA_ARM64="9de0fbb5300d80bbf91dc7e4a4d066bfd6bead3830a0d7ae6c8b0a8529cf59ea"

say()  { printf '  %s\n' "$*"; }
ok()   { printf '  \033[32m[ ok ]\033[0m %s\n' "$*"; }
warn() { printf '  \033[33m[warn]\033[0m %s\n' "$*"; }
die()  { printf '  \033[31m[FAIL]\033[0m %s\n' "$*" >&2; exit 1; }

echo
echo "  Claude Desktop ${VERSION} - offline install"
echo "  =========================================="
echo

# --- locate the package ----------------------------------------------------
ARCH=$(dpkg --print-architecture)
DEB=$(ls "claude-desktop_${VERSION}_${ARCH}.deb" 2>/dev/null | head -n1 || true)
[ -z "${DEB:-}" ] && DEB=$(ls claude-desktop_*_"${ARCH}".deb 2>/dev/null | head -n1 || true)
[ -z "${DEB:-}" ] && DEB=$(ls claude-desktop_*.deb 2>/dev/null | head -n1 || true)

if [ -z "${DEB:-}" ]; then
  die "No claude-desktop .deb found next to this script.
       Unzip the release asset first:  unzip claude-desktop_${VERSION}_${ARCH}.deb.zip"
fi

say "Host architecture : $ARCH"
say "Package           : $DEB"
echo

# --- checksum --------------------------------------------------------------
if [ "${SKIP_SUMS:-0}" = "1" ]; then
  warn "Checksum verification skipped (SKIP_SUMS=1)."
else
  case "$DEB" in
    *_amd64.deb) WANT="$SHA_AMD64" ;;
    *_arm64.deb) WANT="$SHA_ARM64" ;;
    *)           WANT="" ;;
  esac

  if [ -n "$WANT" ]; then
    GOT=$(sha256sum "$DEB" | awk '{print $1}')
    if [ "$GOT" != "$WANT" ]; then
      echo "    expected : $WANT" >&2
      echo "    actual   : $GOT"  >&2
      die "Checksum mismatch. Do not install this file. Re-download it."
    fi
    ok "Checksum matches."
  else
    warn "No known checksum for $DEB (different version?). Skipping."
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
MISSING=""
for p in qemu-system-x86 ovmf virtiofsd; do
  dpkg -l "$p" 2>/dev/null | grep -q '^ii' || MISSING="$MISSING $p"
done
if [ -n "$MISSING" ]; then
  warn "Missing VM support packages:$MISSING"
  warn "These are Recommends, not Depends - the app installs without them and then"
  warn "fails to start Cowork sessions. Install them:  sudo apt install$MISSING"
else
  ok "VM support packages present."
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

echo
ok "Installed. Launch 'Claude' from your app menu, or run: claude-desktop"
echo
say "Reminder: Linux has no offline installer. The app fetches its VM bundle and"
say "CLI from downloads.claude.ai at session start. If that host is blocked,"
say "Cowork and Code sessions will not start. See ../docs/06-LINUX-INSTALL.md"
echo
