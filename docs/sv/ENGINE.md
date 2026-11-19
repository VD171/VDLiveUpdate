> **Languages:** [English](../ENGINE.md) · [العربية](../ar/ENGINE.md) · [Čeština](../cs/ENGINE.md) · [Deutsch](../de/ENGINE.md) · [Español](../es/ENGINE.md) · [فارسی](../fa/ENGINE.md) · [Français](../fr/ENGINE.md) · [हिन्दी](../hi/ENGINE.md) · [Bahasa Indonesia](../id/ENGINE.md) · [Italiano](../it/ENGINE.md) · [日本語](../ja/ENGINE.md) · [한국어](../ko/ENGINE.md) · [Nederlands](../nl/ENGINE.md) · [Polski](../pl/ENGINE.md) · [Português](../pt/ENGINE.md) · [Русский](../ru/ENGINE.md) · Svenska · [ไทย](../th/ENGINE.md) · [Türkçe](../tr/ENGINE.md) · [Українська](../uk/ENGINE.md) · [Tiếng Việt](../vi/ENGINE.md) · [中文](../zh/ENGINE.md)

---

# VDLU-motorn (`update.sh`)

Flashless, inkrementell uppdateringsklient för KSU/Magisk-moduler. Implementerar
cykeln `DIFF -> FETCH -> APPLY -> COMMIT` som en återupptagbar transaktion. Rättar sig efter `INTERFACES.md` (konvergens-
lagen).

Ren POSIX sh (mksh/busybox/toybox). **SLIM:** den beror endast på toybox (`sha256sum`/`gzip`/`base64`/`date`) +
den inbäddade `ed25519-mini` (ed25519 verify; **ingen openssl på enheten**) + en statisk `curl` som **hämtas** vid
den första https-uppdateringen (WebUI gör `fetch()`, bevarar den i Tier-2, och `install-tool` verifierar dess
signatur+hash INNAN den används). `file://` behöver ingen curl. Noll beroende av `jq`.

## Anrop

```sh
VDLU_DIR=/data/adb/<mod>/vdlu MODULE_DIR=/data/adb/modules/<mod> MODID=<mod> \
  sh $MODULE_DIR/vdlu/update.sh <cmd>
```

`rc 0` = ok; `rc != 0` = fel (orsak på stderr). `vdlu-verify` levereras av en annan komponent
(signatur i `INTERFACES.md §6`); motorn anropar den bara.

| cmd | gör |
|---|---|
| `check` | skrivskyddad DIFF; skriver ut `{"update":bool,"from":N,"to":M,"fetch":K,"reboot":bool}`; ändrar ingenting |
| `run` | full LIVE-cykel + scenlägger REBOOT-hard; respekterar `cancel`; förlopp i `journal.json` |
| `resume` | återupptar den väntande transaktionen (`target.json`) från den aktuella fasen; idempotent; byter **inte** `.so` |
| `boot` | pre-zygote-läge: resume **+** byter `staged/*.vdlu-new` → stänger `PENDING_REBOOT`→`DONE`. Utan någon väntande transaktion kör den en ny cykel och tillämpar allt (inklusive `.so`) i en enda boot |
| `status` | skriver ut `journal.json` (eller `{"state":"idle"}`) |
| `cancel` | skapar `$VDLU_DIR/cancel`; ett pågående `run` stoppar vid nästa säkra punkt |

## Tillståndsmaskin (journal.json)

```
PLANNED -> FETCHING -> FETCHED -> APPLYING -> APPLIED_LIVE -> (PENDING_REBOOT | DONE)
```

`DONE` endast när en om-hashning av ALLT stämmer. Om någon REBOOT-hard scenlades ⇒ `PENDING_REBOOT` (aldrig ett
falskt `DONE`). `ERROR` vid varje fel, utan att korrumpera modulen (de tillämpade LIVE-filerna återställs
från `rollback/<v>/`; inget "halvtillämpat som ljuger om det"). Godartad utgång från `fetch`-fasen: **`DEFERRED`** -
nedladdningen sköts upp av `net_policy` (nätverk inte tillåtet); plan/target består och den återupptas vid nästa
check/boot (WebUI visar en blå infotoast "väntar på X-nätverk", inte ett fel).

## Rigor-garantier

