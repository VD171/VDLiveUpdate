> **Languages:** [English](../INTERFACES.md) · [العربية](../ar/INTERFACES.md) · [Čeština](../cs/INTERFACES.md) · [Deutsch](../de/INTERFACES.md) · [Español](../es/INTERFACES.md) · [فارسی](../fa/INTERFACES.md) · [Français](../fr/INTERFACES.md) · [हिन्दी](../hi/INTERFACES.md) · [Bahasa Indonesia](../id/INTERFACES.md) · [Italiano](../it/INTERFACES.md) · [日本語](../ja/INTERFACES.md) · [한국어](../ko/INTERFACES.md) · Nederlands · [Polski](../pl/INTERFACES.md) · [Português](../pt/INTERFACES.md) · [Русский](../ru/INTERFACES.md) · [Svenska](../sv/INTERFACES.md) · [ไทย](../th/INTERFACES.md) · [Türkçe](../tr/INTERFACES.md) · [Українська](../uk/INTERFACES.md) · [Tiếng Việt](../vi/INTERFACES.md) · [中文](../zh/INTERFACES.md)

---

# VDLU - Interfacecontract (de naad tussen de componenten)

**Wet van convergentie:** elke component conformeert zich aan dit bestand. De onderdelen van 4 agents moeten
**op elkaar passen** - de CLI-signaturen, bestandsnamen en JSON-sleutels hieronder zijn **onwrikbaar** (een
wijziging betekent dat je hier eerst uitlijnt).

Principes overgeërfd van de repo's: **pure POSIX sh** op het toestel (geen bashisms; draait met toybox/busybox +
toybox' `sha256sum`/`gzip`/`base64` + de opgehaalde `curl` + de ingebedde `ed25519-mini` - slank, geen binaire
bundel), **nul overbodige commentaren**, **altijd release**, **strengheid bij falen** (hervatbare transactie, niets
bedrieglijk "klaar", niets verloren), **niets versoepeld**.

---

## 1. Toestandsindeling (Tier-2, buiten de moduledirectory)

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
`cancelled:true` in het journal = de engine stopte op een cancel (een niet-terminale, hervatbare toestand; `error`
blijft null).

Engine mee-geleverd in de module: `$MODULE_DIR/vdlu/update.sh` (+ `vdlu-verify`). `$MODULE_DIR =
/data/adb/modules/<module>`. De engine ontvangt via env: `VDLU_DIR`, `MODULE_DIR`, `MODID`.

## 2. Engine-CLI (ENGINE-component)

`sh update.sh <cmd>` - rc 0 = ok, !=0 = fout (stderr bevat de reden):

| cmd | doet |
|---|---|
| `check` | DIFF: downloadt het manifest, vergelijkt; print een JSON van 1 regel `{"update":bool,"from":N,"to":M,"fetch":K,"reboot":bool}`; wijzigt niets. Toestel VOOR op de feed (downgrade geblokkeerd, gehard) = een GOEDAARDIGE toestand: `{"update":false,"ahead":true,"from":N,"to":M}` + rc0 (nooit "check failed"). do_diff rc: 2 fetch/parse, 3 verify/meta, 4 ahead |
| `run` | volledige cyclus: DIFF→FETCH→APPLY→COMMIT; respecteert `cancel`; schrijft voortgang naar `journal.json`; past LIVE toe, staget REBOOT-hard |
| `resume` | hervat de `journal.json`-transactie vanaf de huidige fase (idempotent) |
| `boot` | pre-zygote-modus: `resume` + doet de SWAP van de `staged/*.vdlu-new` (past de `.so` toe), sluit `PENDING_REBOOT`→`DONE` |
| `status` | print `journal.json` (of `{"state":"idle"}`) |
| `cancel` | maakt `$VDLU_DIR/cancel` aan (een lopende `run` stopt op het volgende veilige punt) |

Blob/manifest-bron: `source` uit de config. `<source>` + `/manifest.json`, `/blobs/<sha>`, `/blobs/<sha>.gz`.
`source` begint met `https://` (statische curl opgehaald, TLS) of `file://` (lokale staging).

