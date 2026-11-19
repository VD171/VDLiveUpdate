> **Languages:** [English](../INTERFACES.md) · [العربية](../ar/INTERFACES.md) · Čeština · [Deutsch](../de/INTERFACES.md) · [Español](../es/INTERFACES.md) · [فارسی](../fa/INTERFACES.md) · [Français](../fr/INTERFACES.md) · [हिन्दी](../hi/INTERFACES.md) · [Bahasa Indonesia](../id/INTERFACES.md) · [Italiano](../it/INTERFACES.md) · [日本語](../ja/INTERFACES.md) · [한국어](../ko/INTERFACES.md) · [Nederlands](../nl/INTERFACES.md) · [Polski](../pl/INTERFACES.md) · [Português](../pt/INTERFACES.md) · [Русский](../ru/INTERFACES.md) · [Svenska](../sv/INTERFACES.md) · [ไทย](../th/INTERFACES.md) · [Türkçe](../tr/INTERFACES.md) · [Українська](../uk/INTERFACES.md) · [Tiếng Việt](../vi/INTERFACES.md) · [中文](../zh/INTERFACES.md)

---

# VDLU - Kontrakt rozhrani (sev mezi komponentami)

**Zakon konvergence:** kazda komponenta se ridi timto souborem. Dily od 4 agentu musi **zapadnout dohromady** - podpisy
CLI, nazvy souboru a JSON klice nize jsou **nemenne** (zmena znamena nejprve zarovnat zde).

Principy zdedene z repozitaru: **ciste POSIX sh** na zarizeni (zadne bashismy; bezi s toybox/busybox +
toyboxovym `sha256sum`/`gzip`/`base64` + stazenym `curl` + vestavenym `ed25519-mini` - stihle, zadny bin
bundle), **zadne nadbytecne komentare**, **vzdy release**, **prisnost pri selhani** (obnovitelna transakce, nic
falesne "hotove", nic ztraceneho), **nic nerozvolneno**.

---

## 1. Rozlozeni stavu (Tier-2, mimo adresar modulu)

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
`cancelled:true` v journalu = engine se zastavil pri zruseni (nefinalni, obnovitelny stav; `error`
zustava null).

Engine vlozeny v modulu: `$MODULE_DIR/vdlu/update.sh` (+ `vdlu-verify`). `$MODULE_DIR =
/data/adb/modules/<module>`. Engine dostava pres env: `VDLU_DIR`, `MODULE_DIR`, `MODID`.

## 2. CLI enginu (komponenta ENGINE)

`sh update.sh <cmd>` - rc 0 = ok, !=0 = chyba (duvod je na stderr):

| cmd | dela |
|---|---|
| `check` | DIFF: stahne manifest, porovna; vypise jednoradkovy JSON `{"update":bool,"from":N,"to":M,"fetch":K,"reboot":bool}`; nic nemeni. Zarizeni PRED feedem (downgrade zablokovan, zpevneno) = NESKODNY stav: `{"update":false,"ahead":true,"from":N,"to":M}` + rc0 (nikdy "check failed"). do_diff rc: 2 fetch/parse, 3 verify/meta, 4 ahead |
| `run` | plny cyklus: DIFF->FETCH->APPLY->COMMIT; respektuje `cancel`; zapisuje prubeh do `journal.json`; aplikuje LIVE, stageuje REBOOT-hard |
| `resume` | obnovi transakci `journal.json` od aktualni faze (idempotentni) |
| `boot` | rezim pre-zygote: `resume` + provede SWAP `staged/*.vdlu-new` (aplikuje `.so`), uzavre `PENDING_REBOOT`->`DONE` |
| `status` | vypise `journal.json` (nebo `{"state":"idle"}`) |
| `cancel` | vytvori `$VDLU_DIR/cancel` (probihajici `run` se zastavi v nasledujicim bezpecnem bode) |

Zdroj blobu/manifestu: `source` z configu. `<source>` + `/manifest.json`, `/blobs/<sha>`, `/blobs/<sha>.gz`.
`source` zacina `https://` (staticke stazene curl, TLS) nebo `file://` (lokalni staging).

## 3. manifest.json (vyrabi PRODUCER, konzumuje ENGINE)

```json
{ "schema":1, "module":"<id>", "version":<int>, "version_name":"<str>", "built":"<ISO8601>",
  "engine_min":3, "key_id":"<str>", "channel":"stable",
  "files":[ {"path":"webroot/index.html","sha256":"<hex64>","size":<int>,"mode":"0644","enc":"raw|gz","class":"live|soft|reboot"} ],
  "delete":["<path>"], "sig":"<base64>" }
```

