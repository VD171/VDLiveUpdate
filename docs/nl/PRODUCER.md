> **Languages:** [English](../PRODUCER.md) · [العربية](../ar/PRODUCER.md) · [Čeština](../cs/PRODUCER.md) · [Deutsch](../de/PRODUCER.md) · [Español](../es/PRODUCER.md) · [فارسی](../fa/PRODUCER.md) · [Français](../fr/PRODUCER.md) · [हिन्दी](../hi/PRODUCER.md) · [Bahasa Indonesia](../id/PRODUCER.md) · [Italiano](../it/PRODUCER.md) · [日本語](../ja/PRODUCER.md) · [한국어](../ko/PRODUCER.md) · Nederlands · [Polski](../pl/PRODUCER.md) · [Português](../pt/PRODUCER.md) · [Русский](../ru/PRODUCER.md) · [Svenska](../sv/PRODUCER.md) · [ไทย](../th/PRODUCER.md) · [Türkçe](../tr/PRODUCER.md) · [Українська](../uk/PRODUCER.md) · [Tiếng Việt](../vi/PRODUCER.md) · [中文](../zh/PRODUCER.md)

---

# VDLU-producer + signeerlaag

Bouwt de content-addressed levering (manifest + blobs) voor een module en tekent die.
Conformeert zich aan [`INTERFACES.md`](INTERFACES.md) §3/§6/§7.

| tool | draait op | taal | taak |
|---|---|---|---|
| `producer/vdlu-pack` | PC / CI | python3 | doorloop de uiteindelijke moduleboom -> `manifest.json` + `blobs/` |
| `producer/vdlu-keygen` | PC | sh + openssl | ed25519-sleutelpaar (`<id>.pem` priv, `<id>.pub` PEM, `<id>.pub.raw` RAW 32B voor de slanke keyring) |
| `producer/vdlu-sign` | PC | sh + openssl | injecteer `key_id` + `sig` in een manifest, ter plekke |
| `engine/vdlu-verify` | **toestel** | sh + ed25519-mini | verifieer `sig` via de ingebedde ed25519-mini; keyring = RAW 32B pubkey (GEEN openssl op toestel) |

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

`vdlu-pack` is content-addressed en dedupliceert: een blob waarvan de `<sha256>` al bestaat, wordt niet
herschreven, zodat publiceren incrementeel is en de onveranderde / teruggedraaide inhoud nooit opnieuw wordt gepusht.

### `enc`-beslissing (vdlu-pack)

`sha256` is **altijd** van de originele (ongecomprimeerde) inhoud, `enc` benoemt alleen hoe de blob wordt opgeslagen.

- `gz` wanneer `size >= 4096` **en** gzip (`-9 -n`, deterministisch) ten minste 10% bespaart (`comp <= raw*0.90`).
- `raw` anders (kleine tekst die HTTP-gzip al dekt, of al-oncomprimeerbare data).
- gzip ontbreekt op de build-host -> alles `raw` (faalt nooit).

Een blob wordt één keer opgeslagen, in één formaat: `blobs/<sha256>` (raw) of `blobs/<sha256>.gz` (gz). Het toestel
decomprimeert met toybox `gunzip` (altijd aanwezig), zodat er geen zstd wordt meegebundeld.

### `class`-beslissing (vdlu-pack) - reboot-taxonomie

Afgeleid uit het pad (INTERFACES §3, doc §4). Alleen standaardwaarden, een padregel downgradt nooit `reboot`->`live`.

| class | gematcht door | toegepast |
|---|---|---|
| `reboot` | `system/**`, `zygisk/**/*.so`, `*.rule` | gestaged `.vdlu-new`, swap bij boot |
| `soft` | root `service.sh` / `post-fs-data.sh` / `boot-completed.sh` | live geschreven, draait bij volgende boot |
| `live` | al het overige (webroot, bin, lib, confs, module.prop, ...) | live geschreven, atomisch |

