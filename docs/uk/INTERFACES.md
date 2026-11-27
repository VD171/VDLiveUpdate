> **Languages:** [English](../INTERFACES.md) · [العربية](../ar/INTERFACES.md) · [Čeština](../cs/INTERFACES.md) · [Deutsch](../de/INTERFACES.md) · [Español](../es/INTERFACES.md) · [فارسی](../fa/INTERFACES.md) · [Français](../fr/INTERFACES.md) · [हिन्दी](../hi/INTERFACES.md) · [Bahasa Indonesia](../id/INTERFACES.md) · [Italiano](../it/INTERFACES.md) · [日本語](../ja/INTERFACES.md) · [한국어](../ko/INTERFACES.md) · [Nederlands](../nl/INTERFACES.md) · [Polski](../pl/INTERFACES.md) · [Português](../pt/INTERFACES.md) · [Русский](../ru/INTERFACES.md) · [Svenska](../sv/INTERFACES.md) · [ไทย](../th/INTERFACES.md) · [Türkçe](../tr/INTERFACES.md) · Українська · [Tiếng Việt](../vi/INTERFACES.md) · [中文](../zh/INTERFACES.md)

---

# VDLU - Контракт інтерфейсів (шов між компонентами)

**Закон конвергенції:** кожен компонент узгоджується з цим файлом. Частини від 4 агентів мають **стикуватися разом** -
сигнатури CLI, імена файлів та ключі JSON нижче є **незмінними** (зміна означає вирівнювання спочатку тут).

Принципи, успадковані від репозиторіїв: **чистий POSIX sh** на пристрої (без башизмів, працює з toybox/busybox +
`sha256sum`/`gzip`/`base64` від toybox + завантажений `curl` + вбудований `ed25519-mini` - компактно, без набору
бінарників), **нуль зайвих коментарів**, **завжди release**, **суворість у разі збою** (поновлювана транзакція, нічого
фальшиво "завершеного", нічого не втрачено), **нічого не послаблено**.

---

## 1. Розкладка стану (Tier-2, поза каталогом модуля)

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
`cancelled:true` у журналі = engine зупинився на скасуванні (нетермінальний, поновлюваний стан, `error`
залишається null).

Engine, вендоризований у модулі: `$MODULE_DIR/vdlu/update.sh` (+ `vdlu-verify`). `$MODULE_DIR =
/data/adb/modules/<module>`. Engine отримує через env: `VDLU_DIR`, `MODULE_DIR`, `MODID`.

## 2. CLI engine (компонент ENGINE)

`sh update.sh <cmd>` - rc 0 = ok, !=0 = помилка (причина у stderr):

| cmd | що робить |
|---|---|
| `check` | DIFF: завантажує маніфест, порівнює; друкує 1-рядковий JSON `{"update":bool,"from":N,"to":M,"fetch":K,"reboot":bool}`; нічого не змінює. Пристрій ПОПЕРЕДУ стрічки (downgrade заблоковано, hardened) = ДОБРОЯКІСНИЙ стан: `{"update":false,"ahead":true,"from":N,"to":M}` + rc0 (ніколи "check failed"). rc do_diff: 2 fetch/parse, 3 verify/meta, 4 ahead |
| `run` | повний цикл: DIFF→FETCH→APPLY→COMMIT; шанує `cancel`; пише прогрес у `journal.json`; застосовує LIVE, стейджить REBOOT-hard |
| `resume` | поновлює транзакцію `journal.json` з поточної фази (ідемпотентно) |
| `boot` | режим pre-zygote: `resume` + виконує ОБМІН `staged/*.vdlu-new` (застосовує `.so`), закриває `PENDING_REBOOT`→`DONE` |
| `status` | друкує `journal.json` (або `{"state":"idle"}`) |
| `cancel` | створює `$VDLU_DIR/cancel` (`run` у процесі зупиняється на наступній безпечній точці) |

Джерело блобів/маніфесту: `source` з config. `<source>` + `/manifest.json`, `/blobs/<sha>`, `/blobs/<sha>.gz`.
`source` починається з `https://` (статичний curl завантажує, TLS) або `file://` (локальний стейджинг).

