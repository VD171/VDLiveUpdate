> **Languages:** [English](../ENGINE.md) · العربية · [Čeština](../cs/ENGINE.md) · [Deutsch](../de/ENGINE.md) · [Español](../es/ENGINE.md) · [فارسی](../fa/ENGINE.md) · [Français](../fr/ENGINE.md) · [हिन्दी](../hi/ENGINE.md) · [Bahasa Indonesia](../id/ENGINE.md) · [Italiano](../it/ENGINE.md) · [日本語](../ja/ENGINE.md) · [한국어](../ko/ENGINE.md) · [Nederlands](../nl/ENGINE.md) · [Polski](../pl/ENGINE.md) · [Português](../pt/ENGINE.md) · [Русский](../ru/ENGINE.md) · [Svenska](../sv/ENGINE.md) · [ไทย](../th/ENGINE.md) · [Türkçe](../tr/ENGINE.md) · [Українська](../uk/ENGINE.md) · [Tiếng Việt](../vi/ENGINE.md) · [中文](../zh/ENGINE.md)

---

# محرّك VDLU (`update.sh`)

عميل تحديث تزايدي بلا فلاش (flashless) لوحدات KSU/Magisk. يطبّق دورة
‏`DIFF -> FETCH -> APPLY -> COMMIT` كمعاملة قابلة للاستئناف. يمتثل لـ `INTERFACES.md` (قانون
التقارب).

POSIX sh خالص (mksh/busybox/toybox). **نحيف:** يعتمد فقط على toybox (`sha256sum`/`gzip`/`base64`/`date`) +
الـ `ed25519-mini` المضمّن (تحقّق ed25519؛ **بلا openssl على الجهاز**) + `curl` ثابت **يُجلَب** عند أول
تحديث https (الـ WebUI يجري الـ `fetch()`، ويبقيه في Tier-2، و`install-tool` يتحقّق من
توقيعه+تجزئته **قبل** الاستخدام). `file://` لا يحتاج curl. صفر اعتماد على `jq`.

## الاستدعاء

```sh
VDLU_DIR=/data/adb/<mod>/vdlu MODULE_DIR=/data/adb/modules/<mod> MODID=<mod> \
  sh $MODULE_DIR/vdlu/update.sh <cmd>
```

‏`rc 0` = حسنًا؛ `rc != 0` = خطأ (السبب على stderr). `vdlu-verify` يسلّمه مكوّن آخر
(التوقيع في `INTERFACES.md §6`)؛ المحرّك يستدعيه فقط.

| cmd | يفعل |
|---|---|
| `check` | DIFF للقراءة فقط؛ يطبع `{"update":bool,"from":N,"to":M,"fetch":K,"reboot":bool}`؛ لا يغيّر شيئًا |
| `run` | دورة LIVE كاملة + يجهّز REBOOT-hard؛ يحترم `cancel`؛ التقدّم في `journal.json` |
| `resume` | يستأنف المعاملة المعلّقة (`target.json`) من الطور الحالي؛ idempotent؛ **لا** يبدّل الـ `.so` |
| `boot` | وضع pre-zygote: resume **+** يبدّل `staged/*.vdlu-new` ← يُغلق `PENDING_REBOOT`→`DONE`. بلا معاملة معلّقة، يشغّل دورة جديدة ويطبّق كل شيء (بما فيه الـ `.so`) في إقلاع واحد |
| `status` | يطبع `journal.json` (أو `{"state":"idle"}`) |
| `cancel` | ينشئ `$VDLU_DIR/cancel`؛ أي `run` جارٍ يتوقّف عند أقرب نقطة آمنة |

## آلة الحالة (journal.json)

```
PLANNED -> FETCHING -> FETCHED -> APPLYING -> APPLIED_LIVE -> (PENDING_REBOOT | DONE)
```

‏`DONE` فقط بعد أن تتطابق إعادة تجزئة كل شيء. إن جُهِّز أي REBOOT-hard ⇐ `PENDING_REBOOT` (أبدًا
‏`DONE` زائف). `ERROR` عند أي فشل، دون إفساد الوحدة (ملفات LIVE المطبَّقة تُعاد
من `rollback/<v>/`؛ لا شيء "مطبَّق نصفيًا يكذب عن ذلك"). المخرج الحميد لطور `fetch`: **`DEFERRED`** -
التنزيل أُجِّل بسبب `net_policy` (الشبكة غير مسموح بها)؛ يبقى plan/target ويُستأنَف عند الفحص/الإقلاع
التالي (الـ WebUI يعرض نخبًا أزرق إعلاميًا "waiting for X network"، لا خطأً).

## ضمانات الصرامة

- **FETCH:** مبوَّب بـ `net_policy` (any/wifi/mobile؛ http/https فقط، `file://` أبدًا) - شبكة غير مسموح بها ⇐
  ‏`DEFERRED` (قابل للاستئناف)، دون إنفاق بيانات. ينزّل فقط ما هو مفقود إلى `<sha>.part` (curl مع
  ‏`--connect-timeout` + `--speed-time`، لا يعلق أبدًا)، يفكّ ضغط `gz` (toybox `gunzip`)، يفحص `sha256sum` ==
  المانيفست، `mv` ذرّي إلى `blobs/<sha>`. يُتخطّى الـ blob المخبّأ+السليم. يمكنه بذر الـ blob من ملف محلي
  غير متغيّر (dedup/offline). **3 إخفاقات على الـ blob نفسه = يُجهض الطور دون تطبيق أي شيء.** لا يصبح
  ‏`FETCHED` إلا بعد حضور+تحقّق **كل** blobs الخطّة.
