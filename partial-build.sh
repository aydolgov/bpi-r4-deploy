#!/bin/bash
# partial-build.sh <package> [universal|x8]
#
# The ONLY sanctioned way to partial-build a package. Born 2026-08-05:
# a mapagent built in a leftover tree against a feed frozen on July 15
# took the mesh down for half a day. This script refuses to build unless
# the shared feed is at the pin common-easymesh.sh says, and it prints
# the binary md5 so the deploy can be verified end to end.
set -e

PKG="${1:?usage: partial-build.sh <package> [universal|x8]}"
TREE="${2:-universal}"
case "$TREE" in
	universal) BD="$HOME/universal-new/openwrt" ;;
	x8)        BD="$HOME/x8-new/openwrt" ;;
	*) echo "tree must be: universal | x8"; exit 1 ;;
esac

SHARED="$(cd "$(dirname "$0")" && pwd)"
FEED="$SHARED/iopsys-feed"

PIN=$(grep -oE 'git reset --hard [0-9a-f]+' "$SHARED/common-easymesh.sh" | awk '{print $4}' | head -1)
[ -n "$PIN" ] || { echo "FAIL: no pin found in common-easymesh.sh"; exit 1; }

FULL=$(git -C "$FEED" rev-parse HEAD)
case "$FULL" in
	"$PIN"*) echo "OK: feed HEAD $FULL matches pin $PIN" ;;
	*) echo "FAIL: feed HEAD $FULL does not match pin $PIN"; echo "      (git -C $FEED reset --hard $PIN)"; exit 1 ;;
esac

grep -qs "src-link iopsys $FEED" "$BD/feeds.conf.default" "$BD/feeds.conf" || {
	echo "FAIL: $BD does not src-link $FEED - wrong tree?"; exit 1; }

cd "$BD"
make "package/$PKG/clean" >/dev/null 2>&1 || true
make "package/$PKG/compile" -j"$(nproc)"

echo "=== binaries (verify this md5 on the node after deploy) ==="
find build_dir -path "*ipkg-*" -type f -perm -111 2>/dev/null \
	| grep -E "/${PKG}[^/]*/.*(usr/s?bin|lib)/" | while read -r B; do md5sum "$B"; done
