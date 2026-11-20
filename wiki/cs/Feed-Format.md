# Feed Format

**Feed** je to, co VDLU poskytuje po drátě a z čeho zařízení aktualizuje. Je to obyčejný statický adresář, servírovatelný čímkoli (GitHub Pages, cíl rsync, cesta `file://`):

```
<source>/
  manifest.json          # the signed description of the current release
  blobs/<sha256>         # one blob per distinct file content
  blobs/<sha256>.gz      # (when the blob is stored gzipped)
```

Modul sám také dodává jeden soubor navíc, `baseline.json`, uvnitř `.zip` (neservírovaný z feedu). Producer, který vše toto sestavuje, je popsán v [[Producer]]; tato stránka je kontrakt na drátě.

---

## manifest.json

Manifest je úplný popis jednoho vydání: každý soubor v cílovém stromu, co smazat a podpis nad celou věcí.

```json
{
  "schema": 1,
  "module": "demo",
  "version": 106,
  "version_name": "v106",
  "built": "2026-11-19T12:00:00Z",
  "engine_min": 3,
  "channel": "stable",
  "key_id": "release-2026",
  "files": [
    {
      "path": "webroot/index.html",
      "sha256": "<hex64>",
      "size": 1234,
      "mode": "0644",
      "enc": "raw",
      "class": "live"
    }
  ],
  "delete": ["webroot/old.html"],
  "sig": "<base64>"
}
```

### Pole

| Pole | Význam |
|---|---|
| `schema` | Verze formátu samotného manifestu (aktuálně `1`). |
| `module` | Id modulu. Zařízení zamítne manifest, pokud neodpovídá jeho vlastnímu id modulu, takže platně podepsaný feed pro jiný modul nelze servírovat na jeho místě. |
| `version` | Celočíselná verze. Engine aktualizuje jen vpřed; feed starší než zařízení je neškodný stav "ahead", ne chyba. |
| `version_name` | Lidsky čitelný řetězec verze (například `v106`). |
| `built` | Časové razítko buildu ISO 8601. Respektuje `SOURCE_DATE_EPOCH` pro reprodukovatelnost. |
| `engine_min` | Minimální verze enginu požadovaná k aplikaci tohoto manifestu. |
| `channel` | Kanál vydání (například `stable`). |
| `key_id` | Který klíč v keyringu zařízení podepsal tento manifest. Vybírá veřejný klíč pro ověření, a musí být v allowlistu aktualizace modulu enginu (viz [[Security and Trust Model]]); klíč pouze přítomný v keyringu, ale ne na allowlistu, je odmítnut dříve, než je jeho pubkey načten. |
| `files[]` | **Úplný** cílový strom (ne diff). Každý záznam: `path`, `sha256`, `size`, `mode`, `enc` (`raw`/`gz`), `class` (`live`/`soft`/`reboot`). |
| `delete[]` | Cesty přítomné v předchozím vydání, ale nyní pryč, aby je zařízení odstranilo. |
| `sig` | ed25519 podpis, base64. Viz kanonizaci níže. |

`files[]` popisuje **celý** strom, ne deltu. Zařízení spočítá deltu samo porovnáním manifestu proti tomu, co již má, a stahuje jen bloby, jejichž `sha256` mu chybí. `sha256` je vždy z originálního (nekomprimovaného) obsahu; `enc` jen říká, jak je ten blob uložen v `blobs/`. Význam `class` a to, co zařízení s každou hodnotou dělá, je pokryto v [[Reboot Handling]].

---

## Kanonizace (podepsané bajty)

Toto je nejdůležitější invariant ve formátu. PC podepisovač a ověřovač na zařízení běží na zcela odlišných runtime (openssl na PC, toybox + nepatrný vestavěný ověřovač na zařízení a **vůbec žádná JSON knihovna** na zařízení). Přesto musí odvodit přesně tytéž bajty k podpisu a k ověření. Pravidlo je proto záměrná **bajtová transformace**, ne znovu-serializace JSON.

