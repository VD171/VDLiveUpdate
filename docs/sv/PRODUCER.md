> **Languages:** [English](../PRODUCER.md) · [العربية](../ar/PRODUCER.md) · [Čeština](../cs/PRODUCER.md) · [Deutsch](../de/PRODUCER.md) · [Español](../es/PRODUCER.md) · [فارسی](../fa/PRODUCER.md) · [Français](../fr/PRODUCER.md) · [हिन्दी](../hi/PRODUCER.md) · [Bahasa Indonesia](../id/PRODUCER.md) · [Italiano](../it/PRODUCER.md) · [日本語](../ja/PRODUCER.md) · [한국어](../ko/PRODUCER.md) · [Nederlands](../nl/PRODUCER.md) · [Polski](../pl/PRODUCER.md) · [Português](../pt/PRODUCER.md) · [Русский](../ru/PRODUCER.md) · Svenska · [ไทย](../th/PRODUCER.md) · [Türkçe](../tr/PRODUCER.md) · [Українська](../uk/PRODUCER.md) · [Tiếng Việt](../vi/PRODUCER.md) · [中文](../zh/PRODUCER.md)

---

# VDLU-producent + signeringslager

Bygger den innehållsadresserade leveransen (manifest + blobbar) för en modul och signerar den.
Rättar sig efter [`INTERFACES.md`](INTERFACES.md) §3/§6/§7.

| verktyg | körs på | språk | jobb |
|---|---|---|---|
| `producer/vdlu-pack` | PC / CI | python3 | vandra det slutliga modulträdet -> `manifest.json` + `blobs/` |
| `producer/vdlu-keygen` | PC | sh + openssl | ed25519-nyckelpar (`<id>.pem` priv, `<id>.pub` PEM, `<id>.pub.raw` RAW 32B för den slimmade keyringen) |
| `producer/vdlu-sign` | PC | sh + openssl | injicera `key_id` + `sig` i ett manifest, på plats |
| `engine/vdlu-verify` | **enhet** | sh + ed25519-mini | verifiera `sig` via den inbäddade ed25519-mini; keyring = RAW 32B pubnyckel (INGEN openssl på enheten) |

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

`vdlu-pack` är innehållsadresserad och deduplicerande: en blob vars `<sha256>` redan finns skrivs inte
om, så publiceringen är inkrementell och det oförändrade / återställda innehållet pushas aldrig på nytt.

### `enc`-beslutet (vdlu-pack)

`sha256` är **alltid** av originalinnehållet (okomprimerat), `enc` namnger bara hur bloben lagras.

- `gz` när `size >= 4096` **och** gzip (`-9 -n`, deterministisk) sparar minst 10 % (`comp <= raw*0.90`).
- `raw` annars (liten text som HTTP gzip redan täcker, eller redan inkompressibel data).
- gzip saknas på byggvärden -> allt `raw` (misslyckas aldrig).

En blob lagras en gång, i ett format: `blobs/<sha256>` (raw) eller `blobs/<sha256>.gz` (gz). Enheten
dekomprimerar med toybox `gunzip` (alltid närvarande), så ingen zstd paketeras.

### `class`-beslutet (vdlu-pack) - reboot-taxonomi

Härlett från sökväg (INTERFACES §3, doc §4). Endast standardvärden, en sökvägsregel nedgraderar aldrig `reboot`->`live`.

| class | matchas av | tillämpas |
|---|---|---|
| `reboot` | `system/**`, `zygisk/**/*.so`, `*.rule` | scenlagd `.vdlu-new`, byte vid boot |
| `soft` | rot-`service.sh` / `post-fs-data.sh` / `boot-completed.sh` | skriven live, körs nästa boot |
| `live` | allt annat (webroot, bin, lib, confs, module.prop, ...) | skriven live, atomisk |

