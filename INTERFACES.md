# VDLU - Interface contract (the seam between the components)

**Law of convergence:** every component conforms to this file. The pieces from 4 agents have to **fit together** - the
CLI signatures, file names and JSON keys below are **immutable** (a change means aligning here first).

Principles inherited from the repos: **pure POSIX sh** on the device (no bashisms; runs with toybox/busybox +
toybox's `sha256sum`/`gzip`/`base64` + the fetched `curl` + the embedded `ed25519-mini` - slim, no bin
bundle), **zero gratuitous comments**, **always release**, **rigor on failure** (resumable transaction, nothing
bogusly "done", nothing lost), **nothing loosened**.

---

## 1. State layout (Tier-2, outside the module dir)

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
`cancelled:true` in the journal = the engine stopped on a cancel (a non-terminal, resumable state; `error`
stays null).

Engine vendored in the module: `$MODULE_DIR/vdlu/update.sh` (+ `vdlu-verify`). `$MODULE_DIR =
/data/adb/modules/<module>`. The engine receives via env: `VDLU_DIR`, `MODULE_DIR`, `MODID`.

## 2. Engine CLI (ENGINE component)

`sh update.sh <cmd>` - rc 0 = ok, !=0 = error (stderr has the reason):

| cmd | does |
|---|---|
| `check` | DIFF: downloads the manifest, compares; prints a 1-line JSON `{"update":bool,"from":N,"to":M,"fetch":K,"reboot":bool}`; changes nothing. Device AHEAD of the feed (downgrade blocked, hardened) = a BENIGN state: `{"update":false,"ahead":true,"from":N,"to":M}` + rc0 (never "check failed"). do_diff rc: 2 fetch/parse, 3 verify/meta, 4 ahead |
| `run` | full cycle: DIFF→FETCH→APPLY→COMMIT; honors `cancel`; writes progress to `journal.json`; applies LIVE, stages REBOOT-hard |
| `resume` | resumes the `journal.json` transaction from the current phase (idempotent) |
| `boot` | pre-zygote mode: `resume` + does the SWAP of the `staged/*.vdlu-new` (applies the `.so`), closes `PENDING_REBOOT`→`DONE` |
| `status` | prints `journal.json` (or `{"state":"idle"}`) |
| `cancel` | creates `$VDLU_DIR/cancel` (a `run` in progress stops at the next safe point) |

Blob/manifest source: `source` from the config. `<source>` + `/manifest.json`, `/blobs/<sha>`, `/blobs/<sha>.gz`.
`source` begins with `https://` (static curl fetched, TLS) or `file://` (local staging).

## 3. manifest.json (produced by the PRODUCER, consumed by the ENGINE)

```json
{ "schema":1, "module":"<id>", "version":<int>, "version_name":"<str>", "built":"<ISO8601>",
  "engine_min":3, "key_id":"<str>", "channel":"stable",
  "files":[ {"path":"webroot/index.html","sha256":"<hex64>","size":<int>,"mode":"0644","enc":"raw|gz","class":"live|soft|reboot"} ],
  "delete":["<path>"], "sig":"<base64>" }
```

- `files[]` = the COMPLETE target tree. `class`: `live` (webroot/bin/lib/confs/scripts-on-demand/module.prop) ·
  `soft` (service.sh/post-fs-data.sh/boot-completed.sh) · `reboot` (`zygisk/**/*.so`, `system/**`, `*.rule`).
  Default by path; never downgrades `reboot`→`live`.
- `enc`: `gz` (gzip `-9 -n`, deterministic; toybox gunzip on the device) only when it compresses well AND the
  size is significant; `sha256` is ALWAYS of the original content.
- `sig`: signature of the canonical manifest WITHOUT the `sig` field (§4 of verify).

## 4. journal.json (ENGINE writes, WEBUI reads - the progress contract)

```json
{ "schema":1, "module":"<id>", "target":<version>, "from":<version>,
  "phase":"diff|fetch|apply|commit", "state":"PLANNED|FETCHING|FETCHED|APPLYING|APPLIED_LIVE|PENDING_REBOOT|DONE|ERROR|DEFERRED",
  "total":<int>, "done":<int>, "current":"<path>", "bytes":<int>, "reboot_pending":bool,
  "cancelled":bool, "error":"<str|null>", "updated":"<ISO8601>",
  "items":[ {"path":"<p>","sha256":"<h>","class":"<c>","st":"pending|fetched|applied|staged|skipped"} ] }
```

State machine (fixed order): `PLANNED→FETCHING→FETCHED→APPLYING→APPLIED_LIVE→(PENDING_REBOOT|DONE)`.
`DONE` only once a re-hash of EVERYTHING matches. A staged REBOOT-hard ⇒ `PENDING_REBOOT` (not `DONE`). Exits
from the `fetch` phase: `ERROR` (hard failure) or `DEFERRED` (net_policy blocked the download - benign/resumable,
not an error).

## 5. config (key=value, one per line; editable in the WEBUI)

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

