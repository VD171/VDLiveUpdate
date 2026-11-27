> **Languages:** English · [العربية](ar/TRUST-MODEL.md) · [Čeština](cs/TRUST-MODEL.md) · [Deutsch](de/TRUST-MODEL.md) · [Español](es/TRUST-MODEL.md) · [فارسی](fa/TRUST-MODEL.md) · [Français](fr/TRUST-MODEL.md) · [हिन्दी](hi/TRUST-MODEL.md) · [Bahasa Indonesia](id/TRUST-MODEL.md) · [Italiano](it/TRUST-MODEL.md) · [日本語](ja/TRUST-MODEL.md) · [한국어](ko/TRUST-MODEL.md) · [Nederlands](nl/TRUST-MODEL.md) · [Polski](pl/TRUST-MODEL.md) · [Português](pt/TRUST-MODEL.md) · [Русский](ru/TRUST-MODEL.md) · [Svenska](sv/TRUST-MODEL.md) · [ไทย](th/TRUST-MODEL.md) · [Türkçe](tr/TRUST-MODEL.md) · [Українська](uk/TRUST-MODEL.md) · [Tiếng Việt](vi/TRUST-MODEL.md) · [中文](zh/TRUST-MODEL.md)

---

# Security policy and trust model

VDLiveUpdate (VDLU) applies **flashless root updates** to a live module: it writes
into `/data/adb/modules/<mod>` and swaps a Zygisk `.so` at boot. Every field of a
fetched manifest (`path`, `sha256`, `delete[]`, `mode`, ...) is **hostile input** - a
poisoned feed or a MITM delivers it. This page is the trust model and the responsible
disclosure policy. For the full seam contract see [`INTERFACES.md`](INTERFACES.md),
and the engine/producer internals in [`ENGINE.md`](ENGINE.md) and
[`PRODUCER.md`](PRODUCER.md), the wiki page **Security-and-Trust-Model** carries the
same model for readers outside the repo.

## Supported versions

Security fixes land in the latest `ENGINE_VERSION`, a signed manifest declares the
minimum engine it needs via `engine_min`, and the on-device engine refuses a manifest
that asks for more than it implements. Older vendored engines are expected to
**re-vendor** to pick up a fix, not to be back-patched in place.

