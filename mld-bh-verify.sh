#!/bin/sh
# Verify one step of the MLO backhaul experiment. Pass/fail criteria are fixed
# here, before the test, so the result cannot be argued into success afterwards.
#
#   mld-bh-verify.sh ap    on the serving node, after --apply-ap  + reboot
#   mld-bh-verify.sh sta   on the leaf node,    after --apply-sta + reboot
#
# The driver's mt76_links_info is the authority throughout. uci says what was
# asked for; only the driver says what happened - and the failure mode that
# matters here (two AP-MLDs silently merging into one group) is invisible in uci
# and in iw, and shows up only as an identical "group mld id".

ROLE="${1:?usage: mld-bh-verify.sh ap|sta}"
AP_IF=ap-mld-2
STA_IF="${STA_IF:-bsta-mld-3}"  # bsta- prefix je povinny: libwifi get_wifi_driver()
                                 # paruje token pres strstr(ifname, token)
FH_IF=ap-mld-1
fail=0

li() { echo "/sys/kernel/debug/ieee80211/phy0/netdev:$1/mt76_links_info"; }
field() { sed -n "s/^$2 = //p" "$(li "$1")" 2>/dev/null | head -1; }

check() {  # check <popis> <ocekavano> <namereno>
	if [ "$2" = "$3" ]; then
		printf '  OK    %-34s %s\n' "$1" "$3"
	else
		printf '  CHYBA %-34s ceka se %s, je %s\n' "$1" "$2" "$3"
		fail=$((fail + 1))
	fi
}

echo "=== $(cat /proc/sys/kernel/hostname)  t$(cut -d. -f1 /proc/uptime)s  role=$ROLE ==="

case "$ROLE" in
ap)
	[ -e "$(li $AP_IF)" ] || { echo "  CHYBA $AP_IF neexistuje - AP-MLD nenaskocilo"; exit 1; }

	# 0x3 = links 0 and 1 of THIS mld (its own numbering), i.e. both radios joined.
	check "$AP_IF valid links"      "0x3" "$(field $AP_IF 'valid links')"
	# The whole point: a second MLD must be its own group. Same group as the
	# fronthaul means they merged and this only looks like it worked.
	fh_group=$(field $FH_IF 'group mld id')
	bh_group=$(field $AP_IF 'group mld id')
	if [ -n "$bh_group" ] && [ "$bh_group" != "$fh_group" ]; then
		printf '  OK    %-34s backhaul=%s fronthaul=%s\n' "group mld id se lisi" "$bh_group" "$fh_group"
	else
		printf '  CHYBA %-34s obe %s - MLD se slily\n' "group mld id" "$bh_group"
		fail=$((fail + 1))
	fi
	check "$FH_IF valid links (nedotceny)" "0x7" "$(field $FH_IF 'valid links')"

	echo "  -- linky $AP_IF --"
	grep -E 'link\[|band_idx' "$(li $AP_IF)" 2>/dev/null | sed 's/^/    /'

	# The legacy per-radio backhaul BSSes must survive, or an agent still running a
	# single-link bSTA loses its uplink and the experiment costs the mesh.
	n=$(iw dev 2>/dev/null | awk '/^\tInterface/ { i = $2 } /ssid MAP--BH$/ { print i }' | wc -l)
	if [ "$n" -ge 1 ]; then
		printf '  OK    %-34s %s BSS\n' "legacy MAP--BH zije" "$n"
	else
		printf '  CHYBA %-34s zadna - agent na jednolince prijde o uplink\n' "legacy MAP--BH"
		fail=$((fail + 1))
	fi

	echo "  -- hostapd --"
	for l in 0 1; do
		printf '    %s_link%s: state=%s freq=%s\n' "$AP_IF" "$l" \
			"$(hostapd_cli -i ${AP_IF}_link$l status 2>/dev/null | sed -n 's/^state=//p')" \
			"$(hostapd_cli -i ${AP_IF}_link$l status 2>/dev/null | sed -n 's/^freq=//p')"
	done
	echo "  -- pripojene MLD STA (az po kroku 3) --"
	hostapd_cli -i "$AP_IF" all_sta 2>/dev/null \
		| grep -E '^[0-9a-f][0-9a-f]:|max_simul_links|emlsr_support' | sed 's/^/    /'
	;;

