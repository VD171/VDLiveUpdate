# Changelog

Notable changes to the VDLU engine. Entries track ENGINE_VERSION, the on-device compatibility gate a
signed manifest declares via `engine_min`.

## Unreleased
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

> _This documentation was generated with Claude (Anthropic) and is maintained by VD171. Corrections and improvements are welcome; see [CONTRIBUTING.md](CONTRIBUTING.md)._
