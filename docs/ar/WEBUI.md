> **Languages:** [English](../WEBUI.md) · العربية · [Čeština](../cs/WEBUI.md) · [Deutsch](../de/WEBUI.md) · [Español](../es/WEBUI.md) · [فارسی](../fa/WEBUI.md) · [Français](../fr/WEBUI.md) · [हिन्दी](../hi/WEBUI.md) · [Bahasa Indonesia](../id/WEBUI.md) · [Italiano](../it/WEBUI.md) · [日本語](../ja/WEBUI.md) · [한국어](../ko/WEBUI.md) · [Nederlands](../nl/WEBUI.md) · [Polski](../pl/WEBUI.md) · [Português](../pt/WEBUI.md) · [Русский](../ru/WEBUI.md) · [Svenska](../sv/WEBUI.md) · [ไทย](../th/WEBUI.md) · [Türkçe](../tr/WEBUI.md) · [Українська](../uk/WEBUI.md) · [Tiếng Việt](../vi/WEBUI.md) · [中文](../zh/WEBUI.md)

---

# VDLU - عنصر WebUI (تحديث بلا فلاش)

واجهة VDLU (VD Live Update) لـ WebUI مدير جذر KernelSU/APatch. Vanilla JS، بلا إطار عمل، بلا
بناء، بلا CDN. جاهزة للإسقاط (Drop-in): الـ `index.html` المضيف يحمّل الملفين ويستدعي الـ API.

التقارب: `INTERFACES.md` §9 (WEBUI↔ENGINE)، §4 (journal.json)، §5 (config).

## الملفات

| الملف | ما هو |
|---|---|
| `vdlu.js` | العنصر - يُظهِر `window.VDLU` |
| `vdlu.css` | نخب التقدّم، لافتة إعادة الإقلاع، تبويب "Updates" (سمة داكنة، يرث متغيّرات المضيف) |
| `demo.html` | صفحة مستقلّة بـ `ksu.exec` مُحاكى - تُفتح في متصفّح، بلا جهاز |

## الدمج في الـ `index.html` المضيف

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

### ما يجب على المضيف تعريفه

- **`moduleDir`** = `$MODULE_DIR` (`/data/adb/modules/<modid>`)، حيث المحرّك مُضمَّن
  (`vdlu/update.sh`).
- **`vdluDir`** = `$VDLU_DIR` (`/data/adb/<modid>/vdlu`)، حالة Tier-2 (`journal.json`، `config`،
  `cancel`).
- **`modid`** = معرّف الوحدة.

يجمّع العنصر أمر المحرّك حاملًا أصلًا env الخاص بالعقد (§1):
`VDLU_DIR=… MODULE_DIR=… MODID=… sh $MODULE_DIR/vdlu/update.sh <cmd>`. `run`/`resume` يذهبان إلى
**الخلفية** (`(… &)`)، ويُقرأ التقدّم باستطلاع خفيف (~1 ثانية) لـ `cat $VDLU_DIR/journal.json`.

### `exec`/`toast`/`confirm` (اختياري)

إن حُذِفت، يستخدم العنصر خاصّته:
- **`exec(cmd)`** يجب أن يُرجع `Promise` **يُحقَّق (resolves)** بـ stdout (rc 0) و**يُرفَض (rejects)** بـ stderr
  (rc≠0) - تمامًا توقيع `ex()` في `webroot/index.html` الخاص بالـ Demo. البديل الداخلي يستدعي
  `ksu.exec(cmd, '{}', cb)` بالعقد نفسه.
- **`toast(msg)`** = إشعار عابر قصير (البديل يحقن نخبه المصغّر الخاص).
- **`confirm(title,msg,ok,danger,fn)`** = نافذة (modal) (تُستخدَم اليوم من المضيف فقط؛ العنصر لا يتطلّب أي
  تأكيد في أي تدفّق).

تمرير خاصّة المضيف يجعل العنصر يتكلّم عبر **نفس** الطابور المُسلسَل والمرئيات كبقية الـ
WebUI.

## الـ API العام (`window.VDLU`)

| الدالة | تفعل |
|---|---|
| `init(opts)` | تهيّئ (انظر أعلاه). تُرجع `window.VDLU`. |
| `onWebUIOpen()` | ادعُها عند التحميل: تُظهِر اللافتة إن كان `reboot_pending`؛ تعرض **Resume** إن وُجدت معاملة غير نهائية؛ مع `auto_on_webui_open=1` تشغّل **تحديثًا تلقائيًّا صامتًا** (أولًا `check()` صامت؛ لا تطلق `run`+نخبًا ثابتًا إلا إذا `update && fetch>0` - محدَّث/متقدّم = نتيجة ضمنية في اللوحة، بلا نخب). |
| `mountUpdatesPanel(el)` | تعرض تبويب "Updates" داخل `el` (معرّف نصّي أو عنصر): **Check for update**، **Update now**، مفاتيح `auto_on_webui_open`/`auto_on_reboot`، حقول boot-retry، قائمة **Network** (`net_policy`: Wi-Fi+mobile / Wi-Fi-only / mobile-only) وحقول `source`/`channel`/`profile`. |
| `check()` | تشغّل `update.sh check`؛ `Promise<{update,from,to,fetch,reboot}>`. |
| `startUpdate()` | تطلق `run` في الخلفية + نخب تقدّم بزر **Cancel**. |
| `cancel()` | تنشئ `$VDLU_DIR/cancel` (المحرّك يتوقّف عند النقطة الآمنة). |
| `resume()` | `update.sh resume` + نخب (تستأنف الطور الحالي). |
| `refreshBanner()` | تعيد تقييم لافتة إعادة الإقلاع المعلّقة الثابتة. |

