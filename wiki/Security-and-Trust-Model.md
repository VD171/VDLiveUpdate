# Security and Trust Model

VDLU updates a module in place, over the network, as root. That is a lot of power pointed at a file that comes from a feed, so the whole engine is built on a single assumption:

> **Every field in the manifest is hostile input.**

A feed can be poisoned at the source, or swapped and mangled in transit by a MITM. When that happens the manifest still arrives looking like a manifest: it carries file paths, `sha256` strings, a `delete[]` list, modes, classes and an encoding flag. VDLU treats none of those as trustworthy. It validates the entire plan before it downloads a single byte, and it never lets a manifest value reach a shell.

This page is the full trust story. See [[Feed Format]] for the manifest schema it validates, and [[Engine]] for where these checks sit in the DIFF -> FETCH -> APPLY -> COMMIT transaction.

---

## The core idea: fail-closed, before anything happens

`validate_plan()` runs inside the `check`/diff phase, **before** any fetch and **before** any apply. It walks every entry in the planned file tree and every entry in `delete[]`, and if any single entry is malformed it **rejects the whole manifest** and the transaction never starts. There is no partial accept, no "skip the bad one and apply the rest". One bad field poisons the batch, on purpose.

A manifest is accepted only if **all** of these hold for **every** entry:

| Field | Rule | Why |
|---|---|---|
| `path` | not absolute, no `..` component, no `.` component, no leading `./`, no embedded `/./`, no trailing slash, no control character (tab / newline) | a path must stay inside `MODULE_DIR`; an absolute or `..` path is write-anywhere |
| `sha256` | matches `^[0-9a-f]{64}$` exactly | a non-hex sha would otherwise be interpolated into a shell path; it is the content address, so it must be a pure hex digest and nothing else |
| `mode` | octal only (`[0-7]`) | a mode string becomes a `chmod` argument |
| `size` | digits only, and `<=` the engine's size ceiling | bounds the download and the decompression |
| `class` | exactly `live`, `soft` or `reboot` | the class decides whether a file applies live or is staged for reboot |
| `enc` | exactly `raw` or `gz` | the encoding decides whether the blob is gunzipped |
| `delete[]` entries | the same path rules as above | a `delete[]` entry drives a removal; an unchecked `..` would be `rm` outside the tree |

Because this runs first, a poisoned manifest can never write outside the module, never delete outside the module, and never inject a non-hex token into a command line.

### Manifest values never touch a shell

The second half of the rule: even after a value passes validation, it is never interpolated into `sh`, and never fed to `awk system()`. The check command was deliberately rewritten to contain no `system()` call. Content addressing does the rest of the work: a blob is fetched by its `sha256`, written to a cache path named by that same `sha256`, and the downloaded bytes are re-hashed and compared before anything is applied. A value that is not a clean 64-hex digest never gets that far, because `validate_plan()` already rejected it.

### A second line of defense at apply time

`validate_plan()` blocks `..` **lexically**, but a pre-existing symlink already inside the tree could still redirect a write. So at apply time `contained()` resolves the real target path and confirms it sits under the module base, failing closed when it cannot resolve. Writes are atomic (write to a temp name, then `rename` over the target) and every overwrite is backed up to `rollback/` first; a failed backup aborts the apply rather than overwrite with no safety net.

---

## The two profiles

VDLU runs in one of two trust profiles, set by `profile=` in the config.

### `hardened` (the public default)

- **Signature is mandatory.** The manifest must carry a valid ed25519 signature from a key in the on-device keyring, or the transaction aborts.
- **Downgrade is blocked.** A manifest whose `version` is lower than the installed version is refused. An attacker cannot roll you back to a known-vulnerable build.
- This is the profile for any module distributed to the public over `https://`.

### `trusted` (private, SSH-staged source)

- Signature verification is **best-effort**: the source is a private `file://` or SSH-staged feed you control, so a missing or unverifiable signature does not hard-abort.
- **But every blob's `sha256` is still checked, always.** `trusted` relaxes *who signed the manifest*, never *whether the bytes match the plan*. Content integrity is non-negotiable in both profiles.

---

## Fail-closed by inversion

This is the subtle part, and it is the part most systems get wrong.

`trusted` is the **only** string that opts into relaxed verification. The engine does not test "is this `hardened`?" It tests "is this **not** `trusted`?":

```sh
prof=$(cfg profile hardened | tr -d '[:space:]')
...
if [ "$prof" != trusted ]; then
    # signature mandatory
fi
```

So **anything** other than the literal `trusted` resolves to hardened behaviour:

- the line is missing entirely -> hardened
- a typo like `hardend` -> hardened
- `trusted ` with a trailing space, or a `\r` from CRLF -> hardened
- `Trusted` with wrong case -> hardened
- a MITM-mangled value -> hardened

