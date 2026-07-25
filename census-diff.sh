#!/bin/sh
# Diff two fleet censuses produced by census.sh.
#
# Facts EXPECTED to move across a reboot (uptime, client counts, log counters
# that only grow, db file size) are reported apart from facts that must not move,
# so a real regression cannot hide in the noise.
#
# Census lines are "host key value..." where the value may contain spaces
# (db_depths lists one entry per agent). Everything from field 3 on is the value,
# so key and value are joined on TAB - splitting on whitespace truncated
# multi-word values to their first word and made three correct agent rows look
# like one missing fact.

B="$1"; A="$2"
[ -r "$B" ] && [ -r "$A" ] || { echo "usage: $0 before.txt after.txt" >&2; exit 2; }
T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT
TAB=$(printf '\t')

VOLATILE='uptime_s|ap_stations|db_bytes|addba_token|freqset_eperm|retry_setup_failed'

# $1 = census file, $2 = stable|volatile
flatten() {
	awk -v v="$VOLATILE" -v want="$2" '
		# boot-census prefixes every line with an uptime token (host tNNNs key ...)
		# while census.sh does not (host key ...). Keying on field 2 blindly made the
		# uptime part of the key, so every line was unique and a clean run read as
		# "0 matched, 44 changed" - the tool disagreeing with itself, not a regression.
		{ f = 2
		  if ($2 ~ /^t[0-9]+s$/) f = 3
		  # Some lines are pure key=value runs (clients=0 mlo=0 bh_peers=0), so the
		  # key token carries a value. Split it, or the key changes whenever the
		  # value does and the fact reads as appearing/disappearing rather than moving.
		  k = $f
		  sub(/=.*/, "", k)
		  key = $1 "_" k
		  hit = (key ~ v)
		  if ((want == "stable" && hit) || (want == "volatile" && !hit)) next
		  val = $f
		  sub(/^[^=]*=/, "", val)
		  if (val == $f) val = ""
		  for (i = f + 1; i <= NF; i++) val = val (val == "" ? "" : " ") $i
		  printf "%s\t%s\n", key, val }
	' "$1" | LC_ALL=C sort -t"$TAB" -k1,1
}

echo "=== MUSI SEDET (zmena = regrese) ==="
flatten "$B" stable > "$T/b"
flatten "$A" stable > "$T/a"
join -t"$TAB" -a1 -a2 -e '<chybi>' -o 0,1.2,2.2 "$T/b" "$T/a" \
| awk -F"$TAB" '
	{ if ($2 == $3) same++
	  else { printf "  ZMENA  %-30s %s -> %s\n", $1, $2, $3; moved++ } }
	END { printf "  --- %d shodnych, %d zmenenych\n", same+0, moved+0 }'

echo
echo "=== ocekavane pohyblive ==="
flatten "$B" volatile > "$T/b"
flatten "$A" volatile > "$T/a"
join -t"$TAB" -a1 -a2 -e '-' -o 0,1.2,2.2 "$T/b" "$T/a" \
| awk -F"$TAB" '{ printf "  %-34s %s -> %s\n", $1, $2, $3 }'
