> **Languages:** [English](../ENGINE.md) · [العربية](../ar/ENGINE.md) · Čeština · [Deutsch](../de/ENGINE.md) · [Español](../es/ENGINE.md) · [فارسی](../fa/ENGINE.md) · [Français](../fr/ENGINE.md) · [हिन्दी](../hi/ENGINE.md) · [Bahasa Indonesia](../id/ENGINE.md) · [Italiano](../it/ENGINE.md) · [日本語](../ja/ENGINE.md) · [한국어](../ko/ENGINE.md) · [Nederlands](../nl/ENGINE.md) · [Polski](../pl/ENGINE.md) · [Português](../pt/ENGINE.md) · [Русский](../ru/ENGINE.md) · [Svenska](../sv/ENGINE.md) · [ไทย](../th/ENGINE.md) · [Türkçe](../tr/ENGINE.md) · [Українська](../uk/ENGINE.md) · [Tiếng Việt](../vi/ENGINE.md) · [中文](../zh/ENGINE.md)

---

# VDLU engine (`update.sh`)

Flashless, inkrementalni update klient pro moduly KSU/Magisk. Implementuje cyklus
`DIFF -> FETCH -> APPLY -> COMMIT` jako obnovitelnou transakci. Ridi se `INTERFACES.md` (zakonem
konvergence).

Ciste POSIX sh (mksh/busybox/toybox). **STIHLE:** zavisi jen na toyboxu (`sha256sum`/`gzip`/`base64`/`date`) +
vestavenem `ed25519-mini` (ed25519 verify; **zadny openssl na zarizeni**) + statickem `curl`, ktery se **stahne** pri
prvnim https updatu (WebUI provede `fetch()`, persistuje ho v Tier-2 a `install-tool` overi jeho
podpis+hash PRED pouzitim). `file://` curl nepotrebuje. Nulova zavislost na `jq`.

## Vyvolani

```sh
VDLU_DIR=/data/adb/<mod>/vdlu MODULE_DIR=/data/adb/modules/<mod> MODID=<mod> \
  sh $MODULE_DIR/vdlu/update.sh <cmd>
```

`rc 0` = ok; `rc != 0` = chyba (duvod na stderr). `vdlu-verify` dodava jina komponenta
(podpis v `INTERFACES.md §6`); engine ho jen vola.

| cmd | dela |
|---|---|
| `check` | read-only DIFF; vypise `{"update":bool,"from":N,"to":M,"fetch":K,"reboot":bool}`; nic nemeni |
| `run` | plny LIVE cyklus + stageuje REBOOT-hard; respektuje `cancel`; prubeh v `journal.json` |
| `resume` | obnovi cekajici transakci (`target.json`) od aktualni faze; idempotentni; **ne**swapuje `.so` |
| `boot` | rezim pre-zygote: resume **+** swapuje `staged/*.vdlu-new` -> uzavre `PENDING_REBOOT`->`DONE`. Bez cekajici transakce spusti cerstvy cyklus a aplikuje vse (vcetne `.so`) v jednom bootu |
| `status` | vypise `journal.json` (nebo `{"state":"idle"}`) |
| `cancel` | vytvori `$VDLU_DIR/cancel`; probihajici `run` se zastavi v nasledujicim bezpecnem bode |

## Stavovy automat (journal.json)

```
PLANNED -> FETCHING -> FETCHED -> APPLYING -> APPLIED_LIVE -> (PENDING_REBOOT | DONE)
```

`DONE` az kdyz prehasovani VSEHO souhlasi. Pokud byl stageovan jakykoli REBOOT-hard => `PENDING_REBOOT` (nikdy
falesne `DONE`). `ERROR` pri jakemkoli selhani, bez poskozeni modulu (aplikovane LIVE soubory se vrati
z `rollback/<v>/`; nic "napul aplikovaneho, co o tom lze"). Neskodny vystup faze `fetch`: **`DEFERRED`** -
stahovani bylo odlozeno `net_policy` (sit nepovolena); plan/target zustavaji a obnovi se pri dalsim
checku/bootu (WebUI zobrazi modry info toast "waiting for X network", ne chybu).

## Zaruky prisnosti

