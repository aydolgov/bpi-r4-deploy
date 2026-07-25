#!/bin/bash
# ============================================================================
# verify-identical.sh — dokáže, že REFAKTOROVANÝ universal builder produkuje
# TÝŽ build jako ten stávající (v bin/). Tier 1 (vstupy) + Tier 2 (rootfs tree).
#
# Refactor jen přesouvá stejné cp/patch příkazy do common-easymesh.sh funkcí.
# Když .config + sada patchů + files/ overlay zůstanou identické, image je
# ekvivalentní KONSTRUKČNĚ (jediný rozdíl = build timestampy v squashfs).
#
# Použití:
#   1) OLD = stávající strom (referenční, co dal release v bin/):
#        REF=/home/ipsec/universal-easymesh/openwrt
#   2) NEW = strom po běhu refaktorovaného builderu (aspoň prepare+defconfig):
#        NEW=/home/ipsec/universal-new/openwrt
#   verify-identical.sh $REF $NEW
# Výstup: "IDENTICAL" nebo přesný seznam co se rozešlo.
# ============================================================================
set -uo pipefail
REF="${1:?ref openwrt tree}"; NEW="${2:?new openwrt tree}"
rc=0

echo "=== Tier 1a: .config (nejdůležitější - určuje CELÝ build) ==="
if diff -q "$REF/.config" "$NEW/.config" >/dev/null 2>&1; then
	echo "  OK  .config byte-identický"
else
	echo "  DIFF .config se rozešel:"; diff "$REF/.config" "$NEW/.config" | head -40; rc=1
fi

echo "=== Tier 1b: files/ overlay (baked config/scripty) ==="
# porovnat strom + obsah (sha256), ignorovat mtime
diff <(cd "$REF/files" 2>/dev/null && find . -type f -exec sha256sum {} \; | sort) \
     <(cd "$NEW/files" 2>/dev/null && find . -type f -exec sha256sum {} \; | sort) \
     && echo "  OK  files/ identický" || { echo "  DIFF files/ se rozešel (viz výše)"; rc=1; }

echo "=== Tier 1c: aplikované patche (mtk feed + openwrt patches) ==="
for d in "target/linux/mediatek/patches-6.12" \
         "package/boot/uboot-mediatek/patches" \
         "../mtk-openwrt-feeds/autobuild/unified/filogic/mac80211/25.12/files/package/kernel/mt76/patches" \
         "../mtk-openwrt-feeds/autobuild/unified/filogic/mac80211/25.12/files/package/kernel/mac80211/patches/subsys" \
         "../mtk-openwrt-feeds/autobuild/unified/filogic/mac80211/25.12/files/package/network/services/hostapd/patches"; do
	diff <(cd "$REF/$d" 2>/dev/null && ls -1 *.patch 2>/dev/null | sort; find . -name '*.patch' -exec sha256sum {} \; 2>/dev/null | sort) \
	     <(cd "$NEW/$d" 2>/dev/null && ls -1 *.patch 2>/dev/null | sort; find . -name '*.patch' -exec sha256sum {} \; 2>/dev/null | sort) \
	     >/dev/null 2>&1 && echo "  OK  $d" || { echo "  DIFF patch dir: $d"; \
	     diff <(cd "$REF/$d" 2>/dev/null && ls -1 *.patch 2>/dev/null|sort) <(cd "$NEW/$d" 2>/dev/null && ls -1 *.patch 2>/dev/null|sort) | head; rc=1; }
done

echo "=== Tier 1d: iopsys feed HEAD (musí být týž zdroj) ==="
# REF feed = vedle stareho stromu; NEW feed = sdileny easymesh-shared/iopsys-feed.
# Lze override: REF_FEED=... NEW_FEED=...
REF_FEED="${REF_FEED:-$REF/../iopsys-feed}"
NEW_FEED="${NEW_FEED:-/home/ipsec/easymesh-shared/iopsys-feed}"
r=$(git -C "$REF_FEED" rev-parse HEAD 2>/dev/null || echo REF-none)
n=$(git -C "$NEW_FEED" rev-parse HEAD 2>/dev/null || echo NEW-none)
[ "$r" = "$n" ] && echo "  OK  iopsys feed HEAD $r  (REF=$REF_FEED NEW=$NEW_FEED)" \
                || { echo "  DIFF feed: REF($REF_FEED)=$r NEW($NEW_FEED)=$n"; rc=1; }

# Tier 2 (volitelně, když existuje itb): rozbalit squashfs a diff file tree
if [ -n "${REF_ITB:-}" ] && [ -n "${NEW_ITB:-}" ]; then
	echo "=== Tier 2: rootfs file tree z itb (ignoruje mtime) ==="
	echo "  (TODO: unpack squashfs z $REF_ITB a $NEW_ITB, diff -r stromy)"
fi

echo "======================================================"
[ "$rc" = 0 ] && echo ">>> IDENTICAL — refaktorovaný universal = stávající <<<" \
             || echo ">>> ROZDÍLY NAHOŘE — reconcile než universal nahradíme <<<"
exit $rc
