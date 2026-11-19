> **Languages:** [English](../ENGINE.md) · [العربية](../ar/ENGINE.md) · [Čeština](../cs/ENGINE.md) · Deutsch · [Español](../es/ENGINE.md) · [فارسی](../fa/ENGINE.md) · [Français](../fr/ENGINE.md) · [हिन्दी](../hi/ENGINE.md) · [Bahasa Indonesia](../id/ENGINE.md) · [Italiano](../it/ENGINE.md) · [日本語](../ja/ENGINE.md) · [한국어](../ko/ENGINE.md) · [Nederlands](../nl/ENGINE.md) · [Polski](../pl/ENGINE.md) · [Português](../pt/ENGINE.md) · [Русский](../ru/ENGINE.md) · [Svenska](../sv/ENGINE.md) · [ไทย](../th/ENGINE.md) · [Türkçe](../tr/ENGINE.md) · [Українська](../uk/ENGINE.md) · [Tiếng Việt](../vi/ENGINE.md) · [中文](../zh/ENGINE.md)

---

# VDLU-Engine (`update.sh`)

Flashloser, inkrementeller Update-Client fuer KSU/Magisk-Module. Implementiert den
`DIFF -> FETCH -> APPLY -> COMMIT`-Zyklus als wiederaufnehmbare Transaktion. Richtet sich nach `INTERFACES.md` (dem Gesetz
der Konvergenz).

Reines POSIX sh (mksh/busybox/toybox). **SCHLANK:** haengt nur von toybox ab (`sha256sum`/`gzip`/`base64`/`date`) +
dem eingebetteten `ed25519-mini` (ed25519 verify; **kein openssl auf dem Geraet**) + einem statischen `curl`, das beim
ersten https-Update **geholt** wird (die WebUI macht das `fetch()`, persistiert es in Tier-2, und `install-tool` verifiziert seine
Signatur+Hash VOR der Verwendung). `file://` braucht kein curl. Null Abhaengigkeit von `jq`.

## Aufruf

```sh
VDLU_DIR=/data/adb/<mod>/vdlu MODULE_DIR=/data/adb/modules/<mod> MODID=<mod> \
  sh $MODULE_DIR/vdlu/update.sh <cmd>
```

`rc 0` = ok; `rc != 0` = Fehler (Grund auf stderr). `vdlu-verify` wird von einer anderen Komponente geliefert
(Signatur in `INTERFACES.md §6`); die Engine ruft es nur auf.

| cmd | tut |
|---|---|
| `check` | read-only DIFF; gibt `{"update":bool,"from":N,"to":M,"fetch":K,"reboot":bool}` aus; aendert nichts |
| `run` | voller LIVE-Zyklus + staget REBOOT-hard; beachtet `cancel`; Fortschritt in `journal.json` |
| `resume` | nimmt die anstehende Transaktion (`target.json`) ab der aktuellen Phase wieder auf; idempotent; swapt die `.so` **nicht** |
| `boot` | Pre-Zygote-Modus: resume **+** swapt die `staged/*.vdlu-new` -> schliesst `PENDING_REBOOT`->`DONE`. Ohne anstehende Transaktion fuehrt es einen frischen Zyklus aus und wendet alles (einschliesslich der `.so`) in einem einzigen Boot an |
| `status` | gibt `journal.json` aus (oder `{"state":"idle"}`) |
| `cancel` | erzeugt `$VDLU_DIR/cancel`; ein laufendes `run` stoppt am naechsten sicheren Punkt |

## Zustandsautomat (journal.json)

```
PLANNED -> FETCHING -> FETCHED -> APPLYING -> APPLIED_LIVE -> (PENDING_REBOOT | DONE)
```

`DONE` erst, sobald ein erneutes Hashen von ALLEM uebereinstimmt. Falls irgendein REBOOT-hard gestaget wurde => `PENDING_REBOOT` (niemals ein
faelschliches `DONE`). `ERROR` bei jedem Fehler, ohne das Modul zu beschaedigen (die angewandten LIVE-Dateien werden
aus `rollback/<v>/` zurueckgesetzt; nichts "halb angewandt, das darueber luegt"). Gutartiger Austritt der `fetch`-Phase: **`DEFERRED`** -
der Download wurde von `net_policy` verschoben (Netzwerk nicht erlaubt); plan/target bleiben erhalten und es nimmt beim naechsten
Check/Boot wieder auf (die WebUI zeigt einen blauen Info-Toast "waiting for X network", keinen Fehler).

## Strenge-Garantien

