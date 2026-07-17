#!/bin/bash
set -euo pipefail

# absolutni cesta k tomuto repu (builder cd-uje do openwrt/, feed potrebuje abs. cestu)
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# EASYMESH-X8 2026-07-17: piny SROVNANY na easymesh-standard (determinismus MLD/TTLM ma prednost):
#   OpenWrt:  13ff2256e5dd9bc070f9a9c6a673bff4a9191837  (openwrt-25.12 HEAD, BEZE ZMENY)
#   MTK SDK:  ec6b3fcef259708da3d7d2c189fa108c9bc67ac7  (MAIN HEAD; git01 mrazi -> MTK doporucil main)

rm -rf openwrt
rm -rf mtk-openwrt-feeds

git clone --branch openwrt-25.12 https://github.com/openwrt/openwrt.git openwrt
cd openwrt; git checkout ${OPENWRT_COMMIT:-13ff2256e5dd9bc070f9a9c6a673bff4a9191837}; cd -;

git clone --branch main https://github.com/mediatek/mtk-openwrt-feeds mtk-openwrt-feeds
( cd mtk-openwrt-feeds && git checkout ${MTK_COMMIT:-ec6b3fcef259708da3d7d2c189fa108c9bc67ac7} )

\cp -r my_files/999-sfp-10-additional-quirks.patch mtk-openwrt-feeds/25.12/files/target/linux/mediatek/patches-6.12
\cp -r my_files/999-sfp-11-rtl8261be-mdio-none.patch mtk-openwrt-feeds/25.12/files/target/linux/mediatek/patches-6.12
\cp -r my_files/999-sfp-22-rtl8261be-boot-1g-reprobe.patch mtk-openwrt-feeds/25.12/files/target/linux/mediatek/patches-6.12
\cp -r my_files/999-eth-21-mtk-gdm-rx-fsm-reset.patch mtk-openwrt-feeds/25.12/files/target/linux/mediatek/patches-6.12
#\cp -r my_files/999-sfp-15-oem-sfp10gt-ignore-los.patch mtk-openwrt-feeds/25.12/files/target/linux/mediatek/patches-6.12
\cp -r my_files/999-fix-00-xfrm-sw-sa-offload-ok.patch mtk-openwrt-feeds/25.12/files/target/linux/mediatek/patches-6.12

### tx_power check Ivan Mironov's patch - for defective BE14 boards with defective eeprom flash
\cp -r my_files/100-wifi-mt76-mt7996-Use-tx_power-from-default-fw-if-EEP.patch mtk-openwrt-feeds/autobuild/unified/filogic/mac80211/25.12/files/package/kernel/mt76/patches

### per-band WiFi LED (MT7996, single-wiphy MLO) + shared tpt trigger - HW verified 2026-06-28
\cp -r my_files/999-wifi-01-mt7996-per-band-leds.patch mtk-openwrt-feeds/autobuild/unified/filogic/mac80211/25.12/files/package/kernel/mt76/patches/9999-w-mt7996-per-band-leds.patch
\cp -r my_files/999-wifi-02-mt76-share-tpt-led-trigger.patch mtk-openwrt-feeds/autobuild/unified/filogic/mac80211/25.12/files/package/kernel/mt76/patches/9999-w-mt76-share-tpt-led-trigger.patch

cd openwrt
bash ../mtk-openwrt-feeds/autobuild/unified/autobuild.sh filogic-mac80211-mt798x_rfb-wifi7_nic prepare

# platform.sh: register bpi-r4-pro-8x in fit_do_upgrade, fit_check_image, platform_copy_config
# POJISTKA: overuje pocet zasahu. Bez ni by pri zmene upstreamu replace() tise neudelal
# nic, build by dobehl OK a sysupgrade by uzel rozbil (tichy no-op). Radeji spadnout tady.
python3 - <<'PLATFORM_EOF'
f = "target/linux/mediatek/filogic/base-files/lib/upgrade/platform.sh"
c = open(f).read()
p1 = "\tbananapi,bpi-r4-lite|\\\n\tbazis,ax3000wm"
p2 = "\tbananapi,bpi-r4-lite|\\\n\tcmcc,rax3000m"
n1, n2 = c.count(p1), c.count(p2)
assert n1 == 2, "platform.sh: pattern 'bazis' ma %d vyskytu, ceka se 2 - UPSTREAM SE ZMENIL" % n1
assert n2 == 1, "platform.sh: pattern 'cmcc' ma %d vyskytu, ceka se 1 - UPSTREAM SE ZMENIL" % n2
c = c.replace(p1, "\tbananapi,bpi-r4-lite|\\\n\tbananapi,bpi-r4-pro-8x|\\\n\tbazis,ax3000wm")
c = c.replace(p2, "\tbananapi,bpi-r4-lite|\\\n\tbananapi,bpi-r4-pro-8x|\\\n\tcmcc,rax3000m")
open(f, "w").write(c)
n = c.count("bananapi,bpi-r4-pro-8x")
assert n == 3, "platform.sh: pro-8x registrovan %dx, ceka se 3x" % n
print("platform.sh: bpi-r4-pro-8x registrovan 3x (do_upgrade/check_image/copy_config) - OK")
PLATFORM_EOF