## 3. manifest.json (виробляється PRODUCER, споживається ENGINE)

```json
{ "schema":1, "module":"<id>", "version":<int>, "version_name":"<str>", "built":"<ISO8601>",
  "engine_min":5, "key_id":"<str>", "channel":"stable",
  "files":[ {"path":"webroot/index.html","sha256":"<hex64>","size":<int>,"mode":"0644","enc":"raw|gz","class":"live|soft|reboot"} ],
  "delete":["<path>"], "sig":"<base64>" }
```

- `files[]` = ПОВНЕ цільове дерево. `class`: `live` (webroot/bin/lib/confs/scripts-on-demand/module.prop) ·
  `soft` (service.sh/post-fs-data.sh/boot-completed.sh) · `reboot` (`zygisk/**/*.so`, `system/**`, `*.rule`).
  За замовчуванням за шляхом, ніколи не знижує `reboot`→`live`.
- `enc`: `gz` (gzip `-9 -n`, детермінований, toybox gunzip на пристрої) лише коли стискається добре І
  розмір значущий, `sha256` ЗАВЖДИ береться від оригінального вмісту.
- `sig`: підпис канонічного маніфесту БЕЗ поля `sig` (§4 verify).
- **Виключення якоря довіри (з боку engine, VDLU#2):** engine ВІДКИДАЄ з плану будь-який path
  `files[]`/`delete[]` під `vdlu/` (власні `update.sh`/`vdlu-verify`/`verify/*`/`keyring/*`/config) - ніколи не
  завантажується, не застосовується й не видаляється - навіть якщо підписана стрічка їх несе. Якір довіри на
  пристрої змінюється лише через повну підписану повторну прошивку, а не по мережі, `vdlu-pack` також виключає
  `vdlu/` з боку producer, тож це другий, з боку engine, захист проти витеклого ключа підпису.

## 4. journal.json (ENGINE пише, WEBUI читає - контракт прогресу)

```json
{ "schema":1, "module":"<id>", "target":<version>, "from":<version>,
  "phase":"diff|fetch|apply|commit", "state":"PLANNED|FETCHING|FETCHED|APPLYING|APPLIED_LIVE|PENDING_REBOOT|DONE|ERROR|DEFERRED",
  "total":<int>, "done":<int>, "current":"<path>", "bytes":<int>, "reboot_pending":bool,
  "cancelled":bool, "error":"<str|null>", "updated":"<ISO8601>",
  "items":[ {"path":"<p>","sha256":"<h>","class":"<c>","st":"pending|fetched|applied|staged|skipped"} ] }
```

Машина станів (фіксований порядок): `PLANNED→FETCHING→FETCHED→APPLYING→APPLIED_LIVE→(PENDING_REBOOT|DONE)`.
`DONE` лише коли повторне гешування УСЬОГО збігається. Застейджений REBOOT-hard ⇒ `PENDING_REBOOT` (не `DONE`). Виходи
з фази `fetch`: `ERROR` (жорсткий збій) або `DEFERRED` (net_policy заблокувала завантаження - доброякісно/поновлювано,
не помилка).

## 5. config (key=value, по одному в рядку, редагується у WEBUI)

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

**Повтор завантаження (офлайн) - ТЕРПЛЯЧИЙ, безпечний для батареї:** лише на `boot` (ніколи на check/auto-open). Якщо
завантаження маніфесту не вдається через МЕРЕЖУ (`fetch_offline` класифікує за кодом виходу фетчера), воно чекає й
повторює до успіху АБО вичерпання `boot_retry_minutes` часу в стані AWAKE. Конструкція, яка **нічого не утримує і не висаджує**:
- **Нуль wakelock:** між спробами це `sleep`, який замерзає в deep-sleep → пристрій спить нормально
  (~нуль батареї), повтор призупиняється й відновлюється лише коли пристрій уже прокинувся.
- **Нуль утримуваного замка:** `acquire_lock_try`+release МІЖ спробами (не утримує замок під час очікування) →
  `run`/ручний check ніколи не блокуються, якщо ручний run стейджить TARGET тим часом, boot відкладається.
- **Не будить радіо даремно:** проба `net_allowed` (через `net_type`/`ip route get`, пошук маршруту в ядрі,
  що шанує policy-routing Android, без пакета) контролює кожну спробу - вона витрачає fetch лише коли
  мережа з'явилася.
- НІКОЛИ не повторює детермінований збій (manifest/sig/downgrade). `--connect-timeout 15` на fetch (не
  зависає на captive portal). `service.sh` переводить його у фон (boot ніколи не зависає).
- ⛔ **ЖОРСТКО: увімкнення `boot_retry_minutes>0` вимагає ТЕРПЛЯЧОГО engine** (той, що з
  `net_allowed`+`acquire_lock_try`, канонічний `da7115f4`+). ПОПЕРЕДНІЙ boot-retry (утримує замок усе
  вікно + повторює сліпий curl офлайн) **ВИСАДЖУЄ батарею/будить радіо** - увімкнення повтору у старому
  engine - це footgun. Вмикаючи його, вендоризуйте поточний engine.

**`net_policy` (any|wifi|mobile):** контролює **ЗАВАНТАЖЕННЯ** за типом мережі. `net_type()` класифікує вихід
`ip route get` (стільниковий iface `rmnet/ccmni/v4-*/clat` = mobile, усе інше = wifi, пошук у ядрі, без
пакета). `net_allowed()` порівнює з `net_policy` і контролює `do_fetch` (блоби) + пробу терплячого boot-retry.
**Перевірка маніфесту залишається безкоштовною** (крихітна → UI повідомляє про оновлення в будь-якій мережі), лише
завантаження чекає на дозволену мережу. Завантаження в недозволеній мережі = стан **`DEFERRED`** у журналі
(НЕ ERROR, делікатний синій INFO-тост "очікування мережі X", plan/target зберігаються, воно поновлюється на наступній
перевірці/boot у правильній мережі). `net_policy` **замінює** `allow_metered` (який ніколи не споживався).
Engine `97baf887`+ (`file://` ніколи не контролюється).

## 6. Підпис (PRODUCER підписує на ПК через openssl, ENGINE перевіряє на пристрої через ed25519-mini)

- Канонізація: маніфест БЕЗ `sig`, ключі відсортовані, компактний JSON (без зайвих пробілів), UTF-8.
  Що підписується/перевіряється = `sha256` hex тієї канонічної форми (дає кросс-інструментальну детермінованість).
- `producer/vdlu-sign <manifest.json> <privkey.pem> <key_id>` → впорскує `key_id` + `sig` (base64 підпису ed25519 канонічного sha256) у маніфест, на місці.
- `engine/vdlu-verify <manifest.json> <keyring_dir>` → rc 0 якщо `sig` збігається з публічним ключем `<key_id>.pub` у
  keyring (SLIM: публічний ключ **RAW 32 байти**). Усередині, без openssl: toybox `sha256sum`/`base64 -d` + вбудований
  бінарник `ed25519-mini` (CLI `ed25519-mini <pub32> <msg> <sig64>`, rc 0=валідний/1=невалідний/2=usage).
  rc!=0 = відхилення. **`profile=hardened` ⇒ verify обов'язковий, збій = abort.**
  `profile=trusted` ⇒ verify є best-effort (джерело вже довірене через SSH), але геш кожного блоба ЗАВЖДИ перевіряється.
- **Allowlist ключа module-update (fail-closed, перед вибором pubkey):** `key_id` маніфесту має бути прийнятим ключем MODULE-UPDATE, перш ніж буде вибрано `<key_id>.pub` - `key_id` з config (§5) і є цією allowlist. Keyring може НЕСТИ й ключ нижчої довіри (напр., ключ fingerprint-feed, автоматизований, інший акаунт), без allowlist маніфест, підписаний цим ключем, пройшов би перевірку і застосував би повне flashless root-оновлення в разі витоку. `verify_manifest` застосовує це в ОБОХ profiles і передає розв'язану множину до `vdlu-verify` через env `VDLU_KEYID_ALLOW` (щоб окремий верифікатор погоджувався). Невстановлене є безпечним за замовчуванням (keyring з одним ключем: лише той ключ, багатоключовий keyring: відхилено, доки `key_id` не закріплено). Корінь довіри fingerprint-feed - це ОКРЕМИЙ шлях із власним закріпленим ключем, і він не зачіпається.
- `producer/vdlu-keygen <id> <out>` → генерує `<id>.pem` (priv) + `<id>.pub` (PEM, для інструментів на ПК) +
  `<id>.pub.raw` (**RAW 32B** = `<id>.pub` компактного keyring на пристрої). openssl `genpkey -algorithm ed25519`.

## 7. Блоб - перевірка (ENGINE)

Завантажує `<source>/blobs/<sha>` (або `.gz`, якщо `enc=gz`), пише `.part`, якщо `gz` розпаковує (`gunzip`),
перевіряє `sha256sum` == `sha256` маніфесту, збіг → атомарний `mv` до `$VDLU_DIR/blobs/<sha>`. 3 збої на
одному блобі = перериває фазу (нічого не застосовано). Блоб уже в `$VDLU_DIR/blobs/<sha>` з ok гешем =
пропускає завантаження.

## 8. APPLY за класом (ENGINE)

- `live`/`soft`: резервна копія `rollback/<v>/<path>` → пише `$MODULE_DIR/<path>.vdlu-tmp` з блоба → `chmod mode` →
  атомарний `rename` поверх цілі. Уже на цільовому геші = пропуск. (У варіанті Zygisk запис іде в
  змонтований каталог = злиття пофайлово, ніколи `rm -rf` каталогу.)
- `reboot`: матеріалізується в `$VDLU_DIR/staged/<path>.vdlu-new` (НЕ чіпає живий). Обмін - на `boot`.
- `delete[]`: резервна копія → видалення.

## 9. WEBUI ↔ ENGINE (компонент WEBUI)

- Запускає: `ksu.exec("sh $MODULE_DIR/vdlu/update.sh run")` (у фоні).
- Прогрес: легкий polling `ksu.exec("cat $VDLU_DIR/journal.json")` кожні ~1s, рендерить `{phase,state,total,done,current,bytes}`.
- Живучість: журнал відсутній 8 тіків ⇒ "немає відповіді". Журнал ЗАМЕРЗ (ті самі значення) на 20 тіків ⇒ перевіряє `lock.d`: живий = продовжує (повільний fetch 1 блоба), мертвий = помилка + Resume. Без цього run, що помер посеред fetch, заморозив би тост на "updating".
- Скасування: `ksu.exec("touch $VDLU_DIR/cancel")`.
- Config: читає/пише `$VDLU_DIR/config` (key=value) у вкладці "Updates".
- Тост: смуга + `phase done/total · current`, на завершенні з `reboot_pending` ⇒ постійний банер "reboot to activate the .so".
- Авто-відкриття (`auto_on_webui_open=1`): спершу робить ТИХИЙ `check()` (без тосту прогресу), запускає `run`+постійний тост лише якщо `update && fetch>0`. Актуально/попереду/нічого нового = інлайн-результат у панелі, нуль залишкового тосту. Ненав'язливо, як ручна кнопка (тост з'являється лише коли є реальне завантаження). curl-bootstrap одноразовий.