- `files[]` = UPLNY cilovy strom. `class`: `live` (webroot/bin/lib/confs/scripts-on-demand/module.prop) ·
  `soft` (service.sh/post-fs-data.sh/boot-completed.sh) · `reboot` (`zygisk/**/*.so`, `system/**`, `*.rule`).
  Vychozi podle cesty; nikdy nesnizuje `reboot`->`live`.
- `enc`: `gz` (gzip `-9 -n`, deterministicke; toybox gunzip na zarizeni) jen kdyz se dobre komprimuje A
  velikost je vyznamna; `sha256` je VZDY z puvodniho obsahu.
- `sig`: podpis kanonickeho manifestu BEZ pole `sig` (§4 verify).

## 4. journal.json (ENGINE zapisuje, WEBUI cte - kontrakt prubehu)

```json
{ "schema":1, "module":"<id>", "target":<version>, "from":<version>,
  "phase":"diff|fetch|apply|commit", "state":"PLANNED|FETCHING|FETCHED|APPLYING|APPLIED_LIVE|PENDING_REBOOT|DONE|ERROR|DEFERRED",
  "total":<int>, "done":<int>, "current":"<path>", "bytes":<int>, "reboot_pending":bool,
  "cancelled":bool, "error":"<str|null>", "updated":"<ISO8601>",
  "items":[ {"path":"<p>","sha256":"<h>","class":"<c>","st":"pending|fetched|applied|staged|skipped"} ] }
```

Stavovy automat (pevne poradi): `PLANNED->FETCHING->FETCHED->APPLYING->APPLIED_LIVE->(PENDING_REBOOT|DONE)`.
`DONE` az kdyz prehasovani VSEHO souhlasi. Stageovany REBOOT-hard => `PENDING_REBOOT` (ne `DONE`). Vystupy
z faze `fetch`: `ERROR` (tvrde selhani) nebo `DEFERRED` (net_policy zablokovala stahovani - neskodne/obnovitelne,
neni to chyba).

## 5. config (key=value, jedno na radek; editovatelne ve WEBUI)

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

**Boot retry (offline) - TRPELIVY, setrny k baterii:** jen pri `boot` (nikdy pri check/auto-open). Pokud stazeni
manifestu selze kvuli SITI (`fetch_offline` klasifikuje podle navratoveho kodu fetcheru), ceka a opakuje az do
uspechu NEBO dokud se nevycerpa `boot_retry_minutes` AWAKE-casu. Navrh, ktery **nic nedrzi a nevycerpava**:
- **Nulovy wakelock:** mezi pokusy je to `sleep`, ktery v deep-sleepu zmrzne -> zarizeni normalne spi
  (~nulova baterie); retry pozastavi a pokracuje, jakmile je zarizeni uz vzhuru.
- **Nulovy drzeny zamek:** `acquire_lock_try`+release MEZI pokusy (nedrzi zamek behem cekani) ->
  `run`/manualni check nikdy neblokuji; pokud manualni run mezitim stageuje TARGET, boot se odlozi.
- **Nebudi radio zbytecne:** sonda `net_allowed` (pres `net_type`/`ip route get`, kernelovy lookup
  smerovani, ktery respektuje Androidi policy-routing; zadny paket) hlida kazdy pokus - fetch utrati az kdyz se
  sit objevi.
- NIKDY neopakuje deterministicke selhani (manifest/sig/downgrade). `--connect-timeout 15` pri fetchi (nezasekne se
  na captive portalu). `service.sh` ho da na pozadi (boot se nikdy nezasekne).
- ⛔ **TVRDE: zapnuti `boot_retry_minutes>0` vyzaduje TRPELIVY engine** (ten s
  `net_allowed`+`acquire_lock_try`, kanonicky `da7115f4`+). PREDCHOZI boot-retry (drzi zamek cele
  okno + opakuje slepe curl offline) **VYCERPAVA baterii/budi radio** - zapnout retry ve starem
  enginu je footgun. Pri zapnuti vlozte aktualni engine.

**`net_policy` (any|wifi|mobile):** hlida **STAHOVANI** podle typu site. `net_type()` klasifikuje egress
`ip route get` (celularni iface `rmnet/ccmni/v4-*/clat` = mobile; vse ostatni = wifi; kernelovy lookup, zadny
paket). `net_allowed()` porovnava s `net_policy` a hlida `do_fetch` (bloby) + sondu trpeliveho boot-retry.
**Kontrola manifestu zustava volna** (drobna -> UI hlasi update na jakekoli siti); jen stahovani ceka na povolenou
sit. Stahovani na nepovolene siti = stav **`DEFERRED`** v journalu (NE ERROR; jemny modry INFO toast
"waiting for X network"; plan/target zustavaji, obnovi se pri dalsim checku/bootu na spravne siti). `net_policy`
**nahrazuje** `allow_metered` (ktere se nikdy nekonzumovalo). Engine `97baf887`+ (`file://` se nikdy nehlida).