## 3. manifest.json (geproduceerd door de PRODUCER, geconsumeerd door de ENGINE)

```json
{ "schema":1, "module":"<id>", "version":<int>, "version_name":"<str>", "built":"<ISO8601>",
  "engine_min":3, "key_id":"<str>", "channel":"stable",
  "files":[ {"path":"webroot/index.html","sha256":"<hex64>","size":<int>,"mode":"0644","enc":"raw|gz","class":"live|soft|reboot"} ],
  "delete":["<path>"], "sig":"<base64>" }
```

- `files[]` = de VOLLEDIGE doelboom. `class`: `live` (webroot/bin/lib/confs/scripts-on-demand/module.prop) ·
  `soft` (service.sh/post-fs-data.sh/boot-completed.sh) · `reboot` (`zygisk/**/*.so`, `system/**`, `*.rule`).
  Standaard op basis van pad; downgradt `reboot`→`live` nooit.
- `enc`: `gz` (gzip `-9 -n`, deterministisch; toybox gunzip op het toestel) alleen wanneer het goed comprimeert EN de
  omvang significant is; `sha256` is ALTIJD van de originele inhoud.
- `sig`: handtekening van het canonieke manifest ZONDER het `sig`-veld (§4 van verify).

## 4. journal.json (ENGINE schrijft, WEBUI leest - het voortgangscontract)

```json
{ "schema":1, "module":"<id>", "target":<version>, "from":<version>,
  "phase":"diff|fetch|apply|commit", "state":"PLANNED|FETCHING|FETCHED|APPLYING|APPLIED_LIVE|PENDING_REBOOT|DONE|ERROR|DEFERRED",
  "total":<int>, "done":<int>, "current":"<path>", "bytes":<int>, "reboot_pending":bool,
  "cancelled":bool, "error":"<str|null>", "updated":"<ISO8601>",
  "items":[ {"path":"<p>","sha256":"<h>","class":"<c>","st":"pending|fetched|applied|staged|skipped"} ] }
```

Toestandsmachine (vaste volgorde): `PLANNED→FETCHING→FETCHED→APPLYING→APPLIED_LIVE→(PENDING_REBOOT|DONE)`.
`DONE` pas zodra een her-hash van ALLES overeenkomt. Een gestagede REBOOT-hard ⇒ `PENDING_REBOOT` (niet `DONE`).
Uitgangen vanuit de `fetch`-fase: `ERROR` (harde fout) of `DEFERRED` (net_policy blokkeerde de download - goedaardig/hervatbaar,
geen fout).

## 5. config (key=value, één per regel; bewerkbaar in de WEBUI)

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

**Boot retry (offline) - GEDULDIG, batterijveilig:** alleen bij `boot` (nooit bij check/auto-open). Als het ophalen
van het manifest faalt wegens NETWERK (`fetch_offline` classificeert op basis van de exit van de fetcher), wacht het
en probeert het opnieuw tot succes OF tot `boot_retry_minutes` aan AWAKE-tijd op is. Een ontwerp dat **niets
vasthoudt en niet leegtrekt**:
- **Nul wakelock:** tussen pogingen is het `sleep`, dat bevriest in deep-sleep → het toestel slaapt normaal
  (~nul batterij); de retry pauzeert en hervat zodra het toestel al wakker is.
- **Nul vastgehouden lock:** `acquire_lock_try`+release TUSSEN pogingen (houdt de lock niet vast tijdens het wachten) →
  `run`/handmatige check blokkeren nooit; als een handmatige run intussen een TARGET staget, wijkt de boot.
- **Wekt de radio nergens voor:** een `net_allowed`-probe (via `net_type`/`ip route get`, een kernel-route-
  lookup die het policy-routing van Android respecteert; geen pakket) gatet elke poging - het besteedt pas een fetch
  zodra het netwerk is verschenen.