Symlänkar **följs inte** (läcker aldrig innehåll utanför trädet, t.ex. en länk till
`/etc/shadow`) och hoppas över med en varning, eftersom manifestschemat inte har någon symlänktyp.
Icke-reguljära filer (kataloger, fifos, enheter) hoppas över. `built` respekterar `SOURCE_DATE_EPOCH` för
reproducerbara manifest.

### Baseline (installationsseeden) - osignerad, nyckellös

`baseline.json` (levererad vid `vdlu/baseline.json` i modul-zippen) seedar `current.json` vid en ny installation
så att enheten föds "aktuell" (ingen from:0, ingen om-hämtning). Motorn behandlar den som en **lokal betrodd seed**
(den anlände i den flashade zippen, som är installationens tillitsgräns) och **verifierar INTE dess signatur** -
endast manifestet som HÄMTATS från flödet går genom `vdlu-verify`. Så baseline behöver **ingen nyckel**: den är
bara `vdlu-pack`-utdata över det levererade trädet (osignerad, `sig`/`key_id` förblir tomma). En CI kan därför
generera den **nyckellöst**, vilket håller signeringsnyckeln 100 % borta från CI - endast det publicerade FLÖDET signeras (operatör,
lokalt). `vdlu-pack` exkluderar `baseline.json` från sitt eget manifest (anti-självreferens). Icke-fatalt om
frånvarande: enheten börjar bara från:0 vid den första uppdateringen, aldrig trasig.

## Kanonikalisering (konvergenspunkten)

`vdlu-sign` och `engine/vdlu-verify` måste härleda **samma byte** från ett manifest, på två
olika körtider (PC openssl vs enhet toybox). Regeln är avsiktligt en byte-
transformation, inte en JSON-omserialisering, så den behöver inget JSON-bibliotek på enheten:

1. `vdlu-pack` skriver `manifest.json` **kompakt, nycklar sorterade, UTF-8**
   (`json.dumps(obj, sort_keys=True, separators=(",",":"), ensure_ascii=False)`), och inkluderar alltid
   fälten `key_id` och `sig` (tomma strängplatshållare tills signerat). Detta är den kanoniska
   lagringsformen.
2. **Kanonisk form = den texten med `"sig"`-fältet borttaget.** Eftersom nycklarna är sorterade visas `sig`
   alltid som `,"sig":"<value>",` inramat av `"schema"` (före) och `"version"` (efter),
   båda alltid närvarande. Att ta bort den lämnar välformat `...,"schema":N,"version":...`.
   JSON escapar varje `"` inuti strängvärden till `\"`, så den strukturella token `"sig":"` är
   entydig även mot ett filnamn som bokstavligen innehåller `"sig":"` (testat).
3. Det signerade/verifierade meddelandet är **sha256-hexen** (64 ASCII-tecken, ingen radbrytning) av den
   kanoniska formen. ed25519 över den hexen (`openssl pkeyutl -sign/-verify -rawin`).

Borttagningen i POSIX sh (identisk funktion i båda verktygen, ingen `sed`/`jq`):

```sh
# $1 = full manifest text (trailing newline already stripped by $(cat ...))
_pre=${_c%%\"sig\":\"*}     # up to  ...,"schema":N,
_rest=${_c#*\"sig\":\"}      # after "sig":"
_tail=${_rest#*\",}          # after <value>",  ->  "version":...
printf '%s%s' "$_pre" "$_tail" | sha256sum | cut -d' ' -f1
```

`key_id` är en del av den kanoniska formen (endast `sig` strippas), `vdlu-sign` sätter `key_id` **innan**
hashning. Att värdesplatshållaren är tom (`"sig":""`, signeringstid) eller fylld (verifieringstid) ger de
identiska kanoniska byten, så signering och verifiering stämmer genom konstruktion.

Python reproducerar det som `re.sub(r'"sig":"[^"]*",', '', text.rstrip("\\n"), count=1)` sedan sha256 - används
bara för att dubbelkolla, de auktoritativa producenterna är de två sh-verktygen.

