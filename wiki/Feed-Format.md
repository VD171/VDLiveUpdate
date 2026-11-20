# Feed Format

The **feed** is what VDLU serves over the wire and what the device updates from. It is a plain static directory, servable by anything (GitHub Pages, a rsync target, a `file://` path):

```
<source>/
  manifest.json          # the signed description of the current release
  blobs/<sha256>         # one blob per distinct file content
  blobs/<sha256>.gz      # (when the blob is stored gzipped)
```

The module itself also ships one extra file, `baseline.json`, inside the `.zip` (not served from the feed). The producer that builds all of this is described in [[Producer]]; this page is the on-wire contract.

---

## manifest.json

The manifest is the complete description of one release: every file in the target tree, what to delete, and the signature over the whole thing.

```json
{
  "schema": 1,
  "module": "demo",
  "version": 106,
  "version_name": "v106",
  "built": "2026-11-19T12:00:00Z",
  "engine_min": 3,
  "channel": "stable",
  "key_id": "release-2026",
  "files": [
    {
      "path": "webroot/index.html",
      "sha256": "<hex64>",
      "size": 1234,
      "mode": "0644",
      "enc": "raw",
      "class": "live"
    }
  ],
  "delete": ["webroot/old.html"],
  "sig": "<base64>"
}
```

### Fields

| Field | Meaning |
|---|---|
| `schema` | Format version of the manifest itself (currently `1`). |
| `module` | The module id. The device rejects the manifest if it does not match its own module id, so a validly signed feed for a different module cannot be served in its place. |
| `version` | Integer version. The engine updates forward only; a feed older than the device is a benign "ahead" state, not an error. |
| `version_name` | Human-readable version string (for example `v106`). |
| `built` | ISO 8601 build timestamp. Honors `SOURCE_DATE_EPOCH` for reproducibility. |
| `engine_min` | The minimum engine version required to apply this manifest. |
| `channel` | Release channel (for example `stable`). |
| `key_id` | Which key in the device keyring signed this manifest. Selects the public key for verification, and must be in the engine's module-update allowlist (see [[Security and Trust Model]]); a key merely present in the keyring but not allowlisted is rejected before its pubkey is loaded. |
| `files[]` | The **complete** target tree (not a diff). Each entry: `path`, `sha256`, `size`, `mode`, `enc` (`raw`/`gz`), `class` (`live`/`soft`/`reboot`). |
| `delete[]` | Paths present in the previous release but gone now, for the device to remove. |
| `sig` | The ed25519 signature, base64. See the canonicalization below. |

`files[]` describes the **whole** tree, not a delta. The device computes the delta itself by comparing the manifest against what it already has, and fetches only the blobs whose `sha256` it is missing. The `sha256` is always of the original (uncompressed) content; `enc` only says how that blob is stored in `blobs/`. The meaning of `class` and what the device does with each value is covered in [[Reboot Handling]].

---

## Canonicalization (the signed bytes)

This is the single most important invariant in the format. The PC signer and the on-device verifier run on completely different runtimes (openssl on the PC, toybox + a tiny embedded verifier on the device, and **no JSON library at all** on the device). They must still derive the exact same bytes to sign and to verify. The rule is therefore a deliberate **byte transform**, not a JSON re-serialization.

**Step 1: a fixed store form.** `vdlu-pack` writes `manifest.json` compact, with keys sorted, UTF-8, always including `key_id` and `sig` (as empty strings until signed):

```
json.dumps(obj, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
```

**Step 2: strip only `sig`.** The canonical form is that exact text with **only the `"sig"` field removed**. Because keys are sorted, `sig` always appears as `,"sig":"<value>",` bracketed by `"schema"` before it and `"version"` after it (both always present), so removing it leaves well-formed text. JSON escapes every `"` inside a string value as `\"`, so the structural token `"sig":"` is unambiguous even against a filename that literally contains `"sig":"`.

The removal is a handful of POSIX parameter expansions, identical in the signer and the verifier, with no `sed` and no `jq`:

```sh
# $1 = the full manifest text
_pre=${_c%%\"sig\":\"*}     # up to  ...,"schema":N,
_rest=${_c#*\"sig\":\"}      # after "sig":"
_tail=${_rest#*\",}          # after <value>",  ->  "version":...
printf '%s%s' "$_pre" "$_tail" | sha256sum | cut -d' ' -f1
```

**Step 3: sign the hash of that.** The signed/verified message is the **sha256 hex** (64 ASCII characters, no newline) of the canonical form. ed25519 signs that hex.

Two consequences fall out of this by construction:

- `key_id` is part of the canonical form (only `sig` is stripped). `vdlu-sign` sets `key_id` **before** hashing, so the key identity is covered by the signature.
- Whether the `sig` placeholder is empty (`"sig":""`, at sign time) or filled (at verify time), stripping it yields the identical canonical bytes. Signing and verifying agree automatically.

