> **Languages:** English · [العربية](ar/QUICKSTART.md) · [Čeština](cs/QUICKSTART.md) · [Deutsch](de/QUICKSTART.md) · [Español](es/QUICKSTART.md) · [فارسی](fa/QUICKSTART.md) · [Français](fr/QUICKSTART.md) · [हिन्दी](hi/QUICKSTART.md) · [Bahasa Indonesia](id/QUICKSTART.md) · [Italiano](it/QUICKSTART.md) · [日本語](ja/QUICKSTART.md) · [한국어](ko/QUICKSTART.md) · [Nederlands](nl/QUICKSTART.md) · [Polski](pl/QUICKSTART.md) · [Português](pt/QUICKSTART.md) · [Русский](ru/QUICKSTART.md) · [Svenska](sv/QUICKSTART.md) · [ไทย](th/QUICKSTART.md) · [Türkçe](tr/QUICKSTART.md) · [Українська](uk/QUICKSTART.md) · [Tiếng Việt](vi/QUICKSTART.md) · [中文](zh/QUICKSTART.md)

---

# VDLU adoption quickstart

A copy-paste checklist for vendoring **VDLiveUpdate** into a module. VDLU is not a
module itself: it is dropped into `<module>/vdlu/` and ships inside your module's zip.
For the full rationale see [`INTERFACES.md`](INTERFACES.md) (the seam contract),
[`ENGINE.md`](ENGINE.md), [`PRODUCER.md`](PRODUCER.md) and [`WEBUI.md`](WEBUI.md).

Replace `<id>` with your signing-key id, `<abi>` with the device ABI(s) you ship
(`arm64-v8a`, `armeabi-v7a`, `x86_64`, `x86`), and `<module>` with your module tree.

## Target layout

This is the exact `vdlu/` tree the module carries after adoption:

```
<module>/
├── module.prop
├── post-fs-data.sh            # pre-zygote trigger: sh "$MODDIR/vdlu/update.sh" boot
├── webroot/
│   └── index.html             # your WebUI, wiring the Updates panel (step 5)
└── vdlu/
    ├── update.sh              # the engine (vendored byte-for-byte)
    ├── vdlu-verify            # ed25519 verify shim (device-side, no openssl)
    ├── verify/
    │   └── <abi>/ed25519-mini # per-ABI verifier binary
    ├── keyring/
    │   └── <id>.pub           # RAW 32-byte public key (NEVER the PEM)
    ├── config.default         # profile + source + automation defaults
    └── baseline.json          # install seed (unsigned, keyless)
```

The engine's mutable state (`config`, `current.json`, journal, lock) lives in
Tier-2, `/data/adb/<modid>/vdlu/`, outside the module dir; `config.default` seeds it
on first run.

## 1. Vendor the engine

Copy the engine, the verify shim and the per-ABI verifier into `<module>/vdlu/`:

```sh
mkdir -p <module>/vdlu/verify
cp engine/update.sh      <module>/vdlu/update.sh
cp engine/vdlu-verify    <module>/vdlu/vdlu-verify
cp -r verify/<abi>       <module>/vdlu/verify/<abi>      # ed25519-mini per ABI
```

Ship only the ABIs you support; `customize.sh` can prune `verify/` to the device's
ABI at install time.

## 2. Generate a signing key (one-time)

```sh
producer/vdlu-keygen <id> ./keys
```

This emits `<id>.pem` (private, keep it off every device and off any repo push),
`<id>.pub` (PEM, PC-side only) and `<id>.pub.raw` (RAW 32 bytes, for the device keyring).

## 3. Embed the raw public key

The device keyring holds the **RAW 32-byte** key, never the PEM (`ed25519-mini`
cannot read a PEM):

```sh
mkdir -p <module>/vdlu/keyring
cp ./keys/<id>.pub.raw <module>/vdlu/keyring/<id>.pub
```

The keyring is stable across releases (it only changes on key rotation): on a
re-vendor, **verify, do not overwrite** it.

## 4. Write the config

Ship `config.default` in `<module>/vdlu/` (seeds the Tier-2 `config` on first run):

```
auto_on_reboot=1
auto_on_webui_open=1
source=https://<user>.github.io/<repo>/<module>
channel=stable
profile=hardened        # public feed: signature mandatory, downgrade blocked
net_policy=any
pubkey_dir=keyring
```

Use `profile=trusted` only for a private `file://`/SSH source (verify best-effort;
every blob's sha256 is still checked). Any value other than the literal `trusted`
is treated as `hardened` (fail-closed).

## 5. Wire the triggers

**On reboot** (`auto_on_reboot`): call the engine pre-zygote from `post-fs-data.sh`
so staged files (a `.so`, a `/system` overlay, an `sepolicy.rule`) swap in with no
extra reboot:

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
  VDLU.onWebUIOpen();                                             // evaluates journal + banner + auto_on_webui_open
  VDLU.mountUpdatesPanel(document.getElementById('b-updates'));  // the "Updates" tab
</script>
```

(`vdlu.js` / `vdlu.css` are vendored from `webui/`; a translation can be added with
`i18n: window.VDLU_I18N_<LANG>`.)

## 6. Sign the feed in your release workflow

Each release, pack the final module tree and sign the manifest. Keep the private key
on the operator machine, never in CI:

```sh
producer/vdlu-pack  <module>  ./out  <module> <versionCode> --version-name v<versionCode> --channel stable \
                    [--prev ./prev/manifest.json]        # delete[] = paths gone since prev
producer/vdlu-sign  ./out/manifest.json  ./keys/<id>.pem  <id>
# publish ./out/{manifest.json,blobs/} to <source>
```

## 7. Ship the baseline

Generate `baseline.json` over the shipped tree and place it at `<module>/vdlu/baseline.json`.
It seeds `current.json` on a fresh install so the device is born "current" (no
re-fetch). It is a **local trusted seed**: unsigned and keyless, so CI can build it
without ever touching the signing key:

```sh
producer/vdlu-pack  <module>  ./seed  <module> <versionCode> --version-name v<versionCode>
cp ./seed/manifest.json <module>/vdlu/baseline.json
```

It is non-fatal if absent (the device just starts from `0` on the first update).

---

That is the whole adoption. `sh -n <module>/vdlu/update.sh` must pass; test the
producer and engine end-to-end as shown in [`PRODUCER.md`](PRODUCER.md) and the
root README before you ship.

<!-- doc-footer -->

---

> _This documentation was generated with Claude (Anthropic) and is maintained by VD171. Corrections and improvements are welcome; see [CONTRIBUTING.md](../CONTRIBUTING.md)._
