# shellcheck shell=bash
# ============================================================================
# common-easymesh.sh  —  JEDINÝ ZDROJ PRAVDY pro EasyMesh R6 WiFi/mesh vrstvu.
#
# Sourcuje se z builder-universal.sh i builder-x8.sh. Cokoli, co MUSÍ být
# na všech uzlech identické (WiFi patche, iopsys feed, easymesh config, mld
# skripty), žije JEN tady — takže x8 a universal se v tom NEMOHOU rozejít.
#
# Board/identity delta (device target, DTS, mgmt port, AL-MAC) NEPATŘÍ sem —
# ta zůstává v příslušném builder-<board>.sh.
#
# Pravidlo hranice (viz lekce 2026-07-24, split-brain / builder drift):
#   - SEM: všechno WiFi/mesh (patche, feed, easymesh defconfig, genconfig, mld)
#   - board builder: JEN {device defconfig, board patche, identita, role}
#
# Očekávané proměnné od volajícího builderu (nastavit PŘED source):
#   REPO_DIR         = absolutní cesta k repu (kvůli src-link feedu)
#   EASYMESH_SHARED  = absolutní cesta k adresáři se sdíleným iopsys-feed/
#                      a my_files-easymesh/ (WiFi patche). Jeden pro všechny.
#   AUTOBUILD_TARGET = filogic-mac80211-mt798x_rfb-wifi7_nic  (stejný na obou)
# ============================================================================

# --- 1) WiFi patche do MTK feedu (PŘED autobuild prepare) -------------------
# Voláno z build root (kde je mtk-openwrt-feeds/). Identické na všech uzlech.
easymesh_apply_wifi_patches() {
	local P="${EASYMESH_SHARED}/my_files-easymesh"
	local MAC80211="mtk-openwrt-feeds/autobuild/unified/filogic/mac80211/25.12/files"

	# BTWT: mac80211 he-btwt-supported + hostapd wpa_s btwt join.
	# (x8 je NEMĚL — driver/hostapd divergence, root řady dnešních fantomů.)
	\cp -r "$P/999-fix-01-mac80211-btwt-ap-mode.patch" \
		"$MAC80211/package/kernel/mac80211/patches/subsys/0139-fix-mac80211-btwt-ap-mode-he-btwt-supported.patch"
	\cp -r "$P/0264-wpa_s-add-btwt-join-command.patch" \
		"$MAC80211/package/network/services/hostapd/patches/0264-wpa_s-add-btwt-join-command.patch"

	# per-band WiFi LED (MT7996 single-wiphy MLO) + shared tpt trigger.
	\cp -r "$P/999-wifi-01-mt7996-per-band-leds.patch" \
		"$MAC80211/package/kernel/mt76/patches/9999-w-mt7996-per-band-leds.patch"
	\cp -r "$P/999-wifi-02-mt76-share-tpt-led-trigger.patch" \
		"$MAC80211/package/kernel/mt76/patches/9999-w-mt76-share-tpt-led-trigger.patch"

	# tx_power-from-default-fw ZÁMĚRNĚ vynechán i v universalu (jen defektní
	# BE14 eeprom) — necháváme stejně vynechaný, ať zůstane shodné.
}

