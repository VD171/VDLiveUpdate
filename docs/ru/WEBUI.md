> **Languages:** [English](../WEBUI.md) · [العربية](../ar/WEBUI.md) · [Čeština](../cs/WEBUI.md) · [Deutsch](../de/WEBUI.md) · [Español](../es/WEBUI.md) · [فارسی](../fa/WEBUI.md) · [Français](../fr/WEBUI.md) · [हिन्दी](../hi/WEBUI.md) · [Bahasa Indonesia](../id/WEBUI.md) · [Italiano](../it/WEBUI.md) · [日本語](../ja/WEBUI.md) · [한국어](../ko/WEBUI.md) · [Nederlands](../nl/WEBUI.md) · [Polski](../pl/WEBUI.md) · [Português](../pt/WEBUI.md) · Русский · [Svenska](../sv/WEBUI.md) · [ไทย](../th/WEBUI.md) · [Türkçe](../tr/WEBUI.md) · [Українська](../uk/WEBUI.md) · [Tiếng Việt](../vi/WEBUI.md) · [中文](../zh/WEBUI.md)

---

# VDLU - WebUI-виджет (flashless обновление)

Интерфейс VDLU (VD Live Update) для WebUI root-менеджера KernelSU/APatch. Vanilla JS, без фреймворка, без
сборки, без CDN. Drop-in: хостовый `index.html` загружает 2 файла и вызывает API.

Сходимость: `INTERFACES.md` §9 (WEBUI↔ENGINE), §4 (journal.json), §5 (config).

## Файлы

| Файл | Что |
|---|---|
| `vdlu.js` | компонент - экспонирует `window.VDLU` |
| `vdlu.css` | тост прогресса, баннер reboot, вкладка "Updates" (тёмная тема, наследует переменные хоста) |
| `demo.html` | автономная страница с мокнутым `ksu.exec` - открывается в браузере, без устройства |

## Интеграция в хостовый `index.html`

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

### Что хост должен определить

- **`moduleDir`** = `$MODULE_DIR` (`/data/adb/modules/<modid>`), где вендорен engine
  (`vdlu/update.sh`).
- **`vdluDir`** = `$VDLU_DIR` (`/data/adb/<modid>/vdlu`), состояние Tier-2 (`journal.json`, `config`,
  `cancel`).
- **`modid`** = id модуля.

Виджет собирает команду engine, уже несущую env контракта (§1):
`VDLU_DIR=… MODULE_DIR=… MODID=… sh $MODULE_DIR/vdlu/update.sh <cmd>`. `run`/`resume` уходят в
**фон** (`(… &)`), а прогресс читается лёгким опросом (~1s) `cat $VDLU_DIR/journal.json`.

### `exec`/`toast`/`confirm` (опционально)

Если опущены, виджет использует свои собственные:
- **`exec(cmd)`** должен вернуть `Promise`, который **резолвится** с stdout (rc 0) и **реджектится** с stderr
  (rc≠0) - точно сигнатура `ex()` из `webroot/index.html` Demo. Внутренний fallback вызывает
  `ksu.exec(cmd, '{}', cb)` с тем же контрактом.
- **`toast(msg)`** = короткое транзиентное уведомление (fallback внедряет свой собственный мини-тост).
- **`confirm(title,msg,ok,danger,fn)`** = модальное окно (сегодня используется только хостом, виджет не требует
  подтверждения ни в одном потоке).

Передача собственных хоста заставляет виджет общаться через ТУ ЖЕ сериализованную очередь и визуалы, что и остальной
WebUI.

## Публичный API (`window.VDLU`)

| Функция | Делает |
|---|---|
| `init(opts)` | конфигурирует (см. выше). Возвращает `window.VDLU`. |
| `onWebUIOpen()` | вызовите при загрузке: показывает баннер, если `reboot_pending`; предлагает **Resume**, если есть нетерминальная транзакция; с `auto_on_webui_open=1` запускает **ТИХОЕ авто-обновление** (сначала бесшумный `check()`; запускает `run`+постоянный тост только если `update && fetch>0` - актуально/впереди = встроенный результат в панели, ноль тоста). |
| `mountUpdatesPanel(el)` | рендерит вкладку "Updates" внутри `el` (строковый id или элемент): **Check for update**, **Update now**, переключатели `auto_on_webui_open`/`auto_on_reboot`, поля boot-retry, селект **Network** (`net_policy`: Wi-Fi+мобильная / только-Wi-Fi / только-мобильная) и поля `source`/`channel`/`profile`. |
| `check()` | запускает `update.sh check`; `Promise<{update,from,to,fetch,reboot}>`. |
| `startUpdate()` | запускает `run` в фоне + тост прогресса с **Cancel**. |
| `cancel()` | создаёт `$VDLU_DIR/cancel` (engine останавливается на безопасной точке). |
| `resume()` | `update.sh resume` + тост (возобновляет текущую фазу). |
| `refreshBanner()` | переоценивает постоянный баннер pending-reboot. |

