> **Languages:** [English](../ENGINE.md) · [العربية](../ar/ENGINE.md) · [Čeština](../cs/ENGINE.md) · [Deutsch](../de/ENGINE.md) · [Español](../es/ENGINE.md) · [فارسی](../fa/ENGINE.md) · [Français](../fr/ENGINE.md) · [हिन्दी](../hi/ENGINE.md) · [Bahasa Indonesia](../id/ENGINE.md) · [Italiano](../it/ENGINE.md) · [日本語](../ja/ENGINE.md) · [한국어](../ko/ENGINE.md) · [Nederlands](../nl/ENGINE.md) · [Polski](../pl/ENGINE.md) · [Português](../pt/ENGINE.md) · Русский · [Svenska](../sv/ENGINE.md) · [ไทย](../th/ENGINE.md) · [Türkçe](../tr/ENGINE.md) · [Українська](../uk/ENGINE.md) · [Tiếng Việt](../vi/ENGINE.md) · [中文](../zh/ENGINE.md)

---

# Engine VDLU (`update.sh`)

Flashless инкрементальный клиент обновлений для модулей KSU/Magisk. Реализует цикл
`DIFF -> FETCH -> APPLY -> COMMIT` как возобновляемую транзакцию. Соответствует `INTERFACES.md` (закон
сходимости).

Чистый POSIX sh (mksh/busybox/toybox). **SLIM:** зависит только от toybox (`sha256sum`/`gzip`/`base64`/`date`) +
встроенного `ed25519-mini` (verify ed25519, **без openssl на устройстве**) + статического `curl`, **загружаемого** при
первом https-обновлении (WebUI делает `fetch()`, сохраняет его в Tier-2, а `install-tool` проверяет его
подпись+хэш ПЕРЕД использованием). `file://` не нуждается в curl. Нулевая зависимость от `jq`.

## Вызов

```sh
VDLU_DIR=/data/adb/<mod>/vdlu MODULE_DIR=/data/adb/modules/<mod> MODID=<mod> \
  sh $MODULE_DIR/vdlu/update.sh <cmd>
```

`rc 0` = ok, `rc != 0` = ошибка (причина в stderr). `vdlu-verify` поставляется другим компонентом
(подпись в `INTERFACES.md §6`), engine только вызывает его.

| cmd | делает |
|---|---|
| `check` | DIFF только для чтения; печатает `{"update":bool,"from":N,"to":M,"fetch":K,"reboot":bool}`; ничего не меняет |
| `run` | полный LIVE-цикл + инсценирует REBOOT-hard; учитывает `cancel`; прогресс в `journal.json` |
| `resume` | возобновляет ожидающую транзакцию (`target.json`) с текущей фазы; идемпотентно; **не** делает swap `.so` |
| `boot` | режим pre-zygote: resume **+** делает swap файлов `staged/*.vdlu-new` → закрывает `PENDING_REBOOT`→`DONE`. Без ожидающей транзакции запускает свежий цикл и применяет всё (включая `.so`) за одну загрузку |
| `status` | печатает `journal.json` (или `{"state":"idle"}`) |
| `cancel` | создаёт `$VDLU_DIR/cancel`; идущий `run` останавливается на следующей безопасной точке |

## Машина состояний (journal.json)

```
PLANNED -> FETCHING -> FETCHED -> APPLYING -> APPLIED_LIVE -> (PENDING_REBOOT | DONE)
```

`DONE` только после того, как повторный хэш ВСЕГО совпадёт. Если какой-либо REBOOT-hard был инсценирован ⇒
`PENDING_REBOOT` (никогда ложный `DONE`). `ERROR` при любом сбое, без порчи модуля (применённые LIVE-файлы
откатываются из `rollback/<v>/`, ничего "наполовину применённого, лгущего об этом"). Доброкачественный выход из
фазы `fetch`: **`DEFERRED`** - загрузка была отложена `net_policy` (сеть не разрешена), plan/target сохраняются,
и она возобновляется при следующем check/boot (WebUI показывает синий инфо-тост "ожидание сети X", не ошибку).

## Гарантии строгости

- **FETCH:** гейтится `net_policy` (any/wifi/mobile, только http/https, `file://` никогда) - неразрешённая сеть ⇒
  `DEFERRED` (возобновляемо), без траты данных. Скачивает только недостающее в `<sha>.part` (curl с
  `--connect-timeout` + `--speed-time`, никогда не зависает), распаковывает `gz` (toybox `gunzip`), проверяет `sha256sum` ==
  манифест, атомарный `mv` в `blobs/<sha>`. Кэшированный+ok блоб пропускается. Может засеять блоб из неизменного
  локального файла (dedup/офлайн). **3 сбоя на одном блобе = фаза прерывается без применения чего-либо.** Она
  становится `FETCHED` только когда ВСЕ блобы плана присутствуют+проверены. При настройке
  toolchain он логирует разрешённое доверие TLS (путь CA + читаемость, размер бандла и число
  сертификатов), чтобы загрузочный curl `rc 77` сам себя объяснял в `boot.log` - он отличает
  пустое хранилище от нечитаемого (случай контекста SELinux при загрузке).
- **APPLY** (только из `FETCHED`): `live`/`soft` → резервная копия в `rollback/<v>/` → `.vdlu-tmp` → `chmod` → verify →
  атомарный `rename`. `reboot` → материализует в `staged/<path>.vdlu-new` (НЕ трогает живой inode).
  `delete[]` → резервная копия → удаление. Идемпотентно (файл, уже на целевом хэше, пропускается).
