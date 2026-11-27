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

# VD Live Update

> **Languages:** [English](README.md) · [العربية](README.ar.md) · [Čeština](README.cs.md) · [Deutsch](README.de.md) · [Español](README.es.md) · [فارسی](README.fa.md) · [Français](README.fr.md) · [हिन्दी](README.hi.md) · [Bahasa Indonesia](README.id.md) · [Italiano](README.it.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Nederlands](README.nl.md) · [Polski](README.pl.md) · [Português](README.pt.md) · [Русский](README.ru.md) · [Svenska](README.sv.md) · [ไทย](README.th.md) · [Türkçe](README.tr.md) · Українська · [Tiếng Việt](README.vi.md) · [中文](README.zh.md)

<p align="center">
  <img src="images/logo-wordmark.png" alt="VD Live Update" width="320">
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-Apache--2.0-1a7f37" alt="License"></a>
  <a href="https://github.com/VD171/VDLiveUpdate/stargazers"><img src="https://img.shields.io/github/stars/VD171/VDLiveUpdate?color=d29922" alt="Stars"></a>
</p>

<p align="center">
  <a href="docs/QUICKSTART.md">Quickstart</a> ·
  <a href="docs/ENGINE.md">Engine</a> ·
  <a href="docs/PRODUCER.md">Producer</a> ·
  <a href="docs/WEBUI.md">WebUI</a> ·
  <a href="docs/INTERFACES.md">Interfaces</a> ·
  <a href="docs/AI-AGENTS.md">AI agents</a> ·
  <a href="docs/TRUST-MODEL.md">Trust model</a>
</p>

**VDLU** є flashless-рушієм інкрементного самооновлення для модулів **KernelSU / APatch / Magisk**. Встановлений модуль оновлює себе, завантажуючи **лише файли, що змінилися** (адресовані за вмістом блоби + підписаний маніфест), застосовує "живі" **без перезавантаження** й готує та позначає ті кілька, що перезавантаження таки потребують (`.so`, overlay у `/system`, `sepolicy.rule`). Без менеджера root, без повторного завантаження цілого `.zip`, без перезавантаження, окрім як для цих підготовлених файлів.

Його задумано як **vendored**-залежність усередині модуля (укладається в `<module>/vdlu/`), а не як окремий модуль.

## Навіщо

Звичайне оновлення модуля щоразу постачає цілий `.zip`. Для великого модуля це означає велике повторне завантаження заради кількох змінених рядків, а статичний маніфест оновлення може вказувати лише на один `zipUrl`, тож він не здатен обслужити той flavor (ABI, full vs lite), який реально має пристрій. VDLU порівнює **встановлене** дерево з підписаним feed і завантажує лише дельти, тож інсталяція arm64-full лишається arm64-full, lite-інсталяція лишається lite, і більшість оновлень застосовуються наживо.

## Як це працює

- **Producer (ПК / реліз):** `vdlu-pack` перетворює дерево модуля на адресований за вмістом feed (`manifest.json` + `blobs/<sha256>`, gzip, dedup, `delete[]`), `vdlu-keygen` / `vdlu-sign` (ed25519), `vdlu-gc` вичищає осиротілі блоби за посиланнями на останні N маніфестів (fail-safe, за замовчуванням dry-run).
- **Engine (пристрій):** POSIX sh, без `jq`. `update.sh` (`check | run | resume | boot | status | cancel`) виконує DIFF -> FETCH -> APPLY -> COMMIT як **відновлювану транзакцію** (журнал), з відкатом і блокуванням через `mkdir`. Підпис перевіряється вбудованим `ed25519-mini` (без `openssl` на пристрої).
- **WebUI:** готова до вбудовування панель Updates (спливне сповіщення про прогрес, скасування, банер перезавантаження), чистий JS.

## Профілі

- `trusted`: приватне використання, джерело `file://` або SSH, перевірка за можливості (хеш завжди).
- `hardened`: публічне використання, **підпис обов'язковий**, пониження версії заблоковано. Маніфест **прив'язаний до id модуля**, і кожне поле валідується fail-closed, перш ніж бодай щось буде завантажено.

## Впровадження у вашому модулі

Укладіть `engine/update.sh` + `vdlu-verify` + `verify/<abi>/ed25519-mini` у `<module>/vdlu/`, вбудуйте ваш **сирий 32-байтовий публічний ключ** як `vdlu/keyring/<id>.pub`, додайте `config` (профіль + джерело), пов'яжіть тригери (`post-fs-data.sh` pre-zygote для автооновлення під час завантаження, тригер відкриття WebUI) і додайте `vdlu-pack` + `vdlu-sign` до вашого релізу. Робочий шаблон див. у [`docs/QUICKSTART.md`](docs/QUICKSTART.md).

## Безпека

- **Кожне поле маніфесту є ворожим входом.** `validate_plan()` відхиляє весь маніфест fail-closed на абсолютному шляху чи шляху з `..`, на `sha256`, що не є 64 hex-символами, або на недійсному режимі / класі / кодуванні, **перш** ніж відбудеться будь-який fetch чи apply.
- **Приватний ключ підпису ніколи не торкається CI чи пристрою**, вбудовується лише сирий публічний ключ, а перевірка використовує `ed25519-mini`, а не `openssl`.
- `hardened` є fail-closed за інверсією: будь-що, окрім буквального `trusted`, трактується як `hardened`, тож пошкоджене значення профілю ніколи не зможе тихо прийняти непідписаний маніфест.
- Файли класу reboot (`.so`, overlay у `/system`, `sepolicy.rule`) **готуються, їх ніколи не пишуть поверх живого inode**, усе інше застосовується наживо. Невдале застосування перериває роботу, а не перезаписує без резервної копії.

