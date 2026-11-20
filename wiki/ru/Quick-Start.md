# Quick Start

Это чек-лист внедрения: как встроить **VDLiveUpdate (VDLU)** в
модуль KernelSU / APatch / Magisk. VDLU сам по себе не модуль. Он помещается в
`<module>/vdlu/` и поставляется внутри zip вашего модуля, так что установленный модуль может
обновлять себя бесшовно из подписанного канала, который вы публикуете.

Везде заменяйте `<id>` на id вашего ключа подписи, `<abi>` на ABI
устройства, которые вы поставляете (`arm64-v8a`, `armeabi-v7a`, `x86_64`, `x86`), и `<module>`
на дерево вашего модуля.

Обоснование каждого элемента см. в [[Engine]], [[Producer]], [[WebUI]] и
[[Security and Trust Model]].

## Раскладка `vdlu/` внутри модуля

Это точное дерево, которое ваш модуль несёт после внедрения:

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

Изменяемое состояние движка (`config`, `current.json`, журнал, блокировка, кэш блобов)
живёт в Tier-2 по пути `/data/adb/<modid>/vdlu/`, вне каталога модуля.
`config.default` засевает этот Tier-2 `config` при первом запуске. См. [[Engine]] про
полную раскладку состояния.

## 1. Встроить движок

Скопируйте движок, verify-шим и per-ABI бинарник проверяющего в
`<module>/vdlu/`:

```sh
mkdir -p <module>/vdlu/verify
cp engine/update.sh   <module>/vdlu/update.sh
cp engine/vdlu-verify <module>/vdlu/vdlu-verify
cp -r verify/<abi>    <module>/vdlu/verify/<abi>    # ed25519-mini per ABI
```

Поставляйте только те ABI, которые поддерживаете. Ваш `customize.sh` может обрезать `verify/` до
ABI устройства во время установки.

## 2. Сгенерировать ключ подписи (разово)

```sh
producer/vdlu-keygen <id> ./keys
```

Это выдаёт три файла:

- `<id>.pem` - приватный ключ. Держите его подальше от любого устройства и вне любого push в репозиторий
  или секрета CI.
- `<id>.pub` - PEM-публичный ключ. Только на стороне ПК (используется `vdlu-sign`).
- `<id>.pub.raw` - сырой 32-байтовый публичный ключ, для связки ключей на устройстве.

См. [[Security and Trust Model]] про то, почему разделение важно.

## 3. Встроить сырой публичный ключ

Связка ключей на устройстве хранит **сырой 32-байтовый** ключ, никогда PEM. `ed25519-mini`
не может прочитать PEM, поэтому копирование PEM сюда ломает проверку на устройстве:

```sh
mkdir -p <module>/vdlu/keyring
cp ./keys/<id>.pub.raw <module>/vdlu/keyring/<id>.pub
```

Связка стабильна между релизами: она меняется только при ротации ключа. При
повторном встраивании **проверьте её, не перезаписывайте**.

## 4. Написать конфиг

Поставьте `config.default` в `<module>/vdlu/`. Он засевает Tier-2 `config` при первом
запуске:

```
auto_on_reboot=1
auto_on_webui_open=1
source=https://<user>.github.io/<repo>/<module>
channel=stable
profile=hardened        # public feed: signature mandatory, downgrade blocked
net_policy=any
pubkey_dir=keyring
```

Используйте `profile=trusted` только для приватного источника `file://` или SSH (verify там
по возможности, но `sha256` каждого блоба всё равно проверяется). Любое значение, отличное
от буквального `trusted`, рассматривается как `hardened`, отказоустойчиво. См.
[[Security and Trust Model]] про полную семантику профилей.

## 5. Подключить триггеры

**On reboot** (`auto_on_reboot`): вызывайте движок pre-zygote из
`post-fs-data.sh`, чтобы подготовленные файлы класса reboot (`.so`, оверлей `/system`,
`sepolicy.rule`) заменялись без дополнительной перезагрузки:

```sh
# <module>/post-fs-data.sh
MODDIR=${0%/*}
sh "$MODDIR/vdlu/update.sh" boot
```

**On WebUI open** (`auto_on_webui_open`): подключите встраиваемую панель Updates в вашем
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

`vdlu.js` и `vdlu.css` встраиваются из `webui/`. Перевод можно добавить
через `i18n: window.VDLU_I18N_<LANG>`. См. [[WebUI]] про контракт панели.

## 6. Подписать канал в своём релизном workflow

На каждый релиз упакуйте финальное дерево модуля и подпишите манифест. Держите приватный
ключ на машине оператора, никогда в CI:

```sh
producer/vdlu-pack  <module>  ./out  <module> <versionCode> \
                    --version-name v<versionCode> --channel stable \
                    [--prev ./prev/manifest.json]      # delete[] = paths gone since prev
producer/vdlu-sign  ./out/manifest.json  ./keys/<id>.pem  <id>
# publish ./out/{manifest.json,blobs/} to <source>
```

`vdlu-pack` адресуется по содержимому и дедуплицирует, поэтому публикация инкрементальна:
неизменные блобы никогда не заливаются повторно. См. [[Producer]] и [[Feed Format]].

## 7. Поставить baseline

Сгенерируйте `baseline.json` по поставляемому дереву и разместите его по пути
`<module>/vdlu/baseline.json`. Он засевает `current.json` на свежей установке, чтобы
устройство родилось "актуальным" и не загружало повторно собственную поставляемую версию. Это
**локальная доверенная затравка**: без подписи и безключевая, так что CI может собрать её, ни разу не
касаясь ключа подписи:

```sh
producer/vdlu-pack  <module>  ./seed  <module> <versionCode> --version-name v<versionCode>
cp ./seed/manifest.json <module>/vdlu/baseline.json
```

Его отсутствие не фатально: устройство просто стартует с версии `0` при
первом обновлении.

---

Вот и всё внедрение. Прежде чем поставлять, `sh -n <module>/vdlu/update.sh`
должен пройти, и вам следует протестировать продюсер и движок от начала до конца, как показано в
[[Contributing]] и [[Producer]].
