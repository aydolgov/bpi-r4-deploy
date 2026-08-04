# Plán: pomalá a systematická práce — od 4. 8. 2026 odpoledne

> **Řídicí pravidlo (Petr, 4. 8.):** žádné rozšiřování funkcionality na úkor
> spolehlivosti. Spolehlivost je základ všeho, včetně důsledného a opakovaného
> testování.
>
> Z toho plyne pořadí níže: **nejdřív dokončit rozdělané, pak prověřit, teprve
> potom stavět nové.** Backhaul steering a pohyblivá gateway jsou nové funkce —
> jsou až ve fázi 5, ne dřív.

---

## Jak číst tenhle plán

Každý krok má **co**, **proč** a **jak poznám, že je hotový**. Bez toho třetího
se kroky nikdy neuzavírají a hromadí se rozdělaná práce — to je přesně stav,
ze kterého jsme dnes vylezli.

⚠️ **Kroky se nepřeskakují kvůli tomu, že další vypadá zajímavěji.**

---

# FÁZE 0 — Zbytek dnešního odpoledne

### 0.1 Roaming, tentokrát pořádně
**Co:** Změřit přechod klienta mezi **x8 a 8g** — tedy tam, kde je pokrytí
souvislé. Chodit tam a zpět, pomalu, s běžícím videem.

**Proč:** Dnešní pokus mísil dvě různé věci. Přechod `x8 → 8g` byl skutečný
roaming a vypadal dobře; úsek `8g → 4g` byl **90 s bez signálu**, což roaming
není. Nevíme, jestli video přeskočilo kvůli roamingu, nebo kvůli té díře.

**Hotovo když:** víme, jestli je v přechodu `x8 ↔ 8g` mezera v konektivitě.
- **mezera není** → roaming funguje, dnešní výpadek byl pokrytím
- **mezera je** → máme vadu a jde do fáze 1 jako priorita

**Měřit:** vzorkování po 1 s na obou uzlech + `ping -i 0.2` z telefonu, ať se
mezera zachytí i když je krátká.

---

### 0.2 Vyhodit vlastní diagnostiku z produkčního obrazu
**Co:** Odstranit ze série a z obrazu:
- `map-agent/9996-TEMP-e2emit-trace`
- `map-controller/9998-TEMP-e2trace`
- `uci-trace-shim` instalovaný jako `/usr/sbin/uci`
- `S02mld-watch`

**Proč:** `E2TRACE` loguje na úrovni `err()` při **každé** Topology Response,
shim forkuje proces navíc při **každém** volání `uci` na **každém** uzlu a
přisypává do logu bez rotace. Měříme přes vlastní instrumentaci. Autoři obou
patchů napsali „až bude viník znám, pryč" — a je znám.

**Hotovo když:** `logread | grep -E "E2EMIT|E2TRACE"` je prázdné a
`head -1 /usr/sbin/uci` není shell skript.

---

### 0.3 Opakované ověření dnešních oprav
**Co:** Každou dnešní opravu ověřit **znovu a po restartu**, ne jednou.

| co ověřit | jak |
|---|---|
| per-link `rcpi` v `affiliated_sta` | 5× v odstupu, plus po rebootu controlleru |
| `99994` (autor místo relaye) | že se `is from … relayed by …` objevuje opakovaně |
| `99995` (per-link BSSID) | že `releasing … absent from` zůstává na nule |
| DB vs realita | 3× v odstupu hodiny, ne jeden snímek |

**Proč:** každá dnešní oprava je prokázaná **jednou**. To není spolehlivost,
to je „jednou se to povedlo". Tři z dnešních chybných závěrů vznikly z jediného
vzorku.

**Hotovo když:** existuje zápis s opakovanými měřeními, ne s jedním.

---

# FÁZE 1 — Dokončit „opraveno 1 z N"

> Recenze našla systémový vzor: série opakovaně opravila **jedno místo z N**
> u vícemístného problému. Dnešek to nezávisle potvrdil třikrát. Tohle je
> nejlevnější práce, jakou máme — mechanismus už známe, jen není dotažen.

Pořadí podle poměru dopad/cena:

### 1.1 `dl_est_thput` / `ul_est_thput` — zero-clobber (recenze 1.5)
Identická vada dva řádky **nad** `rcpi`, které jsme opravili v `99993`.
Nezměřený link vynuluje propustnost v RAM i v DB → steering dostává nuly.
**Ověřit:** MLO klient, sledovat `est_mac_rate_*` v `sta`; skáče na 0 = potvrzeno.