# BPI-R4 patches
\cp -r ../my_files/453-w-add-bpi-r4-nvme-dtso.patch target/linux/mediatek/patches-6.12/
\cp -r ../my_files/455-w-add-bpi-r4-pro-nvme-dtso.patch target/linux/mediatek/patches-6.12/
\cp -r ../my_files/450-w-nand-mmc-add-bpi-r4.patch package/boot/uboot-mediatek/patches/450-add-bpi-r4.patch
\cp -r ../my_files/451-w-add-bpi-r4-nvme.patch package/boot/uboot-mediatek/patches/451-add-bpi-r4-nvme.patch
\cp ../my_files/452-w-add-bpi-r4-nvme-rfb.patch package/boot/uboot-mediatek/patches/452-add-bpi-r4-nvme-rfb.patch
\cp ../my_files/454-w-add-bpi-r4-nvme-env.patch package/boot/uboot-mediatek/patches/454-add-bpi-r4-nvme-env.patch

# BPI-R4-Pro-8x patches
# Remove MTK feed patches superseded by our ports or already provided by feed
rm -f target/linux/mediatek/patches-6.12/999-eth-06-mtk_eth_soc-support-ethernet-passive-mux.patch
# Remove upstream Frank-W DTS patch — we use Sinovoip-based DTS instead
rm -f target/linux/mediatek/patches-6.12/046-v6.19-arm64-dts-mediatek-mt7988a-bpi-r4-pro-add-dts.patch
\cp -r ../my_files/bpi-r4-pro/patches-kernel/* target/linux/mediatek/patches-6.12/
\cp ../my_files/bpi-r4-pro/patches-uboot/471-add-bpi-r4-pro-8x.patch package/boot/uboot-mediatek/patches/
#\cp ../my_files/bpi-r4-pro/patches-uboot/472-add-bpi-r4-pro-8x-makefile.patch package/boot/uboot-mediatek/patches/
\cp ../my_files/bpi-r4-pro/uboot-mediatek-Makefile package/boot/uboot-mediatek/Makefile
\cp ../my_files/bpi-r4-pro/arm-trusted-firmware-mediatek-Makefile package/boot/arm-trusted-firmware-mediatek/Makefile
\cp -r ../my_files/w-sd-nand-mmc-nvme-ddr4-filogic.mk target/linux/mediatek/image/filogic.mk
mv target/linux/mediatek/image/filogic-extra.mk target/linux/mediatek/image/filogic-extra.mk.disabled

echo "CONFIG_BLK_DEV_NVME=y" >> target/linux/mediatek/filogic/config-6.12
echo "CONFIG_TASK_IO_ACCOUNTING=y" >> target/linux/mediatek/filogic/config-6.12
python3 -c 'content=open("package/kernel/linux/modules/netdevices.mk").read(); content=content.replace("  KCONFIG:=CONFIG_AS21XXX_PHY\n  FILES:= \\\n   $(LINUX_DIR)/drivers/net/phy/as21xxx.ko\n  AUTOLOAD:=$(call AutoLoad,18,as21xxx)", "  KCONFIG:=CONFIG_AS21XXX_PHY\n  FILES:= \\\n   $(LINUX_DIR)/drivers/net/phy/aeon_as21xxx.ko\n  AUTOLOAD:=$(call AutoLoad,18,aeon_as21xxx)"); open("package/kernel/linux/modules/netdevices.mk","w").write(content)'
python3 -c 'content=open("target/linux/mediatek/filogic/config-6.12").read(); content=content.replace("CONFIG_AS21XXX_PHY=y", "CONFIG_AS21XXX_PHY=m"); open("target/linux/mediatek/filogic/config-6.12","w").write(content)'

\cp -r ../my_files/999-fitblk-02-w-add-bpi-r4-nvme-fitblk.patch target/linux/mediatek/patches-6.12

mkdir -p files/etc/uci-defaults
\cp -r ../my_files/99-set-hostname files/etc/uci-defaults/
chmod +x files/etc/uci-defaults/99-set-hostname
\cp -r ../my_files/99-pro-8x-network files/etc/uci-defaults/
chmod +x files/etc/uci-defaults/99-pro-8x-network

# --- identita uzlu bpi-x8 (bezi jako POSLEDNI uci-default) ---
# Bez tohoto by sysupgrade -n nasadil default 192.168.1.1 = kolize s controllerem
# bpi-4g. Takhle uzel po kazdem -n naskoci rovnou spravne, bez rucnich kroku.
\cp -r ../my_files/99-x8-identity files/etc/uci-defaults/
chmod +x files/etc/uci-defaults/99-x8-identity

# SD auto-expand: grow production + fitrw f2fs to fill the SD card on first boot
# (SD-only, fail-closed gate inside the hook; no-op on eMMC/NVMe/NAND)
mkdir -p files/lib/preinit
\cp ../my_files/etc-files/lib/preinit/19-expand-fit-rootfs files/lib/preinit/
chmod +x files/lib/preinit/19-expand-fit-rootfs

mkdir -p files/etc
\cp ../my_files/fw_env_pro8x_snand.config files/etc/fw_env.config


mkdir -p files/root/install-dir
\cp ../my_files/bpi-r4-install/install-nand-pro8x.sh files/root/install-dir/install-nand.sh
chmod +x files/root/install-dir/install-nand.sh
\cp ../my_files/bpi-r4-install/install-nvme-pro8x.sh files/root/install-dir/install-nvme.sh
chmod +x files/root/install-dir/install-nvme.sh
\cp ../my_files/bpi-r4-install/install-emmc-pro8x.sh files/root/install-dir/install-emmc.sh
chmod +x files/root/install-dir/install-emmc.sh
mkdir -p files/usr/sbin
\cp ../my_files/bpi-r4-install/boot-nvme files/usr/sbin/boot-nvme
chmod +x files/usr/sbin/boot-nvme
\cp ../my_files/bpi-r4-pro/files/usr/sbin/boot-nand files/usr/sbin/boot-nand
chmod +x files/usr/sbin/boot-nand


./scripts/feeds update -a
./scripts/feeds install -a

### ---------- EASYMESH R6 vrstva (iopsys Multi-AP) ----------
### Feed = VLASTNI KOPIE v tomto repu (iopsys-feed/), nese i nase patche
### (DB persistence, MLD/TTLM, onboarding determinismus).
### Cileny install: feed ma ~200 balicku, `install -a` by prebil stock OpenWrt.
grep -q "src-link iopsys" feeds.conf.default || echo "src-link iopsys ${REPO_DIR}/iopsys-feed" >> feeds.conf.default
./scripts/feeds update iopsys
./scripts/feeds install libeasy libwifiutils libwifi libieee1905 ieee1905 ieee1905-map-plugin wifimngr map-controller map-agent



\cp ../my_files/fit.sh package/utils/fitblk/files/fit.sh


\cp -r ../configs/my_defconfig-8x-full .config

### ---------- EASYMESH R6 config (shodne s easymesh-standard vyvojovym stromem) ----------
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
# hostapd/wpad s MLO - easymesh stoji na ap-mld (x8 defconfig mel jen hostapd-utils)
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
# DB persistence vrstva (flagship - deterministicky recovery)
CONFIG_PACKAGE_libsqlite3=y
CONFIG_PACKAGE_sqlite3-cli=y
# on-box HAL diagnostika
CONFIG_PACKAGE_strace=y
CONFIG_PACKAGE_gdb=y
CONFIG_PACKAGE_gdbserver=y
# bbfdm (iopsys TR-181 datamodel) VYPNOUT - `feeds install` ho vytahne jako zavislost
# ieee1905/wifimngr (include bbfdm.mk), protoze NEvyhodnocuje podminku
# `+IEEE1905_BUILD_TR181_PLUGIN:libbbfdm-api`. defconfig ho pak zapne jako =y a build
# padne na generovani datamodelu (dm-service), ktery bez TR181 nedava smysl.
# defconfig existujici volby neprepisuje -> "is not set" napsane PRED nim vydrzi.
# CONFIG_PACKAGE_dm-service is not set
# CONFIG_PACKAGE_libbbfdm-api is not set
# CONFIG_PACKAGE_libbbfdm-ubus is not set
# CONFIG_PACKAGE_bbf_configmngr is not set
# busybox timeout - bez nej se na uzlu neda nic ohranicit/merit (kousalo nas opakovane)
CONFIG_BUSYBOX_CUSTOM=y
CONFIG_BUSYBOX_CONFIG_TIMEOUT=y
EASYMESH_EOF
make defconfig

### TR181 pluginy + libdpp VYPNOUT (defconfig je zapina defaultne)
sed -i "s/^CONFIG_IEEE1905_BUILD_TR181_PLUGIN=y/# CONFIG_IEEE1905_BUILD_TR181_PLUGIN is not set/" .config
sed -i "s/^CONFIG_WIFIMNGR_BUILD_TR181_PLUGIN=y/# CONFIG_WIFIMNGR_BUILD_TR181_PLUGIN is not set/" .config
sed -i "s/^CONFIG_AGENT_USE_LIBDPP=y/# CONFIG_AGENT_USE_LIBDPP is not set/" .config
sed -i "s/^CONFIG_CONTROLLER_USE_LIBDPP=y/# CONFIG_CONTROLLER_USE_LIBDPP is not set/" .config
make defconfig
echo "CONFIG_PACKAGE_trusted-firmware-a-mt7988-emmc-comb-4bg=y" >> .config
echo "CONFIG_PACKAGE_trusted-firmware-a-mt7988-sdmmc-comb-4bg=y" >> .config
echo "CONFIG_PACKAGE_trusted-firmware-a-mt7988-spim-nand-ubi-comb-4bg=y" >> .config


bash ../mtk-openwrt-feeds/autobuild/unified/autobuild.sh filogic-mac80211-mt798x_rfb-wifi7_nic build