Тост (угловой оверлей, неблокирующий) и баннер (сверху, постоянный) внедряются виджетом в
`document.body` - хосту не нужен HTML для них. Вкладка "Updates" это единственная точка, которую хост выделяет (пустой
`<div>`).

### Поток состояний, который отражает тост (journal.json, §4)

`PLANNED → FETCHING → FETCHED → APPLYING → APPLIED_LIVE → (PENDING_REBOOT | DONE)`, `ERROR` в любой момент. Тост
показывает **полосу + `phase done/total · current · bytes`**. Терминалы:
- **`DONE`** → зелёный тост "v&lt;target&gt; применена".
- **`PENDING_REBOOT`** (или `reboot_pending=true`) → зелёный тост + **постоянный баннер** "⚠️ Перезагрузите для
  активации новой `.so` (vX)".
- **`ERROR`** → красный тост с причиной (`journal.error`/stderr). Никогда не имитирует успех.
- **Отменено** → "отменено - N/M, возобновляемо" + кнопка **Resume**.

## Запуск демо

Откройте `demo.html` в браузере (`xdg-open webui/demo.html`). Мокнутый `ksu.exec` симулирует эволюцию `update.sh` и
`journal.json`, кнопки переключают между сценариями **LIVE→DONE**, **reboot_pending**, **ошибка посреди**
и **отменяемый**. Это те же `vdlu.js`/`vdlu.css`, что и на устройстве.

## i18n (язык)

Строки виджета по умолчанию на **английском** (нейтрально для публичных многоязычных модулей). Хост переопределяет
любой ключ, передавая map в `init`:

```html
<script src="i18n/pt-BR.js"></script>   <!-- defines window.VDLU_I18N_PT_BR -->
<script>VDLU.init({ exec: ex, moduleDir: MOD, vdluDir: VDL, modid: 'x', i18n: window.VDLU_I18N_PT_BR });</script>
```

- **Частичное** слияние допустимо: отсутствующий ключ откатывается к английскому дефолту.
- Ключи phase/state это `ph_<phase>` / `st_<STATE>`, остальное плоское (`cancel`, `updateNow`, …).
- Полный map ключей = объект `DEFAULT_I18N` в `vdlu.js` (также экспонирован как `VDLU.i18n`).
- Готовый перевод предоставлен как проработанный пример: `i18n/pt-BR.js`. Новые языки = файл
  `i18n/<lang>.js` в том же шаблоне, или хост строит map из своей собственной системы i18n.

## Единый источник (паритет между модулями)

Эти `vdlu.js`/`vdlu.css` это **каноническая копия**. Каждый модуль, встраивающий виджет,
**пере-вендорит** эту копию байт-в-байт в свой `webroot/` - он **никогда** не редактирует
свою на месте. Новая функция виджета рождается здесь и спускается вниз через пере-вендоринг, обратное производит
бесшумный дрейф (это случалось на практике: вендоренная копия отстала и была без `net_policy`, тоста
`DEFERRED` и полей `boot_retry`).

Страж: [`../tools/webui-parity.sh`](../../tools/webui-parity.sh) находит каждую копию в дереве исходников и помечает
те, что расходятся с канонической (только `vdlu.js`/`vdlu.css`, keyring это "проверять, не копировать").

```sh
tools/webui-parity.sh         # report; exits 1 if there is drift
tools/webui-parity.sh --fix   # re-vendors the divergent ones from the canonical
```

> 🪤 Keyring (`keyring/<id>.pub` RAW 32B) и engine (`vdlu/update.sh`) имеют свою собственную каденцию пере-вендоринга;
> этот страж покрывает **только WebUI-виджет**.

<!-- doc-footer -->

---

> _Эта документация создана с помощью Claude (Anthropic) и поддерживается VD171. Исправления и улучшения приветствуются, см. [CONTRIBUTING.md](CONTRIBUTING.md)._
