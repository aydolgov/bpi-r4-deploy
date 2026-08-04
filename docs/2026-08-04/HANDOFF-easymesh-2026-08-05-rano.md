# HANDOFF — EasyMesh R6, ráno 5. 8. 2026

Navazuje na `EasyMesh-2026-08-04/HANDOFF-2026-08-04-odpoledne.md` (podrobnosti a
důkazy) — tenhle soubor je **na start bez diskuze o kontextu**.

Řídicí pravidlo beze změny: **spolehlivost před funkcemi**, včetně opakovaného
testování. Žádné nové funkce, dokud nejsou uzavřené body níže.

---

## 1. CO SE VČERA ZMĚNILO — jednou větou

Klient se do databáze zapíše **z události za ~0,1 s** místo dřívějších
nepředvídatelných **minut**. Producent těch událostí přitom existoval už dřív —
byl to **mrtvý kód**, protože chyběl konfigurační soubor, který nikdo nedodává.

```
klient se připojil / odešel / přeskočil   ~0,1 s   (dřív MINUTY)
RCPI, rychlosti, bajty                    ~5 s     (beze změny, vlastní časovač)
```

---

## 2. STAV ŽELEZA (ověřeno 4. 8. ve 21:1x)

```
bpi-4g  soketů 13  klienti 1  mlo-steerd 0  libwifi 4032ae69  mapc 4acc15b0
bpi-8g  soketů 13  klienti 1  mlo-steerd 0  libwifi 4032ae69  mapc 4acc15b0
bpi-x8  soketů 13  klienti 1  mlo-steerd 0  libwifi 4032ae69  mapc 4acc15b0

num_nodes: 3
topologie:  x8 --(2 hops)--> 8g --(1 hop)--> 4g
```

**13 soketů = zdroj událostí žije.** Bez evmapu jich je 7, s ním 19 (13 soketů).
Rychlá kontrola uzlu:
```sh
P=$(ps w | grep "[/]usr/sbin/wifimngr" | awk '{print $1}' | head -1)
ls -l /proc/$P/fd | grep -c socket        # < 8 == ŠPATNĚ
```

---

## 3. GIT — vše commitnuto a pushnuto

```
iopsys-feed      19507bd73   vetev devel           → woziwrt/devel   ✅
easymesh-shared  9b33a6e     vetev easymesh-shared → origin          ✅
pin v common-easymesh.sh: 19507bd73                                  ✅

TAGY (pushnuté) — ČTYŘI REPA, OBNOVÍ DNEŠEK KOMPLETNĚ:
  iopsys-feed      easymesh-pin-2026-08-04            → 19507bd73   patche
  easymesh-shared  easymesh-2026-08-04                → 6d77ae0     skripty + dokumenty
  universal-new    easymesh-2026-08-04-universal-new  → 684768b     builder + defconfig
  x8-new           easymesh-2026-08-04-x8-new         → 66a3332     builder + defconfig

BUNDLY: VM /home/ipsec/git-backups-2026-08-04/
  iopsys-feed-devel-20260804.bundle    (59 MB)
  easymesh-shared-20260804.bundle
```

**Dokumenty jsou nově v gitu** — `easymesh-shared/docs/2026-08-04/`. Tag tedy
obnoví obojí: co se postavilo **i proč**, včetně měřicích pastí.
Ověřeno obsahem tagu: `evsrc-check` v tagu má md5 `c2880c08da`, **shodné s tím,
co běží na uzlech**.

⚠️ **Buildery byly do 4. 8. večer necommitnuté** a našlo se to až na Petrův dotaz
„jsou buildery taky na gitu?". Chybělo v gitu přesně to, co určuje, co se
postaví:
```
MTK_COMMIT   90323e273792 -> 3a4e2a2511af       (pin MTK feedu)
defconfig    + CONFIG_IEEE1905_CMDU_SA_IS_ALMAC=y
```
Bez toho by dnešní obrazy **nešly z gitu postavit znovu**. Teď commitnuto,
pushnuto a otagováno v obou builder repech.

**Zbývá tam necommitnuté (záměrně, je to mrtvé dřevo):**
`my_files/etc-files/www-cgi/mesh-status` v `universal-new` i `x8-new` — kopie
z 2. 8., kterou **žádný builder nepoužívá** (`common-easymesh.sh` bere výhradně
`easymesh-shared/my_files-easymesh`). A `configs/*.pred-almac` jsou zálohy
z doby před změnou ALMAC. Commitovat zastaralá data by jen zaneslo repo —
buď smazat, nebo nechat být.

⚠️ `easymesh-shared` **do včerejška neměl tagy vůbec** a feed měl poslední
z 3. 8. Od teď tagovat po každém posunu pinu — je to poslední článek receptu
z [[project_easymesh_feed_clean_eats_patches]], který jsme vynechávali.

Obě repa `git status` prázdné. `my_files` == `files/` v obou stromech
(`evsrc-check` md5 `c2880c08da` všude i na uzlech).

