# VDLiveUpdate (VDLU)

**VDLU is a flashless, incremental self-update engine for KernelSU / APatch / Magisk modules: an installed module updates its own files over a signed feed, fetching only what changed and applying most of it without a reboot.**

A normal module update ships the whole `.zip` again, so a few changed lines cost a full re-download, and a static update manifest can only point at a single `zipUrl` (one flavor for every device). VDLU takes a different path: it diffs the tree that is actually installed against a signed, content-addressed feed, downloads only the deltas, and writes them in place. An arm64 full install stays arm64 full, a lite install stays lite, and the module is never re-flashed.

VDLU is meant to be **vendored** into a module, dropped into `<module>/vdlu/`. It is not a module of its own.

## Objectives

- **Flashless self-update.** Update an installed module in place, over the air, with no root manager, no re-flash of the `.zip`, and no loss of the installed flavor.
- **Incremental by content.** Transfer only the blobs whose content changed. A content-addressed feed (`manifest.json` + `blobs/<sha256>`) means unchanged or reverted files are never re-fetched.
- **Reboot-free where it is safe.** Apply ordinary files live, immediately. Reserve a staged reboot only for the few files that truly need one (a `.so`, a `/system` overlay, an `sepolicy.rule`).
- **Slim on the device.** Pure POSIX `sh`, no `jq`, no `bash`, no `openssl` on the device. Verification rides on an embedded `ed25519-mini`; the only fetched binary is a static `curl`, used only for `https` feeds.
- **Fail-closed and honest.** Every manifest field is treated as hostile input and validated before anything is downloaded. Nothing is ever reported "done" unless a re-hash proves it, and nothing is overwritten without a backup first.

## Peculiarities

What makes VDLU different from a typical OTA client:

- **Flashless and incremental.** Content-addressed diff / fetch / apply with dedup: the device computes the delta against the signed feed and pulls only missing blobs.
- **Reboot-free where possible.** Ordinary files apply live; only `.so`, `/system` overlays, and `sepolicy.rule` files are staged and swapped on a single reboot. See [[Reboot Handling]].
- **POSIX `sh` on the device.** Runs under toybox / busybox / mksh. No `jq` (a `gron`-style `awk` flattener parses JSON), no `bash`isms, no heavy runtime.
- **Slim verification.** An embedded `ed25519-mini` verifies signatures. There is **no `openssl` on the device**; the private key never touches a device or CI.
- **Fail-closed security.** `validate_plan()` rejects the **whole** manifest on any bad field (absolute or `..` path, a `sha256` that is not 64 hex chars, an invalid mode / class / encoding). Two profiles, `trusted` and `hardened`, with `hardened` fail-closed by inversion. See [[Security and Trust Model]].
- **Resumable and atomic.** A journal makes every transaction crash-safe; writes use `rename` / `mv`; a backup is taken before any overwrite so a failed apply rolls back instead of corrupting the module.

## Start here

| If you want to... | Go to |
|---|---|
| Adopt VDLU into your module, step by step | [[Quick Start]] |
| Understand the whole system at a glance | [[Architecture]] |
| Learn the device-side engine (`update.sh`) | [[Engine]] |
| Build and sign a feed on your PC | [[Producer]] |
| Drop in the Updates panel | [[WebUI]] |
| Read the trust model and threat posture | [[Security and Trust Model]] |
| See the manifest and blob layout | [[Feed Format]] |
| Know what reboots and why | [[Reboot Handling]] |
| Ask a common question | [[FAQ]] |
| Contribute | [[Contributing]] |

## Project links

- **Source:** https://github.com/VD171/VDLiveUpdate
- **Channel (updates):** @Priv8_VD https://t.me/Priv8_VD

VDLiveUpdate is an independent, unofficial project. "Android" is a trademark of Google LLC; "KernelSU", "Magisk", and "APatch" are the marks of their respective authors. VDLU runs entirely on your device and your own release host.
