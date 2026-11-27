> **Languages:** [English](../AI-AGENTS.md) · [العربية](../ar/AI-AGENTS.md) · [Čeština](../cs/AI-AGENTS.md) · [Deutsch](../de/AI-AGENTS.md) · [Español](../es/AI-AGENTS.md) · [فارسی](../fa/AI-AGENTS.md) · [Français](../fr/AI-AGENTS.md) · [हिन्दी](../hi/AI-AGENTS.md) · [Bahasa Indonesia](../id/AI-AGENTS.md) · [Italiano](../it/AI-AGENTS.md) · [日本語](../ja/AI-AGENTS.md) · [한국어](../ko/AI-AGENTS.md) · [Nederlands](../nl/AI-AGENTS.md) · [Polski](../pl/AI-AGENTS.md) · [Português](../pt/AI-AGENTS.md) · [Русский](../ru/AI-AGENTS.md) · [Svenska](../sv/AI-AGENTS.md) · [ไทย](../th/AI-AGENTS.md) · [Türkçe](../tr/AI-AGENTS.md) · Українська · [Tiếng Việt](../vi/AI-AGENTS.md) · [中文](../zh/AI-AGENTS.md)

---

# Керування VDLU з ШІ-агента

VDLiveUpdate (VDLU) є безфлешовим інкрементним оновлювачем, який модулі KSU/Magisk вбудовують у `vdlu/`. Увесь рушій керується з оболонки, тож ШІ-асистент або агент може перевірити, застосувати, відновити та завершити оновлення безголово, той самий цикл, що його запускає WebUI, без UI і без людини в контурі. Розбирайте JSON, який він друкує, ніколи не зіскрібайте текст.

## Контракт

Одна точка входу, що запускається як root на пристрої, з трьома заданими змінними середовища рушія:

```sh
VDLU_DIR=/data/adb/<mod>/vdlu MODULE_DIR=/data/adb/modules/<mod> MODID=<mod> \
  sh "$MODULE_DIR/vdlu/update.sh" <verb>
```

- `VDLU_DIR` позначає каталог стану Tier-2 (поза модулем, переживає перепрошивку), `MODULE_DIR` позначає живе дерево модуля, `MODID` позначає id модуля.
- `rc 0` = ок, `rc != 0` = помилка, з причиною на stderr.
- Читальні дієслова (`check`, `status`) друкують **один об'єкт JSON** у stdout. Розберіть його, ніколи не зіскрібайте текст.
- Рушій залежить лише від toybox (`sha256sum`/`gzip`/`base64`) плюс вбудованого `ed25519-mini` плюс статичного `curl`, завантаженого під час першого https-оновлення, нуль `jq`.

Під час розробки той самий скрипт лежить у `engine/update.sh` у цьому репозиторії, тож `sh engine/update.sh <verb>` із трьома заданими змінними керує тестовою копією так само.

## Дієслова

| Дієслово | Робить | Друкує |
|------|------|--------|
| `check` | DIFF лише для читання проти стрічки, нічого не змінює | `{"update":bool,"from":N,"to":M,"fetch":K,"reboot":bool}`, або `{"update":false,"ahead":true,"from":N,"to":M}`, коли пристрій попереду стрічки (пониження заблоковано, безпечно, rc 0) |
| `run` | повний LIVE-цикл DIFF -> FETCH -> APPLY -> COMMIT, застосовує файли LIVE і стейджить REBOOT-hard, шанує `cancel` | поступ у `journal.json` |
| `resume` | відновлює відкладену транзакцію з її поточної фази, ідемпотентно, ніколи не підміняє `.so` | оновлений `journal.json` |
| `boot` | режим pre-zygote, `resume` плюс підміна застейдженого `.so`, закриває `PENDING_REBOOT` у `DONE` | оновлений `journal.json` |
| `status` | знімок лише для читання, нічого не змінює | `journal.json`, або `{"state":"idle"}`, коли жодна транзакція не активна |
| `cancel` | запитує зупинку, поточний `run` зупиняється в наступній безпечній точці | створює `$VDLU_DIR/cancel` |

Безголове оновлення виглядає так: `check`, щоб побачити, чи щось очікує, `run`, щоб застосувати все, що може піти наживо, потім `boot` під час наступного завантаження, щоб підмінити будь-який застейджений `.so` (або `resume`, щоб повторити відкладене завантаження). Кожне дієслово безпечно викликати знову, збій або обрив мережі посеред циклу залишає відновлюваний журнал, ніколи не напівзастосований модуль.

## JSON статусу

`status` (і живий файл у `$VDLU_DIR/journal.json`) становить контракт поступу, який читають і WebUI, і агент:

```json
{ "schema":1, "module":"<id>", "target":<version>, "from":<version>,
  "phase":"diff|fetch|apply|commit",
  "state":"PLANNED|FETCHING|FETCHED|APPLYING|APPLIED_LIVE|PENDING_REBOOT|DONE|ERROR|DEFERRED",
  "total":<int>, "done":<int>, "current":"<path>", "bytes":<int>,
  "reboot_pending":bool, "cancelled":bool, "error":"<str|null>",
  "updated":"<ISO8601>",
  "items":[ {"path":"<p>","sha256":"<h>","class":"<c>","st":"pending|fetched|applied|staged|skipped"} ] }
```

- `state` рухається у фіксованому порядку: `PLANNED -> FETCHING -> FETCHED -> APPLYING -> APPLIED_LIVE -> (PENDING_REBOOT | DONE)`.
- `DONE` досягається лише після того, як повторний хеш усього збігається. Застейджений файл REBOOT-hard дає `PENDING_REBOOT`, ніколи фальшивий `DONE`, запустіть `boot`, щоб завершити його.
- `DEFERRED` означає, що `net_policy` заблокувала завантаження, безпечний і відновлюваний стан, а не помилка, план зберігається і наступний `check`/`boot` продовжує.
- `ERROR` несе причину в `error`, застосовані файли LIVE відкочуються з `rollback/`, модуль ніколи не лишається напівзастосованим.
- `cancelled:true` з `error:null` означає чисту зупинку, журнал лишається відновлюваним.

## Контракт шва

Кожен компонент (рушій, продюсер, WebUI) відповідає [`INTERFACES.md`](INTERFACES.md), закону збіжності. Дієслова CLI, схема `manifest.json`, ключі `journal.json` та визначені там ключі config є **незмінними**, ставтеся до цього файлу як до єдиного джерела істини й вирівнюйтеся за ним, перш ніж змінювати будь-який з них. Щодо нутрощів рушія (відновлювана транзакція, гарантії суворості, виключення trust-anchor) див. [`ENGINE.md`](ENGINE.md), щодо боку стрічки (збирання та підписання адресованої за вмістом стрічки) див. [`PRODUCER.md`](PRODUCER.md).

## Правила для агента

- Використовуйте дієслова та JSON, ніколи не зіскрібайте WebUI і ніколи не редагуйте файли стану вручну.
- Ставтеся до `INTERFACES.md` як до незмінного, зміна означає спершу вирівняти контракт.
- Патч від ШІ-агента проходить ту саму планку рецензії, що й будь-який інший, build завжди release, нічого не послаблюйте, нічого не втрачайте.

<!-- doc-footer -->

---

> _Ця документація створена за допомогою Claude (Anthropic) і підтримується VD171. Виправлення та покращення вітаються, див. [CONTRIBUTING.md](CONTRIBUTING.md)._
