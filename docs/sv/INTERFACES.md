> **Languages:** [English](../INTERFACES.md) · [العربية](../ar/INTERFACES.md) · [Čeština](../cs/INTERFACES.md) · [Deutsch](../de/INTERFACES.md) · [Español](../es/INTERFACES.md) · [فارسی](../fa/INTERFACES.md) · [Français](../fr/INTERFACES.md) · [हिन्दी](../hi/INTERFACES.md) · [Bahasa Indonesia](../id/INTERFACES.md) · [Italiano](../it/INTERFACES.md) · [日本語](../ja/INTERFACES.md) · [한국어](../ko/INTERFACES.md) · [Nederlands](../nl/INTERFACES.md) · [Polski](../pl/INTERFACES.md) · [Português](../pt/INTERFACES.md) · [Русский](../ru/INTERFACES.md) · Svenska · [ไทย](../th/INTERFACES.md) · [Türkçe](../tr/INTERFACES.md) · [Українська](../uk/INTERFACES.md) · [Tiếng Việt](../vi/INTERFACES.md) · [中文](../zh/INTERFACES.md)

---

# VDLU - Gränssnittskontrakt (skarven mellan komponenterna)

**Konvergenslag:** varje komponent rättar sig efter den här filen. Delarna från 4 agenter måste **passa ihop** - CLI-
signaturerna, filnamnen och JSON-nycklarna nedan är **oföränderliga** (en ändring innebär att man först samordnar här).

Principer ärvda från repona: **ren POSIX sh** på enheten (inga bashismer, körs med toybox/busybox +
toybox's `sha256sum`/`gzip`/`base64` + den hämtade `curl` + den inbäddade `ed25519-mini` - slimmad, inget binär-
paket), **noll onödiga kommentarer**, **alltid release**, **rigor vid fel** (återupptagbar transaktion, inget felaktigt
"klart", inget förlorat), **inget uppluckrat**.

---

## 1. Tillståndslayout (Tier-2, utanför modulkatalogen)

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
`cancelled:true` i journalen = motorn stoppade på en avbrytning (ett icke-terminalt, återupptagbart tillstånd, `error`
förblir null).

Motorn vendorad i modulen: `$MODULE_DIR/vdlu/update.sh` (+ `vdlu-verify`). `$MODULE_DIR =
/data/adb/modules/<module>`. Motorn tar emot via env: `VDLU_DIR`, `MODULE_DIR`, `MODID`.

## 2. Motor-CLI (ENGINE-komponenten)

`sh update.sh <cmd>` - rc 0 = ok, !=0 = fel (stderr har orsaken):

| cmd | gör |
|---|---|
| `check` | DIFF: laddar ner manifestet, jämför; skriver ut en 1-rads JSON `{"update":bool,"from":N,"to":M,"fetch":K,"reboot":bool}`; ändrar ingenting. Enhet FÖRE flödet (nedgradering blockerad, hardened) = ett GODARTAT tillstånd: `{"update":false,"ahead":true,"from":N,"to":M}` + rc0 (aldrig "check failed"). do_diff rc: 2 fetch/parse, 3 verify/meta, 4 ahead |
| `run` | full cykel: DIFF→FETCH→APPLY→COMMIT; respekterar `cancel`; skriver förlopp till `journal.json`; tillämpar LIVE, scenlägger REBOOT-hard |
| `resume` | återupptar `journal.json`-transaktionen från den aktuella fasen (idempotent) |
| `boot` | pre-zygote-läge: `resume` + gör SWAP av `staged/*.vdlu-new` (tillämpar `.so`), stänger `PENDING_REBOOT`→`DONE` |
| `status` | skriver ut `journal.json` (eller `{"state":"idle"}`) |
| `cancel` | skapar `$VDLU_DIR/cancel` (ett pågående `run` stoppar vid nästa säkra punkt) |

Blob-/manifestkälla: `source` från config. `<source>` + `/manifest.json`, `/blobs/<sha>`, `/blobs/<sha>.gz`.
`source` börjar med `https://` (statisk curl hämtas, TLS) eller `file://` (lokal staging).

