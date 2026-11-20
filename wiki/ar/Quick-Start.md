# Quick Start

هذه قائمة التحقق للتبنّي: كيف تضمّن **VDLiveUpdate (VDLU)** في
وحدة KernelSU / APatch / Magisk. VDLU ليس وحدة بنفسه. يوضع في
`<module>/vdlu/` ويُرسل داخل zip وحدتك، فتستطيع وحدة مثبّتة أن
تحدّث نفسها بلا فلاش من تغذية موقّعة تنشرها.

في كل موضع استبدل `<id>` بمعرّف مفتاح التوقيع لديك، و`<abi>` بمعماريات
ABI للجهاز التي ترسلها (`arm64-v8a`، `armeabi-v7a`، `x86_64`، `x86`)، و`<module>`
بشجرة وحدتك.

للتعليل وراء كل قطعة، انظر [[Engine]] و[[Producer]] و[[WebUI]] و
[[Security and Trust Model]].

## تخطيط `vdlu/` داخل الوحدة

هذه هي الشجرة بالضبط التي تحملها وحدتك بعد التبنّي:

```
<module>/
|-- module.prop
|-- post-fs-data.sh            # pre-zygote trigger: sh "$MODDIR/vdlu/update.sh" boot
|-- webroot/
|   `-- index.html             # your WebUI, wiring the Updates panel (step 5)
`-- vdlu/
    |-- update.sh              # the engine (vendored byte-for-byte)
    |-- vdlu-verify            # ed25519 verify shim (device-side, no openssl)
    |-- verify/
    |   `-- <abi>/ed25519-mini # per-ABI verifier binary
    |-- keyring/
    |   `-- <id>.pub           # RAW 32-byte public key (NEVER the PEM)
    |-- config.default         # profile + source + automation defaults
    `-- baseline.json          # install seed (unsigned, keyless)
```

حالة المحرّك القابلة للتغيير (`config`، `current.json`، السجلّ، القفل، ذاكرة الكتل المؤقّتة)
تعيش في Tier-2 في `/data/adb/<modid>/vdlu/`، خارج دليل الوحدة.
يزرع `config.default` قيمة Tier-2 `config` عند أول تشغيل. انظر [[Engine]] لتخطيط
الحالة الكامل.

## 1. تضمين المحرّك

انسخ المحرّك، وشِم (shim) التحقق، وثنائي المُتحقِّق لكل ABI إلى
`<module>/vdlu/`:

```sh
mkdir -p <module>/vdlu/verify
cp engine/update.sh   <module>/vdlu/update.sh
cp engine/vdlu-verify <module>/vdlu/vdlu-verify
cp -r verify/<abi>    <module>/vdlu/verify/<abi>    # ed25519-mini per ABI
```

أرسل فقط معماريات ABI التي تدعمها. يستطيع `customize.sh` لديك تقليم `verify/` إلى
ABI الجهاز وقت التثبيت.

## 2. توليد مفتاح توقيع (لمرة واحدة)

```sh
producer/vdlu-keygen <id> ./keys
```

يُخرج هذا ثلاثة ملفات:

- `<id>.pem` - المفتاح الخاص. أبقِه بعيدًا عن كل جهاز وخارج أي دفع إلى مستودع
  أو سرّ CI.
- `<id>.pub` - المفتاح العام PEM. جانب الحاسوب فقط (يستخدمه `vdlu-sign`).
- `<id>.pub.raw` - المفتاح العام الخام بحجم 32 بايت، لـ keyring الجهاز.

انظر [[Security and Trust Model]] لسبب أهمية الفصل.

## 3. تضمين المفتاح العام الخام

يحمل keyring الجهاز المفتاح **الخام بحجم 32 بايت**، لا PEM أبدًا. لا يستطيع `ed25519-mini`
قراءة PEM، فنسخ PEM هنا يكسر التحقق على الجهاز:

```sh
mkdir -p <module>/vdlu/keyring
cp ./keys/<id>.pub.raw <module>/vdlu/keyring/<id>.pub
```

الـ keyring مستقرّ عبر الإصدارات: لا يتغيّر إلا عند تدوير مفتاح. وعند
إعادة التضمين، **تحقّق منه، لا تكتب فوقه**.

## 4. كتابة الإعداد

أرسل `config.default` في `<module>/vdlu/`. يزرع Tier-2 `config` عند أول
تشغيل:

```
auto_on_reboot=1
auto_on_webui_open=1
source=https://<user>.github.io/<repo>/<module>
channel=stable
profile=hardened        # public feed: signature mandatory, downgrade blocked
net_policy=any
pubkey_dir=keyring
```

استخدم `profile=trusted` فقط لمصدر `file://` خاص أو SSH (التحقق هناك
بذل أفضل جهد، لكن sha256 لكل كتلة يُفحص مع ذلك). أي قيمة غير
`trusted` الحرفي تُعامَل كـ `hardened`، فاشلة مغلقة. انظر
[[Security and Trust Model]] لدلالة الملفات الشخصية الكاملة.

