> **Languages:** [English](../WEBUI.md) · [العربية](../ar/WEBUI.md) · [Čeština](../cs/WEBUI.md) · [Deutsch](../de/WEBUI.md) · [Español](../es/WEBUI.md) · فارسی · [Français](../fr/WEBUI.md) · [हिन्दी](../hi/WEBUI.md) · [Bahasa Indonesia](../id/WEBUI.md) · [Italiano](../it/WEBUI.md) · [日本語](../ja/WEBUI.md) · [한국어](../ko/WEBUI.md) · [Nederlands](../nl/WEBUI.md) · [Polski](../pl/WEBUI.md) · [Português](../pt/WEBUI.md) · [Русский](../ru/WEBUI.md) · [Svenska](../sv/WEBUI.md) · [ไทย](../th/WEBUI.md) · [Türkçe](../tr/WEBUI.md) · [Українська](../uk/WEBUI.md) · [Tiếng Việt](../vi/WEBUI.md) · [中文](../zh/WEBUI.md)

---

# VDLU - ویجتِ WebUI (به‌روزرسانیِ flashless)

رابطِ VDLU (VD Live Update) برای یک WebUIِ root managerِ KernelSU/APatch. Vanilla JS، بدون framework، بدون build،
بدون CDN. Drop-in: `index.html`ِ میزبان دو فایل را بارگذاری می‌کند و API را صدا می‌زند.

همگرایی: `INTERFACES.md` §9 (WEBUI↔ENGINE)، §4 (journal.json)، §5 (config).

## فایل‌ها

| File | چیست |
|---|---|
| `vdlu.js` | مولفه - `window.VDLU` را آشکار می‌کند |
| `vdlu.css` | toast پیشرفت، بنرِ reboot، زبانه‌ی "Updates" (تم تیره، متغیرهای میزبان را به‌ارث می‌برد) |
| `demo.html` | صفحه‌ی standalone با یک `ksu.exec`ِ mock‌شده - در مرورگر باز می‌شود، بدون دستگاه |

## ادغام در `index.html`ِ میزبان

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

### آنچه میزبان باید تعریف کند

- **`moduleDir`** = `$MODULE_DIR` (`/data/adb/modules/<modid>`)، جایی که موتور vendor شده (`vdlu/update.sh`).
- **`vdluDir`** = `$VDLU_DIR` (`/data/adb/<modid>/vdlu`)، وضعیتِ Tier-2 (`journal.json`، `config`، `cancel`).
- **`modid`** = idِ ماژول.

ویجت، فرمانِ موتور را مونتاژ می‌کند که پیشاپیش envِ قرارداد (§1) را حمل می‌کند:
`VDLU_DIR=… MODULE_DIR=… MODID=… sh $MODULE_DIR/vdlu/update.sh <cmd>`. `run`/`resume` به **پس‌زمینه** می‌روند (`(… &)`)،
و پیشرفت با یک pollِ سبک (~۱ ثانیه) از `cat $VDLU_DIR/journal.json` خوانده می‌شود.

### `exec`/`toast`/`confirm` (اختیاری)

اگر حذف شوند، ویجت از مالِ خودش استفاده می‌کند:
- **`exec(cmd)`** باید یک `Promise` برگرداند که با stdout (rc 0) **resolve** و با stderr (rc≠0) **reject** می‌شود - دقیقاً
  امضای `ex()`ِ مربوط به `webroot/index.html`ِ Demo. fallbackِ داخلی `ksu.exec(cmd, '{}', cb)` را با همان قرارداد صدا می‌زند.
- **`toast(msg)`** = یک اعلانِ گذرای کوتاه (fallback، mini-toast خودش را تزریق می‌کند).
- **`confirm(title,msg,ok,danger,fn)`** = یک modal (امروز تنها توسط میزبان استفاده می‌شود؛ ویجت در هیچ جریانی به تایید نیاز
  ندارد).

پاس‌دادنِ مالِ خودِ میزبان باعث می‌شود ویجت از همان صفِ سریالی و همان نماهای بقیه‌ی WebUI سخن بگوید.

## API عمومی (`window.VDLU`)

| Function | چه می‌کند |
|---|---|
| `init(opts)` | پیکربندی می‌کند (بالا را ببین). `window.VDLU` را برمی‌گرداند. |
| `onWebUIOpen()` | هنگام بارگذاری صدایش بزن: اگر `reboot_pending` باشد بنر را نشان می‌دهد؛ اگر یک تراکنشِ غیرپایانی باشد **Resume** را پیشنهاد می‌کند؛ با `auto_on_webui_open=1` یک **خودبه‌روزرسانیِ بی‌صدا** اجرا می‌کند (ابتدا یک `check()`ِ خاموش؛ تنها اگر `update && fetch>0` باشد `run`+toast ماندگار را شلیک می‌کند - به‌روز/جلوتر = نتیجه‌ی درون‌خطی در پنل، صفر toast). |
| `mountUpdatesPanel(el)` | زبانه‌ی "Updates" را درونِ `el` (idِ رشته‌ای یا element) رندر می‌کند: **Check for update**، **Update now**، توگل‌های `auto_on_webui_open`/`auto_on_reboot`، فیلدهای boot-retry، selectِ **Network** (`net_policy`: Wi-Fi+mobile / تنها Wi-Fi / تنها mobile) و فیلدهای `source`/`channel`/`profile`. |
| `check()` | `update.sh check` را اجرا می‌کند؛ `Promise<{update,from,to,fetch,reboot}>`. |
| `startUpdate()` | `run` را در پس‌زمینه شلیک می‌کند + یک toast پیشرفت با **Cancel**. |
| `cancel()` | `$VDLU_DIR/cancel` را می‌سازد (موتور در نقطه‌ی امن می‌ایستد). |
| `resume()` | `update.sh resume` + toast (فاز جاری را ازسر می‌گیرد). |
| `refreshBanner()` | بنرِ ماندگارِ pending-reboot را دوباره ارزیابی می‌کند. |

