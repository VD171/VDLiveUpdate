> **Languages:** [English](../INTERFACES.md) · العربية · [Čeština](../cs/INTERFACES.md) · [Deutsch](../de/INTERFACES.md) · [Español](../es/INTERFACES.md) · [فارسی](../fa/INTERFACES.md) · [Français](../fr/INTERFACES.md) · [हिन्दी](../hi/INTERFACES.md) · [Bahasa Indonesia](../id/INTERFACES.md) · [Italiano](../it/INTERFACES.md) · [日本語](../ja/INTERFACES.md) · [한국어](../ko/INTERFACES.md) · [Nederlands](../nl/INTERFACES.md) · [Polski](../pl/INTERFACES.md) · [Português](../pt/INTERFACES.md) · [Русский](../ru/INTERFACES.md) · [Svenska](../sv/INTERFACES.md) · [ไทย](../th/INTERFACES.md) · [Türkçe](../tr/INTERFACES.md) · [Українська](../uk/INTERFACES.md) · [Tiếng Việt](../vi/INTERFACES.md) · [中文](../zh/INTERFACES.md)

---

# VDLU - عقد الواجهة (الوصلة بين المكوّنات)

**قانون التقارب:** كل مكوّن يمتثل لهذا الملف. القطع الآتية من 4 وكلاء يجب أن **تتلاءم معًا** - توقيعات
الـ CLI وأسماء الملفات ومفاتيح JSON أدناه **ثابتة لا تتغيّر** (أي تغيير يعني المواءمة هنا أولًا).

مبادئ موروثة من المستودعات: **POSIX sh خالص** على الجهاز (بلا bashisms؛ يعمل مع toybox/busybox +
‏`sha256sum`/`gzip`/`base64` الخاصة بـ toybox + الـ `curl` المجلوب + الـ `ed25519-mini` المضمّن - نحيف، بلا
حزمة ثنائيات)، **بلا تعليقات زائدة**، **دائمًا release**، **صرامة عند الفشل** (معاملة قابلة للاستئناف، لا شيء
"منجز" زورًا، لا شيء يُفقد)، **لا تخفيف لأي شيء**.

---

## 1. تخطيط الحالة (Tier-2، خارج مجلد الوحدة)

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
‏`cancelled:true` في الـ journal = المحرّك توقّف عند إلغاء (حالة غير نهائية وقابلة للاستئناف؛ `error`
يبقى null).

المحرّك مُضمَّن في الوحدة: `$MODULE_DIR/vdlu/update.sh` (+ `vdlu-verify`). `$MODULE_DIR =
/data/adb/modules/<module>`. يستقبل المحرّك عبر env: `VDLU_DIR` و`MODULE_DIR` و`MODID`.

## 2. واجهة سطر أوامر المحرّك (مكوّن ENGINE)

‏`sh update.sh <cmd>` - rc 0 = حسنًا، !=0 = خطأ (السبب على stderr):

| cmd | يفعل |
|---|---|
| `check` | DIFF: ينزّل المانيفست ويقارن؛ يطبع JSON من سطر واحد `{"update":bool,"from":N,"to":M,"fetch":K,"reboot":bool}`؛ لا يغيّر شيئًا. الجهاز متقدّم على التغذية (downgrade محجوب، مُصلَّب) = حالة حميدة: `{"update":false,"ahead":true,"from":N,"to":M}` + rc0 (أبدًا "check failed"). do_diff rc: 2 fetch/parse، 3 verify/meta، 4 ahead |
| `run` | الدورة الكاملة: DIFF→FETCH→APPLY→COMMIT؛ يحترم `cancel`؛ يكتب التقدّم إلى `journal.json`؛ يطبّق LIVE ويجهّز (stages) REBOOT-hard |
| `resume` | يستأنف معاملة `journal.json` من الطور الحالي (idempotent) |
| `boot` | وضع pre-zygote: `resume` + يجري SWAP للـ `staged/*.vdlu-new` (يطبّق الـ `.so`)، يُغلق `PENDING_REBOOT`→`DONE` |
| `status` | يطبع `journal.json` (أو `{"state":"idle"}`) |
| `cancel` | ينشئ `$VDLU_DIR/cancel` (أي `run` جارٍ يتوقّف عند أقرب نقطة آمنة) |

مصدر الـ blob/المانيفست: `source` من الـ config. `<source>` + `/manifest.json` و`/blobs/<sha>` و`/blobs/<sha>.gz`.
‏`source` يبدأ بـ `https://` (ثابت مجلوب بـ curl، TLS) أو `file://` (staging محلي).

