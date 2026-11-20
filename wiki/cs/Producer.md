# Producer

**Producer** je strana VDLU na PC / release: malá sada nástrojů, které promění hotový strom modulu na podepsaný, obsahově adresovaný feed, ze kterého může zařízení aktualizovat. Nic zde neběží na telefonu. Tyto nástroje běží na vašem release stroji (nebo, pro části, pro které je to bezpečné, v CI).

Jsou čtyři:

| Nástroj | Běží na | Jazyk | Úloha |
|---|---|---|---|
| `vdlu-pack` | PC / CI | python3 | Projít finální strom modulu do `manifest.json` + `blobs/<sha256>` |
| `vdlu-keygen` | PC | sh + openssl | Vygenerovat ed25519 podpisový pár klíčů |
| `vdlu-sign` | PC | sh + openssl | Vložit `key_id` + podpis do manifestu, na místě |
| `vdlu-gc` | PC | python3 | Odstranit sirotčí bloby z publikovaného feedu (bezpečně) |

Release postup má tři kroky, prováděné jednou na vydání: **zabalit, pak podepsat, pak publikovat**. `vdlu-keygen` je jednorázové nastavení a `vdlu-gc` je údržba, kterou spouštíte, když feed roste. Vše, co producer vydá, odpovídá [[Feed Format]], který engine na zařízení konzumuje.

---

## vdlu-pack

`vdlu-pack` vezme **přesný strom, který váš `.zip` dodává** (finální strom poté, co váš build aplikoval svou vlastní whitelist a oříznutí ABI) a vyprodukuje pro něj feed.

```sh
vdlu-pack <module_tree_dir> <out_dir> <module_id> <version> \
          [--version-name v106] [--channel stable] [--prev ./prev/manifest.json]
```

Zapíše dvě věci do `<out_dir>`:

- `manifest.json` - úplný popis cílového stromu (každý soubor s jeho `sha256`, `size`, `mode`, kódováním a třídou reboot), stále **nepodepsaný** (pole `key_id` a `sig` jsou prázdné zástupné symboly).
- `blobs/<sha256>` (nebo `blobs/<sha256>.gz`) - jeden blob na odlišný obsah souboru.

### Obsahově adresované a deduplikující

Každý blob je pojmenován podle **sha256 svého originálního (nekomprimovaného) obsahu**. Protože jméno je hash, identický obsah přistane na stejném blobu. `vdlu-pack` zapíše blob jen tehdy, pokud ještě není přítomný, takže:

- Soubor, který se nezměnil, si zachová stejné jméno blobu a nikdy se znovu nezapíše ani nepushne.
- Dva různé soubory s identickým obsahem sdílejí jeden blob.
- Vrácený soubor znovu použije blob, který tam již byl předtím.

Publikování je proto **inkrementální z konstrukce**: napříč vydáními `blobs/` jen roste a přidá se jen skutečně nový obsah. Zařízení stahuje podle stejných hashů, takže stahuje jen bloby, které ještě nemá.

### Komprese (pole `enc`)

Pro každý soubor `vdlu-pack` rozhodne, jak blob uložit:

- `gz`, když je soubor alespoň 4096 bajtů **a** gzip (deterministické `-9 -n`) ušetří alespoň 10 procent.
- `raw` jinak (malé soubory, které gzip na drátě stejně pokrývá, nebo již nekomprimovatelná data).
- Pokud na build hostu chybí `gzip`, vše se ukládá `raw`. Balení na tom nikdy neselže.

`sha256` v manifestu je **vždy** z originálního obsahu; `enc` jen pojmenovává, jak je blob náhodou uložen. Zařízení dekomprimuje `gz` bloby pomocí toybox `gunzip` a pak zkontroluje hash proti originálu.

### Třída reboot a bezpečnost

`vdlu-pack` také označuje každý soubor třídou reboot (`class`: `live`, `soft`, `reboot`) odvozenou z jeho cesty, takže engine ví, co lze aplikovat bez restartu a co musí být inscenováno. Pravidla a to, co zařízení s každou třídou dělá, jsou pokryta v [[Reboot Handling]].

Několik věcí, které `vdlu-pack` záměrně **nedělá**:

- Nenásleduje symbolické odkazy (přeskočí je s varováním, takže obsah zvenčí stromu, jako odkaz na systémový soubor, nikdy nemůže uniknout do blobu).
- Přeskakuje neregulární soubory (adresáře, fifo, zařízení).
- Respektuje `SOURCE_DATE_EPOCH` pro časové razítko `built`, takže manifesty jsou reprodukovatelné.
- Zcela vylučuje pevnou sadu cest z feedu (kořen důvěry, instalační lešení a pár dalších). Úplný seznam a proč je každá vyloučena, je v [[Feed Format]].

### Seznam `delete[]`

Předejte `--prev <previous manifest.json>` a `vdlu-pack` spočítá `delete[]`: cesty, které existovaly v předchozím vydání, ale v tomto jsou pryč, takže je zařízení odstraní místo ponechání sirotků. Vyloučené cesty se nikdy nevydají jako mazání, i když se objeví v předchozím manifestu (viz [[Feed Format]] pro přesnou sémantiku).

---

## vdlu-keygen

Jednorázový krok. `vdlu-keygen` vytvoří ed25519 podpisový pár klíčů pro váš feed.

