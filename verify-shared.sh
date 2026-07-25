#!/bin/bash
# ============================================================================
# verify-shared.sh — dokáže, že x8 SDÍLENÁ WiFi/mesh vrstva == universal.
# Porovnává JEN sdílené podmnožiny (musí být identické). Board delta (device
# defconfig, DTS, uboot, identita) se legitimně liší → tady se NEsrovnává.
#   verify-shared.sh <UNI_openwrt_tree> <X8_openwrt_tree>
# ============================================================================
set -uo pipefail
UNI="${1:?uni openwrt tree}"; X8="${2:?x8 openwrt tree}"
rc=0

echo "=== SHARED 1: WiFi patch adresáře (BTWT+LED, musí být identické) ==="
for d in "../mtk-openwrt-feeds/autobuild/unified/filogic/mac80211/25.12/files/package/kernel/mt76/patches" \
         "../mtk-openwrt-feeds/autobuild/unified/filogic/mac80211/25.12/files/package/kernel/mac80211/patches/subsys" \
         "../mtk-openwrt-feeds/autobuild/unified/filogic/mac80211/25.12/files/package/network/services/hostapd/patches"; do
  diff <(cd "$UNI/$d" 2>/dev/null && find . -name '*.patch' -exec sha256sum {} \; | sort) \
       <(cd "$X8/$d"  2>/dev/null && find . -name '*.patch' -exec sha256sum {} \; | sort) \
    >/dev/null 2>&1 && echo "  OK  $(basename "$d")" || { echo "  DIFF $d"; \
    diff <(cd "$UNI/$d" 2>/dev/null && ls *.patch|sort) <(cd "$X8/$d" 2>/dev/null && ls *.patch|sort)|head; rc=1; }
done

echo "=== SHARED 2: iopsys feed HEAD (sdílený easymesh-shared) ==="
h=$(git -C /home/ipsec/easymesh-shared/iopsys-feed rev-parse HEAD 2>/dev/null || echo none)
echo "  feed $h (oba buildery src-link na tentýž strom)"

echo "=== SHARED 3: files/ mesh subset (mld/bssid/mesh-status/mapc-db-keep) ==="
SUB="usr/sbin/mld-link-check usr/sbin/mld-config-check usr/sbin/mld-report-check usr/sbin/bssid-pin \
etc/init.d/mld-link-check etc/init.d/mld-config-check etc/init.d/mld-report-check etc/init.d/bssid-pin \
www/cgi-bin/mesh-status etc/mesh-node-names etc/uci-defaults/97-mapc-db-keep"
for f in $SUB; do
  a=$(sha256sum "$UNI/files/$f" 2>/dev/null | awk '{print $1}')
  b=$(sha256sum "$X8/files/$f"  2>/dev/null | awk '{print $1}')
  if [ -n "$a" ] && [ "$a" = "$b" ]; then echo "  OK  $f"; else echo "  DIFF/MISS $f (uni=${a:-chybi} x8=${b:-chybi})"; rc=1; fi
done

echo "=== SHARED 4: easymesh .config symboly (board symboly ignorovány) ==="
PAT='map-agent|map-controller|libeasy|libwifi|libwifiutils|libieee1905|ieee1905|wifimngr|EASYMESH|IEEE1905|LIBWIFI|WIFIMNGR|libbbfdm|dm-service|LIBDPP|TR181_PLUGIN|wpad-openssl|hostapd-common|hostapd-utils|wpa-cli|libsqlite3|sqlite3-cli'
diff <(grep -E "$PAT" "$UNI/.config" | sort) <(grep -E "$PAT" "$X8/.config" | sort) \
  && echo "  OK  easymesh symboly identické" || { echo "  DIFF easymesh symboly (viz výše)"; rc=1; }

echo "======================================================"
[ "$rc" = 0 ] && echo ">>> SHARED IDENTICAL — x8 mesh stack = universal mesh stack <<<" \
             || echo ">>> SHARED DIFF — x8 se v mesh vrstvě liší, reconcile <<<"
exit $rc