### 1.2 BTM response se zahazuje (recenze 1.1) — kandidát na `btm_success = 0`
Patche `9999`/`99993` přepnuly **request** na MLD, ale **response** se dál
resolvuje per-link ifname → lookup vrátí NULL a report se nikdy neodešle.
**Ověřit:** `ubus monitor | grep btm-resp` během steeru; nese-li MLD jméno,
potvrzeno. ⚠️ **potřeba klient, který BTM umí** — Mac hlásí `dot11v_btm: false`.

### 1.3 Origin: dotáhnout na zbylé handlery (recenze 1.3, 1.15)
`99994` opravil Topology Response. Zbývají `handle_topology_notification`
(roaming!), AP Capability Report, AP Metrics. Idiom je hotový — handler najde
autora z TLV a přepíše `cmdu->origin`.
**Pozn.:** `99996` už opravil ACS/DFS adresáta, na železe neověřeno.

### 1.4 `99995` na zbylá pole (recenze 1.8)
Ochránili jsme `bssid`; `channel`, `ssid`, `bssload`, `max_sta` se z MLD masteru
přepisují dál.

### 1.5 Mazání v DB (recenze 1.13)
`mapc_del_*` volané z ageoutu. Dnes **nic nemaže nic** → seznam odešlých roste
donekonečna a vyřazený uzel po každém bootu ožije.

### 1.6 Únik `stamldlist`
`cntlr_free_apmld_list` uvolní `aplist` a `ttlmlist`, ale ne `stamldlist` —
každá Topology Response je leakuje.

### 1.0 🔴 Registrace klienta u agenta trvá MINUTY — kořen zastaralé DB
**PRIORITA. Změřeno 4. 8. při procházce s telefonem.**

Celý řetěz, změřený článek po článku:

```
1. klient odejde z x8    → x8 drží MRTVOU asociaci ~3 min
                            (inactive time 164 480 ms, connected 198 s)
                            jádro a HAL ji drží; agent ji pustí správně (99991)
2. klient přijde na 4g    → agent 4g ho registruje AŽ ZA MINUTY
                            (dorazil 11:00:21, v 11:05 agent stále 0,
                             později už ano)
3. mezitím                → platí poslední hlášení, tedy STARÝ uzel
4. DB ukazuje špatný uzel → tabulka to věrně opakuje
```

**Úzké hrdlo je krok 2, ne synchronizace DB.** Zrychlovat sync nepomůže —
posílal by rychleji tatáž zastaralá data. ⚠️ **Tohle mění prioritu fáze 2.2:**
sync na notifikaci má smysl až potom, co agent ví včas.

**Směr:** agent má klienta zaregistrovat **v okamžiku asociace** (událost
z hostapd), ne až ho najde obchůzka `refresh_bssinfo` (60 s, a evidentně
i déle). `agent_ubus_events.c` existuje — ověřit, jestli se událost odebírá
a proč nevede k okamžitému `wifi_add_sta`.

**Vedlejší nález:** `wifi_ubus_get_assoclist` vrací **chybu 4** na
`wlan0-1`, `wlan1-1`, `wlan2-1` (backhaulové linky) → `agent_ap_add_stations:
failed to get assoclist`, 30× v logu. Na těch linkách klienti nejsou, takže to
zřejmě neškodí — ale je to hlášená chyba, kterou nikdo neřeší.

**Hotovo když:** po roamingu má nový agent klienta **do 10 s** a DB do 15 s,
ověřeno opakovaně na několika přechodech.

### 1.7 Sousedé v `map.agent status` (bod 5 z ranního handoffu)
`neighbor` má **0 řádků**, přestože rádio sousedy slyší. Nedotčeno.

---

### 1.8 🪰 „No internet" a zaseknuté video při přechodu mezi uzly — ZADÁNO PETREM

**Příznak (Petr, 4. 8.):** občas při přechodu od routeru k routeru vyskočí
*no internet connection*, video se zastaví a **obnoví se až po vypnutí
a zapnutí WiFi**. Nestane se to vždycky.

**Změřeno:**
- **fdb neproplachuje nikdo** — ani map-agent, ani map-controller, ani deploy
  skripty (ověřeno grepem). Mesh se spoléhá výhradně na to, že se mosty naučí
  z provozu.
- `ageing_time` = **300 s** na všech uzlech
- záznamy nesou příznak **`offload`** → přeposílá hardware, ne softwarový bridge

**Tři kandidáti, seřazení podle pravděpodobnosti:**

1. **Hardwarový offload drží zastaralou cestu.** Softwarový most se novou cestu
   naučí, offloadovaná tabulka si drží starou → provoz do prázdna, vyléčí to až
   plná přeasociace. Sedí na „nestane se to vždycky" (závisí na časování)
   i na „pomůže jen off/on".
2. **iOS si síť zabouchne sám.** Po přechodu ověřuje internet dotazem na Apple;
   když jednou selže, označí síť za bez internetu, **přestane ji používat**
   a sám se nevrátí. Spouštěč je ale náš — krátká mezera při roamingu.
