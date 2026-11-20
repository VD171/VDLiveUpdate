> **Languages:** [English](../ENGINE.md) · [العربية](../ar/ENGINE.md) · [Čeština](../cs/ENGINE.md) · [Deutsch](../de/ENGINE.md) · [Español](../es/ENGINE.md) · [فارسی](../fa/ENGINE.md) · [Français](../fr/ENGINE.md) · [हिन्दी](../hi/ENGINE.md) · [Bahasa Indonesia](../id/ENGINE.md) · [Italiano](../it/ENGINE.md) · [日本語](../ja/ENGINE.md) · [한국어](../ko/ENGINE.md) · Nederlands · [Polski](../pl/ENGINE.md) · [Português](../pt/ENGINE.md) · [Русский](../ru/ENGINE.md) · [Svenska](../sv/ENGINE.md) · [ไทย](../th/ENGINE.md) · [Türkçe](../tr/ENGINE.md) · [Українська](../uk/ENGINE.md) · [Tiếng Việt](../vi/ENGINE.md) · [中文](../zh/ENGINE.md)

---

# VDLU-engine (`update.sh`)

Flashless, incrementele update-client voor KSU/Magisk-modules. Implementeert de
`DIFF -> FETCH -> APPLY -> COMMIT`-cyclus als een hervatbare transactie. Conformeert zich aan `INTERFACES.md` (de wet
van convergentie).

Pure POSIX sh (mksh/busybox/toybox). **SLANK:** het hangt alleen af van toybox (`sha256sum`/`gzip`/`base64`/`date`) +
de ingebedde `ed25519-mini` (ed25519-verify; **geen openssl op het toestel**) + een statische `curl` die bij de
eerste https-update wordt **opgehaald** (de WebUI doet de `fetch()`, bewaart hem in Tier-2, en `install-tool` verifieert zijn
handtekening+hash VÓÓR gebruik). `file://` heeft geen curl nodig. Nul afhankelijkheid van `jq`.

## Aanroep

```sh
VDLU_DIR=/data/adb/<mod>/vdlu MODULE_DIR=/data/adb/modules/<mod> MODID=<mod> \
  sh $MODULE_DIR/vdlu/update.sh <cmd>
```

`rc 0` = ok; `rc != 0` = fout (reden op stderr). `vdlu-verify` wordt geleverd door een andere component
(handtekening in `INTERFACES.md §6`); de engine roept het alleen aan.

| cmd | doet |
|---|---|
| `check` | alleen-lezen DIFF; print `{"update":bool,"from":N,"to":M,"fetch":K,"reboot":bool}`; wijzigt niets |
| `run` | volledige LIVE-cyclus + staget REBOOT-hard; respecteert `cancel`; voortgang in `journal.json` |
| `resume` | hervat de hangende transactie (`target.json`) vanaf de huidige fase; idempotent; swapt de `.so` **niet** |
| `boot` | pre-zygote-modus: resume **+** swapt de `staged/*.vdlu-new` → sluit `PENDING_REBOOT`→`DONE`. Zonder hangende transactie draait het een verse cyclus en past het alles toe (inclusief de `.so`) in één enkele boot |
| `status` | print `journal.json` (of `{"state":"idle"}`) |
| `cancel` | maakt `$VDLU_DIR/cancel` aan; een lopende `run` stopt op het volgende veilige punt |

## Toestandsmachine (journal.json)

```
PLANNED -> FETCHING -> FETCHED -> APPLYING -> APPLIED_LIVE -> (PENDING_REBOOT | DONE)
```

`DONE` pas zodra een her-hash van ALLES overeenkomt. Als er een REBOOT-hard gestaged werd ⇒ `PENDING_REBOOT` (nooit een
bedrieglijke `DONE`). `ERROR` bij elke fout, zonder de module te corrumperen (de toegepaste LIVE-bestanden worden
teruggedraaid vanuit `rollback/<v>/`; niets dat "half toegepast is en erover liegt"). Goedaardige uitgang van de `fetch`-fase: **`DEFERRED`** -
de download werd uitgesteld door `net_policy` (netwerk niet toegestaan); plan/target blijven behouden en het hervat bij de volgende
check/boot (de WebUI toont een blauwe info-toast "waiting for X network", geen fout).

## Strengheidsgaranties

- **FETCH:** gegatet door `net_policy` (any/wifi/mobile; alleen http/https, `file://` nooit) - een niet-toegestaan netwerk ⇒
  `DEFERRED` (hervatbaar), zonder data te besteden. Downloadt alleen wat ontbreekt naar `<sha>.part` (curl met
  `--connect-timeout` + `--speed-time`, hangt nooit), decomprimeert `gz` (toybox `gunzip`), controleert `sha256sum` ==
  manifest, atomische `mv` naar `blobs/<sha>`. Een blob die gecached+ok is, wordt overgeslagen. Het kan de blob seeden vanuit een onveranderd
  lokaal bestand (dedup/offline). **3 fouten op dezelfde blob = de fase breekt af zonder iets toe te passen.** Het
  wordt pas `FETCHED` met ALLE blobs van het plan aanwezig+geverifieerd.
