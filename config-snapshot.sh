#!/bin/sh
# Snapshot and compare node CONFIG, because the image is not the state.
#
# A keep-config sysupgrade replaces files and keeps /etc/config. So reflashing a
# known-good build does NOT undo an experiment - every uci change made by hand
# survives, and the good build then runs on top of experimental config and can
# misbehave in ways the build itself never had. Measured today: dhcp.lan.ignore
# had to be set by hand before flashing the controller or a uci-default would have
# silenced its DHCP; a stale macaddr pin survived every flash and kept lying about
# an address; ap_mld_2 and bsta_mld_1 would survive a reflash of any image.
#
# And the uci-defaults cannot fix this, by design: they are written "only if
# unset" so they never stomp a deliberate decision - which is exactly what makes
# them unable to restore anything.
#
# So config needs its own baseline, taken at the moment a state is proven, and a
# diff so "did something survive that should not have" is a check instead of a hope.
#
#   config-snapshot.sh save <label>       pull /etc/config from every node
#   config-snapshot.sh diff <a> <b>       compare two labels
#   config-snapshot.sh check <label>      compare nodes AS THEY ARE NOW against a label
#   config-snapshot.sh list
#
# Snapshots live outside the session scratchpad on purpose - that directory is
# temporary, and the round-4 images only survived today because a copy happened to
# be there when the builder overwrote them.

ARCHIVE="$HOME/Desktop/CLAUDE-ARCHIV/config-snapshots"
NODES="4g:192.168.1.1 8g:192.168.1.3 x8:192.168.1.2"

ssh_node() {
	perl -e 'alarm 40; exec @ARGV' ssh -o StrictHostKeyChecking=no \
		-o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 "root@$1" "$2" 2>/dev/null
}

# One normalised uci dump per node. Sorted so a diff shows real changes rather
# than uci's ordering, and volatile bits dropped so the diff is not all noise.
pull() {
	ssh_node "$1" 'for p in wireless network dhcp firewall mapagent mapcontroller ieee1905; do
		uci -q show "$p" 2>/dev/null
	done' | LC_ALL=C sort
}

case "${1:-}" in
save)
	label="${2:?usage: config-snapshot.sh save <label>}"
	dir="$ARCHIVE/$label"
	mkdir -p "$dir"
	for n in $NODES; do
		nm=${n%%:*}; ip=${n##*:}
		out="$dir/$nm.uci"
		pull "$ip" > "$out"
		lines=$(wc -l < "$out" | tr -d ' ')
		if [ "$lines" -lt 20 ]; then
			echo "  $nm: JEN $lines radku - uzel nedosazitelny? snimek NEPOUZITELNY" >&2
		else
			echo "  $nm: $lines radku"
		fi
	done
	date '+%Y-%m-%d %H:%M:%S' > "$dir/.taken"
	echo "  ulozeno: $dir"
	;;

diff)
	a="${2:?}"; b="${3:?usage: config-snapshot.sh diff <a> <b>}"
	for n in $NODES; do
		nm=${n%%:*}
		fa="$ARCHIVE/$a/$nm.uci"; fb="$ARCHIVE/$b/$nm.uci"
		[ -r "$fa" ] && [ -r "$fb" ] || { echo "=== $nm: chybi snimek ==="; continue; }
		echo "=== $nm: $a -> $b ==="
		diff "$fa" "$fb" | grep -E '^[<>]' | sed 's/^</  ubylo: /;s/^>/  pribylo: /' || echo "  beze zmeny"
	done
	;;

check)
	label="${2:?usage: config-snapshot.sh check <label>}"
	tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
	bad=0
	for n in $NODES; do
		nm=${n%%:*}; ip=${n##*:}
		ref="$ARCHIVE/$label/$nm.uci"
		[ -r "$ref" ] || { echo "=== $nm: v $label neni ==="; continue; }
		pull "$ip" > "$tmp/$nm.uci"
		if cmp -s "$ref" "$tmp/$nm.uci"; then
			echo "=== $nm: SHODNE s $label ==="
		else
			echo "=== $nm: LISI SE od $label ==="
			diff "$ref" "$tmp/$nm.uci" | grep -E '^[<>]' | sed 's/^</  chybi: /;s/^>/  navic: /'
			bad=$((bad + 1))
		fi
	done
	[ "$bad" -eq 0 ] && echo ">>> VSE SEDI <<<" || echo ">>> $bad UZLU SE LISI <<<"
	exit "$bad"
	;;

list)
	ls -1 "$ARCHIVE" 2>/dev/null | while read -r l; do
		printf '  %-28s %s\n' "$l" "$(cat "$ARCHIVE/$l/.taken" 2>/dev/null)"
	done
	;;
*)
	echo "usage: config-snapshot.sh save|diff|check|list" >&2
	exit 2
	;;
esac
