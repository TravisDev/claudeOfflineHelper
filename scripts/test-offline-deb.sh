#!/bin/bash
# Install the rebuilt offline .deb in a throwaway container and verify that the
# preseed tree lands intact - checked against the SAME manifest the build used.
#
#   docker run --rm -v "<repo>:/work" -e VERSION=2.19675.0 debian:12 \
#       bash /work/scripts/test-offline-deb.sh
#
# This proves packaging and installation. It does NOT prove the app runs offline:
# that needs a desktop session with downloads.claude.ai firewalled off. See
# scripts/check-preseed-live.sh for that half.
set -euo pipefail

VERSION="${VERSION:?set VERSION, e.g. VERSION=2.19675.0}"
ARCH="${ARCH:-amd64}"
SUFFIX="${SUFFIX:-+offline1}"
WORK="${WORK:-/work}"
DEB="${DEB:-$WORK/_release/v${VERSION}/claude-desktop_${VERSION}${SUFFIX}_${ARCH}.deb}"
MANIFEST="$WORK/manifests/${VERSION}.${ARCH}.preseed.sha256"
PRESEED=/usr/lib/claude-desktop/resources/preseed

say() { printf '\n==> %s\n' "$*"; }

[ -f "$DEB" ]      || { echo "FAIL: missing $DEB" >&2; exit 1; }
[ -f "$MANIFEST" ] || { echo "FAIL: missing $MANIFEST" >&2; exit 1; }

say "Installing $(basename "$DEB")"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
# Let apt pull the real dependency set, exactly as it would on a target machine.
apt-get install -y -qq "$DEB" 2>&1 | tail -5

say "Package state"
dpkg -l claude-desktop | tail -1
dpkg -s claude-desktop | grep -E '^(Version|Installed-Size|Status):' | sed 's/^/  /'

say "Preseed tree on disk"
[ -d "$PRESEED" ] || { echo "  FAIL: $PRESEED does not exist" >&2; exit 1; }
( cd "$PRESEED" && find . -type f -printf '  %10s  %P\n' | sort -k2 )

say "Checksums after installation (against $(basename "$MANIFEST"))"
grep -vE '^\s*(#|$)' "$MANIFEST" > /tmp/want.sums
fail=0
( cd "$PRESEED" && sha256sum -c /tmp/want.sums ) | sed 's/^/  /' || fail=1

say "No unexpected files in the preseed tree"
want=$(awk '{print $2}' /tmp/want.sums | sort)
have=$(cd "$PRESEED" && find . -type f -printf '%P\n' | sort)
if [ "$want" = "$have" ]; then
  echo "  exactly the $(echo "$want" | wc -l) manifest files, nothing extra"
else
  echo "  MISMATCH between manifest and installed tree:"
  diff <(echo "$want") <(echo "$have") | sed 's/^/    /'
  fail=1
fi

say "dpkg integrity verification"
if dpkg --verify claude-desktop; then
  echo "  no discrepancies"
else
  echo "  (files above differ from DEBIAN/md5sums)"; fail=1
fi

say "Binary present"
ls -l /usr/lib/claude-desktop/claude-desktop | sed 's/^/  /'
command -v claude-desktop | sed 's/^/  on PATH: /' || echo "  not on PATH"

if [ "$fail" -ne 0 ]; then
  say "RESULT: FAILED - see above"
  exit 1
fi
say "RESULT: package installs and the preseed tree is intact"
