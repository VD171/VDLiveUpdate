# Changelog

Notable changes to the VDLU engine. Entries track ENGINE_VERSION, the on-device compatibility gate a
signed manifest declares via `engine_min`.

## ENGINE_VERSION 8 - 2026-11-26
- Engine (ABI-aware plan reduction): the feed is packed from the universal-full zip (all 4 ABIs:
  `arm64-v8a`/`armeabi-v7a`/`x86`/`x86_64`), but `customize.sh` prunes every install to the device's SINGLE
  in-use ABI. The diff therefore saw the other 3 ABIs' files as missing and kept re-fetching them (~255 MiB),
  re-bloating the install on every run. The engine now detects the device's single on-device ABI (the one
  `bin/<abi>`, `vdlu/verify/<abi>`, `verify/<abi>`, `lib/<abi>` or `zygisk/<abi>.so` present under `MODULE_DIR`;
  falls back to `getprop ro.product.cpu.abi`) and DROPS other-ABI paths from the plan, mirroring what
  `customize.sh` does at install time.
- HARD invariant: the ABI filter is a plan REDUCTION only (it can never ADD or alter a path) and runs AFTER
  `validate_plan`, so every security check (path containment, 64-hex sha, mode/class/enc, downgrade block,
  signature) already saw the FULL manifest. It cannot hide a malicious update of the device's own-ABI or
  non-ABI files. Fail-SAFE: when the device ABI cannot be detected it drops nothing (behaves as before).
- The feed stays universal-full-packed: NO change to `producer/vdlu-pack`.
- Engine: `ENGINE_VERSION` 7->8. A backward-compatible, fail-safe plan reduction, so manifests keep their
  `engine_min`; the bump keeps the engine version honest per the "any logic change bumps" rule.
- WebUI widget (`vdlu.js`): the update bar (reboot banner) gains a persistent "x" dismissal (localStorage,
  per-module, keyed by target version - a later version re-shows it) and a `silent_update` config toggle in the
  Updates panel that suppresses the bar entirely (the update still applies in the background). Prose: the
  `deferredSub` string now uses a comma clause separator instead of " - ".

