> **Languages:** [English](../ENGINE.md) · [العربية](../ar/ENGINE.md) · [Čeština](../cs/ENGINE.md) · [Deutsch](../de/ENGINE.md) · [Español](../es/ENGINE.md) · [فارسی](../fa/ENGINE.md) · [Français](../fr/ENGINE.md) · [हिन्दी](../hi/ENGINE.md) · [Bahasa Indonesia](../id/ENGINE.md) · [Italiano](../it/ENGINE.md) · [日本語](../ja/ENGINE.md) · [한국어](../ko/ENGINE.md) · [Nederlands](../nl/ENGINE.md) · [Polski](../pl/ENGINE.md) · [Português](../pt/ENGINE.md) · [Русский](../ru/ENGINE.md) · [Svenska](../sv/ENGINE.md) · [ไทย](../th/ENGINE.md) · [Türkçe](../tr/ENGINE.md) · Українська · [Tiếng Việt](../vi/ENGINE.md) · [中文](../zh/ENGINE.md)

---

# VDLU engine (`update.sh`)

Flashless, інкрементальний клієнт оновлення для модулів KSU/Magisk. Реалізує цикл
`DIFF -> FETCH -> APPLY -> COMMIT` як поновлювану транзакцію. Узгоджується з `INTERFACES.md` (закон
конвергенції).

Чистий POSIX sh (mksh/busybox/toybox). **SLIM:** залежить лише від toybox (`sha256sum`/`gzip`/`base64`/`date`) +
вбудований `ed25519-mini` (ed25519 verify, **без openssl на пристрої**) + статичний `curl`, **завантажений** під час
першого https-оновлення (WebUI робить `fetch()`, зберігає його в Tier-2, а `install-tool` перевіряє його
підпис+геш ПЕРЕД використанням). `file://` не потребує curl. Нуль залежності від `jq`.

## Виклик

```sh
VDLU_DIR=/data/adb/<mod>/vdlu MODULE_DIR=/data/adb/modules/<mod> MODID=<mod> \
  sh $MODULE_DIR/vdlu/update.sh <cmd>
```

`rc 0` = ok, `rc != 0` = помилка (причина на stderr). `vdlu-verify` постачається іншим компонентом
(підпис у `INTERFACES.md §6`), engine лише викликає його.

| cmd | що робить |
|---|---|
| `check` | read-only DIFF; друкує `{"update":bool,"from":N,"to":M,"fetch":K,"reboot":bool}`; нічого не змінює |
| `run` | повний LIVE-цикл + стейджить REBOOT-hard; шанує `cancel`; прогрес у `journal.json` |
| `resume` | поновлює незавершену транзакцію (`target.json`) з поточної фази; ідемпотентно; **не** обмінює `.so` |
| `boot` | режим pre-zygote: resume **+** обмінює `staged/*.vdlu-new` → закриває `PENDING_REBOOT`→`DONE`. Без незавершеної транзакції виконує свіжий цикл і застосовує все (включно з `.so`) за одне завантаження |
| `status` | друкує `journal.json` (або `{"state":"idle"}`) |
| `cancel` | створює `$VDLU_DIR/cancel`; `run` у процесі зупиняється на наступній безпечній точці |

## Машина станів (journal.json)

```
PLANNED -> FETCHING -> FETCHED -> APPLYING -> APPLIED_LIVE -> (PENDING_REBOOT | DONE)
```

`DONE` лише коли повторне гешування УСЬОГО збігається. Якщо застейджено будь-який REBOOT-hard ⇒ `PENDING_REBOOT` (ніколи
фальшивий `DONE`). `ERROR` на будь-якому збої, без пошкодження модуля (застосовані LIVE-файли відкочуються
з `rollback/<v>/`, нічого "напівзастосованого, що про це бреше"). Доброякісний вихід фази `fetch`: **`DEFERRED`** -
завантаження було відкладене `net_policy` (мережа не дозволена), plan/target зберігаються і воно поновлюється на наступній
перевірці/boot (WebUI показує синій інфо-тост "очікування мережі X", не помилку).

## Гарантії суворості

- **FETCH:** контролюється `net_policy` (any/wifi/mobile, лише http/https, `file://` ніколи) - недозволена мережа ⇒
  `DEFERRED` (поновлюване), без витрати даних. Завантажує лише те, чого бракує, у `<sha>.part` (curl з
  `--connect-timeout` + `--speed-time`, ніколи не зависає), розпаковує `gz` (toybox `gunzip`), перевіряє `sha256sum` ==
  маніфест, атомарний `mv` до `blobs/<sha>`. Кешований+ok блоб пропускається. Може засіяти блоб з незмінного
  локального файлу (dedup/offline). **3 збої на одному блобі = фаза переривається, нічого не застосовуючи.** Воно
  стає `FETCHED` лише коли ВСІ блоби плану присутні+перевірені. Під час налаштування toolchain воно логує
  розв'язану довіру TLS (path до CA + читабельність, розмір bundle і кількість сертифікатів), тож curl
  `rc 77` під час boot сам себе пояснює в `boot.log` - воно відрізняє порожнє сховище від нечитабельного
  (випадок SELinux-контексту при boot).
- **APPLY** (лише з `FETCHED`): `live`/`soft` → резервна копія до `rollback/<v>/` → `.vdlu-tmp` → `chmod` → verify →
  атомарний `rename`. `reboot` → матеріалізується в `staged/<path>.vdlu-new` (НЕ чіпає живий inode).
  `delete[]` → резервна копія → видалення. Ідемпотентно (файл уже на цільовому геші пропускається).