## 10. Інтеграція в демо (компонент INTEGRATION) - СНІПЕТИ, не редагуйте живі файли

Виробляє в `integration/demo/` сніпети + `INTEGRATION.md`, що каже, куди кожен іде (без застосування):
- хук `auto_on_reboot` у `post-fs-data`/`service.sh` (pre-zygote → `update.sh boot`) та `auto_on_webui_open`.
- значення за замовчуванням `config` + вбудований keyring + вендоризація (`modules/<mod>/vdlu/`).
- варіант PARTIAL (злиття в змонтований каталог).

## 11. Завантажений toolchain + baseline (SLIM, підхід B)

**Розкладка в модулі (zip):** `vdlu/{update.sh, vdlu-verify, config.default, keyring/<id>.pub (RAW 32B),
verify/<abi>/ed25519-mini, baseline.json}`. **БЕЗ** `bin/` (openssl/curl/zstd). `customize.sh` може обрізати
`verify/` до ABI пристрою (`vdlu-verify` знаходить mini в `<dir>/ed25519-mini` АБО `<dir>/verify/<abi>/ed25519-mini`).

**ed25519-mini** (вбудований бінарник, лише verify): `ed25519-mini <pubkey32> <msg> <sig64>` → rc 0=валідний,
1=невалідний, 2=usage/IO. msg = точні підписані байти (НЕ перегешує). TweetNaCl PD, статичний по ABI, PROVENANCE.