- **COMMIT:** повторный хэш каждого `live`/`soft`, только затем пишет `current.json`. С инсценированными файлами ⇒
  `PENDING_REBOOT`. `boot` делает `mv -f staged/....vdlu-new $MODULE_DIR/<path>` (pre-zygote) + перепроверяет +
  `DONE`.
- **cancel:** проверяется между файлами (безопасная точка), удаляет выполняемый `.vdlu-tmp`/`.part`, удаляет `cancel`,
  оставляет journal возобновляемым (`cancelled:true`, `error:null`).
- **mkdir-lock `$VDLU_DIR/lock.d`** сериализует (flock неработоспособен на toybox, восстановление устаревшего по PID).
  ТЕРПЕЛИВЫЙ boot-retry не удерживает lock во время ожидания (`acquire_lock_try`+release между попытками) и не держит
  wakelock - безопасно для батареи. Крах/сеть/перезагрузка посреди → `resume`/`boot` продолжает.
- **profile=hardened** ⇒ `vdlu-verify` обязателен на манифесте ПЕРЕД использованием, сбой = прерывание, даунгрейд заблокирован
  (монотонная версия). **trusted** ⇒ verify по возможности, но хэш каждого блоба ВСЕГДА проверяется.
- **Allowlist ключа module-update (оба profiles):** `verify_manifest` отклоняет, fail-closed, любой манифест, чей `key_id` не входит в настроенную allowlist `key_id` (см. INTERFACES §5/§6), ПЕРЕД выбором pubkey, так что ключ меньшего доверия, который лишь лежит в keyring (напр., ключ fingerprint-feed), никогда не сможет подписать flashless root-обновление. Безопасно по умолчанию, когда не задано: keyring с одним ключом = только этот один ключ, многоключевой keyring = отклонено, пока `key_id` не закреплён.
- **Исключение якоря доверия (VDLU#2):** engine ИГНОРИРУЕТ каждый путь `vdlu/` в загруженном плане (`update.sh`, `vdlu-verify`, `verify/*`, `keyring/*`, config) - никогда не загружается, не применяется и не удаляется - даже если подписанный фид их несёт. Фид никогда не может подменить верификатор на устройстве или ключ подписи, якорь доверия меняется только через полный подписанный re-flash, так что один утёкший ключ подписи не может закрепить root по сети.
- **Отсрочка при занятости (опциональный `apply_busy_file`):** с заданным `apply_busy_file` (абсолютный путь, который модуль-хост трогает во время собственных операций, напр. идущего бэкапа), APPLY откладывается, пока этот путь существует - обновление никогда не подменяет файлы модуля посреди операции. Блобы уже загружены, поэтому следующий триггер применяет без повторной загрузки.
- **Потолки размера:** 128 MiB на файл (`MAX_FILE_BYTES`) и 2 MiB на манифест (`MAX_MANIFEST_BYTES`), применяемые до чтения как в `update.sh`, так и в `vdlu-verify` (анти бомба-декомпрессии / анти-OOM).
- Деградирует изящно: отсутствующий бинарник / сеть упала / диск полон → явная ошибка в stderr + `state:ERROR` в
  journal, без порчи модуля.

## Парсинг JSON без jq

Flattener в стиле gron на `awk` (чистый POSIX: `substr`/`index`/`gsub`/`split`/`printf` + локальные, передаваемые как
параметры) токенизирует манифест посимвольно и выдаёт одну строку `path<TAB>value` на скалярный лист
(`files/0/sha256<TAB>ab..`, `version<TAB>6`, `delete/0<TAB>etc/x`). Устойчив к компактному ИЛИ
pretty-printed JSON. `sh` потребляет его через `grep`/`cut`, пофайловый план пересобирается во 2-м `awk` в TSV
(`class st mode enc sha size path`), который становится `$VDLU_DIR/plan.tsv`.

## Файлы состояния (в `$VDLU_DIR`, Tier-2)

| файл | роль |
|---|---|
| `config` | key=value (`source`/`profile`/`channel`/`net_policy`/`key_id`/`apply_busy_file`/`boot_retry_*`/…; см. INTERFACES §5) |
| `current.json` | манифест АКТИВНОЙ версии (база diff); отсутствует = никогда не обновлялся |
| `target.json` | закреплённый манифест выполняемой транзакции (наличие = активная транзакция); становится `current.json` при `DONE` |
| `plan.tsv` / `plan.del` | план + пофайловый прогресс (st) / пути к удалению |
| `journal.json` | прогресс для WebUI (регенерируется при каждом переходе) |
| `blobs/<sha256>` | кэш проверенного оригинального содержимого |
| `rollback/<version>/<path>` | резервная копия перезаписанных файлов (undo; хранит последние 3) |
| `staged/<path>.vdlu-new` | REBOOT-hard, ожидающий swap при загрузке |
| `lock.d/` | mkdir-lock (flock неработоспособен на toybox; восстановление устаревшего по PID) |
| `tools/<abi>/curl` | загруженный статический curl (компактный bootstrap); сохраняется между обновлениями |
| `cancel` | запрос отмены |

<!-- doc-footer -->

---

> _Эта документация создана с помощью Claude (Anthropic) и поддерживается VD171. Исправления и улучшения приветствуются, см. [CONTRIBUTING.md](CONTRIBUTING.md)._
