# Handoff — EasyMesh R6, odpoledne 4. 8. 2026

Navazuje na `HANDOFF-easymesh-2026-08-04-rano.md` a `PLAN-systematicka-prace-2026-08-04.md`.
Řídicí pravidlo beze změny: **spolehlivost před funkcemi**, včetně opakovaného testování.

---

## 1. Jeden kořen dvou vad — libwifi mluví cizím hostapd API

Log na 4g, doslova:

```
wifimngr: ubus call hostapd.ap-mld-2 event_mask_add {"event":"raw-assoc"}  (Method not found)
wifimngr: ubus call hostapd.ap-mld-1 event_mask_add {"event":"raw-action"} (Method not found)
```

`event_mask_add` je **iopsysí rozšíření hostapd**. Náš hostapd je OpenWrtí —
nabízí `notify_response` a `bss_mgmt_enable`, tuhle metodu nemá. Volá to
`hostapd_ubus_iface_subscribe_frame()` (`libwifi/modules/wpactrl/hostapd_ctrl.c:1967`)
z `wifi_subscribe_frame()`, takže **každé předplacení syrových rámců selže**.

Důsledky:

| vada | proč |
|---|---|
| minutové zpoždění registrace klienta | `wifi.sta` nikdo nevyrábí — v celém libwifi to umí jen broadcomový `modules/broadcom/wlctrl.c` |
| `btm_success = 0` | map-agent si předplácí `WIFI_FRAME_ACTION`, kde přichází BTM Response |

**map-agent není vinen.** Odběr `wifi.sta` i celý řetěz k `wifi_add_sta()` je
správný — jen nikdy nevystřelí.

### Slepé uličky, které se nemusí zkoumat znovu

- **wifimngr NENÍ místo opravy.** Ve switchi řeší zvlášť jen skenování, zbytek
  jde do `default:` a jen propustí hotový řetězec od libwifi.
- **`hapdctrl_parse_event()`** čte `AP-STA-CONNECTED` jen do `apconn_cache`.
- **`NL80211_CMD_CONNECT`** je STA mód (backhaul), ne asociace klienta, a nechává
  `resp` prázdný → `sscanf` ve wifimngr selže.
- **`/etc/wifi.json`** (evmap) na uzlu neexistuje a balíček ho neinstaluje.

---

## 2. HOTOVO: patch 922 — producent `wifi.sta`

`iopsys-feed/libwifi/patches/922-hostapd-ctrl-publishes-wifi-sta.patch`

Emituje z hostapd ctrl soketů, které už teď držíme a drénujeme na uloopu,
jeden na afilovanou linku. Tvar odpovídá tomu, co map-agent parsuje
v `process_sta_con_dis_evt()`, **včetně MLO polí** — tím se rovnou spustí
`stamld_update()` a per-link model se staví z události, ne odhadem.

Ověřeno měřením před psaním kódu:

- `AP-STA-CONNECTED` chodí **per-link** (`ap-mld-1_link0/1/2`), ubus notifikace
  jen na úrovni MLD ⇒ ctrl socket je bohatší zdroj
- afilovaná MAC = `peer_addr[link_id]` z `STA <mld>`; pole je **na všech
  soketech totožné**, tedy indexované link id
- `bssid[0]`, `mld_addr[0]`, `mld_link_id[0]` z `STATUS`, statické → cache
- map-agent AP dohledává **podle BSSID**, ne podle jména, a všechny tři linkové
  BSSID skutečně drží (ověřeno proti běžícímu agentovi)

Dvě věci řešené kvůli spolehlivosti:

- dotazy jdou přes `wpa_ctrl_cmd()` s vlastním krátkodobým soketem, **ne** přes
  monitorovací — `wpa_ctrl_request()` zahazuje nevyžádané zprávy, dokud čeká na
  odpověď, takže by v bouři asociací spolkl událost
- odpojení pojmenuje nohu z malé per-socket tabulky, protože hostapd v tu chvíli
  STA už zahodil