Symlinks worden **niet gevolgd** (lekt nooit inhoud van buiten de boom, bijv. een link naar
`/etc/shadow`) en worden met een waarschuwing overgeslagen, aangezien het manifest-schema geen symlink-type heeft.
Niet-reguliere bestanden (dirs, fifos, devices) worden overgeslagen. `built` respecteert `SOURCE_DATE_EPOCH` voor
reproduceerbare manifesten.

### Baseline (de installatie-seed) - ongetekend, sleutelloos

`baseline.json` (geleverd op `vdlu/baseline.json` in de module-zip) seedt `current.json` bij een verse installatie
zodat het toestel "current" wordt geboren (geen from:0, geen her-fetch). De engine behandelt het als een **lokale vertrouwde seed**
(het arriveerde in de geflashte zip, die de installatie-vertrouwensgrens is) en **verifieert zijn handtekening NIET** -
alleen het manifest dat FETCHED is van de feed gaat door `vdlu-verify`. Dus de baseline heeft **geen sleutel** nodig: het is
gewoon `vdlu-pack`-output over de geleverde boom (ongetekend, `sig`/`key_id` blijven leeg). Een CI kan daarom
**sleutelloos** worden gegenereerd, waardoor de signeersleutel 100% buiten CI blijft - alleen de gepubliceerde FEED wordt getekend (operator,
lokaal). `vdlu-pack` sluit `baseline.json` uit van zijn eigen manifest (anti-zelfreferentie). Niet-fataal indien
afwezig: het toestel begint gewoon vanaf from:0 bij de eerste update, nooit kapot.

## Canonicalisatie (het convergentiepunt)

`vdlu-sign` en `engine/vdlu-verify` moeten **dezelfde bytes** afleiden uit een manifest, op twee
verschillende runtimes (PC openssl vs toestel toybox). De regel is bewust een byte-
transformatie, geen JSON-herserialisatie, zodat het geen JSON-bibliotheek op het toestel nodig heeft:

1. `vdlu-pack` schrijft `manifest.json` **compact, sleutels gesorteerd, UTF-8**
   (`json.dumps(obj, sort_keys=True, separators=(",",":"), ensure_ascii=False)`), altijd met inbegrip van
   de velden `key_id` en `sig` (lege-string-placeholders tot getekend). Dit is de canonieke
   opslagvorm.
2. **Canonieke vorm = die tekst met het `"sig"`-veld verwijderd.** Omdat sleutels gesorteerd zijn, verschijnt `sig`
   altijd als `,"sig":"<value>",` omgeven door `"schema"` (ervoor) en `"version"` (erna),
   beide altijd aanwezig. Het verwijderen laat een welgevormd `...,"schema":N,"version":...` achter.
   JSON escapet elke `"` binnen stringwaarden naar `\"`, dus het structurele token `"sig":"` is
   ondubbelzinnig, zelfs tegen een bestandsnaam die letterlijk `"sig":"` bevat (getest).
3. Het getekende/geverifieerde bericht is de **sha256-hex** (64 ASCII-tekens, geen newline) van de canonieke
   vorm. ed25519 over die hex (`openssl pkeyutl -sign/-verify -rawin`).

De verwijdering in POSIX sh (identieke functie in beide tools, geen `sed`/`jq`):

```sh
# $1 = full manifest text (trailing newline already stripped by $(cat ...))
_pre=${_c%%\"sig\":\"*}     # up to  ...,"schema":N,
_rest=${_c#*\"sig\":\"}      # after "sig":"
_tail=${_rest#*\",}          # after <value>",  ->  "version":...
printf '%s%s' "$_pre" "$_tail" | sha256sum | cut -d' ' -f1
```

`key_id` is onderdeel van de canonieke vorm (alleen `sig` wordt gestript), `vdlu-sign` zet `key_id` **vóór** het
hashen. Of de waarde-placeholder leeg is (`"sig":""`, signeertijd) of gevuld (verifytijd) levert identieke
canonieke bytes op, dus signeren en verifiëren komen per constructie overeen.

Python reproduceert het als `re.sub(r'"sig":"[^"]*",', '', text.rstrip("\\n"), count=1)` daarna sha256 - gebruikt
alleen om te cross-checken, de gezaghebbende producenten zijn de twee sh-tools.

