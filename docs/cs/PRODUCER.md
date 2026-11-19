> **Languages:** [English](../PRODUCER.md) · [العربية](../ar/PRODUCER.md) · Čeština · [Deutsch](../de/PRODUCER.md) · [Español](../es/PRODUCER.md) · [فارسی](../fa/PRODUCER.md) · [Français](../fr/PRODUCER.md) · [हिन्दी](../hi/PRODUCER.md) · [Bahasa Indonesia](../id/PRODUCER.md) · [Italiano](../it/PRODUCER.md) · [日本語](../ja/PRODUCER.md) · [한국어](../ko/PRODUCER.md) · [Nederlands](../nl/PRODUCER.md) · [Polski](../pl/PRODUCER.md) · [Português](../pt/PRODUCER.md) · [Русский](../ru/PRODUCER.md) · [Svenska](../sv/PRODUCER.md) · [ไทย](../th/PRODUCER.md) · [Türkçe](../tr/PRODUCER.md) · [Українська](../uk/PRODUCER.md) · [Tiếng Việt](../vi/PRODUCER.md) · [中文](../zh/PRODUCER.md)

---

# VDLU producer + podpisová vrstva

Sestavuje obsahově adresovanou dodávku (manifest + bloby) pro modul a podepisuje ji.
Řídí se [`INTERFACES.md`](INTERFACES.md) §3/§6/§7.

| tool | běží na | jazyk | práce |
|---|---|---|---|
| `producer/vdlu-pack` | PC / CI | python3 | projít finální strom modulu -> `manifest.json` + `blobs/` |
| `producer/vdlu-keygen` | PC | sh + openssl | ed25519 pár klíčů (`<id>.pem` priv, `<id>.pub` PEM, `<id>.pub.raw` RAW 32B pro štíhlý keyring) |
| `producer/vdlu-sign` | PC | sh + openssl | vložit `key_id` + `sig` do manifestu, na místě |
| `engine/vdlu-verify` | **zařízení** | sh + ed25519-mini | ověřit `sig` přes vestavěný ed25519-mini; keyring = RAW 32B veřejný klíč (ŽÁDNÝ openssl na zařízení) |

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

`vdlu-pack` je obsahově adresovaný a deduplikující: blob, jehož `<sha256>` už existuje, se
nepřepisuje, takže publikování je inkrementální a nezměněný / vrácený obsah se nikdy znovu nepushuje.

### Rozhodnutí `enc` (vdlu-pack)

`sha256` je **vždy** z původního (nekomprimovaného) obsahu; `enc` jen pojmenovává, jak je blob uložen.

- `gz` když `size >= 4096` **a** gzip (`-9 -n`, deterministické) ušetří aspoň 10% (`comp <= raw*0.90`).
- `raw` jinak (malý text, který HTTP gzip už pokrývá, nebo už nekomprimovatelná data).
- gzip chybí na build hostu -> vše `raw` (nikdy neselže).

Blob je uložen jednou, v jednom formátu: `blobs/<sha256>` (raw) nebo `blobs/<sha256>.gz` (gz). Zařízení
dekomprimuje toyboxovým `gunzip` (vždy přítomný), takže se nebundluje žádný zstd.

### Rozhodnutí `class` (vdlu-pack) - reboot taxonomie

Odvozeno z cesty (INTERFACES §3, doc §4). Jen výchozí; pravidlo cesty nikdy nesnižuje `reboot`->`live`.

| class | matchnuto přes | aplikováno |
|---|---|---|
| `reboot` | `system/**`, `zygisk/**/*.so`, `*.rule` | stageované `.vdlu-new`, swap při bootu |
| `soft` | root `service.sh` / `post-fs-data.sh` / `boot-completed.sh` | zapsáno live, běží při dalším bootu |
| `live` | vše ostatní (webroot, bin, lib, confs, module.prop, ...) | zapsáno live, atomicky |

Symlinky se **nenásledují** (nikdy neleakují obsah zvenčí stromu, např. odkaz na
`/etc/shadow`) a přeskakují se s varováním, protože schéma manifestu nemá symlink typ.
Neregulární soubory (adresáře, fify, zařízení) se přeskakují. `built` respektuje `SOURCE_DATE_EPOCH` pro
reprodukovatelné manifesty.

### Baseline (seed instalace) - nepodepsané, bez klíče

`baseline.json` (dodané v `vdlu/baseline.json` v zipu modulu) naseeduje `current.json` při čerstvé instalaci,
aby se zařízení narodilo "current" (žádný from:0, žádný re-fetch). Engine ho bere jako **lokální důvěryhodný seed**
(přišel v flashnutém zipu, což je instalační hranice důvěry) a **NEověřuje jeho podpis** -
jen manifest STAŽENÝ z feedu projde `vdlu-verify`. Baseline tedy nepotřebuje **žádný klíč**: je to
prostě výstup `vdlu-pack` nad dodaným stromem (nepodepsané; `sig`/`key_id` zůstávají prázdné). CI ho tedy může
generovat **bez klíče** a držet podpisový klíč 100% mimo CI - jen publikovaný FEED se podepisuje (operátor,
lokálně). `vdlu-pack` vylučuje `baseline.json` z vlastního manifestu (anti self-reference). Nefatální pokud
chybí: zařízení prostě začne from:0 při prvním updatu, nikdy rozbité.