## 6. Podpis (PRODUCER podepisuje na PC pres openssl; ENGINE overuje na zarizeni pres ed25519-mini)

- Kanonizace: manifest BEZ `sig`, klice serazene, kompaktni JSON (zadne zbytecne mezery), UTF-8.
  Co se podepisuje/overuje = `sha256` hex teto kanonicke formy (poskytuje determinismus napric nastroji).
- `producer/vdlu-sign <manifest.json> <privkey.pem> <key_id>` -> vlozi `key_id` + `sig` (base64 podpisu ed25519 kanonickeho sha256) do manifestu, na miste.
- `engine/vdlu-verify <manifest.json> <keyring_dir>` -> rc 0 pokud `sig` odpovida verejnemu klici `<key_id>.pub` v
  keyringu (STIHLE: verejny klic **RAW 32 bajtu**). Interne, zadny openssl: toybox `sha256sum`/`base64 -d` + vestaveny
  binary `ed25519-mini` (CLI `ed25519-mini <pub32> <msg> <sig64>`, rc 0=platne/1=neplatne/2=usage).
  rc!=0 = odmitnuti. **`profile=hardened` => verify povinne; selhani = abort.**
  `profile=trusted` => verify je best-effort (zdroj uz duveryhodny pres SSH), ale hash kazdeho blobu se VZDY kontroluje.
- `producer/vdlu-keygen <id> <out>` -> generuje `<id>.pem` (priv) + `<id>.pub` (PEM, pro nastroje na PC) +
  `<id>.pub.raw` (**RAW 32B** = `<id>.pub` stihleho keyringu na zarizeni). openssl `genpkey -algorithm ed25519`.

## 7. Blob - overeni (ENGINE)

Stahne `<source>/blobs/<sha>` (nebo `.gz` pokud `enc=gz`), zapise `.part`, pokud `gz` dekomprimuje (`gunzip`),
zkontroluje `sha256sum` == `sha256` manifestu; shoda -> atomicke `mv` do `$VDLU_DIR/blobs/<sha>`. 3 selhani na
stejnem blobu = abortuje fazi (nic aplikovano). Blob uz v `$VDLU_DIR/blobs/<sha>` s ok hashem =
preskoci stahovani.

## 8. APPLY podle tridy (ENGINE)

- `live`/`soft`: zaloha `rollback/<v>/<path>` -> zapise `$MODULE_DIR/<path>.vdlu-tmp` z blobu -> `chmod mode` ->
  atomicke `rename` pres cil. Uz na cilovem hashi = skip. (Ve variante Zygisk jde zapis do
  mountovaneho adresare = merge po souborech, nikdy `rm -rf` adresare.)
- `reboot`: materializuje do `$VDLU_DIR/staged/<path>.vdlu-new` (NEDOTYKA se zive). Swap je pri `boot`.
- `delete[]`: zaloha -> odstranit.

## 9. WEBUI <-> ENGINE (komponenta WEBUI)

- Spousti: `ksu.exec("sh $MODULE_DIR/vdlu/update.sh run")` (pozadi).
- Prubeh: lehky poll `ksu.exec("cat $VDLU_DIR/journal.json")` kazdou ~1s; renderuje `{phase,state,total,done,current,bytes}`.
- Zivost: journal chybejici 8 ticku => "no response". Journal ZMRZLY (stejne hodnoty) 20 ticku => kontroluje `lock.d`: zivy = pokracuje (pomale fetchovani 1 blobu), mrtvy = chyba + Resume. Bez toho by run, ktery umrel uprostred fetche, zmrazil toast na "updating".
- Cancel: `ksu.exec("touch $VDLU_DIR/cancel")`.
- Config: cte/zapisuje `$VDLU_DIR/config` (key=value) v zalozce "Updates".
- Toast: lista + `phase done/total · current`; pri dokonceni s `reboot_pending` => trvaly banner "reboot to activate the .so".
- Auto-open (`auto_on_webui_open=1`): nejprve provede TICHY `check()` (zadny progress toast); `run`+trvaly toast spusti jen pokud `update && fetch>0`. Aktualni/napred/nic noveho = inline vysledek v panelu, zadny zbyly toast. Nevtiravy jako manualni tlacitko (toast se objevi jen kdyz je skutecne stahovani). Curl bootstrap je jednorazovy.

