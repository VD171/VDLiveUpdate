> **Languages:** [English](../INTERFACES.md) · [العربية](../ar/INTERFACES.md) · [Čeština](../cs/INTERFACES.md) · [Deutsch](../de/INTERFACES.md) · [Español](../es/INTERFACES.md) · [فارسی](../fa/INTERFACES.md) · [Français](../fr/INTERFACES.md) · [हिन्दी](../hi/INTERFACES.md) · [Bahasa Indonesia](../id/INTERFACES.md) · [Italiano](../it/INTERFACES.md) · [日本語](../ja/INTERFACES.md) · [한국어](../ko/INTERFACES.md) · [Nederlands](../nl/INTERFACES.md) · [Polski](../pl/INTERFACES.md) · [Português](../pt/INTERFACES.md) · Русский · [Svenska](../sv/INTERFACES.md) · [ไทย](../th/INTERFACES.md) · [Türkçe](../tr/INTERFACES.md) · [Українська](../uk/INTERFACES.md) · [Tiếng Việt](../vi/INTERFACES.md) · [中文](../zh/INTERFACES.md)

---

# VDLU - Контракт интерфейсов (шов между компонентами)

**Закон сходимости:** каждый компонент соответствует этому файлу. Части от 4 агентов должны **стыковаться** -
сигнатуры CLI, имена файлов и ключи JSON ниже **неизменны** (изменение означает сначала согласование здесь).

Принципы, унаследованные из репозиториев: **чистый POSIX sh** на устройстве (без башизмов, работает с
toybox/busybox + `sha256sum`/`gzip`/`base64` из toybox + загруженным `curl` + встроенным `ed25519-mini` -
компактно, без набора бинарников), **ноль лишних комментариев**, **всегда release**, **строгость при сбое**
(возобновляемая транзакция, ничего ложно "готового", ничего не потеряно), **ничего не ослаблено**.

---

## 1. Раскладка состояния (Tier-2, вне каталога модуля)

```
$VDLU_DIR = /data/adb/<module>/vdlu
  config               # key=value (§5)
  current.json         # manifest of the ACTIVE version (diff base); absent = never updated
  journal.json         # transaction in progress (§4); absent = idle
  cancel               # presence = cancel request (WebUI creates it; engine deletes it on stop)
  lock.d/              # mkdir-lock (flock unworkable on toybox; stale-recovery by PID)
  blobs/<sha256>       # cache of verified blobs (ORIGINAL content, already decompressed)
  rollback/<version>/<path>   # backup of overwritten files
  staged/<path>.vdlu-new      # REBOOT-hard awaiting swap at boot
  target.json          # PINNED manifest of the in-flight transaction (presence = active transaction; becomes current.json on DONE)
  plan.tsv  plan.del   # engine's internal plan (progress); the WebUI IGNORES it (reads only journal/config/current)
```
`cancelled:true` в journal = engine остановился на отмене (нетерминальное, возобновляемое состояние, `error`
остаётся null).

Engine вендорен в модуле: `$MODULE_DIR/vdlu/update.sh` (+ `vdlu-verify`). `$MODULE_DIR =
/data/adb/modules/<module>`. Engine получает через env: `VDLU_DIR`, `MODULE_DIR`, `MODID`.

## 2. CLI engine (компонент ENGINE)

`sh update.sh <cmd>` - rc 0 = ok, !=0 = ошибка (stderr содержит причину):

| cmd | делает |
|---|---|
| `check` | DIFF: скачивает манифест, сравнивает; печатает однострочный JSON `{"update":bool,"from":N,"to":M,"fetch":K,"reboot":bool}`; ничего не меняет. Устройство ВПЕРЕДИ фида (даунгрейд заблокирован, усилено) = ДОБРОКАЧЕСТВЕННОЕ состояние: `{"update":false,"ahead":true,"from":N,"to":M}` + rc0 (никогда "check failed"). rc do_diff: 2 fetch/parse, 3 verify/meta, 4 ahead |
| `run` | полный цикл: DIFF→FETCH→APPLY→COMMIT; учитывает `cancel`; пишет прогресс в `journal.json`; применяет LIVE, инсценирует REBOOT-hard |
| `resume` | возобновляет транзакцию `journal.json` с текущей фазы (идемпотентно) |
| `boot` | режим pre-zygote: `resume` + выполняет SWAP файлов `staged/*.vdlu-new` (применяет `.so`), закрывает `PENDING_REBOOT`→`DONE` |
| `status` | печатает `journal.json` (или `{"state":"idle"}`) |
| `cancel` | создаёт `$VDLU_DIR/cancel` (идущий `run` останавливается на следующей безопасной точке) |

