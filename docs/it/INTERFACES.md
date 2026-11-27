> **Languages:** [English](../INTERFACES.md) · [العربية](../ar/INTERFACES.md) · [Čeština](../cs/INTERFACES.md) · [Deutsch](../de/INTERFACES.md) · [Español](../es/INTERFACES.md) · [فارسی](../fa/INTERFACES.md) · [Français](../fr/INTERFACES.md) · [हिन्दी](../hi/INTERFACES.md) · [Bahasa Indonesia](../id/INTERFACES.md) · Italiano · [日本語](../ja/INTERFACES.md) · [한국어](../ko/INTERFACES.md) · [Nederlands](../nl/INTERFACES.md) · [Polski](../pl/INTERFACES.md) · [Português](../pt/INTERFACES.md) · [Русский](../ru/INTERFACES.md) · [Svenska](../sv/INTERFACES.md) · [ไทย](../th/INTERFACES.md) · [Türkçe](../tr/INTERFACES.md) · [Українська](../uk/INTERFACES.md) · [Tiếng Việt](../vi/INTERFACES.md) · [中文](../zh/INTERFACES.md)

---

# VDLU - Contratto di interfaccia (la cucitura tra i componenti)

**Legge di convergenza:** ogni componente si conforma a questo file. I pezzi dei 4 agenti devono **combaciare** - le
firme CLI, i nomi dei file e le chiavi JSON qui sotto sono **immutabili** (una modifica significa prima allinearsi qui).

Principi ereditati dai repo: **sh POSIX puro** sul dispositivo (niente bashism, gira con toybox/busybox +
`sha256sum`/`gzip`/`base64` di toybox + il `curl` recuperato + l'`ed25519-mini` incorporato - snello, senza bundle di
binari), **zero commenti gratuiti**, **sempre release**, **rigore sul fallimento** (transazione ripristinabile, niente di
falsamente "concluso", niente di perso), **niente allentato**.

---

## 1. Layout dello stato (Tier-2, fuori dalla directory del modulo)

```
$VDLU_DIR = /data/adb/<module>/vdlu
  config               # key=value (§5)
  current.json         # manifest of the ACTIVE version (diff base); absent = never updated
  journal.json         # transaction in progress (§4); absent = idle
  cancel               # presence = cancel request (WebUI creates it; engine deletes it on stop)
  lock.d/              # mkdir-lock (flock unworkable on toybox; stale-recovery by PID)
  blobs/<sha256>       # cache of verified blobs (ORIGINAL content, already decompressed)
  rollback/<version>/<path>   # backup of overwritten files
  staged/<path>.vdlu-new      # REBOOT-hard awaiting swap at boot
  target.json          # PINNED manifest of the in-flight transaction (presence = active transaction; becomes current.json on DONE)
  plan.tsv  plan.del   # engine's internal plan (progress); the WebUI IGNORES it (reads only journal/config/current)
```
`cancelled:true` nel journal = l'engine si è fermato su un annullamento (uno stato non terminale, ripristinabile, `error`
resta null).

Engine vendorizzato nel modulo: `$MODULE_DIR/vdlu/update.sh` (+ `vdlu-verify`). `$MODULE_DIR =
/data/adb/modules/<module>`. L'engine riceve tramite env: `VDLU_DIR`, `MODULE_DIR`, `MODID`.

## 2. CLI dell'engine (componente ENGINE)

`sh update.sh <cmd>` - rc 0 = ok, !=0 = errore (lo stderr contiene il motivo):

| cmd | fa |
|---|---|
| `check` | DIFF: scarica il manifest, confronta; stampa un JSON su 1 riga `{"update":bool,"from":N,"to":M,"fetch":K,"reboot":bool}`; non cambia nulla. Dispositivo PIÙ AVANTI del feed (downgrade bloccato, hardened) = uno stato BENIGNO: `{"update":false,"ahead":true,"from":N,"to":M}` + rc0 (mai "check failed"). rc di do_diff: 2 fetch/parse, 3 verify/meta, 4 ahead |
| `run` | ciclo completo: DIFF->FETCH->APPLY->COMMIT; rispetta `cancel`; scrive il progresso su `journal.json`; applica LIVE, mette in stage i REBOOT-hard |
| `resume` | riprende la transazione di `journal.json` dalla fase corrente (idempotente) |
| `boot` | modalità pre-zygote: `resume` + esegue lo SWAP dei `staged/*.vdlu-new` (applica il `.so`), chiude `PENDING_REBOOT`->`DONE` |
| `status` | stampa `journal.json` (oppure `{"state":"idle"}`) |
| `cancel` | crea `$VDLU_DIR/cancel` (un `run` in corso si ferma al prossimo punto sicuro) |

