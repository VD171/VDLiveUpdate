> **Languages:** [English](../PRODUCER.md) · [العربية](../ar/PRODUCER.md) · Čeština · [Deutsch](../de/PRODUCER.md) · [Español](../es/PRODUCER.md) · [فارسی](../fa/PRODUCER.md) · [Français](../fr/PRODUCER.md) · [हिन्दी](../hi/PRODUCER.md) · [Bahasa Indonesia](../id/PRODUCER.md) · [Italiano](../it/PRODUCER.md) · [日本語](../ja/PRODUCER.md) · [한국어](../ko/PRODUCER.md) · [Nederlands](../nl/PRODUCER.md) · [Polski](../pl/PRODUCER.md) · [Português](../pt/PRODUCER.md) · [Русский](../ru/PRODUCER.md) · [Svenska](../sv/PRODUCER.md) · [ไทย](../th/PRODUCER.md) · [Türkçe](../tr/PRODUCER.md) · [Українська](../uk/PRODUCER.md) · [Tiếng Việt](../vi/PRODUCER.md) · [中文](../zh/PRODUCER.md)

---

# VDLU producer + podpisova vrstva

Sestavuje obsahove adresovanou dodavku (manifest + bloby) pro modul a podepisuje ji.
Ridi se [`INTERFACES.md`](INTERFACES.md) §3/§6/§7.

| tool | bezi na | jazyk | prace |
|---|---|---|---|
| `producer/vdlu-pack` | PC / CI | python3 | projit finalni strom modulu -> `manifest.json` + `blobs/` |
| `producer/vdlu-keygen` | PC | sh + openssl | ed25519 par klicu (`<id>.pem` priv, `<id>.pub` PEM, `<id>.pub.raw` RAW 32B pro stihly keyring) |
| `producer/vdlu-sign` | PC | sh + openssl | vlozit `key_id` + `sig` do manifestu, na miste |
| `engine/vdlu-verify` | **zarizeni** | sh + ed25519-mini | overit `sig` pres vestaveny ed25519-mini; keyring = RAW 32B verejny klic (ZADNY openssl na zarizeni) |

## Pipeline

```sh
# 1. one-time: a signing key. Keep the .pem off every device and off any repo push.
producer/vdlu-keygen release-2026 ./keys

# 2. each release: pack the final tree (same tree the .zip ships, post-whitelist).
producer/vdlu-pack  ./module_tree  ./out  demo 106 --version-name v106 --channel stable \
                    [--prev ./prev/manifest.json]      # delete[] = paths gone since prev

# 3. sign the manifest in place.
producer/vdlu-sign  ./out/manifest.json  ./keys/release-2026.pem  release-2026

# 4. publish ./out/{manifest.json,blobs/} to <source> (Pages batch for public; rsync for private).
#    The slim device keyring holds ./keys/release-2026.pub.raw as keyring/release-2026.pub (RAW 32B).
```

`vdlu-pack` je obsahove adresovany a deduplikujici: blob, jehoz `<sha256>` uz existuje, se
neprepisuje, takze publikovani je inkrementalni a nezmeneny / vraceny obsah se nikdy znovu nepushuje.

### Rozhodnuti `enc` (vdlu-pack)

`sha256` je **vzdy** z puvodniho (nekomprimovaneho) obsahu; `enc` jen pojmenovava, jak je blob ulozen.

- `gz` kdyz `size >= 4096` **a** gzip (`-9 -n`, deterministicke) usetri aspon 10% (`comp <= raw*0.90`).
- `raw` jinak (maly text, ktery HTTP gzip uz pokryva, nebo uz nekomprimovatelna data).
- gzip chybi na build hostu -> vse `raw` (nikdy neselze).

Blob je ulozen jednou, v jednom formatu: `blobs/<sha256>` (raw) nebo `blobs/<sha256>.gz` (gz). Zarizeni
dekomprimuje toyboxovym `gunzip` (vzdy pritomny), takze se nebundluje zadny zstd.

### Rozhodnuti `class` (vdlu-pack) - reboot taxonomie

Odvozeno z cesty (INTERFACES §3, doc §4). Jen vychozi; pravidlo cesty nikdy nesnizuje `reboot`->`live`.

| class | matchnuto pres | aplikovano |
|---|---|---|
| `reboot` | `system/**`, `zygisk/**/*.so`, `*.rule` | stageovane `.vdlu-new`, swap pri bootu |
| `soft` | root `service.sh` / `post-fs-data.sh` / `boot-completed.sh` | zapsano live, bezi pri dalsim bootu |
| `live` | vse ostatni (webroot, bin, lib, confs, module.prop, ...) | zapsano live, atomicky |

Symlinky se **nenasleduji** (nikdy neleakuji obsah zvenci stromu, napr. odkaz na
`/etc/shadow`) a preskakuji se s varovanim, protoze schema manifestu nema symlink typ.
Neregularni soubory (adresare, fify, zarizeni) se preskakuji. `built` respektuje `SOURCE_DATE_EPOCH` pro
reprodukovatelne manifesty.

### Baseline (seed instalace) - nepodepsane, bez klice

`baseline.json` (dodane v `vdlu/baseline.json` v zipu modulu) naseeduje `current.json` pri cerstve instalaci,
aby se zarizeni narodilo "current" (zadny from:0, zadny re-fetch). Engine ho bere jako **lokalni duveryhodny seed**
(prisel v flashnutem zipu, coz je instalacni hranice duvery) a **NEoverrruje jeho podpis** -
jen manifest STAZENY z feedu projde `vdlu-verify`. Baseline tedy nepotrebuje **zadny klic**: je to
proste vystup `vdlu-pack` nad dodanym stromem (nepodepsane; `sig`/`key_id` zustavaji prazdne). CI ho tedy muze
generovat **bez klice** a drzet podpisovy klic 100% mimo CI - jen publikovany FEED se podepisuje (operator,
lokalne). `vdlu-pack` vylucuje `baseline.json` z vlastniho manifestu (anti self-reference). Nefatalni pokud
chybi: zarizeni proste zacne from:0 pri prvnim updatu, nikdy rozbite.