Источник блобов/манифеста: `source` из config. `<source>` + `/manifest.json`, `/blobs/<sha>`, `/blobs/<sha>.gz`.
`source` начинается с `https://` (статический curl загружается, TLS) или `file://` (локальный staging).

## 3. manifest.json (производится PRODUCER, потребляется ENGINE)

```json
{ "schema":1, "module":"<id>", "version":<int>, "version_name":"<str>", "built":"<ISO8601>",
  "engine_min":5, "key_id":"<str>", "channel":"stable",
  "files":[ {"path":"webroot/index.html","sha256":"<hex64>","size":<int>,"mode":"0644","enc":"raw|gz","class":"live|soft|reboot"} ],
  "delete":["<path>"], "sig":"<base64>" }
```

- `files[]` = ПОЛНОЕ целевое дерево. `class`: `live` (webroot/bin/lib/confs/скрипты-по-требованию/module.prop) ·
  `soft` (service.sh/post-fs-data.sh/boot-completed.sh) · `reboot` (`zygisk/**/*.so`, `system/**`, `*.rule`).
  По умолчанию по path, никогда не понижает `reboot`→`live`.
- `enc`: `gz` (gzip `-9 -n`, детерминированный, gunzip из toybox на устройстве) только когда хорошо сжимается И
  размер значителен, `sha256` ВСЕГДА от оригинального содержимого.
