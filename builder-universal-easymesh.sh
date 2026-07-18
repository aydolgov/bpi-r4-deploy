#!/bin/bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# BUMP 2026-07-06 (main migration; predchozi git01 base: 13f39a74):
#   OpenWrt:  6dead2869209f4ff9825f3169c129c5ef04f6273  (openwrt-25.12 HEAD, BEZE ZMENY)
#   MTK SDK:  822c2f0603614e47ec8496571043431494fd2841  (MAIN HEAD; git01 mrazi -> MTK doporucil main)
OPENWRT_COMMIT=${OPENWRT_COMMIT:-13ff2256e5dd9bc070f9a9c6a673bff4a9191837}   # EASYMESH pin (jako x8)

rm -rf openwrt
rm -rf mtk-openwrt-feeds

git clone --branch openwrt-25.12 https://github.com/openwrt/openwrt.git openwrt
cd openwrt; git checkout ${OPENWRT_COMMIT}; cd -;

# 2026-07-06: migrated git01 -> main (git01 frozen; MTK recommends main). Single source of truth.
git clone --branch main https://github.com/mediatek/mtk-openwrt-feeds mtk-openwrt-feeds
( cd mtk-openwrt-feeds && git checkout ec6b3fcef259708da3d7d2c189fa108c9bc67ac7 )   # EASYMESH pin (jako x8)


\cp -r my_files/999-sfp-10-additional-quirks.patch mtk-openwrt-feeds/25.12/files/target/linux/mediatek/patches-6.12
\cp -r my_files/999-sfp-11-rtl8261be-mdio-none.patch mtk-openwrt-feeds/25.12/files/target/linux/mediatek/patches-6.12
\cp -r my_files/999-sfp-22-rtl8261be-boot-1g-reprobe.patch mtk-openwrt-feeds/25.12/files/target/linux/mediatek/patches-6.12
\cp -r my_files/999-eth-21-mtk-gdm-rx-fsm-reset.patch mtk-openwrt-feeds/25.12/files/target/linux/mediatek/patches-6.12
\cp -r my_files/999-pcs-10-lynxi-hold-link-down-on-invalid-speed.patch mtk-openwrt-feeds/25.12/files/target/linux/mediatek/patches-6.12
\cp -r my_files/999-fix-01-mac80211-btwt-ap-mode.patch mtk-openwrt-feeds/autobuild/unified/filogic/mac80211/25.12/files/package/kernel/mac80211/patches/subsys/0139-fix-mac80211-btwt-ap-mode-he-btwt-supported.patch
\cp -r my_files/999-fix-00-xfrm-propagate-einprogress.patch mtk-openwrt-feeds/25.12/files/target/linux/mediatek/patches-6.12
\cp -r my_files/0264-wpa_s-add-btwt-join-command.patch mtk-openwrt-feeds/autobuild/unified/filogic/mac80211/25.12/files/package/network/services/hostapd/patches/0264-wpa_s-add-btwt-join-command.patch

### tx_power check Ivan Mironov's patch - for defective BE14 boards with defective eeprom flash
#\cp -r my_files/100-wifi-mt76-mt7996-Use-tx_power-from-default-fw-if-EEP.patch mtk-openwrt-feeds/autobuild/unified/filogic/mac80211/25.12/files/package/kernel/mt76/patches

### per-band WiFi LED (MT7996, single-wiphy MLO) + shared tpt trigger - HW verified 2026-06-28
\cp -r my_files/999-wifi-01-mt7996-per-band-leds.patch mtk-openwrt-feeds/autobuild/unified/filogic/mac80211/25.12/files/package/kernel/mt76/patches/9999-w-mt7996-per-band-leds.patch
\cp -r my_files/999-wifi-02-mt76-share-tpt-led-trigger.patch mtk-openwrt-feeds/autobuild/unified/filogic/mac80211/25.12/files/package/kernel/mt76/patches/9999-w-mt76-share-tpt-led-trigger.patch

cd openwrt
bash ../mtk-openwrt-feeds/autobuild/unified/autobuild.sh filogic-mac80211-mt798x_rfb-wifi7_nic prepare