- Probeert NOOIT een deterministische fout opnieuw (manifest/sig/downgrade). `--connect-timeout 15` op de fetch (blijft
  niet hangen op een captive portal). `service.sh` zet het op de achtergrond (de boot hangt nooit).
- ⛔ **HARD: `boot_retry_minutes>0` aanzetten vereist de GEDULDIGE engine** (die met
  `net_allowed`+`acquire_lock_try`, canoniek `da7115f4`+). De VORIGE boot-retry (houdt de lock het hele
  venster vast + probeert blinde curl offline opnieuw) **TREKT DE BATTERIJ LEEG/wekt de radio** - de retry aanzetten in een oude
  engine is een voetboog. Bij het inschakelen: lever de huidige engine mee.

**`net_policy` (any|wifi|mobile):** gatet de **DOWNLOAD** op basis van netwerktype. `net_type()` classificeert de egress
van `ip route get` (cellulaire iface `rmnet/ccmni/v4-*/clat` = mobile; al het overige = wifi; kernel-lookup, geen
pakket). `net_allowed()` vergelijkt met `net_policy` en gatet `do_fetch` (blobs) + de geduldige boot-retry-
probe. De **manifest-check blijft gratis** (klein → de UI meldt een update op elk netwerk); alleen de download
wacht op het toegestane netwerk. Een download op een niet-toegestaan netwerk = de **`DEFERRED`**-toestand in het
journal (GEEN ERROR; een vriendelijke blauwe INFO-toast "waiting for X network"; plan/target blijven behouden, het hervat bij de volgende
check/boot op het juiste netwerk). `net_policy` **verdringt** `allow_metered` (dat nooit werd geconsumeerd).
Engine `97baf887`+ (`file://` wordt nooit gegatet).

## 6. Handtekening (PRODUCER tekent op de pc via openssl; ENGINE verifieert op het toestel via ed25519-mini)

- Canonicalisatie: het manifest ZONDER `sig`, sleutels gesorteerd, compacte JSON (geen overbodige spaties), UTF-8.
  Wat getekend/geverifieerd wordt = de `sha256`-hex van die canonieke vorm (geeft cross-tool-determinisme).
- `producer/vdlu-sign <manifest.json> <privkey.pem> <key_id>` → injecteert `key_id` + `sig` (base64 van de ed25519-handtekening van de canonieke sha256) in het manifest, ter plekke.
- `engine/vdlu-verify <manifest.json> <keyring_dir>` → rc 0 als de `sig` overeenkomt met de `<key_id>.pub`-pubkey in
  de keyring (SLANK: pubkey **RAW 32 bytes**). Intern, geen openssl: toybox `sha256sum`/`base64 -d` + de
  ingebedde `ed25519-mini`-binary (CLI `ed25519-mini <pub32> <msg> <sig64>`, rc 0=geldig/1=ongeldig/2=gebruik).
  rc!=0 = weiger. **`profile=hardened` ⇒ verify verplicht; falen = afbreken.**
  `profile=trusted` ⇒ verify is best-effort (bron al vertrouwd via SSH), maar de hash van elke blob wordt ALTIJD gecontroleerd.
- **Allowlist voor module-update-sleutel (fail-closed, vóór de pubkey-selectie):** de `key_id` van het manifest moet een geaccepteerde MODULE-UPDATE-sleutel zijn voordat `<key_id>.pub` wordt geselecteerd - de `key_id` van de config (§5) is die allowlist. Een keyring kan OOK een sleutel van lager vertrouwen dragen (bijv. een fingerprint-feed-sleutel, geautomatiseerd, ander account); zonder de allowlist zou een manifest dat door die sleutel is getekend verifiëren en bij een lek een volledige flashless root-update toepassen. `verify_manifest` dwingt het af in BEIDE profiles en geeft de opgeloste set door aan `vdlu-verify` via de env `VDLU_KEYID_ALLOW` (zodat de standalone verifier het eens is). Niet ingesteld is standaardveilig (keyring met één sleutel: alleen die sleutel; keyring met meerdere sleutels: geweigerd tot `key_id` is vastgepind). De vertrouwenswortel van de fingerprint-feed is een APART pad met zijn eigen vastgepinde sleutel en wordt niet beïnvloed.
- `producer/vdlu-keygen <id> <out>` → genereert `<id>.pem` (priv) + `<id>.pub` (PEM, voor tooling op de pc) +
  `<id>.pub.raw` (**RAW 32B** = de `<id>.pub` van de slanke keyring op het toestel). openssl `genpkey -algorithm ed25519`.

