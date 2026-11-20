> **Languages:** [English](../INTERFACES.md) · [العربية](../ar/INTERFACES.md) · Čeština · [Deutsch](../de/INTERFACES.md) · [Español](../es/INTERFACES.md) · [فارسی](../fa/INTERFACES.md) · [Français](../fr/INTERFACES.md) · [हिन्दी](../hi/INTERFACES.md) · [Bahasa Indonesia](../id/INTERFACES.md) · [Italiano](../it/INTERFACES.md) · [日本語](../ja/INTERFACES.md) · [한국어](../ko/INTERFACES.md) · [Nederlands](../nl/INTERFACES.md) · [Polski](../pl/INTERFACES.md) · [Português](../pt/INTERFACES.md) · [Русский](../ru/INTERFACES.md) · [Svenska](../sv/INTERFACES.md) · [ไทย](../th/INTERFACES.md) · [Türkçe](../tr/INTERFACES.md) · [Українська](../uk/INTERFACES.md) · [Tiếng Việt](../vi/INTERFACES.md) · [中文](../zh/INTERFACES.md)

---

# VDLU - Kontrakt rozhraní (šev mezi komponentami)

**Zákon konvergence:** každá komponenta se řídí tímto souborem. Díly od 4 agentů musí **zapadnout dohromady** - podpisy
CLI, názvy souborů a JSON klíče níže jsou **neměnné** (změna znamená nejprve zarovnat zde).

Principy zděděné z repozitáře: **čisté POSIX sh** na zařízení (žádné bashismy; běží s toybox/busybox +
toyboxovým `sha256sum`/`gzip`/`base64` + staženým `curl` + vestavěným `ed25519-mini` - štíhle, žádný bin
bundle), **žádné nadbytečné komentáře**, **vždy release**, **přísnost při selhání** (obnovitelná transakce, nic
falešně "hotové", nic ztraceného), **nic nerozvolněno**.

---

## 1. Rozložení stavu (Tier-2, mimo adresář modulu)

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
`cancelled:true` v journalu = engine se zastavil při zrušení (nefinální, obnovitelný stav; `error`
zůstává null).

Engine vložený v modulu: `$MODULE_DIR/vdlu/update.sh` (+ `vdlu-verify`). `$MODULE_DIR =
/data/adb/modules/<module>`. Engine dostává přes env: `VDLU_DIR`, `MODULE_DIR`, `MODID`.

## 2. CLI enginu (komponenta ENGINE)

`sh update.sh <cmd>` - rc 0 = ok, !=0 = chyba (důvod je na stderr):

| cmd | dělá |
|---|---|
| `check` | DIFF: stáhne manifest, porovná; vypíše jednořádkový JSON `{"update":bool,"from":N,"to":M,"fetch":K,"reboot":bool}`; nic nemění. Zařízení PŘED feedem (downgrade zablokován, zpevněno) = NEŠKODNÝ stav: `{"update":false,"ahead":true,"from":N,"to":M}` + rc0 (nikdy "check failed"). do_diff rc: 2 fetch/parse, 3 verify/meta, 4 ahead |
| `run` | plný cyklus: DIFF->FETCH->APPLY->COMMIT; respektuje `cancel`; zapisuje průběh do `journal.json`; aplikuje LIVE, stageuje REBOOT-hard |
| `resume` | obnoví transakci `journal.json` od aktuální fáze (idempotentní) |
| `boot` | režim pre-zygote: `resume` + provede SWAP `staged/*.vdlu-new` (aplikuje `.so`), uzavře `PENDING_REBOOT`->`DONE` |
| `status` | vypíše `journal.json` (nebo `{"state":"idle"}`) |
| `cancel` | vytvoří `$VDLU_DIR/cancel` (probíhající `run` se zastaví v následujícím bezpečném bodě) |

Zdroj blobů/manifestu: `source` z configu. `<source>` + `/manifest.json`, `/blobs/<sha>`, `/blobs/<sha>.gz`.
`source` začíná `https://` (statické stažené curl, TLS) nebo `file://` (lokální staging).

