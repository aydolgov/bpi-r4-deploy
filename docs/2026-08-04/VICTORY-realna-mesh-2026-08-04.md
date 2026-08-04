# 🏔️ Milník: první topologicky reálná mesh — 4. 8. 2026

> Do dneška to byly tři routery vedle sebe na stole, které se navzájem přeslechly.
> Od dneška je to mesh přes tři místnosti, kde se každý skok musí odpracovat.
>
> Všechna čísla níže jsou **naměřená na železe** v den vzniku dokumentu.

---

## Topologie

```
                internet
                    │
              ┌─────┴──────┐
              │   bpi-4g   │  controller + kolokovaný agent + gateway
              │  (stůl)    │  jediný datový kabel v celé síti
              └─────┬──────┘
                    │  5 GHz −44 dBm · 6 GHz −58 dBm
                    │  1152 Mbit/s · NSS 2
              ┌─────┴──────┐
              │   bpi-8g   │  agent, depth 1
              │ (místnost 2)│  jen napájení
              └─────┬──────┘
                    │  5 GHz −52 dBm · 6 GHz −71 dBm
                    │   864 Mbit/s · NSS 1–2
              ┌─────┴──────┐
              │   bpi-x8   │  agent, depth 2
              │ (místnost 3)│  jen napájení
              └────────────┘
```

**Řetěz vznikl sám** po zapnutí na cílových místech — nebyl vynucen steeringem.

---

## Uzly

| | bpi-4g | bpi-8g | bpi-x8 |
|---|---|---|---|
| role | controller + agent | agent | agent |
| AL-MAC | `86:f7:56:41:01:d3` | `ca:8e:1d:ca:bc:ae` | `e6:a9:d2:c1:98:3f` |
| ap-mld-1 (fronthaul) | `7e:04:1c:81:7c:2e` | `3a:fb:2f:94:51:7b` | `00:0c:43:26:60:10` |
| ap-mld-2 (backhaul) | `86:f7:56:41:01:d4` | `ca:8e:1d:ca:bc:af` | `e6:a9:d2:c1:98:40` |
| bsta-mld-3 | — | `3e:fb:2f:94:72:7b` | `06:0c:43:26:81:10` |
| depth | 0 | 1 | 2 |
| mesh IP | `10.10.10.1` | `10.10.10.2`* | `10.10.10.3`* |
| datový kabel | **ano** | ne | ne |

\* pozn.: `10.10.10.2` = x8, `10.10.10.3` = 8g

Všechny tři: `mapcontroller 3f0905c0`, `mapagent c9f80a20`, jedno wiphy (`phy0`)
se třemi linkami — to je MLO model, ne chybějící rádia.

---

## Naměřené linkové rozpočty

### 4g → 8g

```
Link 0  5 GHz 160 MHz   -44 [-55, -50, -45] dBm   tx 1152.8 Mbit/s  EHT-NSS 2
Link 1  6 GHz 320 MHz   -58 [-61, -63, -63] dBm   rx 2305.6 Mbit/s  EHT-NSS 2
```
Zdravé. Řetězce vyrovnané, obě nohy nesou provoz.

### 8g → x8

```
Link 0  5 GHz 160 MHz   -52 [-61, -57, -54] dBm   rx 2161.3 Mbit/s  EHT-NSS 2
Link 1  6 GHz 320 MHz   -71 [-87, -72, -77] dBm   tx  288.2 Mbit/s  EHT-NSS 1
```
Provoz veze 5 GHz, rezerva ~18 dB do kritické hranice. 6GHz noha je navázaná,
ale na hraně — **a víme přesně proč**, viz omezení níže.

---

## 📊 Propustnost

### Cena druhého skoku — hlavní výsledek

Měřeno stahováním z HTTP endpointu (`/cgi-bin/dl`, sype nuly), takže se měří
**mesh cesta, ne internet**. Zátěž i odečet běží na routerech, řídicí spojení
během měření mlčí.

| cesta | celkem | 5 GHz | 6 GHz |
|---|---|---|---|
| **x8 → 8g** (jeden skok) | **604 Mbit/s** | 547 | 56 |
| **x8 → 4g** (dva skoky) | **136 Mbit/s** | 105 | 30 |

**Druhý skok stojí mnohem víc než polovinu — zbyde 22 %, tedy ~4,4× zpomalení.**
Klasické pravidlo „relay ubere polovinu" je tedy u nás **optimistické**, ne
pesimistické.

Obě MLO nohy přitom nesou naráz i pod plnou zátěží — 6 GHz přidává k pětce
zhruba třetinu navíc. To je přesně to, kvůli čemu MLO na backhaulu je.

