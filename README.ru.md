<!--
  ======================================================================
   VDLiveUpdate (VDLU)  ::  flashless, incremental module updates
   A self-update engine for KernelSU/APatch/Magisk modules: fetch only the
   files that changed, apply the live ones with no reboot, verified by ed25519.

   Copyright (C) 2026  VD171
   SPDX-License-Identifier: Apache-2.0

   Licensed under the Apache License, Version 2.0; you may obtain a copy at
   http://www.apache.org/licenses/LICENSE-2.0

   Site           : https://vd171.ru
   Site           : https://vd.priv8.ru
   Source         : https://github.com/VD171/VDLiveUpdate
   GitHub         : @VD171 https://github.com/VD171
   XDA-Developers : @VD171 https://xdaforums.com/m/vd171.4699873/
   Telegram       : @VD_Priv8 https://t.me/VD_Priv8
   Channel        : @Priv8_VD https://t.me/Priv8_VD
   Discord        : @VD.Priv8 https://discord.com/users/1296831918989639721
   E-mail         : vd.priv8@pm.me
  ======================================================================
-->

# VDLiveUpdate

> **Languages:** [English](README.md) · [العربية](README.ar.md) · [Čeština](README.cs.md) · [Deutsch](README.de.md) · [Español](README.es.md) · [فارسی](README.fa.md) · [Français](README.fr.md) · [हिन्दी](README.hi.md) · [Bahasa Indonesia](README.id.md) · [Italiano](README.it.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Nederlands](README.nl.md) · [Polski](README.pl.md) · [Português](README.pt.md) · [Русский](README.ru.md) · [Svenska](README.sv.md) · [ไทย](README.th.md) · [Türkçe](README.tr.md) · [Українська](README.uk.md) · [Tiếng Việt](README.vi.md) · [中文](README.zh.md)

**VDLU** - это инкрементальный движок самообновления без прошивки для модулей **KernelSU / APatch / Magisk**. Установленный модуль обновляет себя сам, скачивая **только изменившиеся файлы** (блобы с адресацией по содержимому + подписанный манифест), применяет обновляемые на лету **без перезагрузки**, а те немногие, которым перезагрузка действительно нужна (`.so`, оверлей `/system`, `sepolicy.rule`), подготавливает и помечает. Без менеджера root, без повторного скачивания всего `.zip`, без перезагрузки, кроме как ради этих подготовленных файлов.

Он рассчитан на то, чтобы быть **встроенным (vendored)** в модуль (скопированным в `<module>/vdlu/`), а не запускаться как отдельный модуль.

## Зачем

Обычное обновление модуля снова доставляет весь `.zip`. Для большого модуля это означает крупное повторное скачивание ради нескольких изменённых строк, а статический манифест обновления может указывать лишь на один `zipUrl`, поэтому он не способен отдать именно тот вариант (ABI, full или lite), который реально установлен на устройстве. VDLU сравнивает **установленное** дерево с подписанным фидом и скачивает только дельты, так что установка arm64-full остаётся arm64-full, установка lite остаётся lite, а большинство обновлений применяется на лету.

## Как это работает

- **Производитель (ПК / релиз):** `vdlu-pack` превращает дерево модуля в фид с адресацией по содержимому (`manifest.json` + `blobs/<sha256>`, gzip, дедупликация, `delete[]`); `vdlu-keygen` / `vdlu-sign` (ed25519); `vdlu-gc` удаляет осиротевшие блобы по ссылкам на последние N манифестов (fail-safe, по умолчанию dry-run).
- **Движок (устройство):** POSIX sh, без `jq`. `update.sh` (`check | run | resume | boot | status | cancel`) выполняет DIFF -> FETCH -> APPLY -> COMMIT как **возобновляемую транзакцию** (журнал), с откатом и блокировкой через `mkdir`. Подпись проверяется встроенным `ed25519-mini` (без `openssl` на устройстве).
- **WebUI:** готовая к встраиванию панель Updates (тост прогресса, отмена, баннер перезагрузки), чистый JS.

## Профили

- `trusted`: приватное использование, источник `file://` или SSH, проверка best-effort (хеш всегда).
- `hardened`: публичное использование, **подпись обязательна**, понижение версии заблокировано. Манифест **привязан к id модуля**, и каждое поле проверяется по принципу fail-closed до того, как что-либо будет скачано.

## Внедрите его в свой модуль