## 3. manifest.json (يُنتجه PRODUCER، يستهلكه ENGINE)

```json
{ "schema":1, "module":"<id>", "version":<int>, "version_name":"<str>", "built":"<ISO8601>",
  "engine_min":3, "key_id":"<str>", "channel":"stable",
  "files":[ {"path":"webroot/index.html","sha256":"<hex64>","size":<int>,"mode":"0644","enc":"raw|gz","class":"live|soft|reboot"} ],
  "delete":["<path>"], "sig":"<base64>" }
```

- `files[]` = شجرة الهدف **الكاملة**. `class`: `live` (webroot/bin/lib/confs/scripts-on-demand/module.prop) ·
  `soft` (service.sh/post-fs-data.sh/boot-completed.sh) · `reboot` (`zygisk/**/*.so`, `system/**`, `*.rule`).
  الافتراضي حسب المسار؛ لا يخفّض أبدًا `reboot`→`live`.
- `enc`: `gz` (gzip `-9 -n`، حتمي؛ toybox gunzip على الجهاز) فقط حين يُضغط جيّدًا و كذلك حين يكون
  الحجم ذا شأن؛ `sha256` هو **دائمًا** للمحتوى الأصلي.
- `sig`: توقيع المانيفست القانوني **دون** حقل `sig` (§4 من verify).

## 4. journal.json (ENGINE يكتب، WEBUI يقرأ - عقد التقدّم)

```json
{ "schema":1, "module":"<id>", "target":<version>, "from":<version>,
  "phase":"diff|fetch|apply|commit", "state":"PLANNED|FETCHING|FETCHED|APPLYING|APPLIED_LIVE|PENDING_REBOOT|DONE|ERROR|DEFERRED",
  "total":<int>, "done":<int>, "current":"<path>", "bytes":<int>, "reboot_pending":bool,
  "cancelled":bool, "error":"<str|null>", "updated":"<ISO8601>",
  "items":[ {"path":"<p>","sha256":"<h>","class":"<c>","st":"pending|fetched|applied|staged|skipped"} ] }
```

آلة الحالة (ترتيب ثابت): `PLANNED→FETCHING→FETCHED→APPLYING→APPLIED_LIVE→(PENDING_REBOOT|DONE)`.
‏`DONE` فقط بعد أن تتطابق إعادة تجزئة كل شيء. وجود REBOOT-hard مُجهَّز ⇐ `PENDING_REBOOT` (لا `DONE`). المخارج
من طور `fetch`: `ERROR` (فشل قاسٍ) أو `DEFERRED` (الـ net_policy حجبت التنزيل - حميد/قابل للاستئناف،
ليس خطأً).

## 5. config (key=value، واحد لكل سطر؛ قابل للتحرير في WEBUI)

```
auto_on_webui_open=0
auto_on_reboot=1
source=https://<user>.github.io/<repo>/<module>
channel=stable
profile=trusted        # trusted | hardened. CODE DEFAULT (line absent) = hardened (fail-closed, 9a9a824)
net_policy=any         # any (Wi-Fi+mobile) | wifi (Wi-Fi only) | mobile (mobile only) - gates the DOWNLOAD by network type
allow_metered=0        # ⚠️ SUPERSEDED by net_policy (not consumed by the engine)
pubkey_dir=keyring     # relative to $MODULE_DIR/vdlu (keyring of pubkeys for verify)
ca_path=               # empty = auto-detect of the Android trust store; set a path to override
tools_source=          # empty = derived from source (.../vdlu-tools); feed of the static curl
boot_retry_interval=30 # seconds between probes when BOOT finds the device offline (floor 5s)
boot_retry_minutes=0   # ceiling of the PATIENT retry (AWAKE-time) only at boot; 0 = off. Battery-safe (no wakelock,
                       # no held lock, route probe never wakes the radio) -> a generous ceiling is ~free
```

**إعادة محاولة الإقلاع (offline) - صبورة، آمنة للبطارية:** فقط عند `boot` (أبدًا عند check/auto-open). إذا فشل جلب
المانيفست بسبب الشبكة (`fetch_offline` يصنّف حسب رمز خروج الجالب)، ينتظر ويعيد المحاولة حتى النجاح
أو حتى نفاد `boot_retry_minutes` من زمن اليقظة (AWAKE-time). تصميم **لا يمسك شيئًا ولا يستنزف**:
- **بلا wakelock:** بين المحاولات هو `sleep` يتجمّد في النوم العميق ⇐ الجهاز ينام بشكل طبيعي
  (~بطارية صفر)؛ تتوقّف إعادة المحاولة مؤقتًا وتستأنف بمجرّد أن يكون الجهاز مستيقظًا أصلًا.
