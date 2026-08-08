#!/bin/bash
set -euo pipefail
# ============================================================================
# builder-universal.sh  —  klasik BPI-R4 (4g/8g) EasyMesh R6 image.
#
# = SDÍLENÁ easymesh WiFi/mesh vrstva (common-easymesh.sh) + klasik BPI-R4 delta.
# Identická struktura jako builder-x8.sh — liší se JEN board deltou (device
# defconfig, patche, identita). WiFi/mesh je v common → x8 a universal se v tom
# NEMOHOU rozejít.
#
# REFACTOR 2026-07-24: dřív měl vlastní kopie WiFi patchů + iopsys-feed +
# easymesh config. Ty přesunuty do common-easymesh.sh (jeden zdroj). Musí
# zůstat BIT-EKVIVALENTNÍ s předchozím buildem (viz verify-identical.sh).
# ============================================================================

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EASYMESH_SHARED="${EASYMESH_SHARED:-${REPO_DIR}/../easymesh-shared}"
AUTOBUILD_TARGET="filogic-mac80211-mt798x_rfb-wifi7_nic"
OPENWRT_COMMIT="${OPENWRT_COMMIT:-4d0fec5a4845ba166203a782d08217b3f1cf2af9}"
MTK_COMMIT="${MTK_COMMIT:-3a4e2a2511af93cea1ca43205a02362423882b7c}"

# shellcheck source=common-easymesh.sh
. "${EASYMESH_SHARED}/common-easymesh.sh"

rm -rf openwrt mtk-openwrt-feeds
git clone --branch openwrt-25.12 https://github.com/openwrt/openwrt.git openwrt
( cd openwrt && git checkout "${OPENWRT_COMMIT}" )
git clone --branch main https://github.com/mediatek/mtk-openwrt-feeds mtk-openwrt-feeds
( cd mtk-openwrt-feeds && git checkout "${MTK_COMMIT}" )

# --- eth/SFP patche (BPI-R4 networking HW; TODO: kandidát na common-board) ---
for p in 999-sfp-10-additional-quirks 999-sfp-11-rtl8261be-mdio-none \
	 999-sfp-22-rtl8261be-boot-1g-reprobe 999-eth-21-mtk-gdm-rx-fsm-reset \
	 999-pcs-10-lynxi-hold-link-down-on-invalid-speed \
	 999-fix-00-xfrm-propagate-einprogress; do
	\cp -r "my_files/$p.patch" mtk-openwrt-feeds/25.12/files/target/linux/mediatek/patches-6.12
done

# --- SDÍLENÉ: WiFi patche (BTWT + LED) do MTK feedu ---
easymesh_apply_wifi_patches

cd openwrt
bash ../mtk-openwrt-feeds/autobuild/unified/autobuild.sh "${AUTOBUILD_TARGET}" prepare

# ==========================================================================
# ---------- klasik BPI-R4 HARDWARE DELTA -----------------------------------
# ==========================================================================
\cp -r ../my_files/453-w-add-bpi-r4-nvme-dtso.patch target/linux/mediatek/patches-6.12/
\cp -r ../my_files/450-w-nand-mmc-add-bpi-r4.patch package/boot/uboot-mediatek/patches/450-add-bpi-r4.patch
\cp -r ../my_files/451-w-add-bpi-r4-nvme.patch package/boot/uboot-mediatek/patches/451-add-bpi-r4-nvme.patch
\cp ../my_files/452-w-add-bpi-r4-nvme-rfb.patch package/boot/uboot-mediatek/patches/452-add-bpi-r4-nvme-rfb.patch
\cp ../my_files/454-w-add-bpi-r4-nvme-env.patch package/boot/uboot-mediatek/patches/454-add-bpi-r4-nvme-env.patch
\cp -r ../my_files/w-filogic-bpi-r4-universal.mk target/linux/mediatek/image/filogic.mk

# ethernet/board LED (klasik BPI-R4)
\cp -r ../my_files/470-w-add-bpi-r4-leds-overlay.patch target/linux/mediatek/patches-6.12/
\cp ../my_files/471-w-bpi-r4-led-uboot.patch package/boot/uboot-mediatek/patches/471-bpi-r4-led-uboot.patch
sed -i 's/mt7988a-bananapi-bpi-r4-nvme$/mt7988a-bananapi-bpi-r4-nvme mt7988a-bananapi-bpi-r4-leds/' target/linux/mediatek/image/filogic.mk
echo "CONFIG_LED_TRIGGER_PHY=y" >> target/linux/mediatek/filogic/config-6.12

\cp ../my_files/arm-trusted-firmware-mediatek-Makefile package/boot/arm-trusted-firmware-mediatek/Makefile
echo "CONFIG_BLK_DEV_NVME=y" >> target/linux/mediatek/filogic/config-6.12
\cp -r ../my_files/999-fitblk-02-w-add-bpi-r4-nvme-fitblk.patch target/linux/mediatek/patches-6.12

# --- image files/: hostname + SDÍLENÉ mld skripty + runtime identita -------
mkdir -p files/etc/uci-defaults
\cp -r ../my_files/99-set-hostname files/etc/uci-defaults/; chmod +x files/etc/uci-defaults/99-set-hostname