sta)
	[ -e "$(li $STA_IF)" ] || { echo "  CHYBA $STA_IF neexistuje - MLD STA nenaskocila"; exit 1; }
	check "$STA_IF valid links" "0x3" "$(field $STA_IF 'valid links')"

	l=$(iw dev "$STA_IF" link 2>/dev/null | head -1)
	case "$l" in
	Connected*) printf '  OK    %-34s %s\n' "asociace" "$l" ;;
	*)          printf '  CHYBA %-34s %s\n' "asociace" "${l:-nic}"; fail=$((fail + 1)) ;;
	esac

	# The 938 criterion. Before that patch wl_mldsta_status() answered
	# UBUS_STATUS_UNKNOWN_ERROR for this exact object, so map-agent never learned
	# the uplink was up: no bstamld_parse, no wifi_mod_bridge(add), endless
	# bsta_scan. Association and per-link traffic looked healthy meanwhile, which
	# is why this must be checked explicitly and never inferred from iw.
	if ubus list 2>/dev/null | grep -qx "wifi.bstamld.$STA_IF"; then
		printf '  OK    %-34s\n' "ubus objekt wifi.bstamld.$STA_IF"
	else
		printf '  CHYBA %-34s neexistuje\n' "ubus objekt wifi.bstamld.$STA_IF"
		fail=$((fail + 1))
	fi
	if ubus call "wifi.bstamld.$STA_IF" status >/dev/null 2>&1; then
		printf '  OK    %-34s odpovida\n' "wifi.bstamld status"
	else
		printf '  CHYBA %-34s %s\n' "wifi.bstamld status" \
			"$(ubus call "wifi.bstamld.$STA_IF" status 2>&1 | head -1)"
		fail=$((fail + 1))
	fi

	# Two links up is not the same as two links carrying signal. One non-zero
	# signal means it associated but is running single-link after all - which is
	# exactly the outcome that would otherwise be reported as success.
	d=$(iw dev "$STA_IF" station dump 2>/dev/null)
	blocks=$(echo "$d" | grep -c '^	Link [0-9]*:')
	live=$(echo "$d" | awk '/^\t\tsignal:/ { if ($2 + 0 != 0) n++ } END { print n + 0 }')
	check "bloku Link N:" "2" "$blocks"
	check "linek s nenulovym signalem" "2" "$live"
	echo "  -- per-link --"
	echo "$d" | awk '
		/^\tLink [0-9]+:/ { l = $2; sub(":", "", l) }
		/^\t\tsignal:/     { printf "    link%s signal=%s\n", l, $2 }
		/^\t\trx bitrate:/ { printf "    link%s rx=%s %s %s\n", l, $3, $4, $5 }'

	echo "  -- per-radio bSTA musi byt dole --"
	for s in $(uci -q show wireless | sed -n "s/^wireless\.\(default_sta_radio[0-9]*\)\.mode='sta'$/\1/p"); do
		printf '    %-22s disabled=%s\n' "$s" "$(uci -q get "wireless.$s.disabled")"
	done

	# Connectivity counts toward the verdict. On 2026-07-25 both pings failed
	# while the four link criteria passed, and this script still printed
	# ">>> KROK PROSEL <<<" - the association was real but the interface was not a
	# bridge port, so nothing flowed. A verdict that ignores whether traffic passes
	# is worse than no verdict.
	echo "  -- dosah do meshe --"
	for t in 10.10.10.1 1.1.1.1; do
		if ping -c2 -W2 "$t" >/dev/null 2>&1; then
			printf '  OK    %-34s %s\n' "ping $t" "ok"
		else
			printf '  CHYBA %-34s neprochazi\n' "ping $t"
			fail=$((fail + 1))
		fi
	done
	if ls /sys/class/net/br-lan/brif/ 2>/dev/null | grep -qx "$STA_IF"; then
		printf '  OK    %-34s\n' "$STA_IF je port br-lan"
	else
		printf '  CHYBA %-34s neni v mostu - nic nepotece\n' "$STA_IF"
		fail=$((fail + 1))
	fi
	;;
*)
	echo "usage: mld-bh-verify.sh ap|sta" >&2
	exit 2
	;;
esac

echo
[ "$fail" -eq 0 ] && echo ">>> KROK PROSEL <<<" || echo ">>> $fail KRITERII NESPLNENO - revert: mlo-backhaul-setup --revert && reboot <<<"
exit "$fail"