- **بلا قفل ممسوك:** `acquire_lock_try`+release **بين** المحاولات (لا يمسك القفل أثناء الانتظار) ⇐
  ‏`run`/الفحص اليدوي لا يُحظَران أبدًا؛ وإن جهّز run يدوي هدفًا (TARGET) في هذه الأثناء، يؤجّل الإقلاع.
- **لا يوقظ الراديو بلا طائل:** مسبار `net_allowed` (عبر `net_type`/`ip route get`، بحث مسار في النواة
  يحترم سياسة توجيه أندرويد؛ بلا حزمة) يبوّب كل محاولة - لا ينفق جلبًا إلا بعد ظهور
  الشبكة.
- **أبدًا** لا يعيد محاولة فشل حتمي (manifest/sig/downgrade). `--connect-timeout 15` على الجلب (لا يعلق
  على بوابة أسر captive portal). `service.sh` يشغّله في الخلفية (الإقلاع لا يعلق أبدًا).
- ⛔ **صارم: تشغيل `boot_retry_minutes>0` يتطلّب المحرّك الصبور** (ذاك الذي فيه
  ‏`net_allowed`+`acquire_lock_try`، القانوني `da7115f4`+). إعادة محاولة الإقلاع **السابقة** (تمسك القفل طوال
  النافذة + تعيد curl أعمى offline) **تستنزف البطارية/توقظ الراديو** - تشغيل إعادة المحاولة في محرّك قديم
  فخّ ذاتي. عند التفعيل، ضمّن المحرّك الحالي.

**‏`net_policy` (any|wifi|mobile):** تبوّب **التنزيل** حسب نوع الشبكة. `net_type()` تصنّف مخرج
‏`ip route get` (واجهة خلوية `rmnet/ccmni/v4-*/clat` = mobile؛ كل ما عداها = wifi؛ بحث في النواة، بلا
حزمة). `net_allowed()` تقارن مع `net_policy` وتبوّب `do_fetch` (الـ blobs) + مسبار إعادة محاولة الإقلاع
الصبور. **فحص المانيفست يبقى مجّانيًا** (صغير ⇐ تبلّغ الواجهة عن تحديث على أي شبكة)؛ فقط التنزيل
ينتظر الشبكة المسموح بها. تنزيل على شبكة غير مسموح بها = حالة **`DEFERRED`** في الـ journal
(ليس ERROR؛ نخب (toast) أزرق ناعم من نوع INFO "waiting for X network"؛ يبقى plan/target، ويُستأنَف عند الفحص/
الإقلاع التالي على الشبكة الصحيحة). `net_policy` **تَجُبُّ** `allow_metered` (التي لم تُستهلَك قط).
المحرّك `97baf887`+ (`file://` لا يُبوَّب أبدًا).

## 6. التوقيع (PRODUCER يوقّع على الحاسوب عبر openssl؛ ENGINE يتحقّق على الجهاز عبر ed25519-mini)

- التقنين (Canonicalization): المانيفست **دون** `sig`، المفاتيح مرتّبة، JSON مضغوط (بلا مسافات زائدة)، UTF-8.
  ما يُوقَّع/يُتحقَّق منه = `sha256` بالست عشري لهذه الصورة القانونية (يمنح حتمية عبر الأدوات).
- `producer/vdlu-sign <manifest.json> <privkey.pem> <key_id>` ← يحقن `key_id` + `sig` (base64 لتوقيع ed25519 للـ sha256 القانوني) في المانيفست، في مكانه.
- `engine/vdlu-verify <manifest.json> <keyring_dir>` ← rc 0 إن طابق الـ `sig` المفتاح العام `<key_id>.pub` في
  الـ keyring (نحيف: المفتاح العام **RAW 32 بايت**). داخليًا بلا openssl: toybox `sha256sum`/`base64 -d` + الثنائي
  المضمّن `ed25519-mini` (CLI `ed25519-mini <pub32> <msg> <sig64>`، rc 0=صالح/1=غير صالح/2=usage).
  ‏rc!=0 = رفض. **`profile=hardened` ⇐ التحقّق إلزامي؛ الفشل = إجهاض.**
  ‏`profile=trusted` ⇐ التحقّق بذل أفضل جهد (المصدر موثوق أصلًا عبر SSH)، لكن تجزئة كل blob **تُفحَص دائمًا**.
