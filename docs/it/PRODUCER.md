> **Languages:** [English](../PRODUCER.md) · [العربية](../ar/PRODUCER.md) · [Čeština](../cs/PRODUCER.md) · [Deutsch](../de/PRODUCER.md) · [Español](../es/PRODUCER.md) · [فارسی](../fa/PRODUCER.md) · [Français](../fr/PRODUCER.md) · [हिन्दी](../hi/PRODUCER.md) · [Bahasa Indonesia](../id/PRODUCER.md) · Italiano · [日本語](../ja/PRODUCER.md) · [한국어](../ko/PRODUCER.md) · [Nederlands](../nl/PRODUCER.md) · [Polski](../pl/PRODUCER.md) · [Português](../pt/PRODUCER.md) · [Русский](../ru/PRODUCER.md) · [Svenska](../sv/PRODUCER.md) · [ไทย](../th/PRODUCER.md) · [Türkçe](../tr/PRODUCER.md) · [Українська](../uk/PRODUCER.md) · [Tiếng Việt](../vi/PRODUCER.md) · [中文](../zh/PRODUCER.md)

---

# Livello producer + firma di VDLU

Costruisce la delivery content-addressed (manifest + blob) per un modulo e la firma.
Si conforma a [`INTERFACES.md`](INTERFACES.md) §3/§6/§7.

| tool | gira su | linguaggio | compito |
|---|---|---|---|
| `producer/vdlu-pack` | PC / CI | python3 | percorre l'albero finale del modulo -> `manifest.json` + `blobs/` |
| `producer/vdlu-keygen` | PC | sh + openssl | coppia di chiavi ed25519 (`<id>.pem` priv, `<id>.pub` PEM, `<id>.pub.raw` RAW 32B per il keyring snello) |
| `producer/vdlu-sign` | PC | sh + openssl | inietta `key_id` + `sig` in un manifest, in place |
| `engine/vdlu-verify` | **dispositivo** | sh + ed25519-mini | verifica `sig` tramite l'ed25519-mini incorporato; keyring = pubkey RAW 32B (NIENTE openssl sul dispositivo) |

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

`vdlu-pack` è content-addressed e deduplicante: un blob il cui `<sha256>` esiste già non viene
riscritto, quindi la pubblicazione è incrementale e il contenuto invariato / ripristinato non viene mai ri-pushato.

### Decisione `enc` (vdlu-pack)

`sha256` è **sempre** del contenuto originale (non compresso); `enc` nomina solo come il blob viene memorizzato.

- `gz` quando `size >= 4096` **e** gzip (`-9 -n`, deterministico) risparmia almeno il 10% (`comp <= raw*0.90`).
- `raw` altrimenti (testo piccolo che il gzip di HTTP copre già, o dati già incomprimibili).
- gzip mancante sull'host di build -> tutto `raw` (non fallisce mai).

Un blob viene memorizzato una volta, in un formato: `blobs/<sha256>` (raw) oppure `blobs/<sha256>.gz` (gz). Il dispositivo
decomprime con toybox `gunzip` (sempre presente), quindi non viene imbarcato zstd.

### Decisione `class` (vdlu-pack) - tassonomia del reboot

Derivata dal path (INTERFACES §3, doc §4). Solo default; una regola di path non fa mai il downgrade `reboot`->`live`.

| class | corrisposta da | applicata |
|---|---|---|
| `reboot` | `system/**`, `zygisk/**/*.so`, `*.rule` | in stage `.vdlu-new`, swap all'avvio |
| `soft` | root `service.sh` / `post-fs-data.sh` / `boot-completed.sh` | scritta live, gira al boot successivo |
| `live` | tutto il resto (webroot, bin, lib, confs, module.prop, ...) | scritta live, atomica |

I symlink **non vengono seguiti** (non fa mai trapelare contenuto da fuori dell'albero, es. un link a
`/etc/shadow`) e vengono saltati con un avviso, poiché lo schema del manifest non ha un tipo symlink.
I file non regolari (dir, fifo, device) vengono saltati. `built` rispetta `SOURCE_DATE_EPOCH` per
manifest riproducibili.

### Baseline (il seme di installazione) - non firmata, senza chiave

