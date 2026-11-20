<!--
  ======================================================================
   VDLiveUpdate (VDLU)  ::  flashless, incremental module updates
   A self-update engine for KernelSU/APatch/Magisk modules: fetch only the
   files that changed, apply the live ones with no reboot, verified by ed25519.

   Copyright (C) 2026  VD171
   SPDX-License-Identifier: Apache-2.0

   Licensed under the Apache License, Version 2.0; you may obtain a copy at
   http://www.apache.org/licenses/LICENSE-2.0

   Site           : https://vd171.ru
   Site           : https://vd.priv8.ru
   Source         : https://github.com/VD171/VDLiveUpdate
   GitHub         : @VD171 https://github.com/VD171
   XDA-Developers : @VD171 https://xdaforums.com/m/vd171.4699873/
   Telegram       : @VD_Priv8 https://t.me/VD_Priv8
   Channel        : @Priv8_VD https://t.me/Priv8_VD
   Discord        : @VD.Priv8 https://discord.com/users/1296831918989639721
   E-mail         : vd.priv8@pm.me
  ======================================================================
-->

# VDLiveUpdate

> **Languages:** [English](README.md) · [العربية](README.ar.md) · [Čeština](README.cs.md) · [Deutsch](README.de.md) · [Español](README.es.md) · [فارسی](README.fa.md) · [Français](README.fr.md) · [हिन्दी](README.hi.md) · [Bahasa Indonesia](README.id.md) · [Italiano](README.it.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Nederlands](README.nl.md) · [Polski](README.pl.md) · [Português](README.pt.md) · [Русский](README.ru.md) · [Svenska](README.sv.md) · [ไทย](README.th.md) · [Türkçe](README.tr.md) · [Українська](README.uk.md) · [Tiếng Việt](README.vi.md) · [中文](README.zh.md)

**VDLU** is a flashless, incremental self-update engine for **KernelSU / APatch / Magisk** modules. An installed module updates itself by fetching **only the files that changed** (content-addressed blobs + a signed manifest), applies the live ones **without a reboot**, and stages and flags the few that do need one (a `.so`, a `/system` overlay, an `sepolicy.rule`). No root manager, no re-downloading the whole `.zip`, no reboot except for those staged files.

It is designed to be **vendored** into a module (dropped into `<module>/vdlu/`), not run as a module itself.

## Why

A normal module update ships the whole `.zip` again. For a large module that means a big re-download for a few changed lines, and a static update manifest can only point at one `zipUrl`, so it cannot serve the flavor (ABI, full vs lite) the device actually has. VDLU diffs the **installed** tree against a signed feed and fetches only the deltas, so an arm64-full install stays arm64-full, a lite install stays lite, and most updates apply live.

## How it works

- **Producer (PC / release):** `vdlu-pack` turns a module tree into a content-addressed feed (`manifest.json` + `blobs/<sha256>`, gzip, dedup, `delete[]`); `vdlu-keygen` / `vdlu-sign` (ed25519); `vdlu-gc` prunes orphan blobs by reference to the last N manifests (fail-safe, dry-run by default).
- **Engine (device):** POSIX sh, no `jq`. `update.sh` (`check | run | resume | boot | status | cancel`) runs DIFF -> FETCH -> APPLY -> COMMIT as a **resumable transaction** (journal), with rollback and an `mkdir` lock. Signature is verified by the embedded `ed25519-mini` (no `openssl` on device).
- **WebUI:** a drop-in Updates panel (progress toast, cancel, reboot banner), vanilla JS.

## Profiles

- `trusted`: private use, `file://` or SSH source, best-effort verify (hash always).
- `hardened`: public use, **signature mandatory**, downgrade blocked. The manifest is **bound to the module id**, and every field is validated fail-closed before anything is downloaded.

## Adopt it in your module

Vendor `engine/update.sh` + `vdlu-verify` + `verify/<abi>/ed25519-mini` into `<module>/vdlu/`, embark your **raw 32-byte public key** as `vdlu/keyring/<id>.pub`, add a `config` (profile + source), wire the triggers (`post-fs-data.sh` pre-zygote for auto-update on boot; a WebUI-open trigger), and add `vdlu-pack` + `vdlu-sign` to your release. See [`docs/QUICKSTART.md`](docs/QUICKSTART.md) for a worked template.

## Security

