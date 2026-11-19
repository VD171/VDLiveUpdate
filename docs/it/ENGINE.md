> **Languages:** [English](../ENGINE.md) · [العربية](../ar/ENGINE.md) · [Čeština](../cs/ENGINE.md) · [Deutsch](../de/ENGINE.md) · [Español](../es/ENGINE.md) · [فارسی](../fa/ENGINE.md) · [Français](../fr/ENGINE.md) · [हिन्दी](../hi/ENGINE.md) · [Bahasa Indonesia](../id/ENGINE.md) · Italiano · [日本語](../ja/ENGINE.md) · [한국어](../ko/ENGINE.md) · [Nederlands](../nl/ENGINE.md) · [Polski](../pl/ENGINE.md) · [Português](../pt/ENGINE.md) · [Русский](../ru/ENGINE.md) · [Svenska](../sv/ENGINE.md) · [ไทย](../th/ENGINE.md) · [Türkçe](../tr/ENGINE.md) · [Українська](../uk/ENGINE.md) · [Tiếng Việt](../vi/ENGINE.md) · [中文](../zh/ENGINE.md)

---

# Engine VDLU (`update.sh`)

Client di aggiornamento flashless e incrementale per moduli KSU/Magisk. Implementa il
ciclo `DIFF -> FETCH -> APPLY -> COMMIT` come una transazione ripristinabile. Si conforma a `INTERFACES.md` (la legge
di convergenza).

sh POSIX puro (mksh/busybox/toybox). **SNELLO:** dipende solo da toybox (`sha256sum`/`gzip`/`base64`/`date`) +
l'`ed25519-mini` incorporato (verify ed25519; **niente openssl sul dispositivo**) + un `curl` statico **recuperato** al
primo aggiornamento https (la WebUI fa il `fetch()`, lo persiste in Tier-2, e `install-tool` ne verifica la
firma+hash PRIMA di usarlo). `file://` non ha bisogno di curl. Zero dipendenza da `jq`.

## Invocazione

```sh
VDLU_DIR=/data/adb/<mod>/vdlu MODULE_DIR=/data/adb/modules/<mod> MODID=<mod> \
  sh $MODULE_DIR/vdlu/update.sh <cmd>
```

`rc 0` = ok; `rc != 0` = errore (motivo su stderr). `vdlu-verify` e fornito da un altro componente
(firma in `INTERFACES.md §6`); l'engine si limita a chiamarlo.

| cmd | fa |
|---|---|
| `check` | DIFF in sola lettura; stampa `{"update":bool,"from":N,"to":M,"fetch":K,"reboot":bool}`; non cambia nulla |
| `run` | ciclo LIVE completo + mette in stage i REBOOT-hard; rispetta `cancel`; progresso in `journal.json` |
| `resume` | riprende la transazione in sospeso (`target.json`) dalla fase corrente; idempotente; **non** fa lo swap del `.so` |
| `boot` | modalita pre-zygote: resume **+** fa lo swap dei `staged/*.vdlu-new` -> chiude `PENDING_REBOOT`->`DONE`. Senza una transazione in sospeso, esegue un ciclo fresco e applica tutto (incluso il `.so`) in un singolo boot |
| `status` | stampa `journal.json` (oppure `{"state":"idle"}`) |
| `cancel` | crea `$VDLU_DIR/cancel`; un `run` in corso si ferma al prossimo punto sicuro |

## Macchina a stati (journal.json)

```
PLANNED -> FETCHING -> FETCHED -> APPLYING -> APPLIED_LIVE -> (PENDING_REBOOT | DONE)
```

`DONE` solo quando un re-hash di TUTTO combacia. Se un qualsiasi REBOOT-hard e stato messo in stage ⇒ `PENDING_REBOOT` (mai un
falso `DONE`). `ERROR` su qualsiasi fallimento, senza corrompere il modulo (i file LIVE applicati vengono ripristinati
da `rollback/<v>/`; niente di "mezzo-applicato che mente a riguardo"). Uscita benigna dalla fase `fetch`: **`DEFERRED`** -
il download e stato rinviato da `net_policy` (rete non consentita); plan/target persistono e riprende al prossimo
check/boot (la WebUI mostra un toast info blu "in attesa della rete X", non un errore).

## Garanzie di rigore

