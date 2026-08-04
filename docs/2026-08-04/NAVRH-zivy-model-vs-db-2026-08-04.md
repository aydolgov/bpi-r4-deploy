# Návrhové rozhodnutí: živý model vs. databáze — 4. 8. 2026

> Vzniklo z Petrovy otázky: *„data v DB nejsou spolehlivě synchronizovaná
> s online stavem, a když jsou, tak se zpožděním. Pro další vývoj je budeme
> potřebovat správná a rychlá. Co s tím?"*
>
> Odpověď není „zrychlit DB". Je to **rozdělit role podle časového horizontu**.

---

## Co je dnes

Controller drží **živý model** v paměti a v určitých místech ho zrcadlí do
SQLite (`mapc_sync_*`, volané z dispatcheru podle typu CMDU). Drtivě převažuje
**Topology Response**, tedy perioda ~60 s.

Důsledky, všechny naměřené 4. 8.:

- roaming se v DB projeví **nejhůř za minutu**
- **nic se nikdy nemaže** — odešlí klienti i vyřazené uzly zůstávají navždy
  (proto seznam „departed records" jen roste)
- některá pole plní jen konkrétní CMDU, takže část sloupců je trvale prázdná
- **`sta` nemá časové razítko** — u řádku nejde poznat, jak je starý
  (`sta_mld` má `last_seen`, `sta` má jen `conn_time`, což je něco jiného)

⚠️ **Pozor na záměnu:** 4. 8. byla DB v okamžiku kontroly **věcně správná** —
všichni tři klienti u správných uzlů. Problém není nesprávnost, ale **latence
a neúplnost**. To jsou různé vady s různým řešením.

---

## Rozhodnutí

### Rozděl podle časového horizontu, ne podle toho, co je „rozhodování"

```
ŽIVÝ MODEL — co se děje TEĎ
   RSSI po nohách · kde klient právě je · žije linka?
   → aktuální do jednoho CMDU
   → sem patří vstupy, na kterých závisí latence

DATABÁZE — co se DĚLO
   historie · trendy · záznam rozhodnutí · přežití restartu
   → sem patří vše, co dělá rozhodnutí DOBRÝM, ne rychlým
```

### Tok dat

```
   živý model  ──►  vstupy do rozhodnutí (aktuální hodnoty)
                         │
                     politika
                         │
   databáze  ◄──────  co jsem rozhodl, kdy, a co se pak stalo
        │
        └──────────►  zpětné čtení při dalším rozhodnutí
                      (hystereze, trend, „co se stalo minule")
```

---

## Proč DB z návrhu NEVYPADÁVÁ

Původní úvaha byla, že steering a optimalizace budou stavět na datech z DB.
**Tu úvahu neruším** — jen se mění důvod, proč tam DB je. Není to zdroj
aktuálního stavu; je to **paměť té politiky**. A bez ní dobrý steering
postavit nejde:

| co | proč to živý model nezvládne |
|---|---|
| **hystereze / antiflapping** | největší riziko není špatné rozhodnutí, ale rozhodnutí každých 30 s; k jeho potlačení musíš vědět, co jsi udělal naposled a jak to dopadlo |
| **trendy** | „linka je teď na −70" je slabý argument; „je pod −68 posledních 10 minut" je silný — rozdíl je historie |
| **přežití restartu** | bez DB si politika po každém rebootu začne od nuly a znovu rozhází usazené klienty |
| **záznam rozhodnutí** | aby šlo zpětně říct *proč* jsi klienta přehodil; bez toho se to nedá ladit ani obhájit |

> ⚠️ **Korekce vlastní formulace.** Nejdřív jsem napsal „rozhodovací logika
> nesmí číst z DB". To je příliš kategorické a mohlo by vést ke zrušení něčeho
> užitečného. Správně: **aktuální stav, na kterém závisí latence, nesmí chodit
> z DB.** Historie a záznam rozhodnutí ano, a mají.

---

## Co z toho plyne pro implementaci

### ① Politiku psát proti živému modelu, ne proti DB
Rozhodnout **dřív, než se začne psát** backhaul steering — potom už by to byl
přepis, ne volba.

### ② Zkrátit prodlevu tam, kde je to levné
Synchronizovat i na **Topology Notification** (asociace/odpojení klienta), ne
jen na periodické Topology Response. To je zpráva, která nese roaming —
zkrátí reakci z ~60 s na jednotky sekund.
Pozn.: ta cesta se stejně bude opravovat, recenze u ní našla vadu s ukládáním
pod relay (nález 1.3).

### ③ Každý řádek musí nést čas pořízení
Bez razítka je zastaralost **neviditelná**. S razítkem je z ní údaj, se kterým
umí konzument pracovat („tohle je 4 minuty staré, neřídím se tím").
Je to týž princip jako u tabulky `mesh-status`: raději „nevím, jak je to staré"
než tiché tvrzení, že je to teď.

### ④ Doplnit mazání
`mapc_del_*` volané z ageoutu. Bez toho DB odpovídá na otázku „kdo kdy byl",
ne „kdo je" — a to je u vlajkové vlastnosti (deterministické zotavení) přesně
naopak, než chceme.

### ⑤ Ukládat i to, co dnes ztrácíme
Např. **na které lince sedí ne-MLO klient**. Dnes je v `sta.bssid` adresa
AP-MLD, takže se pásmo nedá určit — a tabulka pak vypisuje všechna tři, což
vypadá jako údaj, ale není.

---

## Co NEDĚLAT

- **Nedávat DB do latenční cesty rozhodování.** SQLite v horké smyčce je
  latence, kterou nepotřebujeme, a živý model je stejně autoritativnější.
- **Nedělat z DB jediný zdroj pravdy** (controller píše jen tam a čte odtud).
  Velký zásah, velké riziko regresí, žádný odpovídající přínos.
- **Nerušit DB jako podklad optimalizace.** Viz tabulka výše — je to paměť
  politiky, ne jen zrcadlo stavu.

---

## Otevřené otázky

1. **Jak dlouho držet historii?** Trend přes 10 minut stačí na hysterezi;
   na „tenhle klient roamuje pořád" je potřeba hodiny. Retence zatím nemáme.
2. **Kam zapisovat rozhodnutí?** Nová tabulka (`steer_log`?) vs. rozšíření
   stávajících. Nová je čistší a nemíchá pozorování s akcemi.
3. **Perioda vzorkování metrik.** Dnes se řídí dotazy; pro trendy bude
   potřeba pravidelnost, ne nahodilost.
4. **Airtime a retries** — dnes je vůbec neukládáme, přitom pro rozhodování
   o kvalitě linky jsou nejspíš důležitější než samotné RSSI.

---

*Souvisí: `VICTORY-realna-mesh-2026-08-04.md` (stav a naměřené parametry),
`HANDOFF-easymesh-2026-08-04-vecer.md` (rozpracované věci),
`PATCH-REVIEW-EASYMESH-2026-08-04.md` (nález 1.3 a 1.13).*