## Kanonizace (bod konvergence)

`vdlu-sign` a `engine/vdlu-verify` musí odvodit **stejné bajty** z manifestu, na dvou
různých runtimech (PC openssl vs zařízení toybox + openssl). Pravidlo je záměrně bajtová
transformace, ne JSON reserializace, takže nepotřebuje žádnou JSON knihovnu na zařízení:

1. `vdlu-pack` zapisuje `manifest.json` **kompaktně, klíče seřazené, UTF-8**
   (`json.dumps(obj, sort_keys=True, separators=(",",":"), ensure_ascii=False)`), vždy včetně
   polí `key_id` a `sig` (prázdné string placeholdery dokud nepodepsáno). Toto je kanonická
   uložná forma.
2. **Kanonická forma = ten text s odstraněným polem `"sig"`.** Protože klíče jsou seřazené, `sig`
   se vždy objeví jako `,"sig":"<value>",`, obklopeno `"schema"` (před) a `"version"` (po),
   obě vždy přítomné. Odstranění zanechá dobře tvarované `...,"schema":N,"version":...`.
   JSON escapuje každou `"` uvnitř string hodnot na `\"`, takže strukturní token `"sig":"`
   je jednoznačný i proti názvu souboru, který doslova obsahuje `"sig":"` (otestováno).
3. Podepsaná/ověřená zpráva je **sha256 hex** (64 ASCII znaků, žádný nový řádek) kanonické
   formy. ed25519 nad tímto hexem (`openssl pkeyutl -sign/-verify -rawin`).

Odstranění v POSIX sh (identická funkce v obou nástrojích, žádný `sed`/`jq`):

```sh
# $1 = full manifest text (trailing newline already stripped by $(cat ...))
_pre=${_c%%\"sig\":\"*}     # up to  ...,"schema":N,
_rest=${_c#*\"sig\":\"}      # after "sig":"
_tail=${_rest#*\",}          # after <value>",  ->  "version":...
printf '%s%s' "$_pre" "$_tail" | sha256sum | cut -d' ' -f1
```

`key_id` je součástí kanonické formy (odstraňuje se jen `sig`); `vdlu-sign` nastavuje `key_id` **před**
hashováním. Placeholder hodnoty, ať prázdný (`"sig":""`, čas podpisu) nebo vyplněný (čas ověření), dává
identické kanonické bajty, takže podpis a ověření se shodují konstrukcí.

Python to reprodukuje jako `re.sub(r'"sig":"[^"]*",', '', text.rstrip("\\n"), count=1)` pak sha256 - použito
jen pro křížovou kontrolu; autoritativní producenti jsou dva sh nástroje.

## Podpis (ed25519)

- `vdlu-keygen` (PC): `openssl genpkey -algorithm ed25519` (priv `0600`) + `openssl pkey -pubout` (pub **PEM**,
  pro podepisování/openssl) + `openssl pkey -pubout -outform DER | tail -c 32` -> **`.pub.raw` (RAW 32B)** (ed25519
  SPKI DER je 12bajtový prefix + 32bajtový klíč, takže `tail -c 32` JE klíč). Emituje OBĚ.
- `vdlu-sign` (PC): `openssl pkeyutl -sign -rawin` nad kanonickým sha256 hexem; podpis uložen base64.
- `vdlu-verify` (**zařízení, štíhlé**): `ed25519-mini <pubkey32> <msg> <sig64>` - čte keyring jako **RAW 32B**
  veřejný klíč, ŽÁDNÝ openssl na zařízení. `key_id` je path-sanitizován (žádné `/`, `.`, `..`, `"`). 🚨 Keyring dodává
  **`.pub.raw` (32B)**, nikdy `.pub` PEM (113B): PEM je jen PC-side a `ed25519-mini` ho neumí přečíst.

Model důvěry (INTERFACES §6, doc §11/§13): `profile=hardened` (public) činí verify povinné - selhaný
nebo chybějící podpis abortuje update. `profile=trusted` (privátní, SSH-stageovaný zdroj) bere
verify jako best-effort, ale sha256 každého blobu se kontroluje bez ohledu na to.

## Keyring + rotace

Keyring je adresář souborů `<key_id>.pub`, každý **RAW 32B** ed25519 veřejný klíč (z `keygen`ova
`.pub.raw`), NE PEM - `ed25519-mini` čte holých 32 bajtů. Dodávejte aktuální **i** předchozí raw veřejný klíč
(doc §13), aby rotovaný klíč nebrickoval starší instalace. `vdlu-sign` s novým `key_id` a zařízení
vybírající `<keyring>/<key_id>.pub` (raw) je celý rotační mechanismus - žádná změna enginu. Keyring je
**stabilní** napříč releasy (mění ho jen rotace klíče): re-vendor musí **ověřit-ne-kopírovat** a nikdy ho
nepřepsat PC-side `.pub` PEM.

<!-- doc-footer -->

---

> _Tato dokumentace byla vytvořena pomocí Claude (Anthropic) a spravuje ji VD171. Opravy a vylepšení jsou vítány; viz [CONTRIBUTING.md](CONTRIBUTING.md)._