# --- 2) mld-*-check watchdogy + mesh helpers do image files/ ----------------
# Voláno z openwrt/ (kde je files/). Identické na všech uzlech.
easymesh_install_mld_scripts() {
	local E="${EASYMESH_SHARED}/my_files-easymesh/etc-files"
	mkdir -p files/usr/sbin files/etc/init.d files/etc/rc.d files/www/cgi-bin

	local s
	# boot-census:S99 zapisuje kazdy boot do /etc/mapc/boot-census.log (prezije
	# sysupgrade diky 97-mapc-db-keep). Spolehlivost je deliverable, ale mereni
	# z 25. 7. byl vzorek JEDEN studeny powercycle. Timhle se serie hromadi sama
	# z kazdeho bootu, ktery kdokoli kdy udela, misto abychom po Petrovi chteli
	# deset powercyclu. Verdikt si uzel odvozuje ze SVE role a SVEHO poctu radii.
	# node-heartbeat:S99 pise jednu radku za minutu + NOVE radky z dmesg do
	# /etc/mapc/heartbeat.log. boot-census odpovida na 'naskocilo to a vydrzelo
	# ctvrt hodiny'; tohle odpovida na 'co delalo minutu predtim, nez umrelo'.
	# 2026-07-25 zmizel bpi-x8 z meshe I z drateneho mgmt portu dve hodiny po
	# poslednim census vzorku a nezustalo po nem NIC - zadny crashlog a dmesg po
	# powercyclu uz popisuje jen novy boot.
	for s in mld-link-check:S98 mld-config-check:S96 mld-report-check:S99 boot-census:S99 node-heartbeat:S99; do
		local name="${s%%:*}" rc="${s##*:}"
		\cp "$E/usr-sbin/$name" "files/usr/sbin/$name";  chmod +x "files/usr/sbin/$name"
		\cp "$E/init.d/$name"   "files/etc/init.d/$name"; chmod +x "files/etc/init.d/$name"
		ln -sf "../init.d/$name" "files/etc/rc.d/${rc}${name}"
	done

	# bssid-pin: JEN nástroj do /usr/sbin, ŽÁDNÝ init.d skript.
	#
	# Vynechání rc.d symlinku službu NEVYPNE: OpenWrt při stavbě rootfs povolí
	# každý /etc/init.d/* s START=, takže se S95 vyrobí znovu. Naměřeno
	# 2026-07-25 — staged files/etc/rc.d mělo jen S96/S98/S99, ale rootfs
	# nového x8 image měl S95bssid-pin, a služba běžela na všech třech uzlech.
	#
	# Běžet nemá: pinuje jen rozhraní, která právě existují, a pin nikdy
	# neodstraní. Nepinnuté BSS si přitom adresu přepočítávají čítačem v
	# iface.uc, takže po každé změně sady rozhraní může sednout na zamrzlý pin.
	# Na x8 se to stalo doslova: default_sta_radio1 (wlan1_0, dnes vypnutá) je
	# připnutá na 06:0c:43:26:81:10, na které běží 5GHz AP wlan1. Závěr z
	# BSSID driftu byl odpinovat, nepinovat — tohle dělalo pravý opak.
	#
	# Nástroj zůstává spustitelný ručně, když někdo pinovat chce.
	\cp "$E/usr-sbin/bssid-pin" files/usr/sbin/bssid-pin; chmod +x files/usr/sbin/bssid-pin

	# mlo-backhaul-setup: postavi REALNY MLO backhaul (druhe AP-MLD + MLD STA)
	# misto dnesniho jednolinkoveho 6GHz spoje. JEN nastroj, ZADNY init.d — pousti
	# se vedome na jednom uzlu, protoze nespravna konfigurace backhaulu shodi mesh.
	#
	# Proc to vubec chceme (naměřeno 2026-07-25): backhaul dnes NENI MLD — tri
	# oddelene per-radiove BSS MAP--BH, kazda s vlastnim klicem, driver hlasi
	# `valid links = 0x0`. MLD STA se proti nim navazat nemuze. A druhy duvod je
	# tezsi: iPhone 16 je MLSR (max_simul_links=1, emlsr_support=0) a na Neg-TTLM
	# neodpovi, takze MLMR protistranu nam da JEDINE nas vlastni router jako MLD
	# STA. Tenhle backhaul je proto i jedina cesta, jak Neg-TTLM predvest.
	\cp "$E/usr-sbin/mlo-backhaul-setup" files/usr/sbin/mlo-backhaul-setup; chmod +x files/usr/sbin/mlo-backhaul-setup

	# mesh-env: vypise nastaveni, ktera zijou MIMO /etc/config (U-Boot env:
	# netmode, owrt_country, disable_mlo) a co z nich reálne platí. Ty hodnoty
	# ridi chovani genconfigu i regulacni domain, v zadnem uci dumpu nejsou a
	# jsou per-kus — 2026-07-25 nas kazda z nich stala hledani na spatnem miste.
	\cp "$E/usr-sbin/mesh-env" files/usr/sbin/mesh-env; chmod +x files/usr/sbin/mesh-env

	\cp "$E/www-cgi/mesh-status" files/www/cgi-bin/mesh-status; chmod +x files/www/cgi-bin/mesh-status
	\cp "$E/mesh-node-names"     files/etc/mesh-node-names

	# mapc.db keep přes sysupgrade (deterministic recovery vrstva)
	\cp "$E/uci-defaults/97-mapc-db-keep" files/etc/uci-defaults/; chmod +x files/etc/uci-defaults/97-mapc-db-keep

	# Fail-safe: uzel nerozdava DHCP, dokud to node-config.sh vyslovne nedovoli.
	# Druhy DHCP server v mesh L2 domene tise vezme klientum internet.
	\cp "$E/uci-defaults/98-mesh-dhcp-safe" files/etc/uci-defaults/; chmod +x files/etc/uci-defaults/98-mesh-dhcp-safe

	# Per-radiove fronthauly pryc: AP-MLD JE fronthaul (rozhodnuto 2026-07-17).
	# Nutne jako uci-default, NE v genconfigu - tam to na provisionovanem uzlu
	# nikdy nedobehne (viz komentar ve skriptu, prokazano instrumentaci).
	\cp "$E/uci-defaults/99-drop-legacy-fronthaul" files/etc/uci-defaults/; chmod +x files/etc/uci-defaults/99-drop-legacy-fronthaul
}

