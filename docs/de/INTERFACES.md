> **Languages:** [English](../INTERFACES.md) · [العربية](../ar/INTERFACES.md) · [Čeština](../cs/INTERFACES.md) · Deutsch · [Español](../es/INTERFACES.md) · [فارسی](../fa/INTERFACES.md) · [Français](../fr/INTERFACES.md) · [हिन्दी](../hi/INTERFACES.md) · [Bahasa Indonesia](../id/INTERFACES.md) · [Italiano](../it/INTERFACES.md) · [日本語](../ja/INTERFACES.md) · [한국어](../ko/INTERFACES.md) · [Nederlands](../nl/INTERFACES.md) · [Polski](../pl/INTERFACES.md) · [Português](../pt/INTERFACES.md) · [Русский](../ru/INTERFACES.md) · [Svenska](../sv/INTERFACES.md) · [ไทย](../th/INTERFACES.md) · [Türkçe](../tr/INTERFACES.md) · [Українська](../uk/INTERFACES.md) · [Tiếng Việt](../vi/INTERFACES.md) · [中文](../zh/INTERFACES.md)

---

# VDLU - Schnittstellenvertrag (die Naht zwischen den Komponenten)

**Gesetz der Konvergenz:** jede Komponente richtet sich nach dieser Datei. Die Teile von 4 Agenten muessen **zusammenpassen** - die
CLI-Signaturen, Dateinamen und JSON-Schluessel unten sind **unveraenderlich** (eine Aenderung bedeutet, zuerst hier anzugleichen).