**Stav:** commit `82d3658b4`, pin posunut (`895cab3`), obojí pushnuto.
libwifi přeloženo **bez varování**, řetězec `wifi.sta '{…}'` ověřen
v `libwifi-7.so.21`. **Na železe zatím neotestováno — čeká na full build.**

⚠️ Riziko k testu: callback jde synchronně uvnitř drénovací smyčky → při bouři
asociací N × `ubus_send_event` v jednom probuzení. Třída problému, kterou řešil
patch `910` (ENFILE). Test = boot s aktivními klienty a hlídat fd, ne jen
„telefon se připojil".

---

## 3. `btm_success = 0` má PRVNÍ příčinu mimo náš kód

`hostapd_cli log_level DEBUG` na 4g (vratné, vráceno na INFO):

```
WNM: Send BSS Transition Management Request to 7a:6f:6d:db:82:92 … dialog_token=11
Ignore BSS Transition Management Response from 7a:6f:6d:db:82:92
      since BSS Transition Management is disabled
```

Žádost odejde, klient odpoví, **hostapd odpověď zahodí**.
`/lib/netifd/hostapd.sh:857` → `set_default bss_transition 0`; do configu se to
dostane jen při `option bss_transition '1'` na `wifi-iface` (ř. 868). U nás to
**není nastavené nikde** — `uci show wireless` prázdné,
v `/var/run/hostapd-phy0.*.conf` jen `rrm_neighbor_report` a `rrm_beacon_report`.

Tím se srovnává starý rozpor: **steering funguje, a přitom `btm_success` je nula.**
Chybělo započtení, ne přesměrování.

⚠️ Runtime `ubus call hostapd.ap-mld-1 bss_mgmt_enable {"bss_transition":true}`
**nepomohlo** — hostapd hlásil „disabled" dál. Nejspíš proto, že odpověď přijímá
linkový hapd a ubus objekt existuje jen na úrovni MLD. ⇒ patří to do konfigurace,
kterou generuje naše vrstva.

**Pořadí:** napřed `bss_transition=1`, teprve pak doručení odpovědi do agenta.
Doručovat něco, co hostapd zahodí, nemá smysl.

Pro producenta: map-agent má handler `btm-resp` hotový a čeká `macaddr`,
`target_bssid`, `status` — **`status` jako ŘETĚZEC** (`strtol`). Odtud vede
`wifi_send_sta_report()` → `agent_get_ap_by_ifname()`, takže se musí poslat
jméno, které agent zná: drží `wlan0/1/2`, `ap-mld-1/2`, `bhmld5/6` —
**NE** `ap-mld-1_link2`, to je jen jméno ctrl soketu.

---

## 4. „Připojeno, ale bez internetu" — chyceno naživo

Petr hlásil telefon připojený bez internetu. Po `/etc/init.d/mlo-steerd stop`
internet naskočil, **aniž by se telefonu kdokoli dotkl**.

`/root/mlo-steerd.sh` (služba `/etc/init.d/mlo-steerd`, běží na **všech** uzlech)
posílá každých 10 s A-TTLM:

```sh
attlm_set() { hostapd_cli -i ap-mld-1 set_attlm disabled_links=$mask … }
```

Maska jsou **vypnuté** linky. Naměřeno: 4g `mask=4` (vypnutý 6 GHz),
8g `mask=6` (vypnuté 5 i 6 GHz, zbylo 2,4 GHz).

**Jádro vady — plošná akce podle nejhoršího jednotlivce:**
`SNR = min_rssi(link) − noise_at(freq)`, kde `min_rssi` je **minimum přes všechny
stanice**, a A-TTLM je *advertised*, tedy platí celému AP-MLD.
⇒ jeden vzdálený klient vypne pásmo i klientům u antény.

Klient se pak asociuje normálně, ale TIDy má na vypnutých linkách ⇒ **připojeno,
data neteče**. Přerušovanost odpovídá tomu, kde se zrovna nachází nejslabší klient.

Prahy: `SNR_HARD_LOW_6=2`, `SNR_HARD_HIGH_6=20` — široká mezera.
Kaskáda: blok pro 5 GHz běží jen když je 6 GHz už vypnutá.
Zamrznutí: obě větve visí na `SNR*_VALID`, takže bez měření se stav nemění.

