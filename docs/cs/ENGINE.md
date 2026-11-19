> **Languages:** [English](../ENGINE.md) · [العربية](../ar/ENGINE.md) · Čeština · [Deutsch](../de/ENGINE.md) · [Español](../es/ENGINE.md) · [فارسی](../fa/ENGINE.md) · [Français](../fr/ENGINE.md) · [हिन्दी](../hi/ENGINE.md) · [Bahasa Indonesia](../id/ENGINE.md) · [Italiano](../it/ENGINE.md) · [日本語](../ja/ENGINE.md) · [한국어](../ko/ENGINE.md) · [Nederlands](../nl/ENGINE.md) · [Polski](../pl/ENGINE.md) · [Português](../pt/ENGINE.md) · [Русский](../ru/ENGINE.md) · [Svenska](../sv/ENGINE.md) · [ไทย](../th/ENGINE.md) · [Türkçe](../tr/ENGINE.md) · [Українська](../uk/ENGINE.md) · [Tiếng Việt](../vi/ENGINE.md) · [中文](../zh/ENGINE.md)

---

# VDLU engine (`update.sh`)

Flashless, inkrementální update klient pro moduly KSU/Magisk. Implementuje cyklus
`DIFF -> FETCH -> APPLY -> COMMIT` jako obnovitelnou transakci. Řídí se `INTERFACES.md` (zákonem
konvergence).

Čisté POSIX sh (mksh/busybox/toybox). **ŠTÍHLÉ:** závisí jen na toyboxu (`sha256sum`/`gzip`/`base64`/`date`) +
vestavěném `ed25519-mini` (ed25519 verify; **žádný openssl na zařízení**) + statickém `curl`, který se **stáhne** při
prvním https updatu (WebUI provede `fetch()`, persistuje ho v Tier-2 a `install-tool` ověří jeho
podpis+hash PŘED použitím). `file://` curl nepotřebuje. Nulová závislost na `jq`.

## Vyvolání

```sh
VDLU_DIR=/data/adb/<mod>/vdlu MODULE_DIR=/data/adb/modules/<mod> MODID=<mod> \
  sh $MODULE_DIR/vdlu/update.sh <cmd>
```

`rc 0` = ok; `rc != 0` = chyba (důvod na stderr). `vdlu-verify` dodává jiná komponenta
(podpis v `INTERFACES.md §6`); engine ho jen volá.

| cmd | dela |
|---|---|
| `check` | read-only DIFF; vypíše `{"update":bool,"from":N,"to":M,"fetch":K,"reboot":bool}`; nic nemění |
| `run` | plný LIVE cyklus + stageuje REBOOT-hard; respektuje `cancel`; průběh v `journal.json` |
| `resume` | obnoví čekající transakci (`target.json`) od aktuální fáze; idempotentní; **ne**swapuje `.so` |
| `boot` | režim pre-zygote: resume **+** swapuje `staged/*.vdlu-new` -> uzavře `PENDING_REBOOT`->`DONE`. Bez čekající transakce spustí čerstvý cyklus a aplikuje vše (včetně `.so`) v jednom bootu |
| `status` | vypíše `journal.json` (nebo `{"state":"idle"}`) |
| `cancel` | vytvoří `$VDLU_DIR/cancel`; probíhající `run` se zastaví v následujícím bezpečném bodě |

## Stavový automat (journal.json)

```
PLANNED -> FETCHING -> FETCHED -> APPLYING -> APPLIED_LIVE -> (PENDING_REBOOT | DONE)
```

`DONE` až když přehašování VŠEHO souhlasí. Pokud byl stageován jakýkoli REBOOT-hard => `PENDING_REBOOT` (nikdy
falešné `DONE`). `ERROR` při jakémkoli selhání, bez poškození modulu (aplikované LIVE soubory se vrátí
z `rollback/<v>/`; nic "napůl aplikovaného, co o tom lze"). Neškodný výstup fáze `fetch`: **`DEFERRED`** -
stahování bylo odloženo `net_policy` (síť nepovolena); plan/target zůstávají a obnoví se při dalším
checku/bootu (WebUI zobrazí modrý info toast "waiting for X network", ne chybu).

## Záruky přísnosti