## 3. manifest.json (produceras av PRODUCER, konsumeras av ENGINE)

```json
{ "schema":1, "module":"<id>", "version":<int>, "version_name":"<str>", "built":"<ISO8601>",
  "engine_min":5, "key_id":"<str>", "channel":"stable",
  "files":[ {"path":"webroot/index.html","sha256":"<hex64>","size":<int>,"mode":"0644","enc":"raw|gz","class":"live|soft|reboot"} ],
  "delete":["<path>"], "sig":"<base64>" }
```

- `files[]` = det KOMPLETTA målträdet. `class`: `live` (webroot/bin/lib/confs/scripts-on-demand/module.prop) ·
  `soft` (service.sh/post-fs-data.sh/boot-completed.sh) · `reboot` (`zygisk/**/*.so`, `system/**`, `*.rule`).
  Standard efter sökväg, nedgraderar aldrig `reboot`→`live`.
- `enc`: `gz` (gzip `-9 -n`, deterministisk, toybox gunzip på enheten) endast när det komprimerar väl OCH
  storleken är betydande, `sha256` är ALLTID av originalinnehållet.
- `sig`: signatur av det kanoniska manifestet UTAN `sig`-fältet (§4 i verify).
- **Exkludering av tillitsankaret (engine-sidig, VDLU#2):** engine SLÄPPER från planen varje
  `files[]`/`delete[]`-sökväg under `vdlu/` (dess egen `update.sh`/`vdlu-verify`/`verify/*`/`keyring/*`/config)
  - aldrig hämtad, tillämpad eller raderad - även om ett signerat flöde bär dem. Tillitsankaret på enheten
  ändras bara genom en fullständig signerad om-flash, inte över nätet, `vdlu-pack` exkluderar också `vdlu/`
  på producent-sidan, så detta är en andra, engine-sidig vakt mot en läckt signeringsnyckel.

## 4. journal.json (ENGINE skriver, WEBUI läser - förloppskontraktet)

```json
{ "schema":1, "module":"<id>", "target":<version>, "from":<version>,
  "phase":"diff|fetch|apply|commit", "state":"PLANNED|FETCHING|FETCHED|APPLYING|APPLIED_LIVE|PENDING_REBOOT|DONE|ERROR|DEFERRED",
  "total":<int>, "done":<int>, "current":"<path>", "bytes":<int>, "reboot_pending":bool,
  "cancelled":bool, "error":"<str|null>", "updated":"<ISO8601>",
  "items":[ {"path":"<p>","sha256":"<h>","class":"<c>","st":"pending|fetched|applied|staged|skipped"} ] }
```

Tillståndsmaskin (fast ordning): `PLANNED→FETCHING→FETCHED→APPLYING→APPLIED_LIVE→(PENDING_REBOOT|DONE)`.
`DONE` endast när en om-hashning av ALLT stämmer. En scenlagd REBOOT-hard ⇒ `PENDING_REBOOT` (inte `DONE`). Utgångar
från `fetch`-fasen: `ERROR` (hårt fel) eller `DEFERRED` (net_policy blockerade nedladdningen - godartat/återupptagbart,
inte ett fel).

## 5. config (key=value, en per rad, redigerbar i WEBUI)

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

**Boot-retry (offline) - TÅLMODIG, batterisäker:** endast vid `boot` (aldrig vid check/auto-open). Om manifest-
hämtningen misslyckas på grund av NÄTVERK (`fetch_offline` klassificerar efter hämtarens utgång) väntar den och
försöker igen tills den lyckas ELLER `boot_retry_minutes` av VAKEN-tid är uttömd. En design som **håller ingenting
och tömmer inte batteriet**:
- **Noll wakelock:** mellan försök är det `sleep`, som fryser i deep-sleep → enheten sover normalt
  (~noll batteri), omförsöket pausar och återupptas när enheten redan är vaken.
- **Noll hållet lås:** `acquire_lock_try`+release MELLAN försök (håller inte låset medan den väntar) →
  `run`/manuell check blockerar aldrig, om ett manuellt run scenlägger ett TARGET under tiden skjuter booten upp.
- **Väcker inte radion i onödan:** en `net_allowed`-sondering (via `net_type`/`ip route get`, en kernel-route-
  uppslagning som respekterar Androids policy-routing, inget paket) grindar varje försök - den spenderar en hämtning
  först när nätverket har dykt upp.
- Försöker ALDRIG igen vid ett deterministiskt fel (manifest/sig/nedgradering). `--connect-timeout 15` på hämtningen
  (hänger inte på en captive portal). `service.sh` lägger den i bakgrunden (booten hänger aldrig).
- ⛔ **HARD: att slå på `boot_retry_minutes>0` kräver den TÅLMODIGA motorn** (den med
  `net_allowed`+`acquire_lock_try`, kanonisk `da7115f4`+). Den TIDIGARE boot-retryn (håller låset hela fönstret +
  försöker blind curl offline igen) **TÖMMER batteriet/väcker radion** - att slå på omförsöket i en gammal motor
  är att skjuta sig själv i foten. När du aktiverar det, vendora den aktuella motorn.

**`net_policy` (any|wifi|mobile):** grindar **NEDLADDNINGEN** efter nätverkstyp. `net_type()` klassificerar utgången
av `ip route get` (mobilgränssnitt `rmnet/ccmni/v4-*/clat` = mobile, allt annat = wifi, kernel-uppslagning, inget
paket). `net_allowed()` jämför mot `net_policy` och grindar `do_fetch` (blobbar) + den tålmodiga boot-retry-
sonderingen. **Manifestkontrollen förblir fri** (liten → gränssnittet rapporterar en uppdatering på vilket nätverk
som helst), endast nedladdningen väntar på det tillåtna nätverket. En nedladdning på ett ej tillåtet nätverk =
tillståndet **`DEFERRED`** i journalen (INTE ERROR, en mild blå INFO-toast "väntar på X-nätverk", plan/target består,
den återupptas vid nästa check/boot på rätt nätverk). `net_policy` **ersätter** `allow_metered` (som aldrig
konsumerades). Motor `97baf887`+ (`file://` grindas aldrig).

## 6. Signatur (PRODUCER signerar på PC:n via openssl, ENGINE verifierar på enheten via ed25519-mini)

- Kanonikalisering: manifestet UTAN `sig`, nycklar sorterade, kompakt JSON (inga överflödiga mellanslag), UTF-8.
  Det som signeras/verifieras = `sha256`-hexen av den kanoniska formen (ger determinism över verktyg).
- `producer/vdlu-sign <manifest.json> <privkey.pem> <key_id>` → injicerar `key_id` + `sig` (base64 av ed25519-signaturen av den kanoniska sha256) i manifestet, på plats.
- `engine/vdlu-verify <manifest.json> <keyring_dir>` → rc 0 om `sig` matchar `<key_id>.pub`-pubnyckeln i
  keyringen (SLIM: pubnyckel **RAW 32 byte**). Internt, ingen openssl: toybox `sha256sum`/`base64 -d` + den
  inbäddade `ed25519-mini`-binären (CLI `ed25519-mini <pub32> <msg> <sig64>`, rc 0=giltig/1=ogiltig/2=användning).
  rc!=0 = avvisa. **`profile=hardened` ⇒ verify obligatoriskt, fel = avbryt.**
  `profile=trusted` ⇒ verify är best-effort (källan redan betrodd via SSH), men varje blobs hash kontrolleras ALLTID.
- **Allowlist för module-update-nyckel (fail-closed, före pubnyckel-valet):** manifestets `key_id` måste vara en accepterad MODULE-UPDATE-nyckel innan `<key_id>.pub` väljs - configens `key_id` (§5) är den allowlisten. En keyring kan OCKSÅ bära en nyckel med lägre tillit (t.ex. en fingerprint-feed-nyckel, automatiserad, annat konto), utan allowlisten skulle ett manifest signerat av den nyckeln verifieras och vid en läcka tillämpa en fullständig flashless root-uppdatering. `verify_manifest` upprätthåller det i BÅDA profiles och skickar den upplösta mängden till `vdlu-verify` via env `VDLU_KEYID_ALLOW` (så att den fristående verifieraren håller med). Osatt är standardsäkert (keyring med en nyckel: bara den nyckeln, keyring med flera nycklar: avvisad tills `key_id` är fastnålad). Fingerprint-feedens tillitsrot är en SEPARAT väg med sin egen fastnålade nyckel och påverkas inte.
- `producer/vdlu-keygen <id> <out>` → genererar `<id>.pem` (priv) + `<id>.pub` (PEM, för verktyg på PC:n) +
  `<id>.pub.raw` (**RAW 32B** = `<id>.pub` i den slimmade keyringen på enheten). openssl `genpkey -algorithm ed25519`.

## 7. Blob - verifiering (ENGINE)

Laddar ner `<source>/blobs/<sha>` (eller `.gz` om `enc=gz`), skriver `.part`, om `gz` dekomprimerar (`gunzip`),
kontrollerar `sha256sum` == manifestets `sha256`, matchning → atomisk `mv` till `$VDLU_DIR/blobs/<sha>`. 3 miss-
lyckanden på samma blob = avbryter fasen (inget tillämpat). En blob som redan finns i `$VDLU_DIR/blobs/<sha>` med en
ok hash = hoppar över nedladdningen.

## 8. APPLY efter klass (ENGINE)

- `live`/`soft`: backup `rollback/<v>/<path>` → skriver `$MODULE_DIR/<path>.vdlu-tmp` från bloben → `chmod mode` →
  atomisk `rename` över målet. Redan på målets hash = hoppa över. (I Zygisk-varianten går skrivningen till den
  monterade katalogen = sammanfogning per fil, aldrig `rm -rf` av katalogen.)
- `reboot`: materialiseras i `$VDLU_DIR/staged/<path>.vdlu-new` (rör INTE den levande). Bytet sker vid `boot`.
- `delete[]`: backup → ta bort.

## 9. WEBUI ↔ ENGINE (WEBUI-komponenten)

- Avfyrar: `ksu.exec("sh $MODULE_DIR/vdlu/update.sh run")` (bakgrund).
- Förlopp: en lätt poll `ksu.exec("cat $VDLU_DIR/journal.json")` var ~1 s, renderar `{phase,state,total,done,current,bytes}`.
- Livskraft: journal frånvarande i 8 ticks ⇒ "inget svar". Journal FRUSEN (samma värden) i 20 ticks ⇒ kontrollerar `lock.d`: levande = fortsätter (långsam hämtning av 1 blob), död = fel + Resume. Utan detta skulle ett run som dog mitt i hämtningen frysa toasten vid "uppdaterar".
- Avbryt: `ksu.exec("touch $VDLU_DIR/cancel")`.
- Config: läser/skriver `$VDLU_DIR/config` (key=value) i en "Updates"-flik.
- Toast: stapel + `phase done/total · current`, vid avslut med `reboot_pending` ⇒ en beständig banner "starta om för att aktivera .so-filen".
- Auto-open (`auto_on_webui_open=1`): gör först en TYST `check()` (ingen förloppstoast), avfyrar `run`+beständig toast endast om `update && fetch>0`. Aktuell/före/inget nytt = ett inline-resultat i panelen, noll kvarvarande toast. Icke-påträngande som den manuella knappen (toasten visas bara när det finns en riktig nedladdning). curl-bootstrappen är en engångsföreteelse.

## 10. Integration i demon (INTEGRATION-komponenten) - SNIPPETS, redigera inte de levande filerna

Producerar, i `integration/demo/`, snippets + en `INTEGRATION.md` som säger var var och en hör hemma (utan att tillämpa):
- `auto_on_reboot`-kroken i `post-fs-data`/`service.sh` (pre-zygote → `update.sh boot`) och `auto_on_webui_open`.
- `config`-standardvärdena + den inbäddade keyringen + vendoringen (`modules/<mod>/vdlu/`).
- PARTIAL-varianten (sammanfoga i den monterade katalogen).

## 11. Hämtad verktygskedja + baseline (SLIM, Approach B)

**Layout i modulen (zip):** `vdlu/{update.sh, vdlu-verify, config.default, keyring/<id>.pub (RAW 32B),
verify/<abi>/ed25519-mini, baseline.json}`. **INGEN** `bin/` (openssl/curl/zstd). `customize.sh` kan beskära
`verify/` ner till enhetens ABI (`vdlu-verify` hittar minin på `<dir>/ed25519-mini` ELLER `<dir>/verify/<abi>/ed25519-mini`).

**ed25519-mini** (inbäddad binär, endast verify): `ed25519-mini <pubkey32> <msg> <sig64>` → rc 0=giltig,
1=ogiltig, 2=användning/IO. msg = de exakta signerade byten (om-hashar INTE). TweetNaCl PD, statisk per ABI, PROVENANCE.

**tools-feed** (endast public/https-profil): serveras vid `<tools_source>` (standard härledd: byter ut sista segmentet
av `source` mot `vdlu-tools`, t.ex. `https://<user>.github.io/<repo>/vdlu-tools`). Innehåller:
- `tools-manifest.json` - ett SIGNERAT `vdlu-pack`-manifest över `<abi>/curl`-trädet, som fäster `sha256` för
  varje curl (samma `release-2026`-nyckel).
- `<abi>/curl` - den RÅA **statiska** curl (fristående, ~1MB, curl 8.11.1 + mbedTLS). 🪤 mbedTLS bär INTE
  med sig ett CA-paket: `fetch_url` skickar `--capath` (autodetektering av Androids trust store: `/system/etc/security/cacerts`
  → APEX conscrypt, `ca_path` åsidosätter). Ingen capath = fel 60. Integriteten är ed25519, certifikatkontrollen är djupförsvar.

**install-tool** (ENGINE): `update.sh install-tool <abi>` läser `$VDLU_DIR/.work/{tools-manifest.json, tool.<abi>}`
(WEBUI laddar ner den via `fetch()` och skriver den där), **verifierar tools-manifestets signatur (ed25519-mini,
OBLIGATORISKT i vilken profil som helst)** + curlens hash == manifest, och installerar den först då till `$VDLU_DIR/tools/<abi>/curl` (0755).
Curlen körs som root → sig+hash före exec stänger RCE:n. Består i Tier-2: laddas aldrig ner igen (utom vid avinstallation).

**fetch-bootstrap** (WEBUI, `ensureToolchain()`): körs före check/run/resume. `file://` = no-op, curl REDAN
tillgänglig (Tier-2, ELLER `module/bin/<abi>/curl` från en **självpaketerad** modul, ELLER systemet) = no-op
(VDLU återanvänder den befintliga curlen), endast `https` **helt utan curl** laddar ner curl + tools-manifest via webview:n, skriver
dem till `.work` (chunkad base64 via `ksu.exec`), anropar `install-tool`. Tillit = kontrollen på enheten, inte nedladdningen.

> 🪤 **Slim (fetch-bootstrap) ≠ obligatorisk.** En modul vars `bin/` finns för SINA EGNA funktioner (t.ex. den paketerar
> restic/rclone/age/tar/curl...) slimmar **inte** ner till ~2MB och laddar inte ner curl - VDLU antar den slimmade motorn
> (gz, mini, baseline, fixar) och **återanvänder** den inbäddade verktygskedjan. Endast moduler utan egen verktygskedja får de ~2MB.

**baseline.json** (fix from:0): releasen kopierar den SIGNERADE `manifest.json` för den levererade versionen till
`vdlu/baseline.json`, vid en ny installation seedar motorn `current.json` från den (`init_paths`, bara om frånvarande) → enheten
föds "aktuell", utan någon autouppdatering av sig själv och ingen om-hämtning.

<!-- doc-footer -->

---

> _Denna dokumentation genererades med Claude (Anthropic) och underhålls av VD171. Rättelser och förbättringar välkomnas, se [CONTRIBUTING.md](CONTRIBUTING.md)._
