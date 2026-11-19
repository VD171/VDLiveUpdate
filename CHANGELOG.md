# Changelog

Notable changes to the VDLU engine. Entries track ENGINE_VERSION, the on-device compatibility gate a
signed manifest declares via `engine_min`.

## Unreleased
- Public release: English README and dev docs, Apache-2.0 LICENSE, third-party NOTICE.
- Hardening: path validation now also rejects dot-segment (`.`/`..` as a whole segment) and trailing-slash
  paths. The signed feed never carries the on-device trust root (keyring + verifier) or flash-only infra, so
  no manifest can rewrite what verifies it.

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
