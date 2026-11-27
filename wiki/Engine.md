# Engine

The engine is the device side of VDLU: the part that runs on the phone, decides what changed, downloads it, and applies it. It is a single POSIX shell script, `engine/update.sh`, plus a tiny signature checker, `engine/vdlu-verify`. Both are vendored into the host module at `<module>/vdlu/` and run by root.

The whole engine is built around one idea: an update is a **resumable transaction**. If the phone is rebooted, killed, or loses network halfway through, the next run picks up exactly where it stopped, and the module is never left half-applied while pretending to be done.

If you want the big picture first, see [[Architecture]]. For how updates avoid a reboot whenever they can, see [[Reboot Handling]].

## Written for the device, not for your laptop

`update.sh` is pure POSIX `sh`. It runs under mksh, busybox, or toybox, with no bash-only features, and it passes `sh -n`. That matters because the environment on a rooted Android device is small and strict.

In particular, there is no `jq`. VDLU parses `manifest.json` with a small gron-style flattener written in `awk`: it walks the JSON one character at a time and emits one `path<TAB>value` line per leaf (for example `files/0/sha256<TAB>ab..` or `version<TAB>6`). The shell then reads those lines with `grep` and `cut`. This works on both compact and pretty-printed JSON, and it never shells out to a JSON tool that is not there.

The engine depends only on what toybox already ships (`sha256sum`, `gzip`/`gunzip`, `base64`, `date`), the embedded `ed25519-mini` verifier, and, for `https://` feeds, a small static `curl` that is fetched and verified once. A `file://` feed needs no `curl` at all.

## The six commands

You invoke the engine with the module's paths in the environment and one command:

```sh
VDLU_DIR=/data/adb/<mod>/vdlu MODULE_DIR=/data/adb/modules/<mod> MODID=<mod> \
  sh "$MODULE_DIR/vdlu/update.sh" <cmd>
```

Exit code `0` means success; any other code means an error, with the reason printed to stderr.

| Command | What it does |
|---|---|
| `check` | Read-only diff. Downloads the manifest, compares it to what is installed, and prints a one-line JSON summary: `{"update":bool,"from":N,"to":M,"fetch":K,"reboot":bool}`. Changes nothing on disk. If the device is newer than the feed (a blocked downgrade) it reports `{"update":false,"ahead":true,...}` with exit `0`, not an error. |
| `run` | The full live cycle: DIFF, FETCH, APPLY, COMMIT. Applies every live file immediately and stages the few reboot-class files. Honors `cancel`. Writes progress to `journal.json`. |
| `resume` | Continues a transaction that was interrupted, starting from whatever phase it was in. Idempotent. It does **not** swap a staged `.so` (that is reserved for `boot`). |
| `boot` | The pre-zygote path. Does a `resume` and then swaps any staged `*.vdlu-new` files into place, closing `PENDING_REBOOT` to `DONE`. If there is no pending transaction, it runs a fresh cycle and applies everything, including the `.so`, in that single boot. |
| `status` | Prints `journal.json`, or `{"state":"idle"}` when there is nothing in flight. |
| `cancel` | Creates a `cancel` marker. A `run` in progress stops cleanly at the next safe point. |

The `check` command is deliberately cheap, so the UI can tell you an update exists on any network. The actual download is gated separately (see the fetch phase below).

## The transaction, step by step

Every `run` moves through a fixed state machine, recorded in `journal.json` so the WebUI (and you) can watch it:

```
PLANNED -> FETCHING -> FETCHED -> APPLYING -> APPLIED_LIVE -> (PENDING_REBOOT | DONE)
```

**DIFF.** The engine fetches `manifest.json`, validates every field (see below and [[Security and Trust Model]]), and diffs the signed target tree against `current.json`, the manifest of the version already installed. The result is a per-file plan written to `plan.tsv`: one row per file, carrying its class, target hash, mode, and progress state. Files already at the target hash are marked to skip.