- `sig`: подпись канонического манифеста БЕЗ поля `sig` (§4 verify).
- **Исключение якоря доверия (на стороне engine, VDLU#2):** engine ОТБРАСЫВАЕТ из плана любой путь `files[]`/`delete[]` под `vdlu/` (собственные `update.sh`/`vdlu-verify`/`verify/*`/`keyring/*`/config) - никогда не загружается, не применяется и не удаляется - даже если подписанный фид их несёт. Якорь доверия на устройстве меняется только через полный подписанный re-flash, не по сети, `vdlu-pack` также исключает `vdlu/` на стороне producer, так что это вторая, на стороне engine, защита против утёкшего ключа подписи.

## 4. journal.json (ENGINE пишет, WEBUI читает - контракт прогресса)

```json
{ "schema":1, "module":"<id>", "target":<version>, "from":<version>,
  "phase":"diff|fetch|apply|commit", "state":"PLANNED|FETCHING|FETCHED|APPLYING|APPLIED_LIVE|PENDING_REBOOT|DONE|ERROR|DEFERRED",
  "total":<int>, "done":<int>, "current":"<path>", "bytes":<int>, "reboot_pending":bool,
  "cancelled":bool, "error":"<str|null>", "updated":"<ISO8601>",
  "items":[ {"path":"<p>","sha256":"<h>","class":"<c>","st":"pending|fetched|applied|staged|skipped"} ] }
```

Машина состояний (фиксированный порядок): `PLANNED→FETCHING→FETCHED→APPLYING→APPLIED_LIVE→(PENDING_REBOOT|DONE)`.
`DONE` только после того, как повторный хэш ВСЕГО совпадёт. Инсценированный REBOOT-hard ⇒ `PENDING_REBOOT` (не
`DONE`). Выходы из фазы `fetch`: `ERROR` (жёсткий сбой) или `DEFERRED` (net_policy заблокировал загрузку -
доброкачественно/возобновляемо, не ошибка).

## 5. config (key=value, по одному в строке, редактируется в WEBUI)

```
auto_on_webui_open=0
auto_on_reboot=1
source=https://<user>.github.io/<repo>/<module>
channel=stable
profile=trusted        # trusted | hardened. CODE DEFAULT (line absent) = hardened (fail-closed, 9a9a824)
net_policy=any         # any (Wi-Fi+mobile) | wifi (Wi-Fi only) | mobile (mobile only) - gates the DOWNLOAD by network type
allow_metered=0        # ⚠️ SUPERSEDED by net_policy (not consumed by the engine)
pubkey_dir=keyring     # relative to $MODULE_DIR/vdlu (keyring of pubkeys for verify)
key_id=                # ALLOWLIST of accepted MODULE-UPDATE signing key id(s), comma-separated (rotation).
                       # UNSET = default-safe: a single-key keyring accepts only that one key; a MULTI-key
                       # keyring (one that also ships a fingerprint-feed key) MUST pin its module key here.
ca_path=               # empty = auto-detect of the Android trust store; set a path to override
ca_cert=               # empty = auto-build a CA bundle from the trust store; set a path to a bundle to override
tools_source=          # empty = derived from source (.../vdlu-tools); feed of the static curl
apply_busy_file=       # OPT-IN: absolute path the host module touches during its own operations (e.g. a
                       # backup). While it EXISTS, APPLY is deferred to the next trigger (blobs already
                       # fetched, no re-download) so an update never swaps module files mid-operation. UNSET = off.
boot_retry_interval=30 # seconds between probes when BOOT finds the device offline (floor 5s)
boot_retry_minutes=0   # ceiling of the PATIENT retry (AWAKE-time) only at boot; 0 = off. Battery-safe (no wakelock,
                       # no held lock, route probe never wakes the radio) -> a generous ceiling is ~free
```

**Boot retry (офлайн) - ТЕРПЕЛИВЫЙ, безопасный для батареи:** только при `boot` (никогда при check/auto-open).
Если fetch манифеста падает из-за СЕТИ (`fetch_offline` классифицирует по коду выхода fetcher), он ждёт и
повторяет до успеха ИЛИ пока не исчерпается `boot_retry_minutes` времени БОДРСТВОВАНИЯ. Дизайн, который **ничего
не удерживает и не разряжает**:
- **Ноль wakelock:** между попытками это `sleep`, который замерзает в deep-sleep → устройство спит нормально
  (~ноль батареи), повтор приостанавливается и возобновляется, как только устройство уже проснулось.
- **Ноль удержанного lock:** `acquire_lock_try`+release МЕЖДУ попытками (не удерживает lock во время ожидания) →
  `run`/ручной check никогда не блокируются, если ручной run инсценирует TARGET в это время, загрузка откладывается.
- **Не будит радио зря:** зонд `net_allowed` (через `net_type`/`ip route get`, поиск маршрута в ядре, который
  уважает policy-routing Android, без пакета) гейтит каждую попытку - он тратит fetch только когда сеть появилась.
- НИКОГДА не повторяет детерминированный сбой (манифест/sig/даунгрейд). `--connect-timeout 15` на fetch (не
  зависает на captive portal). `service.sh` отправляет его в фон (загрузка никогда не зависает).
- ⛔ **ЖЁСТКО: включение `boot_retry_minutes>0` требует ТЕРПЕЛИВОГО engine** (того, что с
  `net_allowed`+`acquire_lock_try`, канонический `da7115f4`+). ПРЕДЫДУЩИЙ boot-retry (удерживает lock всё окно +
  повторяет слепой curl офлайн) **РАЗРЯЖАЕТ батарею/будит радио** - включить повтор в старом engine это
  самострел. При включении вендорите текущий engine.

**`net_policy` (any|wifi|mobile):** гейтит **ЗАГРУЗКУ** по типу сети. `net_type()` классифицирует egress
`ip route get` (сотовый интерфейс `rmnet/ccmni/v4-*/clat` = mobile, всё остальное = wifi, поиск в ядре, без
пакета). `net_allowed()` сравнивает с `net_policy` и гейтит `do_fetch` (блобы) + зонд терпеливого boot-retry.
**Проверка манифеста остаётся свободной** (крошечная → UI сообщает об обновлении в любой сети), только загрузка
ждёт разрешённую сеть. Загрузка в неразрешённой сети = состояние **`DEFERRED`** в journal (НЕ ERROR, мягкий
синий INFO-тост "ожидание сети X", plan/target сохраняются, возобновляется при следующем check/boot в правильной
сети). `net_policy` **заменяет** `allow_metered` (который никогда не потреблялся). Engine `97baf887`+ (`file://`
никогда не гейтится).

## 6. Подпись (PRODUCER подписывает на ПК через openssl, ENGINE проверяет на устройстве через ed25519-mini)

- Канонизация: манифест БЕЗ `sig`, ключи отсортированы, компактный JSON (без лишних пробелов), UTF-8.
  Что подписывается/проверяется = hex `sha256` этой канонической формы (даёт кросс-инструментальный детерминизм).
- `producer/vdlu-sign <manifest.json> <privkey.pem> <key_id>` → внедряет `key_id` + `sig` (base64 подписи ed25519 канонического sha256) в манифест, in place.
- `engine/vdlu-verify <manifest.json> <keyring_dir>` → rc 0, если `sig` совпадает с pubkey `<key_id>.pub` в
  keyring (SLIM: pubkey **RAW 32 байта**). Внутри, без openssl: `sha256sum`/`base64 -d` из toybox + встроенный
  бинарник `ed25519-mini` (CLI `ed25519-mini <pub32> <msg> <sig64>`, rc 0=валидно/1=невалидно/2=использование).
  rc!=0 = отклонить. **`profile=hardened` ⇒ verify обязателен, сбой = прерывание.**
  `profile=trusted` ⇒ verify по возможности (источник уже доверенный через SSH), но хэш каждого блоба ВСЕГДА проверяется.
- **Allowlist ключа module-update (fail-closed, перед выбором pubkey):** `key_id` манифеста должен быть принятым ключом MODULE-UPDATE, прежде чем будет выбран `<key_id>.pub` - `key_id` из config (§5) и есть эта allowlist. Keyring может НЕСТИ и ключ меньшего доверия (напр., ключ fingerprint-feed, автоматизированный, другой аккаунт), без allowlist манифест, подписанный этим ключом, прошёл бы проверку и применил бы полное flashless root-обновление в случае утечки. `verify_manifest` обеспечивает это в ОБОИХ profiles и передаёт разрешённое множество в `vdlu-verify` через env `VDLU_KEYID_ALLOW` (чтобы отдельный верификатор соглашался). Не задано - безопасно по умолчанию (keyring с одним ключом: только этот ключ, многоключевой keyring: отклонено, пока `key_id` не закреплён). Корень доверия fingerprint-feed - это ОТДЕЛЬНЫЙ путь со своим закреплённым ключом, и он не затрагивается.
- `producer/vdlu-keygen <id> <out>` → генерирует `<id>.pem` (priv) + `<id>.pub` (PEM, для тулинга на ПК) +
  `<id>.pub.raw` (**RAW 32B** = `<id>.pub` компактного keyring на устройстве). openssl `genpkey -algorithm ed25519`.

## 7. Блоб - проверка (ENGINE)

Скачивает `<source>/blobs/<sha>` (или `.gz`, если `enc=gz`), пишет `.part`, если `gz` распаковывает (`gunzip`),
проверяет `sha256sum` == `sha256` манифеста, совпало → атомарный `mv` в `$VDLU_DIR/blobs/<sha>`. 3 сбоя на
одном блобе = прерывает фазу (ничего не применено). Блоб, уже находящийся в `$VDLU_DIR/blobs/<sha>` с ok-хэшем =
пропускает загрузку.

## 8. APPLY по классу (ENGINE)

- `live`/`soft`: резервная копия `rollback/<v>/<path>` → пишет `$MODULE_DIR/<path>.vdlu-tmp` из блоба → `chmod mode` →
  атомарный `rename` поверх цели. Уже на целевом хэше = пропуск. (В варианте Zygisk запись идёт в
  примонтированный каталог = слияние пофайлово, никогда `rm -rf` каталога.)
- `reboot`: материализует в `$VDLU_DIR/staged/<path>.vdlu-new` (НЕ трогает живой). Swap при `boot`.
- `delete[]`: резервная копия → удаление.

## 9. WEBUI ↔ ENGINE (компонент WEBUI)

- Запускает: `ksu.exec("sh $MODULE_DIR/vdlu/update.sh run")` (background).
- Прогресс: лёгкий опрос `ksu.exec("cat $VDLU_DIR/journal.json")` каждую ~1s, рендерит `{phase,state,total,done,current,bytes}`.
- Живучесть: journal отсутствует 8 тиков ⇒ "нет ответа". Journal ЗАМОРОЖЕН (те же значения) 20 тиков ⇒ проверяет `lock.d`: жив = продолжает (медленный fetch 1 блоба), мёртв = ошибка + Resume. Без этого run, умерший посреди fetch, заморозил бы тост на "обновление".
- Cancel: `ksu.exec("touch $VDLU_DIR/cancel")`.
- Config: читает/пишет `$VDLU_DIR/config` (key=value) во вкладке "Updates".
- Тост: полоса + `phase done/total · current`, по завершении с `reboot_pending` ⇒ постоянный баннер "перезагрузите для активации .so".
- Auto-open (`auto_on_webui_open=1`): сначала делает ТИХИЙ `check()` (без тоста прогресса), запускает `run`+постоянный тост только если `update && fetch>0`. Актуально/впереди/ничего-нового = встроенный результат в панели, ноль остаточного тоста. Ненавязчиво как ручная кнопка (тост появляется только при реальной загрузке). Bootstrap curl однократный.

## 10. Интеграция в демо (компонент INTEGRATION) - СНИППЕТЫ, не редактируйте живые файлы

Производит в `integration/demo/` сниппеты + `INTEGRATION.md`, указывающий, куда идёт каждый (без применения):
- хук `auto_on_reboot` в `post-fs-data`/`service.sh` (pre-zygote → `update.sh boot`) и `auto_on_webui_open`.
- дефолты `config` + встроенный keyring + вендоринг (`modules/<mod>/vdlu/`).
- ЧАСТИЧНЫЙ вариант (слияние в примонтированный каталог).

## 11. Загруженный toolchain + baseline (SLIM, Подход B)

**Раскладка в модуле (zip):** `vdlu/{update.sh, vdlu-verify, config.default, keyring/<id>.pub (RAW 32B),
verify/<abi>/ed25519-mini, baseline.json}`. **НЕТ** `bin/` (openssl/curl/zstd). `customize.sh` может урезать
`verify/` до ABI устройства (`vdlu-verify` находит mini в `<dir>/ed25519-mini` ИЛИ `<dir>/verify/<abi>/ed25519-mini`).

**ed25519-mini** (встроенный бинарник, только-verify): `ed25519-mini <pubkey32> <msg> <sig64>` → rc 0=валидно,
1=невалидно, 2=использование/IO. msg = точные подписанные байты (НЕ перехэширует). TweetNaCl PD, статический по ABI, PROVENANCE.

**tools-feed** (только профиль public/https): обслуживается по `<tools_source>` (дефолт выводится: меняет
последний сегмент `source` на `vdlu-tools`, напр. `https://<user>.github.io/<repo>/vdlu-tools`). Содержит:
- `tools-manifest.json` - ПОДПИСАННЫЙ манифест `vdlu-pack` над деревом `<abi>/curl`, закрепляющий `sha256`
  каждого curl (тот же ключ `release-2026`).
- `<abi>/curl` - СЫРОЙ **статический** curl (самодостаточный, ~1MB, curl 8.11.1 + mbedTLS). 🪤 mbedTLS НЕ
  несёт CA-бандл: `fetch_url` передаёт `--capath` (автоопределение trust store Android: `/system/etc/security/cacerts`
  → APEX conscrypt, `ca_path` переопределяет). Без capath = ошибка 60. Целостность это ed25519, проверка сертификата это глубокая защита.

**install-tool** (ENGINE): `update.sh install-tool <abi>` читает `$VDLU_DIR/.work/{tools-manifest.json, tool.<abi>}`
(WEBUI скачивает через `fetch()` и пишет туда), **проверяет подпись tools-manifest (ed25519-mini,
ОБЯЗАТЕЛЬНО в любом профиле)** + хэш curl == манифест, и только затем устанавливает в `$VDLU_DIR/tools/<abi>/curl` (0755).
curl работает как root → sig+hash до exec закрывает RCE. Сохраняется в Tier-2: никогда не перекачивается (кроме как при uninstall).

**fetch-bootstrap** (WEBUI, `ensureToolchain()`): работает до check/run/resume. `file://` = no-op, curl УЖЕ
доступен (Tier-2, ИЛИ `module/bin/<abi>/curl` из **самодостаточного** модуля, ИЛИ система) = no-op
(VDLU переиспользует существующий curl), только `https` **без curl вообще** скачивает curl + tools-manifest через webview, пишет
их в `.work` (чанкованный base64 через `ksu.exec`), вызывает `install-tool`. Доверие = проверка на устройстве, не загрузка.

> 🪤 **Slim (fetch-bootstrap) ≠ обязателен.** Модуль, чей `bin/` существует для ЕГО СОБСТВЕННЫХ функций (напр.
> несёт restic/rclone/age/tar/curl...) **не** урезается до ~2MB и не скачивает curl - VDLU принимает компактный
> engine (gz, mini, baseline, фиксы) и **переиспользует** встроенный toolchain. Только модули без своего
> toolchain получают ~2MB.

**baseline.json** (фикс from:0): релиз копирует ПОДПИСАННЫЙ `manifest.json` поставляемой версии в
`vdlu/baseline.json`, при чистой установке engine сеет `current.json` из него (`init_paths`, только если отсутствует) → устройство
рождается "актуальным", без авто-обновления себя и без повторной загрузки.

<!-- doc-footer -->

---

> _Эта документация создана с помощью Claude (Anthropic) и поддерживается VD171. Исправления и улучшения приветствуются, см. [CONTRIBUTING.md](CONTRIBUTING.md)._