An earlier version defaulted a *missing* line to hardened, which still left a corrupted *value* falling through to the open path. That was a fail-open: a mangled profile string could silently accept an unsigned manifest, and an unsigned manifest means an attacker-supplied `.so` swapped in under MITM, which is root-level remote code execution. The inversion closes it. The only way to get relaxed verification is to spell `trusted` exactly, and even then the blob hashes are checked. The engine is never one typo away from accepting unsigned code. (The `tr -d` strips stray whitespace so a legitimate `trusted` with sloppy spacing is not wrongly rejected, without reopening the hole.)

**This test is load-bearing. It must stay `!= trusted` and never become `== hardened`.**

---

## The manifest is bound to the module

A single release key signs many modules. So a manifest that is validly signed, for a *different* module, could in principle be served to this one (a feed misconfiguration, a source swap, or a MITM redirect) and its signature would check out.

VDLU closes this with a bind: the signed `module` field inside the manifest must equal this install's `MODID`, or the manifest is rejected as a cross-module feed. Because `module` is inside the signed canonical form, an attacker cannot change it without breaking the signature. A validly signed feed for module B simply cannot be applied to module A.

---

## The slim on-device verifier

Verification on the device uses **ed25519-mini**, a tiny verify-only checker built on TweetNaCl (public domain). There is **no `openssl` on the device**.

- The keyring entry is the **raw 32-byte public key**, stored as `keyring/<key_id>.pub`. (The PEM public key is a PC-side artifact only; copying a PEM into the device keyring breaks verification, since the verifier expects exactly 32 raw bytes.)
- `vdlu-verify <manifest.json> <keyring_dir>` reconstructs the canonical form (the manifest text with the `sig` field removed, compact, sorted keys), hashes it to the 64-char hex message the signature covers, decodes the base64 signature, checks it is 64 bytes, and asks `ed25519-mini <pub32> <msg> <sig64>` for a verdict. rc 0 = valid, anything else = reject.
- The binary is static per ABI (arm64-v8a, armeabi-v7a, x86, x86_64), with a `PROVENANCE.json` pinning the exact TweetNaCl sources, wrapper hash and build flags, so the thing running as root is auditable.
- The `key_id` from the manifest is itself sanitized (no `/`, no `..`, no quote) before it is used to pick a keyring file, so it cannot escape the keyring directory.

### The keyring is flash-only, verify-not-copy, stable

The keyring ships inside the module at flash time and does not get rewritten by the update engine. On re-vendor the rule is **verify, do not copy**: the keyring changes only on a deliberate key rotation, never as a side effect of an update.

### Key rotation does not brick older installs

When a signing key is rotated, the keyring ships **both the current and the previous raw public keys**. The verifier selects the key file by the manifest's `key_id`, so a feed still signed by the old key verifies against the old pubkey, and a feed signed by the new key verifies against the new one. A device that has not updated past the rotation keeps working; nothing is stranded.

---

## What the tools-manifest closes

The slim fetch bootstrap downloads a static `curl` on first use for modules that do not ship their own. Because that binary runs as root, its own manifest signature (ed25519-mini) and its hash are **mandatory in any profile**, including `trusted`, before it is ever installed or executed. The webview is only transport; trust comes from the on-device signature and hash check, never from the fact that a download succeeded.

---

## What an attacker CANNOT do

Even owning the feed, or sitting on the wire as a full MITM, an attacker cannot:

- **Write outside the module.** Absolute paths, `..`, `.`, control characters and trailing slashes are all rejected before any apply, and symlink redirection is caught again at apply time.
- **Delete outside the module.** `delete[]` entries pass the same path validation.
- **Inject a command.** No manifest value is interpolated into a shell or `awk system()`; `sha256` must be pure 64-hex or the whole manifest is rejected.
- **Ship unsigned code to a public install.** `hardened` makes the signature mandatory, and the profile is fail-closed by inversion, so no typo or mangled value downgrades that.
- **Serve another module's signed feed here.** The signed `module` field must equal this `MODID`.
- **Roll you back.** Downgrade is blocked in `hardened`.
- **Corrupt a blob undetected.** Every downloaded blob is re-hashed against the manifest `sha256` in both profiles; a mismatch after three tries aborts the phase with nothing applied.
- **Swap in a fake root fetcher.** The bootstrapped `curl` is signature- and hash-checked before it is installed or run, in every profile.
- **Half-apply a corrupt update.** The transaction only reaches `DONE` when a re-hash of everything matches; a failed apply rolls back rather than overwrite without a backup.

---

See also: [[Feed Format]] for the manifest schema, [[Engine]] for the transaction these checks live in, and [[Architecture]] for the big picture.