- **FETCH:** hlidano `net_policy` (any/wifi/mobile; jen http/https, `file://` nikdy) - nepovolena sit =>
  `DEFERRED` (obnovitelne), bez utraceni dat. Stahuje jen to, co chybi, do `<sha>.part` (curl s
  `--connect-timeout` + `--speed-time`, nikdy se nezasekne), dekomprimuje `gz` (toybox `gunzip`), kontroluje `sha256sum` ==
  manifest, atomicke `mv` do `blobs/<sha>`. Cachovany+ok blob se preskoci. Muze naseedovat blob z nezmeneneho
  lokalniho souboru (dedup/offline). **3 selhani na stejnem blobu = faze abortuje bez aplikace cehokoli.** Stane se
  `FETCHED` az kdyz jsou VSECHNY bloby planu pritomne+overene.
- **APPLY** (jen z `FETCHED`): `live`/`soft` -> zaloha do `rollback/<v>/` -> `.vdlu-tmp` -> `chmod` -> verify ->
  atomicke `rename`. `reboot` -> materializuje do `staged/<path>.vdlu-new` (NEDOTYKA se ziveho inode).
  `delete[]` -> zaloha -> odstranit. Idempotentni (soubor uz na cilovem hashi se preskoci).
- **COMMIT:** prehasovani kazdeho `live`/`soft`; teprve pak zapise `current.json`. Se stageovanymi soubory =>
  `PENDING_REBOOT`. `boot` provede `mv -f staged/....vdlu-new $MODULE_DIR/<path>` (pre-zygote) + znovu overi +
  `DONE`.
- **cancel:** kontrolovano mezi soubory (bezpecny bod); odstrani rozpracovane `.vdlu-tmp`/`.part`, smaze `cancel`,
  ponecha journal obnovitelny (`cancelled:true`, `error:null`).
- **mkdir-lock `$VDLU_DIR/lock.d`** serializuje (flock je na toyboxu nepouzitelny; stale-recovery podle PID).
  TRPELIVY boot-retry nedrzi zamek behem cekani (`acquire_lock_try`+release mezi pokusy) ani
  wakelock - setrny k baterii. Pad/sit/reboot uprostred -> `resume`/`boot` pokracuje.
- **profile=hardened** => `vdlu-verify` povinne na manifestu PRED pouzitim; selhani = abort; downgrade zablokovan
  (monotonni verze). **trusted** => verify je best-effort, ale hash kazdeho blobu se VZDY kontroluje.
- Degraduje elegantne: chybejici binary / sit dole / plny disk -> jasna chyba na stderr + `state:ERROR` v
  journalu, bez poskozeni modulu.

## Parsovani JSON bez jq

Flattener ve stylu gron v `awk` (ciste POSIX: `substr`/`index`/`gsub`/`split`/`printf` + lokaly predane jako
parametry) tokenizuje manifest znak po znaku a emituje jeden radek `path<TAB>value` na skalarni list
(`files/0/sha256<TAB>ab..`, `version<TAB>6`, `delete/0<TAB>etc/x`). Robustni vuci kompaktnimu NEBO pretty-printed
JSON. `sh` ho konzumuje pres `grep`/`cut`; plan po souborech se znovu sestavi v 2. `awk` do TSV
(`class st mode enc sha size path`), ktere se stane `$VDLU_DIR/plan.tsv`.

## Stavove soubory (v `$VDLU_DIR`, Tier-2)

| soubor | role |
|---|---|
| `config` | key=value (`source`/`profile`/`channel`/`net_policy`/`boot_retry_*`/…; viz INTERFACES §5) |
| `current.json` | manifest AKTIVNI verze (diff base); chybi = nikdy neaktualizovano |
| `target.json` | pripnuty manifest rozpracovane transakce (pritomnost = aktivni transakce); stane se `current.json` pri `DONE` |
| `plan.tsv` / `plan.del` | plan + prubeh po souborech (st) / cesty k smazani |
| `journal.json` | prubeh pro WebUI (regenerovano pri kazdem prechodu) |
| `blobs/<sha256>` | cache overeneho puvodniho obsahu |
| `rollback/<version>/<path>` | zaloha prepsanych souboru (undo; drzi poslednich 3) |
| `staged/<path>.vdlu-new` | REBOOT-hard cekajici na swap pri bootu |
| `lock.d/` | mkdir-lock (flock na toyboxu nepouzitelny; stale-recovery podle PID) |
| `tools/<abi>/curl` | stazene staticke curl (stihly bootstrap); persistuje napric updaty |
| `cancel` | pozadavek na zruseni |

<!-- doc-footer -->

---

> _Tato dokumentace byla vytvořena pomocí Claude (Anthropic) a spravuje ji VD171. Opravy a vylepšení jsou vítány; viz [CONTRIBUTING.md](CONTRIBUTING.md)._
