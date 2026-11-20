> **Languages:** [English](../QUICKSTART.md) · العربية · [Čeština](../cs/QUICKSTART.md) · [Deutsch](../de/QUICKSTART.md) · [Español](../es/QUICKSTART.md) · [فارسی](../fa/QUICKSTART.md) · [Français](../fr/QUICKSTART.md) · [हिन्दी](../hi/QUICKSTART.md) · [Bahasa Indonesia](../id/QUICKSTART.md) · [Italiano](../it/QUICKSTART.md) · [日本語](../ja/QUICKSTART.md) · [한국어](../ko/QUICKSTART.md) · [Nederlands](../nl/QUICKSTART.md) · [Polski](../pl/QUICKSTART.md) · [Português](../pt/QUICKSTART.md) · [Русский](../ru/QUICKSTART.md) · [Svenska](../sv/QUICKSTART.md) · [ไทย](../th/QUICKSTART.md) · [Türkçe](../tr/QUICKSTART.md) · [Українська](../uk/QUICKSTART.md) · [Tiếng Việt](../vi/QUICKSTART.md) · [中文](../zh/QUICKSTART.md)

---

# دليل البدء السريع لتبنّي VDLU

قائمة تحقّق جاهزة للّصق لتضمين (vendor) **VDLiveUpdate** داخل وحدة. VDLU ليس وحدة بذاته: يُوضَع
في `<module>/vdlu/` ويُشحَن داخل zip وحدتك. للاطّلاع على الأساس المنطقي الكامل راجع
[`INTERFACES.md`](INTERFACES.md) (عقد التقارب)، و[`ENGINE.md`](ENGINE.md)
و[`PRODUCER.md`](PRODUCER.md) و[`WEBUI.md`](WEBUI.md).

استبدِل `<id>` بمعرّف مفتاح التوقيع لديك، و`<abi>` بالـ ABI(s) التي تشحنها على الجهاز
(`arm64-v8a`، `armeabi-v7a`، `x86_64`، `x86`)، و`<module>` بشجرة وحدتك.

## التخطيط المستهدف

هذه هي شجرة `vdlu/` بالضبط التي تحملها الوحدة بعد التبنّي:

```
<module>/
├── module.prop
├── post-fs-data.sh            # pre-zygote trigger: sh "$MODDIR/vdlu/update.sh" boot
├── webroot/
│   └── index.html             # your WebUI, wiring the Updates panel (step 5)
└── vdlu/
    ├── update.sh              # the engine (vendored byte-for-byte)
    ├── vdlu-verify            # ed25519 verify shim (device-side, no openssl)
    ├── verify/
    │   └── <abi>/ed25519-mini # per-ABI verifier binary
    ├── keyring/
    │   └── <id>.pub           # RAW 32-byte public key (NEVER the PEM)
    ├── config.default         # profile + source + automation defaults
    └── baseline.json          # install seed (unsigned, keyless)
```

الحالة المتغيّرة للمحرّك (`config`، `current.json`، journal، lock) تعيش في Tier-2،
`/data/adb/<modid>/vdlu/`، خارج دليل الوحدة؛ و`config.default` يبذرها عند أوّل تشغيل.

## 1. تضمين المحرّك

انسخ المحرّك، وshim التحقّق، والمتحقّق per-ABI إلى `<module>/vdlu/`:

```sh
mkdir -p <module>/vdlu/verify
cp engine/update.sh      <module>/vdlu/update.sh
cp engine/vdlu-verify    <module>/vdlu/vdlu-verify
cp -r verify/<abi>       <module>/vdlu/verify/<abi>      # ed25519-mini per ABI
```

اشحن فقط الـ ABIs التي تدعمها؛ و`customize.sh` يمكنه تقليم `verify/` إلى ABI الجهاز وقت
التثبيت.

## 2. توليد مفتاح توقيع (مرّة واحدة)

```sh
producer/vdlu-keygen <id> ./keys
```

يُصدِر هذا `<id>.pem` (خاص، أبقِه بعيدًا عن كلّ جهاز وعن أيّ دفع (push) إلى مستودع)، و`<id>.pub`
(PEM، جهة الحاسوب فقط) و`<id>.pub.raw` (RAW بطول 32 بايت، لـ keyring الجهاز).