- **Every manifest field is hostile input.** `validate_plan()` rejects the whole manifest fail-closed on an absolute or `..` path, a `sha256` that is not 64 hex chars, or an invalid mode / class / encoding, **before** any fetch or apply.
- The **private signing key never touches CI or a device**; only the raw public key is embedded, and verification uses `ed25519-mini`, not `openssl`.
- `hardened` is fail-closed by inversion: anything other than the literal `trusted` is treated as `hardened`, so a corrupted profile value can never silently accept an unsigned manifest.
- Reboot-class files (`.so`, `/system` overlay, `sepolicy.rule`) are **staged, never written over a live inode**; everything else applies live. A failed apply aborts rather than overwrite without a backup.

## Build / test

It is scripts, nothing to compile. End-to-end (producer + engine together):

```sh
producer/vdlu-keygen demo /tmp/k
producer/vdlu-pack /tmp/tree /tmp/feed demo 1 --version-name v1
producer/vdlu-sign /tmp/feed/manifest.json /tmp/k/demo.pem demo
VDLU_DIR=... MODULE_DIR=... MODID=demo sh engine/update.sh check   # then run / boot
```

`sh -n engine/*.sh`, `node --check webui/vdlu.js`, and open `webui/demo.html` in a browser (it mocks the device bridge).

## Documentation

- [`INTERFACES.md`](docs/INTERFACES.md): the seam contract between the components (the law of convergence; treat it as immutable).
- [`ENGINE.md`](docs/ENGINE.md): the device-side engine (`update.sh`): the resumable DIFF -> FETCH -> APPLY -> COMMIT transaction.
- [`PRODUCER.md`](docs/PRODUCER.md): the PC / release side: building and signing the content-addressed feed (`vdlu-pack`, `vdlu-sign`).
- [`WEBUI.md`](docs/WEBUI.md): the drop-in Updates panel widget (progress toast, cancel, reboot banner).
- [`docs/QUICKSTART.md`](docs/QUICKSTART.md): a step-by-step adoption guide and wiring snippets.

## See also

Sibling projects by the same author:

- **[VDInfos](https://github.com/VD171/VD-Infos)**: a device method debugger that reads each item through every method that can read it.
- **[VDGoogle](https://github.com/VD171/VD-Google)**: reads what Google records on your device, fully on-device and with no internet.
- **[COPG-VD](https://github.com/VD171/COPG-VD)**: a device spoofer that turns a fresh fingerprint into a coherent, consistent profile.
- **[VD-dropbear](https://github.com/VD171/VD-dropbear)**: a standalone, configurable rooted SSH daemon for KernelSU/APatch/Magisk.
- **[VDBackup](https://github.com/VD171/VD-Backup)**: full app and data backup and restore as root, driven entirely from a WebUI.
- **[VDInstaller](https://github.com/VD171/VD-Installer)**: a frictionless root sideload installer for single, batch and split APKs, with a Play Protect verifier toggle and install-source spoofing.

## Contacts

- https://vd171.ru
- https://vd.priv8.ru
- **Telegram:** @VD_Priv8 https://t.me/VD_Priv8
- **Channel:** @Priv8_VD https://t.me/Priv8_VD
- **Discord:** @VD.Priv8 https://discord.com/users/1296831918989639721
- **E-mail:** vd.priv8@pm.me
- **XDA-Developers:** @VD171 https://xdaforums.com/m/vd171.4699873/
- **GitHub:** @VD171 https://github.com/VD171

## License

VDLiveUpdate's own code is **Apache-2.0**; see [LICENSE](LICENSE). It vendors a small `ed25519-mini`
verifier and a static `curl` for the fetch bootstrap, each under its own license; see
[NOTICE.md](NOTICE.md) and the `PROVENANCE.json` files next to the bundled binaries.

## Trademarks

VDLiveUpdate is an independent, unofficial project, not affiliated with or endorsed by any third party.
"Android" is a trademark of Google LLC; "KernelSU", "Magisk" and "APatch" are the marks of their
respective authors. VDLU runs entirely on your device and on your own release host.

## Tags

`VDLU` `flashless-update` `incremental-update` `KernelSU` `Magisk` `APatch` `module-update` `ed25519` `content-addressed` `OTA` `self-update` `Android` `VDLiveUpdate`

---

📣 **Join the channel for updates:** @Priv8_VD https://t.me/Priv8_VD
