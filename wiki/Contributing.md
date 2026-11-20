# Contributing

Contributions are welcome. VDLU is a flashless, incremental self-update engine
vendored into KernelSU / APatch / Magisk modules. This page is the practical dev
workflow; for how the pieces fit, read [[Architecture]], [[Engine]] and
[[Producer]] first.

## Nothing compiles

VDLU is scripts (POSIX sh, a little Python on the release side, vanilla JS for the
WebUI), so there is no build step. You verify a change by running the pipeline
end-to-end and by static-checking each piece.

## Seam contract first

The interface contract between the components (the CLI signatures, file names and
JSON keys shared by the engine, the producer and the WebUI) is the **law of
convergence**. Treat it as immutable. If your change touches the
producer-to-engine seam (manifest schema, journal schema, config keys, the
signature/canonicalization rule), **align the interface contract first**, then
change the code on both sides to match. A change on one side of the seam without
the other silently breaks adopters. See [[Producer]] for the canonicalization
rule the signer and verifier must agree on byte-for-byte.

## Test end-to-end before a PR

Run the producer and the engine together on a throwaway tree, the same way an
adopter's release does:

```sh
# 1. a signing key
producer/vdlu-keygen demo /tmp/k

# 2. pack a module tree into a feed
producer/vdlu-pack /tmp/tree /tmp/feed demo 1 --version-name v1

# 3. sign the manifest in place
producer/vdlu-sign /tmp/feed/manifest.json /tmp/k/demo.pem demo

# 4. verify the manifest the way the device will (RAW 32B keyring)
engine/vdlu-verify /tmp/feed/manifest.json /tmp/keyring

# 5. drive the engine against the feed (source=file:///tmp/feed in the config)
VDLU_DIR=... MODULE_DIR=... MODID=demo sh engine/update.sh check   # then run / boot
```

Then static-check each component:

```sh
sh -n engine/*.sh            # POSIX sh syntax, must pass
node --check webui/vdlu.js   # WebUI JS syntax
```

And open `webui/demo.html` in a browser: it mocks the root-manager bridge
(`ksu.exec`), so you can exercise the Updates panel, the progress toast, cancel
and the reboot banner with no device. See [[WebUI]].

## House rules

- **POSIX sh on the device.** No bashisms beyond `local`, and no `jq`. It has to
  run on toybox / busybox.
- **Security is non-negotiable.** Every manifest field is hostile input;
  `validate_plan()` stays fail-closed, and the private signing key never touches
  CI or a device. Do not loosen a check to make a test pass.
- **Rigor on failure.** Keep the transaction resumable: nothing reports "done"
  without a matching re-hash, nothing is overwritten without a backup, and
  applies stay atomic.
- **Always release quality.** Keep comments terse; no gratuitous comments.
- **One logical change per PR.** Say what changed and why.

## Filing issues

Open an issue describing what you did, what you expected, and what happened.
For a bug, include the module id, the source profile (`hardened` or `trusted`),
the `update.sh` command you ran, and the relevant `journal.json` (it records the
phase, state and error). For a feature, say which component it touches (engine,
producer, or WebUI) so the seam impact is clear up front.