## 3. manifest.json (vyrábí PRODUCER, konzumuje ENGINE)

```json
{ "schema":1, "module":"<id>", "version":<int>, "version_name":"<str>", "built":"<ISO8601>",
  "engine_min":3, "key_id":"<str>", "channel":"stable",
  "files":[ {"path":"webroot/index.html","sha256":"<hex64>","size":<int>,"mode":"0644","enc":"raw|gz","class":"live|soft|reboot"} ],
  "delete":["<path>"], "sig":"<base64>" }
```

- `files[]` = ÚPLNÝ cílový strom. `class`: `live` (webroot/bin/lib/confs/scripts-on-demand/module.prop) ·
  `soft` (service.sh/post-fs-data.sh/boot-completed.sh) · `reboot` (`zygisk/**/*.so`, `system/**`, `*.rule`).
  Výchozí podle cesty; nikdy nesnižuje `reboot`->`live`.
- `enc`: `gz` (gzip `-9 -n`, deterministické; toybox gunzip na zařízení) jen když se dobře komprimuje A
  velikost je významná; `sha256` je VŽDY z původního obsahu.
- `sig`: podpis kanonického manifestu BEZ pole `sig` (§4 verify).

## 4. journal.json (ENGINE zapisuje, WEBUI čte - kontrakt průběhu)

```json
{ "schema":1, "module":"<id>", "target":<version>, "from":<version>,
  "phase":"diff|fetch|apply|commit", "state":"PLANNED|FETCHING|FETCHED|APPLYING|APPLIED_LIVE|PENDING_REBOOT|DONE|ERROR|DEFERRED",
  "total":<int>, "done":<int>, "current":"<path>", "bytes":<int>, "reboot_pending":bool,
  "cancelled":bool, "error":"<str|null>", "updated":"<ISO8601>",
  "items":[ {"path":"<p>","sha256":"<h>","class":"<c>","st":"pending|fetched|applied|staged|skipped"} ] }
```

Stavový automat (pevné pořadí): `PLANNED->FETCHING->FETCHED->APPLYING->APPLIED_LIVE->(PENDING_REBOOT|DONE)`.
`DONE` až když přehašování VŠEHO souhlasí. Stageovaný REBOOT-hard => `PENDING_REBOOT` (ne `DONE`). Výstupy
z fáze `fetch`: `ERROR` (tvrdé selhání) nebo `DEFERRED` (net_policy zablokovala stahování - neškodné/obnovitelné,
není to chyba).

## 5. config (key=value, jedno na řádek; editovatelné ve WEBUI)

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
tools_source=          # empty = derived from source (.../vdlu-tools); feed of the static curl
boot_retry_interval=30 # seconds between probes when BOOT finds the device offline (floor 5s)
boot_retry_minutes=0   # ceiling of the PATIENT retry (AWAKE-time) only at boot; 0 = off. Battery-safe (no wakelock,
                       # no held lock, route probe never wakes the radio) -> a generous ceiling is ~free