**FETCH.** For each file still needed, the engine downloads its content-addressed blob from `<source>/blobs/<sha>` (or `<sha>.gz` when compressed), into a `.part` file. If the blob is gzipped it is decompressed, then its SHA-256 is checked against the manifest. Only on a match is it atomically `mv`-ed into `blobs/<sha>`. A blob already cached with a correct hash is skipped entirely, and an unchanged local file can seed the cache without any download. Three failures on the same blob abort the phase with nothing applied. The phase reaches `FETCHED` only once every blob in the plan is present and verified. For the [[Feed Format]] these blobs come from, see that page. At toolchain setup the engine logs the resolved TLS trust - the CA path and whether it is readable, plus the bundle's size and certificate count - so a boot-time curl `rc 77` is self-explaining in `boot.log` (it distinguishes an empty trust store from an unreadable one, the boot SELinux-context case).

The fetch is gated by network policy: a feed may be restricted to Wi-Fi only, mobile only, or any network. When the current network is not allowed, the fetch does not fail; it enters the benign `DEFERRED` state, keeps the plan and target pinned, and resumes on the next check or boot once the right network appears. No data is spent in the meantime.

**APPLY.** Only ever entered from `FETCHED`. For each file the engine acts by class:

- `live` and `soft` files: back up the current file to `rollback/<version>/<path>`, write the new content to a `.vdlu-tmp` sibling, `chmod` it, verify its hash, then atomically `rename` it over the target. A file already at the target hash is skipped.
- `reboot` files (a `.so`, a `/system` overlay, an `sepolicy.rule`): materialize into `staged/<path>.vdlu-new`. The live inode is never touched here. See [[Reboot Handling]].
- deletions: back up, then remove. Deletions are applied only at the very end, on a clean `DONE`, never while a reboot is still pending.

**COMMIT.** The engine re-hashes every live and soft file it touched. Only when all of them match does it write `current.json`, making the new version the diff base. If any reboot-class file was staged, the state becomes `PENDING_REBOOT` instead of `DONE`; the swap and the final re-verify happen later under the `boot` command.

## Fail-safe by construction

The guarantees that make this safe to run unattended:

- **Nothing is marked `DONE` without a matching re-hash.** `DONE` is reached only after every applied file has been read back and its SHA-256 compared to the manifest. A staged reboot file forces `PENDING_REBOOT`, never a bogus `DONE`.
- **Nothing is lost.** Every file is backed up to `rollback/<version>/` before it is overwritten, and the last three versions are kept. If an apply fails, the live files are reverted from the backup; the module is never left half-applied lying about it. `apply_live` aborts outright if the backup step fails, rather than overwrite with no way back.
- **Everything is atomic.** New content lands via `rename`/`mv` over the target, so a reader ever sees either the old file or the new one, never a truncated write.
- **Resumable after a crash or kill.** A crash, a lost network, or a reboot mid-way leaves a valid journal; `resume` (or `boot`) continues from the recorded phase. The design assumes it will be interrupted.
- **Degrades cleanly.** A missing binary, a down network, or a full disk produces a clear error on stderr and `state:ERROR` in the journal, without corrupting the module.
- **The trust anchor is excluded (`ENGINE_VERSION` 5).** The engine ignores every `vdlu/` path in a fetched plan - its own `update.sh`, `vdlu-verify`, the `verify/` binaries, the keyring and the config - so a feed can never swap the verifier or the signing key over the wire; the anchor changes only by a full signed re-flash. See [[Security and Trust Model]].
- **An update defers while the module is busy.** With the opt-in `apply_busy_file` set to an absolute path the host module touches during its own operations (for example a running backup), APPLY waits while that path exists, so files are never swapped mid-operation; the blobs are already fetched, so the next trigger applies with no re-download.
- **Size ceilings.** A file is capped at **128 MiB** and the manifest at **2 MiB**, enforced before either is read in both `update.sh` and `vdlu-verify` (anti decompression-bomb / anti-OOM).
- **A module ahead of the feed is never reverted (`ENGINE_VERSION` 7).** The live installed `versionCode`, read from the module's own `module.prop`, floors the "from" version, so a device manually updated past a stale feed reads as *ahead*: the downgrade guard returns benign, with no plan and no revert. `boot` also self-heals an existing install - a persisted plan whose target is below the installed version, or a stale `target <= 0` journal (`ENGINE_VERSION` 6), is cleared before any resume.

