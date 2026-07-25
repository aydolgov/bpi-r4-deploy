#!/bin/sh
# Fleet census - one line per fact, so two runs diff cleanly.
# Run on any node; controller-only facts are skipped elsewhere.
H=$(cat /proc/sys/kernel/hostname)
u=$(cut -d. -f1 /proc/uptime)
echo "$H uptime_s $u"
echo "$H role_agent $(uci -q get mapagent.agent.enabled)"
echo "$H role_ctl $(uci -q get mapcontroller.controller.enabled)"
c=no; for f in /proc/[0-9]*/comm; do [ "$(cat "$f" 2>/dev/null)" = mapcontroller ] && c=yes && break; done
echo "$H ctl_proc $c"
echo "$H mapagent_ubus $(ubus list 2>/dev/null | grep -cx map.agent)"
# links per MLD: count how many times each mld iface appears with a channel
for i in $(iw dev 2>/dev/null | awk '/^\tInterface/{print $2}' | grep -- '-mld-'); do
	echo "$H mld_links_$i $(iw dev 2>/dev/null | awk -v w="$i" '/^\tInterface/{cur=$2} /channel/{if(cur==w) n++} END{print n+0}')"
done
# bSTA: managed ifaces and whether associated
for i in $(iw dev 2>/dev/null | awk '/^\tInterface/{print $2}'); do
	[ "$(iw dev "$i" info 2>/dev/null | awk '/type/{print $2}')" = managed ] || continue
	echo "$H bsta_$i $(iw dev "$i" link 2>/dev/null | head -1 | awk '{print $1}')"
done
echo "$H wifi_iface $(uci show wireless | grep -c '=wifi-iface')"
echo "$H macaddr_pins $(uci show wireless | grep -c macaddr)"
echo "$H country $(iw reg get 2>/dev/null | sed -n 's/^country \([A-Z]*\).*/\1/p' | head -1)"
echo "$H dhcp_ignore $(uci -q get dhcp.lan.ignore)"
echo "$H dhcp_listen67 $(netstat -uln 2>/dev/null | grep -c ':67 ')"
echo "$H inet $(ping -c2 -W2 1.1.1.1 >/dev/null 2>&1 && echo ok || echo FAIL)"
echo "$H retry_setup_failed $(logread 2>/dev/null | grep -c 'retry_setup_failed')"
echo "$H addba_token $(logread 2>/dev/null | grep -c 'wrong addBA response token')"
echo "$H freqset_eperm $(logread 2>/dev/null | grep -c 'Frequency set failed')"
# clients on AP-MLDs (AP-side census only, so a peer AP is not counted as a station)
n=0
for i in $(iw dev 2>/dev/null | awk '/^\tInterface/{print $2}'); do
	[ "$(iw dev "$i" info 2>/dev/null | awk '/type/{print $2}')" = AP ] || continue
	n=$((n + $(iw dev "$i" station dump 2>/dev/null | grep -c '^Station')))
done
echo "$H ap_stations $n"
if [ -f /etc/mapc/mapc.db ]; then
	echo "$H db_bytes $(wc -c < /etc/mapc/mapc.db | tr -d ' ')"
	echo "$H db_integrity $(sqlite3 /etc/mapc/mapc.db 'pragma integrity_check;' 2>/dev/null | head -1)"
	for t in agent radio bss apmld affiliated_ap ttlm topology_link sta; do
		echo "$H db_$t $(sqlite3 /etc/mapc/mapc.db "select count(*) from $t;" 2>/dev/null)"
	done
	echo "$H db_depths $(sqlite3 /etc/mapc/mapc.db 'select substr(almac,13)||"/d"||depth||"/a"||is_agent from agent order by almac;' 2>/dev/null | tr '\n' ' ')"
	echo "$H db_upstream $(sqlite3 /etc/mapc/mapc.db 'select substr(almac,13)||"->"||substr(upstream_bssid,13) from agent order by almac;' 2>/dev/null | tr '\n' ' ')"
	echo "$H db_bsta_rows $(sqlite3 /etc/mapc/mapc.db 'select count(*) from sta where is_bsta=1;' 2>/dev/null)"
fi
