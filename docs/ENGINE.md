> **Languages:** English · [العربية](ar/ENGINE.md) · [Čeština](cs/ENGINE.md) · [Deutsch](de/ENGINE.md) · [Español](es/ENGINE.md) · [فارسی](fa/ENGINE.md) · [Français](fr/ENGINE.md) · [हिन्दी](hi/ENGINE.md) · [Bahasa Indonesia](id/ENGINE.md) · [Italiano](it/ENGINE.md) · [日本語](ja/ENGINE.md) · [한국어](ko/ENGINE.md) · [Nederlands](nl/ENGINE.md) · [Polski](pl/ENGINE.md) · [Português](pt/ENGINE.md) · [Русский](ru/ENGINE.md) · [Svenska](sv/ENGINE.md) · [ไทย](th/ENGINE.md) · [Türkçe](tr/ENGINE.md) · [Українська](uk/ENGINE.md) · [Tiếng Việt](vi/ENGINE.md) · [中文](zh/ENGINE.md)

---

# VDLU engine (`update.sh`)

Flashless, incremental update client for KSU/Magisk modules. Implements the
`DIFF -> FETCH -> APPLY -> COMMIT` cycle as a resumable transaction. Conforms to `INTERFACES.md` (the law
of convergence).

Pure POSIX sh (mksh/busybox/toybox). **SLIM:** it depends only on toybox (`sha256sum`/`gzip`/`base64`/`date`) +
the embedded `ed25519-mini` (ed25519 verify; **no openssl on the device**) + a static `curl` **fetched** on the
first https update (the WebUI does the `fetch()`, persists it in Tier-2, and `install-tool` verifies its
signature+hash BEFORE using it). `file://` needs no curl. Zero dependency on `jq`.

## Invocation

```sh
VDLU_DIR=/data/adb/<mod>/vdlu MODULE_DIR=/data/adb/modules/<mod> MODID=<mod> \
  sh $MODULE_DIR/vdlu/update.sh <cmd>
```

`rc 0` = ok; `rc != 0` = error (reason on stderr). `vdlu-verify` is delivered by another component
(signature in `INTERFACES.md §6`); the engine only calls it.

| cmd | does |
|---|---|
| `check` | read-only DIFF; prints `{"update":bool,"from":N,"to":M,"fetch":K,"reboot":bool}`; changes nothing |
| `run` | full LIVE cycle + stages REBOOT-hard; honors `cancel`; progress in `journal.json` |
| `resume` | resumes the pending transaction (`target.json`) from the current phase; idempotent; does **not** swap the `.so` |
| `boot` | pre-zygote mode: resume **+** swaps the `staged/*.vdlu-new` → closes `PENDING_REBOOT`→`DONE`. With no pending transaction, it runs a fresh cycle and applies everything (including the `.so`) in a single boot |
| `status` | prints `journal.json` (or `{"state":"idle"}`) |
| `cancel` | creates `$VDLU_DIR/cancel`; a `run` in progress stops at the next safe point |

## State machine (journal.json)

```
PLANNED -> FETCHING -> FETCHED -> APPLYING -> APPLIED_LIVE -> (PENDING_REBOOT | DONE)
```

`DONE` only once a re-hash of EVERYTHING matches. If any REBOOT-hard was staged ⇒ `PENDING_REBOOT` (never a
bogus `DONE`). `ERROR` on any failure, without corrupting the module (the applied LIVE files are reverted
from `rollback/<v>/`; nothing "half-applied lying about it"). Benign exit of the `fetch` phase: **`DEFERRED`** -
the download was deferred by `net_policy` (network not allowed); plan/target persist and it resumes on the next
check/boot (the WebUI shows a blue info toast "waiting for X network", not an error).

## Rigor guarantees