## Handtekening (ed25519)

- `vdlu-keygen` (PC): `openssl genpkey -algorithm ed25519` (priv `0600`) + `openssl pkey -pubout` (pub **PEM**,
  voor signeren/openssl) + `openssl pkey -pubout -outform DER | tail -c 32` -> **`.pub.raw` (RAW 32B)** (de ed25519
  SPKI DER is een 12-byte prefix + de 32-byte sleutel, dus `tail -c 32` IS de sleutel). Het zendt BEIDE uit.
- `vdlu-sign` (PC): `openssl pkeyutl -sign -rawin` over de canonieke sha256-hex, handtekening opgeslagen als base64.
- `vdlu-verify` (**toestel, slank**): `ed25519-mini <pubkey32> <msg> <sig64>` - leest de keyring als de **RAW 32B**
  pubkey, GEEN openssl op het toestel. `key_id` is pad-gesaneerd (geen `/`, `.`, `..`, `"`). 🚨 De keyring levert de
  **`.pub.raw` (32B)**, nooit de `.pub` PEM (113B): de PEM is alleen PC-zijdig en `ed25519-mini` kan hem niet lezen.

Vertrouwensmodel (INTERFACES §6, doc §11/§13): `profile=hardened` (publiek) maakt verify verplicht - een
mislukte of ontbrekende handtekening breekt de update af. `profile=trusted` (privé, SSH-gestagede bron) behandelt
verify als best-effort, maar de sha256 van elke blob wordt hoe dan ook gecontroleerd.

## Keyring + rotatie

De keyring is een directory van `<key_id>.pub`-bestanden, elk de **RAW 32B** ed25519-pubkey (uit `keygen`'s
`.pub.raw`), GEEN PEM - `ed25519-mini` leest raw 32 bytes. Lever de huidige **en** de vorige raw pubkey
(doc §13) zodat een geroteerde sleutel oudere installaties niet brickt. `vdlu-sign` met de nieuwe `key_id` en het toestel
dat `<keyring>/<key_id>.pub` (raw) kiest, is het hele rotatiemechanisme - geen engine-wijziging. De keyring is
**stabiel** over releases heen (alleen sleutelrotatie verandert hem): een her-vendor moet hem **verifiëren-niet-kopiëren**, en nooit
overschrijven met de PC-zijdige `.pub` PEM.

**Keyrings met meerdere sleutels MOETEN de modulesleutel vastpinnen.** De engine beperkt welke `key_id` een MODULE-UPDATE mag tekenen tot de `key_id`-allowlist van de config (INTERFACES §5/§6), fail-closed gecontroleerd voordat de pubkey wordt geselecteerd. Een keyring met één sleutel is standaardveilig (die ene sleutel wordt geaccepteerd). Maar een module waarvan de keyring OOK een sleutel van lager vertrouwen draagt - bijv. een fingerprint-feed-sleutel naast de release-sleutel - wordt geweigerd tot zijn `config` de modulesleutel declareert, bijv. `key_id=vd-2026` (kommagescheiden voor rotatie, bijv. `key_id=vd-2026,vd-2027`). Dit voorkomt dat een gelekte sleutel van lager vertrouwen een flashless root-update tekent.

`vdlu-pack` **sluit de keyring en de `verify/`-binaries uit van de feed** (de vertrouwenswortel is alleen-flash, wordt nooit over de draad geserveerd), naast `baseline.json`, de installer-steiger (`META-INF/`, `customize.sh`), de `.vd/`-flashpoort, de door CI gevulde `update.json`/`update-mmrl.json`, en de `.sha256`-metgezellen per bestand. Alleen de eigen inhoud van de module is via de feed bij te werken, zodat een manifest het vertrouwensanker op het toestel nooit kan herschrijven.

<!-- doc-footer -->

---

> _Deze documentatie is gegenereerd met Claude (Anthropic) en wordt onderhouden door VD171. Correcties en verbeteringen zijn welkom, zie [CONTRIBUTING.md](CONTRIBUTING.md)._