## Kanonizace (bod konvergence)

`vdlu-sign` a `engine/vdlu-verify` musi odvodit **stejne bajty** z manifestu, na dvou
ruznych runtimech (PC openssl vs zarizeni toybox + openssl). Pravidlo je zamerne bajtova
transformace, ne JSON reserializace, takze nepotrebuje zadnou JSON knihovnu na zarizeni:

1. `vdlu-pack` zapisuje `manifest.json` **kompaktne, klice serazene, UTF-8**
   (`json.dumps(obj, sort_keys=True, separators=(",",":"), ensure_ascii=False)`), vzdy vcetne
   poli `key_id` a `sig` (prazdne string placeholdery dokud nepodepsano). Toto je kanonicka
   ulozna forma.
2. **Kanonicka forma = ten text s odstranenym polem `"sig"`.** Protoze klice jsou serazene, `sig`
   se vzdy objevi jako `,"sig":"<value>",`, obklopeno `"schema"` (pred) a `"version"` (po),
   obe vzdy pritomne. Odstraneni zanecha dobre tvarovane `...,"schema":N,"version":...`.
   JSON escapuje kazdou `"` uvnitr string hodnot na `\"`, takze strukturni token `"sig":"`
   je jednoznacny i proti nazvu souboru, ktery doslova obsahuje `"sig":"` (otestovano).
3. Podepsana/overena zprava je **sha256 hex** (64 ASCII znaku, zadny novy radek) kanonicke
   formy. ed25519 nad timto hexem (`openssl pkeyutl -sign/-verify -rawin`).

Odstraneni v POSIX sh (identicka funkce v obou nastrojich, zadny `sed`/`jq`):

```sh
# $1 = full manifest text (trailing newline already stripped by $(cat ...))
_pre=${_c%%\"sig\":\"*}     # up to  ...,"schema":N,
_rest=${_c#*\"sig\":\"}      # after "sig":"
_tail=${_rest#*\",}          # after <value>",  ->  "version":...
printf '%s%s' "$_pre" "$_tail" | sha256sum | cut -d' ' -f1
```

`key_id` je soucasti kanonicke formy (odstranuje se jen `sig`); `vdlu-sign` nastavuje `key_id` **pred**
hashovanim. Placeholder hodnoty, at prazdny (`"sig":""`, cas podpisu) nebo vyplneny (cas overeni), dava
identicke kanonicke bajty, takze podpis a overeni se shoduji konstrukci.

Python to reprodukuje jako `re.sub(r'"sig":"[^"]*",', '', text.rstrip("\\n"), count=1)` pak sha256 - pouzito
jen pro krizovou kontrolu; autoritativni producenti jsou dva sh nastroje.

## Podpis (ed25519)

- `vdlu-keygen` (PC): `openssl genpkey -algorithm ed25519` (priv `0600`) + `openssl pkey -pubout` (pub **PEM**,
  pro podepisovani/openssl) + `openssl pkey -pubout -outform DER | tail -c 32` -> **`.pub.raw` (RAW 32B)** (ed25519
  SPKI DER je 12bajtovy prefix + 32bajtovy klic, takze `tail -c 32` JE klic). Emituje OBE.
- `vdlu-sign` (PC): `openssl pkeyutl -sign -rawin` nad kanonickym sha256 hexem; podpis ulozen base64.
- `vdlu-verify` (**zarizeni, stihle**): `ed25519-mini <pubkey32> <msg> <sig64>` - cte keyring jako **RAW 32B**
  verejny klic, ZADNY openssl na zarizeni. `key_id` je path-sanitizovan (zadne `/`, `.`, `..`, `"`). 🚨 Keyring dodava
  **`.pub.raw` (32B)**, nikdy `.pub` PEM (113B): PEM je jen PC-side a `ed25519-mini` ho neumi precist.

Model duvery (INTERFACES §6, doc §11/§13): `profile=hardened` (public) cini verify povinne - selhany
nebo chybejici podpis abortuje update. `profile=trusted` (privatni, SSH-stageovany zdroj) bere
verify jako best-effort, ale sha256 kazdeho blobu se kontroluje bez ohledu na to.

## Keyring + rotace

Keyring je adresar souboru `<key_id>.pub`, kazdy **RAW 32B** ed25519 verejny klic (z `keygen`ova
`.pub.raw`), NE PEM - `ed25519-mini` cte holych 32 bajtu. Dodavejte aktualni **i** predchozi raw verejny klic
(doc §13), aby rotovany klic nebrickoval starsi instalace. `vdlu-sign` s novym `key_id` a zarizeni
vybirajici `<keyring>/<key_id>.pub` (raw) je cely rotacni mechanismus - zadna zmena enginu. Keyring je
**stabilni** napric releasy (meni ho jen rotace klice): re-vendor musi **overit-ne-kopirovat** a nikdy ho
neprepsat PC-side `.pub` PEM.

<!-- doc-footer -->

---

> _Tato dokumentace byla vytvořena pomocí Claude (Anthropic) a spravuje ji VD171. Opravy a vylepšení jsou vítány; viz [CONTRIBUTING.md](CONTRIBUTING.md)._