The two POSIX sh tools are authoritative. A Python equivalent, `re.sub(r'"sig":"[^"]*",', '', text, count=1)` then sha256, exists only to cross-check them.

The trust reasoning around all of this (why verification is on-device, how `hardened` fails closed) lives in [[Security and Trust Model]].

---

## baseline.json (the install seed)

When a module is freshly installed, it should already be "current" for its own shipped version, with no needless self-update of the version it just installed. That is what `baseline.json` does.

`baseline.json` ships **inside the module zip** (at `vdlu/baseline.json`), not on the feed. On a fresh install, the engine seeds its "active version" record from it, so the device is born current, with no `from:0` and no re-fetch of what it already has.

Key properties:

- It is a **keyless copy of the signed manifest** for the shipped version: the same `vdlu-pack` output, left unsigned (`key_id` and `sig` stay empty).
- It is **not verified**. The engine treats it as a local trusted seed because it arrived inside the flashed zip, which is the install trust boundary. Only a manifest *fetched from the feed* goes through signature verification.
- Because it needs no signature, **CI can generate it keyless**, which is what keeps the signing key entirely out of CI (see [[Producer]]).
- `vdlu-pack` **excludes `baseline.json` from its own manifest**, so the manifest never references the baseline (that would be a self-reference loop: manifest to baseline to manifest).
- It is **non-fatal if absent**. Without it, the device simply starts from `from:0` on its first update and fetches what it needs. Never broken, just less optimal.

---

## Blobs

Each distinct file content is one blob under `blobs/`, named by the **sha256 of the original content**:

- `blobs/<sha256>` for a raw blob.
- `blobs/<sha256>.gz` for a gzipped blob (gzip is kept only when the file is at least 4096 bytes and compression saves at least 10 percent).

A blob is stored once, in one format. Content addressing gives deduplication for free: unchanged, shared or reverted content maps to a blob that already exists, so the feed grows only by genuinely new content, and the device downloads only the hashes it is missing. The device checks every downloaded blob's `sha256` against the manifest (after decompressing a `gz` blob) before using it.

---

## What is excluded from the feed, and why

The feed carries **only the module's own content**. A fixed set of paths is kept out of it on purpose. `vdlu-pack` applies one exclusion predicate both when walking the tree and when computing `delete[]`.

| Excluded | Why |
|---|---|
| `vdlu/keyring/`, `vdlu/verify/` (the trust root: raw public keys + the verifier binary) | **This is the core security reason.** The trust anchor is **flash-only**. If the keyring or verifier were feed-deliverable, a manifest could overwrite the very thing that validates it. Keeping them off the wire means a manifest can never rewrite the on-device trust anchor. |
| `vdlu/baseline.json` | It is a copy of the signed manifest (the install seed); packing it would be a self-reference loop. |
| `.vd/` flash infrastructure | Flash-gate scaffolding that ships in the zip, never applied live. |
| `update.json`, `update-mmrl.json` | Their size/sha are filled in by CI *after* the zips are built, so the shipped copy differs from any feed copy. Feeding them would cause a phantom single-file fetch on every install's first self-update, and they are vestigial on-device anyway (the manager reads the remote raw update JSON). |
| `META-INF/`, `customize.sh` (installer scaffolding) | Consumed by the manager at **flash** time and not kept in the installed module. They are not VDLU content; serving them wastes blobs and, if one ever changed between versions, it would get written as an installer file into the live module directory. |
| Per-file `.sha256` companions | They belong to the flashable zip only, go stale after an incremental update, and would double the manifest. |
| Dev/doc files (`RELEASE.md`, `CLAUDE.md`, `.gitignore`) | Never shipped to the device; serving them wastes blobs and churns the signed manifest on every doc edit. |

The reasoning behind the trust-root exclusion is expanded in [[Security and Trust Model]].

---

## delete[] semantics

`delete[]` tells the device which paths to remove, so a file dropped between releases does not linger on-device as an orphan. It is computed by passing `--prev <previous manifest.json>` to `vdlu-pack`: a path that was in the previous release and is not in the current one becomes a delete entry.

The important rule: **excluded paths are never emitted as deletes, even with `--prev`.** Every previous path is run through the same exclusion predicate used when walking the tree. If a `--prev` points at an older manifest that still listed now-excluded paths (a stray `baseline.json`, `META-INF/*`, a keyring entry, and so on), those paths are **not** turned into delete entries. An excluded path was never feed content, so it is not VDLU's to delete, and the device is never ordered to remove a file that was not served through the feed. This is what keeps the exclusion list from ever doubling back as a destructive instruction.