`baseline.json` (spedito a `vdlu/baseline.json` nello zip del modulo) semina `current.json` a un'installazione pulita
così il dispositivo nasce "corrente" (niente da:0, niente re-fetch). L'engine lo tratta come un **seme locale fidato**
(è arrivato nello zip flashato, che è il confine di fiducia dell'installazione) e **NON ne verifica la firma** -
solo il manifest RECUPERATO dal feed passa per `vdlu-verify`. Quindi la baseline non ha bisogno di **nessuna chiave**: è
semplicemente l'output di `vdlu-pack` sull'albero spedito (non firmata; `sig`/`key_id` restano vuoti). Una CI può quindi
generarla **senza chiave**, tenendo la chiave di firma al 100% fuori dalla CI - solo il FEED pubblicato viene firmato (operatore,
localmente). `vdlu-pack` esclude `baseline.json` dal proprio manifest (anti auto-riferimento). Non fatale se
assente: il dispositivo parte semplicemente da:0 al primo aggiornamento, mai rotto.

## Canonicalizzazione (il punto di convergenza)

`vdlu-sign` e `engine/vdlu-verify` devono derivare gli **stessi byte** da un manifest, su due
runtime diversi (openssl del PC vs toybox + openssl del dispositivo). La regola è deliberatamente una trasformazione di
byte, non una ri-serializzazione JSON, così non ha bisogno di alcuna libreria JSON sul dispositivo:

1. `vdlu-pack` scrive `manifest.json` **compatto, chiavi ordinate, UTF-8**
   (`json.dumps(obj, sort_keys=True, separators=(",",":"), ensure_ascii=False)`), includendo sempre
   i campi `key_id` e `sig` (segnaposto stringa vuota finché non firmato). Questa è la forma canonica
   di memorizzazione.
2. **Forma canonica = quel testo con il campo `"sig"` rimosso.** Poiché le chiavi sono ordinate, `sig`
   appare sempre come `,"sig":"<value>",` racchiuso tra `"schema"` (prima) e `"version"` (dopo),
   entrambi sempre presenti. Rimuoverlo lascia `...,"schema":N,"version":...` ben formato.
   JSON fa l'escape di ogni `"` dentro i valori stringa in `\"`, quindi il token strutturale `"sig":"` è
   non ambiguo anche contro un filename che contiene letteralmente `"sig":"` (testato).
3. Il messaggio firmato/verificato è lo **sha256 esadecimale** (64 caratteri ASCII, nessun newline) della forma
   canonica. ed25519 su quell'esadecimale (`openssl pkeyutl -sign/-verify -rawin`).

La rimozione in sh POSIX (funzione identica in entrambi i tool, niente `sed`/`jq`):

```sh
# $1 = full manifest text (trailing newline already stripped by $(cat ...))
_pre=${_c%%\"sig\":\"*}     # up to  ...,"schema":N,
_rest=${_c#*\"sig\":\"}      # after "sig":"
_tail=${_rest#*\",}          # after <value>",  ->  "version":...
printf '%s%s' "$_pre" "$_tail" | sha256sum | cut -d' ' -f1
```

`key_id` fa parte della forma canonica (solo `sig` viene tolto); `vdlu-sign` imposta `key_id` **prima**
dell'hashing. Il segnaposto del valore, vuoto (`"sig":""`, al momento della firma) o riempito (al momento del verify), produce gli
identici byte canonici, quindi sign e verify concordano per costruzione.

Python lo riproduce come `re.sub(r'"sig":"[^"]*",', '', text.rstrip("\\n"), count=1)` poi sha256 - usato
solo per cross-check; i produttori autoritativi sono i due tool sh.

## Firma (ed25519)

- `vdlu-keygen` (PC): `openssl genpkey -algorithm ed25519` (priv `0600`) + `openssl pkey -pubout` (pub **PEM**,
  per firma/openssl) + `openssl pkey -pubout -outform DER | tail -c 32` -> **`.pub.raw` (RAW 32B)** (il DER SPKI
  ed25519 è un prefisso di 12 byte + la chiave di 32 byte, quindi `tail -c 32` È la chiave). Emette ENTRAMBE.
- `vdlu-sign` (PC): `openssl pkeyutl -sign -rawin` sullo sha256 esadecimale canonico; firma memorizzata base64.
- `vdlu-verify` (**dispositivo, snello**): `ed25519-mini <pubkey32> <msg> <sig64>` - legge il keyring come la pubkey **RAW 32B**,
  NIENTE openssl sul dispositivo. `key_id` è sanificato come path (niente `/`, `.`, `..`, `"`). 🚨 Il keyring spedisce la
  **`.pub.raw` (32B)**, mai la `.pub` PEM (113B): il PEM è solo PC-side e `ed25519-mini` non può leggerlo.

Modello di fiducia (INTERFACES §6, doc §11/§13): `profile=hardened` (pubblico) rende il verify obbligatorio - una
firma fallita o mancante aborta l'aggiornamento. `profile=trusted` (privato, sorgente SSH-staged) tratta
il verify come best-effort, ma lo sha256 di ogni blob viene controllato comunque.

## Keyring + rotazione

Il keyring è una directory di file `<key_id>.pub`, ognuno la pubkey ed25519 **RAW 32B** (dalla `.pub.raw`
di `keygen`), NON PEM - `ed25519-mini` legge 32 byte grezzi. Spedisci la pubkey grezza corrente **e** la precedente
(doc §13) così una chiave ruotata non brickizza le installazioni più vecchie. `vdlu-sign` con il nuovo `key_id` e il dispositivo
che sceglie `<keyring>/<key_id>.pub` (grezza) sono l'intero meccanismo di rotazione - nessuna modifica all'engine. Il keyring è
**stabile** tra le release (solo la rotazione delle chiavi lo cambia): un re-vendor deve **verificare-non-copiare**, e mai
sovrascriverlo con la `.pub` PEM PC-side.

<!-- doc-footer -->

---

> _Questa documentazione è stata generata con Claude (Anthropic) ed è gestita da VD171. Correzioni e miglioramenti sono benvenuti; vedi [CONTRIBUTING.md](CONTRIBUTING.md)._
