# Architecture

VDLU has two sides joined by one thing in the middle. On the PC, the [[Producer]] turns a module tree into a signed, content-addressed feed. On the device, the [[Engine]] reads that feed, works out what changed, and applies it. The seam between them is the **signed manifest plus the blob store** (the [[Feed Format]]). Nothing else crosses the gap.

```
        PC / release host                                device
  +--------------------------+                 +---------------------------+
  |  Producer                |                 |  Engine  (update.sh)      |
  |  vdlu-pack  -> manifest  |    signed       |  POSIX sh, no jq          |
  |  vdlu-sign  -> sig       |    feed         |  DIFF FETCH APPLY COMMIT  |
  |  vdlu-gc    -> prune     | =============>  |  journal + rollback       |
  +--------------------------+   manifest.json |  ed25519-mini verify      |
                                 blobs/<sha>   +-------------+-------------+
                                                             |
                                                       +-----v------+
                                                       |  WebUI     |
                                                       |  Updates   |
                                                       |  panel     |
                                                       +------------+
```

The two sides never share a runtime. The Producer uses `python3` and `openssl`; the Engine is pure POSIX `sh` with toybox and an embedded `ed25519-mini`. They agree only because both derive the **same canonical bytes** from a manifest (see [[Security and Trust Model]]). The WebUI is a thin, vanilla-JS panel that drives the engine over the root-manager bridge and reads its progress journal; it holds no update logic of its own. See [[WebUI]].

## The two sides

| Side | Runs on | Built from | Job |
|---|---|---|---|
| [[Producer]] | PC / CI | `python3` + `sh` + `openssl` | Walk the module tree into `manifest.json` + `blobs/`, sign it, prune orphans |
| [[Engine]] | device | POSIX `sh` + toybox + `ed25519-mini` | Diff the installed tree against the feed, fetch deltas, apply, commit |
| [[WebUI]] | device (webview) | vanilla JS/CSS | Trigger updates, show progress, edit config, show the reboot banner |

## The update pipeline

Every update is one transaction, run in a fixed order:

```
  DIFF  ------>  FETCH  ------>  APPLY  ------>  COMMIT
  read feed      download        write live     re-hash all,
  + validate     only missing    files now,      promote target
  + plan         blobs, verify   stage reboot     -> current,
  (no changes)   each sha256     ones             DONE or
                                                  PENDING_REBOOT
```

- **DIFF** (`update.sh check` is this phase, read-only). The engine downloads just the manifest, runs `validate_plan()` over every field **before** touching anything, then compares the feed against `current.json` to build a per-file plan. It changes nothing on disk. A device ahead of the feed is a benign "ahead" result, not an error.
- **FETCH.** Downloads only the blobs the plan is missing, into `<sha>.part`, decompresses `gz`, checks `sha256sum` against the manifest, and atomically `mv`s each verified blob into the cache. A blob already cached (or seeded from an unchanged local file) is skipped, so a revert or a shared file costs nothing. Three failures on one blob abort the phase without applying anything. A download blocked by the network policy exits as `DEFERRED` (resumable), not an error.
- **APPLY.** Ordinary (`live` / `soft`) files are written now: back up to `rollback/<v>/`, write a `.vdlu-tmp`, `chmod`, verify, then atomic `rename` over the target. Reboot-class files are materialized into `staged/<path>.vdlu-new` and the live inode is left untouched. A `delete[]` entry is backed up, then removed. Every step is idempotent: a file already at the target hash is skipped.
- **COMMIT.** Re-hash every live file; only if everything matches does the engine promote `target.json` to `current.json`. If anything was staged, the transaction ends in `PENDING_REBOOT`; otherwise `DONE`.

## Content-addressed manifest and blobs

The feed is content-addressed: the manifest lists the **complete** target tree, each file carried by its `sha256`, and the blob store holds one copy of each distinct content under `blobs/<sha256>` (or `blobs/<sha256>.gz`).

- **Dedup.** Identical content anywhere in the tree, or across releases, is one blob. Publishing is incremental: a blob whose `sha256` already exists on the host is never re-pushed, and the device never re-fetches content it already has.
- **sha256 is of the original.** The hash always names the uncompressed content; `enc` (`raw` or `gz`) only records how that one blob happens to be stored. The device decompresses `gz` with toybox `gunzip`, so no extra compressor is bundled.
- **Flavor-stable.** Because the device diffs against what is actually installed, the feed can carry a whole module family; each install pulls only the blobs that complete its own flavor.

Full field-by-field layout is in [[Feed Format]].

## The resumable journal

Every transaction is crash-safe because its progress lives in a journal (`journal.json`), and the pinned target of the in-flight transaction lives in `target.json`. The state machine runs in a fixed order:

```
PLANNED -> FETCHING -> FETCHED -> APPLYING -> APPLIED_LIVE -> ( PENDING_REBOOT | DONE )
                                                               \-> ERROR / DEFERRED
```

| State | Meaning |
|---|---|
| `PLANNED` | Plan built, nothing fetched yet |
| `FETCHING` / `FETCHED` | Downloading blobs / all blobs present and verified |
| `APPLYING` / `APPLIED_LIVE` | Writing files / all live files written |
| `PENDING_REBOOT` | A reboot-class file is staged, waiting for the boot swap |
| `DONE` | Re-hash of everything matched; `current.json` promoted |
| `ERROR` | Hard failure; module left uncorrupted, live files reverted from `rollback/` |
| `DEFERRED` | Download held back by the network policy; plan persists, resumes later |

`DONE` is reached **only** once a re-hash of everything matches, so the journal never claims a half-applied update is complete. A crash, a dropped network, or a reboot mid-way leaves a resumable journal; `update.sh resume` (or `boot`) picks up from the current phase. See [[Engine]] for the command set and the on-device state files.

## Atomicity and rollback

Nothing is ever overwritten in place and nothing is lost:

- **Atomic writes.** Each file lands via a temp (`.vdlu-tmp`) and an atomic `rename` / `mv`, so a reader never sees a half-written file.
- **Backup before overwrite.** The previous content goes to `rollback/<version>/<path>` before the new file is renamed over it (the last few versions are kept). If an apply fails, the live files are reverted from the rollback copy rather than left corrupted. A failed backup **aborts** the apply instead of overwriting without a safety net.
- **Serialized.** An `mkdir`-based lock (`lock.d/`, since `flock` is unworkable on toybox, with stale recovery by PID) serializes concurrent runs.

## The reboot-free principle

Most files can be swapped while the module is live, so VDLU applies them immediately. Only three classes need a reboot, because a live process has already mapped them: a `.so` (loaded by Zygisk), a `/system` overlay, and an `sepolicy.rule`. Those are **staged, never written over a live inode**, and swapped in one pre-zygote step on the next boot. The full taxonomy and the boot flow are in [[Reboot Handling]].

## The fail-closed trust posture

The feed is the only thing that crosses from the PC to the device, so the engine treats every byte of it as hostile. `validate_plan()` runs in the DIFF phase, before any download, and rejects the entire manifest on any malformed field. Signature verification uses an embedded `ed25519-mini` (no `openssl` on the device), the private key never touches a device or CI, and the `hardened` profile is fail-closed by inversion so a corrupted profile value can never silently accept an unsigned feed. The full model, the two profiles, and the threats each one answers are in [[Security and Trust Model]].