Встройте `engine/update.sh` + `vdlu-verify` + `verify/<abi>/ed25519-mini` в `<module>/vdlu/`, вложите свой **сырой 32-байтовый открытый ключ** как `vdlu/keyring/<id>.pub`, добавьте `config` (профиль + источник), подключите триггеры (`post-fs-data.sh` до zygote для автообновления при загрузке; триггер открытия WebUI) и добавьте `vdlu-pack` + `vdlu-sign` в свой релиз. Готовый шаблон смотрите в [`integration/`](integration/).

## Безопасность

- **Любое поле манифеста - враждебный ввод.** `validate_plan()` отклоняет весь манифест по принципу fail-closed при абсолютном пути или пути с `..`, при `sha256`, в котором не 64 hex-символа, либо при недопустимом mode / class / encoding, **до** любого fetch или apply.
- **Приватный ключ для подписи никогда не касается CI или устройства**; встраивается только сырой открытый ключ, а проверка использует `ed25519-mini`, а не `openssl`.
- `hardened` работает по принципу fail-closed через инверсию: всё, что не является буквальным `trusted`, трактуется как `hardened`, поэтому повреждённое значение профиля никогда не сможет молча принять неподписанный манифест.
- Файлы класса перезагрузки (`.so`, оверлей `/system`, `sepolicy.rule`) **подготавливаются, но никогда не записываются поверх живого inode**; всё остальное применяется на лету. Неудавшийся apply прерывается, а не перезаписывает без резервной копии.

## Сборка / тестирование

Это скрипты, компилировать нечего. Сквозной сценарий (производитель + движок вместе):

```sh
producer/vdlu-keygen demo /tmp/k
producer/vdlu-pack /tmp/tree /tmp/feed demo 1 --version-name v1
producer/vdlu-sign /tmp/feed/manifest.json /tmp/k/demo.pem demo
VDLU_DIR=... MODULE_DIR=... MODID=demo sh engine/update.sh check   # затем run / boot
```

`sh -n engine/*.sh`, `node --check webui/vdlu.js` и открытие `webui/demo.html` в браузере (он мокает мост с устройством).

## Документация

- [`INTERFACES.md`](INTERFACES.md): контракт стыка между компонентами (закон сходимости; считайте его неизменным).
- `integration/`: пошаговое руководство по внедрению и фрагменты для подключения.

## Смотрите также

Родственные проекты того же автора:

- **[VDBackup](https://github.com/VD171/VD-Backup)**: полное резервное копирование и восстановление приложений и данных с правами root, полностью управляемое из WebUI.
- **[COPG-VD](https://github.com/VD171/COPG-VD)**: спуфер устройства, превращающий свежий fingerprint в согласованный, непротиворечивый профиль.
- **[VD-dropbear](https://github.com/VD171/VD-dropbear)**: автономный, настраиваемый SSH-демон с root для KernelSU/APatch/Magisk.
- **[VDInfos](https://github.com/VD171/VD-Infos)**: отладчик методов устройства, читающий каждый элемент всеми методами, способными его прочитать.
- **[VDGoogle](https://github.com/VD171/VD-Google)**: читает то, что Google записывает на вашем устройстве, полностью на устройстве и без интернета.

## Контакты

- https://vd171.ru
- https://vd.priv8.ru
- **Telegram:** @VD_Priv8 https://t.me/VD_Priv8
- **Channel:** @Priv8_VD https://t.me/Priv8_VD
- **Discord:** @VD.Priv8 https://discord.com/users/1296831918989639721
- **E-mail:** vd.priv8@pm.me
- **XDA-Developers:** @VD171 https://xdaforums.com/m/vd171.4699873/
- **GitHub:** @VD171 https://github.com/VD171

## Лицензия

Собственный код VDLiveUpdate распространяется под **Apache-2.0**; см. [LICENSE](LICENSE). Он встраивает небольшой
верификатор `ed25519-mini` и статический `curl` для бутстрапа загрузки, каждый под своей лицензией; см.
[NOTICE.md](NOTICE.md) и файлы `PROVENANCE.json` рядом с включёнными бинарными файлами.

## Товарные знаки

VDLiveUpdate - независимый, неофициальный проект, не связанный с какой-либо третьей стороной и не одобренный ею.
"Android" - товарный знак Google LLC; "KernelSU", "Magisk" и "APatch" - знаки их
соответствующих авторов. VDLU работает целиком на вашем устройстве и на вашем собственном хосте релизов.

## Tags

`VDLU` `flashless-update` `incremental-update` `KernelSU` `Magisk` `APatch` `module-update` `ed25519` `content-addressed` `OTA` `self-update` `Android` `VDLiveUpdate`

---

📣 **Join the channel for updates:** @Priv8_VD https://t.me/Priv8_VD