- **APPLY** (فقط من `FETCHED`): `live`/`soft` ← نسخ احتياطي إلى `rollback/<v>/` ← `.vdlu-tmp` ← `chmod` ← verify ←
  ‏`rename` ذرّي. `reboot` ← يُجسّد في `staged/<path>.vdlu-new` (لا يمسّ الـ inode الحيّ).
  `delete[]` ← نسخ احتياطي ← إزالة. idempotent (ملف على تجزئة الهدف أصلًا يُتخطّى).
- **COMMIT:** إعادة تجزئة لكل `live`/`soft`؛ وعندها فقط يكتب `current.json`. مع ملفات مجهَّزة ⇐
  ‏`PENDING_REBOOT`. `boot` يجري `mv -f staged/....vdlu-new $MODULE_DIR/<path>` (pre-zygote) + يعيد التحقّق +
  ‏`DONE`.
- **cancel:** يُفحَص بين الملفات (نقطة آمنة)؛ يزيل الـ `.vdlu-tmp`/`.part` الجارية، يحذف `cancel`،
  يترك الـ journal قابلًا للاستئناف (`cancelled:true`, `error:null`).
- **mkdir-lock `$VDLU_DIR/lock.d`** يُسلسِل (flock غير عملي على toybox؛ stale-recovery حسب PID).
  إعادة محاولة الإقلاع **الصبورة** لا تمسك القفل أثناء الانتظار (`acquire_lock_try`+release بين المحاولات) ولا
  wakelock - آمنة للبطارية. تعطّل/شبكة/إقلاع في المنتصف ← `resume`/`boot` يتابع.
- **profile=hardened** ⇐ `vdlu-verify` إلزامي على المانيفست **قبل** الاستخدام؛ الفشل = إجهاض؛ downgrade محجوب
  (نسخة رتيبة التزايد). **trusted** ⇐ التحقّق بذل أفضل جهد، لكن تجزئة كل blob **تُفحَص دائمًا**.
- **قائمة سماح لمفتاح module-update (كلا الـ profiles):** يرفض `verify_manifest`، بنمط fail-closed، أيّ مانيفست لا يكون `key_id` الخاص به ضمن قائمة سماح `key_id` المضبوطة (انظر INTERFACES §5/§6) قبل اختيار pubkey، فلا يستطيع مفتاح أدنى ثقة يقبع فقط في الـ keyring (مثل مفتاح fingerprint-feed) أن يوقّع أبدًا تحديث root من نوع flashless. آمن افتراضيًا عند عدم الضبط: keyring بمفتاح واحد = ذلك المفتاح الوحيد فقط؛ keyring متعدّد المفاتيح = مرفوض حتى يُثبَّت `key_id`.
- يتدهور بسلاسة: ثنائي مفقود / شبكة ساقطة / قرص ممتلئ ← خطأ واضح على stderr + `state:ERROR` في
  الـ journal، دون إفساد الوحدة.

## تحليل JSON بلا jq

مُسطِّح (flattener) على نمط gron في `awk` (POSIX خالص: `substr`/`index`/`gsub`/`split`/`printf` + محليّات تُمرَّر
كمعاملات) يجزّئ المانيفست حرفًا بحرف ويُصدِر سطر `path<TAB>value` واحدًا لكل ورقة قياسية
(`files/0/sha256<TAB>ab..`، `version<TAB>6`، `delete/0<TAB>etc/x`). صامد أمام JSON المضغوط **أو** المنسَّق
بأناقة. الـ `sh` يستهلكه بـ `grep`/`cut`؛ وتُعاد خطّة كلّ ملف في `awk` ثانٍ إلى TSV
(`class st mode enc sha size path`)، التي تصير `$VDLU_DIR/plan.tsv`.

## ملفات الحالة (في `$VDLU_DIR`، Tier-2)

| ملف | الدور |
|---|---|
| `config` | key=value (`source`/`profile`/`channel`/`net_policy`/`key_id`/`boot_retry_*`/…؛ انظر INTERFACES §5) |
| `current.json` | مانيفست النسخة **النشطة** (diff base)؛ غائب = لم يُحدَّث قط |
| `target.json` | مانيفست مثبَّت للمعاملة الجارية (الوجود = معاملة نشطة)؛ يصير `current.json` عند `DONE` |
| `plan.tsv` / `plan.del` | الخطّة + تقدّم كلّ ملف (st) / مسارات للحذف |
| `journal.json` | التقدّم للـ WebUI (يُعاد توليده عند كل انتقال) |
| `blobs/<sha256>` | ذاكرة مؤقتة للمحتوى الأصلي المتحقَّق منه |
| `rollback/<version>/<path>` | نسخة احتياطية للملفات المكتوب فوقها (تراجع؛ يُبقي آخر 3) |
| `staged/<path>.vdlu-new` | REBOOT-hard بانتظار التبديل عند الإقلاع |
| `lock.d/` | mkdir-lock (flock غير عملي على toybox؛ stale-recovery حسب PID) |
| `tools/<abi>/curl` | curl ثابت مجلوب (تهيئة نحيفة)؛ يبقى عبر التحديثات |
| `cancel` | طلب إلغاء |

<!-- doc-footer -->

---

> _تم إنشاء هذا التوثيق باستخدام Claude (Anthropic) ويتولى صيانته VD171. التصحيحات والتحسينات مرحّب بها؛ راجع [CONTRIBUTING.md](CONTRIBUTING.md)._