\cp -r ../my_files/453-w-add-bpi-r4-nvme-dtso.patch target/linux/mediatek/patches-6.12/
\cp -r ../my_files/450-w-nand-mmc-add-bpi-r4.patch package/boot/uboot-mediatek/patches/450-add-bpi-r4.patch
\cp -r ../my_files/451-w-add-bpi-r4-nvme.patch package/boot/uboot-mediatek/patches/451-add-bpi-r4-nvme.patch
\cp ../my_files/452-w-add-bpi-r4-nvme-rfb.patch package/boot/uboot-mediatek/patches/452-add-bpi-r4-nvme-rfb.patch
\cp ../my_files/454-w-add-bpi-r4-nvme-env.patch package/boot/uboot-mediatek/patches/454-add-bpi-r4-nvme-env.patch
\cp -r ../my_files/w-filogic-bpi-r4-universal.mk target/linux/mediatek/image/filogic.mk

### ethernet/board LED (BPI-R4 standard) - leds overlay + uboot LED + filogic device + PHY trigger
\cp -r ../my_files/470-w-add-bpi-r4-leds-overlay.patch target/linux/mediatek/patches-6.12/
\cp ../my_files/471-w-bpi-r4-led-uboot.patch package/boot/uboot-mediatek/patches/471-bpi-r4-led-uboot.patch
sed -i 's/mt7988a-bananapi-bpi-r4-nvme$/mt7988a-bananapi-bpi-r4-nvme mt7988a-bananapi-bpi-r4-leds/' target/linux/mediatek/image/filogic.mk
echo "CONFIG_LED_TRIGGER_PHY=y" >> target/linux/mediatek/filogic/config-6.12

\cp ../my_files/arm-trusted-firmware-mediatek-Makefile package/boot/arm-trusted-firmware-mediatek/Makefile

echo "CONFIG_BLK_DEV_NVME=y" >> target/linux/mediatek/filogic/config-6.12
#echo "CONFIG_DYNAMIC_DEBUG=y" >> target/linux/mediatek/filogic/config-6.12
#echo "CONFIG_DYNAMIC_DEBUG_CORE=y" >> target/linux/mediatek/filogic/config-6.12

\cp -r ../my_files/999-fitblk-02-w-add-bpi-r4-nvme-fitblk.patch target/linux/mediatek/patches-6.12

\cp -r ../my_files/luci-app-wifimgr feeds/luci/applications/luci-app-wifimgr

mkdir -p files/etc/uci-defaults
\cp -r ../my_files/99-set-hostname files/etc/uci-defaults/
chmod +x files/etc/uci-defaults/99-set-hostname
# easymesh: node-config.sh napecena do /root (spusti se AZ ZA BEHU per uzel:
#   sh /root/node-config.sh controller bpi-4g 192.168.1.1
#   sh /root/node-config.sh agent      bpi-8g 192.168.1.3
# jeden image pro 4g i 8g -> identita nejde napect, resi ji tenhle skript.
mkdir -p files/root
\cp ../my_files/node-config.sh files/root/node-config.sh
chmod +x files/root/node-config.sh

# LAN LED: mtk-led-fix programs mt7530 gphy port-LED registers at boot (link + tx/rx activity)
mkdir -p files/etc/init.d
\cp ../my_files/etc-files/init.d/mtk-led-fix files/etc/init.d/
chmod +x files/etc/init.d/mtk-led-fix
\cp ../my_files/etc-files/uci-defaults/95-mtk-led-fix-enable files/etc/uci-defaults/
chmod +x files/etc/uci-defaults/95-mtk-led-fix-enable

# SD auto-expand: grow production + fitrw f2fs to fill the SD card on first boot (SD-only, guarded)
mkdir -p files/lib/preinit
\cp ../my_files/etc-files/lib/preinit/19-expand-fit-rootfs files/lib/preinit/
chmod +x files/lib/preinit/19-expand-fit-rootfs

# NVMe /data: mount the LABEL=data partition (NVMe installs only) at /data on first boot
\cp ../my_files/etc-files/uci-defaults/96-data-mount files/etc/uci-defaults/
chmod +x files/etc/uci-defaults/96-data-mount