**tools-feed** (лише публічний/https профіль): обслуговується за `<tools_source>` (за замовчуванням виводиться: міняє останній сегмент
`source` на `vdlu-tools`, напр. `https://<user>.github.io/<repo>/vdlu-tools`). Містить:
- `tools-manifest.json` - ПІДПИСАНИЙ маніфест `vdlu-pack` над деревом `<abi>/curl`, що фіксує `sha256`
  кожного curl (той самий ключ `release-2026`).
- `<abi>/curl` - СИРИЙ **статичний** curl (самодостатній, ~1MB, curl 8.11.1 + mbedTLS). 🪤 mbedTLS НЕ
  несе CA bundle: `fetch_url` передає `--capath` (автовизначення сховища довіри Android: `/system/etc/security/cacerts`
  → APEX conscrypt, `ca_path` перевизначає). Без capath = помилка 60. Цілісність - це ed25519, перевірка сертифіката - defense-in-depth.

**install-tool** (ENGINE): `update.sh install-tool <abi>` читає `$VDLU_DIR/.work/{tools-manifest.json, tool.<abi>}`
(WEBUI завантажує його через `fetch()` і записує туди), **перевіряє підпис tools-manifest (ed25519-mini,
ОБОВ'ЯЗКОВО в будь-якому профілі)** + геш curl == маніфест, і лише тоді встановлює його в `$VDLU_DIR/tools/<abi>/curl` (0755).
curl працює як root → sig+hash перед exec закриває RCE. Зберігається в Tier-2: ніколи не завантажується повторно (окрім видалення).

**fetch-bootstrap** (WEBUI, `ensureToolchain()`): працює перед check/run/resume. `file://` = no-op, curl ВЖЕ
доступний (Tier-2, АБО `module/bin/<abi>/curl` з **самозапакованого** модуля, АБО system) = no-op
(VDLU повторно використовує наявний curl), лише `https` **без жодного curl** завантажує curl + tools-manifest через webview, записує
їх у `.work` (chunked base64 через `ksu.exec`), викликає `install-tool`. Довіра = перевірка на пристрої, не завантаження.

> 🪤 **Slim (fetch-bootstrap) ≠ обов'язковий.** Модуль, чий `bin/` існує для ЙОГО ВЛАСНИХ функцій (напр. він пакує
> restic/rclone/age/tar/curl...), **не** стискається до ~2MB і не завантажує curl - VDLU переймає slim engine
> (gz, mini, baseline, фікси) і **повторно використовує** вбудований toolchain. Лише модулі без власного toolchain
> набирають ~2MB.

**baseline.json** (фікс from:0): реліз копіює ПІДПИСАНИЙ `manifest.json` відвантаженої версії в
`vdlu/baseline.json`, на свіжій установці engine засіває `current.json` з нього (`init_paths`, лише якщо відсутній) → пристрій
народжується "актуальним", без авто-оновлення самого себе і без повторного завантаження.

<!-- doc-footer -->

---

> _Ця документація створена за допомогою Claude (Anthropic) і підтримується VD171. Виправлення та покращення вітаються, див. [CONTRIBUTING.md](CONTRIBUTING.md)._
