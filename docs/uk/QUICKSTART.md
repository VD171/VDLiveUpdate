> **Languages:** [English](../QUICKSTART.md) · [العربية](../ar/QUICKSTART.md) · [Čeština](../cs/QUICKSTART.md) · [Deutsch](../de/QUICKSTART.md) · [Español](../es/QUICKSTART.md) · [فارسی](../fa/QUICKSTART.md) · [Français](../fr/QUICKSTART.md) · [हिन्दी](../hi/QUICKSTART.md) · [Bahasa Indonesia](../id/QUICKSTART.md) · [Italiano](../it/QUICKSTART.md) · [日本語](../ja/QUICKSTART.md) · [한국어](../ko/QUICKSTART.md) · [Nederlands](../nl/QUICKSTART.md) · [Polski](../pl/QUICKSTART.md) · [Português](../pt/QUICKSTART.md) · [Русский](../ru/QUICKSTART.md) · [Svenska](../sv/QUICKSTART.md) · [ไทย](../th/QUICKSTART.md) · [Türkçe](../tr/QUICKSTART.md) · Українська · [Tiếng Việt](../vi/QUICKSTART.md) · [中文](../zh/QUICKSTART.md)

---

# Швидкий старт із впровадження VDLU

Чек-лист для копіювання-вставляння задля вендоризації **VDLiveUpdate** у модуль. VDLU не є модулем сам по
собі: його кладуть у `<module>/vdlu/` і він ship-иться всередині zip вашого модуля. Щодо повного обґрунтування
див. [`INTERFACES.md`](INTERFACES.md) (seam-контракт), [`ENGINE.md`](ENGINE.md), [`PRODUCER.md`](PRODUCER.md)
та [`WEBUI.md`](WEBUI.md).

Замініть `<id>` на id вашого ключа підпису, `<abi>` на ABI пристрою, які ви ship-ите (`arm64-v8a`,
`armeabi-v7a`, `x86_64`, `x86`), а `<module>` - на дерево вашого модуля.

## Цільовий layout

Це точне дерево `vdlu/`, яке модуль несе після впровадження:

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

Змінний стан engine (`config`, `current.json`, journal, lock) живе в Tier-2, `/data/adb/<modid>/vdlu/`, поза
module dir, `config.default` засіває його на першому запуску.

## 1. Вендоризуйте engine

Скопіюйте engine, verify shim і verifier на кожен ABI у `<module>/vdlu/`:

```sh
mkdir -p <module>/vdlu/verify
cp engine/update.sh      <module>/vdlu/update.sh
cp engine/vdlu-verify    <module>/vdlu/vdlu-verify
cp -r verify/<abi>       <module>/vdlu/verify/<abi>      # ed25519-mini per ABI
```

Ship-те лише ABI, які ви підтримуєте, `customize.sh` може обрізати `verify/` до ABI пристрою під час установки.

## 2. Згенеруйте ключ підпису (одноразово)

```sh
producer/vdlu-keygen <id> ./keys
```

Це видає `<id>.pem` (priv, тримайте його подалі від кожного пристрою й від будь-якого push-у repo), `<id>.pub`
(PEM, лише PC-side) і `<id>.pub.raw` (RAW 32 байти, для keyring пристрою).

## 3. Вбудуйте сирий публічний ключ

Keyring пристрою тримає **RAW 32-байтовий** ключ, ніколи PEM (`ed25519-mini` не може прочитати PEM):

```sh
mkdir -p <module>/vdlu/keyring
cp ./keys/<id>.pub.raw <module>/vdlu/keyring/<id>.pub
```

Keyring стабільний між релізами (він змінюється лише при ротації ключа): під час повторної вендоризації
**перевіряйте, не перезаписуйте** його.

## 4. Напишіть config

Ship-те `config.default` у `<module>/vdlu/` (засіває Tier-2 `config` на першому запуску):

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

Використовуйте `profile=trusted` лише для приватного `file://`/SSH-джерела (verify best-effort, sha256 кожного
блоба все одно перевіряється). Будь-яке значення, окрім буквального `trusted`, трактується як `hardened`
(fail-closed).

## 5. Підключіть тригери

**На reboot** (`auto_on_reboot`): викликайте engine pre-zygote з `post-fs-data.sh`, щоб застейджені файли
(`.so`, overlay `/system`, `sepolicy.rule`) обмінялися без зайвого reboot:

```sh
# <module>/post-fs-data.sh
MODDIR=${0%/*}
sh "$MODDIR/vdlu/update.sh" boot
```

**На відкриття WebUI** (`auto_on_webui_open`): підключіть drop-in Updates panel у вашому `webroot/index.html`:

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

(`vdlu.js` / `vdlu.css` вендоризуються з `webui/`, переклад можна додати через
`i18n: window.VDLU_I18N_<LANG>`.)

## 6. Підпишіть стрічку у вашому release-workflow

У кожному релізі запакуйте фінальне дерево модуля й підпишіть маніфест. Тримайте приватний ключ на машині
оператора, ніколи в CI:

```sh
producer/vdlu-pack  <module>  ./out  <module> <versionCode> --version-name v<versionCode> --channel stable \
                    [--prev ./prev/manifest.json]        # delete[] = paths gone since prev
producer/vdlu-sign  ./out/manifest.json  ./keys/<id>.pem  <id>
# publish ./out/{manifest.json,blobs/} to <source>
```

## 7. Ship-те baseline

Згенеруйте `baseline.json` над ship-нутим деревом і розмістіть його за `<module>/vdlu/baseline.json`. Воно
засіває `current.json` на свіжій установці, тож пристрій народжується "актуальним" (без re-fetch). Це
**локальне довірене насіння**: непідписане й без ключа, тож CI може збудувати його, жодного разу не торкнувшись
ключа підпису:

```sh
producer/vdlu-pack  <module>  ./seed  <module> <versionCode> --version-name v<versionCode>
cp ./seed/manifest.json <module>/vdlu/baseline.json
```

Його відсутність не фатальна (пристрій просто стартує з `0` на першому оновленні).

---

Це і є все впровадження. `sh -n <module>/vdlu/update.sh` мусить пройти, протестуйте producer і engine
end-to-end, як показано в [`PRODUCER.md`](PRODUCER.md) і кореневому README, перш ніж ship-ити.

<!-- doc-footer -->

---

> _Ця документація створена за допомогою Claude (Anthropic) і підтримується VD171. Виправлення та покращення вітаються, див. [CONTRIBUTING.md](CONTRIBUTING.md)._