- **FETCH:** gated durch `net_policy` (any/wifi/mobile; nur http/https, `file://` nie) - ein nicht-erlaubtes Netzwerk =>
  `DEFERRED` (wiederaufnehmbar), ohne Daten auszugeben. Laedt nur, was fehlt, in `<sha>.part` (curl mit
  `--connect-timeout` + `--speed-time`, haengt nie), dekomprimiert `gz` (toybox `gunzip`), prueft `sha256sum` ==
  Manifest, atomares `mv` nach `blobs/<sha>`. Ein gecachter+ok Blob wird uebersprungen. Es kann den Blob aus einer unveraenderten
  lokalen Datei seeden (dedup/offline). **3 Fehlschlaege beim selben Blob = die Phase bricht ab, ohne etwas anzuwenden.** Es
  wird erst `FETCHED`, wenn ALLE Blobs des Plans vorhanden+verifiziert sind.
- **APPLY** (nur aus `FETCHED`): `live`/`soft` -> Backup nach `rollback/<v>/` -> `.vdlu-tmp` -> `chmod` -> verify ->
  atomares `rename`. `reboot` -> materialisiert in `staged/<path>.vdlu-new` (beruehrt den Live-Inode NICHT).
  `delete[]` -> Backup -> entfernen. Idempotent (eine Datei, die bereits beim Ziel-Hash ist, wird uebersprungen).
- **COMMIT:** erneutes Hashen jedes `live`/`soft`; erst dann schreibt es `current.json`. Mit gestageten Dateien =>
  `PENDING_REBOOT`. `boot` macht `mv -f staged/....vdlu-new $MODULE_DIR/<path>` (pre-zygote) + re-verifiziert +
  `DONE`.
- **cancel:** zwischen Dateien geprueft (sicherer Punkt); entfernt die im Flug befindliche `.vdlu-tmp`/`.part`, loescht `cancel`,
  laesst das Journal wiederaufnehmbar (`cancelled:true`, `error:null`).
- **mkdir-lock `$VDLU_DIR/lock.d`** serialisiert (flock ist auf toybox nicht praktikabel; stale-recovery per PID). Der
  GEDULDIGE Boot-Retry haelt das Lock nicht waehrend des Wartens (`acquire_lock_try`+release zwischen den Versuchen) noch einen
  Wakelock - batterieschonend. Ein Crash/Netzwerk/Reboot mittendrin -> `resume`/`boot` macht weiter.
- **profile=hardened** => `vdlu-verify` obligatorisch auf dem Manifest VOR der Verwendung; Fehler = Abbruch; Downgrade blockiert
  (monotone Version). **trusted** => verify ist best-effort, aber der Hash jedes Blobs wird IMMER geprueft.
- Degradiert anstaendig: fehlendes Binary / Netzwerk down / Platte voll -> ein klarer Fehler auf stderr + `state:ERROR` im
  Journal, ohne das Modul zu beschaedigen.

## JSON-Parsing ohne jq

Ein gron-artiger Flattener in `awk` (reines POSIX: `substr`/`index`/`gsub`/`split`/`printf` + als Parameter uebergebene
Locals) tokenisiert das Manifest Zeichen fuer Zeichen und emittiert eine `path<TAB>value`-Zeile pro skalarem Blatt
(`files/0/sha256<TAB>ab..`, `version<TAB>6`, `delete/0<TAB>etc/x`). Robust gegen kompaktes ODER pretty-printed
JSON. Das `sh` konsumiert es mit `grep`/`cut`; der Plan pro Datei wird in einem 2. `awk` zu TSV zusammengesetzt
(`class st mode enc sha size path`), das zu `$VDLU_DIR/plan.tsv` wird.

## State-Dateien (in `$VDLU_DIR`, Tier-2)

| Datei | Rolle |
|---|---|
| `config` | key=value (`source`/`profile`/`channel`/`net_policy`/`boot_retry_*`/…; siehe INTERFACES §5) |
| `current.json` | Manifest der AKTIVEN Version (diff base); abwesend = nie aktualisiert |
| `target.json` | gepinntes Manifest der im Flug befindlichen Transaktion (Praesenz = aktive Transaktion); wird bei `DONE` zu `current.json` |
| `plan.tsv` / `plan.del` | Plan + Fortschritt pro Datei (st) / zu loeschende Pfade |
| `journal.json` | Fortschritt fuer die WebUI (bei jedem Uebergang neu erzeugt) |
| `blobs/<sha256>` | Cache verifizierten Originalinhalts |
| `rollback/<version>/<path>` | Backup ueberschriebener Dateien (undo; behaelt die letzten 3) |
| `staged/<path>.vdlu-new` | REBOOT-hard, das auf den Swap beim Boot wartet |
| `lock.d/` | mkdir-lock (flock auf toybox nicht praktikabel; stale-recovery per PID) |
| `tools/<abi>/curl` | geholtes statisches curl (schlankes Bootstrap); persistiert ueber Updates hinweg |
| `cancel` | Cancel-Anfrage |

<!-- doc-footer -->

---

> _Diese Dokumentation wurde mit Claude (Anthropic) erstellt und wird von VD171 gepflegt. Korrekturen und Verbesserungen sind willkommen; siehe [CONTRIBUTING.md](CONTRIBUTING.md)._