```

**Boot retry (offline) - TRPĚLIVÝ, šetrný k baterii:** jen při `boot` (nikdy při check/auto-open). Pokud stažení
manifestu selže kvůli SÍTI (`fetch_offline` klasifikuje podle návratového kódu fetcheru), čeká a opakuje až do
úspěchu NEBO dokud se nevyčerpá `boot_retry_minutes` AWAKE-času. Návrh, který **nic nedrží a nevyčerpává**:
- **Nulový wakelock:** mezi pokusy je to `sleep`, který v deep-sleepu zmrzne -> zařízení normálně spí
  (~nulová baterie); retry pozastaví a pokračuje, jakmile je zařízení už vzhůru.
- **Nulový držený zámek:** `acquire_lock_try`+release MEZI pokusy (nedrží zámek během čekání) ->
  `run`/manuální check nikdy neblokují; pokud manuální run mezitím stageuje TARGET, boot se odloží.
- **Nebudí radio zbytečně:** sonda `net_allowed` (přes `net_type`/`ip route get`, kernelový lookup
  směrování, který respektuje Androidí policy-routing; žádný paket) hlídá každý pokus - fetch utratí až když se
  síť objeví.
- NIKDY neopakuje deterministické selhání (manifest/sig/downgrade). `--connect-timeout 15` při fetchi (nezasekne se
  na captive portalu). `service.sh` ho dá na pozadí (boot se nikdy nezasekne).
- ⛔ **TVRDĚ: zapnutí `boot_retry_minutes>0` vyžaduje TRPĚLIVÝ engine** (ten s
  `net_allowed`+`acquire_lock_try`, kanonický `da7115f4`+). PŘEDCHOZÍ boot-retry (drží zámek celé
  okno + opakuje slepě curl offline) **VYČERPÁVÁ baterii/budí radio** - zapnout retry ve starém
  enginu je footgun. Při zapnutí vložte aktuální engine.

**`net_policy` (any|wifi|mobile):** hlídá **STAHOVÁNÍ** podle typu sítě. `net_type()` klasifikuje egress
`ip route get` (celulární iface `rmnet/ccmni/v4-*/clat` = mobile; vše ostatní = wifi; kernelový lookup, žádný
paket). `net_allowed()` porovnává s `net_policy` a hlídá `do_fetch` (bloby) + sondu trpělivého boot-retry.
**Kontrola manifestu zůstává volná** (drobná -> UI hlásí update na jakékoli síti); jen stahování čeká na povolenou
síť. Stahování na nepovolené síti = stav **`DEFERRED`** v journalu (NE ERROR; jemný modrý INFO toast
"waiting for X network"; plan/target zůstávají, obnoví se při dalším checku/bootu na správné síti). `net_policy`
**nahrazuje** `allow_metered` (které se nikdy nekonzumovalo). Engine `97baf887`+ (`file://` se nikdy nehlídá).

## 6. Podpis (PRODUCER podepisuje na PC přes openssl; ENGINE ověřuje na zařízení přes ed25519-mini)

- Kanonizace: manifest BEZ `sig`, klíče seřazené, kompaktní JSON (žádné zbytečné mezery), UTF-8.
  Co se podepisuje/ověřuje = `sha256` hex této kanonické formy (poskytuje determinismus napříč nástroji).
- `producer/vdlu-sign <manifest.json> <privkey.pem> <key_id>` -> vloží `key_id` + `sig` (base64 podpisu ed25519 kanonického sha256) do manifestu, na místě.
- `engine/vdlu-verify <manifest.json> <keyring_dir>` -> rc 0 pokud `sig` odpovídá veřejnému klíči `<key_id>.pub` v
  keyringu (ŠTÍHLE: veřejný klíč **RAW 32 bajtů**). Interně, žádný openssl: toybox `sha256sum`/`base64 -d` + vestavěný
  binary `ed25519-mini` (CLI `ed25519-mini <pub32> <msg> <sig64>`, rc 0=platné/1=neplatné/2=usage).
  rc!=0 = odmítnutí. **`profile=hardened` => verify povinné; selhání = abort.**
  `profile=trusted` => verify je best-effort (zdroj už důvěryhodný přes SSH), ale hash každého blobu se VŽDY kontroluje.