- **FETCH:** regolato da `net_policy` (any/wifi/mobile; solo http/https, `file://` mai) - una rete non consentita ⇒
  `DEFERRED` (ripristinabile), senza spendere dati. Scarica solo cio che manca in `<sha>.part` (curl con
  `--connect-timeout` + `--speed-time`, non si blocca mai), decomprime `gz` (toybox `gunzip`), controlla `sha256sum` ==
  manifest, `mv` atomico in `blobs/<sha>`. Un blob in cache+ok viene saltato. Puo seminare il blob da un file
  locale invariato (dedup/offline). **3 fallimenti sullo stesso blob = la fase aborta senza applicare nulla.** Diventa
  `FETCHED` solo quando TUTTI i blob del piano sono presenti+verificati.
- **APPLY** (solo da `FETCHED`): `live`/`soft` -> backup in `rollback/<v>/` -> `.vdlu-tmp` -> `chmod` -> verify ->
  `rename` atomico. `reboot` -> materializza in `staged/<path>.vdlu-new` (NON tocca l'inode vivo).
  `delete[]` -> backup -> rimuove. Idempotente (un file gia all'hash di destinazione viene saltato).
- **COMMIT:** re-hash di ogni `live`/`soft`; solo allora scrive `current.json`. Con file in stage ⇒
  `PENDING_REBOOT`. `boot` fa `mv -f staged/....vdlu-new $MODULE_DIR/<path>` (pre-zygote) + ri-verifica +
  `DONE`.
- **cancel:** controllato tra i file (punto sicuro); rimuove il `.vdlu-tmp`/`.part` in volo, elimina `cancel`,
  lascia il journal ripristinabile (`cancelled:true`, `error:null`).
- **lock-mkdir `$VDLU_DIR/lock.d`** serializza (flock non praticabile su toybox; recupero da stale per PID). Il
  boot-retry PAZIENTE non trattiene il lock durante l'attesa (`acquire_lock_try`+release tra i tentativi) ne un
  wakelock - battery-safe. Un crash/rete/reboot a meta -> `resume`/`boot` prosegue.
- **profile=hardened** ⇒ `vdlu-verify` obbligatorio sul manifest PRIMA dell'uso; fallimento = abort; downgrade bloccato
  (versione monotona). **trusted** ⇒ il verify e best-effort, ma l'hash di ogni blob viene SEMPRE controllato.
- Degrada con eleganza: binario mancante / rete giu / disco pieno -> un errore chiaro su stderr + `state:ERROR` nel
  journal, senza corrompere il modulo.

## Parsing JSON senza jq

Un flattener stile gron in `awk` (POSIX puro: `substr`/`index`/`gsub`/`split`/`printf` + locali passate come
parametri) tokenizza il manifest carattere per carattere ed emette una riga `path<TAB>value` per ogni foglia scalare
(`files/0/sha256<TAB>ab..`, `version<TAB>6`, `delete/0<TAB>etc/x`). Robusto contro JSON compatto O pretty-printed.
Lo `sh` lo consuma con `grep`/`cut`; il piano per-file viene riassemblato in un 2° `awk` in TSV
(`class st mode enc sha size path`), che diventa `$VDLU_DIR/plan.tsv`.

## File di stato (in `$VDLU_DIR`, Tier-2)

| file | ruolo |
|---|---|
| `config` | key=value (`source`/`profile`/`channel`/`net_policy`/`boot_retry_*`/…; vedi INTERFACES §5) |
| `current.json` | manifest della versione ATTIVA (base del diff); assente = mai aggiornato |
| `target.json` | manifest fissato della transazione in volo (presenza = transazione attiva); diventa `current.json` su `DONE` |
| `plan.tsv` / `plan.del` | piano + progresso per-file (st) / path da eliminare |
| `journal.json` | progresso per la WebUI (rigenerato ad ogni transizione) |
| `blobs/<sha256>` | cache del contenuto originale verificato |
| `rollback/<version>/<path>` | backup dei file sovrascritti (undo; tiene gli ultimi 3) |
| `staged/<path>.vdlu-new` | REBOOT-hard in attesa dello swap all'avvio |
| `lock.d/` | lock-mkdir (flock non praticabile su toybox; recupero da stale per PID) |
| `tools/<abi>/curl` | curl statico recuperato (bootstrap snello); persiste tra gli aggiornamenti |
| `cancel` | richiesta di annullamento |

<!-- doc-footer -->

---

> _Questa documentazione è stata generata con Claude (Anthropic) ed è gestita da VD171. Correzioni e miglioramenti sono benvenuti; vedi [CONTRIBUTING.md](CONTRIBUTING.md)._