toast (اوورلیِ گوشه، غیرمسدودکننده) و بنر (بالا، ماندگار) توسط ویجت در `document.body` تزریق می‌شوند - میزبان برای آن‌ها به
هیچ HTMLی نیاز ندارد. زبانه‌ی "Updates" تنها نقطه‌ای است که میزبان تخصیص می‌دهد (یک `<div>`ِ خالی).

### جریانِ وضعیتی که toast بازتاب می‌دهد (journal.json، §4)

`PLANNED → FETCHING → FETCHED → APPLYING → APPLIED_LIVE → (PENDING_REBOOT | DONE)`؛ `ERROR` در هر لحظه. toast **یک نوار +
`phase done/total · current · bytes`** نشان می‌دهد. پایانی‌ها:
- **`DONE`** → toast سبز "v&lt;target&gt; applied".
- **`PENDING_REBOOT`** (یا `reboot_pending=true`) → toast سبز + **بنرِ ماندگار** "⚠️ Reboot to
  activate the new `.so` (vX)".
- **`ERROR`** → toast قرمز با دلیل (`journal.error`/stderr). هرگز موفقیت را جعل نمی‌کند.
- **لغوشده** → "cancelled - N/M, resumable" + یک دکمه‌ی **Resume**.

## اجرای demo

`demo.html` را در یک مرورگر باز کن (`xdg-open webui/demo.html`). `ksu.exec`ِ mock‌شده، `update.sh` و `journal.json`ِ در حال
تحول را شبیه‌سازی می‌کند؛ دکمه‌ها میان سناریوهای **LIVE→DONE**، **reboot_pending**، **خطا در میانه** و **قابل‌لغو** جابه‌جا
می‌شوند. همان `vdlu.js`/`vdlu.css`ِ روی دستگاه است.

## i18n (زبان)

رشته‌های ویجت به‌طور پیش‌فرض **انگلیسی** هستند (خنثی برای ماژول‌های عمومیِ چندزبانه). میزبان هر کلیدی را با پاس‌دادنِ یک map
در `init` بازنویسی می‌کند:

```html
<script src="i18n/pt-BR.js"></script>   <!-- defines window.VDLU_I18N_PT_BR -->
<script>VDLU.init({ exec: ex, moduleDir: MOD, vdluDir: VDL, modid: 'x', i18n: window.VDLU_I18N_PT_BR });</script>
```

- یک ادغامِ **جزئی** مانعی ندارد: کلیدِ گم‌شده به پیش‌فرضِ انگلیسی بازمی‌گردد.
- کلیدهای phase/state به‌صورت `ph_<phase>` / `st_<STATE>` هستند؛ بقیه مسطح است (`cancel`، `updateNow`، …).
- mapِ کاملِ کلیدها = شیءِ `DEFAULT_I18N` در `vdlu.js` (که به‌صورت `VDLU.i18n` نیز آشکار شده).
- یک ترجمه‌ی آماده به‌عنوان نمونه‌ی کارشده فراهم است: `i18n/pt-BR.js`. زبان‌های تازه = یک فایلِ `i18n/<lang>.js` در همان قالب،
  یا میزبان map را از سیستمِ i18n خودش می‌سازد.

## منبعِ یکتا (برابریِ میان ماژول‌ها)

این `vdlu.js`/`vdlu.css` همان **نسخه‌ی canonical** هستند. هر ماژولی که ویجت را تعبیه می‌کند این نسخه را بایت‌به‌بایت در
`webroot/` خود **دوباره vendor می‌کند** - **هرگز** مالِ خودش را درجا ویرایش نمی‌کند. یک ویژگیِ تازه‌ی ویجت اینجا زاده می‌شود و
با re-vendor به پایین جاری می‌شود؛ عکسِ آن driftِ خاموش می‌سازد (در عمل رخ داده: یک نسخه‌ی vendorشده عقب ماند و `net_policy`،
toastِ `DEFERRED` و فیلدهای `boot_retry` را کم داشت).

نگهبان: [`../tools/webui-parity.sh`](../../tools/webui-parity.sh) هر نسخه را در درختِ منبع می‌یابد و آن‌هایی را که از نسخه‌ی
canonical واگرا شده‌اند متهم می‌کند (تنها `vdlu.js`/`vdlu.css`؛ keyring «تایید، نه کپی» است).

```sh
tools/webui-parity.sh         # report; exits 1 if there is drift
tools/webui-parity.sh --fix   # re-vendors the divergent ones from the canonical
```

> 🪤 keyring (`keyring/<id>.pub` RAW 32B) و موتور (`vdlu/update.sh`) آهنگِ re-vendor خودشان را دارند؛ این نگهبان **تنها
> ویجتِ WebUI** را پوشش می‌دهد.

<!-- doc-footer -->

---

> _این مستندات با Claude (Anthropic) تولید شده و توسط VD171 نگهداری می‌شود. اصلاحات و بهبودها خوش‌آمد است؛ به [CONTRIBUTING.md](CONTRIBUTING.md) مراجعه کنید._