- **Allowlist klíče pro module-update (fail-closed, před výběrem pubkey):** `key_id` manifestu musí být přijatý MODULE-UPDATE klíč, než se vybere `<key_id>.pub` - `key_id` z configu (§5) je ta allowlist. Keyring může NÉST i klíč nižší důvěry (např. klíč fingerprint-feedu, automatizovaný, jiný účet); bez allowlistu by se manifest podepsaný tím klíčem ověřil a při úniku by aplikoval celou flashless root aktualizaci. `verify_manifest` to vynucuje v OBOU profiles a předává vyřešenou množinu `vdlu-verify` přes env `VDLU_KEYID_ALLOW` (aby samostatný verifikátor souhlasil). Nenastaveno je bezpečné ve výchozím stavu (keyring s jedním klíčem: jen ten klíč; víceklíčový keyring: odmítnuto, dokud není `key_id` připnuto). Kořen důvěry fingerprint-feedu je ODDĚLENÁ cesta s vlastním připnutým klíčem a není dotčen.
- `producer/vdlu-keygen <id> <out>` -> generuje `<id>.pem` (priv) + `<id>.pub` (PEM, pro nástroje na PC) +
  `<id>.pub.raw` (**RAW 32B** = `<id>.pub` štíhlého keyringu na zařízení). openssl `genpkey -algorithm ed25519`.

## 7. Blob - ověření (ENGINE)

Stáhne `<source>/blobs/<sha>` (nebo `.gz` pokud `enc=gz`), zapíše `.part`, pokud `gz` dekomprimuje (`gunzip`),
zkontroluje `sha256sum` == `sha256` manifestu; shoda -> atomické `mv` do `$VDLU_DIR/blobs/<sha>`. 3 selhání na
stejném blobu = abortuje fázi (nic aplikováno). Blob už v `$VDLU_DIR/blobs/<sha>` s ok hashem =
přeskočí stahování.

## 8. APPLY podle třídy (ENGINE)

- `live`/`soft`: záloha `rollback/<v>/<path>` -> zapíše `$MODULE_DIR/<path>.vdlu-tmp` z blobu -> `chmod mode` ->
  atomické `rename` přes cíl. Už na cílovém hashi = skip. (Ve variantě Zygisk jde zápis do
  mountovaného adresáře = merge po souborech, nikdy `rm -rf` adresáře.)
- `reboot`: materializuje do `$VDLU_DIR/staged/<path>.vdlu-new` (NEDOTÝKÁ se živé). Swap je při `boot`.
- `delete[]`: záloha -> odstranit.

## 9. WEBUI <-> ENGINE (komponenta WEBUI)

- Spouští: `ksu.exec("sh $MODULE_DIR/vdlu/update.sh run")` (pozadí).
- Průběh: lehký poll `ksu.exec("cat $VDLU_DIR/journal.json")` každou ~1s; renderuje `{phase,state,total,done,current,bytes}`.
- Živost: journal chybějící 8 ticků => "no response". Journal ZMRZLÝ (stejné hodnoty) 20 ticků => kontroluje `lock.d`: živý = pokračuje (pomalé fetchování 1 blobu), mrtvý = chyba + Resume. Bez toho by run, který umřel uprostřed fetche, zmrazil toast na "updating".
- Cancel: `ksu.exec("touch $VDLU_DIR/cancel")`.
- Config: čte/zapisuje `$VDLU_DIR/config` (key=value) v záložce "Updates".
- Toast: lišta + `phase done/total · current`; při dokončení s `reboot_pending` => trvalý banner "reboot to activate the .so".
- Auto-open (`auto_on_webui_open=1`): nejprve provede TICHÝ `check()` (žádný progress toast); `run`+trvalý toast spustí jen pokud `update && fetch>0`. Aktuální/napřed/nic nového = inline výsledek v panelu, žádný zbylý toast. Nevtíravý jako manuální tlačítko (toast se objeví jen když je skutečné stahování). Curl bootstrap je jednorázový.

## 10. Integrace do demo (komponenta INTEGRATION) - SNIPPETY, needitujte živé soubory

Vyrábí, v `integration/demo/`, snippety + `INTEGRATION.md` říkající kam každý patří (bez aplikace):
- hook `auto_on_reboot` v `post-fs-data`/`service.sh` (pre-zygote -> `update.sh boot`) a `auto_on_webui_open`.
- výchozí hodnoty `config` + vložený keyring + vendoring (`modules/<mod>/vdlu/`).
- PARTIAL varianta (merge do mountovaného adresáře).

## 11. Stažený toolchain + baseline (ŠTÍHLE, přístup B)

