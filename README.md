# x8-easymesh — EasyMesh R6 for BPI-R4 Pro 8X

**This branch builds one thing only:** an EasyMesh R6 image for the
`bananapi_bpi-r4-pro-8x` board, used as the third node (`bpi-x8`) of the
woziwrt EasyMesh R6 lab. It never builds a standard BPI-R4 image — all other
builders and `build-versions.env` (which drives the standard-R4 workflow) were
removed on purpose.

HW verified 2026-07-17: flashed to eMMC with `sysupgrade -n`, joined the lab
mesh as third node — `num_nodes=3`, DB `agent=3 / radio=9 / topology_link=2`,
5 GHz `MAP--BH` backhaul, mesh data path 1.1 ms.

## Layout

```
builder-x8-easymesh.sh   the only builder (renamed from builder-pro-8x.sh)
my_files/                sources it copies into the tree (patches, scripts, files)
  99-x8-identity           node identity, baked into the image
configs/my_defconfig-8x-full
```

Not in git (see `.gitignore`), the builder fetches or you provide them:

```
openwrt/             ~28G, cloned by the builder at the pinned commit
mtk-openwrt-feeds/   cloned by the builder at the pinned commit
iopsys-feed/         copy of the iopsys feed incl. our patches (see below)
```

## Pins — aligned to easymesh-standard, not to deploy

```
OPENWRT_COMMIT = 13ff2256e5dd9bc070f9a9c6a673bff4a9191837   (openwrt-25.12, 2026-05-16)
MTK_COMMIT     = ec6b3fcef259708da3d7d2c189fa108c9bc67ac7   (main, 2026-07-09)
```

The deploy branch uses `6dead2869` + `822c2f06`. We deliberately use the pins the
easymesh dev tree was tuned on: an easymesh regression would be **silent and
non-deterministic**, a board-patch mismatch fails **loudly at build time**.
Loud beats silent. The Pro-8X patches do build against the older base.

`build-versions.env` is gone — the single source of pins is the builder script.

## iopsys feed

`iopsys-feed/` is a copy of the iopsys feed **including our patches** (DB
persistence, MLD/TTLM, onboarding determinism). It is a local copy on purpose:
the easymesh-standard tree grafts the feed via a `src-link` symlink, so both
trees would share it and a change for x8 would silently apply to the standard
tree as well.

Canonical source of the patches: `github.com/woziwrt/easymesh-r6` → `patches/`,
deployment recipe in its `RESTORE.md` (ČÁST D).

The builder installs **9 packages explicitly**, not `feeds install -a` — the feed
holds ~200 packages and `-a` would shadow stock OpenWrt ones.

The capstone patch `953-mapcontroller-restore-apmld` is parked
(`.disabled-capstone-odlozen`): it is an unfinished draft and has no place in a
first image.

## Build

```sh
cd /home/ipsec/x8-easymesh
./builder-x8-easymesh.sh 2>&1 | tee build-$(date +%Y%m%d-%H%M).log
```

Watch for this line shortly after `autobuild.sh prepare`:

```
platform.sh: bpi-r4-pro-8x registrovan 3x (do_upgrade/check_image/copy_config) - OK
```

If it says `UPSTREAM SE ZMENIL` instead, stop: the sysupgrade registration no
longer matches upstream and an image built anyway would brick the node on the
first flash.

Image: `openwrt/bin/targets/mediatek/filogic/openwrt-mediatek-filogic-bananapi_bpi-r4-pro-8x-squashfs-sysupgrade.itb`

**MTK autobuild caveat:** on any build error it silently falls back to `-j1`,
turning a 20-minute build into hours. And `download_openwrt_packages()` ignores
the return code of `make download`, so failed mirrors do not stop the build.
If a build crawls, check for `Build failed with error code` in the log.

## Flash

```sh
scp -O <image> root@<node>:/tmp/fw.itb      # -O is required
ssh root@<node> 'md5sum /tmp/fw.itb'        # verify BEFORE flashing
ssh root@<node> 'sysupgrade -n /tmp/fw.itb'
```

`-n` is mandatory: config compat 1.0→1.1 (ports were renamed upstream), a
keep-config upgrade is refused. `-n` is also what you want — the identity is in
the image.

**Then do not touch the node for 5 minutes.** The bSTA is bridged into `br-lan`
about a minute after boot, the controller DB catches up over tens of seconds.
Measuring earlier reads a half-finished state and invites wrong conclusions.

`sysupgrade -n` regenerates the node's ieee1905 AL-MAC (see gaps), so the
controller keeps a ghost node from the previous identity.

## Node identity (`my_files/99-x8-identity`)

Runs as a uci-default on first boot after `-n`:

```
hostname bpi-x8
mgmt  mxl_lan0 -> 192.168.1.2/24     (Pro 8X ports are mxl_lan*, not lan*)
mesh  br-lan   -> 10.10.10.2/24
firewall: lan_3 into the lan zone, atomically
role: agent (mapcontroller disabled), 5 GHz bSTA on MAP--BH
```

Notes:
* The mgmt port is `mxl_lan0` — the port with the cable. ADR 0008 says LAN3, but
  the Pro 8X driver names do not map to the case labels. Only the mgmt port
  leaves `br-lan`; the rest stay, because **netifd will not bring up a bridge
  with no ports** (learned the hard way 2026-07-17).
* No `fw_setenv netmode extender` (unlike `node-config.sh`): `/etc/fw_env.config`
  in this image describes the NAND env while we boot from eMMC (env lives on
  `/dev/mmcblk0p1`), so `fw_setenv` writes nowhere and `|| true` hides it. The
  explicit `config bsta` is what actually works — `bpi-8g` proves it.
* The identity is **board-specific**. For another Pro 8X it has to be
  parameterised.

## Known gaps

1. **`99-x8-identity` should be `999-x8-identity`.** `991-multiap-genconfig` and
   `994-map-set-cntlr-sel-mode` sort *after* `99-` and override
   `controller_select.local` and `mapcontroller.enabled`.
2. **AL-MAC is not stable.** `30-set-ieee1905-al-macaddr` bails out because
   `get_mac_label` is empty on this board, so ieee1905 generates a random AL-MAC
   per fresh config. Every `-n` flash therefore leaves a ghost node in the
   controller topology and DB. Bake the AL-MAC into the identity script.
3. `/etc/fw_env.config` is wrong twice over: wrong medium (NAND UBI while booting
   from eMMC) and wrong geometry (`0x40000` vs LEB `0x1f000`). `fw_printenv`
   silently falls back to a default environment.
4. Agents do not emit their own AP-MLD: `wireless.mld0` + `mapagent.apmld0` +
   `mld_id` exist only in the controller branch of `node-config.sh`, so
   `apmld` in the DB has exactly one owner — the controller.