- **APPLY** (alleen vanuit `FETCHED`): `live`/`soft` → backup naar `rollback/<v>/` → `.vdlu-tmp` → `chmod` → verify →
  atomische `rename`. `reboot` → materialiseert naar `staged/<path>.vdlu-new` (raakt de live inode NIET aan).
  `delete[]` → backup → verwijderen. Idempotent (een bestand dat al op de doelhash staat, wordt overgeslagen).
- **COMMIT:** her-hash van elke `live`/`soft`; pas dan schrijft het `current.json`. Met gestagede bestanden ⇒
  `PENDING_REBOOT`. `boot` doet `mv -f staged/....vdlu-new $MODULE_DIR/<path>` (pre-zygote) + herverifieert +
  `DONE`.
- **cancel:** gecontroleerd tussen bestanden (veilig punt); verwijdert de lopende `.vdlu-tmp`/`.part`, wist `cancel`,
  laat het journal hervatbaar (`cancelled:true`, `error:null`).
- **mkdir-lock `$VDLU_DIR/lock.d`** serialiseert (flock is onwerkbaar op toybox; stale-recovery via PID). De
  GEDULDIGE boot-retry houdt de lock niet vast tijdens het wachten (`acquire_lock_try`+release tussen pogingen) noch een
  wakelock - batterijveilig. Een crash/netwerk/reboot halverwege → `resume`/`boot` gaat door.
- **profile=hardened** ⇒ `vdlu-verify` verplicht op het manifest VÓÓR gebruik; falen = afbreken; downgrade geblokkeerd
  (monotone versie). **trusted** ⇒ verify is best-effort, maar de hash van elke blob wordt ALTIJD gecontroleerd.
- **Allowlist voor module-update-sleutel (beide profiles):** `verify_manifest` weigert, fail-closed, elk manifest waarvan de `key_id` niet in de geconfigureerde `key_id`-allowlist staat (zie INTERFACES §5/§6) VOORDAT de pubkey wordt geselecteerd, zodat een sleutel van lager vertrouwen die slechts in de keyring zit (bijv. een fingerprint-feed-sleutel) nooit een flashless root-update kan tekenen. Standaardveilig wanneer niet ingesteld: keyring met één sleutel = alleen die ene sleutel; keyring met meerdere sleutels = geweigerd tot `key_id` is vastgepind.
- Degradeert gracieus: ontbrekende binary / netwerk plat / schijf vol → een duidelijke fout op stderr + `state:ERROR` in
  het journal, zonder de module te corrumperen.

## JSON-parsing zonder jq

Een gron-achtige flattener in `awk` (pure POSIX: `substr`/`index`/`gsub`/`split`/`printf` + locals doorgegeven als
parameters) tokeniseert het manifest teken voor teken en zendt één `path<TAB>value`-regel uit per scalair blad
(`files/0/sha256<TAB>ab..`, `version<TAB>6`, `delete/0<TAB>etc/x`). Robuust tegen compacte OF pretty-printed
JSON. De `sh` consumeert het met `grep`/`cut`; het plan per bestand wordt heropgebouwd in een 2e `awk` tot TSV
(`class st mode enc sha size path`), dat `$VDLU_DIR/plan.tsv` wordt.

## Toestandsbestanden (in `$VDLU_DIR`, Tier-2)

| bestand | rol |
|---|---|
| `config` | key=value (`source`/`profile`/`channel`/`net_policy`/`key_id`/`boot_retry_*`/…; zie INTERFACES §5) |
| `current.json` | manifest van de ACTIEVE versie (diff-basis); afwezig = nooit geüpdatet |
| `target.json` | vastgepind manifest van de lopende transactie (aanwezigheid = actieve transactie); wordt `current.json` bij `DONE` |
| `plan.tsv` / `plan.del` | plan + voortgang per bestand (st) / te verwijderen paden |
| `journal.json` | voortgang voor de WebUI (bij elke overgang opnieuw gegenereerd) |
| `blobs/<sha256>` | cache van geverifieerde originele inhoud |
| `rollback/<version>/<path>` | backup van overschreven bestanden (undo; bewaart de laatste 3) |
| `staged/<path>.vdlu-new` | REBOOT-hard die wacht op swap bij boot |
| `lock.d/` | mkdir-lock (flock onwerkbaar op toybox; stale-recovery via PID) |
| `tools/<abi>/curl` | opgehaalde statische curl (slanke bootstrap); blijft behouden over updates heen |
| `cancel` | cancel-verzoek |

<!-- doc-footer -->

---

> _Deze documentatie is gegenereerd met Claude (Anthropic) en wordt onderhouden door VD171. Correcties en verbeteringen zijn welkom; zie [CONTRIBUTING.md](CONTRIBUTING.md)._
