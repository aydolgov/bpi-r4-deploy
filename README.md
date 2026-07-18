# bpi-r4-deploy — branch `universal-easymesh`

Single reproducible builder → ONE image for both 4GB and 8GB BPI-R4
(MULTI_PROFILE, comb-4bg TFA autodetect RAM).

- base: classic universal (openwrt `13ff2256` / mtk `ec6b3fce`)
- layer: EasyMesh R6 (iopsys Multi-AP, feed pin `4e4bbbf5a`, 22 patches) + wifimgr
- defconfig: `configs/my_defconfig-universal-easymesh` (trimmed, no strongswan/docker)
- identity: runtime via `/root/node-config.sh controller|agent <host> <ip>`

Build trees (`openwrt/`, `mtk-openwrt-feeds/`, `iopsys-feed/`) are gitignored —
the builder re-clones them on the pinned commits. iopsys feed backup = bundle in
CLAUDE-ARCHIV/git-backups/easymesh-build-env/.
