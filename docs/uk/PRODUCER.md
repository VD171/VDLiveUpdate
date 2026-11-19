> **Languages:** [English](../PRODUCER.md) · [العربية](../ar/PRODUCER.md) · [Čeština](../cs/PRODUCER.md) · [Deutsch](../de/PRODUCER.md) · [Español](../es/PRODUCER.md) · [فارسی](../fa/PRODUCER.md) · [Français](../fr/PRODUCER.md) · [हिन्दी](../hi/PRODUCER.md) · [Bahasa Indonesia](../id/PRODUCER.md) · [Italiano](../it/PRODUCER.md) · [日本語](../ja/PRODUCER.md) · [한국어](../ko/PRODUCER.md) · [Nederlands](../nl/PRODUCER.md) · [Polski](../pl/PRODUCER.md) · [Português](../pt/PRODUCER.md) · [Русский](../ru/PRODUCER.md) · [Svenska](../sv/PRODUCER.md) · [ไทย](../th/PRODUCER.md) · [Türkçe](../tr/PRODUCER.md) · Українська · [Tiếng Việt](../vi/PRODUCER.md) · [中文](../zh/PRODUCER.md)

---

# VDLU producer + шар підпису

Будує content-addressed доставку (маніфест + блоби) для модуля і підписує її.
Узгоджується з [`INTERFACES.md`](INTERFACES.md) §3/§6/§7.

| інструмент | працює на | мова | завдання |
|---|---|---|---|
| `producer/vdlu-pack` | ПК / CI | python3 | обхід фінального дерева модуля -> `manifest.json` + `blobs/` |
| `producer/vdlu-keygen` | ПК | sh + openssl | ключова пара ed25519 (`<id>.pem` priv, `<id>.pub` PEM, `<id>.pub.raw` RAW 32B для компактного keyring) |
| `producer/vdlu-sign` | ПК | sh + openssl | впорскує `key_id` + `sig` у маніфест, на місці |
| `engine/vdlu-verify` | **пристрій** | sh + ed25519-mini | перевіряє `sig` через вбудований ed25519-mini; keyring = RAW 32B публічний ключ (БЕЗ openssl на пристрої) |

## Конвеєр

```sh
# 1. one-time: a signing key. Keep the .pem off every device and off any repo push.
producer/vdlu-keygen release-2026 ./keys

# 2. each release: pack the final tree (same tree the .zip ships, post-whitelist).
producer/vdlu-pack  ./module_tree  ./out  demo 106 --version-name v106 --channel stable \
                    [--prev ./prev/manifest.json]      # delete[] = paths gone since prev

# 3. sign the manifest in place.
producer/vdlu-sign  ./out/manifest.json  ./keys/release-2026.pem  release-2026

# 4. publish ./out/{manifest.json,blobs/} to <source> (Pages batch for public; rsync for private).
#    The slim device keyring holds ./keys/release-2026.pub.raw as keyring/release-2026.pub (RAW 32B).
```

`vdlu-pack` є content-addressed і дедуплікуючим: блоб, чий `<sha256>` уже існує, не
переписується, тож публікація інкрементальна, а незмінний / відкочений вміст ніколи не пушиться повторно.

### Рішення про `enc` (vdlu-pack)

`sha256` **завжди** береться від оригінального (нестиснутого) вмісту; `enc` лише називає, як блоб зберігається.

- `gz` коли `size >= 4096` **і** gzip (`-9 -n`, детермінований) заощаджує щонайменше 10% (`comp <= raw*0.90`).
- `raw` інакше (малий текст, який HTTP gzip уже покриває, або вже-нестисковні дані).
- gzip відсутній на білд-хості -> усе `raw` (ніколи не падає).

Блоб зберігається один раз, в одному форматі: `blobs/<sha256>` (raw) або `blobs/<sha256>.gz` (gz). Пристрій
розпаковує через toybox `gunzip` (завжди присутній), тож zstd не пакується.

### Рішення про `class` (vdlu-pack) - таксономія reboot

Виводиться зі шляху (INTERFACES §3, doc §4). Лише значення за замовчуванням; правило шляху ніколи не знижує `reboot`->`live`.

| class | співставляється | застосовується |
|---|---|---|
| `reboot` | `system/**`, `zygisk/**/*.so`, `*.rule` | застейджено `.vdlu-new`, обмін під час завантаження |
| `soft` | root `service.sh` / `post-fs-data.sh` / `boot-completed.sh` | записано live, виконується наступним завантаженням |
| `live` | усе інше (webroot, bin, lib, confs, module.prop, ...) | записано live, атомарно |

Символьні посилання **не переходяться** (ніколи не витікає вміст ззовні дерева, напр. посилання на
`/etc/shadow`) і пропускаються з попередженням, оскільки схема маніфесту не має типу symlink.
Нерегулярні файли (каталоги, fifo, пристрої) пропускаються. `built` шанує `SOURCE_DATE_EPOCH` для
відтворюваних маніфестів.

### Baseline (насіння установки) - непідписане, без ключа