⚠️ **NAFLASHOVANÝ OBRAZ MÁ `evsrc-check` VERZI 3, ne 4.** Na uzlech běží v4,
protože jsem ji nahrál přes `ssh cat`; je v `/etc/sysupgrade.conf`, takže
sysupgrade přežije. **Příští build ji už bude mít v obrazu.**

---

## 4. VČEREJŠÍ PATCHE

| patch | co dělá | HW |
|---|---|---|
| `libwifi 922` | producent `wifi.sta` z hostapd ctrl soketu, per linka, s MLO poli | ✅ |
| `libwifi 923` | BTM odpověď jako událost `btm-resp` | ✅ |
| `libwifi 924` | BSS se hledá **podle jména**, ne `bssid[0]` | ✅ |
| `libwifi 925` | legacy klient na MLD AP **není MLD** | ✅ |
| `map-agent 99996` | u `btm-resp` dohledat AP podle **BSSID** | ✅ |
| `map-controller 999991` | `sta_mld.is_bsta` se odvodí, nebylo nikdy nastaveno | ⏳ částečně |
| `map-controller 999992` | odešlý klient přestane tvrdit `associated=1` | ✅ 4g, 8g |
| `wnm-enable` (S19) | `bss_transition=1` — bez toho hostapd **zahodí každou BTM odpověď** | ✅ |
| `wifi-evmap` (S94) | vyrobí `/etc/wifi.json`, **jedna položka NA LINKU** | ✅ |
| `evsrc-check` (S99) | ověří, že se wifimngr **opravdu připojil**; až 3 pokusy | ✅ |
| `91-mlo-steerd-off` | mlo-steerd zůstává v obrazu, nespouští se | ✅ |

---

## 5. KROKY NA ZÍTŘEK — v tomhle pořadí

### KROK 0 — vyhodnotit NOČNÍ BĚH (~12 h v provozu)

Mesh běží od 4. 8. cca 21:00 nepřetržitě. **Tohle je první dlouhý soak test
událostní cesty a nedá se nasimulovat** — kontrolovat dřív, než se cokoli sáhne.

```sh
# 1) drží se zdroj událostí, nebo se rozpadl? (nejdůležitější)
P=$(ps w | grep "[/]usr/sbin/wifimngr" | awk '{print $1}' | head -1)
echo "$(uname -n) soketů=$(ls -l /proc/$P/fd | grep -c socket) uptime_wifimngr=$(ps -o etime= -p $P 2>/dev/null)"
#    13 = OK. Méně = zdroj během noci umřel → PODSTATNÝ NÁLEZ, zapsat.

# 2) nezasahoval hlídač opakovaně? (znamenalo by opakovaný rozpad)
logread | grep -c evsrc-check
logread | grep evsrc-check | tail -5

# 3) neroste počet fd? (riziko ENFILE, které jsem pojmenoval a NEOVĚŘIL)
ls /proc/$P/fd | wc -l

# 4) nezaplavil log? (922 emituje synchronně v drénovací smyčce)
logread | grep -c "wifi.sta"

# 5) přežil stav?
ls /etc/rc.d/ | grep -c mlo-steerd        # 0
grep -c bss_transition /var/run/hostapd-*.conf | head -3
```

**Hotovo když:** všechny tři uzly mají 13 soketů, `evsrc-check` zasáhl nejvýš
jednou (při bootu) a počet fd je stabilní.

**Když ne:** je to nejcennější nález dne — zapsat přesně, kdy a co, **než**
se cokoli restartuje. Stav po rozpadu je jediný důkaz, který budeme mít.

### KROK 2 — dokončit úklid databáze (hlavní úkol dne)

**Problém:** uzel, jehož `stalist` vidí controller jako **prázdný**, se nedá
uklidit — sweep se na prázdném seznamu záměrně vrací (ochrana proti napůl
rozparsované CMDU). x8 tak drží **5 mrtvých adres** s `associated=1`, přestože
na něm iPhone reálně je.

```
skutečné nohy iPhonu na x8:  5a:8d:f0:aa:76:51  1a:84:15:fa:ba:53  6a:a3:72:94:0f:84
v affiliated_sta:            ANO
v sta pod uzlem x8:          ŽÁDNÁ   ← proto je stalist prázdný
```

Pravidlo „jedna MAC nemůže být na dvou uzlech" (patch 999992, část 1) jim
nepomůže — jsou to adresy, které už **nikdy nikdo nenahlásí**.

**Návrh k rozmyšlení, ne k okamžitému psaní:** živý seznam uzlu odvodit nejen ze
`sta`, ale i z `affiliated_sta` podle BSSID, která tomu uzlu patří. Tím by x8
přestalo vypadat prázdné a sweep by se rozjel.

**Hotovo když:** `select agent_almac, count(*), sum(associated) from sta group
by agent_almac` odpovídá realitě na **všech třech** uzlech (včera to sedělo na
4g a 8g, ne na x8).

### KROK 3 — přeměřit propustnost (ranní čísla jsou k ničemu)

Včerejší dvouskok **604 → 136 Mbit/s** a úvahy kolem antény x8 vznikly, když
mlo-steerd administrativně vypínal pásma. Teď je vzduch čistý.