**Boot retry (offline) - PATIENT, battery-safe:** only at `boot` (never on check/auto-open). If the manifest
fetch fails due to NETWORK (`fetch_offline` classifies by the fetcher's exit), it waits and retries until
success OR `boot_retry_minutes` of AWAKE-time is exhausted. A design that **holds nothing and does not drain**:
- **Zero wakelock:** between tries it is `sleep`, which freezes in deep-sleep → the device sleeps normally
  (~zero battery); the retry pauses and resumes once the device is already awake.
- **Zero held lock:** `acquire_lock_try`+release BETWEEN tries (does not hold the lock while waiting) →
  `run`/manual check never block; if a manual run stages a TARGET in the meantime, the boot defers.
- **Does not wake the radio for nothing:** a `net_allowed` probe (via `net_type`/`ip route get`, a kernel route
  lookup that respects Android's policy-routing; no packet) gates each try - it only spends a fetch once the
  network has appeared.
- NEVER retries a deterministic failure (manifest/sig/downgrade). `--connect-timeout 15` on the fetch (does not
  hang on a captive portal). `service.sh` backgrounds it (boot never hangs).
- ⛔ **HARD: turning on `boot_retry_minutes>0` requires the PATIENT engine** (the one with
  `net_allowed`+`acquire_lock_try`, canonical `da7115f4`+). The PREVIOUS boot-retry (holds the lock the whole
  window + retries blind curl offline) **DRAINS the battery/wakes the radio** - turning the retry on in an old
  engine is a footgun. When enabling it, vendor the current engine.

**`net_policy` (any|wifi|mobile):** gates the **DOWNLOAD** by network type. `net_type()` classifies the egress
of `ip route get` (cellular iface `rmnet/ccmni/v4-*/clat` = mobile; everything else = wifi; kernel lookup, no
packet). `net_allowed()` compares against `net_policy` and gates `do_fetch` (blobs) + the patient boot-retry
probe. The **manifest check stays free** (tiny → the UI reports an update on any network); only the download
waits for the allowed network. A download on a non-allowed network = the **`DEFERRED`** state in the journal
(NOT ERROR; a gentle blue INFO toast "waiting for X network"; plan/target persist, it resumes on the next
check/boot on the right network). `net_policy` **supersedes** `allow_metered` (which was never consumed).
Engine `97baf887`+ (`file://` is never gated).

## 6. Signature (PRODUCER signs on the PC via openssl; ENGINE verifies on the device via ed25519-mini)

- Canonicalization: the manifest WITHOUT `sig`, keys sorted, compact JSON (no superfluous spaces), UTF-8.
  What is signed/verified = the `sha256` hex of that canonical form (gives cross-tool determinism).
- `producer/vdlu-sign <manifest.json> <privkey.pem> <key_id>` → injects `key_id` + `sig` (base64 of the ed25519 signature of the canonical sha256) into the manifest, in place.
- `engine/vdlu-verify <manifest.json> <keyring_dir>` → rc 0 if the `sig` matches the `<key_id>.pub` pubkey in
  the keyring (SLIM: pubkey **RAW 32 bytes**). Internally, no openssl: toybox `sha256sum`/`base64 -d` + the
  embedded `ed25519-mini` binary (CLI `ed25519-mini <pub32> <msg> <sig64>`, rc 0=valid/1=invalid/2=usage).
  rc!=0 = reject. **`profile=hardened` ⇒ verify mandatory; failure = abort.**
  `profile=trusted` ⇒ verify is best-effort (source already trusted via SSH), but every blob's hash is ALWAYS checked.
- `producer/vdlu-keygen <id> <out>` → generates `<id>.pem` (priv) + `<id>.pub` (PEM, for tooling on the PC) +
  `<id>.pub.raw` (**RAW 32B** = the `<id>.pub` of the slim keyring on the device). openssl `genpkey -algorithm ed25519`.

## 7. Blob - verification (ENGINE)

Downloads `<source>/blobs/<sha>` (or `.gz` if `enc=gz`), writes `.part`, if `gz` decompresses (`gunzip`),
checks `sha256sum` == the manifest's `sha256`; match → atomic `mv` to `$VDLU_DIR/blobs/<sha>`. 3 failures on
the same blob = aborts the phase (nothing applied). A blob already in `$VDLU_DIR/blobs/<sha>` with an ok hash =
skips the download.

## 8. APPLY by class (ENGINE)

- `live`/`soft`: backup `rollback/<v>/<path>` → writes `$MODULE_DIR/<path>.vdlu-tmp` from the blob → `chmod mode` →
  atomic `rename` over the target. Already at the target hash = skip. (In the Zygisk variant the write goes to
  the mounted dir = per-file merge, never `rm -rf` of the dir.)
- `reboot`: materializes into `$VDLU_DIR/staged/<path>.vdlu-new` (does NOT touch the live one). The swap is at `boot`.
- `delete[]`: backup → remove.

## 9. WEBUI ↔ ENGINE (WEBUI component)

- Fires: `ksu.exec("sh $MODULE_DIR/vdlu/update.sh run")` (background).
- Progress: a light poll `ksu.exec("cat $VDLU_DIR/journal.json")` every ~1s; renders `{phase,state,total,done,current,bytes}`.
- Liveness: journal absent for 8 ticks ⇒ "no response". Journal FROZEN (same values) for 20 ticks ⇒ checks `lock.d`: alive = carries on (slow fetch of 1 blob), dead = error + Resume. Without this, a run that died mid-fetch would freeze the toast at "updating".
- Cancel: `ksu.exec("touch $VDLU_DIR/cancel")`.
- Config: reads/writes `$VDLU_DIR/config` (key=value) in an "Updates" tab.
- Toast: bar + `phase done/total · current`; on finish with `reboot_pending` ⇒ a persistent banner "reboot to activate the .so".
- Auto-open (`auto_on_webui_open=1`): does a QUIET `check()` first (no progress toast); only fires the `run`+persistent toast if `update && fetch>0`. Up-to-date/ahead/nothing-new = an inline result in the panel, zero leftover toast. Non-intrusive like the manual button (the toast only appears when there is a real download). The curl bootstrap is one-time.

## 10. Integration into the demo (INTEGRATION component) - SNIPPETS, do not edit the live files

Produces, in `integration/demo/`, snippets + an `INTEGRATION.md` saying where each one goes (without applying):
- the `auto_on_reboot` hook in `post-fs-data`/`service.sh` (pre-zygote → `update.sh boot`) and `auto_on_webui_open`.
- the `config` defaults + the embedded keyring + the vendoring (`modules/<mod>/vdlu/`).
- the PARTIAL variant (merge into the mounted dir).

## 11. Fetched toolchain + baseline (SLIM, Approach B)

**Layout in the module (zip):** `vdlu/{update.sh, vdlu-verify, config.default, keyring/<id>.pub (RAW 32B),
verify/<abi>/ed25519-mini, baseline.json}`. **NO** `bin/` (openssl/curl/zstd). `customize.sh` can prune
`verify/` down to the device's ABI (`vdlu-verify` finds the mini at `<dir>/ed25519-mini` OR `<dir>/verify/<abi>/ed25519-mini`).

**ed25519-mini** (embedded binary, verify-only): `ed25519-mini <pubkey32> <msg> <sig64>` → rc 0=valid,
1=invalid, 2=usage/IO. msg = the exact signed bytes (does NOT re-hash). TweetNaCl PD, static per-ABI, PROVENANCE.

**tools-feed** (public/https profile only): served at `<tools_source>` (default derived: swaps the last segment
of `source` for `vdlu-tools`, e.g. `https://<user>.github.io/<repo>/vdlu-tools`). Contains:
- `tools-manifest.json` - a SIGNED `vdlu-pack` manifest over the `<abi>/curl` tree, pinning the `sha256` of
  each curl (same `release-2026` key).
- `<abi>/curl` - the RAW **static** curl (self-contained, ~1MB; curl 8.11.1 + mbedTLS). 🪤 mbedTLS does NOT
  carry a CA bundle: `fetch_url` passes `--capath` (auto-detect of the Android trust store: `/system/etc/security/cacerts`
  → APEX conscrypt; `ca_path` overrides). No capath = error 60. The integrity is the ed25519; the cert-check is defense-in-depth.

**install-tool** (ENGINE): `update.sh install-tool <abi>` reads `$VDLU_DIR/.work/{tools-manifest.json, tool.<abi>}`
(the WEBUI downloads it via `fetch()` and writes it there), **verifies the tools-manifest signature (ed25519-mini,
MANDATORY in any profile)** + the curl's hash == manifest, and only then installs it to `$VDLU_DIR/tools/<abi>/curl` (0755).
The curl runs as root → sig+hash before exec closes the RCE. Persists in Tier-2: never re-downloaded (except on uninstall).

**fetch-bootstrap** (WEBUI, `ensureToolchain()`): runs before check/run/resume. `file://` = no-op; curl ALREADY
available (Tier-2, OR `module/bin/<abi>/curl` from a **self-bundled** module, OR system) = no-op
(VDLU reuses the existing curl); only `https` **with no curl at all** downloads curl + tools-manifest via the webview, writes
them to `.work` (chunked base64 via `ksu.exec`), calls `install-tool`. Trust = the on-device check, not the download.

> 🪤 **Slim (fetch-bootstrap) ≠ mandatory.** A module whose `bin/` exists for ITS OWN features (e.g. it bundles
> restic/rclone/age/tar/curl...) does **not** slim down to ~2MB nor download curl - VDLU adopts the slim engine
> (gz, mini, baseline, fixes) and **reuses** the embedded toolchain. Only modules without their own toolchain
> gain the ~2MB.

**baseline.json** (fix from:0): the release copies the SIGNED `manifest.json` of the shipped version to
`vdlu/baseline.json`; on a fresh install the engine seeds `current.json` from it (`init_paths`, only if absent) → the
device is born "current", with no auto-update of itself and no re-fetch.