Sorgente del blob/manifest: `source` dalla config. `<source>` + `/manifest.json`, `/blobs/<sha>`, `/blobs/<sha>.gz`.
`source` inizia con `https://` (curl statico recuperato, TLS) oppure `file://` (staging locale).

## 3. manifest.json (prodotto dal PRODUCER, consumato dall'ENGINE)

```json
{ "schema":1, "module":"<id>", "version":<int>, "version_name":"<str>", "built":"<ISO8601>",
  "engine_min":5, "key_id":"<str>", "channel":"stable",
  "files":[ {"path":"webroot/index.html","sha256":"<hex64>","size":<int>,"mode":"0644","enc":"raw|gz","class":"live|soft|reboot"} ],
  "delete":["<path>"], "sig":"<base64>" }
```

- `files[]` = l'albero di destinazione COMPLETO. `class`: `live` (webroot/bin/lib/confs/script-on-demand/module.prop) ·
  `soft` (service.sh/post-fs-data.sh/boot-completed.sh) · `reboot` (`zygisk/**/*.so`, `system/**`, `*.rule`).
  Default per path, non fa mai il downgrade `reboot`->`live`.
- `enc`: `gz` (gzip `-9 -n`, deterministico, gunzip di toybox sul dispositivo) solo quando comprime bene E la
  dimensione è significativa, `sha256` è SEMPRE del contenuto originale.
- `sig`: firma del manifest canonico SENZA il campo `sig` (§4 di verify).
- **Esclusione dell'ancora di fiducia (lato-engine, VDLU#2):** l'engine SCARTA dal piano ogni path `files[]`/`delete[]` sotto `vdlu/` (i propri `update.sh`/`vdlu-verify`/`verify/*`/`keyring/*`/config) - mai recuperato, applicato o eliminato - anche se un feed firmato li porta. L'ancora di fiducia on-device cambia solo tramite un re-flash firmato completo, non via cavo, anche `vdlu-pack` esclude `vdlu/` lato-producer, quindi questo è un secondo guard, lato-engine, contro una chiave di firma trapelata.

## 4. journal.json (l'ENGINE scrive, la WEBUI legge - il contratto di progresso)

```json
{ "schema":1, "module":"<id>", "target":<version>, "from":<version>,
  "phase":"diff|fetch|apply|commit", "state":"PLANNED|FETCHING|FETCHED|APPLYING|APPLIED_LIVE|PENDING_REBOOT|DONE|ERROR|DEFERRED",
  "total":<int>, "done":<int>, "current":"<path>", "bytes":<int>, "reboot_pending":bool,
  "cancelled":bool, "error":"<str|null>", "updated":"<ISO8601>",
  "items":[ {"path":"<p>","sha256":"<h>","class":"<c>","st":"pending|fetched|applied|staged|skipped"} ] }
```

Macchina a stati (ordine fisso): `PLANNED->FETCHING->FETCHED->APPLYING->APPLIED_LIVE->(PENDING_REBOOT|DONE)`.
`DONE` solo quando un re-hash di TUTTO combacia. Un REBOOT-hard messo in stage ⇒ `PENDING_REBOOT` (non `DONE`). Uscite
dalla fase `fetch`: `ERROR` (fallimento hard) oppure `DEFERRED` (net_policy ha bloccato il download - benigno/ripristinabile,
non un errore).

## 5. config (key=value, una per riga, modificabile nella WEBUI)

```
auto_on_webui_open=0
auto_on_reboot=1
source=https://<user>.github.io/<repo>/<module>
channel=stable
profile=trusted        # trusted | hardened. CODE DEFAULT (line absent) = hardened (fail-closed, 9a9a824)
net_policy=any         # any (Wi-Fi+mobile) | wifi (Wi-Fi only) | mobile (mobile only) - gates the DOWNLOAD by network type
allow_metered=0        # ⚠️ SUPERSEDED by net_policy (not consumed by the engine)
pubkey_dir=keyring     # relative to $MODULE_DIR/vdlu (keyring of pubkeys for verify)
key_id=                # ALLOWLIST of accepted MODULE-UPDATE signing key id(s), comma-separated (rotation).
                       # UNSET = default-safe: a single-key keyring accepts only that one key; a MULTI-key
                       # keyring (one that also ships a fingerprint-feed key) MUST pin its module key here.
ca_path=               # empty = auto-detect of the Android trust store; set a path to override
ca_cert=               # empty = auto-build a CA bundle from the trust store; set a path to a bundle to override
tools_source=          # empty = derived from source (.../vdlu-tools); feed of the static curl
apply_busy_file=       # OPT-IN: absolute path the host module touches during its own operations (e.g. a
                       # backup). While it EXISTS, APPLY is deferred to the next trigger (blobs already
                       # fetched, no re-download) so an update never swaps module files mid-operation. UNSET = off.
boot_retry_interval=30 # seconds between probes when BOOT finds the device offline (floor 5s)
boot_retry_minutes=0   # ceiling of the PATIENT retry (AWAKE-time) only at boot; 0 = off. Battery-safe (no wakelock,
                       # no held lock, route probe never wakes the radio) -> a generous ceiling is ~free
```