3. **Zastaralý záznam s 300s životností.** Nejméně pravděpodobné (provoz od
   klienta ji obvykle přepíše dřív), ale **u mlčícího klienta** — video má
   nabuffrováno — ne.

**Jak je rozlišit** (rozšíření testu 0.1):
`ping` po 200 ms během přechodu + současně sledovat fdb na všech třech uzlech.

| pozorování | závěr |
|---|---|
| ztráta pár paketů, fdb se hned opraví | normální roaming, viník iOS (bod 2) |
| delší ztráta, fdb ukazuje špatný port | bod 1 nebo 3 — a víme na kterém uzlu |
| fdb správně, přesto ztráta | je to **pod** bridgem, tedy offload (bod 1) |

**Levná sonda:** snížit `ageing_time` z 300 s na 30 s. Není to oprava příčiny,
ale zkrátí nejhorší případ desetkrát a hned ukáže, jestli je zastaralost vůbec
ve hře. Nepomůže-li vůbec, bod 3 se škrtne.

**Hotovo když:** víme, který z těch tří to je, a máme to doložené měřením —
ne odhadem.

---

#### ✅ PROKÁZÁNO 4. 8. — vada má jméno a záznam: ztrácí se DHCP odpověď

Z logu `dnsmasq` na 4g při Petrově přechodu k x8:

```
10:42:09  DISCOVER → OFFER
10:42:13  DISCOVER → OFFER      ← znovu
10:42:22  DISCOVER → OFFER      ← znovu
10:42:32  DISCOVER → OFFER      ← znovu
10:42:33  REQUEST  → ACK        ← adresu dostal až po 24 s

10:43:56  DISCOVER → OFFER ×4   (čtyři pokusy v jedné vteřině)
10:44:26  REQUEST  → ACK        ← až o 30 s později
```

**Čti to takhle:** klient se ptá, server odpovídá, **odpověď k němu nedorazí**.
Kdyby ji dostal, hned následuje `REQUEST`. Místo toho čeká **24 a 30 vteřin**
bez platné IP — a to JE ta hláška *no internet connection*.

`DISCOVER` jde všesměrově, takže k serveru dorazí vždy. `OFFER` se posílá
**adresně zpět klientovi**, a k tomu musí most vědět, kterým portem se k němu
chodí. Po přechodu to ještě neví, nebo ví špatně. Odtud i to „nestane se to
vždycky" — záleží, jestli se most přeučí dřív, než odpověď přijde.

**Zjištěno k prostředí:** WED a PPE (`wed0-2`, `mtk_ppe`) jsou aktivní,
záznamy v `bridge fdb` nesou příznak `offload`. PPE tabulka ale v době kontroly
**žádný záznam pro klienta neměla** (5 záznamů celkem), takže tahle konkrétní
tabulka starou cestu nedrží. Firewall `flow_offloading` je vypnutý.

#### Měření, které to rozhodne

Při přechodu odposlouchávat DHCP **na uzlu, kam klient přijde**:
```
tcpdump -i any -n -e "port 67 or port 68"
```

| pozorování | závěr |
|---|---|
| odpověď na uzel **dorazí**, ke klientovi ne | vada je na posledním skoku (WiFi/hostapd) |
| odpověď na uzel **vůbec nedorazí** | vada je v cestě přes mesh (fdb/offload) |

**Poznámka k `ageing_time`:** 4. 8. sníženo živě z 300 s na 30 s na všech třech
uzlech jako sonda. **Není to oprava a nepřežije reboot** — schválně. Ukáže jen,
jestli je zastaralost vůbec ve hře.

---

# FÁZE 2 — Čerstvost dat

> Podklad: `NAVRH-zivy-model-vs-db-2026-08-04.md`. Rozhodnutí padlo,
> tady se provádí.

### 2.1 Časové razítko na každý řádek
`sta` dnes nemá žádné (`conn_time` je něco jiného). Bez razítka je zastaralost
**neviditelná**.

### 2.2 Synchronizovat i na Topology Notification
Dnes se sync váže hlavně na periodickou Topology Response (~60 s). Notifikace
nese asociaci a odpojení — zkrátí reakci na roaming z minut na vteřiny.

**Změřeno 4. 8. jako důkaz, že to je potřeba:** po přechodu klienta na 4g
ukazovala `sta_mld` pořád 8g, **stará 209 s**.

Pozn.: ta cesta se stejně opravuje ve fázi 1.3.

### 2.3 Ukládat, na které lince sedí ne-MLO klient
`sta.bssid` je adresa AP-MLD → pásmo se nedá určit. Tabulka proto musí psát
„band unknown", což je poctivé, ale zbytečné.

**Hotovo když:** po roamingu je DB shodná s realitou **do 10 s**, ověřeno
opakovaně.