- **FETCH:** hlídáno `net_policy` (any/wifi/mobile; jen http/https, `file://` nikdy) - nepovolená síť =>
  `DEFERRED` (obnovitelné), bez utracení dat. Stahuje jen to, co chybí, do `<sha>.part` (curl s
  `--connect-timeout` + `--speed-time`, nikdy se nezasekne), dekomprimuje `gz` (toybox `gunzip`), kontroluje `sha256sum` ==
  manifest, atomické `mv` do `blobs/<sha>`. Cachovaný+ok blob se přeskočí. Může naseedovat blob z nezměněného
  lokálního souboru (dedup/offline). **3 selhání na stejném blobu = fáze abortuje bez aplikace čehokoli.** Stane se
  `FETCHED` až když jsou VŠECHNY bloby plánu přítomné+ověřené.
- **APPLY** (jen z `FETCHED`): `live`/`soft` -> záloha do `rollback/<v>/` -> `.vdlu-tmp` -> `chmod` -> verify ->
  atomické `rename`. `reboot` -> materializuje do `staged/<path>.vdlu-new` (NEDOTÝKÁ se živého inode).
  `delete[]` -> záloha -> odstranit. Idempotentní (soubor už na cílovém hashi se přeskočí).
- **COMMIT:** přehašování každého `live`/`soft`; teprve pak zapíše `current.json`. Se stageovanými soubory =>
  `PENDING_REBOOT`. `boot` provede `mv -f staged/....vdlu-new $MODULE_DIR/<path>` (pre-zygote) + znovu ověří +
  `DONE`.
- **cancel:** kontrolováno mezi soubory (bezpečný bod); odstraní rozpracované `.vdlu-tmp`/`.part`, smaže `cancel`,
  ponechá journal obnovitelný (`cancelled:true`, `error:null`).
- **mkdir-lock `$VDLU_DIR/lock.d`** serializuje (flock je na toyboxu nepoužitelný; stale-recovery podle PID).
  TRPĚLIVÝ boot-retry nedrží zámek během čekání (`acquire_lock_try`+release mezi pokusy) ani
  wakelock - šetrný k baterii. Pád/síť/reboot uprostřed -> `resume`/`boot` pokračuje.
- **profile=hardened** => `vdlu-verify` povinné na manifestu PŘED použitím; selhání = abort; downgrade zablokován
  (monotónní verze). **trusted** => verify je best-effort, ale hash každého blobu se VŽDY kontroluje.
- Degraduje elegantně: chybějící binary / síť dole / plný disk -> jasná chyba na stderr + `state:ERROR` v
  journalu, bez poškození modulu.

## Parsování JSON bez jq

Flattener ve stylu gron v `awk` (čisté POSIX: `substr`/`index`/`gsub`/`split`/`printf` + lokály předané jako
parametry) tokenizuje manifest znak po znaku a emituje jeden řádek `path<TAB>value` na skalární list
(`files/0/sha256<TAB>ab..`, `version<TAB>6`, `delete/0<TAB>etc/x`). Robustní vůči kompaktnímu NEBO pretty-printed
JSON. `sh` ho konzumuje přes `grep`/`cut`; plán po souborech se znovu sestaví v 2. `awk` do TSV
(`class st mode enc sha size path`), které se stane `$VDLU_DIR/plan.tsv`.

## Stavové soubory (v `$VDLU_DIR`, Tier-2)

| soubor | role |
|---|---|
| `config` | key=value (`source`/`profile`/`channel`/`net_policy`/`boot_retry_*`/…; viz INTERFACES §5) |
| `current.json` | manifest AKTIVNÍ verze (diff base); chybí = nikdy neaktualizováno |
| `target.json` | připnutý manifest rozpracované transakce (přítomnost = aktivní transakce); stane se `current.json` při `DONE` |
| `plan.tsv` / `plan.del` | plán + průběh po souborech (st) / cesty ke smazání |
| `journal.json` | průběh pro WebUI (regenerováno při každém přechodu) |
| `blobs/<sha256>` | cache ověřeného původního obsahu |
| `rollback/<version>/<path>` | záloha přepsaných souborů (undo; drží posledních 3) |
| `staged/<path>.vdlu-new` | REBOOT-hard čekající na swap při bootu |
| `lock.d/` | mkdir-lock (flock na toyboxu nepoužitelný; stale-recovery podle PID) |
| `tools/<abi>/curl` | stažené statické curl (štíhlý bootstrap); persistuje napříč updaty |
| `cancel` | požadavek na zrušení |

<!-- doc-footer -->

---

> _Tato dokumentace byla vytvořena pomocí Claude (Anthropic) a spravuje ji VD171. Opravy a vylepšení jsou vítány; viz [CONTRIBUTING.md](CONTRIBUTING.md)._