## Signatur (ed25519)

- `vdlu-keygen` (PC): `openssl genpkey -algorithm ed25519` (priv `0600`) + `openssl pkey -pubout` (pub **PEM**,
  för signering/openssl) + `openssl pkey -pubout -outform DER | tail -c 32` -> **`.pub.raw` (RAW 32B)** (ed25519
  SPKI DER är ett 12-byte-prefix + den 32-byte-nyckeln, så `tail -c 32` ÄR nyckeln). Den avger BÅDA.
- `vdlu-sign` (PC): `openssl pkeyutl -sign -rawin` över den kanoniska sha256-hexen, signatur lagrad base64.
- `vdlu-verify` (**enhet, slim**): `ed25519-mini <pubkey32> <msg> <sig64>` - läser keyringen som **RAW 32B**-
  pubnyckeln, INGEN openssl på enheten. `key_id` är sökvägssaniterad (ingen `/`, `.`, `..`, `"`). 🚨 Keyringen levererar
  **`.pub.raw` (32B)**, aldrig `.pub` PEM (113B): PEM:en är endast PC-sidig och `ed25519-mini` kan inte läsa den.

Tillitsmodell (INTERFACES §6, doc §11/§13): `profile=hardened` (public) gör verify obligatoriskt - en
misslyckad eller saknad signatur avbryter uppdateringen. `profile=trusted` (private, SSH-scenlagd källa) behandlar
verify som best-effort, men varje blobs sha256 kontrolleras oavsett.

## Keyring + rotation

Keyringen är en katalog med `<key_id>.pub`-filer, var och en den **RAW 32B** ed25519-pubnyckeln (från `keygen`:s
`.pub.raw`), INTE PEM - `ed25519-mini` läser råa 32 byte. Leverera den aktuella **och** den föregående råa pubnyckeln
(doc §13) så att en roterad nyckel inte tegelstenar äldre installationer. `vdlu-sign` med det nya `key_id` och enheten
som väljer `<keyring>/<key_id>.pub` (rå) är hela rotationsmekanismen - ingen motorändring. Keyringen är
**stabil** över releaser (bara nyckelrotation ändrar den): en om-vendoring måste **verifiera-inte-kopiera** den, och aldrig
skriva över den med den PC-sidiga `.pub` PEM:en.

**Keyringar med flera nycklar MÅSTE nåla fast modulnyckeln.** Engine begränsar vilken `key_id` som får signera en MODULE-UPDATE till configens `key_id`-allowlist (INTERFACES §5/§6), kontrollerad fail-closed innan pubnyckeln väljs. En keyring med en nyckel är standardsäker (den enda nyckeln accepteras). Men en modul vars keyring OCKSÅ bär en nyckel med lägre tillit - t.ex. en fingerprint-feed-nyckel vid sidan av release-nyckeln - avvisas tills dess `config` deklarerar modulnyckeln, t.ex. `key_id=vd-2026` (kommaseparerade för rotation, t.ex. `key_id=vd-2026,vd-2027`). Detta hindrar en läckt nyckel med lägre tillit från att signera en flashless root-uppdatering.

`vdlu-pack` **exkluderar keyringen och `verify/`-binärerna från flödet** (tillitsroten är endast flash, serveras aldrig över nätet), vid sidan av `baseline.json`, installerarställningen (`META-INF/`, `customize.sh`), `.vd/`-flashgrinden, de CI-fyllda `update.json`/`update-mmrl.json` och de per-fil `.sha256`-följeslagarna. Endast modulens eget innehåll är flödesuppdaterbart, så ett manifest kan aldrig skriva om tillitsankaret på enheten.

<!-- doc-footer -->

---

> _Denna dokumentation genererades med Claude (Anthropic) och underhålls av VD171. Rättelser och förbättringar välkomnas, se [CONTRIBUTING.md](CONTRIBUTING.md)._