# --- 3) iopsys feed = JEDEN sdílený zdroj (proti 991-typu driftu) -----------
# Voláno z openwrt/. Feed žije v EASYMESH_SHARED/iopsys-feed — jeden pro
# universal i x8, takže se NEMŮŽOU rozejít (dnes ráno 991 chyběl v x8 kopii).
# iopsys feed = map-agent, map-controller, libwifi, ieee1905 + vsechny nase
# EasyMesh patche (936, 970-994, genconfig). Zije jako samostatny git repo v
# ${EASYMESH_SHARED}/iopsys-feed a je v .gitignore, protoze ma vlastni historii.
#
# ZALOHA: do 2026-07-25 nebyly nase commity na ZADNEM remote - `origin` je
# upstream dev.iopsys.eu, kam nepushujeme, takze jadro projektu existovalo jen
# na disku VM1. Od 25. 7. je zrcadleno:
#
#   remote woziwrt = https://github.com/woziwrt/iopsys-feed.git  (private)
#   branch devel, tag easymesh-pin-2026-07-27c -> 957a3a4a6
#
# Pri obnove na cistem stroji klonovat odtud, ne z upstreamu - upstream nase
# patche nema. Po zmene ve feedu: commit + `git push woziwrt devel` + posunout
# pin nize, jinak `git reset --hard` v teto funkci tu zmenu pri buildu zahodi.
easymesh_setup_iopsys_feed() {
	# pin na týž commit jako original builder (L152), fallback HEAD
	( cd "${EASYMESH_SHARED}/iopsys-feed" && git reset --hard 957a3a4a6 && git clean -fd ) 2>/dev/null || \
	( cd "${EASYMESH_SHARED}/iopsys-feed" && git reset --hard HEAD && git clean -fd ) 2>/dev/null || true
	grep -q "src-link iopsys" feeds.conf.default || \
		echo "src-link iopsys ${EASYMESH_SHARED}/iopsys-feed" >> feeds.conf.default
	./scripts/feeds update iopsys
	./scripts/feeds install libeasy libwifiutils libwifi libieee1905 ieee1905 \
		ieee1905-map-plugin wifimngr map-controller map-agent
}

# --- 4) easymesh defconfig blok (identický na všech uzlech) -----------------
# Voláno z openwrt/ PO `cp <board-defconfig> .config`. Přidá easymesh symboly
# a vypne TR181/bbfdm. Board defconfig řeší JEN device/HW volby.
# luci-app-wifimgr. Musi byt na VSECH uzlech, ne jen na klasicich: krome UI nese
# /etc/init.d/wifimgr-defaults (START=99), ktery na prvnim bootu nastavi
# country=CZ a factory SSID heslo/sifrovani. Bez nej zustane regulacni domain na
# hardcoded fallbacku US z /lib/wifi/mac80211.uc:155 (board.json nema
# wlan.defaults a owrt_country neni v U-Boot env) - presne to se stalo x8
# 2026-07-25: klasici CZ, x8 US, tedy FCC pravidla v CR.
#
# Proto je balik TADY a ne v per-builder delte: cokoli, co ovlivnuje WiFi, patri
# do sdilene vrstvy. Volat PRED `feeds install -a`, jinak se package nezaregistruje.
easymesh_install_wifimgr() {
	\cp -r "${EASYMESH_SHARED}/my_files-easymesh/luci-app-wifimgr" feeds/luci/applications/luci-app-wifimgr
}