- **FETCH:** grindas av `net_policy` (any/wifi/mobile; endast http/https, `file://` aldrig) - ett ej tillåtet nätverk ⇒
  `DEFERRED` (återupptagbart), utan att spendera data. Laddar bara ner det som saknas till `<sha>.part` (curl med
  `--connect-timeout` + `--speed-time`, hänger aldrig), dekomprimerar `gz` (toybox `gunzip`), kontrollerar `sha256sum` ==
  manifest, atomisk `mv` till `blobs/<sha>`. En cachad+ok blob hoppas över. Den kan seeda bloben från en oförändrad
  lokal fil (dedup/offline). **3 misslyckanden på samma blob = fasen avbryter utan att tillämpa något.** Den
  blir `FETCHED` först när ALLA planens blobbar finns+verifierade.
- **APPLY** (endast från `FETCHED`): `live`/`soft` → backup till `rollback/<v>/` → `.vdlu-tmp` → `chmod` → verifiera →
  atomisk `rename`. `reboot` → materialiseras i `staged/<path>.vdlu-new` (rör INTE den levande inoden).
  `delete[]` → backup → ta bort. Idempotent (en fil som redan är på målets hash hoppas över).
- **COMMIT:** om-hashning av varje `live`/`soft`; först då skriver den `current.json`. Med scenlagda filer ⇒
  `PENDING_REBOOT`. `boot` gör `mv -f staged/....vdlu-new $MODULE_DIR/<path>` (pre-zygote) + om-verifierar +
  `DONE`.
- **cancel:** kontrolleras mellan filer (säker punkt); tar bort den pågående `.vdlu-tmp`/`.part`, raderar `cancel`,
  lämnar journalen återupptagbar (`cancelled:true`, `error:null`).
- **mkdir-lås `$VDLU_DIR/lock.d`** serialiserar (flock är ogörligt på toybox; stale-recovery efter PID). Den
  TÅLMODIGA boot-retryn håller varken låset medan den väntar (`acquire_lock_try`+release mellan försök) eller ett
  wakelock - batterisäker. En krasch/nätverk/omstart mitt i → `resume`/`boot` fortsätter.
- **profile=hardened** ⇒ `vdlu-verify` obligatoriskt på manifestet INNAN användning; fel = avbryt; nedgradering blockerad
  (monoton version). **trusted** ⇒ verify är best-effort, men varje blobs hash kontrolleras ALLTID.
- Degraderar graciöst: saknad binär / nätverk nere / disk full → ett tydligt fel på stderr + `state:ERROR` i
  journalen, utan att korrumpera modulen.

## JSON-parsning utan jq

En gron-stil-utplattare i `awk` (ren POSIX: `substr`/`index`/`gsub`/`split`/`printf` + lokala variabler som skickas som
parametrar) tokeniserar manifestet tecken för tecken och avger en `path<TAB>value`-rad per skalärt löv
(`files/0/sha256<TAB>ab..`, `version<TAB>6`, `delete/0<TAB>etc/x`). Robust mot kompakt ELLER prydligt utskriven
JSON. `sh` konsumerar den med `grep`/`cut`; planen per fil återmonteras i en 2:a `awk` till TSV
(`class st mode enc sha size path`), som blir `$VDLU_DIR/plan.tsv`.

## Tillståndsfiler (i `$VDLU_DIR`, Tier-2)

| fil | roll |
|---|---|
| `config` | key=value (`source`/`profile`/`channel`/`net_policy`/`boot_retry_*`/…; se INTERFACES §5) |
| `current.json` | manifest för den AKTIVA versionen (diff-bas); frånvarande = aldrig uppdaterad |
| `target.json` | fäst manifest för den pågående transaktionen (närvaro = aktiv transaktion); blir `current.json` vid `DONE` |
| `plan.tsv` / `plan.del` | plan + förlopp per fil (st) / sökvägar att ta bort |
| `journal.json` | förlopp för WebUI (regenereras vid varje övergång) |
| `blobs/<sha256>` | cache av verifierat originalinnehåll |
| `rollback/<version>/<path>` | backup av överskrivna filer (ångra; behåller de senaste 3) |
| `staged/<path>.vdlu-new` | REBOOT-hard som väntar på byte vid boot |
| `lock.d/` | mkdir-lås (flock ogörligt på toybox; stale-recovery efter PID) |
| `tools/<abi>/curl` | hämtad statisk curl (slim bootstrap); består över uppdateringar |
| `cancel` | avbrytningsbegäran |

<!-- doc-footer -->

---

> _Denna dokumentation genererades med Claude (Anthropic) och underhålls av VD171. Rättelser och förbättringar välkomnas; se [CONTRIBUTING.md](CONTRIBUTING.md)._