```sh
vdlu-keygen <id> <out_dir>
```

Zapíše tři soubory:

| Soubor | Co to je | Kam jde |
|---|---|---|
| `<id>.pem` | **Privátní** podpisový klíč (mód `0600`) | Zůstává na vašem release stroji. Nikdy. |
| `<id>.pub` | Veřejný klíč jako PEM | Jen nástroje na straně PC |
| `<id>.pub.raw` | Veřejný klíč jako **syrových 32 bajtů** | Dodán jako záznam keyringu modulu na zařízení |

Syrový 32-bajtový veřejný klíč je to, co čte ověřovač na zařízení (nenese `openssl`, takže PEM přečíst nemůže). Vložíte `<id>.pub.raw` do modulu jako `vdlu/keyring/<id>.pub`. PEM je jen pro použití na straně PC. Toto rozdělení a jak funguje rotace klíčů, je vysvětleno v [[Security and Trust Model]].

> Privátní `.pem` je jediné tajemství v celém systému. Držte ho mimo každé zařízení a mimo každý push do repozitáře. Viz poznámku o CI níže.

---

## vdlu-sign

`vdlu-sign` vezme nepodepsaný manifest, který `vdlu-pack` vyprodukoval, a podepíše ho **na místě**.

```sh
vdlu-sign <manifest.json> <privkey.pem> <key_id>
```

Nastaví pole `key_id`, spočítá kanonickou formu manifestu a zapíše ed25519 podpis (base64) do pole `sig`. Podpis je nad přesnou bajtovou transformací manifestu tak, aby PC a zařízení odvodily přesně tytéž podepsané bajty bez JSON knihovny na zařízení. Ta transformace (**kanonizace**) je nejdůležitější invariant ve formátu a je kompletně zdokumentována v [[Feed Format]].

Privátní klíč se čte jen zde, na vašem stroji, a nikdy ho neopustí.

### Podpisový klíč zůstává mimo CI

To je záměrný návrhový bod. CI může spustit `vdlu-pack` a vyprodukovat dokonale platný **bezklíčový baseline** (nepodepsaný semínkový manifest; viz [[Feed Format]]), takže čerstvá instalace se narodí aktuální, aniž by se CI kdy dotklo privátního klíče. Samotné podepsání publikovaného feedu provádíte vy, lokálně, pomocí `vdlu-sign`. Tak je podpisový klíč ze 100 procent mimo CI a podepsán je jen feed, který publikujete ručně.

---

## vdlu-gc

Protože bloby jsou obsahově adresované a neměnné, `blobs/` jen vždy roste: `vdlu-pack` přidává, nikdy neodstraňuje. Přes mnoho vydání feed (a Pages web, který ho hostuje) hromadí bloby, které žádný aktuální manifest již nereferencuje. `vdlu-gc` tyto siroty odstraní.

```sh
vdlu-gc <feed_dir> [--keep-last N] [--keep extra.json ...] [--apply]
```

Sestaví **zachovanou sadu** manifestů: aktuální `manifest.json`, plus posledních `N` archivovaných manifestů podle verze (výchozí `N=3`, což dává rezervu pro rollback), plus jakékoli, které pojmenujete pomocí `--keep`. Blob referencovaný **žádným** zachovaným manifestem je sirotek a je kandidátem na odstranění. Zachovaná sada je sjednocení, takže blob zůstává, dokud ho jakékoli zachované vydání ještě potřebuje; zařízení sedící na starší zachované verzi nikdy nepřijde o své stažení.

`vdlu-gc` je postaven tak, aby byl bezpečný:

- **Výchozí suchý běh.** Bez `--apply` jen vypíše, co *by* odstranil. Přidáte `--apply`, aby skutečně smazal.
- **Bezpečný při selhání.** Pokud nenajde vůbec žádný zachovaný manifest, odmítne odstraňovat místo rizika vyprázdnění feedu.
- **Zachování podle reference, ne podle data.** Blob se zachová, protože na něj zachovaný manifest ukazuje, nikdy kvůli časovému razítku.

Po odstranění pushnete menší feed na svůj host. Rozložte zápis v čase, pokud váš host omezuje dávkové zápisy rychlosti.

---

## Dání to dohromady

Typické vydání, od začátku do konce:

```sh
# one-time: make a signing key. Keep the .pem off every device and every repo push.
vdlu-keygen release-2026 ./keys

# each release: pack the final shipped tree (post-whitelist, same tree the .zip ships)
vdlu-pack ./module_tree ./out demo 106 --version-name v106 --channel stable \
          --prev ./prev/manifest.json

# sign the manifest in place (local, private key never leaves your machine)
vdlu-sign ./out/manifest.json ./keys/release-2026.pem release-2026

# publish ./out/{manifest.json,blobs/} to your source (GitHub Pages, rsync, ...).
# occasionally: prune orphan blobs
vdlu-gc ./feed --keep-last 3            # dry-run first
vdlu-gc ./feed --keep-last 3 --apply    # then delete
```

Pro úplný propracovaný příklad převzetí VDLU do modulu viz [[Quick Start]]. Pro tvar všeho, co producer vydá, na drátě viz [[Feed Format]]. Pro úvahu za zacházením s klíči a to, co je drženo mimo feed, viz [[Security and Trust Model]].