- **FETCH:** gated by `net_policy` (any/wifi/mobile; http/https only, `file://` never) - a disallowed network ⇒
  `DEFERRED` (resumable), without spending data. Downloads only what is missing into `<sha>.part` (curl with
  `--connect-timeout` + `--speed-time`, never hangs), decompresses `gz` (toybox `gunzip`), checks `sha256sum` ==
  manifest, atomic `mv` to `blobs/<sha>`. A cached+ok blob is skipped. It can seed the blob from an unchanged
  local file (dedup/offline). **3 failures on the same blob = the phase aborts without applying anything.** It
  only becomes `FETCHED` with ALL the plan's blobs present+verified.
- **APPLY** (only from `FETCHED`): `live`/`soft` → backup to `rollback/<v>/` → `.vdlu-tmp` → `chmod` → verify →
  atomic `rename`. `reboot` → materializes into `staged/<path>.vdlu-new` (does NOT touch the live inode).
  `delete[]` → backup → remove. Idempotent (a file already at the target hash is skipped).
- **COMMIT:** re-hash of every `live`/`soft`; only then does it write `current.json`. With staged files ⇒
  `PENDING_REBOOT`. `boot` does `mv -f staged/....vdlu-new $MODULE_DIR/<path>` (pre-zygote) + re-verifies +
  `DONE`.
- **cancel:** checked between files (safe point); removes the in-flight `.vdlu-tmp`/`.part`, deletes `cancel`,
  leaves the journal resumable (`cancelled:true`, `error:null`).
- **mkdir-lock `$VDLU_DIR/lock.d`** serializes (flock is unworkable on toybox; stale-recovery by PID). The
  PATIENT boot-retry does not hold the lock while waiting (`acquire_lock_try`+release between tries) nor a
  wakelock - battery-safe. A crash/network/reboot mid-way → `resume`/`boot` continues.
- `boot` runs **synchronously** in post-fs-data (pre-zygote, required so the `.so` swap lands before any
  process maps it). The patient boot-retry only engages with a non-file (http) source AND
  `boot_retry_minutes>0` - a latent boot stall exists only in that config.
- **profile=hardened** ⇒ `vdlu-verify` mandatory on the manifest BEFORE use; failure = abort; downgrade blocked
  (monotonic version). **trusted** ⇒ verify is best-effort, but every blob's hash is ALWAYS checked.
- Degrades gracefully: missing binary / network down / disk full → a clear error on stderr + `state:ERROR` in
  the journal, without corrupting the module.

## JSON parsing without jq

A gron-style flattener in `awk` (pure POSIX: `substr`/`index`/`gsub`/`split`/`printf` + locals passed as
parameters) tokenizes the manifest char-by-char and emits one `path<TAB>value` line per scalar leaf
(`files/0/sha256<TAB>ab..`, `version<TAB>6`, `delete/0<TAB>etc/x`). Robust against compact OR pretty-printed
JSON. The `sh` consumes it with `grep`/`cut`; the per-file plan is reassembled in a 2nd `awk` into TSV
(`class st mode enc sha size path`), which becomes `$VDLU_DIR/plan.tsv`.

## State files (in `$VDLU_DIR`, Tier-2)

| file | role |
|---|---|
| `config` | key=value (`source`/`profile`/`channel`/`net_policy`/`boot_retry_*`/…; see INTERFACES §5) |
| `current.json` | manifest of the ACTIVE version (diff base); absent = never updated |
| `target.json` | pinned manifest of the in-flight transaction (presence = active transaction); becomes `current.json` on `DONE` |
| `plan.tsv` / `plan.del` | plan + per-file progress (st) / paths to delete |
| `journal.json` | progress for the WebUI (regenerated on each transition) |
| `blobs/<sha256>` | cache of verified original content |
| `rollback/<version>/<path>` | backup of overwritten files (undo; keeps the last 3) |
| `staged/<path>.vdlu-new` | REBOOT-hard awaiting swap at boot |
| `lock.d/` | mkdir-lock (flock unworkable on toybox; stale-recovery by PID) |
| `tools/<abi>/curl` | fetched static curl (slim bootstrap); persists across updates |
| `cancel` | cancel request |

<!-- doc-footer -->

---

> _This documentation was generated with Claude (Anthropic) and is maintained by VD171. Corrections and improvements are welcome; see [CONTRIBUTING.md](../CONTRIBUTING.md)._
