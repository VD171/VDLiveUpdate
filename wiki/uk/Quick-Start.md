# Quick Start

Це контрольний список упровадження: як вбудувати **VDLiveUpdate (VDLU)** у
модуль KernelSU / APatch / Magisk. VDLU сам не є модулем. Його кладуть у
`<module>/vdlu/`, і він відвантажується всередині zip вашого модуля, тож встановлений модуль може
оновлювати себе без перепрошивки з підписаного feed, який ви публікуєте.

Усюди замінюйте `<id>` на id вашого ключа підпису, `<abi>` на ABI пристрою,
який ви відвантажуєте (`arm64-v8a`, `armeabi-v7a`, `x86_64`, `x86`), і `<module>`
на дерево вашого модуля.

Про обґрунтування кожної частини див. [[Engine]], [[Producer]], [[WebUI]] та
[[Security and Trust Model]].

## Внутрішньомодульна структура `vdlu/`

Це точне дерево, яке ваш модуль несе після впровадження:

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

Змінний стан рушія (`config`, `current.json`, журнал, блокування, кеш blob-ів)
живе в Tier-2 за `/data/adb/<modid>/vdlu/`, поза каталогом модуля.
`config.default` засіває той Tier-2 `config` при першому запуску. Повну структуру
стану див. у [[Engine]].

## 1. Вбудуйте рушій

Скопіюйте рушій, shim перевірки та бінарник перевіряча для кожного ABI у
`<module>/vdlu/`:

```sh
mkdir -p <module>/vdlu/verify
cp engine/update.sh   <module>/vdlu/update.sh
cp engine/vdlu-verify <module>/vdlu/vdlu-verify
cp -r verify/<abi>    <module>/vdlu/verify/<abi>    # ed25519-mini per ABI
```

Відвантажуйте лише ті ABI, які ви підтримуєте. Ваш `customize.sh` може обрізати `verify/` до
ABI пристрою під час встановлення.

## 2. Згенеруйте ключ підпису (одноразово)

```sh
producer/vdlu-keygen <id> ./keys
```

Це видає три файли:

- `<id>.pem` - приватний ключ. Тримайте його поза кожним пристроєм і поза будь-яким push
  репозиторію чи секретом CI.
- `<id>.pub` - PEM-публічний ключ. Лише на боці ПК (використовується `vdlu-sign`).
- `<id>.pub.raw` - сирий 32-байтовий публічний ключ, для keyring пристрою.

Про те, чому поділ важливий, див. [[Security and Trust Model]].

## 3. Вбудуйте сирий публічний ключ

Keyring пристрою тримає **сирий 32-байтовий** ключ, ніколи PEM. `ed25519-mini`
не може прочитати PEM, тож копіювання PEM сюди ламає перевірку на пристрої:

```sh
mkdir -p <module>/vdlu/keyring
cp ./keys/<id>.pub.raw <module>/vdlu/keyring/<id>.pub
```

Keyring стабільний між випусками: він змінюється лише при ротації ключів. При
пере-вбудовуванні **перевірте його, не перезаписуйте**.

## 4. Напишіть конфіг

Відвантажте `config.default` у `<module>/vdlu/`. Він засіває Tier-2 `config` при першому
запуску:

```
auto_on_reboot=1
auto_on_webui_open=1
source=https://<user>.github.io/<repo>/<module>
channel=stable
profile=hardened        # public feed: signature mandatory, downgrade blocked
net_policy=any
pubkey_dir=keyring
```

Використовуйте `profile=trusted` лише для приватного `file://` чи SSH-джерела (перевірка там
best-effort, але sha256 кожного blob-а все одно перевіряється). Будь-яке значення, інше
за буквальне `trusted`, трактується як `hardened`, fail-closed. Про повну
семантику профілів див. [[Security and Trust Model]].

## 5. Підключіть тригери

**При перезавантаженні** (`auto_on_reboot`): викличте рушій pre-zygote з
`post-fs-data.sh`, щоб staged-файли класу reboot (`.so`, overlay `/system`,
`sepolicy.rule`) підмінилися без зайвого перезавантаження:

```sh
# <module>/post-fs-data.sh
MODDIR=${0%/*}
sh "$MODDIR/vdlu/update.sh" boot
```

**При відкритті WebUI** (`auto_on_webui_open`): підключіть панель Updates "вставив і працює" у
вашому `webroot/index.html`:

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

`vdlu.js` та `vdlu.css` вбудовуються з `webui/`. Переклад можна додати
через `i18n: window.VDLU_I18N_<LANG>`. Про контракт панелі див. [[WebUI]].

## 6. Підпишіть feed у вашому потоці випуску

Кожен випуск пакуйте остаточне дерево модуля й підписуйте маніфест. Тримайте приватний
ключ на машині оператора, ніколи в CI:

```sh
producer/vdlu-pack  <module>  ./out  <module> <versionCode> \
                    --version-name v<versionCode> --channel stable \
                    [--prev ./prev/manifest.json]      # delete[] = paths gone since prev
producer/vdlu-sign  ./out/manifest.json  ./keys/<id>.pem  <id>
# publish ./out/{manifest.json,blobs/} to <source>
```

`vdlu-pack` адресований за вмістом і дедуплікує, тож публікація інкрементна:
незмінені blob-и ніколи не відвантажуються знову. Див. [[Producer]] та [[Feed Format]].

## 7. Відвантажте baseline

Згенеруйте `baseline.json` над відвантаженим деревом і покладіть його за
`<module>/vdlu/baseline.json`. Він засіває `current.json` при свіжому встановленні, тож
пристрій народжується "поточним" і не тягне повторно власну відвантажену версію. Це
**локальне довірене насіння**: непідписане й безключове, тож CI може його зібрати, жодного разу
не торкаючись ключа підпису:

```sh
producer/vdlu-pack  <module>  ./seed  <module> <versionCode> --version-name v<versionCode>
cp ./seed/manifest.json <module>/vdlu/baseline.json
```

Його відсутність не фатальна: пристрій просто починає з версії `0` при першому
оновленні.

---

Це все впровадження. Перед відвантаженням `sh -n <module>/vdlu/update.sh`
має пройти, і вам слід протестувати producer та рушій наскрізь, як показано в
[[Contributing]] та [[Producer]].
