#!/bin/bash
# Did the offline package actually work, or did it quietly fall back to downloading?
#
#   ./scripts/check-preseed-live.sh
#
# Run AFTER installing the offline .deb and starting one Cowork session.
# This is the only test that proves the offline build does its job - packaging
# and installation checks cannot tell you what happens at session start.
set -uo pipefail

LOG="${LOG:-$HOME/.config/Claude-3p/logs/main.log}"
PRESEED=/usr/lib/claude-desktop/resources/preseed

say() { printf '\n==> %s\n' "$*"; }
ok()  { printf '  \033[32m[ ok ]\033[0m %s\n' "$*"; }
bad() { printf '  \033[31m[FAIL]\033[0m %s\n' "$*"; }
warn(){ printf '  \033[33m[warn]\033[0m %s\n' "$*"; }

say "1. Is this the offline build?"
if [ -d "$PRESEED" ]; then
  ok "preseed tree present"
  find "$PRESEED" -type f -printf '     %-52p %10s\n'
else
  bad "$PRESEED missing - this is the STOCK package, not the offline one."
  echo "     It will fetch from downloads.claude.ai at session start."
  exit 1
fi

say "2. Installed package version"
dpkg -s claude-desktop 2>/dev/null | grep -E '^(Version|Status):' | sed 's/^/  /' \
  || warn "claude-desktop not installed via dpkg"

say "3. Log file"
if [ ! -f "$LOG" ]; then
  warn "No log at $LOG"
  echo "     Launch Claude and start one Cowork session first."
  echo "     If your log lives elsewhere: LOG=/path/to/main.log $0"
  exit 1
fi
ok "$LOG ($(wc -l < "$LOG") lines)"

say "4. Did preseed staging fire?"
HITS=$(grep -c '\[preseed\]' "$LOG" 2>/dev/null || echo 0)
if [ "$HITS" -gt 0 ]; then
  ok "$HITS preseed log lines - the package supplied the components"
  grep '\[preseed\]' "$LOG" | tail -10 | sed 's/^/     /'
else
  bad "No [preseed] lines found."
  echo "     Either no Cowork session has started yet, or the app did not use the"
  echo "     preseed tree (version mismatch between app and staged components)."
fi

say "5. Did it try to download instead?"
DL=$(grep -iEc 'downloads\.claude\.ai|\[Bundle:download\]|vm_bundle.*download' "$LOG" 2>/dev/null || echo 0)
if [ "$DL" -gt 0 ]; then
  warn "$DL lines reference downloading - inspect these:"
  grep -iE 'downloads\.claude\.ai|\[Bundle:download\]' "$LOG" | tail -10 | sed 's/^/     /'
  echo "     Some may be harmless (update checks). What matters is whether the VM"
  echo "     bundle itself was fetched."
else
  ok "no download attempts logged"
fi

say "6. Bundle readiness"
grep -iE '\[Bundle:status\]|bundle.*ready|VM.*start' "$LOG" 2>/dev/null | tail -8 | sed 's/^/     /' \
  || echo "     (no bundle status lines)"

say "7. Errors worth reading"
grep -iE 'error|failed|ENOENT|checksum|mismatch' "$LOG" 2>/dev/null | tail -12 | sed 's/^/     /' \
  || echo "     (none)"

say "VERDICT"
if [ "$HITS" -gt 0 ]; then
  echo "  Preseed fired. For proof it works with no egress, block downloads.claude.ai"
  echo "  at the firewall, clear the cache, and start a fresh session:"
  echo "     rm -rf ~/.config/Claude-3p/vm_bundles"
else
  echo "  Preseed did NOT fire. Check that the app version matches the components"
  echo "  in the preseed tree - see docs/11-BUILD-OFFLINE-DEB.md."
fi
echo