**Boot retry (offline) - PAZIENTE, battery-safe:** solo al `boot` (mai su check/auto-open). Se il fetch del manifest
fallisce per RETE (`fetch_offline` classifica in base all'exit del fetcher), attende e riprova fino al
successo OPPURE all'esaurimento di `boot_retry_minutes` di tempo AWAKE. Un design che **non trattiene nulla e non scarica**:
- **Zero wakelock:** tra i tentativi c'è `sleep`, che si congela in deep-sleep -> il dispositivo dorme normalmente
  (~zero batteria), il retry si mette in pausa e riprende una volta che il dispositivo è già sveglio.
- **Zero lock trattenuto:** `acquire_lock_try`+release TRA i tentativi (non trattiene il lock durante l'attesa) ->
  `run`/check manuale non bloccano mai, se un run manuale mette in stage un TARGET nel frattempo, il boot rinvia.
- **Non sveglia la radio per niente:** un probe `net_allowed` (tramite `net_type`/`ip route get`, un lookup di route del
  kernel che rispetta il policy-routing di Android, nessun pacchetto) regola ogni tentativo - spende un fetch solo una volta
  che la rete è comparsa.
- NON riprova mai un fallimento deterministico (manifest/sig/downgrade). `--connect-timeout 15` sul fetch (non si
  blocca su un captive portal). `service.sh` lo porta in background (il boot non si blocca mai).
- ⛔ **HARD: attivare `boot_retry_minutes>0` richiede l'engine PAZIENTE** (quello con
  `net_allowed`+`acquire_lock_try`, canonico `da7115f4`+). Il PRECEDENTE boot-retry (trattiene il lock per tutta la
  finestra + riprova alla cieca curl offline) **SCARICA la batteria/sveglia la radio** - attivare il retry su un vecchio
  engine è un autogol. Quando lo si abilita, vendorizza l'engine corrente.

**`net_policy` (any|wifi|mobile):** regola il **DOWNLOAD** per tipo di rete. `net_type()` classifica l'egress
di `ip route get` (iface cellulare `rmnet/ccmni/v4-*/clat` = mobile, tutto il resto = wifi, lookup del kernel, nessun
pacchetto). `net_allowed()` confronta con `net_policy` e regola `do_fetch` (blob) + il probe del boot-retry
paziente. Il **check del manifest resta libero** (minuscolo -> la UI segnala un aggiornamento su qualsiasi rete), solo il download
attende la rete consentita. Un download su una rete non consentita = lo stato **`DEFERRED`** nel journal
(NON ERROR, un gentile toast INFO blu "in attesa della rete X", plan/target persistono, riprende al prossimo
check/boot sulla rete giusta). `net_policy` **sostituisce** `allow_metered` (che non è mai stato consumato).
Engine `97baf887`+ (`file://` non è mai regolato).

## 6. Firma (il PRODUCER firma sul PC via openssl, l'ENGINE verifica sul dispositivo via ed25519-mini)

- Canonicalizzazione: il manifest SENZA `sig`, chiavi ordinate, JSON compatto (nessuno spazio superfluo), UTF-8.
  Ciò che viene firmato/verificato = l'esadecimale `sha256` di quella forma canonica (da determinismo cross-tool).
- `producer/vdlu-sign <manifest.json> <privkey.pem> <key_id>` -> inietta `key_id` + `sig` (base64 della firma ed25519 dello sha256 canonico) nel manifest, in place.
- `engine/vdlu-verify <manifest.json> <keyring_dir>` -> rc 0 se la `sig` corrisponde alla pubkey `<key_id>.pub` nel
  keyring (SNELLO: pubkey **RAW 32 byte**). Internamente, nessun openssl: `sha256sum`/`base64 -d` di toybox + il
  binario `ed25519-mini` incorporato (CLI `ed25519-mini <pub32> <msg> <sig64>`, rc 0=valida/1=non valida/2=uso).
  rc!=0 = rifiuto. **`profile=hardened` ⇒ verify obbligatorio, fallimento = abort.**
  `profile=trusted` ⇒ il verify è best-effort (fonte già fidata via SSH), ma l'hash di ogni blob viene SEMPRE controllato.
- **Allowlist della chiave di module-update (fail-closed, prima della selezione della pubkey):** il `key_id` del manifest deve essere una chiave MODULE-UPDATE accettata prima che `<key_id>.pub` venga selezionata - il `key_id` della config (§5) è quella allowlist. Un keyring può portare ANCHE una chiave a fiducia inferiore (es. una chiave di fingerprint-feed, automatizzata, account diverso), senza l'allowlist un manifest firmato da quella chiave verrebbe verificato e applicherebbe un intero aggiornamento root flashless in caso di leak. `verify_manifest` lo impone in ENTRAMBI i profiles e passa l'insieme risolto a `vdlu-verify` tramite l'env `VDLU_KEYID_ALLOW` (così il verificatore standalone concorda). Non impostato è sicuro di default (keyring a chiave singola: solo quella chiave, keyring multichiave: rifiutato finché `key_id` non è fissato). La radice di fiducia del fingerprint-feed è un percorso SEPARATO, con la propria chiave fissata, e non è influenzata.
- `producer/vdlu-keygen <id> <out>` -> genera `<id>.pem` (priv) + `<id>.pub` (PEM, per il tooling sul PC) +
  `<id>.pub.raw` (**RAW 32B** = la `<id>.pub` del keyring snello sul dispositivo). openssl `genpkey -algorithm ed25519`.

## 7. Blob - verifica (ENGINE)

Scarica `<source>/blobs/<sha>` (o `.gz` se `enc=gz`), scrive `.part`, se `gz` decomprime (`gunzip`),
controlla `sha256sum` == lo `sha256` del manifest, corrisponde -> `mv` atomico in `$VDLU_DIR/blobs/<sha>`. 3 fallimenti sullo
stesso blob = aborta la fase (niente applicato). Un blob già in `$VDLU_DIR/blobs/<sha>` con hash ok =
salta il download.

## 8. APPLY per classe (ENGINE)

- `live`/`soft`: backup `rollback/<v>/<path>` -> scrive `$MODULE_DIR/<path>.vdlu-tmp` dal blob -> `chmod mode` ->
  `rename` atomico sulla destinazione. Già all'hash di destinazione = salta. (Nella variante Zygisk la scrittura va alla
  directory montata = merge per-file, mai `rm -rf` della directory.)
