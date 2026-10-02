#!/bin/bash
# Build an OFFLINE Claude Desktop .deb by injecting the preseed tree that the
# Linux app already knows how to read but that Anthropic does not ship.
#
# Anthropic publishes offline installers for Windows and macOS only. The Linux
# build nonetheless carries the full preseed code path: at session start it looks
# in resources/preseed/ before downloading anything.
#
# This script is MANIFEST-DRIVEN. The expected checksums live in
#   manifests/<VERSION>.<ARCH>.preseed.sha256
# and the script injects exactly the files listed there, after verifying each one.
# To support a new Claude Desktop version, write a new manifest (see
# scripts/inspect-deb-manifests.py --emit) - this script does not change.
#
# Run inside a Debian container (see docs/11-BUILD-OFFLINE-DEB.md):
#   docker run --rm -v "<repo>:/work" -e VERSION=2.19675.0 debian:12 \
#       bash /work/scripts/build-offline-deb.sh
set -euo pipefail

VERSION="${VERSION:?set VERSION, e.g. VERSION=2.19675.0}"
ARCH="${ARCH:-amd64}"
SUFFIX="${SUFFIX:-+offline1}"
WORK="${WORK:-/work}"

MANIFEST="$WORK/manifests/${VERSION}.${ARCH}.preseed.sha256"
PRESEED="${PRESEED:-$WORK/_preseed/$VERSION}"
OUTDIR="$WORK/_release/v${VERSION}"
OUT_DEB="$OUTDIR/claude-desktop_${VERSION}${SUFFIX}_${ARCH}.deb"

# Locate the stock package this build starts from.
SRC_DEB=""
for c in "$WORK/_staging/v$VERSION/claude-desktop_${VERSION}_${ARCH}.deb" \
         "$WORK/linux/claude-desktop_${VERSION}_${ARCH}.deb"; do
  [ -f "$c" ] && { SRC_DEB="$c"; break; }
done

say() { printf '\n==> %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

[ -f "$MANIFEST" ] || die "No manifest: $MANIFEST"
[ -n "$SRC_DEB" ]  || die "Stock claude-desktop_${VERSION}_${ARCH}.deb not found in _staging/ or linux/"
[ -d "$PRESEED" ]  || die "Preseed directory missing: $PRESEED"

say "Installing build tools"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq xz-utils zstd file >/dev/null

say "Source package"
echo "  $(basename "$SRC_DEB")  (control Version: $(dpkg-deb -f "$SRC_DEB" Version))"
SRC_VER=$(dpkg-deb -f "$SRC_DEB" Version)
[ "$SRC_VER" = "$VERSION" ] || die "Package is $SRC_VER but VERSION=$VERSION - refusing to mix versions"

say "Verifying preseed inputs against $(basename "$MANIFEST")"
# Strip comments/blank lines; sha256sum -c fails the whole run on any mismatch,
# any missing file, and prints which one.
grep -vE '^\s*(#|$)' "$MANIFEST" > /tmp/preseed.sums
( cd "$PRESEED" && sha256sum -c /tmp/preseed.sums ) | sed 's/^/  /' \
  || die "Preseed verification failed. Do not build."
COUNT=$(wc -l < /tmp/preseed.sums)
echo "  $COUNT/$COUNT components verified"

BUILD=/build
rm -rf "$BUILD"; mkdir -p "$BUILD"

say "Unpacking $(basename "$SRC_DEB")"
dpkg-deb -R "$SRC_DEB" "$BUILD/pkg"
RES="$BUILD/pkg/usr/lib/claude-desktop/resources"
[ -d "$RES" ] || die "Unexpected layout: $RES not found"

say "Injecting preseed tree (exactly the files in the manifest)"
while read -r _sum rel; do
  install -D -m 644 "$PRESEED/$rel" "$RES/preseed/$rel"
done < /tmp/preseed.sums
find "$RES/preseed" -type d -exec chmod 755 {} +
chown -R root:root "$RES/preseed"
( cd "$RES/preseed" && find . -type f -printf '  %10s  %P\n' | sort -k2 )
du -sh "$RES/preseed" | sed 's/^/  total: /'

say "Updating control metadata"
CONTROL="$BUILD/pkg/DEBIAN/control"
sed -i "s/^Version: .*/Version: ${VERSION}${SUFFIX}/" "$CONTROL"
INSTALLED_KB=$(du -sk --exclude=DEBIAN "$BUILD/pkg" | cut -f1)
if grep -q '^Installed-Size:' "$CONTROL"; then
  sed -i "s/^Installed-Size: .*/Installed-Size: ${INSTALLED_KB}/" "$CONTROL"
else
  printf 'Installed-Size: %s\n' "$INSTALLED_KB" >> "$CONTROL"
fi
grep -E '^(Package|Version|Architecture|Installed-Size):' "$CONTROL" | sed 's/^/  /'

say "Regenerating md5sums"
( cd "$BUILD/pkg" && find . -type f ! -path './DEBIAN/*' -printf '%P\0' \
    | xargs -0 md5sum > DEBIAN/md5sums )
wc -l < "$BUILD/pkg/DEBIAN/md5sums" | sed 's/^/  entries: /'

say "Building package (xz -1; the preseed payload is already compressed)"
mkdir -p "$OUTDIR"
XZ_OPT="-T0" dpkg-deb -Zxz -z1 --build "$BUILD/pkg" "$OUT_DEB"

say "Result"
ls -l "$OUT_DEB" | awk '{printf "  %s  %.1f MB\n", $9, $5/1048576}'
sha256sum "$OUT_DEB" | sed 's/^/  /'
dpkg-deb -f "$OUT_DEB" Version Architecture Installed-Size | sed 's/^/  /'
echo "  --- preseed as packaged ---"
dpkg-deb -c "$OUT_DEB" | grep -E 'preseed/.+\.zst' | awk '{printf "  %12s  %s\n", $3, $6}'

rm -rf "$BUILD" /tmp/preseed.sums
say "Done: $OUT_DEB"
