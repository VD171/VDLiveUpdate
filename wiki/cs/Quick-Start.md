# Quick Start

Toto je kontrolní seznam převzetí: jak vendorovat **VDLiveUpdate (VDLU)** do
modulu KernelSU / APatch / Magisk. VDLU není samotný modul. Vkládá se do
`<module>/vdlu/` a dodává se uvnitř zipu vašeho modulu, takže nainstalovaný modul se může
aktualizovat bezflashově z podepsaného feedu, který publikujete.

Všude nahraďte `<id>` za id svého podpisového klíče, `<abi>` za ABI zařízení, které
dodáváte (`arm64-v8a`, `armeabi-v7a`, `x86_64`, `x86`), a `<module>`
za svůj strom modulu.

Pro úvahu za každým kusem viz [[Engine]], [[Producer]], [[WebUI]] a
[[Security and Trust Model]].

## Rozložení `vdlu/` uvnitř modulu

Toto je přesný strom, který váš modul nese po převzetí:

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

Měnitelný stav enginu (`config`, `current.json`, žurnál, zámek, cache blobů)
žije v Tier-2 na `/data/adb/<modid>/vdlu/`, mimo adresář modulu.
`config.default` naseje onu Tier-2 `config` při prvním běhu. Viz [[Engine]] pro
úplné rozložení stavu.

## 1. Vendorování enginu

Zkopírujte engine, verify shim a per-ABI binární soubor ověřovače do
`<module>/vdlu/`:

```sh
mkdir -p <module>/vdlu/verify
cp engine/update.sh   <module>/vdlu/update.sh
cp engine/vdlu-verify <module>/vdlu/vdlu-verify
cp -r verify/<abi>    <module>/vdlu/verify/<abi>    # ed25519-mini per ABI
```

Dodávejte jen ABI, které podporujete. Váš `customize.sh` může oříznout `verify/` na
ABI zařízení v čase instalace.

## 2. Vygenerování podpisového klíče (jednorázové)

```sh
producer/vdlu-keygen <id> ./keys
```

Toto vydá tři soubory:

- `<id>.pem` - privátní klíč. Držte ho mimo každé zařízení a mimo jakýkoli push do repo
  nebo CI secret.
- `<id>.pub` - PEM veřejný klíč. Jen na straně PC (používán `vdlu-sign`).
- `<id>.pub.raw` - SYROVÝ 32-bajtový veřejný klíč, pro keyring zařízení.

Viz [[Security and Trust Model]] pro to, proč na rozdělení záleží.

## 3. Vložení syrového veřejného klíče

Keyring zařízení drží **SYROVÝ 32-bajtový** klíč, nikdy PEM. `ed25519-mini`
nemůže číst PEM, takže kopírování PEM sem rozbije ověření na zařízení:

```sh
mkdir -p <module>/vdlu/keyring
cp ./keys/<id>.pub.raw <module>/vdlu/keyring/<id>.pub
```

Keyring je stabilní napříč vydáními: mění se jen při rotaci klíče. Při
znovu-vendorování ho **ověřte, nepřepisujte**.

## 4. Napsání konfigurace

Dodejte `config.default` v `<module>/vdlu/`. Naseje Tier-2 `config` při prvním
běhu:

```
auto_on_reboot=1
auto_on_webui_open=1
source=https://<user>.github.io/<repo>/<module>
channel=stable
profile=hardened        # public feed: signature mandatory, downgrade blocked
net_policy=any
pubkey_dir=keyring
```

Použijte `profile=trusted` jen pro privátní `file://` nebo SSH zdroj (verify je
tam best-effort, ale sha256 každého blobu se stále kontroluje). Jakákoli hodnota jiná
než doslovné `trusted` je považována za `hardened`, fail-closed. Viz
[[Security and Trust Model]] pro úplnou sémantiku profilu.

## 5. Zapojení triggerů

**Při restartu** (`auto_on_reboot`): zavolejte engine pre-zygote z
`post-fs-data.sh`, takže inscenované soubory třídy reboot (`.so`, overlay `/system`,
`sepolicy.rule`) se vymění bez extra restartu:

```sh
# <module>/post-fs-data.sh
MODDIR=${0%/*}
sh "$MODDIR/vdlu/update.sh" boot
```

**Při otevření WebUI** (`auto_on_webui_open`): zapojte drop-in panel Updates do svého
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

`vdlu.js` a `vdlu.css` se vendorují z `webui/`. Překlad lze přidat
pomocí `i18n: window.VDLU_I18N_<LANG>`. Viz [[WebUI]] pro kontrakt panelu.

## 6. Podepsání feedu ve vašem release workflow

Při každém vydání zabalte finální strom modulu a podepište manifest. Držte privátní
klíč na operátorském stroji, nikdy v CI:

```sh
producer/vdlu-pack  <module>  ./out  <module> <versionCode> \
                    --version-name v<versionCode> --channel stable \
                    [--prev ./prev/manifest.json]      # delete[] = paths gone since prev
producer/vdlu-sign  ./out/manifest.json  ./keys/<id>.pem  <id>
# publish ./out/{manifest.json,blobs/} to <source>
```

`vdlu-pack` je obsahově adresovaný a deduplikující, takže publikování je inkrementální:
nezměněné bloby se nikdy znovu nepushují. Viz [[Producer]] a [[Feed Format]].

## 7. Dodání baseline

Vygenerujte `baseline.json` nad dodaným stromem a umístěte ji na
`<module>/vdlu/baseline.json`. Naseje `current.json` při čerstvé instalaci, takže
zařízení se narodí "aktuální" a znovu nestahuje svou vlastní dodanou verzi. Je to
**lokální důvěryhodné semínko**: nepodepsané a bezklíčové, takže CI ji může sestavit, aniž by se kdy
dotklo podpisového klíče:

```sh
producer/vdlu-pack  <module>  ./seed  <module> <versionCode> --version-name v<versionCode>
cp ./seed/manifest.json <module>/vdlu/baseline.json
```

Je neosudná, pokud chybí: zařízení jednoduše začíná od verze `0` při
první aktualizaci.

---

To je celé převzetí. Než budete dodávat, `sh -n <module>/vdlu/update.sh`
musí projít a měli byste testovat producer a engine end-to-end, jak je ukázáno v
[[Contributing]] a [[Producer]].