⚠️ **Neměřit skrz měřené médium** — 4. 8. jsem řídil test přes ssh z Macu, který
sám visel na měřené lince, a vyšla čtyřnásobně jiná čísla, která zněla
věrohodně. Potřebuje Petrovu součinnost.

**Hotovo když:** máme čísla pro jeden a dva skoky, změřená mimo řídicí kanál.

### KROK 4 — doměřit `btm_success`

Včera prošel **první skutečný steer** (`status_code=0`, klient přijal a přešel
z 8g na 4g), ale čítač se nezvedl, protože jsem poslal žádost **bez seznamu
kandidátů** a klient vrátil `status_code=6` = „nemám vhodného kandidáta".

```sh
# vzor funkčního steeru (soused se bere z rrm_nr_get_own cílového uzlu)
ubus call hostapd.ap-mld-1 bss_transition_request \
  '{"addr":"<sta>","disassociation_imminent":true,"disassociation_timer":30,
    "validity_period":100,"abridged":true,"dialog_token":31,
    "neighbors":["<hex z rrm_nr_get_own>"]}'
```
**Hotovo když:** `btm_success` se po úspěšném steeru zvedne.

### KROK 5 — zbytek fáze 1

Sousedé v `map.agent status`; ztráta DHCP po roamingu (24–30 s bez IP);
držené asociace ~164 s (`ap_max_inactivity`); únik `stamldlist`.

### KROK 6 — teprve pak nové funkce

Politika backhaul steeringu, pohyblivá gateway. **Ne dřív.**

---

## 6. MĚŘICÍ PASTI — přečíst PŘED prvním měřením

- ⚠️ **`ubus call hostapd.<mld> get_clients` ZAMLČÍ legacy klienty.** Celý den
  jsem jím hledal klienty a tvrdil „na 4g není nikdo", zatímco tam byli dva.
  **Autorita je `iw dev <if> station dump`.**
- **iOS mění afilované MAC při KAŽDÉ reasociaci.** Nedají se zapamatovat ani
  odvodit — jen přečíst z události. Proto seznam „departed" roste po třech.
- **`pgrep -f <vzor>` i `grep -c "[v]zor"` chytají vlastní shell.** Třikrát mě
  to včera svedlo. Používat `ps w | grep "[v]zor"` a **vypsat řádky**.
- **BusyBox `date +%s%N` vrací jen sekundy** — deset měření mi vyšlo „0 ms".
- **`/proc/net/dev` má na 2. pozici bajty, ne pakety** — z toho mi vyšla
  „bouře 3868 paketů/s", ve skutečnosti jich bylo 9.
- **`dbg()` je vázané na log level** — nula výskytů neznamená nic bez kontrolního
  výpisu ze stejné funkce.
- **Nezachycení události neznamená, že se nestala.** BTM odpověď nechytil ani
  ctrl socket, ani ubus — hostapd ji zahodil dřív. Ukázal to až `log_level DEBUG`.
- **Zsh na Macu**: apostrof v textu (`agent's`) rozbije uvozovky, `socket(s)`
  rozbije globbing. Delší texty posílat **souborem**, ne inline.
- **`pkill -f <vzor>` zabije i vlastní ssh sezení**, když vzorec sedí na příkaz.

---

## 7. CO SE VČERA UKÁZALO JAKO PODSTATNÉ

**Tři ze čtyř večerních vad byly v kódu napsaném týž den** — a všechny vyšly
najevo z **jednoho pohledu do tabulky `mesh-status`**, ne z testů a ne z logů.
Producent událostí je nová vrstva pravdy: co dřív nikdo nezapisoval, se teď
zapisuje hodně, takže se každá nepřesnost v identitě okamžitě znásobí.

**`evsrc-check` jsem psal čtyřikrát**, pokaždé kvůli skutečnému selhání:
1. spící registrace (1 socket)
2. hostapd socket **nahradil** → počet sedí, doručování mrtvé
3. restart přišel moc brzy → 1 zdroj ze 7, jen `link0`
4. → testovat **čas i počet**, po restartu **ověřit**, až 3 pokusy

**Dvě věci mimo C rozhodly o všem:** `/etc/wifi.json` (bez něj se nezaregistruje
ani jeden zdroj) a to, že v něm musí být **jedna položka na linku** — wifimngr
hlídá jen `socks[0]`, což je rodičovský socket, na který hostapd nic neposílá.

---

## 8. JAK SE VRÁTIT ZPĚT

Pin je **hash**, ne větev, a leží v `common-easymesh.sh`, které je samo v gitu.
Vrácení `easymesh-shared` na starší commit tedy **automaticky vrátí i feed**.

```sh
# vypnout jen událostní cestu, zbytek nechat
rm /etc/wifi.json && /etc/init.d/wifimngr restart      # zpět na polling

# vrátit mlo-steerd
/etc/init.d/mlo-steerd enable && /etc/init.d/mlo-steerd start

# vypnout hlídač
rm /etc/rc.d/S99evsrc-check
```

⚠️ `iopsys-feed` má **dva remoty** — `origin` je upstream iopsys (tam se
nepushuje), náš je `woziwrt`.