## 5. ربط المشغّلات

**عند إعادة التشغيل** (`auto_on_reboot`): استدعِ المحرّك قبل الزايغوت من
`post-fs-data.sh`، فتُبدَّل ملفات صنف إعادة التشغيل المُجهَّزة (ملف `.so`، تراكب `/system`،
`sepolicy.rule`) دون إعادة تشغيل إضافية:

```sh
# <module>/post-fs-data.sh
MODDIR=${0%/*}
sh "$MODDIR/vdlu/update.sh" boot
```

**عند فتح WebUI** (`auto_on_webui_open`): اربط لوحة Updates الجاهزة في
`webroot/index.html` لديك:

```html
<link rel="stylesheet" href="vdlu.css">
<script src="vdlu.js"></script>
<script>
  VDLU.init({
    moduleDir: '/data/adb/modules/' + MODID,
    vdluDir:   '/data/adb/' + MODID + '/vdlu',
    modid:     MODID,
    module:    'YourModule'
  });
  VDLU.onWebUIOpen();                                            // journal + banner + auto_on_webui_open
  VDLU.mountUpdatesPanel(document.getElementById('b-updates'));  // the "Updates" tab
</script>
```

يُضمَّن `vdlu.js` و`vdlu.css` من `webui/`. يمكن إضافة ترجمة
بـ `i18n: window.VDLU_I18N_<LANG>`. انظر [[WebUI]] لعقد اللوحة.

## 6. توقيع التغذية في سير عمل الإصدار لديك

عند كل إصدار، احزم شجرة الوحدة النهائية ووقّع البيان. أبقِ المفتاح الخاص
على جهاز المشغّل، لا في CI أبدًا:

```sh
producer/vdlu-pack  <module>  ./out  <module> <versionCode> \
                    --version-name v<versionCode> --channel stable \
                    [--prev ./prev/manifest.json]      # delete[] = paths gone since prev
producer/vdlu-sign  ./out/manifest.json  ./keys/<id>.pem  <id>
# publish ./out/{manifest.json,blobs/} to <source>
```

`vdlu-pack` معنون بالمحتوى ومزيل للتكرار، فالنشر تزايدي:
الكتل غير المتغيّرة لا تُدفع من جديد أبدًا. انظر [[Producer]] و[[Feed Format]].

## 7. إرسال خطّ الأساس

ولّد `baseline.json` فوق الشجرة المُرسلة وضعه في
`<module>/vdlu/baseline.json`. يزرع `current.json` عند تثبيت جديد، فيُولد
الجهاز "محدَّثًا" ولا يعيد جلب نسخته المُرسلة. إنه
**بذرة محلية موثوقة**: غير موقّعة وبلا مفتاح، فيستطيع CI بناءها دون أن يلمس
مفتاح التوقيع أبدًا:

```sh
producer/vdlu-pack  <module>  ./seed  <module> <versionCode> --version-name v<versionCode>
cp ./seed/manifest.json <module>/vdlu/baseline.json
```

إنها غير قاتلة إن غابت: يبدأ الجهاز ببساطة من الإصدار `0` عند
أول تحديث.

---

هذا هو التبنّي كله. قبل أن ترسل، يجب أن يجتاز `sh -n <module>/vdlu/update.sh`،
وينبغي أن تختبر المنتِج والمحرّك من طرف إلى طرف كما هو مبيّن في
[[Contributing]] و[[Producer]].
