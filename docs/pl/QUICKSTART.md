> **Languages:** [English](../QUICKSTART.md) · [العربية](../ar/QUICKSTART.md) · [Čeština](../cs/QUICKSTART.md) · [Deutsch](../de/QUICKSTART.md) · [Español](../es/QUICKSTART.md) · [فارسی](../fa/QUICKSTART.md) · [Français](../fr/QUICKSTART.md) · [हिन्दी](../hi/QUICKSTART.md) · [Bahasa Indonesia](../id/QUICKSTART.md) · [Italiano](../it/QUICKSTART.md) · [日本語](../ja/QUICKSTART.md) · [한국어](../ko/QUICKSTART.md) · [Nederlands](../nl/QUICKSTART.md) · Polski · [Português](../pt/QUICKSTART.md) · [Русский](../ru/QUICKSTART.md) · [Svenska](../sv/QUICKSTART.md) · [ไทย](../th/QUICKSTART.md) · [Türkçe](../tr/QUICKSTART.md) · [Українська](../uk/QUICKSTART.md) · [Tiếng Việt](../vi/QUICKSTART.md) · [中文](../zh/QUICKSTART.md)

---

# Quickstart adopcji VDLU

Lista kontrolna kopiuj-wklej do wendorowania **VDLiveUpdate** w module. VDLU sam nie jest
modułem: jest wrzucany do `<module>/vdlu/` i jedzie w zipie twojego modułu. Pełne uzasadnienie
zobacz w [`INTERFACES.md`](INTERFACES.md) (kontrakt styku),
[`ENGINE.md`](ENGINE.md), [`PRODUCER.md`](PRODUCER.md) i [`WEBUI.md`](WEBUI.md).

Zastąp `<id>` id twojego klucza podpisującego, `<abi>` ABI urządzenia, które dostarczasz
(`arm64-v8a`, `armeabi-v7a`, `x86_64`, `x86`), a `<module>` drzewem twojego modułu.

## Docelowy układ

To jest dokładne drzewo `vdlu/`, które moduł niesie po adopcji:

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

Zmienny stan engine (`config`, `current.json`, journal, lock) żyje w
Tier-2, `/data/adb/<modid>/vdlu/`, poza katalogiem modułu; `config.default` zasiewa go przy
pierwszym uruchomieniu.

## 1. Wendoruj engine

Skopiuj engine, shim verify oraz weryfikator per-ABI do `<module>/vdlu/`:

```sh
mkdir -p <module>/vdlu/verify
cp engine/update.sh      <module>/vdlu/update.sh
cp engine/vdlu-verify    <module>/vdlu/vdlu-verify
cp -r verify/<abi>       <module>/vdlu/verify/<abi>      # ed25519-mini per ABI
```

Dostarcz tylko te ABI, które wspierasz; `customize.sh` może przyciąć `verify/` do ABI
urządzenia w czasie instalacji.

## 2. Wygeneruj klucz podpisujący (jednorazowo)

```sh
producer/vdlu-keygen <id> ./keys
```

To emituje `<id>.pem` (prywatny, trzymaj go z dala od każdego urządzenia i od każdego pusha
repo), `<id>.pub` (PEM, tylko po stronie PC) oraz `<id>.pub.raw` (RAW 32 bajty, dla keyringa
urządzenia).

## 3. Osadź surowy klucz publiczny

Keyring urządzenia trzyma klucz **RAW 32-bajtowy**, nigdy PEM (`ed25519-mini`
nie potrafi odczytać PEM):

```sh
mkdir -p <module>/vdlu/keyring
cp ./keys/<id>.pub.raw <module>/vdlu/keyring/<id>.pub
```

Keyring jest stabilny między releasami (zmienia się tylko przy rotacji klucza): przy
re-wendoringu **weryfikuj, nie nadpisuj**.

## 4. Napisz config

Dostarcz `config.default` w `<module>/vdlu/` (zasiewa `config` w Tier-2 przy pierwszym uruchomieniu):

```
auto_on_reboot=1
auto_on_webui_open=1
source=https://<user>.github.io/<repo>/<module>
channel=stable
profile=hardened        # public feed: signature mandatory, downgrade blocked
net_policy=any
pubkey_dir=keyring
```

Używaj `profile=trusted` tylko dla prywatnego źródła `file://`/SSH (verify best-effort;
sha256 każdego bloba i tak jest sprawdzany). Każda wartość inna niż dosłowne `trusted` jest
traktowana jako `hardened` (fail-closed).

## 5. Podłącz triggery

**Przy reboocie** (`auto_on_reboot`): wywołaj engine pre-zygote z `post-fs-data.sh`, aby
staged pliki (`.so`, overlay `/system`, `sepolicy.rule`) wymieniły się bez dodatkowego
rebootu:

```sh
# <module>/post-fs-data.sh
MODDIR=${0%/*}
sh "$MODDIR/vdlu/update.sh" boot
```

**Przy otwarciu WebUI** (`auto_on_webui_open`): podłącz gotowy panel Updates w swoim
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

(`vdlu.js` / `vdlu.css` są wendorowane z `webui/`; tłumaczenie można dodać przez
`i18n: window.VDLU_I18N_<LANG>`.)

## 6. Podpisz feed w swoim workflow release

Przy każdym release spakuj finalne drzewo modułu i podpisz manifest. Trzymaj klucz prywatny na
maszynie operatora, nigdy w CI:

```sh
producer/vdlu-pack  <module>  ./out  <module> <versionCode> --version-name v<versionCode> --channel stable \
                    [--prev ./prev/manifest.json]        # delete[] = paths gone since prev
producer/vdlu-sign  ./out/manifest.json  ./keys/<id>.pem  <id>
# publish ./out/{manifest.json,blobs/} to <source>
```

## 7. Dostarcz baseline

Wygeneruj `baseline.json` nad dostarczanym drzewem i umieść go w `<module>/vdlu/baseline.json`.
Zasiewa `current.json` przy świeżej instalacji, aby urządzenie rodziło się "aktualne" (bez
ponownego fetcha). To **lokalne zaufane ziarno**: niepodpisane i bez klucza, więc CI może je
zbudować, nie dotykając nigdy klucza podpisującego:

```sh
producer/vdlu-pack  <module>  ./seed  <module> <versionCode> --version-name v<versionCode>
cp ./seed/manifest.json <module>/vdlu/baseline.json
```

Niekrytyczne, jeśli nieobecny (urządzenie po prostu startuje od `0` przy pierwszej aktualizacji).

---

To cała adopcja. `sh -n <module>/vdlu/update.sh` musi przejść; przetestuj
producera i engine od końca do końca, jak pokazano w [`PRODUCER.md`](PRODUCER.md) i w głównym
README, zanim dostarczysz.

<!-- doc-footer -->

---

> _Ta dokumentacja została wygenerowana za pomocą Claude (Anthropic) i jest utrzymywana przez VD171. Poprawki i ulepszenia są mile widziane; zobacz [CONTRIBUTING.md](CONTRIBUTING.md)._