## The lock

Only one transaction may touch the state at a time. `flock` is not reliable on toybox, so VDLU serializes with a directory lock: `mkdir "$VDLU_DIR/lock.d"` succeeds for exactly one caller and fails for the rest, which is atomic on any sane filesystem. A stale lock left by a dead process is recovered by checking the recorded PID.

The patient boot-time retry (used when the device is offline at boot) does **not** hold this lock while it waits. It acquires and releases between attempts, so a manual `run` is never blocked by a boot that is waiting for the network, and it never holds a wakelock. Battery-safe by design. More on that in [[Reboot Handling]].

## Signature checking: `vdlu-verify`

`vdlu-verify` is the on-device signature checker, kept deliberately slim:

```
vdlu-verify <manifest.json> <keyring_dir>
```

Exit `0` means the manifest's signature is valid against the keyring public key whose id matches the manifest's `key_id`; any other code is a rejection.

What makes it slim is that it uses **no `openssl` on the device**. It reads the keyring public key as a **raw 32-byte** file, canonicalizes the manifest (the manifest text with the `sig` field removed), hashes it with toybox `sha256sum`, base64-decodes the signature, and hands the raw key, message, and 64-byte signature to the embedded `ed25519-mini` binary. The checker also refuses anything malformed before it ever verifies: a missing or empty `key_id` or `sig`, a `key_id` containing path separators, a public key that is not exactly 32 bytes, or a signature that is not exactly 64 bytes.

Before it selects a key at all, the engine enforces a **`key_id` allowlist**: the manifest's `key_id` must be one the config allows to sign a *module update*, and a key that is merely present in the keyring but not allowlisted is rejected before its pubkey is ever loaded. A single-key keyring auto-pins that one key with no config; a multi-key keyring must pin `key_id` or the engine fails closed. The allowed set is passed down to `vdlu-verify` as `VDLU_KEYID_ALLOW`, and it applies in both profiles. This stops a lower-trust key, such as a fingerprint-feed key sharing the keyring, from signing a full root update; the separate fingerprint feed keeps its own pinned key, `FEED_KEY_ID`. The full story is in [[Security and Trust Model]].

The canonicalization is byte-for-byte identical to the producer's signer, which is what makes a signature verify across tools. The matching private key never touches a device or CI; only the raw public key is embedded. The full trust story, the two profiles, and why `hardened` is fail-closed by inversion are in [[Security and Trust Model]].

The engine calls `vdlu-verify` during the diff phase. Under the `hardened` profile a failed verification aborts the whole update; under `trusted` verification is best-effort, but every blob's hash is still always checked, so corrupted content is caught regardless of profile.

## State on disk

All of the engine's state lives in `$VDLU_DIR` (outside the module directory), so the module tree itself only ever holds finished files:

| Path | Role |
|---|---|
| `config` | key=value settings (source, profile, channel, network policy, boot retry) |
| `current.json` | manifest of the active version; this is the diff base. Absent means never updated |
| `target.json` | the pinned manifest of the in-flight transaction. Its presence marks an active transaction; it becomes `current.json` on `DONE` |
| `plan.tsv` / `plan.del` | the per-file plan and progress, and the list of paths to delete |
| `journal.json` | progress for the WebUI, rewritten on every state change |
| `blobs/<sha256>` | cache of verified, decompressed original content |
| `rollback/<version>/<path>` | backups of overwritten files; the last three versions are kept |
| `staged/<path>.vdlu-new` | a reboot-class file waiting for the boot swap |
| `lock.d/` | the mkdir lock |
| `tools/<abi>/curl` | the fetched, verified static curl; persists across updates |
| `cancel` | a cancel request |

## See also

- [[Reboot Handling]]: how the class system keeps most updates reboot-free, and how a staged `.so` is swapped pre-zygote.
- [[Security and Trust Model]]: the two profiles, fail-closed validation, and the raw-key ed25519 chain.
- [[Feed Format]]: the manifest and content-addressed blobs the engine consumes.
- [[Architecture]]: how the engine, producer, and WebUI fit together.