## 7. Blob - verificatie (ENGINE)

Downloadt `<source>/blobs/<sha>` (of `.gz` als `enc=gz`), schrijft `.part`, als `gz` decomprimeert (`gunzip`),
controleert `sha256sum` == de `sha256` van het manifest; overeenkomst → atomische `mv` naar `$VDLU_DIR/blobs/<sha>`. 3 fouten op
dezelfde blob = breekt de fase af (niets toegepast). Een blob die al in `$VDLU_DIR/blobs/<sha>` staat met een ok hash =
slaat de download over.

## 8. APPLY per class (ENGINE)

- `live`/`soft`: backup `rollback/<v>/<path>` → schrijft `$MODULE_DIR/<path>.vdlu-tmp` vanuit de blob → `chmod mode` →
  atomische `rename` over het doel. Al op de doelhash = overslaan. (In de Zygisk-variant gaat het schrijven naar
  de gemounte dir = samenvoeging per bestand, nooit `rm -rf` van de dir.)
- `reboot`: materialiseert naar `$VDLU_DIR/staged/<path>.vdlu-new` (raakt de live versie NIET aan). De swap is bij `boot`.
- `delete[]`: backup → verwijderen.

## 9. WEBUI ↔ ENGINE (WEBUI-component)

- Vuurt af: `ksu.exec("sh $MODULE_DIR/vdlu/update.sh run")` (achtergrond).
- Voortgang: een lichte poll `ksu.exec("cat $VDLU_DIR/journal.json")` elke ~1s; rendert `{phase,state,total,done,current,bytes}`.
- Liveness: journal afwezig voor 8 ticks ⇒ "no response". Journal BEVROREN (zelfde waarden) voor 20 ticks ⇒ controleert `lock.d`: levend = gaat door (trage fetch van 1 blob), dood = fout + Resume. Zonder dit zou een run die middenin de fetch stierf de toast bevriezen op "updating".
- Cancel: `ksu.exec("touch $VDLU_DIR/cancel")`.
- Config: leest/schrijft `$VDLU_DIR/config` (key=value) in een "Updates"-tabblad.
- Toast: balk + `phase done/total · current`; bij voltooiing met `reboot_pending` ⇒ een persistente banner "reboot to activate the .so".
- Auto-open (`auto_on_webui_open=1`): doet eerst een STILLE `check()` (geen voortgangstoast); vuurt alleen de `run`+persistente toast af als `update && fetch>0`. Up-to-date/ahead/niets-nieuws = een inline resultaat in het paneel, nul achtergebleven toast. Niet-opdringerig zoals de handmatige knop (de toast verschijnt alleen wanneer er een echte download is). De curl-bootstrap is eenmalig.

## 10. Integratie in de demo (INTEGRATION-component) - SNIPPETS, bewerk de live bestanden niet

Produceert, in `integration/demo/`, snippets + een `INTEGRATION.md` die zegt waar elk hoort te gaan (zonder toe te passen):
- de `auto_on_reboot`-hook in `post-fs-data`/`service.sh` (pre-zygote → `update.sh boot`) en `auto_on_webui_open`.
- de `config`-standaardwaarden + de ingebedde keyring + de vendoring (`modules/<mod>/vdlu/`).
- de PARTIAL-variant (samenvoegen in de gemounte dir).

## 11. Opgehaalde toolchain + baseline (SLANK, Aanpak B)