## 10. Integrace do demo (komponenta INTEGRATION) - SNIPPETY, needitujte zive soubory

Vyrabi, v `integration/demo/`, snippety + `INTEGRATION.md` rikajici kam kazdy patri (bez aplikace):
- hook `auto_on_reboot` v `post-fs-data`/`service.sh` (pre-zygote -> `update.sh boot`) a `auto_on_webui_open`.
- vychozi hodnoty `config` + vlozeny keyring + vendoring (`modules/<mod>/vdlu/`).
- PARTIAL varianta (merge do mountovaneho adresare).

## 11. Stazeny toolchain + baseline (STIHLE, pristup B)

**Rozlozeni v modulu (zip):** `vdlu/{update.sh, vdlu-verify, config.default, keyring/<id>.pub (RAW 32B),
verify/<abi>/ed25519-mini, baseline.json}`. **ZADNY** `bin/` (openssl/curl/zstd). `customize.sh` muze oriznout
`verify/` na ABI zarizeni (`vdlu-verify` najde mini v `<dir>/ed25519-mini` NEBO `<dir>/verify/<abi>/ed25519-mini`).

**ed25519-mini** (vestaveny binary, jen verify): `ed25519-mini <pubkey32> <msg> <sig64>` -> rc 0=platne,
1=neplatne, 2=usage/IO. msg = presne podepsane bajty (NEHASHUJE znovu). TweetNaCl PD, staticke per-ABI, PROVENANCE.

**tools-feed** (jen public/https profil): servirovano na `<tools_source>` (vychozi odvozeno: vymeni posledni segment
`source` za `vdlu-tools`, napr. `https://<user>.github.io/<repo>/vdlu-tools`). Obsahuje:
- `tools-manifest.json` - PODEPSANY `vdlu-pack` manifest nad stromem `<abi>/curl`, pripinajici `sha256` kazdeho
  curl (stejny klic `release-2026`).
- `<abi>/curl` - HOLE **staticke** curl (sobestacne, ~1MB; curl 8.11.1 + mbedTLS). 🪤 mbedTLS NENESE
  CA bundle: `fetch_url` predava `--capath` (auto-detekce Androidiho trust store: `/system/etc/security/cacerts`
  -> APEX conscrypt; `ca_path` prepisuje). Zadny capath = chyba 60. Integrita je ed25519; cert-check je defense-in-depth.

**install-tool** (ENGINE): `update.sh install-tool <abi>` cte `$VDLU_DIR/.work/{tools-manifest.json, tool.<abi>}`
(WEBUI to stahne pres `fetch()` a zapise tam), **overi podpis tools-manifestu (ed25519-mini,
POVINNE v jakemkoli profilu)** + hash curl == manifest, a teprve pak ho nainstaluje do `$VDLU_DIR/tools/<abi>/curl` (0755).
Curl bezi jako root -> sig+hash pred exec uzavira RCE. Persistuje v Tier-2: nikdy se znovu nestahuje (krome odinstalace).

**fetch-bootstrap** (WEBUI, `ensureToolchain()`): bezi pred check/run/resume. `file://` = no-op; curl UZ
dostupne (Tier-2, NEBO `module/bin/<abi>/curl` ze **self-bundled** modulu, NEBO system) = no-op
(VDLU znovu pouzije existujici curl); jen `https` **vubec bez curl** stahne curl + tools-manifest pres webview, zapise
je do `.work` (chunkovany base64 pres `ksu.exec`), vola `install-tool`. Trust = kontrola na zarizeni, ne stahovani.

> 🪤 **Stihle (fetch-bootstrap) != povinne.** Modul, jehoz `bin/` existuje pro JEHO VLASTNI featury (napr. bundluje
> restic/rclone/age/tar/curl...), se **neztenci** na ~2MB ani nestahuje curl - VDLU prevezme stihly engine
> (gz, mini, baseline, fixy) a **znovu pouzije** vestaveny toolchain. Jen moduly bez vlastniho toolchainu
> ziskavaji ~2MB.

**baseline.json** (fix from:0): release kopiruje PODEPSANY `manifest.json` dodane verze do
`vdlu/baseline.json`; pri cerstve instalaci engine naseeduje `current.json` z nej (`init_paths`, jen pokud chybi) -> zarizeni
se narodi "current", bez auto-updatu sebe sama a bez re-fetche.

<!-- doc-footer -->

---

> _Tato dokumentace byla vytvořena pomocí Claude (Anthropic) a spravuje ji VD171. Opravy a vylepšení jsou vítány; viz [CONTRIBUTING.md](CONTRIBUTING.md)._