| ENGINE_VERSION | status |
|---|---|
| 8 (current) | supported - ABI-aware plan reduction (drops other-ABI paths so a pruned per-ABI install stops re-fetching the universal-full tree; a pure reduction run after `validate_plan`, fail-safe when the device ABI is undetectable) |
| 7 | superseded - never revert a module ahead of the feed (the live installed `versionCode` floors the "from" version), boot self-heal of a stale downgrade plan |
| 6 | superseded - boot self-heal of a stale `target <= 0` journal (a removed stub's baseline 0 no longer drives any UI or boot action) |
| 5 | superseded - engine-side trust-anchor exclusion (the `vdlu/` dir is ignored even if a feed carries it), 128 MiB per-file / 2 MiB manifest ceilings |
| 4 | superseded - `key_id` allowlist, dot-segment/trailing-slash path rejection, size caps, check-time lock |
| <= 3 | unsupported - re-vendor the current engine |

Any change to engine verification or apply logic bumps `ENGINE_VERSION`.

## Reporting a vulnerability

Report privately. **Do not** open a public issue, PR, or forum post for a security
bug. Use the project contacts (see [`CONTRIBUTING.md`](../CONTRIBUTING.md)):

- Telegram: **@VD_Priv8** (https://t.me/VD_Priv8)
- Channel: **@Priv8_VD** (https://t.me/Priv8_VD)
- E-mail: **vd.priv8@pm.me**

Please include the engine version, the `profile` in use, and a manifest or feed that
reproduces the issue. Fixes ship as a new `ENGINE_VERSION` with a `CHANGELOG.md`
entry, coordinate disclosure timing on the report thread.

## Trust model

- **Detached ed25519 signatures.** The producer signs the canonical manifest on the
  PC (openssl), the device verifies with the embedded `ed25519-mini` - **no openssl on
  the device**. The signed message is the sha256 hex of the manifest without its `sig`
  field (keys sorted, compact, UTF-8), so sign and verify derive the same bytes on two
  runtimes without a JSON library on the device.
- **Keyring = RAW 32-byte pubkeys**, flash-only. The device keyring ships `<key_id>.pub`
  as the raw 32-byte key (never the PEM), `vdlu-pack` **excludes** the keyring and the
  `verify/` binaries from the feed, so a manifest can never rewrite the on-device trust
  anchor over the wire.
- **Engine-side trust-anchor exclusion (VDLU#2).** Independently of the producer-side
  exclusion above, the on-device engine **ignores** every `vdlu/` path (`update.sh`,
  `vdlu-verify`, `verify/*`, `keyring/*`, config) in a fetched plan - it never fetches,
  applies, or deletes them, even if a feed carries them. A published feed ships the whole
  module tree, `vdlu/` included, so the engine silently drops those paths rather than
  rejecting the manifest: the module still updates, and the trust anchor changes only
  through a full signed re-flash. A single leaked signing key can no longer swap the
  verifier or the signing key over the wire and persist root.
- **Module-update `key_id` allowlist (fail-closed, before pubkey selection).** A keyring
  may legitimately carry more than one key (for example a lower-trust fingerprint-feed
  key next to the release key). Before `<key_id>.pub` is ever selected, `verify_manifest`
  rejects any manifest whose `key_id` is not in the configured allowlist, in **both**
  profiles, and mirrors the resolved set into `vdlu-verify` via `VDLU_KEYID_ALLOW`. This
  closes a bypass where a leaked lower-trust key could otherwise sign a full flashless
  root update. Default-safe when `key_id` is unset: a **single-key** keyring auto-pins to
  that one key, a **multi-key** keyring is rejected until `key_id` is pinned
  (comma-separated for rotation).
- **The fingerprint-feed trust root is a separate, pinned path** with its own key, it is
  never reachable through the module-update path above.
- **Baseline is a local trusted seed.** `baseline.json` arrives inside the flashed zip -
  the install trust boundary - so it is unsigned and keyless and is **not** run through
  `vdlu-verify`, only a manifest **fetched** from the feed is verified. This keeps the
  signing key out of CI.

## Fail-closed guarantees

- **`validate_plan` runs before any fetch or apply.** In `do_diff`, fail-closed, it
  rejects the **whole** manifest if any `path` is absolute, contains a `..` or `.`
  segment, ends in `/`, or holds a control character, if any `sha256` is not
  `^[0-9a-f]{64}$`, or if any `mode`/`class`/`enc` is invalid. No hostile field reaches
  a shell, and `cmd_check` carries no `system()` interpolation.
- **Path containment.** Every write and delete is confined to `MODULE_DIR` via
  `contained()` - apply, delete, and the reboot `stage_file` all pass the same guard.
  Symlinks in the tree are skipped by the producer (never leak content from outside it).
- **Two profiles, fail-closed by inversion.** `trusted` (private, SSH-staged source) is
  the **only** opt-in to best-effort verify, **any** other value - including a typo, a
  trailing space/CR, or a different case - is treated as `hardened`, where a valid
  signature is **mandatory** and a failure aborts. Every blob's `sha256` is checked in
  both profiles.
- **Signature + hash before any tool exec.** The fetched static `curl` runs as root, so
  `install-tool` verifies the tools-manifest signature (ed25519-mini, mandatory in **any**
  profile) and the curl's hash **before** it is installed and executed - sig+hash before
  exec closes the RCE.
- **Resumable, pin-safe transaction.** The in-flight manifest is pinned in `target.json`;
  a crash, network loss, or reboot resumes from the journal without re-deciding the plan.
  Downgrade is blocked (monotonic `version`), the signed `module` field must equal
  `MODID`, and `delete[]` runs only at `finalize_done` (a `PENDING_REBOOT` deletes
  nothing). Nothing is ever "done" without a full re-hash, nothing is overwritten without
  a `rollback/<v>/` backup first.

## Hardening (defense in depth)

- **Size caps.** The manifest, the tools-manifest, and the curl-less `wget`/`head -c`
  download path are all bounded before being read (anti-OOM / anti-flood). A blob fails
  its phase after 3 attempts. The ceilings are **128 MiB per file** (`MAX_FILE_BYTES`)
  and **2 MiB for the manifest** (`MAX_MANIFEST_BYTES`), enforced in `update.sh` and
  mirrored in `vdlu-verify`.
- **Check-time lock.** `check` takes the mkdir-lock before rebuilding its work dir, so a
  concurrent run cannot race it.
- **Staging containment.** `stage_file` has the same `contained()` guard as the live
  apply primitives, so a staged reboot-hard path cannot escape `MODULE_DIR` either.
- **TLS is defense in depth, not the trust root.** The static curl uses mbedTLS with the
  Android trust store (`--capath`, `ca_path` override), the integrity guarantee is the
  ed25519 signature, the cert check is a second layer.

## See also

- [`INTERFACES.md`](INTERFACES.md) - the immutable seam contract (§5 config, §6 signature, §11 toolchain).
- [`ENGINE.md`](ENGINE.md) - the device-side engine and its state machine.
- [`PRODUCER.md`](PRODUCER.md) - packing, signing, canonicalization, and key rotation.
- Wiki: **Security-and-Trust-Model**.

<!-- doc-footer -->

---

> _This documentation was generated with Claude (Anthropic) and is maintained by VD171. Corrections and improvements are welcome, see [CONTRIBUTING.md](../CONTRIBUTING.md)._
