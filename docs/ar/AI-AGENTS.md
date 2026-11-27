> **Languages:** [English](../AI-AGENTS.md) · العربية · [Čeština](../cs/AI-AGENTS.md) · [Deutsch](../de/AI-AGENTS.md) · [Español](../es/AI-AGENTS.md) · [فارسی](../fa/AI-AGENTS.md) · [Français](../fr/AI-AGENTS.md) · [हिन्दी](../hi/AI-AGENTS.md) · [Bahasa Indonesia](../id/AI-AGENTS.md) · [Italiano](../it/AI-AGENTS.md) · [日本語](../ja/AI-AGENTS.md) · [한국어](../ko/AI-AGENTS.md) · [Nederlands](../nl/AI-AGENTS.md) · [Polski](../pl/AI-AGENTS.md) · [Português](../pt/AI-AGENTS.md) · [Русский](../ru/AI-AGENTS.md) · [Svenska](../sv/AI-AGENTS.md) · [ไทย](../th/AI-AGENTS.md) · [Türkçe](../tr/AI-AGENTS.md) · [Українська](../uk/AI-AGENTS.md) · [Tiếng Việt](../vi/AI-AGENTS.md) · [中文](../zh/AI-AGENTS.md)

---

# تشغيل VDLU من وكيل ذكاء اصطناعي

VDLiveUpdate (VDLU) هو المُحدِّث التزايدي بلا فلاش الذي تُضمّنه وحدات KSU/Magisk في `vdlu/`. المحرّك بأكمله يُشغَّل من الصدفة، لذا يمكن لمساعد أو وكيل ذكاء اصطناعي أن يفحص ويُطبّق ويستأنف ويُنهي تحديثاً بلا واجهة، نفس الدورة التي تُشغّلها WebUI، دون واجهة ودون إنسان في الحلقة. حلّل JSON الذي يطبعه، ولا تكشط النص أبداً.

## العقد

نقطة دخول واحدة، تُنفَّذ بصلاحية root على الجهاز، مع ضبط متغيّرات البيئة الثلاثة للمحرّك:

```sh
VDLU_DIR=/data/adb/<mod>/vdlu MODULE_DIR=/data/adb/modules/<mod> MODID=<mod> \
  sh "$MODULE_DIR/vdlu/update.sh" <verb>
```

- `VDLU_DIR` هو دليل الحالة Tier-2 (خارج الوحدة، ينجو من إعادة الفلاش)، و`MODULE_DIR` هو شجرة الوحدة الحيّة، و`MODID` هو معرّف الوحدة.
- `rc 0` = حسناً، `rc != 0` = خطأ، مع السبب على stderr.
- أفعال القراءة (`check`، `status`) تطبع **كائن JSON واحداً** على stdout. حلّله، ولا تكشط النص أبداً.
- يعتمد المحرّك على toybox فقط (`sha256sum`/`gzip`/`base64`) زائد `ed25519-mini` مُضمَّن زائد `curl` ساكن يُجلب عند أول تحديث https، صفر `jq`.

أثناء التطوير يوجد نفس السكربت في `engine/update.sh` في هذا المستودع، لذا فإن `sh engine/update.sh <verb>` مع ضبط المتغيّرات الثلاثة يُشغّل نسخة اختبار بالطريقة نفسها.

## الأفعال

| الفعل | يفعل | يطبع |
|------|------|--------|
| `check` | DIFF للقراءة فقط مقابل المصدر، لا يغيّر شيئاً | `{"update":bool,"from":N,"to":M,"fetch":K,"reboot":bool}`، أو `{"update":false,"ahead":true,"from":N,"to":M}` عندما يكون الجهاز متقدّماً على المصدر (التخفيض محظور، حميد، rc 0) |
| `run` | دورة LIVE كاملة DIFF -> FETCH -> APPLY -> COMMIT، تُطبّق ملفات LIVE وتُجهّز REBOOT-hard، وتحترم `cancel` | التقدّم في `journal.json` |
| `resume` | يستأنف المعاملة المعلّقة من مرحلتها الحالية، عديم الأثر المتكرر، ولا يبدّل `.so` أبداً | `journal.json` مُحدَّث |
| `boot` | وضع pre-zygote، `resume` زائد تبديل `.so` المُجهّز، يُغلق `PENDING_REBOOT` إلى `DONE` | `journal.json` مُحدَّث |
| `status` | لقطة للقراءة فقط، لا يغيّر شيئاً | `journal.json`، أو `{"state":"idle"}` عندما لا تكون أي معاملة نشطة |
| `cancel` | يطلب توقّفاً، ويتوقف `run` الجاري عند نقطة الأمان التالية | يُنشئ `$VDLU_DIR/cancel` |