يحقن العنصر النخب (تراكب ركني، غير حاجب) واللافتة (أعلى، ثابتة) في
`document.body` - لا يحتاج المضيف أي HTML لهما. تبويب "Updates" هو النقطة الوحيدة التي يخصّصها المضيف (`<div>`
فارغ).

### تدفّق الحالة الذي يعكسه النخب (journal.json، §4)

`PLANNED → FETCHING → FETCHED → APPLYING → APPLIED_LIVE → (PENDING_REBOOT | DONE)`؛ `ERROR` في أي لحظة.
النخب يُظهِر **شريطًا + `phase done/total · current · bytes`**. النهايات:
- **`DONE`** ← نخب أخضر "v&lt;target&gt; applied".
- **`PENDING_REBOOT`** (أو `reboot_pending=true`) ← نخب أخضر + **لافتة ثابتة** "⚠️ Reboot to
  activate the new `.so` (vX)".
- **`ERROR`** ← نخب أحمر بالسبب (`journal.error`/stderr). لا يزيّف النجاح أبدًا.
- **Cancelled** ← "cancelled - N/M, resumable" + زر **Resume**.

## تشغيل الـ demo

افتح `demo.html` في متصفّح (`xdg-open webui/demo.html`). الـ `ksu.exec` المُحاكى يحاكي `update.sh` و
‏`journal.json` المتطوّر؛ الأزرار تبدّل بين سيناريوهات **LIVE→DONE** و**reboot_pending** و**error mid-way**
و**cancellable**. إنه نفس `vdlu.js`/`vdlu.css` الموجود على الجهاز.

## i18n (اللغة)

نصوص العنصر افتراضها **الإنجليزية** (محايدة للوحدات العامة متعدّدة اللغات). المضيف يتجاوز
أي مفتاح بتمرير خريطة (map) في `init`:

```html
<script src="i18n/pt-BR.js"></script>   <!-- defines window.VDLU_I18N_PT_BR -->
<script>VDLU.init({ exec: ex, moduleDir: MOD, vdluDir: VDL, modid: 'x', i18n: window.VDLU_I18N_PT_BR });</script>
```

- الدمج **الجزئي** جائز: مفتاح مفقود يعود إلى الافتراض الإنجليزي.
- مفاتيح الطور/الحالة هي `ph_<phase>` / `st_<STATE>`؛ الباقي مسطّح (`cancel`، `updateNow`، …).
- خريطة المفاتيح الكاملة = كائن `DEFAULT_I18N` في `vdlu.js` (مُظهَر أيضًا كـ `VDLU.i18n`).
- تُقدَّم ترجمة جاهزة كمثال معالَج: `i18n/pt-BR.js`. اللغات الجديدة = ملف
  `i18n/<lang>.js` على القالب نفسه، أو يبني المضيف الخريطة من نظام i18n الخاص به.

## مصدر واحد (التكافؤ عبر الوحدات)

هذان الـ `vdlu.js`/`vdlu.css` هما **النسخة القانونية**. كل وحدة تُضمِّن العنصر
**تعيد vendor** هذه النسخة بايتًا ببايت إلى `webroot/` الخاص بها - **أبدًا** لا تحرّر نسختها في مكانها.
ميزة جديدة في العنصر تولد هنا وتنساب نزولًا بإعادة الـ vendor؛ والعكس يولّد انحرافًا صامتًا
(حدث عمليًّا: نسخة مُضمَّنة تأخّرت ونقصها `net_policy` ونخب `DEFERRED`
وحقول `boot_retry`).

الحارس: [`../tools/webui-parity.sh`](../../tools/webui-parity.sh) يجد كل نسخة في شجرة المصدر ويعلّم
المنحرفة عن القانونية (فقط `vdlu.js`/`vdlu.css`؛ الـ keyring هو "تحقّق، لا تنسخ").

```sh
tools/webui-parity.sh         # report; exits 1 if there is drift
tools/webui-parity.sh --fix   # re-vendors the divergent ones from the canonical
```

> 🪤 الـ keyring (`keyring/<id>.pub` RAW 32B) والمحرّك (`vdlu/update.sh`) لهما إيقاع إعادة vendor
> خاص بهما؛ هذا الحارس يغطّي **فقط** عنصر الـ WebUI.

<!-- doc-footer -->

---

> _تم إنشاء هذا التوثيق باستخدام Claude (Anthropic) ويتولى صيانته VD171. التصحيحات والتحسينات مرحّب بها؛ راجع [CONTRIBUTING.md](CONTRIBUTING.md)._
