> **Languages:** [English](../WEBUI.md) · [العربية](../ar/WEBUI.md) · [Čeština](../cs/WEBUI.md) · [Deutsch](../de/WEBUI.md) · [Español](../es/WEBUI.md) · [فارسی](../fa/WEBUI.md) · [Français](../fr/WEBUI.md) · [हिन्दी](../hi/WEBUI.md) · [Bahasa Indonesia](../id/WEBUI.md) · [Italiano](../it/WEBUI.md) · [日本語](../ja/WEBUI.md) · [한국어](../ko/WEBUI.md) · [Nederlands](../nl/WEBUI.md) · [Polski](../pl/WEBUI.md) · [Português](../pt/WEBUI.md) · [Русский](../ru/WEBUI.md) · [Svenska](../sv/WEBUI.md) · [ไทย](../th/WEBUI.md) · [Türkçe](../tr/WEBUI.md) · Українська · [Tiếng Việt](../vi/WEBUI.md) · [中文](../zh/WEBUI.md)

---

# VDLU - WebUI віджет (flashless update)

Інтерфейс VDLU (VD Live Update) для WebUI root-менеджера KernelSU/APatch. Vanilla JS, без фреймворку, без
збірки, без CDN. Drop-in: хостовий `index.html` завантажує 2 файли і викликає API.

Конвергенція: `INTERFACES.md` §9 (WEBUI↔ENGINE), §4 (journal.json), §5 (config).

## Файли

| Файл | Що |
|---|---|
| `vdlu.js` | компонент - експонує `window.VDLU` |
| `vdlu.css` | тост прогресу, банер reboot, вкладка "Updates" (темна тема, успадковує змінні хоста) |
| `demo.html` | автономна сторінка з замоканим `ksu.exec` - відкривається в браузері, без пристрою |

## Інтеграція в хостовий `index.html`

```html
<link rel="stylesheet" href="vdlu.css">
...
<script src="vdlu.js"></script>
<script>
  VDLU.init({
    moduleDir: '/data/adb/modules/' + MODID,   // $MODULE_DIR
    vdluDir:   '/data/adb/' + MODID + '/vdlu',  // $VDLU_DIR  (Tier-2, outside the module dir)
    modid:     MODID,
    module:    'Demo',                     // name shown in the toast (default: modid)
    exec:   ex,          // (optional) the host's ksu.exec wrapper; see below
    toast:  toast,       // (optional) the host's transient toast
    confirm: askConfirm  // (optional) the host's confirmation modal
  });

  VDLU.onWebUIOpen();                          // on load: evaluates journal + banner + auto_on_webui_open
  VDLU.mountUpdatesPanel(document.getElementById('b-updates'));  // when the "Updates" tab is opened
</script>
```

### Що має визначити хост

- **`moduleDir`** = `$MODULE_DIR` (`/data/adb/modules/<modid>`), де вендоризовано engine
  (`vdlu/update.sh`).
- **`vdluDir`** = `$VDLU_DIR` (`/data/adb/<modid>/vdlu`), стан Tier-2 (`journal.json`, `config`,
  `cancel`).
- **`modid`** = id модуля.

Віджет збирає команду engine, що вже несе env контракту (§1):
`VDLU_DIR=… MODULE_DIR=… MODID=… sh $MODULE_DIR/vdlu/update.sh <cmd>`. `run`/`resume` ідуть у
**фон** (`(… &)`), а прогрес читається легким polling (~1s) `cat $VDLU_DIR/journal.json`.

### `exec`/`toast`/`confirm` (необов'язково)

Якщо опущено, віджет використовує свої власні:
- **`exec(cmd)`** має повертати `Promise`, що **resolves** зі stdout (rc 0) і **rejects** зі stderr
  (rc≠0) - точно сигнатура `ex()` з Demo `webroot/index.html`. Внутрішній fallback викликає
  `ksu.exec(cmd, '{}', cb)` з тим самим контрактом.
- **`toast(msg)`** = коротке транзієнтне сповіщення (fallback впорскує власний міні-тост).
- **`confirm(title,msg,ok,danger,fn)`** = модалка (сьогодні використовується лише хостом; віджет не вимагає жодного
  підтвердження в жодному потоці).

Передача власних хостових змушує віджет говорити через ТУ САМУ серіалізовану чергу та візуали, що й решта
WebUI.

## Публічний API (`window.VDLU`)

