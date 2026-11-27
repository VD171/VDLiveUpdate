> **Languages:** [English](../QUICKSTART.md) · [العربية](../ar/QUICKSTART.md) · Čeština · [Deutsch](../de/QUICKSTART.md) · [Español](../es/QUICKSTART.md) · [فارسی](../fa/QUICKSTART.md) · [Français](../fr/QUICKSTART.md) · [हिन्दी](../hi/QUICKSTART.md) · [Bahasa Indonesia](../id/QUICKSTART.md) · [Italiano](../it/QUICKSTART.md) · [日本語](../ja/QUICKSTART.md) · [한국어](../ko/QUICKSTART.md) · [Nederlands](../nl/QUICKSTART.md) · [Polski](../pl/QUICKSTART.md) · [Português](../pt/QUICKSTART.md) · [Русский](../ru/QUICKSTART.md) · [Svenska](../sv/QUICKSTART.md) · [ไทย](../th/QUICKSTART.md) · [Türkçe](../tr/QUICKSTART.md) · [Українська](../uk/QUICKSTART.md) · [Tiếng Việt](../vi/QUICKSTART.md) · [中文](../zh/QUICKSTART.md)

---

# Quickstart adopce VDLU

Checklist na zkopírování pro vendorování **VDLiveUpdate** do modulu. VDLU není modul
sám o sobě: vkládá se do `<module>/vdlu/` a cestuje uvnitř zipu tvého modulu.
Pro úplný rationale viz [`INTERFACES.md`](INTERFACES.md) (kontrakt costury),
[`ENGINE.md`](ENGINE.md), [`PRODUCER.md`](PRODUCER.md) a [`WEBUI.md`](WEBUI.md).

Nahraď `<id>` id svého podepisovacího klíče, `<abi>` ABI zařízení, které dodáváš
(`arm64-v8a`, `armeabi-v7a`, `x86_64`, `x86`), a `<module>` stromem svého modulu.

## Cílový layout

Toto je přesný `vdlu/` strom, který modul nese po adopci:

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

Měnitelný stav enginu (`config`, `current.json`, journal, lock) žije v
Tier-2, `/data/adb/<modid>/vdlu/`, mimo adresář modulu, `config.default` ho naseeduje
při prvním runu.

## 1. Vendorovat engine

Zkopíruj engine, verify shim a verifikátor per-ABI do `<module>/vdlu/`:

```sh
mkdir -p <module>/vdlu/verify
cp engine/update.sh      <module>/vdlu/update.sh
cp engine/vdlu-verify    <module>/vdlu/vdlu-verify
cp -r verify/<abi>       <module>/vdlu/verify/<abi>      # ed25519-mini per ABI
```

Dodávej jen ABI, které podporuješ, `customize.sh` umí při instalaci ořezat `verify/` na ABI
zařízení.

## 2. Vygenerovat podepisovací klíč (jednorázově)

```sh
producer/vdlu-keygen <id> ./keys
```

Toto vydá `<id>.pem` (privátní, drž ho mimo každé zařízení a mimo jakýkoli push do repa),
`<id>.pub` (PEM, jen PC-side) a `<id>.pub.raw` (RAW 32 bajtů, pro keyring zařízení).

## 3. Zabudovat raw veřejný klíč

Keyring zařízení drží **RAW 32bajtový** klíč, nikdy PEM (`ed25519-mini`
neumí přečíst PEM):

```sh
mkdir -p <module>/vdlu/keyring
cp ./keys/<id>.pub.raw <module>/vdlu/keyring/<id>.pub
```

Keyring je stabilní napříč releasy (mění ho jen rotace klíče): při
re-vendoru **ověř, nepřepisuj**.

## 4. Napsat config

Dodej `config.default` v `<module>/vdlu/` (naseeduje Tier-2 `config` při prvním runu):

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

`profile=trusted` použij jen pro soukromý `file://`/SSH zdroj (verify best-effort;
sha256 každého blobu se stejně kontroluje). Jakákoli hodnota jiná než doslovné `trusted`
je brána jako `hardened` (fail-closed).

## 5. Zapojit triggery

**Při rebootu** (`auto_on_reboot`): zavolej engine pre-zygote z `post-fs-data.sh`,
aby se stageované soubory (`.so`, `/system` overlay, `sepolicy.rule`) prohodily bez
rebootu navíc:

```sh
# <module>/post-fs-data.sh
MODDIR=${0%/*}
sh "$MODDIR/vdlu/update.sh" boot
```

**Při otevření WebUI** (`auto_on_webui_open`): zapoj drop-in Updates panel do svého
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

(`vdlu.js` / `vdlu.css` se vendorují z `webui/`, překlad lze přidat přes
`i18n: window.VDLU_I18N_<LANG>`.)

## 6. Podepsat feed ve svém release workflow

Při každém releasu zabal finální strom modulu a podepiš manifest. Drž privátní klíč
na stroji operátora, nikdy v CI:

```sh
producer/vdlu-pack  <module>  ./out  <module> <versionCode> --version-name v<versionCode> --channel stable \
                    [--prev ./prev/manifest.json]        # delete[] = paths gone since prev
producer/vdlu-sign  ./out/manifest.json  ./keys/<id>.pem  <id>
# publish ./out/{manifest.json,blobs/} to <source>
```

## 7. Dodat baseline

Vygeneruj `baseline.json` nad dodaným stromem a umísti ho na `<module>/vdlu/baseline.json`.
Naseeduje `current.json` při čisté instalaci, aby se zařízení narodilo "aktuální" (bez
re-fetchu). Je to **lokální důvěryhodné seed**: nepodepsané a bez klíče, takže ho CI umí sestavit
bez jediného dotyku podepisovacího klíče:

```sh
producer/vdlu-pack  <module>  ./seed  <module> <versionCode> --version-name v<versionCode>
cp ./seed/manifest.json <module>/vdlu/baseline.json
```

Není fatální, pokud chybí (zařízení prostě začne od `0` při první aktualizaci).

---

To je celá adopce. `sh -n <module>/vdlu/update.sh` musí projít, otestuj
producer a engine od konce ke konci, jak ukazuje [`PRODUCER.md`](PRODUCER.md) a
kořenový README, než budeš dodávat.

<!-- doc-footer -->

---

> _Tato dokumentace byla vytvořena pomocí Claude (Anthropic) a spravuje ji VD171. Opravy a vylepšení jsou vítány, viz [CONTRIBUTING.md](CONTRIBUTING.md)._