**Krok 1: pevná forma uložení.** `vdlu-pack` zapíše `manifest.json` kompaktně, se seřazenými klíči, UTF-8, vždy včetně `key_id` a `sig` (jako prázdné řetězce, dokud není podepsáno):

```
json.dumps(obj, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
```

**Krok 2: odstranit jen `sig`.** Kanonická forma je přesně ten text s **odstraněným jen polem `"sig"`**. Protože klíče jsou seřazeny, `sig` se vždy objevuje jako `,"sig":"<value>",` ohraničené `"schema"` před ním a `"version"` po něm (obě vždy přítomny), takže odstranění zanechá správně tvarovaný text. JSON escapuje každé `"` uvnitř hodnoty řetězce jako `\"`, takže strukturální token `"sig":"` je jednoznačný i proti názvu souboru, který doslova obsahuje `"sig":"`.

Odstranění je hrstka POSIX expanzí parametru, identických v podepisovači a ověřovači, bez `sed` a bez `jq`:

```sh
# $1 = the full manifest text
_pre=${_c%%\"sig\":\"*}     # up to  ...,"schema":N,
_rest=${_c#*\"sig\":\"}      # after "sig":"
_tail=${_rest#*\",}          # after <value>",  ->  "version":...
printf '%s%s' "$_pre" "$_tail" | sha256sum | cut -d' ' -f1
```

**Krok 3: podepsat hash z toho.** Podepsaná/ověřená zpráva je **sha256 hex** (64 ASCII znaků, bez nového řádku) kanonické formy. ed25519 podepisuje tento hex.

Dva důsledky z toho vyplývají z konstrukce:

- `key_id` je součástí kanonické formy (odstraňuje se jen `sig`). `vdlu-sign` nastavuje `key_id` **před** hashováním, takže identita klíče je pokryta podpisem.
- Ať už je zástupce `sig` prázdný (`"sig":""`, v čase podpisu) nebo vyplněný (v čase ověření), jeho odstranění dá identické kanonické bajty. Podepisování a ověřování se automaticky shodují.

Dva POSIX sh nástroje jsou směrodatné. Python ekvivalent, `re.sub(r'"sig":"[^"]*",', '', text, count=1)` pak sha256, existuje jen k jejich křížové kontrole.

Úvaha o důvěře kolem toho všeho (proč je ověření na zařízení, jak `hardened` selhává fail-closed) žije v [[Security and Trust Model]].

---

## baseline.json (semínko instalace)

Když je modul čerstvě nainstalován, měl by už být "aktuální" pro svou vlastní dodanou verzi, bez zbytečné samoaktualizace verze, kterou právě nainstaloval. To je to, co `baseline.json` dělá.

`baseline.json` se dodává **uvnitř zipu modulu** (v `vdlu/baseline.json`), ne na feedu. Při čerstvé instalaci engine naseje svůj záznam "aktivní verze" z něj, takže zařízení se narodí aktuální, bez `from:0` a bez znovu-stažení toho, co již má.

Klíčové vlastnosti:

- Je to **bezklíčová kopie podepsaného manifestu** pro dodanou verzi: tentýž výstup `vdlu-pack`, ponechaný nepodepsaný (`key_id` a `sig` zůstávají prázdné).
- Není **ověřována**. Engine ji považuje za lokální důvěryhodné semínko, protože dorazila uvnitř flashnutého zipu, což je hranice důvěry instalace. Jen manifest *stažený z feedu* prochází ověřením podpisu.
- Protože nepotřebuje podpis, **CI ji může vygenerovat bezklíčově**, což je to, co udržuje podpisový klíč zcela mimo CI (viz [[Producer]]).
- `vdlu-pack` **vylučuje `baseline.json` z vlastního manifestu**, takže manifest nikdy nereferencuje baseline (to by byla smyčka sebe-reference: manifest na baseline na manifest).
- Je **neosudná, pokud chybí**. Bez ní zařízení jednoduše začíná od `from:0` při své první aktualizaci a stahuje, co potřebuje. Nikdy ne rozbité, jen méně optimální.

---

## Bloby

Každý odlišný obsah souboru je jeden blob pod `blobs/`, pojmenovaný podle **sha256 originálního obsahu**:

- `blobs/<sha256>` pro syrový blob.
- `blobs/<sha256>.gz` pro gzipovaný blob (gzip se drží jen tehdy, když je soubor alespoň 4096 bajtů a komprese ušetří alespoň 10 procent).

Blob se ukládá jednou, v jednom formátu. Obsahové adresování dává deduplikaci zdarma: nezměněný, sdílený nebo vrácený obsah se mapuje na blob, který již existuje, takže feed roste jen skutečně novým obsahem a zařízení stahuje jen hashe, které mu chybí. Zařízení kontroluje `sha256` každého staženého blobu proti manifestu (po dekompresi `gz` blobu) dříve, než ho použije.

---

## Co je vyloučeno z feedu a proč

Feed nese **jen vlastní obsah modulu**. Pevná sada cest je záměrně držena venku. `vdlu-pack` aplikuje jeden vylučovací predikát jak při procházení stromu, tak při výpočtu `delete[]`.

| Vyloučeno | Proč |
|---|---|
| `vdlu/keyring/`, `vdlu/verify/` (kořen důvěry: syrové veřejné klíče + binární soubor ověřovače) | **Toto je základní bezpečnostní důvod.** Kotva důvěry je **flash-only**. Pokud by keyring nebo ověřovač byly dodatelné feedem, manifest by mohl přepsat právě tu věc, která ho ověřuje. Držení jich mimo drát znamená, že manifest nikdy nemůže přepsat kotvu důvěry na zařízení. |
| `vdlu/baseline.json` | Je to kopie podepsaného manifestu (semínko instalace); jeho balení by byla smyčka sebe-reference. |
| `.vd/` flash infrastruktura | Lešení flash-gate, které se dodává v zipu, nikdy aplikované naostro. |
| `update.json`, `update-mmrl.json` | Jejich velikost/sha vyplňuje CI *poté*, co jsou zipy sestaveny, takže dodaná kopie se liší od jakékoli feed kopie. Jejich feedování by způsobilo fantomové stažení jednoho souboru při první samoaktualizaci každé instalace a na zařízení jsou stejně zbytkové (manager čte vzdálený syrový update JSON). |
| `META-INF/`, `customize.sh` (instalační lešení) | Konzumováno managerem v čase **flashe** a neuchováváno v nainstalovaném modulu. Nejsou to obsah VDLU; jejich servírování plýtvá bloby a, kdyby se nějaký kdy změnil mezi verzemi, byl by zapsán jako instalační soubor do adresáře živého modulu. |
| Společníci `.sha256` po souborech | Patří jen k flashovatelnému zipu, po inkrementální aktualizaci zastarávají a zdvojnásobili by manifest. |
| Dev/doc soubory (`RELEASE.md`, `CLAUDE.md`, `.gitignore`) | Nikdy dodané na zařízení; jejich servírování plýtvá bloby a cvičí podepsaný manifest při každé úpravě dokumentace. |

Úvaha za vyloučením kořene důvěry je rozšířena v [[Security and Trust Model]].

---

## Sémantika delete[]

`delete[]` říká zařízení, které cesty odstranit, takže soubor vypuštěný mezi vydáními nezůstává na zařízení jako sirotek. Počítá se předáním `--prev <previous manifest.json>` do `vdlu-pack`: cesta, která byla v předchozím vydání a není v aktuálním, se stane záznamem mazání.

Důležité pravidlo: **vyloučené cesty se nikdy nevydají jako mazání, ani s `--prev`.** Každá předchozí cesta prochází stejným vylučovacím predikátem použitým při procházení stromu. Pokud `--prev` ukazuje na starší manifest, který stále vypisoval nyní-vyloučené cesty (zbloudilá `baseline.json`, `META-INF/*`, záznam keyringu atd.), tyto cesty se **ne**promění na záznamy mazání. Vyloučená cesta nikdy nebyla obsahem feedu, takže není VDLU k mazání, a zařízení nikdy nedostane příkaz odstranit soubor, který nebyl servírován přes feed. To je to, co udržuje vylučovací seznam od toho, aby se kdy vrátil jako destruktivní instrukce.
