# Quick Start

This is the adoption checklist: how to vendor **VDLiveUpdate (VDLU)** into a
KernelSU / APatch / Magisk module. VDLU is not a module itself. It is dropped into
`<module>/vdlu/` and ships inside your module's zip, so an installed module can
update itself flashlessly from a signed feed you publish.

Throughout, replace `<id>` with your signing-key id, `<abi>` with the device
ABI(s) you ship (`arm64-v8a`, `armeabi-v7a`, `x86_64`, `x86`), and `<module>`
with your module tree.

For the rationale behind each piece, see [[Engine]], [[Producer]], [[WebUI]] and
[[Security and Trust Model]].

## The in-module `vdlu/` layout

This is the exact tree your module carries after adoption:

```
<module>/
|-- module.prop
|-- post-fs-data.sh            # pre-zygote trigger: sh "$MODDIR/vdlu/update.sh" boot
|-- webroot/
|   `-- index.html             # your WebUI, wiring the Updates panel (step 5)
`-- vdlu/
    |-- update.sh              # the engine (vendored byte-for-byte)
    |-- vdlu-verify            # ed25519 verify shim (device-side, no openssl)
    |-- verify/
    |   `-- <abi>/ed25519-mini # per-ABI verifier binary
    |-- keyring/
    |   `-- <id>.pub           # RAW 32-byte public key (NEVER the PEM)
    |-- config.default         # profile + source + automation defaults
    `-- baseline.json          # install seed (unsigned, keyless)
```

The engine's mutable state (`config`, `current.json`, journal, lock, blob cache)
lives in Tier-2 at `/data/adb/<modid>/vdlu/`, outside the module directory.
`config.default` seeds that Tier-2 `config` on first run. See [[Engine]] for the
full state layout.

## 1. Vendor the engine

Copy the engine, the verify shim and the per-ABI verifier binary into
`<module>/vdlu/`:

```sh
mkdir -p <module>/vdlu/verify
cp engine/update.sh   <module>/vdlu/update.sh
cp engine/vdlu-verify <module>/vdlu/vdlu-verify
cp -r verify/<abi>    <module>/vdlu/verify/<abi>    # ed25519-mini per ABI
```

Ship only the ABIs you support. Your `customize.sh` can prune `verify/` down to
the device's ABI at install time.

## 2. Generate a signing key (one-time)

```sh
producer/vdlu-keygen <id> ./keys
```

This emits three files:

- `<id>.pem` - the private key. Keep it off every device and out of any repo
  push or CI secret.
- `<id>.pub` - the PEM public key. PC-side only (used by `vdlu-sign`).
- `<id>.pub.raw` - the RAW 32-byte public key, for the device keyring.

See [[Security and Trust Model]] for why the split matters.

## 3. Embed the raw public key

The device keyring holds the **RAW 32-byte** key, never the PEM. `ed25519-mini`
cannot read a PEM, so copying the PEM here breaks on-device verification:

```sh
mkdir -p <module>/vdlu/keyring
cp ./keys/<id>.pub.raw <module>/vdlu/keyring/<id>.pub
```

The keyring is stable across releases: it only changes on key rotation. On a
re-vendor, **verify it, do not overwrite it**.

## 4. Write the config

Ship `config.default` in `<module>/vdlu/`. It seeds the Tier-2 `config` on first
run:

```
auto_on_reboot=1
auto_on_webui_open=1
source=https://<user>.github.io/<repo>/<module>
channel=stable
profile=hardened        # public feed: signature mandatory, downgrade blocked
net_policy=any
pubkey_dir=keyring
```

Use `profile=trusted` only for a private `file://` or SSH source (verify is
best-effort there, but every blob's sha256 is still checked). Any value other
than the literal `trusted` is treated as `hardened`, fail-closed. See
[[Security and Trust Model]] for the full profile semantics.

## 5. Wire the triggers

**On reboot** (`auto_on_reboot`): call the engine pre-zygote from
`post-fs-data.sh`, so staged reboot-class files (a `.so`, a `/system` overlay,
an `sepolicy.rule`) swap in with no extra reboot:

```sh
# <module>/post-fs-data.sh
MODDIR=${0%/*}
sh "$MODDIR/vdlu/update.sh" boot
```

**On WebUI open** (`auto_on_webui_open`): wire the drop-in Updates panel in your
`webroot/index.html`:

```html
<link rel="stylesheet" href="vdlu.css">
<script src="vdlu.js"></script>
<script>
  VDLU.init({
    moduleDir: '/data/adb/modules/' + MODID,
    vdluDir:   '/data/adb/' + MODID + '/vdlu',
    modid:     MODID,
    module:    'YourModule'
  });
  VDLU.onWebUIOpen();                                            // journal + banner + auto_on_webui_open
  VDLU.mountUpdatesPanel(document.getElementById('b-updates'));  // the "Updates" tab
</script>
```

`vdlu.js` and `vdlu.css` are vendored from `webui/`. A translation can be added
with `i18n: window.VDLU_I18N_<LANG>`. See [[WebUI]] for the panel contract.

## 6. Sign the feed in your release workflow

Each release, pack the final module tree and sign the manifest. Keep the private
key on the operator machine, never in CI:

```sh
producer/vdlu-pack  <module>  ./out  <module> <versionCode> \
                    --version-name v<versionCode> --channel stable \
                    [--prev ./prev/manifest.json]      # delete[] = paths gone since prev
producer/vdlu-sign  ./out/manifest.json  ./keys/<id>.pem  <id>
# publish ./out/{manifest.json,blobs/} to <source>
```

`vdlu-pack` is content-addressed and deduplicating, so publishing is incremental:
unchanged blobs are never re-pushed. See [[Producer]] and [[Feed Format]].

## 7. Ship the baseline

Generate `baseline.json` over the shipped tree and place it at
`<module>/vdlu/baseline.json`. It seeds `current.json` on a fresh install, so the
device is born "current" and does not re-fetch its own shipped version. It is a
**local trusted seed**: unsigned and keyless, so CI can build it without ever
touching the signing key:

```sh
producer/vdlu-pack  <module>  ./seed  <module> <versionCode> --version-name v<versionCode>
cp ./seed/manifest.json <module>/vdlu/baseline.json
```

It is non-fatal if absent: the device simply starts from version `0` on the
first update.

---

That is the whole adoption. Before you ship, `sh -n <module>/vdlu/update.sh`
must pass, and you should test the producer and engine end-to-end as shown in
[[Contributing]] and [[Producer]].
