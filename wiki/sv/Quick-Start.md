# Snabbstart

Detta är införandechecklistan: hur du bäddar in **VDLiveUpdate (VDLU)** i en
KernelSU- / APatch- / Magisk-modul. VDLU är inte en modul i sig själv. Den placeras i
`<module>/vdlu/` och levereras inuti din moduls zip, så att en installerad modul kan
uppdatera sig själv flashfritt från ett signerat flöde du publicerar.

Genomgående, ersätt `<id>` med ditt signeringsnyckel-id, `<abi>` med enhetens
ABI(er) du levererar (`arm64-v8a`, `armeabi-v7a`, `x86_64`, `x86`), och `<module>`
med ditt modulträd.

För rationalen bakom varje del, se [[Engine]], [[Producer]], [[WebUI]] och
[[Security and Trust Model]].

## `vdlu/`-layouten i modulen

Detta är exakt det träd din modul bär efter införande:

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

Motorns föränderliga tillstånd (`config`, `current.json`, journal, lås, blob-cache)
lever i Tier-2 vid `/data/adb/<modid>/vdlu/`, utanför modulkatalogen.
`config.default` seedar det Tier-2-`config` vid första körning. Se [[Engine]] för den
fullständiga tillståndslayouten.

## 1. Bädda in motorn

Kopiera motorn, verify-shimmen och per-ABI-verifierarbinären in i
`<module>/vdlu/`:

```sh
mkdir -p <module>/vdlu/verify
cp engine/update.sh   <module>/vdlu/update.sh
cp engine/vdlu-verify <module>/vdlu/vdlu-verify
cp -r verify/<abi>    <module>/vdlu/verify/<abi>    # ed25519-mini per ABI
```

Leverera bara de ABI:er du stöder. Din `customize.sh` kan rensa `verify/` ner till
enhetens ABI vid installationstid.

## 2. Generera en signeringsnyckel (engång)

```sh
producer/vdlu-keygen <id> ./keys
```

Detta skickar ut tre filer:

- `<id>.pem` - den privata nyckeln. Håll den borta från varje enhet och utanför varje repo-
  push eller CI-hemlighet.
- `<id>.pub` - den publika PEM-nyckeln. Endast PC-sidan (används av `vdlu-sign`).
- `<id>.pub.raw` - den RÅA 32-byte publika nyckeln, för enhetens nyckelring.

Se [[Security and Trust Model]] för varför uppdelningen spelar roll.

## 3. Bädda in den råa publika nyckeln

Enhetens nyckelring håller den **RÅA 32-byte** nyckeln, aldrig PEM. `ed25519-mini`
kan inte läsa en PEM, så att kopiera PEM hit bryter verifieringen på enheten:

```sh
mkdir -p <module>/vdlu/keyring
cp ./keys/<id>.pub.raw <module>/vdlu/keyring/<id>.pub
```

Nyckelringen är stabil mellan releaser: den ändras bara vid nyckelrotation. Vid en
återinbäddning, **verifiera den, skriv inte över den**.

## 4. Skriv konfigurationen

Leverera `config.default` i `<module>/vdlu/`. Den seedar det Tier-2-`config` vid första
körning:

```
auto_on_reboot=1
auto_on_webui_open=1
source=https://<user>.github.io/<repo>/<module>
channel=stable
profile=hardened        # public feed: signature mandatory, downgrade blocked
net_policy=any
pubkey_dir=keyring
```

Använd `profile=trusted` bara för en privat `file://`- eller SSH-källa (verifiering är
efter bästa förmåga där, men varje blobs sha256 kontrolleras fortfarande). Varje värde annat
än det bokstavliga `trusted` behandlas som `hardened`, fail-closed. Se
[[Security and Trust Model]] för den fullständiga profilsemantiken.

## 5. Koppla in utlösarna

**Vid omstart** (`auto_on_reboot`): anropa motorn före zygote från
`post-fs-data.sh`, så att förberedda omstartsklass-filer (en `.so`, ett `/system`-överlägg,
en `sepolicy.rule`) byts in utan någon extra omstart:

```sh
# <module>/post-fs-data.sh
MODDIR=${0%/*}
sh "$MODDIR/vdlu/update.sh" boot
```

**Vid WebUI-öppning** (`auto_on_webui_open`): koppla in den inbyggbara Updates-panelen i din
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

`vdlu.js` och `vdlu.css` bäddas in från `webui/`. En översättning kan läggas till
med `i18n: window.VDLU_I18N_<LANG>`. Se [[WebUI]] för panelkontraktet.

## 6. Signera flödet i ditt releasearbetsflöde

Vid varje release, packa det slutliga modulträdet och signera manifestet. Håll den privata
nyckeln på operatörsmaskinen, aldrig i CI:

```sh
producer/vdlu-pack  <module>  ./out  <module> <versionCode> \
                    --version-name v<versionCode> --channel stable \
                    [--prev ./prev/manifest.json]      # delete[] = paths gone since prev
producer/vdlu-sign  ./out/manifest.json  ./keys/<id>.pem  <id>
# publish ./out/{manifest.json,blobs/} to <source>
```

`vdlu-pack` är innehållsadresserad och deduplicerande, så publicering är inkrementell:
oförändrade blobbar skickas aldrig om. Se [[Producer]] och [[Feed Format]].

## 7. Leverera baslinjen

Generera `baseline.json` över det levererade trädet och placera den vid
`<module>/vdlu/baseline.json`. Den seedar `current.json` vid en nyinstallation, så att
enheten föds "aktuell" och inte omhämtar sin egen levererade version. Det är ett
**lokalt betrott seed**: osignerat och nyckellöst, så att CI kan bygga det utan att någonsin
vidröra signeringsnyckeln:

```sh
producer/vdlu-pack  <module>  ./seed  <module> <versionCode> --version-name v<versionCode>
cp ./seed/manifest.json <module>/vdlu/baseline.json
```

Det är icke-fatalt om det saknas: enheten startar helt enkelt från version `0` vid den
första uppdateringen.

---

Det är hela införandet. Innan du levererar måste `sh -n <module>/vdlu/update.sh`
passera, och du bör testa producenten och motorn från början till slut som visas i
[[Contributing]] och [[Producer]].