| Функція | Що робить |
|---|---|
| `init(opts)` | конфігурує (див. вище). Повертає `window.VDLU`. |
| `onWebUIOpen()` | викликайте на завантаженні: показує банер, якщо `reboot_pending`; пропонує **Resume**, якщо є нетермінальна транзакція; з `auto_on_webui_open=1` запускає **ТИХЕ авто-оновлення** (спершу безшумний `check()`; запускає `run`+постійний тост лише якщо `update && fetch>0` - актуально/попереду = інлайн-результат у панелі, нуль тосту). |
| `mountUpdatesPanel(el)` | рендерить вкладку "Updates" всередині `el` (строковий id або елемент): **Check for update**, **Update now**, перемикачі `auto_on_webui_open`/`auto_on_reboot`, поля boot-retry, селект **Network** (`net_policy`: Wi-Fi+mobile / Wi-Fi-only / mobile-only) і поля `source`/`channel`/`profile`. |
| `check()` | запускає `update.sh check`; `Promise<{update,from,to,fetch,reboot}>`. |
| `startUpdate()` | запускає `run` у фоні + тост прогресу з **Cancel**. |
| `cancel()` | створює `$VDLU_DIR/cancel` (engine зупиняється на безпечній точці). |
| `resume()` | `update.sh resume` + тост (поновлює поточну фазу). |
| `refreshBanner()` | повторно оцінює постійний банер pending-reboot. |

Тост (кутовий оверлей, неблокуючий) і банер (зверху, постійний) впорскуються віджетом у
`document.body` - хост не потребує для них HTML. Вкладка "Updates" - єдина точка, яку хост виділяє (порожній
`<div>`).

### Потік станів, який відображає тост (journal.json, §4)

`PLANNED → FETCHING → FETCHED → APPLYING → APPLIED_LIVE → (PENDING_REBOOT | DONE)`; `ERROR` у будь-який момент.
Тост показує **смугу + `phase done/total · current · bytes`**. Термінали:
- **`DONE`** → зелений тост "v&lt;target&gt; applied".
- **`PENDING_REBOOT`** (або `reboot_pending=true`) → зелений тост + **постійний банер** "⚠️ Reboot to
  activate the new `.so` (vX)".
- **`ERROR`** → червоний тост з причиною (`journal.error`/stderr). Ніколи не підробляє успіх.
- **Cancelled** → "cancelled - N/M, resumable" + кнопка **Resume**.

## Запуск демо

Відкрийте `demo.html` у браузері (`xdg-open webui/demo.html`). Замоканий `ksu.exec` симулює `update.sh` та
`journal.json`, що еволюціонують; кнопки перемикають між сценаріями **LIVE→DONE**, **reboot_pending**, **error mid-way**
та **cancellable**. Це той самий `vdlu.js`/`vdlu.css`, що й на пристрої.

## i18n (мова)

Рядки віджета за замовчуванням **English** (нейтрально для публічних багатомовних модулів). Хост перевизначає
будь-який ключ, передаючи map в `init`:

```html
<script src="i18n/pt-BR.js"></script>   <!-- defines window.VDLU_I18N_PT_BR -->
<script>VDLU.init({ exec: ex, moduleDir: MOD, vdluDir: VDL, modid: 'x', i18n: window.VDLU_I18N_PT_BR });</script>
```

- **Часткове** злиття підходить: відсутній ключ повертається до англійського значення за замовчуванням.
- Ключі phase/state - це `ph_<phase>` / `st_<STATE>`; решта пласка (`cancel`, `updateNow`, …).
- Повний map ключів = об'єкт `DEFAULT_I18N` у `vdlu.js` (також експонований як `VDLU.i18n`).
- Готовий переклад надається як пророблений приклад: `i18n/pt-BR.js`. Нові мови = файл
  `i18n/<lang>.js` у тому ж шаблоні, або хост будує map зі своєї власної системи i18n.

## Єдине джерело (паритет між модулями)

Ці `vdlu.js`/`vdlu.css` є **канонічною копією**. Кожен модуль, що вбудовує віджет,
**повторно вендоризує** цю копію байт-у-байт у свій `webroot/` - він **ніколи** не редагує
свою власну на місці. Нова функція віджета народжується тут і тече вниз через повторну вендоризацію; зворотнє породжує тихий
drift (це траплялося на практиці: вендоризована копія відстала і їй бракувало `net_policy`, тосту `DEFERRED`
і полів `boot_retry`).

Вартовий: [`../tools/webui-parity.sh`](../../tools/webui-parity.sh) знаходить кожну копію в дереві джерела і помічає
ті, що розходяться з канонічною (лише `vdlu.js`/`vdlu.css`; keyring - це "verify, not copy").

```sh
tools/webui-parity.sh         # report; exits 1 if there is drift
tools/webui-parity.sh --fix   # re-vendors the divergent ones from the canonical
```

> 🪤 Keyring (`keyring/<id>.pub` RAW 32B) та engine (`vdlu/update.sh`) мають свій власний ритм повторної вендоризації;
> цей вартовий покриває **лише** WebUI-віджет.

<!-- doc-footer -->

---

> _Ця документація створена за допомогою Claude (Anthropic) і підтримується VD171. Виправлення та покращення вітаються; див. [CONTRIBUTING.md](CONTRIBUTING.md)._