- `reboot`: materializza in `$VDLU_DIR/staged/<path>.vdlu-new` (NON tocca quello vivo). Lo swap è al `boot`.
- `delete[]`: backup -> rimuove.

## 9. WEBUI ↔ ENGINE (componente WEBUI)

- Lancia: `ksu.exec("sh $MODULE_DIR/vdlu/update.sh run")` (background).
- Progresso: un poll leggero `ksu.exec("cat $VDLU_DIR/journal.json")` ogni ~1s, renderizza `{phase,state,total,done,current,bytes}`.
- Liveness: journal assente per 8 tick ⇒ "nessuna risposta". Journal CONGELATO (stessi valori) per 20 tick ⇒ controlla `lock.d`: vivo = prosegue (fetch lento di 1 blob), morto = errore + Resume. Senza questo, un run morto a metà fetch congelerebbe il toast su "updating".
- Cancel: `ksu.exec("touch $VDLU_DIR/cancel")`.
- Config: legge/scrive `$VDLU_DIR/config` (key=value) in una scheda "Updates".
- Toast: barra + `phase done/total · current`, al termine con `reboot_pending` ⇒ un banner persistente "riavvia per attivare il .so".
- Auto-open (`auto_on_webui_open=1`): esegue prima un `check()` SILENZIOSO (nessun toast di progresso), lancia il `run`+toast persistente solo se `update && fetch>0`. Aggiornato/ahead/niente-di-nuovo = un risultato inline nel pannello, zero toast residuo. Non intrusivo come il pulsante manuale (il toast compare solo quando c'è un download reale). Il bootstrap del curl è una tantum.

## 10. Integrazione nel demo (componente INTEGRATION) - SNIPPET, non modificare i file live

Produce, in `integration/demo/`, snippet + un `INTEGRATION.md` che dice dove va ognuno (senza applicare):
- l'hook `auto_on_reboot` in `post-fs-data`/`service.sh` (pre-zygote -> `update.sh boot`) e `auto_on_webui_open`.
- i default del `config` + il keyring incorporato + la vendorizzazione (`modules/<mod>/vdlu/`).
- la variante PARZIALE (merge nella directory montata).

## 11. Toolchain recuperata + baseline (SNELLO, Approccio B)

**Layout nel modulo (zip):** `vdlu/{update.sh, vdlu-verify, config.default, keyring/<id>.pub (RAW 32B),
verify/<abi>/ed25519-mini, baseline.json}`. **NESSUN** `bin/` (openssl/curl/zstd). `customize.sh` può potare
`verify/` fino all'ABI del dispositivo (`vdlu-verify` trova il mini in `<dir>/ed25519-mini` OPPURE `<dir>/verify/<abi>/ed25519-mini`).

**ed25519-mini** (binario incorporato, solo-verify): `ed25519-mini <pubkey32> <msg> <sig64>` -> rc 0=valida,
1=non valida, 2=uso/IO. msg = i byte firmati esatti (NON ri-hasha). TweetNaCl PD, statico per-ABI, PROVENANCE.

**tools-feed** (solo profilo pubblico/https): servito a `<tools_source>` (default derivato: scambia l'ultimo segmento
di `source` con `vdlu-tools`, es. `https://<user>.github.io/<repo>/vdlu-tools`). Contiene:
- `tools-manifest.json` - un manifest `vdlu-pack` FIRMATO sull'albero `<abi>/curl`, che fissa lo `sha256` di
  ogni curl (stessa chiave `release-2026`).
- `<abi>/curl` - il curl **statico** GREZZO (autonomo, ~1MB, curl 8.11.1 + mbedTLS). 🪤 mbedTLS NON
  porta con sé un CA bundle: `fetch_url` passa `--capath` (auto-rilevamento del trust store di Android: `/system/etc/security/cacerts`
  -> conscrypt APEX, `ca_path` sovrascrive). Nessun capath = errore 60. L'integrità è l'ed25519, il cert-check è difesa in profondità.

**install-tool** (ENGINE): `update.sh install-tool <abi>` legge `$VDLU_DIR/.work/{tools-manifest.json, tool.<abi>}`
(la WEBUI lo scarica via `fetch()` e lo scrive li), **verifica la firma del tools-manifest (ed25519-mini,
OBBLIGATORIA in qualsiasi profilo)** + l'hash del curl == manifest, e solo allora lo installa in `$VDLU_DIR/tools/<abi>/curl` (0755).
Il curl gira come root -> sig+hash prima dell'exec chiude l'RCE. Persiste in Tier-2: mai ri-scaricato (tranne alla disinstallazione).

**fetch-bootstrap** (WEBUI, `ensureToolchain()`): gira prima di check/run/resume. `file://` = no-op, curl GIÀ
disponibile (Tier-2, OPPURE `module/bin/<abi>/curl` da un modulo **self-bundled**, OPPURE di sistema) = no-op
(VDLU riusa il curl esistente), solo `https` **senza alcun curl** scarica curl + tools-manifest via la webview, li scrive
in `.work` (base64 a chunk via `ksu.exec`), chiama `install-tool`. La fiducia = il controllo on-device, non il download.

> 🪤 **Snello (fetch-bootstrap) ≠ obbligatorio.** Un modulo il cui `bin/` esiste per le SUE PROPRIE feature (es. imbarca
> restic/rclone/age/tar/curl...) **non** si snellisce a ~2MB né scarica curl - VDLU adotta l'engine snello
> (gz, mini, baseline, fix) e **riusa** la toolchain incorporata. Solo i moduli senza una propria toolchain
> guadagnano i ~2MB.

**baseline.json** (fix da:0): la release copia il `manifest.json` FIRMATO della versione spedita in
`vdlu/baseline.json`, a un'installazione pulita l'engine semina `current.json` da esso (`init_paths`, solo se assente) -> il
dispositivo nasce "corrente", senza auto-aggiornamento di sé stesso e senza re-fetch.

<!-- doc-footer -->

---

> _Questa documentazione è stata generata con Claude (Anthropic) ed è gestita da VD171. Correzioni e miglioramenti sono benvenuti, vedi [CONTRIBUTING.md](CONTRIBUTING.md)._