### Hypotéza, proč je to horší než teorie

⚠️ **Hypotéza, ne prokázaný fakt.**

8g jako prostředník **přijímá od 4g na obou pásmech** (naměřeno 99 + 84 Mbit/s).
Dál k x8 ale může posílat prakticky jen po **5 GHz**, protože x8 má 6 GHz kvůli
[vadné anténě](#-známá-omezení) mimo hru. Pětka na 8g tedy dělá obojí — příjem
i vysílání — a právě tam vzniká to dělení vzduchu. Šestka mezitím přinese data,
která se nemají jak předat dál.

⇒ **Ta vadná anténa nezhoršuje jen linku k x8. Zhoršuje propustnost celého
řetězu**, protože bere prostředníkovi možnost přijímat na jednom pásmu a
posílat na druhém.

**Jak to ověřit:** až bude anténa opravená, zopakovat tenhle test a porovnat
těch 136 Mbit/s. Kdyby hypotéza platila, mělo by to znatelně stoupnout.

### ⛔ Dřívější pokus přes iperf3 — NEPOUŽITELNÝ

První měření dne bylo **metodicky vadné** a je poučnější než jeho čísla:

| spoj | běh A | běh B |
|---|---|---|
| 8g → 4g | 106 Mbit/s | 394 Mbit/s |
| x8 → 8g | 349 Mbit/s | 83,8 Mbit/s |

Rozptyl **až čtyřnásobný, v obou směrech**. Z běhu A jsem vyvodil „úzké hrdlo je
8g→4g" a „silná asymetrie" — běh B obojí vyvrátil. Tři chyby:

1. **Měřil jsem přes médium, které měřím.** Řízení šlo z Macu, který je klientem
   na 8g. Odhalila to Petrova otázka „jak se vlastně na routery připojuješ", ne
   ta čísla — ta vypadala věrohodně.
2. **Síť nebyla klidná** — video na iPhonu přes x8, starý iMac na 2,4 GHz
   (**pomalý klient bere víc airtime na stejný objem dat** než rychlý).
3. **Jeden 10s běh je vzorek, ne měření.**

Poučení: *měř jen na čistých configech* platí i na **médium**, nejen na
konfiguraci.

### Fronthaul (jen orientačně)

| klient | uzel | vyjednaná rychlost | signál |
|---|---|---|---|
| iPhone (MLO, 6 GHz) | x8 | 2401,9 Mbit/s | −45 dBm |
| iMac (2,4 GHz, **stará karta**) | 8g | tx 72,2 / rx 52,0 | −60 dBm |
| Watch | 8g | tx 1,0 / rx 13,0 | −66 dBm |

⚠️ **Vyjednané kapacity, ne propustnost.** U iMacu naměřeno 11,8/27,7 Mbit/s —
ale to je limit **staré karty klienta**, ne mesh sítě.

### Co zbývá doměřit

- **airtime a retries** — dnešek naznačil, že rozhodují víc než RSSI
  (nejlepší signál v síti měl nejhorší propustnost v prvním, vadném měření)
- opakování s rozptylem, ne jedno číslo na spoj
- totéž po opravě antény, jako kontrola hypotézy výše

### Fronthaul (jen orientačně)

| klient | uzel | vyjednaná rychlost | signál |
|---|---|---|---|
| iPhone (MLO, 6 GHz) | x8 | 2401,9 Mbit/s | −45 dBm |
| iMac (2,4 GHz, **stará karta**) | 8g | tx 72,2 / rx 52,0 | −60 dBm |
| Watch | 8g | tx 1,0 / rx 13,0 | −66 dBm |

⚠️ To jsou **vyjednané kapacity, ne propustnost**. U iMacu naměřeno 11,8/27,7
Mbit/s — ale to je limit toho klienta (stará WiFi karta na 2,4 GHz), **ne
limit mesh sítě**. Nečíst jako výkon infrastruktury.

---

## 🏆 Co se tím poprvé podařilo

### Per-link kvalita signálu MLO klienta v databázi

iPhone na 4g, tři linky, každá jinak daleko od reality. **Controller poprvé
neuchovává jedno číslo za klienta, ale hodnotu pro každou nohu zvlášť:**

| linka | pásmo | rádio (libwifi) | DB `affiliated_sta.rcpi` | přepočet |
|---|---|---|---|---|
| 0 | 2,4 GHz | −55 dBm | 110 | **−55** ✓ |
| 1 | 5 GHz | −68 dBm | 84 | **−68** ✓ |
| 2 | 6 GHz | −75 dBm | 68 | **−76** ✓ |

Shoda na desetinu, a hodnoty **přežijí opakovanou Topology Response**.

To je podklad, na kterém se steering může rozhodovat podle toho, **která noha
stojí za to** — ne podle průměru za celého klienta.

### Databáze souhlasí s realitou i na dvouskoku

```
             realita (iw)              DB agent        DB topology_link
8g           ← 4g                     ✓ depth 1        ✓ depth 1
x8           ← 8g (ca:8e:1d:ca:bc:af) ✓ depth 2        ✓ depth 2 pod 8g

apmld 6/6 se správnými vlastníky · affiliated_ap 15/15 · bss 5/5/5
bstamld: každý agent pod svou vlastní adresou
```

A že to dělá patch, ne náhoda:
```
is a relay; TLV says …                                    (99992)
is from e6:a9:d2:c1:98:3f, relayed by ca:8e:1d:ca:bc:ae   (99994)
```
Data od x8 dorazí pod adresou relaye 8g, controller je přeatribuuje a **teprve
tak uloží**. Na hvězdě na stole se tahle vada nedala ani vyvolat.

### Uzel potřebuje jen zásuvku

Mesh síť `10.10.10.0/24` sahá přes backhaul na každý uzel, protože management
port není v `br-lan`. Ověřeno v bridge tabulce:
```
ca:8d:a2:5f:45:8e  dev ap-mld-2.sta2  master br-lan     ← 4addr WDS, ne drát
```

**Flash přes vzduch ověřen celý cyklus:** přenos 55 MB → `md5` shoda →
`sysupgrade` → reboot → sám navázal backhaul → dostupný. Marker v `/etc/mapc/`
přežije flash a potvrdí, který obraz reálně nabootoval.

### Klienti reálně cestují

Během psaní tohoto dokumentu se `Petrs-iMac-2` sám přeroamoval z 4g na 8g.
Na stole se klient nehnul, ani když byl u jiného uzlu o 20 dB blíž — musel se
vynutit plechem nebo steeringem.

---

## ⚠️ Známá omezení

**x8 má na 6 GHz odpojený anténní řetěz.** Řetěz 0 je 24–30 dB pod ostatními,
konzistentně, na všech vzdálenostech:
```
na stole   8g 6 GHz:  -17 [-23, -20, -20]
na stole   x8 6 GHz:  -35 [-70, -36, -42]     handicap 18 dB při stejné vzdálenosti
za zdí     x8 6 GHz:  -71 [-87, -72, -77]
```
Na 5 GHz je x8 v pořádku (rozptyl 7 dB), takže **vada je jen v 6GHz pásmu**.
Prakticky: x8 veze provoz jednou nohou.

⇒ **Per-link steering se nesmí ladit proti x8 na 6 GHz** — vyšlo by z toho, že
6 GHz je špatná volba, přitom je to jeden konektor. Baseline pro 6 GHz je **8g**.

**Semafor MT7996** je jediná porucha, po které je bezdrátový uzel nedosažitelný
(`probe failed -11`, prázdná `/sys/class/ieee80211/`). Nezávisí na obrazu, je to
kostka při každém rebootu, `rmmod/modprobe` nepomůže — léčí to jen delší
odpojení od proudu.

⇒ **Doporučeno: chytré zásuvky na vzdálené uzly.** Mění jedinou vadu vyžadující
fyzickou přítomnost na věc řešitelnou na dálku.

⇒ **Přes vzduch neflashovat obraz měnící WiFi vrstvu** (mt76, hostapd, DTS).
Controller/agent patche jsou bezpečné — bring-up rádií je bit po bitu stejný.

---

## Co to odemyká

Do dneška se dala testovat jen **funkčnost** — jestli se příkaz vykoná. Teď jde
poprvé testovat **správnost rozhodnutí**, protože:

- skoky mají různou kvalitu a je co optimalizovat
- klienti se pohybují sami, takže roaming není laboratorní trik
- dvouskok je trvalý stav, takže se v něm projeví chyby, které na stole spí
- per-link metriky existují, takže se dá rozhodovat podle jednotlivých linek

Nejbližší dvě věci, které to umožňuje: **politika backhaul steeringu** (aktuátor
je hotový a prokázaný, chybí rozhodovací smyčka) a **pohyblivá internetová
gateway** — přičemž ty dvě spolu souvisí, protože backhaulový strom se má
kořenit tam, kde je WAN.

---

*Sepsáno 4. 8. 2026 na základě měření z téhož dne. Doprovodné dokumenty:
`HANDOFF-easymesh-2026-08-04-vecer.md` (stav vývoje, nedodělky, pasti),
`PATCH-REVIEW-EASYMESH-2026-08-04.md` (slepá recenze série).*