## ENGINE_VERSION 7 - 2026-11-25
- Fix (never revert a module ahead of the feed): the engine derived the "from" version ONLY from
  `current.json`, never from the installed module. When the feed was stale at an old version and the user had
  manually updated the module past it via the root manager, boot saw the live files differ from the old
  manifest and REVERTED the module back to the stale version (and it survived reinstall, because `current.json`
  persists). The live installed `versionCode` (from the module's own `module.prop`, local trusted device state)
  now FLOORS `FROMVER`, so a module ahead of the feed reads as AHEAD - the existing downgrade guard returns
  benign (no plan, no revert). Forward updates (feed newer than installed) proceed unchanged.
- Engine (`update.sh`): `boot` self-heals existing installs - a persisted plan whose `target` version is below
  the live installed module would downgrade it; it is cleared before any resume (reusing the v6 stale-journal
  self-heal, which keeps clearing a `target <= 0` journal too), so an install that already has a pending revert
  plan heals itself at boot.
- Engine: `ENGINE_VERSION` 6->7. A backward-compatible fix (reads only local device state and tightens an
  existing guard), so manifests keep their `engine_min`; the bump keeps the engine version honest per the
  "any logic change bumps" rule.

## ENGINE_VERSION 6 - 2026-11-25
- Fix (stale journal): a journal whose `target` is `<= 0` is a stale placeholder (the baseline `0`
  a removed stub left behind), never a real resumable update. It no longer drives any UI or boot action.
- WebUI widget (`vdlu.js`): `renderToast` and `onWebUIOpen` treat a `target <= 0` journal as a no-op and
  stay idle - the widget never shows an "Updating `<module>` -> v0" toast or offers to "resume" a bogus v0.
  A real transaction (`target >= 1`) still resumes as before.
- Engine (`update.sh`): `boot` self-heals existing installs - a leftover `target <= 0` journal (and its
  `plan`/`target` state) is cleared before any resume or diff, so the widget sees a clean idle state. A real
  in-flight transaction (`target >= 1`) is left untouched.
- Engine: `ENGINE_VERSION` 5->6. The change is a backward-compatible self-heal, so manifests keep their
  existing `engine_min`; the bump keeps the engine version honest per the "any logic change bumps" rule.

## ENGINE_VERSION 5 - 2026-11-24
- Security (VDLU#2): the engine EXCLUDES its own trust anchor - the `vdlu/` dir (`update.sh`, `vdlu-verify`,
  `verify/*`, `keyring/*`, config) - from the feed sync plan. A published feed carries the whole module tree,
  `vdlu/` included, so the engine IGNORES those paths (never fetches, applies or deletes them) rather than
  rejecting the manifest: the module still updates, the trust anchor changes only by a full signed re-flash,
  and a feed that tries to swap the verifier or signing key is silently ignored. A single signing-key leak
  can no longer swap the trust anchor and persist root. Reported by Solomag (VD-Modules#1).
- Engine: `ENGINE_VERSION` 4->5 (the VDLU#2 path rule above plus the lowered ceilings below). Both are
  backward-compatible tightenings, so manifests keep their existing `engine_min` (an older engine still
  applies a legit feed); the bump keeps the engine version honest per the "any logic change bumps" rule.
- Engine: lower the hardening ceilings - per-file `MAX_FILE_BYTES` 256->128 MiB and manifest
  `MAX_MANIFEST_BYTES` 4->2 MiB (in `update.sh`, and the inline copy in `vdlu-verify`). Defensive margin; the
  largest legitimate fleet file is well under 128 MiB.
- Engine: defer applying an update while the module is busy - opt-in `apply_busy_file` config key (an absolute
  path the module touches during its own operations). An update never swaps module files mid-operation, e.g.
  during a running backup. The blobs are already fetched, so the next trigger applies with no re-download.
  (VD-Modules#1)
- Engine: log the resolved TLS trust at setup - CA path and its readability, plus the bundle file's
  readability, size and cert count - so a boot-time curl rc 77 is self-explaining in `boot.log` (it tells an
  empty store apart from an unreadable one, i.e. the boot SELinux-context case). curl already runs with -S,
  so its own error reaches boot.log too. (VD-Modules#1)
- Docs: add `docs/SECURITY.md` - the security policy and trust-model summary (supported versions, private
  vulnerability reporting, the `key_id` allowlist, the fail-closed guarantees, and the hardening caps) - in
  English plus all 21 translations.
- Docs: translate `docs/QUICKSTART.md` (the module adoption checklist) into all 21 languages.
- Docs(de): restore proper German umlauts (ä/ö/ü/ß) in `docs/de/ENGINE.md`, `docs/de/INTERFACES.md`, and
  `docs/de/PRODUCER.md`, which a prior pass had transliterated to ae/oe/ue/ss.
- Public release: English README and dev docs, Apache-2.0 LICENSE, third-party NOTICE.
- Wiki is now repo-managed: page sources live in `wiki/` (see `wiki/README.md`), `.github/scripts/gen_wiki.sh`
  assembles the published pages, and `.github/workflows/wiki-sync.yml` publishes them to the GitHub Wiki on
  every push to `main` (no-op when unchanged).

## ENGINE_VERSION 4 - 2026-11-19
- **Trust root:** module-update signing key is now pinned to a fail-closed ALLOWLIST. `verify_manifest`
  rejects any manifest whose `key_id` is not in the configured `key_id` allowlist BEFORE selecting the
  pubkey, closing a bypass where a lower-trust key present in the keyring (e.g. a fingerprint-feed key)
  could sign a full flashless root update if it leaked. Default-safe when `key_id` is unset: a single-key
  keyring accepts only that one key; a multi-key keyring is rejected until `key_id` is pinned (comma-
  separated for rotation). The same allowlist is mirrored in `vdlu-verify` (via `VDLU_KEYID_ALLOW`) and
  applied to the signed tools-manifest. The fingerprint-feed trust root stays a separate, pinned path.
- Path validation also rejects dot-segment (`.`/`..` as a whole segment) and trailing-slash paths (this
  rule shipped under v3 without a version bump; versioned here so `engine_min` can gate it).
- Hardening (defense in depth): cap the tools-manifest size before reading it (anti-OOM) in both
  `install-tool` and `vdlu-verify`; bound the `wget` download path with `head -c` (the `--max-filesize`
  equivalent for curl-less devices); `check` now takes the lock before rebuilding its work dir;
  `stage_file` gets the same `contained()` containment guard as the other apply primitives; the WebUI
  poller gets an early `diff` journal at run start so a slow manifest fetch no longer shows a false
  "no response".
- `uname -m` to ABI fallback in `vdlu-verify` now also maps 32-bit x86 (`i686`/`i386`).
- Note: ANY change to engine verification/apply logic bumps `ENGINE_VERSION`.

## ENGINE_VERSION 3 - 2026-11-16
- `hardened` is the default profile; `profile` is fail-closed by inversion - only the literal `trusted`
  opts into best-effort verify, and any other value requires a valid signature.
- Manifest bound to the module id: the signed `module` field must match MODID, so a validly-signed feed
  for another module can no longer write here.
- Downgrade blocked (`version` must be >= the installed one).

## ENGINE_VERSION 2 - 2026-11-15
- `validate_plan()` runs fail-closed before any download or apply: rejects absolute or `..` paths, a
  `sha256` that is not 64 hex chars, and invalid mode/class/encoding.
- Closed three root-level issues from a cold audit: RCE via `sha256` injection, write path traversal via
  `files[].path`, and `rm -rf` via `delete[]`; `apply_live` now aborts if its backup fails.
- gzip decompress-bomb cap and symlink containment; `contained()` is fail-closed when `realpath` is missing.
- Slimmed down (Approach B): dropped openssl and zstd; adopted the embedded `ed25519-mini` verifier and gzip.
- `mkdir`-based lock (toybox `flock` is broken on Android).

## ENGINE_VERSION 1 - 2026-11-14
- Initial VDLU engine: flashless, incremental module self-update (DIFF -> FETCH -> APPLY -> COMMIT),
  content-addressed feed, resumable journal, and rollback.

<!-- doc-footer -->

---

> _This documentation was generated with Claude (Anthropic) and is maintained by VD171. Corrections and improvements are welcome, see [CONTRIBUTING.md](CONTRIBUTING.md)._
