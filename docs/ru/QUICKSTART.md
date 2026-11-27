> **Languages:** [English](../QUICKSTART.md) · [العربية](../ar/QUICKSTART.md) · [Čeština](../cs/QUICKSTART.md) · [Deutsch](../de/QUICKSTART.md) · [Español](../es/QUICKSTART.md) · [فارسی](../fa/QUICKSTART.md) · [Français](../fr/QUICKSTART.md) · [हिन्दी](../hi/QUICKSTART.md) · [Bahasa Indonesia](../id/QUICKSTART.md) · [Italiano](../it/QUICKSTART.md) · [日本語](../ja/QUICKSTART.md) · [한국어](../ko/QUICKSTART.md) · [Nederlands](../nl/QUICKSTART.md) · [Polski](../pl/QUICKSTART.md) · [Português](../pt/QUICKSTART.md) · Русский · [Svenska](../sv/QUICKSTART.md) · [ไทย](../th/QUICKSTART.md) · [Türkçe](../tr/QUICKSTART.md) · [Українська](../uk/QUICKSTART.md) · [Tiếng Việt](../vi/QUICKSTART.md) · [中文](../zh/QUICKSTART.md)

---

# Quickstart по внедрению VDLU

Чек-лист «скопируй-вставь» для вендоринга **VDLiveUpdate** в модуль. VDLU сам по себе не
модуль: он кладётся в `<module>/vdlu/` и едет внутри zip вашего модуля. Полное обоснование см.
в [`INTERFACES.md`](INTERFACES.md) (контракт шва),
[`ENGINE.md`](ENGINE.md), [`PRODUCER.md`](PRODUCER.md) и [`WEBUI.md`](WEBUI.md).

Замените `<id>` на id вашего ключа подписи, `<abi>` на ABI устройства, которые вы поставляете
(`arm64-v8a`, `armeabi-v7a`, `x86_64`, `x86`), а `<module>` на дерево вашего модуля.

## Целевой макет

Это точное дерево `vdlu/`, которое модуль несёт после внедрения:

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

Изменяемое состояние engine (`config`, `current.json`, journal, lock) живёт в
Tier-2, `/data/adb/<modid>/vdlu/`, вне каталога модуля, `config.default` засевает его при
первом запуске.

## 1. Вендорьте engine

Скопируйте engine, shim verify и per-ABI верификатор в `<module>/vdlu/`:

```sh
mkdir -p <module>/vdlu/verify
cp engine/update.sh      <module>/vdlu/update.sh
cp engine/vdlu-verify    <module>/vdlu/vdlu-verify
cp -r verify/<abi>       <module>/vdlu/verify/<abi>      # ed25519-mini per ABI
```

Поставляйте только те ABI, которые поддерживаете, `customize.sh` может подрезать `verify/` до
ABI устройства во время установки.

## 2. Сгенерируйте ключ подписи (единоразово)

```sh
producer/vdlu-keygen <id> ./keys
```

Это выдаёт `<id>.pem` (приватный, держите его вдали от каждого устройства и от любого пуша в
репо), `<id>.pub` (PEM, только на стороне ПК) и `<id>.pub.raw` (RAW 32 байта, для keyring
устройства).

## 3. Встройте сырой публичный ключ

Keyring устройства держит ключ **RAW 32 байта**, никогда PEM (`ed25519-mini`
не может прочитать PEM):

```sh
mkdir -p <module>/vdlu/keyring
cp ./keys/<id>.pub.raw <module>/vdlu/keyring/<id>.pub
```

Keyring стабилен между релизами (он меняется только при ротации ключа): при
пере-вендоринге **проверяйте, не перезаписывайте**.

## 4. Напишите config

Поставляйте `config.default` в `<module>/vdlu/` (засевает `config` в Tier-2 при первом запуске):

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

Используйте `profile=trusted` только для приватного источника `file://`/SSH (verify по
возможности, sha256 каждого блоба всё равно проверяется). Любое значение, кроме буквального
`trusted`, трактуется как `hardened` (fail-closed).

## 5. Подключите триггеры

**При перезагрузке** (`auto_on_reboot`): вызовите engine pre-zygote из `post-fs-data.sh`,
чтобы staged файлы (`.so`, оверлей `/system`, `sepolicy.rule`) подменились без лишней
перезагрузки:

```sh
# <module>/post-fs-data.sh
MODDIR=${0%/*}
sh "$MODDIR/vdlu/update.sh" boot
```

**При открытии WebUI** (`auto_on_webui_open`): подключите готовую панель Updates в вашем
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

(`vdlu.js` / `vdlu.css` вендорятся из `webui/`, перевод можно добавить через
`i18n: window.VDLU_I18N_<LANG>`.)

## 6. Подпишите фид в вашем workflow релиза

На каждый релиз упакуйте финальное дерево модуля и подпишите манифест. Держите приватный ключ
на машине оператора, никогда в CI:

```sh
producer/vdlu-pack  <module>  ./out  <module> <versionCode> --version-name v<versionCode> --channel stable \
                    [--prev ./prev/manifest.json]        # delete[] = paths gone since prev
producer/vdlu-sign  ./out/manifest.json  ./keys/<id>.pem  <id>
# publish ./out/{manifest.json,blobs/} to <source>
```

## 7. Поставьте baseline

Сгенерируйте `baseline.json` над поставляемым деревом и поместите его в
`<module>/vdlu/baseline.json`. Он засевает `current.json` при чистой установке, чтобы
устройство рождалось «актуальным» (без повторной загрузки). Это **локальное доверенное семя**:
без подписи и без ключа, поэтому CI может собрать его, ни разу не касаясь ключа подписи:

```sh
producer/vdlu-pack  <module>  ./seed  <module> <versionCode> --version-name v<versionCode>
cp ./seed/manifest.json <module>/vdlu/baseline.json
```

Не фатально при отсутствии (устройство просто начинает с `0` при первом обновлении).

---

Это всё внедрение целиком. `sh -n <module>/vdlu/update.sh` должен пройти, протестируйте
producer и engine от начала до конца, как показано в [`PRODUCER.md`](PRODUCER.md) и в корневом
README, прежде чем поставлять.

<!-- doc-footer -->

---

> _Эта документация создана с помощью Claude (Anthropic) и поддерживается VD171. Исправления и улучшения приветствуются, см. [CONTRIBUTING.md](CONTRIBUTING.md)._
