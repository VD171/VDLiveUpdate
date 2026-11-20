> **Languages:** [English](../QUICKSTART.md) · [العربية](../ar/QUICKSTART.md) · [Čeština](../cs/QUICKSTART.md) · [Deutsch](../de/QUICKSTART.md) · [Español](../es/QUICKSTART.md) · [فارسی](../fa/QUICKSTART.md) · [Français](../fr/QUICKSTART.md) · [हिन्दी](../hi/QUICKSTART.md) · [Bahasa Indonesia](../id/QUICKSTART.md) · [Italiano](../it/QUICKSTART.md) · [日本語](../ja/QUICKSTART.md) · [한국어](../ko/QUICKSTART.md) · Nederlands · [Polski](../pl/QUICKSTART.md) · [Português](../pt/QUICKSTART.md) · [Русский](../ru/QUICKSTART.md) · [Svenska](../sv/QUICKSTART.md) · [ไทย](../th/QUICKSTART.md) · [Türkçe](../tr/QUICKSTART.md) · [Українська](../uk/QUICKSTART.md) · [Tiếng Việt](../vi/QUICKSTART.md) · [中文](../zh/QUICKSTART.md)

---

# VDLU-adoptie-quickstart

Een kopieer-plak-checklist om **VDLiveUpdate** in een module te vendoren. VDLU is zelf geen
module: het wordt in `<module>/vdlu/` neergezet en gaat mee in de zip van je module. Voor de
volledige rationale zie [`INTERFACES.md`](INTERFACES.md) (het naadcontract),
[`ENGINE.md`](ENGINE.md), [`PRODUCER.md`](PRODUCER.md) en [`WEBUI.md`](WEBUI.md).

Vervang `<id>` door het id van je signeersleutel, `<abi>` door de toestel-ABI('s) die je
levert (`arm64-v8a`, `armeabi-v7a`, `x86_64`, `x86`), en `<module>` door je moduleboom.

## Doel-layout

Dit is de exacte `vdlu/`-boom die de module na adoptie draagt:

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

De muteerbare toestand van de engine (`config`, `current.json`, journal, lock) leeft in
Tier-2, `/data/adb/<modid>/vdlu/`, buiten de module-dir; `config.default` seedt hem bij de
eerste run.

## 1. Vendor de engine

Kopieer de engine, de verify-shim en de per-ABI-verifier naar `<module>/vdlu/`:

```sh
mkdir -p <module>/vdlu/verify
cp engine/update.sh      <module>/vdlu/update.sh
cp engine/vdlu-verify    <module>/vdlu/vdlu-verify
cp -r verify/<abi>       <module>/vdlu/verify/<abi>      # ed25519-mini per ABI
```

Lever alleen de ABI's die je ondersteunt; `customize.sh` kan `verify/` bij installatietijd
snoeien tot de ABI van het toestel.

## 2. Genereer een signeersleutel (eenmalig)

```sh
producer/vdlu-keygen <id> ./keys
```

Dit levert `<id>.pem` (privé, houd hem van elk toestel en van elke repo-push af),
`<id>.pub` (PEM, alleen PC-zijdig) en `<id>.pub.raw` (RAW 32 byte, voor de toestel-keyring).

## 3. Embed de raw publieke sleutel

De toestel-keyring houdt de **RAW 32-byte** sleutel, nooit de PEM (`ed25519-mini`
kan geen PEM lezen):

```sh
mkdir -p <module>/vdlu/keyring
cp ./keys/<id>.pub.raw <module>/vdlu/keyring/<id>.pub
```

De keyring is stabiel over releases heen (hij verandert alleen bij sleutelrotatie): bij een
her-vendor, **verifieer, niet overschrijven**.

## 4. Schrijf de config

Lever `config.default` in `<module>/vdlu/` (seedt de Tier-2-`config` bij de eerste run):

```
auto_on_reboot=1
auto_on_webui_open=1
source=https://<user>.github.io/<repo>/<module>
channel=stable
profile=hardened        # public feed: signature mandatory, downgrade blocked
net_policy=any
pubkey_dir=keyring
```

Gebruik `profile=trusted` alleen voor een privé `file://`/SSH-bron (verify best-effort;
de sha256 van elke blob wordt nog steeds gecontroleerd). Elke waarde anders dan de letterlijke
`trusted` wordt behandeld als `hardened` (fail-closed).

## 5. Bedraad de triggers

**Bij reboot** (`auto_on_reboot`): roep de engine pre-zygote aan vanuit `post-fs-data.sh`
zodat gestagede bestanden (een `.so`, een `/system`-overlay, een `sepolicy.rule`) inwisselen
zonder extra reboot:

```sh
# <module>/post-fs-data.sh
MODDIR=${0%/*}
sh "$MODDIR/vdlu/update.sh" boot
```

**Bij WebUI-opening** (`auto_on_webui_open`): bedraad het kant-en-klare Updates-paneel in je
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

(`vdlu.js` / `vdlu.css` worden gevendord uit `webui/`; een vertaling kan worden toegevoegd met
`i18n: window.VDLU_I18N_<LANG>`.)

## 6. Teken de feed in je release-workflow

Bij elke release, pack de uiteindelijke moduleboom en teken het manifest. Houd de privésleutel
op de operatormachine, nooit in CI:

```sh
producer/vdlu-pack  <module>  ./out  <module> <versionCode> --version-name v<versionCode> --channel stable \
                    [--prev ./prev/manifest.json]        # delete[] = paths gone since prev
producer/vdlu-sign  ./out/manifest.json  ./keys/<id>.pem  <id>
# publish ./out/{manifest.json,blobs/} to <source>
```

## 7. Lever de baseline

Genereer `baseline.json` over de geleverde boom en plaats hem op `<module>/vdlu/baseline.json`.
Hij seedt `current.json` bij een verse installatie zodat het toestel "current" wordt geboren
(geen her-fetch). Het is een **lokale vertrouwde seed**: ongetekend en sleutelloos, zodat CI
hem kan bouwen zonder ooit de signeersleutel aan te raken:

```sh
producer/vdlu-pack  <module>  ./seed  <module> <versionCode> --version-name v<versionCode>
cp ./seed/manifest.json <module>/vdlu/baseline.json
```

Het is niet-fataal indien afwezig (het toestel begint gewoon vanaf `0` bij de eerste update).

---

Dat is de hele adoptie. `sh -n <module>/vdlu/update.sh` moet slagen; test de
producer en engine end-to-end zoals getoond in [`PRODUCER.md`](PRODUCER.md) en de
root-README voordat je levert.

<!-- doc-footer -->

---

> _Deze documentatie is gegenereerd met Claude (Anthropic) en wordt onderhouden door VD171. Correcties en verbeteringen zijn welkom; zie [CONTRIBUTING.md](CONTRIBUTING.md)._