mkdir -p files/root/install-dir
\cp ../my_files/bpi-r4-install/install-nand.sh files/root/install-dir/install-nand.sh
chmod +x files/root/install-dir/install-nand.sh
\cp ../my_files/bpi-r4-install/install-nvme.sh files/root/install-dir/install-nvme.sh
chmod +x files/root/install-dir/install-nvme.sh
\cp ../my_files/bpi-r4-install/install-emmc.sh files/root/install-dir/install-emmc.sh
chmod +x files/root/install-dir/install-emmc.sh
\cp ../my_files/bpi-r4-install/install-nvme-unifi.sh files/root/install-dir/install-nvme-unifi.sh
chmod +x files/root/install-dir/install-nvme-unifi.sh
#mkdir -p files/usr/sbin
#\cp ../my_files/bpi-r4-install/boot-nvme files/usr/sbin/boot-nvme
#chmod +x files/usr/sbin/boot-nvme
#\cp ../my_files/bpi-r4-pro/files/usr/sbin/boot-nand files/usr/sbin/boot-nand
#chmod +x files/usr/sbin/boot-nand



# feeds -a NUTNE (universal ma custom balicek luci-app-wifimgr zkopirovany PO autobuild
# prepare -> bez registrace by se nepostavil). Autobuild prepare feedy sice instaluje,
# ale PRED nasi kopii wifimgr; tohle re-scan/re-install po kopii je registruje.
./scripts/feeds update -a
./scripts/feeds install -a

\cp ../my_files/fit.sh package/utils/fitblk/files/fit.sh

### ---------- EASYMESH R6 vrstva (iopsys Multi-AP) ----------
# feed PIN na 8g stav (4e4bbbf5a) proti driftu (971/922/953 = broken MLD, NEbrat)
( cd "${REPO_DIR}/iopsys-feed" && git reset --hard 4e4bbbf5a && git clean -fd ) 2>/dev/null || \
( cd "${REPO_DIR}/iopsys-feed" && git reset --hard HEAD && git clean -fd ) 2>/dev/null || true
grep -q "src-link iopsys" feeds.conf.default || echo "src-link iopsys ${REPO_DIR}/iopsys-feed" >> feeds.conf.default
./scripts/feeds update iopsys
./scripts/feeds install libeasy libwifiutils libwifi libieee1905 ieee1905 ieee1905-map-plugin wifimngr map-controller map-agent

\cp -r ../configs/my_defconfig-universal-easymesh .config
make defconfig

### ---------- EASYMESH R6 config (verbatim jako x8/klasik) ----------
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
EASYMESH_EOF
make defconfig
sed -i "s/^CONFIG_IEEE1905_BUILD_TR181_PLUGIN=y/# CONFIG_IEEE1905_BUILD_TR181_PLUGIN is not set/" .config
sed -i "s/^CONFIG_WIFIMNGR_BUILD_TR181_PLUGIN=y/# CONFIG_WIFIMNGR_BUILD_TR181_PLUGIN is not set/" .config
sed -i "s/^CONFIG_AGENT_USE_LIBDPP=y/# CONFIG_AGENT_USE_LIBDPP is not set/" .config
sed -i "s/^CONFIG_CONTROLLER_USE_LIBDPP=y/# CONFIG_CONTROLLER_USE_LIBDPP is not set/" .config
sed -i "s/^CONFIG_PACKAGE_dm-service=y/# CONFIG_PACKAGE_dm-service is not set/" .config
sed -i "s/^CONFIG_PACKAGE_libbbfdm-api=y/# CONFIG_PACKAGE_libbbfdm-api is not set/" .config
sed -i "s/^CONFIG_PACKAGE_libbbfdm-ubus=y/# CONFIG_PACKAGE_libbbfdm-ubus is not set/" .config
make defconfig

echo "CONFIG_PACKAGE_trusted-firmware-a-mt7988-emmc-comb-4bg=y" >> .config
echo "CONFIG_PACKAGE_trusted-firmware-a-mt7988-sdmmc-comb-4bg=y" >> .config
echo "CONFIG_PACKAGE_trusted-firmware-a-mt7988-spim-nand-ubi-comb-4bg=y" >> .config

bash ../mtk-openwrt-feeds/autobuild/unified/autobuild.sh filogic-mac80211-mt798x_rfb-wifi7_nic build