**Dvě opravy vlastních tvrzení z dneška:**
- **Není to trvalý latch** — 8g se v 12:27:15 zapnout dokázalo.
- **Čísla nejsou vadná** — šum na 6135 je regulérních −74 dBm, ten klient
  opravdu byl daleko. Vada je v politice, ne v měření.

**Konstrukčně to patří do Neg-TTLM (per-STA), ne do advertised A-TTLM.**
Skript Neg-TTLM umí — používá ho ve větvi `MASK=0`. Oprava tedy není „vyhodit",
ale „nedělat plošně to, co má být adresné".

**Náprava:** `/etc/init.d/mlo-steerd stop` — **ne `kill`**, procd respawnuje
(chvíli běžely dvě instance naráz). A-TTLM vyprší samo do 25 s.
Zpět `start`, nebo `uci set mlo-steerd.global.mode=all_on`.

⚠️ **Dopad na dnešní měření:** ranní čísla propustnosti mohla vzniknout
s administrativně vypnutým pásmem. Dvouskok 604 → 136 Mbit/s a hypotéza kolem
antény x8 se musí **přeměřit s vypnutým mlo-steerd**. Signálová měření per-řetěz
to neovlivňuje.

⚠️ **Obecně:** na síti běžely dva nezávislé steering mozky. Před každým měřením
EasyMesh chování ověřit, že mlo-steerd neběží.

---

## 5. Uklizeno v gitu

`mld-report-check` měl **109 necommitnutých řádků z 1. 8.** — a přitom md5
`c7537252…` běželo **na všech třech uzlech** i v `files/` obou build stromů.
Kód v produkci existoval na jediném disku. Commit `d293334`, pushnuto.

Poučení: **trackování souboru nestačí, hlídat se musí změna.** Odhalilo to
`git status --short` plus porovnání md5 stromu proti běžícímu uzlu.

Vedlejší: `x8-new/my_files/…/mld-report-check` je starší jiná verze
(`882e008a…`). Není to riziko — `common-easymesh.sh` bere výhradně
`easymesh-shared/my_files-easymesh`; per-strom `my_files` jsou mrtvý pozůstatek.

Obě repa čistá. Feed `82d3658b4` → `woziwrt` (ne `origin`, tam je upstream
iopsys), shared `d293334` → `origin`.

---

## 6. Co dál

1. **`bss_transition=1`** do generovaného wireless configu (probíhá)
2. **patch B** — doručení BTM odpovědi do map-agenta, teprve po bodu 1
3. **full build + flash** — patch 922 na železe neověřen
4. **přeměřit propustnost** s vypnutým mlo-steerd
5. **opravit mlo-steerd**: A-TTLM → Neg-TTLM, a nikdy nerozhodovat plošně
   podle `min` přes stanice
6. zbytek fáze 1 podle plánu

## Měřicí lekce z odpoledne

- **`pgrep -f <vzor>` chytá i vlastní shell.** Dvakrát za den mě to svedlo —
  jednou k „wifimngr respawnuje" (nerespawnoval), podruhé k „3 instance
  mlo-steerd" (byla jedna). Autorita je `ps w | grep "[v]zor"`.
- **Nezachycení události neznamená, že se nestala.** BTM odpověď nechytil ani
  ctrl socket, ani ubus — protože ji hostapd zahodil dřív. Teprve
  `log_level DEBUG` ukázal pravdu.
- **Přečíst kód, ne hádat z názvu.** `mask` u `set_attlm` jsou vypnuté linky;
  z názvu bych to měl obráceně.

---

# VEČER — emise událostí JEDE, ověřeno přes studený start

## 7. Producent nestačil — chyběly DVĚ věci mimo kód

Patch 922 byl napsaný správně, ale **nikdy se nespustil**:

```
wifimngr: Failed to open '/etc/wifi.json'
```