Von den Repos geerbte Prinzipien: **reines POSIX sh** auf dem Geraet (keine Bashismen; laeuft mit toybox/busybox +
toybox' `sha256sum`/`gzip`/`base64` + dem geholten `curl` + dem eingebetteten `ed25519-mini` - schlank, kein Binaer-Bundle),
**keine ueberfluessigen Kommentare**, **immer release**, **Strenge bei Fehlern** (wiederaufnehmbare Transaktion, nichts faelschlich
"erledigt", nichts verloren), **nichts gelockert**.

---

## 1. State-Layout (Tier-2, ausserhalb des Modulverzeichnisses)

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
`cancelled:true` im Journal = die Engine stoppte bei einem Cancel (ein nicht-terminaler, wiederaufnehmbarer Zustand; `error`
bleibt null).

Engine im Modul eingebettet: `$MODULE_DIR/vdlu/update.sh` (+ `vdlu-verify`). `$MODULE_DIR =
/data/adb/modules/<module>`. Die Engine erhaelt per env: `VDLU_DIR`, `MODULE_DIR`, `MODID`.

## 2. Engine-CLI (ENGINE-Komponente)

`sh update.sh <cmd>` - rc 0 = ok, !=0 = Fehler (stderr hat den Grund):

| cmd | tut |
|---|---|
| `check` | DIFF: laedt das Manifest, vergleicht; gibt ein einzeiliges JSON `{"update":bool,"from":N,"to":M,"fetch":K,"reboot":bool}` aus; aendert nichts. Geraet VOR dem Feed (Downgrade blockiert, gehaertet) = ein GUTARTIGER Zustand: `{"update":false,"ahead":true,"from":N,"to":M}` + rc0 (niemals "check failed"). do_diff rc: 2 fetch/parse, 3 verify/meta, 4 ahead |
| `run` | voller Zyklus: DIFF->FETCH->APPLY->COMMIT; beachtet `cancel`; schreibt den Fortschritt in `journal.json`; wendet LIVE an, staget REBOOT-hard |
| `resume` | nimmt die `journal.json`-Transaktion ab der aktuellen Phase wieder auf (idempotent) |
| `boot` | Pre-Zygote-Modus: `resume` + macht den SWAP der `staged/*.vdlu-new` (wendet die `.so` an), schliesst `PENDING_REBOOT`->`DONE` |
| `status` | gibt `journal.json` aus (oder `{"state":"idle"}`) |
| `cancel` | erzeugt `$VDLU_DIR/cancel` (ein laufendes `run` stoppt am naechsten sicheren Punkt) |

Blob-/Manifest-Quelle: `source` aus der config. `<source>` + `/manifest.json`, `/blobs/<sha>`, `/blobs/<sha>.gz`.
`source` beginnt mit `https://` (statisches, per curl geholtes, TLS) oder `file://` (lokales Staging).

## 3. manifest.json (vom PRODUCER erzeugt, vom ENGINE konsumiert)

```json
{ "schema":1, "module":"<id>", "version":<int>, "version_name":"<str>", "built":"<ISO8601>",
  "engine_min":3, "key_id":"<str>", "channel":"stable",
  "files":[ {"path":"webroot/index.html","sha256":"<hex64>","size":<int>,"mode":"0644","enc":"raw|gz","class":"live|soft|reboot"} ],
  "delete":["<path>"], "sig":"<base64>" }
```

- `files[]` = der VOLLSTAENDIGE Zielbaum. `class`: `live` (webroot/bin/lib/confs/scripts-on-demand/module.prop) ·
  `soft` (service.sh/post-fs-data.sh/boot-completed.sh) · `reboot` (`zygisk/**/*.so`, `system/**`, `*.rule`).
  Standard nach Pfad; stuft `reboot`->`live` niemals herab.
- `enc`: `gz` (gzip `-9 -n`, deterministisch; toybox gunzip auf dem Geraet) nur wenn es sich gut komprimiert UND die
  Groesse signifikant ist; `sha256` ist IMMER vom Originalinhalt.
- `sig`: Signatur des kanonischen Manifests OHNE das `sig`-Feld (§4 von verify).

## 4. journal.json (ENGINE schreibt, WEBUI liest - der Fortschrittsvertrag)

```json
{ "schema":1, "module":"<id>", "target":<version>, "from":<version>,
  "phase":"diff|fetch|apply|commit", "state":"PLANNED|FETCHING|FETCHED|APPLYING|APPLIED_LIVE|PENDING_REBOOT|DONE|ERROR|DEFERRED",
  "total":<int>, "done":<int>, "current":"<path>", "bytes":<int>, "reboot_pending":bool,
  "cancelled":bool, "error":"<str|null>", "updated":"<ISO8601>",
  "items":[ {"path":"<p>","sha256":"<h>","class":"<c>","st":"pending|fetched|applied|staged|skipped"} ] }
```

Zustandsautomat (feste Reihenfolge): `PLANNED->FETCHING->FETCHED->APPLYING->APPLIED_LIVE->(PENDING_REBOOT|DONE)`.
`DONE` erst, sobald ein erneutes Hashen von ALLEM uebereinstimmt. Ein gestageter REBOOT-hard => `PENDING_REBOOT` (nicht `DONE`). Austritte
aus der `fetch`-Phase: `ERROR` (harter Fehler) oder `DEFERRED` (net_policy blockierte den Download - gutartig/wiederaufnehmbar,
kein Fehler).

## 5. config (key=value, eines pro Zeile; in der WEBUI editierbar)

```
auto_on_webui_open=0
auto_on_reboot=1
source=https://<user>.github.io/<repo>/<module>
channel=stable
profile=trusted        # trusted | hardened. CODE DEFAULT (line absent) = hardened (fail-closed, 9a9a824)
net_policy=any         # any (Wi-Fi+mobile) | wifi (Wi-Fi only) | mobile (mobile only) - gates the DOWNLOAD by network type
allow_metered=0        # ⚠️ SUPERSEDED by net_policy (not consumed by the engine)
pubkey_dir=keyring     # relative to $MODULE_DIR/vdlu (keyring of pubkeys for verify)
ca_path=               # empty = auto-detect of the Android trust store; set a path to override
tools_source=          # empty = derived from source (.../vdlu-tools); feed of the static curl
boot_retry_interval=30 # seconds between probes when BOOT finds the device offline (floor 5s)
boot_retry_minutes=0   # ceiling of the PATIENT retry (AWAKE-time) only at boot; 0 = off. Battery-safe (no wakelock,
                       # no held lock, route probe never wakes the radio) -> a generous ceiling is ~free
```

**Boot-Retry (offline) - GEDULDIG, batterieschonend:** nur bei `boot` (nie bei check/auto-open). Wenn das Manifest-
Fetch wegen des NETZWERKS fehlschlaegt (`fetch_offline` klassifiziert anhand des Exit-Codes des Fetchers), wartet es und wiederholt es bis
zum Erfolg ODER bis `boot_retry_minutes` an AWAKE-Zeit aufgebraucht sind. Ein Design, das **nichts haelt und nicht drainiert**:
- **Null Wakelock:** zwischen den Versuchen ist es ein `sleep`, das im Deep-Sleep einfriert -> das Geraet schlaeft normal
  (~null Batterie); der Retry pausiert und nimmt wieder auf, sobald das Geraet ohnehin wach ist.
- **Null gehaltenes Lock:** `acquire_lock_try`+release ZWISCHEN den Versuchen (haelt das Lock nicht waehrend des Wartens) ->
  `run`/manueller Check blockieren nie; wenn ein manuelles Run in der Zwischenzeit ein TARGET staget, verschiebt sich der Boot.
- **Weckt das Radio nicht fuer nichts:** ein `net_allowed`-Probe (via `net_type`/`ip route get`, ein Kernel-Route-
  Lookup, der Androids Policy-Routing respektiert; kein Paket) gated jeden Versuch - es gibt ein Fetch erst aus, sobald das
  Netzwerk erschienen ist.
- Wiederholt NIEMALS einen deterministischen Fehler (manifest/sig/downgrade). `--connect-timeout 15` beim Fetch (haengt nicht
  an einem Captive Portal). `service.sh` legt es in den Hintergrund (Boot haengt nie).
- ⛔ **HART: `boot_retry_minutes>0` einzuschalten erfordert die GEDULDIGE Engine** (die mit
  `net_allowed`+`acquire_lock_try`, kanonisch `da7115f4`+). Der VORHERIGE Boot-Retry (haelt das Lock das ganze
  Fenster + wiederholt blindes curl offline) **DRAINIERT die Batterie/weckt das Radio** - den Retry in einer alten
  Engine einzuschalten ist ein Footgun. Beim Aktivieren die aktuelle Engine einbetten.

**`net_policy` (any|wifi|mobile):** gated den **DOWNLOAD** nach Netzwerktyp. `net_type()` klassifiziert den Egress
von `ip route get` (Mobilfunk-iface `rmnet/ccmni/v4-*/clat` = mobile; alles andere = wifi; Kernel-Lookup, kein
Paket). `net_allowed()` vergleicht mit `net_policy` und gated `do_fetch` (Blobs) + den geduldigen Boot-Retry-
Probe. Der **Manifest-Check bleibt frei** (winzig -> die UI meldet ein Update in jedem Netzwerk); nur der Download
wartet auf das erlaubte Netzwerk. Ein Download in einem nicht-erlaubten Netzwerk = der **`DEFERRED`**-Zustand im Journal
(NICHT ERROR; ein sanfter blauer INFO-Toast "waiting for X network"; plan/target bleiben erhalten, es nimmt beim naechsten
Check/Boot im richtigen Netzwerk wieder auf). `net_policy` **ersetzt** `allow_metered` (das nie konsumiert wurde).
Engine `97baf887`+ (`file://` wird nie gated).

## 6. Signatur (PRODUCER signiert auf dem PC via openssl; ENGINE verifiziert auf dem Geraet via ed25519-mini)

- Kanonisierung: das Manifest OHNE `sig`, Schluessel sortiert, kompaktes JSON (keine ueberfluessigen Leerzeichen), UTF-8.
  Was signiert/verifiziert wird = der `sha256`-Hex dieser kanonischen Form (ergibt werkzeuguebergreifenden Determinismus).
- `producer/vdlu-sign <manifest.json> <privkey.pem> <key_id>` -> injiziert `key_id` + `sig` (base64 der ed25519-Signatur des kanonischen sha256) in das Manifest, an Ort und Stelle.
- `engine/vdlu-verify <manifest.json> <keyring_dir>` -> rc 0, wenn die `sig` zum `<key_id>.pub`-Pubkey im
  Keyring passt (SCHLANK: Pubkey **RAW 32 Byte**). Intern, kein openssl: toybox `sha256sum`/`base64 -d` + das
  eingebettete `ed25519-mini`-Binary (CLI `ed25519-mini <pub32> <msg> <sig64>`, rc 0=gueltig/1=ungueltig/2=usage).
  rc!=0 = Ablehnung. **`profile=hardened` => verify obligatorisch; Fehler = Abbruch.**
  `profile=trusted` => verify ist best-effort (Quelle bereits via SSH vertraut), aber der Hash jedes Blobs wird IMMER geprueft.
- `producer/vdlu-keygen <id> <out>` -> erzeugt `<id>.pem` (priv) + `<id>.pub` (PEM, fuer Tooling auf dem PC) +
  `<id>.pub.raw` (**RAW 32B** = der `<id>.pub` des schlanken Keyrings auf dem Geraet). openssl `genpkey -algorithm ed25519`.

## 7. Blob - Verifikation (ENGINE)

Laedt `<source>/blobs/<sha>` (oder `.gz` falls `enc=gz`), schreibt `.part`, falls `gz` dekomprimiert (`gunzip`),
prueft `sha256sum` == das `sha256` des Manifests; Treffer -> atomares `mv` nach `$VDLU_DIR/blobs/<sha>`. 3 Fehlschlaege beim
selben Blob = bricht die Phase ab (nichts angewandt). Ein Blob, der bereits in `$VDLU_DIR/blobs/<sha>` mit einem ok Hash liegt =
ueberspringt den Download.

## 8. APPLY nach Klasse (ENGINE)

- `live`/`soft`: Backup `rollback/<v>/<path>` -> schreibt `$MODULE_DIR/<path>.vdlu-tmp` aus dem Blob -> `chmod mode` ->
  atomares `rename` ueber das Ziel. Bereits beim Ziel-Hash = skip. (In der Zygisk-Variante geht der Schreibvorgang in das
  gemountete Verzeichnis = Merge pro Datei, niemals `rm -rf` des Verzeichnisses.)
- `reboot`: materialisiert in `$VDLU_DIR/staged/<path>.vdlu-new` (beruehrt die Live-Datei NICHT). Der Swap ist beim `boot`.
- `delete[]`: Backup -> entfernen.

## 9. WEBUI <-> ENGINE (WEBUI-Komponente)

- Feuert: `ksu.exec("sh $MODULE_DIR/vdlu/update.sh run")` (Hintergrund).
- Fortschritt: ein leichter Poll `ksu.exec("cat $VDLU_DIR/journal.json")` etwa jede ~1s; rendert `{phase,state,total,done,current,bytes}`.
- Liveness: Journal fuer 8 Ticks abwesend => "no response". Journal EINGEFROREN (gleiche Werte) fuer 20 Ticks => prueft `lock.d`: lebendig = macht weiter (langsames Fetch von 1 Blob), tot = Fehler + Resume. Ohne dies wuerde ein Run, der mitten im Fetch starb, den Toast bei "updating" einfrieren.
- Cancel: `ksu.exec("touch $VDLU_DIR/cancel")`.
- Config: liest/schreibt `$VDLU_DIR/config` (key=value) in einem "Updates"-Tab.
- Toast: Balken + `phase done/total · current`; bei Abschluss mit `reboot_pending` => ein persistentes Banner "reboot to activate the .so".
- Auto-open (`auto_on_webui_open=1`): macht zuerst einen STILLEN `check()` (kein Fortschritts-Toast); feuert das `run`+persistenten Toast nur, wenn `update && fetch>0`. Aktuell/voraus/nichts-Neues = ein Inline-Ergebnis im Panel, kein uebrig gebliebener Toast. Nicht aufdringlich wie der manuelle Button (der Toast erscheint nur, wenn es einen echten Download gibt). Das curl-Bootstrap ist einmalig.

## 10. Integration in die Demo (INTEGRATION-Komponente) - SNIPPETS, die Live-Dateien nicht editieren

Erzeugt, in `integration/demo/`, Snippets + eine `INTEGRATION.md`, die sagt, wohin jedes gehoert (ohne es anzuwenden):
- der `auto_on_reboot`-Hook in `post-fs-data`/`service.sh` (pre-zygote -> `update.sh boot`) und `auto_on_webui_open`.
- die `config`-Standardwerte + das eingebettete Keyring + das Vendoring (`modules/<mod>/vdlu/`).
- die PARTIELLE Variante (Merge in das gemountete Verzeichnis).

## 11. Geholte Toolchain + Baseline (SCHLANK, Ansatz B)

**Layout im Modul (zip):** `vdlu/{update.sh, vdlu-verify, config.default, keyring/<id>.pub (RAW 32B),
verify/<abi>/ed25519-mini, baseline.json}`. **KEIN** `bin/` (openssl/curl/zstd). `customize.sh` kann
`verify/` auf die ABI des Geraets reduzieren (`vdlu-verify` findet das mini unter `<dir>/ed25519-mini` ODER `<dir>/verify/<abi>/ed25519-mini`).

**ed25519-mini** (eingebettetes Binary, nur-verify): `ed25519-mini <pubkey32> <msg> <sig64>` -> rc 0=gueltig,
1=ungueltig, 2=usage/IO. msg = die exakten signierten Bytes (hasht NICHT erneut). TweetNaCl PD, statisch pro ABI, PROVENANCE.

**tools-feed** (nur public/https-Profil): bereitgestellt unter `<tools_source>` (Standard abgeleitet: tauscht das letzte Segment
von `source` gegen `vdlu-tools`, z.B. `https://<user>.github.io/<repo>/vdlu-tools`). Enthaelt:
- `tools-manifest.json` - ein SIGNIERTES `vdlu-pack`-Manifest ueber den `<abi>/curl`-Baum, das den `sha256` jedes
  curl pinnt (gleicher `release-2026`-Schluessel).
- `<abi>/curl` - das ROHE **statische** curl (eigenstaendig, ~1MB; curl 8.11.1 + mbedTLS). 🪤 mbedTLS traegt KEIN
  CA-Bundle: `fetch_url` uebergibt `--capath` (Auto-Erkennung des Android-Trust-Stores: `/system/etc/security/cacerts`
  -> APEX conscrypt; `ca_path` ueberschreibt). Kein capath = Fehler 60. Die Integritaet ist das ed25519; der Cert-Check ist Defense-in-Depth.

**install-tool** (ENGINE): `update.sh install-tool <abi>` liest `$VDLU_DIR/.work/{tools-manifest.json, tool.<abi>}`
(die WEBUI laedt es via `fetch()` und schreibt es dorthin), **verifiziert die tools-manifest-Signatur (ed25519-mini,
OBLIGATORISCH in jedem Profil)** + den Hash des curl == Manifest, und installiert es erst dann nach `$VDLU_DIR/tools/<abi>/curl` (0755).
Das curl laeuft als root -> sig+hash vor exec schliesst das RCE. Persistiert in Tier-2: wird nie erneut heruntergeladen (ausser bei Deinstallation).

**fetch-bootstrap** (WEBUI, `ensureToolchain()`): laeuft vor check/run/resume. `file://` = no-op; curl BEREITS
verfuegbar (Tier-2, ODER `module/bin/<abi>/curl` aus einem **selbst-gebundelten** Modul, ODER System) = no-op
(VDLU verwendet das vorhandene curl wieder); nur `https` **ganz ohne curl** laedt curl + tools-manifest via den Webview, schreibt
sie nach `.work` (gechunktes base64 via `ksu.exec`), ruft `install-tool` auf. Trust = die On-Device-Pruefung, nicht der Download.

> 🪤 **Schlank (fetch-bootstrap) != obligatorisch.** Ein Modul, dessen `bin/` fuer SEINE EIGENEN Features existiert (z.B. es bundelt
> restic/rclone/age/tar/curl...), **verschlankt sich nicht** auf ~2MB und laedt kein curl - VDLU uebernimmt die schlanke Engine
> (gz, mini, baseline, Fixes) und **verwendet** die eingebettete Toolchain **wieder**. Nur Module ohne eigene Toolchain
> gewinnen die ~2MB.

**baseline.json** (Fix from:0): das Release kopiert das SIGNIERTE `manifest.json` der ausgelieferten Version nach
`vdlu/baseline.json`; bei einer frischen Installation seedet die Engine `current.json` daraus (`init_paths`, nur wenn abwesend) -> das
Geraet wird "current" geboren, ohne Auto-Update seiner selbst und ohne Re-Fetch.

<!-- doc-footer -->

---

> _Diese Dokumentation wurde mit Claude (Anthropic) erstellt und wird von VD171 gepflegt. Korrekturen und Verbesserungen sind willkommen; siehe [CONTRIBUTING.md](CONTRIBUTING.md)._