## Збирання / тестування

Це скрипти, компілювати нічого. Наскрізне (producer + engine разом):

```sh
producer/vdlu-keygen demo /tmp/k
producer/vdlu-pack /tmp/tree /tmp/feed demo 1 --version-name v1
producer/vdlu-sign /tmp/feed/manifest.json /tmp/k/demo.pem demo
VDLU_DIR=... MODULE_DIR=... MODID=demo sh engine/update.sh check   # then run / boot
```

`sh -n engine/*.sh`, `node --check webui/vdlu.js`, і відкрийте `webui/demo.html` у браузері (він імітує місток до пристрою).

## AI-агенти

Рушій керується повністю з оболонки (`sh engine/update.sh <check|run|resume|boot|status|cancel>` виводить машиночитаний статус), тож ШІ-агент може перевірити, застосувати та відновити оновлення без інтерфейсу. Контракт стику між компонентами описано в [`docs/INTERFACES.md`](docs/INTERFACES.md), а патчі від ШІ проходять той самий рівень перевірки, що й будь-які інші.

## Документація

- [`INTERFACES.md`](docs/INTERFACES.md): контракт стику між компонентами (закон конвергенції, трактуйте його як незмінний).
- [`ENGINE.md`](docs/ENGINE.md): рушій на боці пристрою (`update.sh`): відновлювана транзакція DIFF -> FETCH -> APPLY -> COMMIT.
- [`PRODUCER.md`](docs/PRODUCER.md): бік ПК/релізу: збирання та підписання адресованого за вмістом фіду (`vdlu-pack`, `vdlu-sign`).
- [`WEBUI.md`](docs/WEBUI.md): вбудовуваний віджет панелі Updates (сповіщення про прогрес, скасування, банер перезавантаження).
- [`docs/QUICKSTART.md`](docs/QUICKSTART.md): покроковий посібник з впровадження та фрагменти для пов'язування.

## Дивіться також

- **[COPG-VD](https://github.com/VD171/COPG-VD)**: підміна глобального fingerprint пристрою / Play Integrity, для всього пристрою з областю дії для кожного застосунку та WebUI.
- **[VDBackup](https://github.com/VD171/VD-Backup)**: повне резервне копіювання та відновлення застосунків і даних із правами root, повністю кероване з WebUI.
- **[VD-dropbear](https://github.com/VD171/VD-dropbear)**: автономний SSH-демон із root-правами (Dropbear).
- **[VDGoogle](https://github.com/VD171/VD-Google)**: ваші сервіси Google (RCS, Wallet, атестації Play Integrity), прочитані на вашому пристрої без інтернету.
- **[VDInstaller](https://github.com/VD171/VD-Installer)**: безперешкодний root-інсталятор sideload для одиночних, пакетних і розділених APK, з перемикачем верифікатора Play Protect та підробкою джерела встановлення.
- **[VDInfos](https://github.com/VD171/VD-Infos)**: налагоджувач методів пристрою, який читає кожен елемент через кожен метод, що може його прочитати, і порівнює їх пліч-о-пліч.
- **[VD-Modules](https://github.com/VD171/VD-Modules)**: наш репозиторій модулів для MMRL/WebUI-X (встановіть усе це з вашого root-менеджера).
- **[@VictorGabriel7Dev/build.prop](https://github.com/VictorGabriel7Dev/build.prop)**: набір даних fingerprint-ів `build.prop` від Pixel (форк @T3SL4).
- **[@VictorGabriel7Dev/mtproto-store](https://github.com/VictorGabriel7Dev/mtproto-store)**: використовуйте Telegram як об'єктне сховище з крихітного CLI на Go.

## Contacts

- https://vd171.ru
- https://vd.priv8.ru
- **Telegram:** @VD_Priv8 https://t.me/VD_Priv8
- **Channel:** @Priv8_VD https://t.me/Priv8_VD
- **Discord:** @VD.Priv8 https://discord.com/users/1296831918989639721
- **E-mail:** vd.priv8@pm.me
- **XDA-Developers:** @VD171 https://xdaforums.com/m/vd171.4699873/
- **GitHub:** @VD171 https://github.com/VD171

## Ліцензія

Власний код VDLiveUpdate поширюється під **Apache-2.0**, див. [LICENSE](LICENSE). Він укладає невеликий верифікатор `ed25519-mini`
та статичний `curl` для bootstrap завантаження, кожен під власною ліцензією, див.
[NOTICE.md](NOTICE.md) та файли `PROVENANCE.json` поруч із вбудованими бінарниками.

## Торгові марки

VDLiveUpdate є незалежним, неофіційним проєктом, не пов'язаним із жодною третьою стороною й не схваленим нею.
"Android" є торговою маркою Google LLC, "KernelSU", "Magisk" та "APatch" є марками їхніх
відповідних авторів. VDLU працює цілком на вашому пристрої та на вашому власному хості релізів.

## Tags

`VDLU` `flashless-update` `incremental-update` `KernelSU` `Magisk` `APatch` `module-update` `ed25519` `content-addressed` `OTA` `self-update` `Android` `VDLiveUpdate`

---

📣 **Приєднуйтесь до каналу для оновлень:** @Priv8_VD https://t.me/Priv8_VD