**(a) Evmap neexistoval.** Bez `/etc/wifi.json` selže `wifimngr_setup_events()`
hned na prvním kroku a **nezaregistruje se ANI JEDEN zdroj** — wifimngr pak drží
jediný socket, svoje ubus spojení. Každý producent v libwifi je mrtvý kód.
Balíček ten soubor nedodává a nic jiného ho nevyrábí.

**(b) Jedna položka NA LINKU, ne na MLD.** `hapdctrl_reopen()` končí
`w->req.fd_monitor = w->socks[0].ctrl->s;` a `socks[0]` je **rodičovský** socket.
Na ten hostapd nic neposílá — asociace chodí na `ap-mld-1_linkN`. Hlídaný
deskriptor tedy nikdy neožije a linkové sokety s daty nikdo nepřečte.
⇒ registrovat každou linku zvlášť; jméno s `_link` se dál nevětví, takže drží
právě jeden socket a ten se stane jejím `fd_monitor`. **Oprava bez řádku kódu.**

Řešeno skriptem `wifi-evmap` (S94), který evmap **generuje z konfigurace**
(počet linek MLD = počet rádií). Ne z živých soketů — ty vznikají asynchronně
(5 GHz čeká 60 s na DFS CAC), takže by to na pomalém bootu tiše vyrobilo kratší
mapu. Ověřeno: 7 zdrojů = 7 soketů na všech třech uzlech.

## 8. HW DŮKAZ — klient se registruje z události

bpi-x8, vypnout/zapnout WiFi na iPhonu. **Tři události, jedna na každou nohu:**

```
link0  macaddr 3e:1a:de:62:66:6c  bssid 00:0c:43:26:60:10  mlo_link_id 0
link1  macaddr 4e:d7:fd:22:3c:53  bssid 06:0c:43:26:80:10  mlo_link_id 1
link2  macaddr fe:3d:ae:2d:47:cf  bssid 0a:0c:43:26:a0:10  mlo_link_id 2
       mlo_macaddr 7a:6f:6d:db:82:92   mlo_bssid 00:0c:43:26:60:10
```

map-agent je vzal všechny (STA MLD i tři afilované adresy v `map.agent status`).
✅ BSSID linky 0 se rovná MLD adrese a producent to ustál — poslal linkové.
⚠️ Na prvním odpojení po startu zdroje je `macaddr == mlo_macaddr`; tabulka
MLD→afilovaná se plní až při připojení. Není to vada.

## 9. HW DŮKAZ — BTM celý řetěz

Na 8g, `bss_transition_request` s debugem hostapd:

```
1. hostapd pošle žádost                dialog_token=21
2. klient ODPOVÍ                       status_code=6 + seznam 7 kandidátů
3. hostapd odpověď ZPRACUJE            ← wnm-enable; dřív ji zahazoval
4. BSS-TM-RESP na ctrl
5. libwifi 923 → wifi.sta btm-resp     macaddr fe:3d:ae:2d:47:cf (afilovaná!)
                                       status "6" (řetězec), bssid 32:fb:2f:94:91:7b
6. map-agent to VZAL                   map.agent btm-resp, ifname wlan2-2
```

Bod 6 dokazuje patch **99996**: agent si podle BSSID dohledal rozhraní, které
podle jména dohledat nešlo. Adresa je táž jako v `connected` — překlad přes
tabulku z 922 drží napříč oběma typy událostí.
`status_code=6` = *„nemám vhodného kandidáta"*, správně — poslal jsem žádost bez
seznamu. `btm_success` se proto nezvedne; zvedne se až po úspěšném přesunu.
Bonus: klient vrátil **seznam 7 BSSID, které vidí** — surovina pro steering.

## 10. Studený start — POSLEDNÍ chybějící článek

Po rebootu x8 vyšlo najevo, že celý řetěz je po startu **mrtvý**:

```
wifimngr nastartoval     42 s po bootu
sokety hostapd vznikly   86-93 s po bootu
```

libwifi takový zdroj registruje **DORMANT** (`fd_monitor = 0`), wifimngr pro něj
nepřidá uloop fd, nic ho nepolluje a **už nikdy se nepřipojí**. Tiše — evmap se
otevřel v pořádku, žádná chyba v logu. Na 5 GHz je před tím 60 s DFS, takže to
není smůla, ale **normální průběh každého studeného startu**.

