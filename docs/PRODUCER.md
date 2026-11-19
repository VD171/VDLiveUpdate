> **Languages:** English · [العربية](ar/PRODUCER.md) · [Čeština](cs/PRODUCER.md) · [Deutsch](de/PRODUCER.md) · [Español](es/PRODUCER.md) · [فارسی](fa/PRODUCER.md) · [Français](fr/PRODUCER.md) · [हिन्दी](hi/PRODUCER.md) · [Bahasa Indonesia](id/PRODUCER.md) · [Italiano](it/PRODUCER.md) · [日本語](ja/PRODUCER.md) · [한국어](ko/PRODUCER.md) · [Nederlands](nl/PRODUCER.md) · [Polski](pl/PRODUCER.md) · [Português](pt/PRODUCER.md) · [Русский](ru/PRODUCER.md) · [Svenska](sv/PRODUCER.md) · [ไทย](th/PRODUCER.md) · [Türkçe](tr/PRODUCER.md) · [Українська](uk/PRODUCER.md) · [Tiếng Việt](vi/PRODUCER.md) · [中文](zh/PRODUCER.md)

---

# VDLU producer + signing layer

Builds the content-addressed delivery (manifest + blobs) for a module and signs it.
Conforms to [`INTERFACES.md`](INTERFACES.md) §3/§6/§7.

| tool | runs on | language | job |
|---|---|---|---|
| `producer/vdlu-pack` | PC / CI | python3 | walk the final module tree -> `manifest.json` + `blobs/` |
| `producer/vdlu-keygen` | PC | sh + openssl | ed25519 keypair (`<id>.pem` priv, `<id>.pub` PEM, `<id>.pub.raw` RAW 32B for the slim keyring) |
| `producer/vdlu-sign` | PC | sh + openssl | inject `key_id` + `sig` into a manifest, in place |
| `engine/vdlu-verify` | **device** | sh + ed25519-mini | verify `sig` via the embedded ed25519-mini; keyring = RAW 32B pubkey (NO openssl on device) |

## Pipeline

```sh
# 1. one-time: a signing key. Keep the .pem off every device and off any repo push.
producer/vdlu-keygen release-2026 ./keys

# 2. each release: pack the final tree (same tree the .zip ships, post-whitelist).
producer/vdlu-pack  ./module_tree  ./out  demo 106 --version-name v106 --channel stable \
                    [--prev ./prev/manifest.json]      # delete[] = paths gone since prev

# 3. sign the manifest in place.
producer/vdlu-sign  ./out/manifest.json  ./keys/release-2026.pem  release-2026

# 4. publish ./out/{manifest.json,blobs/} to <source> (Pages batch for public; rsync for private).
#    The slim device keyring holds ./keys/release-2026.pub.raw as keyring/release-2026.pub (RAW 32B).
```

`vdlu-pack` is content-addressed and deduplicating: a blob whose `<sha256>` already exists is not
rewritten, so publishing is incremental and the unchanged / reverted content is never re-pushed.

### `enc` decision (vdlu-pack)

`sha256` is **always** of the original (uncompressed) content; `enc` only names how the blob is stored.

- `gz` when `size >= 4096` **and** gzip (`-9 -n`, deterministic) saves at least 10% (`comp <= raw*0.90`).
- `raw` otherwise (small text that HTTP gzip already covers, or already-incompressible data).
- gzip missing on the build host -> everything `raw` (never fails).

A blob is stored once, in one format: `blobs/<sha256>` (raw) or `blobs/<sha256>.gz` (gz). The device
decompresses with toybox `gunzip` (always present), so no zstd is bundled.

### `class` decision (vdlu-pack) - reboot taxonomy

Derived from path (INTERFACES §3, doc §4). Defaults only; a path rule never downgrades `reboot`->`live`.

| class | matched by | applied |
|---|---|---|
| `reboot` | `system/**`, `zygisk/**/*.so`, `*.rule` | staged `.vdlu-new`, swap at boot |
| `soft` | root `service.sh` / `post-fs-data.sh` / `boot-completed.sh` | written live, runs next boot |
| `live` | everything else (webroot, bin, lib, confs, module.prop, ...) | written live, atomic |

Symlinks are **not followed** (never leaks content from outside the tree, e.g. a link to
`/etc/shadow`) and are skipped with a warning, since the manifest schema has no symlink type.
Non-regular files (dirs, fifos, devices) are skipped. `built` honors `SOURCE_DATE_EPOCH` for
reproducible manifests.

### Baseline (the install seed) - unsigned, keyless

`baseline.json` (shipped at `vdlu/baseline.json` in the module zip) seeds `current.json` on a fresh install
so the device is born "current" (no from:0, no re-fetch). The engine treats it as a **local trusted seed**
(it arrived in the flashed zip, which is the install trust boundary) and **does NOT verify its signature** -
only the manifest FETCHED from the feed goes through `vdlu-verify`. So the baseline needs **no key**: it is
just `vdlu-pack` output over the shipped tree (unsigned; `sig`/`key_id` stay empty). A CI can therefore
generate it **keyless**, keeping the signing key 100% out of CI - only the published FEED is signed (operator,
locally). `vdlu-pack` excludes `baseline.json` from its own manifest (anti self-reference). Non-fatal if
absent: the device just starts from:0 on the first update, never broken.