easymesh_apply_defconfig() {
	cat >> .config <<'EASYMESH_EOF'
CONFIG_PACKAGE_libeasy=y
CONFIG_PACKAGE_libwifi=y
CONFIG_PACKAGE_libwifiutils=y
CONFIG_PACKAGE_libieee1905=y
CONFIG_PACKAGE_ieee1905=y
CONFIG_PACKAGE_ieee1905-map-plugin=y
CONFIG_PACKAGE_wifimngr=y
CONFIG_PACKAGE_map-agent=y
CONFIG_PACKAGE_map-controller=y
CONFIG_PACKAGE_wpad-openssl=y
CONFIG_PACKAGE_hostapd-common=y
CONFIG_PACKAGE_hostapd-utils=y
CONFIG_PACKAGE_wpa-cli=y
CONFIG_AGENT_EASYMESH_VERSION=6
CONFIG_CONTROLLER_EASYMESH_VERSION=6
CONFIG_MULTIAP_EASYMESH_VERSION=6
CONFIG_IEEE1905_ETH_MEDIA_EXTENSION=y
CONFIG_IEEE1905_EXTENSION_ALLOWED=y
CONFIG_IEEE1905_PLATFORM_HAS_WIFI=y
CONFIG_IEEE1905_WIFI_EASYMESH=y
CONFIG_LIBWIFI_SKIP_PROBES=y
CONFIG_LIBWIFI_USE_CTRL_IFACE=y
CONFIG_WIFIMNGR_CACHE_SCANRESULTS=y
CONFIG_WIFIMNGR_VENDOR_EXTENSIONS=y
CONFIG_WIFIMNGR_VENDOR_PREFIX="X_IOWRT_EU_"
CONFIG_PACKAGE_libsqlite3=y
CONFIG_PACKAGE_sqlite3-cli=y
CONFIG_PACKAGE_strace=y
CONFIG_PACKAGE_gdb=y
CONFIG_PACKAGE_gdbserver=y
CONFIG_PACKAGE_python3-light=y
# CONFIG_PACKAGE_dm-service is not set
# CONFIG_PACKAGE_libbbfdm-api is not set
# CONFIG_PACKAGE_libbbfdm-ubus is not set
# CONFIG_PACKAGE_bbf_configmngr is not set
CONFIG_BUSYBOX_CUSTOM=y
CONFIG_BUSYBOX_CONFIG_TIMEOUT=y
CONFIG_PACKAGE_luci-app-wifimgr=y
EASYMESH_EOF
	make defconfig
	# TR181 pluginy + libdpp vypnout (defconfig je zapíná defaultně)
	sed -i "s/^CONFIG_IEEE1905_BUILD_TR181_PLUGIN=y/# CONFIG_IEEE1905_BUILD_TR181_PLUGIN is not set/" .config
	sed -i "s/^CONFIG_WIFIMNGR_BUILD_TR181_PLUGIN=y/# CONFIG_WIFIMNGR_BUILD_TR181_PLUGIN is not set/" .config
	sed -i "s/^CONFIG_AGENT_USE_LIBDPP=y/# CONFIG_AGENT_USE_LIBDPP is not set/" .config
	sed -i "s/^CONFIG_CONTROLLER_USE_LIBDPP=y/# CONFIG_CONTROLLER_USE_LIBDPP is not set/" .config
	# dm-service + libbbfdm-* vypnout AŽ TEĎ (po vypnutí TR181 pluginů výše).
	sed -i "s/^CONFIG_PACKAGE_dm-service=y/# CONFIG_PACKAGE_dm-service is not set/" .config
	sed -i "s/^CONFIG_PACKAGE_libbbfdm-api=y/# CONFIG_PACKAGE_libbbfdm-api is not set/" .config
	sed -i "s/^CONFIG_PACKAGE_libbbfdm-ubus=y/# CONFIG_PACKAGE_libbbfdm-ubus is not set/" .config
	make defconfig
}
