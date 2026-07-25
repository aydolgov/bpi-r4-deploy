#!/bin/sh
# Compare the shared mesh layer in a BUILT image against a running node.
#
# This is the axis that was missing on 2026-07-24/25 and the reason a silent
# regression survived a whole day: verify-identical.sh and verify-shared.sh
# compare tree to tree. Both printed ">>> IDENTICAL <<<" while the tree had
# drifted away from the image the nodes were actually running - mld-link-check
# was overwritten in place three hours after the classics were flashed, so
# tree==tree was true and tree==reality was false. Nothing compared a build
# against a node, so nothing could notice.
#
# Two modes, because the lab is split: VM1 has the build trees but cannot reach
# 192.168.1.x, and the Mac reaches the nodes but has no build tree. One file so
# the list of checked paths lives in exactly one place.
#
#   on the node (or over ssh from wherever it is reachable):
#       verify-vs-node.sh --emit > node-md5.txt
#
#   on the build host:
#       verify-vs-node.sh /home/ipsec/universal-new/openwrt node-md5.txt
#
# Reads the node's /rom - the read-only squashfs, i.e. what the image shipped -
# NOT /, because / is the overlay and a hand edit there would look like a build.

# The shared mesh layer, as image paths. Keep in step with
# easymesh_install_mld_scripts in common-easymesh.sh: if that function starts
# shipping a file and it is not added here, this check silently stops covering it.
FILES="
usr/sbin/mld-link-check
usr/sbin/mld-config-check
usr/sbin/mld-report-check
usr/sbin/bssid-pin
usr/sbin/mesh-env
etc/init.d/mld-link-check
etc/init.d/mld-config-check
etc/init.d/mld-report-check
etc/uci-defaults/97-mapc-db-keep
etc/mesh-node-names
www/cgi-bin/mesh-status
root/mlo-steerd.sh
root/node-config.sh
etc/init.d/mlo-steerd
etc/init.d/wifimgr-defaults
"

# Paths that must NOT be in the image. An absence check belongs in the same pass:
# bssid-pin as a *service* re-enables itself, because OpenWrt enables every init
# script carrying START= while building the rootfs. Measured 2026-07-25 - leaving
# the rc.d symlink out of files/ does not disable it, the image build recreates it.
ABSENT="
etc/init.d/bssid-pin
etc/rc.d/S95bssid-pin
"

if [ "${1:-}" = "--emit" ]; then
	for f in $FILES $ABSENT; do
		if [ -e "/rom/$f" ]; then
			echo "$f $(md5sum "/rom/$f" | cut -d' ' -f1)"
		else
			echo "$f MISSING"
		fi
	done
	exit 0
fi

TREE="${1:-}"
LIST="${2:-}"
if [ -z "$TREE" ] || [ -z "$LIST" ]; then
	echo "usage: $0 <openwrt-tree> <node-md5-file>   |   $0 --emit" >&2
	exit 2
fi
[ -r "$LIST" ] || { echo "FAIL: cannot read $LIST" >&2; exit 2; }

ROOTFS=$(ls -d "$TREE"/build_dir/target-*/root-mediatek 2>/dev/null | head -1)
[ -n "$ROOTFS" ] || { echo "FAIL: no built rootfs under $TREE/build_dir/target-*/root-mediatek" >&2; exit 2; }

node_md5() {
	awk -v f="$1" '$1 == f { print $2; found=1; exit } END { if (!found) print "ABSENT-FROM-LIST" }' "$LIST"
}

echo "rootfs: $ROOTFS"
echo "list:   $LIST"
echo
bad=0
printf '%-38s %-10s %-10s %s\n' "file" "image" "node" ""
for f in $FILES; do
	if [ -e "$ROOTFS/$f" ]; then
		img=$(md5sum "$ROOTFS/$f" | cut -d' ' -f1)
	else
		img="MISSING"
	fi
	nod=$(node_md5 "$f")
	if [ "$img" = "$nod" ] && [ "$img" != "MISSING" ]; then
		printf '%-38s %-10s %-10s ok\n' "$f" "$(echo "$img" | cut -c1-8)" "$(echo "$nod" | cut -c1-8)"
	else
		printf '%-38s %-10s %-10s DIFFERS\n' "$f" "$(echo "$img" | cut -c1-8)" "$(echo "$nod" | cut -c1-8)"
		bad=$((bad + 1))
	fi
done

echo
echo "must be absent:"
for f in $ABSENT; do
	if [ -e "$ROOTFS/$f" ]; then img=yes; else img=no; fi
	if [ "$(node_md5 "$f")" = "MISSING" ]; then nod=no; else nod=yes; fi
	if [ "$img" = no ] && [ "$nod" = no ]; then
		printf '  %-36s image=no  node=no   ok\n' "$f"
	else
		printf '  %-36s image=%-3s node=%-3s PRESENT\n' "$f" "$img" "$nod"
		bad=$((bad + 1))
	fi
done

echo
if [ "$bad" -eq 0 ]; then
	echo ">>> IMAGE MATCHES NODE <<<"
	exit 0
fi
echo ">>> $bad MISMATCH(ES) - build and running node disagree <<<"
echo "    Either the node carries a hand edit that was never baked, or the tree"
echo "    changed after the node was flashed. Both happened on 2026-07-24 and cost"
echo "    a day. Establish which one before trusting either side."
exit 1