Řešeno hlídačem `evsrc-check` (S99, odpojený): počká na sokety, a drží-li
wifimngr míň soketů než je zdrojů, jednou restartuje wifimngr.

**✅ OVĚŘENO ZA SKUTEČNÉHO BOOTU 8g:**
```
15:02:23  evsrc-check: wifimngr holds 1 socket(s) for 7 event source(s) after 15s
                       - registered before hostapd was up; restarting it
15:02:28  after restart: 13 socket(s) for 7 source(s)
```
a po startu: evmap 7 zdrojů, wifimngr 13 soketů, mlo-steerd 0/0,
`bss_transition` ve 3 configech.

## 11. Roaming se propisuje do DB

Petr přenesl telefon 8g → 4g. DB do minuty:
```
sta:  7a:6f:6d:db:82:92 → bssid 7e:04:1c:81:7c:2e, agent 86:f7:56:41:01:d3
nohy: fe:3d:ae → 76:04:1c:81:bc:2e (6G) rcpi 78
      3e:1a:de → 7a:04:1c:81:9c:2e (5G)
      4e:d7:fd → 7e:04:1c:81:7c:2e (2,4G)
```
Všechny tři nohy přepnuté na BSSID nového uzlu.

## 12. Co je rychlé a co ne — změřeno v kódu

| údaj | odkud | latence |
|---|---|---|
| klient se připojil/odpojil, kde, na kterých nohách | **událost** → `wifi_topology_notification()` **přímo v obsluze** | ~0,1 s |
| RCPI, rychlosti, bajty | `agent_metric_report_timer_cb`, samoobnovný časovač, `report_interval=5` | ~5 s |

Dřív: přítomnost klienta **minuty a nepředvídatelně** — `init_ifaces_scheduler`
je **jednorázový** časovač nasazovaný při změně stavu, ne smyčka. Klient se
objevil, „až něco jiného shodou okolností vyvolalo průchod rozhraními".

**Polling se NEZRUŠIL a rušit se nemá.** Cache `apconn` má TTL 5 s a v hlavičce
stojí, že je tam *„self-heals a dropped/missed event"*. Čtecí cesta buď obslouží
z cache (kterou událost právě aktualizovala, stáří 0), nebo — je-li starší 5 s —
**cache nepoužije a jde se zeptat hostapd načerstvo**. Není větev, kde by ležela
stará hodnota a čekala na zápis. Rozvrstvení: události = rychlá cesta,
polling = dorovnávací síť.
⚠️ Ale: **per-linkovou identitu nese VÝHRADNĚ událost.** Polling zná jen seznam
adres, chybu v afilované MAC by nedorovnal.

## 13. mlo-steerd vypnut natrvalo

`uci-defaults/91-mlo-steerd-off` — zůstává v obrazu, nespouští se.
Vynechat rc.d symlink NESTAČÍ: OpenWrt povolí každý init.d s `START=` při stavbě
rootfs. Zpět: `/etc/init.d/mlo-steerd enable && start`.

## 14. Commity (vše pushnuto)

```
82d3658b4  libwifi 922 — producent wifi.sta
b9b501443  libwifi 923 + map-agent 99996 — BTM
0828690    wnm-enable — bss_transition
b5e990f    wifi-evmap — mapa událostí, jedna položka na linku
8a7548a    evsrc-check — ověří, že se wifimngr opravdu připojil
78f3ee9    91-mlo-steerd-off
d293334    mld-report-check — kód, co běžel jen na disku
```

Nové obrazy postavené a ověřené v rootfs (oba stromy): `wifi-evmap`,
`evsrc-check`, `wnm-enable`, `91-mlo-steerd-off`, rc.d symlinky, libwifi 18×
`wifi.sta`. **Zatím NENAFLASHOVÁNO.**

## 15. Zbývá

1. **Flashnout nové obrazy** — na uzlech to zatím drží `sysupgrade.conf`, čistá
   instalace by ty tři skripty neměla
