#!/usr/bin/env bash
# Verify Claude Desktop offline artifacts against their known SHA256 hashes.
#
#   ./scripts/verify-checksums.sh [directory]
#
# Checks whatever is present and skips the rest. Exits non-zero if anything
# present fails, so it is safe to use as a gate in a deployment script.
set -uo pipefail

DIR="${1:-.}"
cd "$DIR" || { echo "No such directory: $DIR" >&2; exit 1; }

# sha256  filename
MANIFEST="
c2ae7281a3d10e74abfdd430359da813ada90fd5b9eefb0db2212e574ac0895a  Claude-1.30096.5-x64-offline.msix
e699763dd0e33bd831a1c771ea2684ead894f2680f02c71693a4e345046bd8f5  claude-desktop_1.30096.5_amd64.deb
9de0fbb5300d80bbf91dc7e4a4d066bfd6bead3830a0d7ae6c8b0a8529cf59ea  claude-desktop_1.30096.5_arm64.deb
230935a518402b1a35b7783ed224d4a53dc436046b319f1aa11667b8ff16c066  Claude-1.30096.5-x64-offline.msix.zip
1c4b9ba49063fa8c3c5558003d7bf40ca9e2d93c95c3e5fdfca4a68fed6ed2b0  claude-desktop_1.30096.5_amd64.deb.zip
eacba1ad5ebc011847e5da04fa861bae1639d0348b6d10d9cdb3ab13d4a8d1e0  claude-desktop_1.30096.5_arm64.deb.zip
"

command -v sha256sum >/dev/null 2>&1 || { echo "sha256sum not found" >&2; exit 1; }

pass=0; fail=0; skip=0

printf '\n  Verifying artifacts in %s\n\n' "$(pwd)"

while read -r want file; do
  [ -z "${file:-}" ] && continue
  if [ ! -f "$file" ]; then
    printf '  \033[90m[skip]\033[0m %s\n' "$file"
    skip=$((skip + 1))
    continue
  fi
  got=$(sha256sum "$file" | awk '{print $1}')
  if [ "$got" = "$want" ]; then
    printf '  \033[32m[ ok ]\033[0m %s\n' "$file"
    pass=$((pass + 1))
  else
    printf '  \033[31m[FAIL]\033[0m %s\n' "$file"
    printf '         expected %s\n' "$want"
    printf '         actual   %s\n' "$got"
    fail=$((fail + 1))
  fi
done <<< "$MANIFEST"

printf '\n  %d verified, %d failed, %d not present\n\n' "$pass" "$fail" "$skip"

if [ "$fail" -gt 0 ]; then
  echo "  Do not install anything that failed. Re-download it." >&2
  exit 1
fi
if [ "$pass" -eq 0 ]; then
  echo "  Nothing to verify - are you in the right directory?" >&2
  exit 1
fi
exit 0
