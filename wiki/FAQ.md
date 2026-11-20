# FAQ

Short answers to the questions that come up most. Each one links to the page with
the full story.

## What does "flashless" mean? Do I still flash the first time?

Yes, you flash once. The module is installed the normal way (flash the zip in
your root manager). "Flashless" describes every update after that: VDLU fetches
only the files that changed and applies them in place, so you never re-flash a
full zip just to ship a few changed lines. See [[Architecture]].

## Does an update need a reboot?

Usually no. Most files (your WebUI, binaries, libraries, configs, `module.prop`)
are **live** class and apply atomically with no reboot. Only reboot-class files
(a `.so` under `zygisk/`, a `/system/**` overlay, an `*.rule` sepolicy file) are
**staged** and swapped in at the next boot, because a running process has already
mapped the live inode. When that happens the WebUI shows a persistent "reboot to
activate" banner. See [[Reboot Handling]].

## Is it safe if the feed is MITM'd or poisoned?

Yes, on a `hardened` feed. Every manifest field is treated as hostile input.
The manifest must carry a valid ed25519 signature over its canonical form, and
`validate_plan()` runs fail-closed **before any download**: it rejects the whole
manifest on an absolute or `..` path, a `sha256` that is not 64 hex characters,
or an invalid mode, class or encoding. The manifest is also bound to your module
id, so a validly signed feed for a different module cannot be served in its place.
Every blob's sha256 is verified after download regardless of profile. See
[[Security and Trust Model]].

## What does it need on the device (dependencies)?

Very little. Pure POSIX sh (mksh / busybox / toybox) plus toybox's `sha256sum`,
`gzip`, `base64` and `date`; the embedded `ed25519-mini` verifier; and, only for
an `https` source, a static `curl` that is fetched once and cached in Tier-2.
A `file://` source needs no curl at all. There is **no dependency on `jq`**: the
engine parses JSON with a gron-style flattener written in `awk`. See [[Engine]].

## Is openssl required on device?

No. `openssl` is used only on the PC/release side (`vdlu-keygen`, `vdlu-sign`).
On the device, signature verification uses the slim embedded `ed25519-mini`
binary, which reads a RAW 32-byte public key. See [[Producer]] and
[[Security and Trust Model]].

## How do I rotate the signing key?

Generate a new keypair with `vdlu-keygen`, add the new RAW 32-byte public key to
the device keyring alongside the previous one, and start signing with the new
`key_id`. The device picks `<keyring>/<key_id>.pub` by the manifest's `key_id`,
so no engine change is needed. Shipping both the current and previous public key
means a rotated key never bricks older installs. Because a rotation leaves more
than one key in the keyring, you must also pin which key may sign a module update:
set the `key_id` config (comma-separated during the rotation window). A single-key
keyring auto-pins and needs no config. See [[Security and Trust Model]].

## hardened vs trusted - which do I use?

Use `hardened` for any public feed (served over `https`, e.g. GitHub Pages).
It makes the signature mandatory and blocks downgrades. Use `trusted` only for a
private `file://` or SSH-staged source you already control, where the signature
is best-effort (every blob hash is still checked). When in doubt, use `hardened`:
it is the fail-closed default, and any non-`trusted` value is treated as
`hardened`. See [[Security and Trust Model]].

## What if a blob is tampered or the manifest is malformed?

The update aborts and nothing is applied. A malformed manifest is rejected whole
by `validate_plan()` before any fetch. A blob whose sha256 does not match the
manifest is rejected; three failures on the same blob abort the fetch phase with
nothing applied. On any hard failure the journal records `ERROR` and the module
is left intact. See [[Engine]].

## Can an update delete my files or brick the device?

The risk is contained by design. Overwritten and deleted files are first backed
up to `rollback/<version>/`, and `apply` aborts rather than overwrite without a
successful backup. Deletes run only when a transaction reaches `DONE`, never
while a reboot is still pending. A failed apply reverts the live files it already
wrote. Paths are validated for containment inside the module directory before use,
so a manifest cannot write or delete outside the tree. See [[Engine]] and
[[Security and Trust Model]].

## Does it work on KernelSU AND Magisk AND APatch?

Yes. VDLU is plain POSIX sh plus a WebUI, vendored into the module, so it runs on
KernelSU, APatch and Magisk alike. It uses the root manager's WebUI bridge
(`ksu.exec`) to drive the engine and poll progress. See [[Architecture]] and
[[WebUI]].

## How big is the on-device footprint?

Small. The engine is scripts; the only binaries are the per-ABI `ed25519-mini`
verifier (tiny) and, for an `https` source, a static `curl` (~1MB) that is
fetched once and cached. A module that already bundles its own `curl` reuses it
and adds no download at all. The Tier-2 blob cache holds verified content plus
the last 3 rollback versions. See [[Engine]] and [[Architecture]].