2. **Studený start 4g** (poslední neověřený uzel)
3. **Přeměřit propustnost** s vypnutým mlo-steerd — ranní čísla jsou podezřelá
4. **Změřit latenci konce do konce** — BusyBox `date` neumí `%N`, chce to jiný
   zdroj času; zatím je 0,1 s **odhad složený ze změřených dílů**
5. Sousedé v `map.agent status`, ztráta DHCP po roamingu, držené asociace 164 s
6. mlo-steerd: A-TTLM → Neg-TTLM (per-STA), nikdy plošně podle `min` přes stanice

## Měřicí lekce z večera

- **`grep -c "[v]zor"` chytá i vlastní shell.** Třikrát za den: „wifimngr
  respawnuje", „3 instance mlo-steerd", „mlo-steerd běží po stopu". Autorita je
  `ps w | grep "[v]zor"` s vypsáním řádků, ne počítání.
- **BusyBox `date +%s%N` vrací jen sekundy.** Deset měření mi vyšlo „0 ms".
  Metoda byla vadná, ne výsledek.
- **`/proc/net/dev` má na 2. pozici BAJTY, ne pakety.** Z toho mi vyšla
  „bouře 3868 paketů/s", ve skutečnosti 9 pkt/s.

---

# POZDNÍ VEČER — čtyři vady nalezené Z TABULKY

Petr si prohlédl `mesh-status` a z toho vypadly čtyři vady, tři z nich
**v mém vlastním kódu z téhož dne**. Bez toho pohledu by nás mátly týdny.

## 16. `924` — backhaul se hlásil na fronthaulu

`hapdctrl_sock_info()` četlo ze `STATUS` natvrdo `bssid[0]`. Jenže STATUS
vypisuje **všechny BSS na tom rádiu**, indexované:

```
bss[0]=ap-mld-1   bssid[0]=32:fb:2f:94:91:7b   ssid[0]=OpenWrt-
bss[1]=ap-mld-2   bssid[1]=32:fb:2f:94:91:7a   ssid[1]=MAP--BH
```

Index 0 je **první BSS na rádiu**, ne ten dotazovaný. Fronthaul vycházel
správně jen náhodou. Backhaulová stanice x8 byla uložena s fronthaulovým
BSSID a `is_bsta=0` ⇒ v tabulce věčný „stale" klient.
Oprava hledá BSS **podle jména** (`bss[i]=<parent>`, pak `bssid[i]`).

**✅ HW ověřeno:** po vynucené reasociaci
`06:0c:43:26:81:10 | ca:8e:1d:ca:bc:af | is_bsta=1` — a `is_bsta` si
controller doplnil **sám**, protože konečně viděl backhaulové BSS.

## 17. `925` — legacy klient není MLD

922 posílalo `mlo_*` pole pro **každou** stanici na MLD lince. map-agent pak
volal `stamld_update()` i pro legacy klienta a uložil ho jako
jednolinkové MLD, které je samo sobě MLD. Petrův Mac ([HT][VHT], žádné EHT)
měl vlastní `sta_mld` řádek — a tabulka ho kvůli němu **schovala jako
odešlého, přestože byl připojený**.

Rozlišovací znak: `STA <mac>` vrací `peer_addr[]` **jen skutečnému MLO
klientovi** — 3 řádky pro iPhone, 0 pro Mac. MLO blok se tedy posílá jen
když se afilovaná adresa opravdu najde.
Vedlejší efekt: odpojení po restartu wifimngr (prázdná tabulka MLD→afilovaná)
jde ven **bez** MLO polí — radši neúplná událost než vymyšlené MLD.

**✅ HW ověřeno** na reasociaci backhaulu 8g: `disconnected` bez `mlo_*`,
`connected` s afilovanou `3e:fb:2f:94:73:7b` a správným MAP--BH BSSID.

## 18. `999991` — `sta_mld.is_bsta` bylo zadrátované na nulu

```sql
VALUES(?,0,?,...)   ON CONFLICT ... DO UPDATE SET is_bsta=0, ...
```