- **COMMIT:** повторне гешування кожного `live`/`soft`, лише тоді пише `current.json`. Із застейдженими файлами ⇒
  `PENDING_REBOOT`. `boot` робить `mv -f staged/....vdlu-new $MODULE_DIR/<path>` (pre-zygote) + повторно перевіряє +
  `DONE`.
- **cancel:** перевіряється між файлами (безпечна точка), видаляє `.vdlu-tmp`/`.part` у польоті, видаляє `cancel`,
  лишає журнал поновлюваним (`cancelled:true`, `error:null`).
- **mkdir-lock `$VDLU_DIR/lock.d`** серіалізує (flock непрацездатний на toybox, відновлення застарілого за PID).
  ТЕРПЛЯЧИЙ boot-retry не утримує замок під час очікування (`acquire_lock_try`+release між спробами) ні
  wakelock - безпечно для батареї. Крах/мережа/перезавантаження посередині → `resume`/`boot` продовжує.
- **profile=hardened** ⇒ `vdlu-verify` обов'язковий на маніфесті ПЕРЕД використанням, збій = abort, downgrade заблоковано
  (монотонна версія). **trusted** ⇒ verify є best-effort, але геш кожного блоба ЗАВЖДИ перевіряється.
- **Allowlist ключа module-update (обидва profiles):** `verify_manifest` відхиляє, fail-closed, будь-який маніфест, чий `key_id` не входить до налаштованої allowlist `key_id` (див. INTERFACES §5/§6), ПЕРЕД вибором pubkey, тож ключ нижчої довіри, що лише лежить у keyring (напр., ключ fingerprint-feed), ніколи не може підписати flashless root-оновлення. Безпечно за замовчуванням, коли невстановлено: keyring з одним ключем = лише той один ключ, багатоключовий keyring = відхилено, доки `key_id` не закріплено.
- **Виключення якоря довіри (VDLU#2):** engine ІГНОРУЄ кожен path `vdlu/` у завантаженому плані (`update.sh`, `vdlu-verify`, `verify/*`, `keyring/*`, config) - ніколи не завантажує, не застосовує й не видаляє - навіть якщо підписана стрічка їх несе. Стрічка ніколи не може обміняти verifier чи ключ підпису на пристрої, якір довіри змінюється лише через повну підписану повторну прошивку, тож один витеклий ключ підпису не може зберегти root по мережі.
- **Відкладення під час зайнятості (opt-in `apply_busy_file`):** коли `apply_busy_file` встановлено (абсолютний path, який хост-модуль торкається під час власних операцій, напр. активна резервна копія), APPLY відкладається, доки цей path існує - оновлення ніколи не обмінює файли модуля посеред операції. Блоби вже завантажені, тож наступний тригер застосовує без повторного завантаження.
- **Обмеження розміру:** 128 MiB на файл (`MAX_FILE_BYTES`) і 2 MiB на маніфест (`MAX_MANIFEST_BYTES`), застосовані перед читанням як у `update.sh`, так і у `vdlu-verify` (anti decompression-bomb / anti-OOM).
- Деградує граційно: відсутній бінарник / мережа лежить / диск повний → ясна помилка на stderr + `state:ERROR` у
  журналі, без пошкодження модуля.

## Розбір JSON без jq

Flattener у gron-стилі на `awk` (чистий POSIX: `substr`/`index`/`gsub`/`split`/`printf` + локальні, передані як
параметри) токенізує маніфест символ за символом і видає один рядок `path<TAB>value` на кожен скалярний лист
(`files/0/sha256<TAB>ab..`, `version<TAB>6`, `delete/0<TAB>etc/x`). Стійкий проти компактного АБО форматованого
JSON. `sh` споживає його через `grep`/`cut`, пофайловий план збирається в 2-му `awk` у TSV
(`class st mode enc sha size path`), який стає `$VDLU_DIR/plan.tsv`.

## Файли стану (у `$VDLU_DIR`, Tier-2)

| файл | роль |
|---|---|
| `config` | key=value (`source`/`profile`/`channel`/`net_policy`/`key_id`/`apply_busy_file`/`boot_retry_*`/…; див. INTERFACES §5) |
| `current.json` | маніфест АКТИВНОЇ версії (база diff); відсутній = ніколи не оновлювався |
| `target.json` | зафіксований маніфест транзакції в польоті (наявність = активна транзакція); стає `current.json` на `DONE` |
| `plan.tsv` / `plan.del` | план + пофайловий прогрес (st) / шляхи для видалення |
| `journal.json` | прогрес для WebUI (регенерується на кожному переході) |
| `blobs/<sha256>` | кеш перевіреного оригінального вмісту |
| `rollback/<version>/<path>` | резервна копія перезаписаних файлів (undo; зберігає останні 3) |
| `staged/<path>.vdlu-new` | REBOOT-hard, що очікує обміну під час завантаження |
| `lock.d/` | mkdir-lock (flock непрацездатний на toybox; відновлення застарілого за PID) |
| `tools/<abi>/curl` | завантажений статичний curl (slim bootstrap); зберігається між оновленнями |
| `cancel` | запит на скасування |

<!-- doc-footer -->

---

> _Ця документація створена за допомогою Claude (Anthropic) і підтримується VD171. Виправлення та покращення вітаються, див. [CONTRIBUTING.md](CONTRIBUTING.md)._