---

# FÁZE 3 — Metodika měření

> Dnešek ukázal, že bez tohohle si měříme vlastní chyby.

### 3.1 Skript na propustnost, který se dá věřit
- řízení **mimo měřené médium** (spustit odpojeně, číst potom)
- **klidná síť** — zaznamenat, co běželo, ne předstírat, že nic
- **aspoň 5 opakování** s rozptylem, ne jedno číslo
- měřit i **airtime a retries**, ne jen propustnost

### 3.2 Zjistit, jestli airtime rozhoduje víc než RSSI
Dnešní náznak: nejlepší signál v síti (−44 dBm) měl v prvním měření nejhorší
propustnost. Kdyby se to potvrdilo, změní to podobu celé steeringové politiky —
a data driver má, jen je nesbíráme.

---

# FÁZE 4 — Prostředí a odolnost

### 4.1 Chytré zásuvky na vzdálené uzly
**Jediná porucha, po které je bezdrátový uzel nedosažitelný pro oba** (semafor
MT7996, `probe failed -11`). Léčí ji jen delší odpojení od proudu — což zásuvka
umí a ruční cvaknutí často ne.

### 4.2 Anténa 6 GHz na x8
Řetěz 0 je 24–30 dB dole. **Nezhoršuje jen linku k x8** — hypotéza z dnešního
měření říká, že bere prostředníkovi možnost přijímat na jednom pásmu a posílat
na druhém, a stojí tak propustnost **celého dvouskoku** (604 → 136 Mbit/s).
**Ověření po opravě:** zopakovat test a porovnat těch 136.

### 4.3 Pokrytí mezi místnostmi
Změřeno: úsek `8g → 4g` má **90 s bez signálu**. Rozhodnout, jestli to řešit
posunutím 8g, nebo to přiznat jako hluché místo. **Obojí je legitimní — jen ať
je to volba, ne překvapení.**

### 4.4 Retry fix na semafor
`mt7996_load_patch()`, retry po 500 ms. Nepokryje zaseknuté MCU, ale pokryje
závod, kdy semafor ještě uvolňuje předchozí probe. Jediná věc, která snižuje
riziko **u zdroje**.

---

# FÁZE 5 — Teprve teď nové funkce

> Až bude základ prověřený. Ne dřív.

### 5.1 Politika backhaul steeringu
Aktuátor je **hotový a prokázaný** (`steer_backhaul`, dnes použit 2×). Chybí
rozhodovací smyčka. Musí mít:
- **hysterezi** — přeparkovat až při trvalém rozdílu, ne při výkyvu
- **ochranu potomků** — přesun uzlu, na kterém visí jiný, počítá s celou větví
- **žádné smyčky** — cíl nesmí být vlastní potomek

Vstupy ze **živého modelu**, záznam rozhodnutí do **DB** (fáze 2 je předpoklad).

### 5.2 Pohyblivá internetová gateway
Plovoucí IP (VRRP/keepalived) + DHCP server u ní. **Souvisí s 5.1**: backhaulový
strom se má kořenit tam, kde je WAN — takže „kdo drží WAN" je vstup té politiky,
ne samostatná věc.

---

# Průběžné — hygiena, ne fáze

- **Zálohy a push** po každém dni práce. 4. 8. ráno leželo 91 commitů jen na VM1.
  ⚠️ `iopsys-feed` má dva remoty a `git log @{u}..HEAD` **lže** — ověřovat proti
  `woziwrt/devel`.
- **Pin feedu v `common-easymesh.sh`** bumpnout po každém commitu, jinak ho
  builder odstřihne a build nic neřekne.
- **`my_files` do `files/`** ručně po každé úpravě — partial build to nekopíruje.
- **Slepá recenze** po větší změně, ne průběžně. Zadání je hotové.

---

# Měřicí disciplína — tři dnešní lekce

1. **`dbg()` je vázané na úroveň logování.** Nula výskytů neznamená nic, dokud
   nemáš **kontrolní `dbg()` ze stejné funkce**, který teče.
2. **Jeden snímek není měření.** Třikrát dnes jsem z předčasného snímku vyvodil
   nález, který se rozpustil. Časová řada, nebo mlčet.
3. **„Měř na čistých configech" platí i na médium.** Řízení testů přes měřenou
   síť dalo čtyřnásobně jiná čísla — a znělo to věrohodně.

---

*Souvisí: `VICTORY-realna-mesh-2026-08-04.md` (stav a čísla),
`HANDOFF-easymesh-2026-08-04-vecer.md` (rozpracované),
`NAVRH-zivy-model-vs-db-2026-08-04.md` (rozhodnutí k fázi 2),
`PATCH-REVIEW-EASYMESH-2026-08-04.md` (zdroj fáze 1).*