## 3. تضمين المفتاح العام الخام

يحمل keyring الجهاز المفتاح **RAW بطول 32 بايت**، أبدًا الـ PEM (`ed25519-mini` لا يقدر على قراءة
PEM):

```sh
mkdir -p <module>/vdlu/keyring
cp ./keys/<id>.pub.raw <module>/vdlu/keyring/<id>.pub
```

الـ keyring مستقرّ عبر الإصدارات (لا يتغيّر إلا عند تدوير المفتاح): عند إعادة الـ vendor،
**تحقَّق، لا تكتب فوقه**.

## 4. كتابة الـ config

اشحن `config.default` في `<module>/vdlu/` (يبذر `config` في Tier-2 عند أوّل تشغيل):

```
auto_on_reboot=1
auto_on_webui_open=1
source=https://<user>.github.io/<repo>/<module>
channel=stable
profile=hardened        # public feed: signature mandatory, downgrade blocked
net_policy=any
pubkey_dir=keyring
```

استخدم `profile=trusted` فقط لمصدر `file://`/SSH خاص (التحقّق ببذل أفضل جهد؛ وsha256 كلّ blob
يُفحَص دائمًا). أيّ قيمة غير الحرفية `trusted` تُعامَل كـ `hardened` (fail-closed).

## 5. توصيل المحفّزات (triggers)

**عند الإقلاع** (`auto_on_reboot`): نادِ المحرّك pre-zygote من `post-fs-data.sh` كي تبدَّل الملفات
المُجهَّزة (`.so`، أو overlay لـ `/system`، أو `sepolicy.rule`) دون إقلاع إضافي:

```sh
# <module>/post-fs-data.sh
MODDIR=${0%/*}
sh "$MODDIR/vdlu/update.sh" boot
```

**عند فتح الـ WebUI** (`auto_on_webui_open`): صِل لوحة Updates الجاهزة في `webroot/index.html`:

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
  VDLU.onWebUIOpen();                                             // evaluates journal + banner + auto_on_webui_open
  VDLU.mountUpdatesPanel(document.getElementById('b-updates'));  // the "Updates" tab
</script>
```

(`vdlu.js` / `vdlu.css` مُضمَّنان من `webui/`؛ ويمكن إضافة ترجمة بـ
`i18n: window.VDLU_I18N_<LANG>`.)

## 6. توقيع التغذية في سير عمل الإصدار لديك

في كلّ إصدار، احزم شجرة الوحدة النهائية ووقّع المانيفست. أبقِ المفتاح الخاص على جهاز المشغّل،
أبدًا في CI:

```sh
producer/vdlu-pack  <module>  ./out  <module> <versionCode> --version-name v<versionCode> --channel stable \
                    [--prev ./prev/manifest.json]        # delete[] = paths gone since prev
producer/vdlu-sign  ./out/manifest.json  ./keys/<id>.pem  <id>
# publish ./out/{manifest.json,blobs/} to <source>
```

## 7. شحن الـ baseline

ولّد `baseline.json` فوق الشجرة المشحونة وضعه في `<module>/vdlu/baseline.json`. يبذر
`current.json` عند تثبيت جديد ليولد الجهاز "محدَّثًا" (بلا إعادة جلب). هو **بذرة محلية موثوقة**:
غير موقّع وبلا مفتاح، فيستطيع CI بناءه دون أن يمسّ مفتاح التوقيع أبدًا:

```sh
producer/vdlu-pack  <module>  ./seed  <module> <versionCode> --version-name v<versionCode>
cp ./seed/manifest.json <module>/vdlu/baseline.json
```

غير قاتل إن غاب (يبدأ الجهاز ببساطة من `0` عند أوّل تحديث).

---

هذا كلّ التبنّي. يجب أن يمرّ `sh -n <module>/vdlu/update.sh`؛ اختبر المنتِج والمحرّك من طرف إلى
طرف كما هو موضَّح في [`PRODUCER.md`](PRODUCER.md) وفي README الجذر قبل أن تشحن.

<!-- doc-footer -->

---

> _تم إنشاء هذا التوثيق باستخدام Claude (Anthropic) ويتولى صيانته VD171. التصحيحات والتحسينات مرحّب بها؛ راجع [CONTRIBUTING.md](CONTRIBUTING.md)._
