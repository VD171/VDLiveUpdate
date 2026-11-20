# Quick Start

To jest lista kontrolna wdrożenia: jak wbudować (vendor) **VDLiveUpdate (VDLU)** do
modułu KernelSU / APatch / Magisk. VDLU nie jest sam modułem. Jest umieszczany w
`<module>/vdlu/` i dostarczany wewnątrz zipa Twojego modułu, aby zainstalowany moduł mógł
aktualizować się bezflashowo z podpisanego kanału, który publikujesz.

W całym tekście zastąp `<id>` swoim id klucza podpisującego, `<abi>` ABI urządzenia,
które dostarczasz (`arm64-v8a`, `armeabi-v7a`, `x86_64`, `x86`), a `<module>`
swoim drzewem modułu.

Aby poznać uzasadnienie każdego elementu, zobacz [[Engine]], [[Producer]], [[WebUI]] i
[[Security and Trust Model]].

## Układ `vdlu/` w module

To jest dokładne drzewo, które Twój moduł niesie po wdrożeniu:

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

Mutowalny stan silnika (`config`, `current.json`, dziennik, blokada, pamięć podręczna blobów)
żyje w Tier-2 w `/data/adb/<modid>/vdlu/`, poza katalogiem modułu.
`config.default` zaszczepia ten `config` Tier-2 przy pierwszym uruchomieniu. Zobacz [[Engine]], aby poznać
pełny układ stanu.

## 1. Wbuduj silnik

Skopiuj silnik, shim weryfikacji i plik binarny weryfikatora per-ABI do
`<module>/vdlu/`:

```sh
mkdir -p <module>/vdlu/verify
cp engine/update.sh   <module>/vdlu/update.sh
cp engine/vdlu-verify <module>/vdlu/vdlu-verify
cp -r verify/<abi>    <module>/vdlu/verify/<abi>    # ed25519-mini per ABI
```

Dostarczaj tylko te ABI, które wspierasz. Twój `customize.sh` może przyciąć `verify/` do
ABI urządzenia w czasie instalacji.

## 2. Wygeneruj klucz podpisujący (jednorazowo)

```sh
producer/vdlu-keygen <id> ./keys
```

To emituje trzy pliki:

- `<id>.pem` - klucz prywatny. Trzymaj go z dala od każdego urządzenia i poza każdym pushem
  do repozytorium lub sekretem CI.
- `<id>.pub` - klucz publiczny PEM. Tylko po stronie PC (używany przez `vdlu-sign`).
- `<id>.pub.raw` - surowy 32-bajtowy klucz publiczny, dla keyringa urządzenia.

Zobacz [[Security and Trust Model]], aby dowiedzieć się, dlaczego podział ma znaczenie.

## 3. Osadź surowy klucz publiczny

Keyring urządzenia trzyma **surowy 32-bajtowy** klucz, nigdy PEM. `ed25519-mini`
nie może odczytać PEM, więc skopiowanie PEM tutaj łamie weryfikację na urządzeniu:

```sh
mkdir -p <module>/vdlu/keyring
cp ./keys/<id>.pub.raw <module>/vdlu/keyring/<id>.pub
```

Keyring jest stabilny między wydaniami: zmienia się tylko przy rotacji klucza. Przy
ponownym wbudowaniu **zweryfikuj go, nie nadpisuj**.

## 4. Napisz konfigurację

Dostarcz `config.default` w `<module>/vdlu/`. Zaszczepia on `config` Tier-2 przy pierwszym
uruchomieniu:

```
auto_on_reboot=1
auto_on_webui_open=1
source=https://<user>.github.io/<repo>/<module>
channel=stable
profile=hardened        # public feed: signature mandatory, downgrade blocked
net_policy=any
pubkey_dir=keyring
```

Użyj `profile=trusted` tylko dla prywatnego źródła `file://` lub SSH (weryfikacja jest
best-effort tam, ale `sha256` każdego bloba i tak jest sprawdzany). Każda wartość inna
niż dosłowne `trusted` jest traktowana jako `hardened`, fail-closed. Zobacz
[[Security and Trust Model]], aby poznać pełną semantykę profili.

## 5. Podepnij wyzwalacze

**Przy restarcie** (`auto_on_reboot`): wywołaj silnik przed-zygote z
`post-fs-data.sh`, aby zetapowane pliki klasy reboot (`.so`, nakładka `/system`,
`sepolicy.rule`) podmieniły się bez dodatkowego restartu:

```sh
# <module>/post-fs-data.sh
MODDIR=${0%/*}
sh "$MODDIR/vdlu/update.sh" boot
```

**Przy otwarciu WebUI** (`auto_on_webui_open`): podepnij gotowy do wstawienia panel Updates w swoim
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

`vdlu.js` i `vdlu.css` są wbudowane z `webui/`. Tłumaczenie można dodać
za pomocą `i18n: window.VDLU_I18N_<LANG>`. Zobacz [[WebUI]], aby poznać kontrakt panelu.

## 6. Podpisz kanał w swoim przepływie wydania

Przy każdym wydaniu spakuj końcowe drzewo modułu i podpisz manifest. Trzymaj klucz prywatny
na maszynie operatora, nigdy w CI:

```sh
producer/vdlu-pack  <module>  ./out  <module> <versionCode> \
                    --version-name v<versionCode> --channel stable \
                    [--prev ./prev/manifest.json]      # delete[] = paths gone since prev
producer/vdlu-sign  ./out/manifest.json  ./keys/<id>.pem  <id>
# publish ./out/{manifest.json,blobs/} to <source>
```

`vdlu-pack` jest adresowany treścią i deduplikujący, więc publikowanie jest przyrostowe:
niezmienione bloby nigdy nie są ponownie wypychane. Zobacz [[Producer]] i [[Feed Format]].

## 7. Dostarcz baseline

Wygeneruj `baseline.json` nad dostarczonym drzewem i umieść go w
`<module>/vdlu/baseline.json`. Zaszczepia `current.json` przy świeżej instalacji, aby
urządzenie rodziło się "aktualne" i nie pobierało ponownie swojej własnej dostarczonej wersji. To
**lokalny zaufany zalążek**: niepodpisany i bezkluczowy, więc CI może zbudować go bez
dotykania klucza podpisującego:

```sh
producer/vdlu-pack  <module>  ./seed  <module> <versionCode> --version-name v<versionCode>
cp ./seed/manifest.json <module>/vdlu/baseline.json
```

Jest niefatalny, jeśli nieobecny: urządzenie po prostu zaczyna od wersji `0` przy
pierwszej aktualizacji.

---

To całe wdrożenie. Zanim dostarczysz, `sh -n <module>/vdlu/update.sh`
musi przejść i powinieneś przetestować producenta i silnik od początku do końca, jak pokazano w
[[Contributing]] i [[Producer]].
