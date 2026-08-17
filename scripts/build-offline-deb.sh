#!/bin/bash
# Build an OFFLINE Claude Desktop .deb by injecting the preseed tree that the
# Linux app already knows how to read but that Anthropic does not ship.
#
# Anthropic publishes an offline installer variant for Windows and macOS only.
# The Linux build nonetheless contains the full preseed code path:
#
#   var x2t=`preseed`, S2t=`vm_bundle`, AU=`claude-code`;
#   function jU(){ return path.join(process.resourcesPath, x2t) }
#   D.info(`[preseed] staging VM bundle cache ${r}.zst from package`);
#   D.info(`[preseed] installing Claude CLI ${e.platform} from package`);
#
# So dropping the right files at resources/preseed/ makes the Linux app stage
# them locally instead of downloading from downloads.claude.ai.
#
# Run inside a Debian container (see docs/11-BUILD-OFFLINE-DEB.md):
#   docker run --rm -v "<repo>:/work" debian:12 bash /work/scripts/build-offline-deb.sh
set -euo pipefail

ARCH="${ARCH:-amd64}"
VERSION="${VERSION:-1.30096.5}"
SUFFIX="${SUFFIX:-+offline1}"
WORK="${WORK:-/work}"

SRC_DEB="$WORK/linux/claude-desktop_${VERSION}_${ARCH}.deb"
PRESEED="$WORK/_preseed"
OUTDIR="$WORK/_release"
OUT_DEB="$OUTDIR/claude-desktop_${VERSION}${SUFFIX}_${ARCH}.deb"

# Checksums compiled into app 1.30096.5. These are over the COMPRESSED .zst
# artifacts, not the decompressed files.
SHA_VMLINUZ="1bb4bc3aa0c0c797a2ca6134d2b7034a196e05d4deea7bb20f064ee353781f3b"
SHA_INITRD="20214efcd451b3b74dc53ed80218c6e616bb2a101cafb18bc2c9bc91e559926b"
SHA_ROOTFS="bc64e0dbc039c30ce986ad3edd2d0cb38d57d78450be72b3a5d4e747c54bf482"
SHA_CLI="c39722950b2cb1ceb2e1ffe4027fa89121150e3853b4f4f27a34e80a6e09cdbe"

say() { printf '\n==> %s\n' "$*"; }

say "Installing build tools"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq xz-utils zstd file >/dev/null

[ -f "$SRC_DEB" ] || { echo "Missing source package: $SRC_DEB" >&2; exit 1; }

say "Verifying preseed inputs"
verify() {
  local f="$1" want="$2"
  [ -f "$f" ] || { echo "MISSING: $f" >&2; exit 1; }
  local got
  got=$(sha256sum "$f" | cut -d' ' -f1)
  if [ "$got" != "$want" ]; then
    echo "CHECKSUM MISMATCH: $f" >&2
    echo "  expected $want" >&2
    echo "  actual   $got" >&2
    exit 1
  fi
  printf '  ok  %-18s %s\n' "$(basename "$f")" "${want:0:16}..."
}
verify "$PRESEED/vm_bundle/vmlinuz.zst"      "$SHA_VMLINUZ"
verify "$PRESEED/vm_bundle/initrd.zst"       "$SHA_INITRD"
verify "$PRESEED/vm_bundle/rootfs.img.zst"   "$SHA_ROOTFS"
verify "$PRESEED/claude-code/linux-x64.zst"  "$SHA_CLI"

BUILD=/build
rm -rf "$BUILD"; mkdir -p "$BUILD"

say "Unpacking $(basename "$SRC_DEB")"
dpkg-deb -R "$SRC_DEB" "$BUILD/pkg"

RES="$BUILD/pkg/usr/lib/claude-desktop/resources"
[ -d "$RES" ] || { echo "Unexpected layout: $RES not found" >&2; exit 1; }

say "Injecting preseed tree"
mkdir -p "$RES/preseed/vm_bundle" "$RES/preseed/claude-code"
cp "$PRESEED/vm_bundle/vmlinuz.zst"     "$RES/preseed/vm_bundle/"
cp "$PRESEED/vm_bundle/initrd.zst"      "$RES/preseed/vm_bundle/"
cp "$PRESEED/vm_bundle/rootfs.img.zst"  "$RES/preseed/vm_bundle/"
cp "$PRESEED/claude-code/linux-x64.zst" "$RES/preseed/claude-code/"
chmod 644 "$RES/preseed/vm_bundle/"*.zst "$RES/preseed/claude-code/"*.zst
find "$RES/preseed" -type d -exec chmod 755 {} +
chown -R root:root "$RES/preseed"
du -sh "$RES/preseed"

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
ls -lh "$OUT_DEB" | awk '{print "  " $9 "  " $5}'
sha256sum "$OUT_DEB" | sed 's/^/  /'

say "Verifying the built package"
dpkg-deb -I "$OUT_DEB" | sed 's/^/  /'
echo "  --- preseed contents as packaged ---"
dpkg-deb -c "$OUT_DEB" | grep preseed | awk '{printf "  %-12s %s\n", $3, $6}'

rm -rf "$BUILD"
say "Done: $OUT_DEB"
