#!/bin/bash
# Install the rebuilt offline .deb in a throwaway container and verify that the
# preseed tree lands intact on disk.
#
#   docker run --rm -v "<repo>:/work" debian:12 bash /work/scripts/test-offline-deb.sh
#
# This proves packaging and installation. It does NOT prove the app runs offline
# - that needs a desktop session with downloads.claude.ai firewalled off.
set -euo pipefail

DEB="${DEB:-/work/_release/claude-desktop_1.30096.5+offline1_amd64.deb}"
PRESEED=/usr/lib/claude-desktop/resources/preseed

say() { printf '\n==> %s\n' "$*"; }

say "Installing $(basename "$DEB")"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
# Let apt pull the real dependency set, exactly as it would on a target machine.
apt-get install -y -qq "$DEB" 2>&1 | tail -20

say "Package state"
dpkg -l claude-desktop | tail -2
dpkg -s claude-desktop | grep -E '^(Version|Installed-Size|Status):' | sed 's/^/  /'

say "Preseed tree on disk"
if [ ! -d "$PRESEED" ]; then
  echo "  FAIL: $PRESEED does not exist" >&2
  exit 1
fi
find "$PRESEED" -type f -printf '  %-58p %10s\n'

say "Checksums after installation"
fail=0
check() {
  got=$(sha256sum "$1" | cut -d' ' -f1)
  if [ "$got" = "$2" ]; then
    printf '  [ ok ] %s\n' "$(basename "$1")"
  else
    printf '  [FAIL] %s\n     expected %s\n     actual   %s\n' "$(basename "$1")" "$2" "$got"
    fail=1
  fi
}
check "$PRESEED/vm_bundle/vmlinuz.zst"     1bb4bc3aa0c0c797a2ca6134d2b7034a196e05d4deea7bb20f064ee353781f3b
check "$PRESEED/vm_bundle/initrd.zst"      20214efcd451b3b74dc53ed80218c6e616bb2a101cafb18bc2c9bc91e559926b
check "$PRESEED/vm_bundle/rootfs.img.zst"  bc64e0dbc039c30ce986ad3edd2d0cb38d57d78450be72b3a5d4e747c54bf482
check "$PRESEED/claude-code/linux-x64.zst" c39722950b2cb1ceb2e1ffe4027fa89121150e3853b4f4f27a34e80a6e09cdbe

say "dpkg integrity verification"
# dpkg --verify compares installed files against DEBIAN/md5sums.
if dpkg --verify claude-desktop; then
  echo "  no discrepancies"
else
  echo "  (output above lists files that differ from md5sums)"
fi

say "Binary present"
ls -l /usr/lib/claude-desktop/claude-desktop | sed 's/^/  /'
command -v claude-desktop | sed 's/^/  on PATH: /' || echo "  not on PATH"

if [ "$fail" -ne 0 ]; then
  say "RESULT: checksum failures above"
  exit 1
fi
say "RESULT: package installs and the preseed tree is intact"