`baseline.json` (відвантажується як `vdlu/baseline.json` у zip модуля) засіває `current.json` на свіжій установці,
тож пристрій народжується "актуальним" (без from:0, без повторного завантаження). Engine трактує його як **локальне довірене насіння**
(воно прибуло у прошитому zip, що є межею довіри установки) і **НЕ перевіряє його підпис** -
лише маніфест, ЗАВАНТАЖЕНИЙ зі стрічки, проходить через `vdlu-verify`. Тож baseline не потребує **жодного ключа**: це
просто вивід `vdlu-pack` над відвантаженим деревом (непідписаний; `sig`/`key_id` лишаються порожніми). CI може, отже,
генерувати його **без ключа**, тримаючи ключ підпису на 100% поза CI - лише опублікована СТРІЧКА підписана (оператором,
локально). `vdlu-pack` виключає `baseline.json` зі свого власного маніфесту (анти-самопосилання). Не фатально, якщо
відсутній: пристрій просто стартує from:0 на першому оновленні, ніколи не зламаний.

## Канонізація (точка конвергенції)

`vdlu-sign` та `engine/vdlu-verify` мають вивести **ті самі байти** з маніфесту, на двох
різних середовищах виконання (PC openssl проти device toybox + openssl). Правило навмисно є байтовим
перетворенням, а не повторною JSON-серіалізацією, тож воно не потребує JSON-бібліотеки на пристрої:

1. `vdlu-pack` пише `manifest.json` **компактно, ключі відсортовані, UTF-8**
   (`json.dumps(obj, sort_keys=True, separators=(",",":"), ensure_ascii=False)`), завжди включаючи
   поля `key_id` та `sig` (порожні рядкові заповнювачі до підпису). Це канонічна
   форма зберігання.
2. **Канонічна форма = той текст з видаленим полем `"sig"`.** Оскільки ключі відсортовані, `sig`
   завжди з'являється як `,"sig":"<value>",`, обрамлений `"schema"` (перед) і `"version"` (після),
   обидва завжди присутні. Видалення залишає добре сформований `...,"schema":N,"version":...`.
   JSON екранує кожну `"` всередині рядкових значень на `\"`, тож структурний токен `"sig":"` є
   однозначним навіть проти імені файлу, що буквально містить `"sig":"` (перевірено).
3. Підписане/перевірене повідомлення - це **sha256 hex** (64 ASCII-символи, без переходу рядка) канонічної
   форми. ed25519 над тим hex (`openssl pkeyutl -sign/-verify -rawin`).

Видалення у POSIX sh (ідентична функція в обох інструментах, без `sed`/`jq`):

```sh
# $1 = full manifest text (trailing newline already stripped by $(cat ...))
_pre=${_c%%\"sig\":\"*}     # up to  ...,"schema":N,
_rest=${_c#*\"sig\":\"}      # after "sig":"
_tail=${_rest#*\",}          # after <value>",  ->  "version":...
printf '%s%s' "$_pre" "$_tail" | sha256sum | cut -d' ' -f1
```

`key_id` є частиною канонічної форми (лише `sig` вирізається); `vdlu-sign` встановлює `key_id` **перед**
гешуванням. Порожній заповнювач значення (`"sig":""`, час підпису) чи заповнений (час перевірки) дає
ідентичні канонічні байти, тож sign і verify узгоджуються за побудовою.

Python відтворює це як `re.sub(r'"sig":"[^"]*",', '', text.rstrip("\\n"), count=1)` потім sha256 - використовується
лише для кросс-перевірки; авторитетними виробниками є два sh-інструменти.

## Підпис (ed25519)

- `vdlu-keygen` (ПК): `openssl genpkey -algorithm ed25519` (priv `0600`) + `openssl pkey -pubout` (pub **PEM**,
  для підпису/openssl) + `openssl pkey -pubout -outform DER | tail -c 32` -> **`.pub.raw` (RAW 32B)** (ed25519
  SPKI DER - це 12-байтовий префікс + 32-байтовий ключ, тож `tail -c 32` Є ключем). Він видає ОБИДВА.
- `vdlu-sign` (ПК): `openssl pkeyutl -sign -rawin` над канонічним sha256 hex; підпис зберігається base64.
- `vdlu-verify` (**пристрій, slim**): `ed25519-mini <pubkey32> <msg> <sig64>` - читає keyring як **RAW 32B**
  публічний ключ, БЕЗ openssl на пристрої. `key_id` санітизується за шляхом (без `/`, `.`, `..`, `"`). 🚨 Keyring відвантажує
  **`.pub.raw` (32B)**, ніколи `.pub` PEM (113B): PEM лише PC-side, і `ed25519-mini` не може його прочитати.

Модель довіри (INTERFACES §6, doc §11/§13): `profile=hardened` (публічний) робить verify обов'язковим - невдалий
чи відсутній підпис перериває оновлення. `profile=trusted` (приватний, SSH-стейджене джерело) трактує
verify як best-effort, але sha256 кожного блоба перевіряється незалежно.

## Keyring + ротація

Keyring - це каталог файлів `<key_id>.pub`, кожен - **RAW 32B** публічний ключ ed25519 (з `.pub.raw`
від `keygen`), НЕ PEM - `ed25519-mini` читає сирі 32 байти. Відвантажуйте поточний **і** попередній сирий публічний ключ
(doc §13), щоб ротований ключ не окирпичив старіші установки. `vdlu-sign` з новим `key_id` і пристрій,
що обирає `<keyring>/<key_id>.pub` (raw), - це весь механізм ротації - без зміни engine. Keyring є
**стабільним** між релізами (лише ротація ключа змінює його): повторна вендоризація має **перевіряти-не-копіювати** його і ніколи
не перезаписувати його PC-side `.pub` PEM.

<!-- doc-footer -->

---

> _Ця документація створена за допомогою Claude (Anthropic) і підтримується VD171. Виправлення та покращення вітаються; див. [CONTRIBUTING.md](CONTRIBUTING.md)._