- `producer/vdlu-keygen <id> <out>` ← يولّد `<id>.pem` (priv) + `<id>.pub` (PEM، لأدوات الحاسوب) +
  `<id>.pub.raw` (**RAW 32B** = الـ `<id>.pub` للـ keyring النحيف على الجهاز). openssl `genpkey -algorithm ed25519`.

## 7. Blob - التحقّق (ENGINE)

ينزّل `<source>/blobs/<sha>` (أو `.gz` إن كان `enc=gz`)، يكتب `.part`، وإن كان `gz` يفكّ الضغط (`gunzip`)،
يفحص `sha256sum` == `sha256` الخاص بالمانيفست؛ تطابق ← `mv` ذرّي إلى `$VDLU_DIR/blobs/<sha>`. 3 إخفاقات على
الـ blob نفسه = يُجهض الطور (لا شيء يُطبَّق). blob موجود أصلًا في `$VDLU_DIR/blobs/<sha>` بتجزئة سليمة =
يتخطّى التنزيل.

## 8. APPLY حسب الصنف (ENGINE)

- `live`/`soft`: نسخ احتياطي `rollback/<v>/<path>` ← يكتب `$MODULE_DIR/<path>.vdlu-tmp` من الـ blob ← `chmod mode` ←
  ‏`rename` ذرّي فوق الهدف. على تجزئة الهدف أصلًا = تخطٍّ. (في متغيّر Zygisk تذهب الكتابة إلى
  المجلد المركّب (mounted) = دمج لكل ملف، أبدًا `rm -rf` للمجلد.)
- `reboot`: يُجسّد في `$VDLU_DIR/staged/<path>.vdlu-new` (لا يمسّ الحيّ). التبديل (swap) عند `boot`.
- `delete[]`: نسخ احتياطي ← إزالة.

## 9. WEBUI ↔ ENGINE (مكوّن WEBUI)

- يطلق: `ksu.exec("sh $MODULE_DIR/vdlu/update.sh run")` (خلفية).
- التقدّم: استطلاع خفيف `ksu.exec("cat $VDLU_DIR/journal.json")` كل ~1 ثانية تقريبًا؛ يعرض `{phase,state,total,done,current,bytes}`.
- الحيوية (Liveness): غياب الـ journal لـ 8 دقّات ⇐ "no response". journal **متجمّد** (القيم نفسها) لـ 20 دقّة ⇐ يفحص `lock.d`: حيّ = يتابع (جلب بطيء لـ blob واحد)، ميّت = خطأ + Resume. بدون هذا، فإن run مات أثناء الجلب سيجمّد النخب عند "updating".
- الإلغاء: `ksu.exec("touch $VDLU_DIR/cancel")`.
- الـ Config: يقرأ/يكتب `$VDLU_DIR/config` (key=value) في تبويب "Updates".
- النخب (Toast): شريط + `phase done/total · current`؛ عند الانتهاء مع `reboot_pending` ⇐ لافتة ثابتة "reboot to activate the .so".
- Auto-open (`auto_on_webui_open=1`): يجري أولًا `check()` **صامتًا** (بلا نخب تقدّم)؛ لا يطلق الـ `run`+النخب الثابت إلا إذا `update && fetch>0`. محدَّث/متقدّم/لا جديد = نتيجة ضمنية في اللوحة، بلا نخب متبقٍّ. غير تطفّلي كالزر اليدوي (النخب لا يظهر إلا عند وجود تنزيل حقيقي). تهيئة curl (bootstrap) لمرة واحدة.

## 10. الدمج في الـ demo (مكوّن INTEGRATION) - مقتطفات، لا تحرّر الملفات الحيّة

ينتج، في `integration/demo/`، مقتطفات + `INTEGRATION.md` يبيّن أين يذهب كلٌّ منها (دون تطبيق):
- خطّاف `auto_on_reboot` في `post-fs-data`/`service.sh` (pre-zygote ← `update.sh boot`) و`auto_on_webui_open`.
- افتراضات `config` + الـ keyring المضمّن + الـ vendoring (`modules/<mod>/vdlu/`).
- المتغيّر **الجزئي** (دمج في المجلد المركّب).

## 11. سلسلة الأدوات المجلوبة + baseline (نحيف، النهج B)

