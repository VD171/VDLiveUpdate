> **Languages:** [English](../QUICKSTART.md) · [العربية](../ar/QUICKSTART.md) · [Čeština](../cs/QUICKSTART.md) · [Deutsch](../de/QUICKSTART.md) · [Español](../es/QUICKSTART.md) · [فارسی](../fa/QUICKSTART.md) · [Français](../fr/QUICKSTART.md) · [हिन्दी](../hi/QUICKSTART.md) · [Bahasa Indonesia](../id/QUICKSTART.md) · [Italiano](../it/QUICKSTART.md) · [日本語](../ja/QUICKSTART.md) · [한국어](../ko/QUICKSTART.md) · [Nederlands](../nl/QUICKSTART.md) · [Polski](../pl/QUICKSTART.md) · [Português](../pt/QUICKSTART.md) · [Русский](../ru/QUICKSTART.md) · Svenska · [ไทย](../th/QUICKSTART.md) · [Türkçe](../tr/QUICKSTART.md) · [Українська](../uk/QUICKSTART.md) · [Tiếng Việt](../vi/QUICKSTART.md) · [中文](../zh/QUICKSTART.md)

---

# VDLU-adoptions-quickstart

En kopiera-klistra-checklista för att vendora **VDLiveUpdate** in i en modul. VDLU är inte en
modul i sig: den släpps in i `<module>/vdlu/` och levereras inuti din moduls zip. För den
fullständiga motiveringen se [`INTERFACES.md`](INTERFACES.md) (sömkontraktet),
[`ENGINE.md`](ENGINE.md), [`PRODUCER.md`](PRODUCER.md) och [`WEBUI.md`](WEBUI.md).

Ersätt `<id>` med din signeringsnyckels id, `<abi>` med enhets-ABI:erna du levererar
(`arm64-v8a`, `armeabi-v7a`, `x86_64`, `x86`), och `<module>` med ditt modulträd.

## Mål-layout

Detta är det exakta `vdlu/`-trädet som modulen bär efter adoption:

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

Engines muteringsbara tillstånd (`config`, `current.json`, journal, lock) bor i
Tier-2, `/data/adb/<modid>/vdlu/`, utanför modul-dir:en, `config.default` seedar det vid första
körningen.

## 1. Vendora engine

Kopiera engine, verify-shimmen och per-ABI-verifieraren till `<module>/vdlu/`:

```sh
mkdir -p <module>/vdlu/verify
cp engine/update.sh      <module>/vdlu/update.sh
cp engine/vdlu-verify    <module>/vdlu/vdlu-verify
cp -r verify/<abi>       <module>/vdlu/verify/<abi>      # ed25519-mini per ABI
```

Leverera endast de ABI:er du stödjer, `customize.sh` kan beskära `verify/` till enhetens ABI
vid installationstid.

## 2. Generera en signeringsnyckel (engångs)

```sh
producer/vdlu-keygen <id> ./keys
```

Detta avger `<id>.pem` (privat, håll den borta från varje enhet och från varje repo-push),
`<id>.pub` (PEM, endast PC-sidig) och `<id>.pub.raw` (RAW 32 byte, för enhetens keyring).

## 3. Bädda in den råa publika nyckeln

Enhetens keyring håller den **RAW 32-byte** nyckeln, aldrig PEM (`ed25519-mini`
kan inte läsa en PEM):

```sh
mkdir -p <module>/vdlu/keyring
cp ./keys/<id>.pub.raw <module>/vdlu/keyring/<id>.pub
```

Keyringen är stabil över releaser (den ändras bara vid nyckelrotation): vid en
om-vendoring, **verifiera, skriv inte över**.

## 4. Skriv config

Leverera `config.default` i `<module>/vdlu/` (seedar Tier-2-`config` vid första körningen):

```
auto_on_reboot=1
auto_on_webui_open=1
source=https://<user>.github.io/<repo>/<module>
channel=stable
profile=hardened        # public feed: signature mandatory, downgrade blocked
net_policy=any
pubkey_dir=keyring
# apply_busy_file=/data/adb/<modid>/.busy   # OPT-IN: defer APPLY while this path exists (e.g. a running backup)
```

Använd `profile=trusted` endast för en privat `file://`/SSH-källa (verify best-effort, varje
blobs sha256 kontrolleras fortfarande). Varje värde annat än det bokstavliga `trusted` behandlas
som `hardened` (fail-closed).

## 5. Koppla triggrarna

**Vid reboot** (`auto_on_reboot`): anropa engine pre-zygote från `post-fs-data.sh` så att
scenlagda filer (en `.so`, ett `/system`-overlay, en `sepolicy.rule`) byts in utan en extra
reboot:

```sh
# <module>/post-fs-data.sh
MODDIR=${0%/*}
sh "$MODDIR/vdlu/update.sh" boot
```

**Vid WebUI-öppning** (`auto_on_webui_open`): koppla in den färdiga Updates-panelen i din
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

(`vdlu.js` / `vdlu.css` vendoras från `webui/`, en översättning kan läggas till med
`i18n: window.VDLU_I18N_<LANG>`.)

## 6. Signera flödet i ditt release-workflow

Vid varje release, packa det slutliga modulträdet och signera manifestet. Håll den privata
nyckeln på operatormaskinen, aldrig i CI:

```sh
producer/vdlu-pack  <module>  ./out  <module> <versionCode> --version-name v<versionCode> --channel stable \
                    [--prev ./prev/manifest.json]        # delete[] = paths gone since prev
producer/vdlu-sign  ./out/manifest.json  ./keys/<id>.pem  <id>
# publish ./out/{manifest.json,blobs/} to <source>
```

## 7. Leverera baseline

Generera `baseline.json` över det levererade trädet och placera det vid
`<module>/vdlu/baseline.json`. Det seedar `current.json` vid en ny installation så att enheten
föds "aktuell" (ingen om-hämtning). Det är en **lokal betrodd seed**: osignerad och nyckellös,
så CI kan bygga det utan att någonsin röra signeringsnyckeln:

```sh
producer/vdlu-pack  <module>  ./seed  <module> <versionCode> --version-name v<versionCode>
cp ./seed/manifest.json <module>/vdlu/baseline.json
```

Det är icke-fatalt om det saknas (enheten börjar bara från `0` vid den första uppdateringen).

---

Det är hela adoptionen. `sh -n <module>/vdlu/update.sh` måste passera, testa producern
och engine från början till slut så som visas i [`PRODUCER.md`](PRODUCER.md) och root-README
innan du levererar.

<!-- doc-footer -->

---

> _Denna dokumentation genererades med Claude (Anthropic) och underhålls av VD171. Rättelser och förbättringar välkomnas, se [CONTRIBUTING.md](CONTRIBUTING.md)._