**Indeling in de module (zip):** `vdlu/{update.sh, vdlu-verify, config.default, keyring/<id>.pub (RAW 32B),
verify/<abi>/ed25519-mini, baseline.json}`. **GEEN** `bin/` (openssl/curl/zstd). `customize.sh` kan `verify/`
terugsnoeien tot de ABI van het toestel (`vdlu-verify` vindt de mini op `<dir>/ed25519-mini` OF `<dir>/verify/<abi>/ed25519-mini`).

**ed25519-mini** (ingebedde binary, alleen-verify): `ed25519-mini <pubkey32> <msg> <sig64>` → rc 0=geldig,
1=ongeldig, 2=gebruik/IO. msg = de exacte getekende bytes (her-hasht NIET). TweetNaCl PD, statisch per ABI, PROVENANCE.

**tools-feed** (alleen public/https-profiel): geserveerd op `<tools_source>` (standaard afgeleid: vervangt het laatste segment
van `source` door `vdlu-tools`, bijv. `https://<user>.github.io/<repo>/vdlu-tools`). Bevat:
- `tools-manifest.json` - een GETEKEND `vdlu-pack`-manifest over de `<abi>/curl`-boom, dat de `sha256` van
  elke curl vastpint (dezelfde `release-2026`-sleutel).
- `<abi>/curl` - de RAW **statische** curl (zelfstandig, ~1MB; curl 8.11.1 + mbedTLS). 🪤 mbedTLS
  draagt GEEN CA-bundel: `fetch_url` geeft `--capath` door (auto-detectie van de Android trust store: `/system/etc/security/cacerts`
  → APEX conscrypt; `ca_path` overschrijft). Geen capath = fout 60. De integriteit is de ed25519; de cert-check is defence-in-depth.

**install-tool** (ENGINE): `update.sh install-tool <abi>` leest `$VDLU_DIR/.work/{tools-manifest.json, tool.<abi>}`
(de WEBUI downloadt het via `fetch()` en schrijft het daar), **verifieert de handtekening van het tools-manifest (ed25519-mini,
VERPLICHT in elk profiel)** + de hash van de curl == manifest, en installeert het pas dan naar `$VDLU_DIR/tools/<abi>/curl` (0755).
De curl draait als root → sig+hash vóór exec dicht de RCE. Blijft behouden in Tier-2: wordt nooit opnieuw gedownload (behalve bij deïnstallatie).

**fetch-bootstrap** (WEBUI, `ensureToolchain()`): draait vóór check/run/resume. `file://` = no-op; curl AL
beschikbaar (Tier-2, OF `module/bin/<abi>/curl` uit een **zelf-gebundelde** module, OF systeem) = no-op
(VDLU hergebruikt de bestaande curl); alleen `https` **zonder enige curl** downloadt curl + tools-manifest via de webview, schrijft
ze naar `.work` (chunked base64 via `ksu.exec`), roept `install-tool` aan. Vertrouwen = de controle op het toestel, niet de download.

> 🪤 **Slank (fetch-bootstrap) ≠ verplicht.** Een module waarvan de `bin/` bestaat voor ZIJN EIGEN features (bijv. hij bundelt
> restic/rclone/age/tar/curl...) slankt **niet** af tot ~2MB en downloadt geen curl - VDLU adopteert de slanke engine
> (gz, mini, baseline, fixes) en **hergebruikt** de ingebedde toolchain. Alleen modules zonder hun eigen toolchain
> winnen de ~2MB.

**baseline.json** (fix vanaf from:0): de release kopieert het GETEKENDE `manifest.json` van de geleverde versie naar
`vdlu/baseline.json`; bij een verse installatie seedt de engine `current.json` daaruit (`init_paths`, alleen indien afwezig) → het
toestel wordt "current" geboren, zonder auto-update van zichzelf en zonder her-fetch.

<!-- doc-footer -->

---

> _Deze documentatie is gegenereerd met Claude (Anthropic) en wordt onderhouden door VD171. Correcties en verbeteringen zijn welkom; zie [CONTRIBUTING.md](CONTRIBUTING.md)._