## Canonicalization (the convergence point)

`vdlu-sign` and `engine/vdlu-verify` must derive the **same bytes** from a manifest, on two
different runtimes (PC openssl vs device toybox). The rule is deliberately a byte
transform, not a JSON re-serialization, so it needs no JSON library on the device:

1. `vdlu-pack` writes `manifest.json` **compact, keys sorted, UTF-8**
   (`json.dumps(obj, sort_keys=True, separators=(",",":"), ensure_ascii=False)`), always including
   the fields `key_id` and `sig` (empty string placeholders until signed). This is the canonical
   store form.
2. **Canonical form = that text with the `"sig"` field removed.** Because keys are sorted, `sig`
   always appears as `,"sig":"<value>",` bracketed by `"schema"` (before) and `"version"` (after),
   both always present. Removing it leaves well-formed `...,"schema":N,"version":...`.
   JSON escapes every `"` inside string values to `\"`, so the structural token `"sig":"` is
   unambiguous even against a filename that literally contains `"sig":"` (tested).
3. The signed/verified message is the **sha256 hex** (64 ASCII chars, no newline) of the canonical
   form. ed25519 over that hex (`openssl pkeyutl -sign/-verify -rawin`).

The removal in POSIX sh (identical function in both tools, no `sed`/`jq`):

```sh
# $1 = full manifest text (trailing newline already stripped by $(cat ...))
_pre=${_c%%\"sig\":\"*}     # up to  ...,"schema":N,
_rest=${_c#*\"sig\":\"}      # after "sig":"
_tail=${_rest#*\",}          # after <value>",  ->  "version":...
printf '%s%s' "$_pre" "$_tail" | sha256sum | cut -d' ' -f1
```

`key_id` is part of the canonical form (only `sig` is stripped); `vdlu-sign` sets `key_id` **before**
hashing. The value placeholder being empty (`"sig":""`, sign time) or filled (verify time) yields the
identical canonical bytes, so sign and verify agree by construction.

Python reproduces it as `re.sub(r'"sig":"[^"]*",', '', text.rstrip("\\n"), count=1)` then sha256 - used
only to cross-check; the authoritative producers are the two sh tools.

## Signature (ed25519)

- `vdlu-keygen` (PC): `openssl genpkey -algorithm ed25519` (priv `0600`) + `openssl pkey -pubout` (pub **PEM**,
  for signing/openssl) + `openssl pkey -pubout -outform DER | tail -c 32` -> **`.pub.raw` (RAW 32B)** (the ed25519
  SPKI DER is a 12-byte prefix + the 32-byte key, so `tail -c 32` IS the key). It emits BOTH.
- `vdlu-sign` (PC): `openssl pkeyutl -sign -rawin` over the canonical sha256 hex; signature stored base64.
- `vdlu-verify` (**device, slim**): `ed25519-mini <pubkey32> <msg> <sig64>` - reads the keyring as the **RAW 32B**
  pubkey, NO openssl on the device. `key_id` is path-sanitized (no `/`, `.`, `..`, `"`). 🚨 The keyring ships the
  **`.pub.raw` (32B)**, never the `.pub` PEM (113B): the PEM is PC-side only and `ed25519-mini` cannot read it.

Trust model (INTERFACES §6, doc §11/§13): `profile=hardened` (public) makes verify mandatory - a
failed or missing signature aborts the update. `profile=trusted` (private, SSH-staged source) treats
verify as best-effort, but every blob's sha256 is checked regardless.

## Keyring + rotation

The keyring is a directory of `<key_id>.pub` files, each the **RAW 32B** ed25519 pubkey (from `keygen`'s
`.pub.raw`), NOT PEM - `ed25519-mini` reads raw 32 bytes. Ship the current **and** the previous raw pubkey
(doc §13) so a rotated key does not brick older installs. `vdlu-sign` with the new `key_id` and the device
picking `<keyring>/<key_id>.pub` (raw) is the whole rotation mechanism - no engine change. The keyring is
**stable** across releases (only key rotation changes it): a re-vendor must **verify-not-copy** it, and never
overwrite it with the PC-side `.pub` PEM.

`vdlu-pack` **excludes the keyring and the `verify/` binaries from the feed** (the trust root is flash-only,
never served over the wire), alongside `baseline.json`, the installer scaffolding (`META-INF/`,
`customize.sh`), the `.vd/` flash gate, the CI-filled `update.json`/`update-mmrl.json`, and the per-file
`.sha256` companions. Only the module's own content is feed-updatable, so a manifest can never rewrite the
on-device trust anchor.

<!-- doc-footer -->

---

> _This documentation was generated with Claude (Anthropic) and is maintained by VD171. Corrections and improvements are welcome; see [CONTRIBUTING.md](../CONTRIBUTING.md)._