easymesh_install_mld_scripts        # SDÍLENÉ: mld-*-check, mesh-status, mapc-db-keep

# klasik = JEDEN image pro 4g i 8g -> identita se řeší AŽ ZA BĚHU per uzel:
#   sh /root/node-config.sh controller bpi-4g 192.168.1.1
#   sh /root/node-config.sh agent      bpi-8g 192.168.1.3
mkdir -p files/root
\cp ../my_files/node-config.sh files/root/node-config.sh; chmod +x files/root/node-config.sh

# LAN LED (mt7530 gphy port-LED registry) + SD auto-expand + NVMe /data mount
mkdir -p files/etc/init.d files/lib/preinit
\cp ../my_files/etc-files/init.d/mtk-led-fix files/etc/init.d/; chmod +x files/etc/init.d/mtk-led-fix
\cp ../my_files/etc-files/uci-defaults/95-mtk-led-fix-enable files/etc/uci-defaults/; chmod +x files/etc/uci-defaults/95-mtk-led-fix-enable
\cp ../my_files/etc-files/lib/preinit/19-expand-fit-rootfs files/lib/preinit/; chmod +x files/lib/preinit/19-expand-fit-rootfs
\cp ../my_files/etc-files/uci-defaults/96-data-mount files/etc/uci-defaults/; chmod +x files/etc/uci-defaults/96-data-mount

mkdir -p files/root/install-dir
for i in nand nvme emmc nvme-unifi; do
	\cp "../my_files/bpi-r4-install/install-$i.sh" "files/root/install-dir/install-$i.sh"
	chmod +x "files/root/install-dir/install-$i.sh"
done

# ==========================================================================
# ---------- SDÍLENÁ easymesh vrstva (feed + defconfig) ---------------------
# ==========================================================================
easymesh_install_wifimgr           # SDILENE: luci-app-wifimgr (nese country=CZ)
./scripts/feeds update -a
./scripts/feeds install -a

easymesh_setup_iopsys_feed          # SDÍLENÝ iopsys feed

# --- produktovy feed woziwrt (ZAMERNE JEN universal) ------------------------
# Baliky easymesh* stavi jen tento builder, x8 ne. Oba stavi pro tutez
# architekturu aarch64_cortex-a53, takze jedna sada .apk slouzi obema deskam.
# Kdyby je stavely oba, vznikly by dve sady stejne verze s jinym otiskem a
# u nasazeneho baliku by nebylo poznat, ze ktereho stromu pochazi.
#
# Radek musi pribyt tady a ne natrvalo v feeds.conf.default: builder vyse dela
# `rm -rf openwrt` a klonuje znovu, takze rucni uprava toho souboru nikdy
# neprezije jediny build.
grep -q "src-link easymeshr6" feeds.conf.default || \
	echo "src-link easymeshr6 ${EASYMESH_SHARED}/easymesh-r6-feed" >> feeds.conf.default
./scripts/feeds update easymeshr6
./scripts/feeds install easymesh easymesh-config easymesh-mesh easymesh-wifi easymesh-api luci-app-easymesh
\cp ../my_files/fit.sh package/utils/fitblk/files/fit.sh

\cp -r ../configs/my_defconfig-universal-easymesh .config   # klasik device volby
easymesh_apply_defconfig            # SDÍLENÉ easymesh symboly + TR181/bbfdm off

echo "CONFIG_PACKAGE_trusted-firmware-a-mt7988-emmc-comb-4bg=y" >> .config
echo "CONFIG_PACKAGE_trusted-firmware-a-mt7988-sdmmc-comb-4bg=y" >> .config
echo "CONFIG_PACKAGE_trusted-firmware-a-mt7988-spim-nand-ubi-comb-4bg=y" >> .config

# Produktove baliky jako =m: .apk se vyrobi do bin/, ale do obrazu se NEZAPECOU.
# To je zamer - mesh vrstva se na uzel dostava pres `apk add easymesh` a da se
# tak aktualizovat bez reflashe. Overeno 2026-08-07 na bpi-4g2 od nuly.
echo "CONFIG_PACKAGE_easymesh=m" >> .config
echo "CONFIG_PACKAGE_easymesh-config=m" >> .config
echo "CONFIG_PACKAGE_easymesh-mesh=m" >> .config
echo "CONFIG_PACKAGE_easymesh-wifi=m" >> .config
echo "CONFIG_PACKAGE_easymesh-api=m" >> .config
echo "CONFIG_PACKAGE_luci-app-easymesh=m" >> .config

# PREPARE_ONLY=1 → doběhne k nastageovanému .config+patches+files/ (verify),
# přeskočí dlouhý full build. Prázdné/0 = normální build.
if [ "${PREPARE_ONLY:-0}" = 1 ]; then
	# ŽÁDNÝ make defconfig tady — force-přidané ATF 4bg řádky výše nesmí být
	# strženy. Reálný build (autobuild build) je taky nechává být → .config
	# tady = přesně to, co reálný build konzumuje (apples-to-apples s REF).
	echo ">>> PREPARE_ONLY: .config + patche + files/ nastageovany, full build PRESKOCEN"
else
	bash ../mtk-openwrt-feeds/autobuild/unified/autobuild.sh "${AUTOBUILD_TARGET}" build
fi
