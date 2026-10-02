#!/bin/bash
# Exercise linux/install.sh end to end inside a throwaway Debian container, with BOTH the
# offline and stock packages present, so package selection, the checksum check and the
# post-install preseed verification are all driven for real.
#
#   docker run --rm -v "<repo>:/work" -e VERSION=2.19675.0 debian:12 \
#       bash /work/scripts/test-install-sh.sh
set -euo pipefail

VERSION="${VERSION:?set VERSION}"
WORK="${WORK:-/work}"
T=/tmp/inst
mkdir -p "$T/linux"

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq sudo >/dev/null

# Lay out like a cloned repo + unzipped release: linux/ next to manifests/.
cp "$WORK/linux/install.sh" "$T/linux/install.sh"
ln -s "$WORK/manifests" "$T/manifests"
ln -s "$WORK/_release/v${VERSION}/claude-desktop_${VERSION}+offline1_amd64.deb" "$T/linux/"
ln -s "$WORK/_staging/v${VERSION}/claude-desktop_${VERSION}_amd64.deb"          "$T/linux/"
chmod +x "$T/linux/install.sh"

echo "=== run install.sh (PKG=auto, both packages present) ==="
cd "$T/linux"
SKIP_REPO=1 ./install.sh 2>&1 | grep -vE '^(Get:|Fetched|Reading|Building|Selecting|Preparing|Unpacking|Setting up|Processing|Updating|Running|done|debconf|aspell|update-alternatives|[0-9]+ added)' | tail -45

echo
echo "=== state after install ==="
dpkg -s claude-desktop | grep -E '^(Version|Status):'
test -f /etc/default/claude-desktop && echo "repo registration suppressed: $(cat /etc/default/claude-desktop)"
