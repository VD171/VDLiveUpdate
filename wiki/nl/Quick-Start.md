# Quick Start

Dit is de adoptie-checklist: hoe je **VDLiveUpdate (VDLU)** in een
KernelSU- / APatch- / Magisk-module vendort. VDLU is zelf geen module. Het wordt gedropt in
`<module>/vdlu/` en levert mee binnen de zip van je module, zodat een geinstalleerde module zich
flashloos kan bijwerken van een gesigneerde feed die je publiceert.

Vervang overal `<id>` door je signeringssleutel-id, `<abi>` door de ABI(('s)
van het apparaat die je meelevert (`arm64-v8a`, `armeabi-v7a`, `x86_64`, `x86`), en `<module>`
door je moduleboom.

Voor de rationale achter elk onderdeel, zie [[Engine]], [[Producer]], [[WebUI]] en
[[Security and Trust Model]].

## De in-module `vdlu/`-indeling

Dit is de exacte boom die je module draagt na adoptie:

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

De muteerbare toestand van de engine (`config`, `current.json`, journal, lock, blob-cache)
leeft in Tier-2 op `/data/adb/<modid>/vdlu/`, buiten de moduledirectory.
`config.default` seedt die Tier-2-`config` bij de eerste run. Zie [[Engine]] voor de
volledige toestandsindeling.

## 1. Vendor de engine

Kopieer de engine, de verify-shim en het per-ABI-verifier-binary in
`<module>/vdlu/`:

```sh
mkdir -p <module>/vdlu/verify
cp engine/update.sh   <module>/vdlu/update.sh
cp engine/vdlu-verify <module>/vdlu/vdlu-verify
cp -r verify/<abi>    <module>/vdlu/verify/<abi>    # ed25519-mini per ABI
```

Lever alleen de ABI's mee die je ondersteunt. Je `customize.sh` kan `verify/` terugsnoeien tot
de ABI van het apparaat op install-tijd.

## 2. Genereer een signeringssleutel (eenmalig)

```sh
producer/vdlu-keygen <id> ./keys
```

Dit zendt drie bestanden uit:

- `<id>.pem` - de private sleutel. Houd hem van elk apparaat en buiten elke repo-push
  of CI-secret.
- `<id>.pub` - de PEM publieke sleutel. Alleen pc-zijdig (gebruikt door `vdlu-sign`).
- `<id>.pub.raw` - de RAUWE publieke sleutel van 32 bytes, voor de keyring van het apparaat.

Zie [[Security and Trust Model]] voor waarom de splitsing ertoe doet.

## 3. Bed de rauwe publieke sleutel in

De keyring van het apparaat houdt de **RAUWE 32-byte**-sleutel, nooit de PEM. `ed25519-mini`
kan geen PEM lezen, dus de PEM hierheen kopiëren breekt verificatie op het apparaat:

```sh
mkdir -p <module>/vdlu/keyring
cp ./keys/<id>.pub.raw <module>/vdlu/keyring/<id>.pub
```

De keyring is stabiel over releases heen: die verandert alleen bij sleutelrotatie. Bij een
opnieuw vendoren, **verifieer hem, overschrijf hem niet**.

## 4. Schrijf de config

Lever `config.default` mee in `<module>/vdlu/`. Het seedt de Tier-2-`config` bij de eerste
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

Gebruik `profile=trusted` alleen voor een private `file://`- of SSH-bron (verify is
daar best-effort, maar de sha256 van elke blob wordt nog steeds gecontroleerd). Elke andere waarde
dan het letterlijke `trusted` wordt als `hardened` behandeld, fail-closed. Zie
[[Security and Trust Model]] voor de volledige profielsemantiek.

## 5. Bedraad de triggers

**Bij herstart** (`auto_on_reboot`): roep de engine pre-zygote aan vanuit
`post-fs-data.sh`, zodat gefaseerde bestanden van de herstartklasse (een `.so`, een `/system`-overlay,
een `sepolicy.rule`) inwisselen zonder extra herstart:

```sh
# <module>/post-fs-data.sh
MODDIR=${0%/*}
sh "$MODDIR/vdlu/update.sh" boot
```

**Bij WebUI-open** (`auto_on_webui_open`): bedraad het drop-in Updates-paneel in je
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

`vdlu.js` en `vdlu.css` worden gevendord vanuit `webui/`. Een vertaling kan worden toegevoegd
met `i18n: window.VDLU_I18N_<LANG>`. Zie [[WebUI]] voor het paneelcontract.

## 6. Signeer de feed in je release-workflow

Pack bij elke release de definitieve moduleboom en signeer het manifest. Houd de private
sleutel op de operator-machine, nooit in CI:

```sh
producer/vdlu-pack  <module>  ./out  <module> <versionCode> \
                    --version-name v<versionCode> --channel stable \
                    [--prev ./prev/manifest.json]      # delete[] = paths gone since prev
producer/vdlu-sign  ./out/manifest.json  ./keys/<id>.pem  <id>
# publish ./out/{manifest.json,blobs/} to <source>
```

`vdlu-pack` is inhoudsgeadresseerd en dedupliceert, zodat publiceren incrementeel is:
ongewijzigde blobs worden nooit herpusht. Zie [[Producer]] en [[Feed Format]].

## 7. Lever de baseline mee

Genereer `baseline.json` over de meegeleverde boom en plaats die op
`<module>/vdlu/baseline.json`. Het seedt `current.json` bij een verse installatie, zodat het
apparaat "current" wordt geboren en zijn eigen meegeleverde versie niet herdownloadt. Het is een
**lokale vertrouwde seed**: ongesigneerd en keyless, zodat CI het kan bouwen zonder ooit
de signeringssleutel aan te raken:

```sh
producer/vdlu-pack  <module>  ./seed  <module> <versionCode> --version-name v<versionCode>
cp ./seed/manifest.json <module>/vdlu/baseline.json
```

Het is niet-fataal indien afwezig: het apparaat start simpelweg vanaf versie `0` bij de
eerste update.

---

Dat is de hele adoptie. Voordat je meelevert, moet `sh -n <module>/vdlu/update.sh`
slagen, en zou je de producer en engine end-to-end moeten testen zoals getoond in
[[Contributing]] en [[Producer]].