**Rozložení v modulu (zip):** `vdlu/{update.sh, vdlu-verify, config.default, keyring/<id>.pub (RAW 32B),
verify/<abi>/ed25519-mini, baseline.json}`. **ŽÁDNÝ** `bin/` (openssl/curl/zstd). `customize.sh` může oříznout
`verify/` na ABI zařízení (`vdlu-verify` najde mini v `<dir>/ed25519-mini` NEBO `<dir>/verify/<abi>/ed25519-mini`).

**ed25519-mini** (vestavěný binary, jen verify): `ed25519-mini <pubkey32> <msg> <sig64>` -> rc 0=platné,
1=neplatné, 2=usage/IO. msg = přesně podepsané bajty (NEHASHUJE znovu). TweetNaCl PD, statické per-ABI, PROVENANCE.

**tools-feed** (jen public/https profil): servírováno na `<tools_source>` (výchozí odvozeno: vymění poslední segment
`source` za `vdlu-tools`, např. `https://<user>.github.io/<repo>/vdlu-tools`). Obsahuje:
- `tools-manifest.json` - PODEPSANÝ `vdlu-pack` manifest nad stromem `<abi>/curl`, připínající `sha256` každého
  curl (stejný klíč `release-2026`).
- `<abi>/curl` - HOLÉ **statické** curl (soběstačné, ~1MB; curl 8.11.1 + mbedTLS). 🪤 mbedTLS NENESE
  CA bundle: `fetch_url` předává `--capath` (auto-detekce Androidího trust store: `/system/etc/security/cacerts`
  -> APEX conscrypt; `ca_path` přepisuje). Žádný capath = chyba 60. Integrita je ed25519; cert-check je defense-in-depth.

**install-tool** (ENGINE): `update.sh install-tool <abi>` čte `$VDLU_DIR/.work/{tools-manifest.json, tool.<abi>}`
(WEBUI to stáhne přes `fetch()` a zapíše tam), **ověří podpis tools-manifestu (ed25519-mini,
POVINNĚ v jakémkoli profilu)** + hash curl == manifest, a teprve pak ho nainstaluje do `$VDLU_DIR/tools/<abi>/curl` (0755).
Curl běží jako root -> sig+hash před exec uzavírá RCE. Persistuje v Tier-2: nikdy se znovu nestahuje (kromě odinstalace).

**fetch-bootstrap** (WEBUI, `ensureToolchain()`): běží před check/run/resume. `file://` = no-op; curl UŽ
dostupné (Tier-2, NEBO `module/bin/<abi>/curl` ze **self-bundled** modulu, NEBO system) = no-op
(VDLU znovu použije existující curl); jen `https` **vůbec bez curl** stáhne curl + tools-manifest přes webview, zapíše
je do `.work` (chunkovaný base64 přes `ksu.exec`), volá `install-tool`. Trust = kontrola na zařízení, ne stahování.

> 🪤 **Štíhle (fetch-bootstrap) != povinné.** Modul, jehož `bin/` existuje pro JEHO VLASTNÍ featury (např. bundluje
> restic/rclone/age/tar/curl...), se **neztenčí** na ~2MB ani nestahuje curl - VDLU převezme štíhlý engine
> (gz, mini, baseline, fixy) a **znovu použije** vestavěný toolchain. Jen moduly bez vlastního toolchainu
> získávají ~2MB.

**baseline.json** (fix from:0): release kopíruje PODEPSANÝ `manifest.json` dodané verze do
`vdlu/baseline.json`; při čerstvé instalaci engine naseeduje `current.json` z něj (`init_paths`, jen pokud chybí) -> zařízení
se narodí "current", bez auto-updatu sebe sama a bez re-fetche.

<!-- doc-footer -->

---

> _Tato dokumentace byla vytvořena pomocí Claude (Anthropic) a spravuje ji VD171. Opravy a vylepšení jsou vítány; viz [CONTRIBUTING.md](CONTRIBUTING.md)._