التحديث بلا واجهة هو `check` لرؤية إن كان هناك شيء معلّق، و`run` لتطبيق كل ما يمكن أن يصبح حيّاً، ثم `boot` عند الإقلاع التالي لتبديل أي `.so` مُجهّز (أو `resume` لإعادة محاولة جلب مؤجَّل). كل فعل آمن للاستدعاء مجدداً، وانهيار أو انقطاع شبكة في منتصف الدورة يترك سجلاً قابلاً للاستئناف، لا وحدة مُطبَّقة نصفياً أبداً.

## JSON الحالة

`status` (والملف الحيّ في `$VDLU_DIR/journal.json`) هو عقد التقدّم الذي تقرأه كل من WebUI والوكيل:

```json
{ "schema":1, "module":"<id>", "target":<version>, "from":<version>,
  "phase":"diff|fetch|apply|commit",
  "state":"PLANNED|FETCHING|FETCHED|APPLYING|APPLIED_LIVE|PENDING_REBOOT|DONE|ERROR|DEFERRED",
  "total":<int>, "done":<int>, "current":"<path>", "bytes":<int>,
  "reboot_pending":bool, "cancelled":bool, "error":"<str|null>",
  "updated":"<ISO8601>",
  "items":[ {"path":"<p>","sha256":"<h>","class":"<c>","st":"pending|fetched|applied|staged|skipped"} ] }
```

- `state` يتحرّك بترتيب ثابت: `PLANNED -> FETCHING -> FETCHED -> APPLYING -> APPLIED_LIVE -> (PENDING_REBOOT | DONE)`.
- `DONE` لا يُبلَغ إلا بعد أن يتطابق إعادة تجزئة كل شيء. ملف REBOOT-hard مُجهّز يُنتج `PENDING_REBOOT`، لا `DONE` زائفاً أبداً، شغّل `boot` لإنهائه.
- `DEFERRED` يعني أن `net_policy` منعت التنزيل، حالة حميدة وقابلة للاستئناف وليست خطأً، تبقى الخطة قائمة ويُكمل `check`/`boot` التالي.
- `ERROR` يحمل السبب في `error`، وتُستعاد ملفات LIVE المُطبَّقة من `rollback/`، ولا تُترك الوحدة مُطبَّقة نصفياً أبداً.
- `cancelled:true` مع `error:null` هو توقّف نظيف، ويبقى السجل قابلاً للاستئناف.

## عقد التماس

كل مكوّن (المحرّك، المُنتِج، WebUI) يتوافق مع [`INTERFACES.md`](INTERFACES.md)، قانون التقارب. أفعال CLI ومخطط `manifest.json` ومفاتيح `journal.json` ومفاتيح config المعرّفة هناك **غير قابلة للتغيير**، عامِل ذلك الملف بوصفه المصدر الوحيد للحقيقة وحاذِ عليه قبل تغيير أي منها. لأجل دواخل المحرّك (المعاملة القابلة للاستئناف، ضمانات الصرامة، استبعاد trust-anchor) انظر [`ENGINE.md`](ENGINE.md)، ولأجل جانب المصدر (بناء وتوقيع المصدر المُعنوَن بالمحتوى) انظر [`PRODUCER.md`](PRODUCER.md).

## قواعد للوكيل

- استخدم الأفعال وJSON، ولا تكشط WebUI أبداً ولا تحرّر ملفات الحالة يدوياً أبداً.
- عامِل `INTERFACES.md` بوصفه غير قابل للتغيير، والتغيير يعني محاذاة العقد أولاً.
- رقعة من وكيل ذكاء اصطناعي تجتاز نفس عتبة المراجعة كأي رقعة أخرى، build دائماً release، لا تُرخِ شيئاً، لا تفقد شيئاً.

<!-- doc-footer -->

---

> _تم إنشاء هذا التوثيق باستخدام Claude (Anthropic) ويتولى صيانته VD171. التصحيحات والتحسينات مرحّب بها؛ راجع [CONTRIBUTING.md](CONTRIBUTING.md)._