Žádné STA-MLD se nikdy neoznačilo jako backhaul ⇒ **každý backhaul svítí jako
klient**, jeden na skok. V řetězu rozprostřené, ve hvězdě všechny na
controlleru.

⚠️ **Nelze hledat přímo v `bss`:** `ap_mld_macaddr` je **MLD adresa**, kdežto
`bss` drží **linková** BSSID; shodují se jen tam, kde linka 0 nese MLD adresu.
Ověřeno proti živé DB: přímý dotaz vyřešil `86:f7:56:41:01:d4` a **tiše vrátil
0** pro `ca:8e:1d:ca:bc:af`. Správně přes `affiliated_ap` → obojí 1,
fronthaulový klient 0.

## 19. `999992` — odešlý klient tvrdil, že je připojený

`associated` se zapisuje jako `state != STA_DISCONNECTED` a **jen pro stanice,
které uzel právě hlásí**. Kdo odroamoval, tomu se řádek už nikdy nepřepíše.
`mapc_del_sta()` běží jen když u odhlášení sedí **BSSID i uzel** — a roamující
klient se neodhlašuje vůbec.

Naměřeno: **20 řádků, všechny `associated=1`**, proti třem skutečným
asociacím v celé mesh. x8 samo drželo pět a neobsluhovalo nikoho.

Dvě doplnění, **obě jen shazují příznak, nic nemažou**:

1. **per stanice** — jedna MAC nemůže být na dvou uzlech; hlášení z jednoho
   uzlu činí řádky pod jiným uzlem neplatnými. Tohle jediné dosáhne na uzel,
   který přišel o **všechny** klienty (ten hlásí prázdný seznam a sweep se na
   něm záměrně vrací, aby napůl rozparsovaná CMDU nevymazala tabulku).
2. **per uzel** — koho uzel nehlásí, ten je pryč. Komentář v našem kódu má
   pravdu, že se takové řádky nesmí **mazat** podle jednoho snímku; příznak je
   jiný obchod: přechodné nedohlášení stojí jedno přehození a příští Topology
   Response ho vrátí.

## 20. Ruční úklid dat (jednorázový)

Falešný `sta_mld` + `affiliated_sta` řádek Macu smazán ručně (DB zazálohována
`/etc/mapc/mapc.db.bak-1626`). `925` brání vzniku nových, staré nemaže.
Rozlišovací dotaz na falešná MLD:
```sql
select m.mld_macaddr, (select count(*) from affiliated_sta a
  where a.mld_macaddr=m.mld_macaddr and a.macaddr<>m.mld_macaddr) from sta_mld m;
```
Nula „skutečných noh" = kandidát na falešné MLD.

## 21. `evsrc-check` — třetí verze

Verze 1 počítala sokety → prohlásila mrtvý uzel za zdravý (13 soketů, nula
doručených událostí — hostapd si sokety při náběhu BSS **znovu vytvoří** a
wifimngr zůstane na starých, už odlinkovaných).
Verze 2 porovnávala časy → minula 4g, kde socket **existoval dřív, než na něm
hostapd uměl obsloužit spojení** (3 sokety pro 7 zdrojů, ticho).
**Verze 3 testuje obojí.** Ověřeno: 4g 2→13, 8g ticho, x8 13→14.

## 22. Commity večer

```
a9d7579d6  libwifi 924
3d4c4f642  libwifi 925
3c68d01a8  map-controller 999991
19507bd73  map-controller 999992
e33c9ba    evsrc-check v2 (casy)
+ v3 (obojí)
```

## Poučení dne

**Tři ze čtyř večerních vad byly v kódu, který jsem napsal týž den** — a
všechny vyšly najevo z **jednoho pohledu na tabulku**, ne z testů. Producent
událostí je nová vrstva pravdy: co dřív nikdo nezapisoval, se teď zapisuje
**hodně**, takže se každá nepřesnost v identitě okamžitě znásobí.

⚠️ **`get_clients` na MLD objektu zamlčí legacy klienty.** Celý den jsem jím
hledal, kde kdo je — a hlásil „na 4g není nikdo", zatímco tam byli dva.
Autorita je `iw dev <if> station dump`.