**التخطيط في الوحدة (zip):** `vdlu/{update.sh, vdlu-verify, config.default, keyring/<id>.pub (RAW 32B),
verify/<abi>/ed25519-mini, baseline.json}`. **بلا** `bin/` (openssl/curl/zstd). يستطيع `customize.sh` تقليم
‏`verify/` إلى ABI الجهاز (`vdlu-verify` يجد الـ mini عند `<dir>/ed25519-mini` أو `<dir>/verify/<abi>/ed25519-mini`).

**ed25519-mini** (ثنائي مضمّن، للتحقّق فقط): `ed25519-mini <pubkey32> <msg> <sig64>` ← rc 0=صالح،
1=غير صالح، 2=usage/IO. msg = البايتات الموقّعة بالضبط (لا يعيد التجزئة). TweetNaCl PD، ثابت لكل ABI، PROVENANCE.

**tools-feed** (ملف public/https فقط): يُقدَّم عند `<tools_source>` (الافتراضي مشتقّ: يستبدل آخر مقطع
من `source` بـ `vdlu-tools`، مثلًا `https://<user>.github.io/<repo>/vdlu-tools`). يحتوي:
- `tools-manifest.json` - مانيفست `vdlu-pack` **موقّع** فوق شجرة `<abi>/curl`، يثبّت `sha256` كلّ
  curl (المفتاح نفسه `release-2026`).
- `<abi>/curl` - الـ curl **الثابت** الخام (مكتفٍ ذاتيًا، ~1MB؛ curl 8.11.1 + mbedTLS). 🪤 mbedTLS لا
  يحمل حزمة CA: `fetch_url` يمرّر `--capath` (كشف تلقائي لمخزن ثقة أندرويد: `/system/etc/security/cacerts`
  ← APEX conscrypt؛ `ca_path` يتجاوز). لا capath = خطأ 60. السلامة هي ed25519؛ وفحص الشهادة دفاع متعمّق.

**install-tool** (ENGINE): `update.sh install-tool <abi>` يقرأ `$VDLU_DIR/.work/{tools-manifest.json, tool.<abi>}`
(الـ WEBUI ينزّله عبر `fetch()` ويكتبه هناك)، **يتحقّق من توقيع tools-manifest (ed25519-mini،
إلزامي في أي ملف تعريف)** + تجزئة الـ curl == المانيفست، وعندها فقط يثبّته في `$VDLU_DIR/tools/<abi>/curl` (0755).
الـ curl يعمل كـ root ← sig+hash قبل exec يُغلق الـ RCE. يبقى في Tier-2: لا يُعاد تنزيله أبدًا (إلا عند إلغاء التثبيت).

**fetch-bootstrap** (WEBUI، `ensureToolchain()`): يعمل قبل check/run/resume. `file://` = لا عمل؛ curl **متوفّر أصلًا**
(Tier-2، أو `module/bin/<abi>/curl` من وحدة **مُحزَّمة ذاتيًا**، أو النظام) = لا عمل
(VDLU يعيد استخدام الـ curl الموجود)؛ فقط `https` **بلا أي curl إطلاقًا** ينزّل curl + tools-manifest عبر الـ webview، ويكتبهما
إلى `.work` (base64 مقطّع عبر `ksu.exec`)، ويستدعي `install-tool`. الثقة = الفحص على الجهاز، لا التنزيل.

> 🪤 **النحيف (fetch-bootstrap) ≠ إلزامي.** وحدة يوجد `bin/` فيها من أجل مزاياها **الخاصة** (مثلًا تحزم
> restic/rclone/age/tar/curl...) **لا** تتنحّف إلى ~2MB ولا تنزّل curl - يتبنّى VDLU المحرّك النحيف
> (gz، mini، baseline، الإصلاحات) و**يعيد استخدام** سلسلة الأدوات المضمّنة. فقط الوحدات بلا سلسلة أدوات خاصة
> تكسب الـ ~2MB.

**baseline.json** (إصلاح from:0): يَنسخ الإصدار الـ `manifest.json` **الموقّع** للنسخة المُشحونة إلى
`vdlu/baseline.json`؛ عند تثبيت جديد يبذر المحرّك `current.json` منه (`init_paths`، فقط إن كان غائبًا) ← يولد
الجهاز "محدَّثًا"، بلا تحديث ذاتي لنفسه وبلا إعادة جلب.

<!-- doc-footer -->

---

> _تم إنشاء هذا التوثيق باستخدام Claude (Anthropic) ويتولى صيانته VD171. التصحيحات والتحسينات مرحّب بها؛ راجع [CONTRIBUTING.md](CONTRIBUTING.md)._
