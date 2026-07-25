#!/bin/sh
# One line per node: where its uplink is, who hangs off it, how many MLD groups
# the chip carries, and whether traffic gets out.

up=$(iw dev sta-mld-1 link 2>/dev/null | sed -n '1s/Connected to \([0-9a-f:]*\).*/\1/p')
[ -n "$up" ] || up=$(iw dev wlan2 link 2>/dev/null | sed -n '1s/Connected to \([0-9a-f:]*\).*/\1/p')

peers=0
mld=0
for i in $(iw dev 2>/dev/null | awk '/^\tInterface/ { print $2 }'); do
	if iw dev "$i" info 2>/dev/null | grep -q 'AP/VLAN'; then
		peers=$((peers + $(iw dev "$i" station dump 2>/dev/null | grep -c '^Station')))
	fi
	f="/sys/kernel/debug/ieee80211/phy0/netdev:$i/mt76_links_info"
	[ -e "$f" ] || continue
	[ "$(sed -n 's/^valid links = //p' "$f")" = "0x0" ] && continue
	mld=$((mld + 1))
done

cl=$(iw dev ap-mld-1 station dump 2>/dev/null | grep -c '^Station')
inet=$(ping -c2 -W2 1.1.1.1 >/dev/null 2>&1 && echo OK || echo FAIL)
br=$(ls /sys/class/net/br-lan/brif/ 2>/dev/null | grep -cx sta-mld-1)

printf '%-7s uplink=%-18s bh_peers=%-2s klienti=%-2s MLD=%-2s sta_v_br=%-2s inet=%s\n' \
	"$(cat /proc/sys/kernel/hostname)" "${up:--}" "$peers" "$cl" "$mld" "$br" "$inet"
