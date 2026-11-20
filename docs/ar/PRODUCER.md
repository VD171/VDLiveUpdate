> **Languages:** [English](../PRODUCER.md) · العربية · [Čeština](../cs/PRODUCER.md) · [Deutsch](../de/PRODUCER.md) · [Español](../es/PRODUCER.md) · [فارسی](../fa/PRODUCER.md) · [Français](../fr/PRODUCER.md) · [हिन्दी](../hi/PRODUCER.md) · [Bahasa Indonesia](../id/PRODUCER.md) · [Italiano](../it/PRODUCER.md) · [日本語](../ja/PRODUCER.md) · [한국어](../ko/PRODUCER.md) · [Nederlands](../nl/PRODUCER.md) · [Polski](../pl/PRODUCER.md) · [Português](../pt/PRODUCER.md) · [Русский](../ru/PRODUCER.md) · [Svenska](../sv/PRODUCER.md) · [ไทย](../th/PRODUCER.md) · [Türkçe](../tr/PRODUCER.md) · [Українська](../uk/PRODUCER.md) · [Tiếng Việt](../vi/PRODUCER.md) · [中文](../zh/PRODUCER.md)

---

# منتِج VDLU + طبقة التوقيع

يبني التسليم المُعنوَن بالمحتوى (مانيفست + blobs) لوحدة ويوقّعه.
يمتثل لـ [`INTERFACES.md`](INTERFACES.md) §3/§6/§7.

| tool | يعمل على | اللغة | المهمّة |
|---|---|---|---|
| `producer/vdlu-pack` | الحاسوب / CI | python3 | يجول شجرة الوحدة النهائية ← `manifest.json` + `blobs/` |
| `producer/vdlu-keygen` | الحاسوب | sh + openssl | زوج مفاتيح ed25519 (`<id>.pem` priv، `<id>.pub` PEM، `<id>.pub.raw` RAW 32B للـ keyring النحيف) |
| `producer/vdlu-sign` | الحاسوب | sh + openssl | يحقن `key_id` + `sig` في مانيفست، في مكانه |
| `engine/vdlu-verify` | **الجهاز** | sh + ed25519-mini | يتحقّق من `sig` عبر ed25519-mini المضمّن؛ keyring = مفتاح عام RAW 32B (بلا openssl على الجهاز) |

## الـ Pipeline

```sh
# 1. one-time: a signing key. Keep the .pem off every device and off any repo push.
producer/vdlu-keygen release-2026 ./keys

# 2. each release: pack the final tree (same tree the .zip ships, post-whitelist).
producer/vdlu-pack  ./module_tree  ./out  demo 106 --version-name v106 --channel stable \
                    [--prev ./prev/manifest.json]      # delete[] = paths gone since prev

# 3. sign the manifest in place.
producer/vdlu-sign  ./out/manifest.json  ./keys/release-2026.pem  release-2026

# 4. publish ./out/{manifest.json,blobs/} to <source> (Pages batch for public; rsync for private).
#    The slim device keyring holds ./keys/release-2026.pub.raw as keyring/release-2026.pub (RAW 32B).
```

‏`vdlu-pack` مُعنوَن بالمحتوى ومُزيل للتكرار: الـ blob الذي يوجد `<sha256>` الخاص به أصلًا لا يُعاد
كتابته، فالنشر تزايدي والمحتوى غير المتغيّر / المُعاد لا يُدفَع (push) ثانيةً أبدًا.

### قرار `enc` (vdlu-pack)

‏`sha256` هو **دائمًا** للمحتوى الأصلي (غير المضغوط)؛ `enc` يسمّي فقط كيفية تخزين الـ blob.

- `gz` حين `size >= 4096` **و** يوفّر gzip (`-9 -n`، حتمي) 10% على الأقل (`comp <= raw*0.90`).
- `raw` خلاف ذلك (نصّ صغير يغطّيه HTTP gzip أصلًا، أو بيانات غير قابلة للضغط أصلًا).
- gzip مفقود على مضيف البناء ← كل شيء `raw` (لا يفشل أبدًا).

يُخزَّن الـ blob مرّة واحدة، بصيغة واحدة: `blobs/<sha256>` (raw) أو `blobs/<sha256>.gz` (gz). الجهاز
يفكّ الضغط بـ toybox `gunzip` (حاضر دائمًا)، فلا يُحزَم zstd.

### قرار `class` (vdlu-pack) - تصنيف إعادة الإقلاع

مشتقّ من المسار (INTERFACES §3، doc §4). افتراضات فقط؛ قاعدة المسار لا تخفّض أبدًا `reboot`->`live`.

| class | يُطابَق بـ | يُطبَّق |
|---|---|---|
| `reboot` | `system/**`، `zygisk/**/*.so`، `*.rule` | مجهَّز `.vdlu-new`، تبديل عند الإقلاع |
| `soft` | جذر `service.sh` / `post-fs-data.sh` / `boot-completed.sh` | مكتوب حيًّا، يعمل في الإقلاع التالي |
| `live` | كل ما عداه (webroot، bin، lib، confs، module.prop، ...) | مكتوب حيًّا، ذرّيًا |

الروابط الرمزية (symlinks) **لا تُتَّبع** (لا تسرّب أبدًا محتوى من خارج الشجرة، مثلًا رابط إلى
`/etc/shadow`) وتُتخطّى مع تحذير، لأن مخطط المانيفست ليس له نوع symlink.
الملفات غير النظامية (أدلّة، fifos، أجهزة) تُتخطّى. `built` يحترم `SOURCE_DATE_EPOCH` من أجل
مانيفستات قابلة لإعادة الإنتاج.

### Baseline (بذرة التثبيت) - غير موقّعة، بلا مفتاح

‏`baseline.json` (المُشحون عند `vdlu/baseline.json` في zip الوحدة) يبذر `current.json` عند تثبيت جديد
ليولد الجهاز "محدَّثًا" (بلا from:0، بلا إعادة جلب). يعامله المحرّك كـ **بذرة محلية موثوقة**
(وصل في الـ zip المفلَّش، وهو حدّ ثقة التثبيت) و**لا يتحقّق من توقيعه** -
فقط المانيفست **المجلوب** من التغذية يمرّ عبر `vdlu-verify`. لذا لا يحتاج الـ baseline إلى **أي مفتاح**: هو
مجرّد مخرج `vdlu-pack` فوق الشجرة المُشحونة (غير موقّع؛ `sig`/`key_id` يبقيان فارغين). ومن ثمّ يمكن لـ CI
توليده **بلا مفتاح**، فيبقى مفتاح التوقيع 100% خارج CI - فقط التغذية **المنشورة** تُوقَّع (المشغّل،
محليًّا). `vdlu-pack` يستبعد `baseline.json` من مانيفسته هو (مانع للإشارة الذاتية). غير قاتل إن
غاب: يبدأ الجهاز ببساطة from:0 عند أول تحديث، بلا عطب أبدًا.

## التقنين (نقطة التقارب)

يجب على `vdlu-sign` و`engine/vdlu-verify` اشتقاق **البايتات نفسها** من مانيفست، على بيئتَي
تشغيل مختلفتين (حاسوب openssl مقابل جهاز toybox). القاعدة عمدًا تحويلٌ على البايتات،
لا إعادة تسلسل لـ JSON، كيلا تحتاج مكتبة JSON على الجهاز:

1. `vdlu-pack` يكتب `manifest.json` **مضغوطًا، المفاتيح مرتّبة، UTF-8**
   (`json.dumps(obj, sort_keys=True, separators=(",",":"), ensure_ascii=False)`)، مع تضمين
   الحقلين `key_id` و`sig` دائمًا (نائبان نصّيّان فارغان حتى التوقيع). هذه هي صورة التخزين
   القانونية.
2. **الصورة القانونية = ذلك النص بحذف الحقل `"sig"`.** لأن المفاتيح مرتّبة، يظهر `sig`
   دائمًا كـ `,"sig":"<value>",` محصورًا بـ `"schema"` (قبله) و`"version"` (بعده)،
   وكلاهما حاضر دائمًا. حذفه يترك `...,"schema":N,"version":...` سليم التركيب.
   JSON يهرّب كل `"` داخل القيم النصية إلى `\"`، فالرمز البنيوي `"sig":"` لا لبس فيه
   حتى أمام اسم ملف يحوي حرفيًّا `"sig":"` (مُختبَر).
3. الرسالة الموقَّعة/المتحقَّقة هي **sha256 بالست عشري** (64 محرف ASCII، بلا سطر جديد) للصورة
   القانونية. ed25519 فوق ذلك الست عشري (`openssl pkeyutl -sign/-verify -rawin`).

الحذف في POSIX sh (دالة متطابقة في الأداتين، بلا `sed`/`jq`):

```sh
# $1 = full manifest text (trailing newline already stripped by $(cat ...))
_pre=${_c%%\"sig\":\"*}     # up to  ...,"schema":N,
_rest=${_c#*\"sig\":\"}      # after "sig":"
_tail=${_rest#*\",}          # after <value>",  ->  "version":...
printf '%s%s' "$_pre" "$_tail" | sha256sum | cut -d' ' -f1
```

‏`key_id` جزء من الصورة القانونية (يُنزَع `sig` فقط)؛ `vdlu-sign` يضبط `key_id` **قبل**
التجزئة. نائب القيمة سواء كان فارغًا (`"sig":""`، وقت التوقيع) أو ممتلئًا (وقت التحقّق) ينتج البايتات
القانونية نفسها، فيتّفق التوقيع والتحقّق بحكم البناء.

Python يعيد إنتاجه كـ `re.sub(r'"sig":"[^"]*",', '', text.rstrip("\\n"), count=1)` ثم sha256 - يُستخدَم
فقط للتحقّق المتقاطع؛ المنتِجان الموثوقان هما أداتا الـ sh.

## التوقيع (ed25519)

- `vdlu-keygen` (الحاسوب): `openssl genpkey -algorithm ed25519` (priv `0600`) + `openssl pkey -pubout` (pub **PEM**،
  للتوقيع/openssl) + `openssl pkey -pubout -outform DER | tail -c 32` ← **`.pub.raw` (RAW 32B)** (الـ ed25519
  SPKI DER بادئته 12 بايت + المفتاح 32 بايت، فالـ `tail -c 32` **هو** المفتاح). يُصدِر كليهما.
- `vdlu-sign` (الحاسوب): `openssl pkeyutl -sign -rawin` فوق sha256 القانوني بالست عشري؛ التوقيع يُخزَّن base64.
- `vdlu-verify` (**الجهاز، نحيف**): `ed25519-mini <pubkey32> <msg> <sig64>` - يقرأ الـ keyring كمفتاح عام **RAW 32B**،
  بلا openssl على الجهاز. `key_id` مُنقّى المسار (بلا `/`، `.`، `..`، `"`). 🚨 الـ keyring يشحن
  **`.pub.raw` (32B)**، أبدًا `.pub` PEM (113B): الـ PEM جهة الحاسوب فقط و`ed25519-mini` لا يقدر على قراءته.

نموذج الثقة (INTERFACES §6، doc §11/§13): `profile=hardened` (public) يجعل التحقّق إلزاميًّا - توقيع
فاشل أو مفقود يُجهض التحديث. `profile=trusted` (خاص، مصدر مُجهَّز عبر SSH) يعامل
التحقّق كبذل أفضل جهد، لكن sha256 كل blob يُفحَص على أي حال.

## الـ Keyring + التدوير

الـ keyring مجلّد من ملفات `<key_id>.pub`، كلٌّ منها مفتاح ed25519 العام **RAW 32B** (من `.pub.raw` الخاص بـ
‏`keygen`)، لا PEM - `ed25519-mini` يقرأ 32 بايت خامًا. اشحن المفتاح العام الخام الحالي **و** السابق
(doc §13) كيلا يُعطِّل مفتاحٌ مُدوَّر التثبيتات الأقدم. `vdlu-sign` بالـ `key_id` الجديد والجهاز
يختار `<keyring>/<key_id>.pub` (raw) هو كامل آلية التدوير - بلا تغيير في المحرّك. الـ keyring
**مستقرّ** عبر الإصدارات (لا يغيّره سوى تدوير المفتاح): إعادة الـ vendor يجب أن **تحقِّق-لا-تنسخ** وألّا
تكتب فوقه أبدًا بالـ `.pub` PEM جهة الحاسوب.

**على keyrings متعدّدة المفاتيح أن تثبّت مفتاح الوحدة.** يقصر المحرّك أيّ `key_id` يجوز له توقيع MODULE-UPDATE على قائمة سماح `key_id` في config (INTERFACES §5/§6)، ويُفحَص بنمط fail-closed قبل اختيار pubkey. keyring بمفتاح واحد آمن افتراضيًا (ذلك المفتاح الوحيد مقبول). لكن وحدة يحمل keyring الخاص بها أيضًا مفتاحًا أدنى ثقة - مثل مفتاح fingerprint-feed إلى جانب مفتاح الإصدار - تُرفض حتى يعلن `config` الخاص بها مفتاح الوحدة، مثل `key_id=vd-2026` (مفصولة بفواصل للتدوير، مثل `key_id=vd-2026,vd-2027`). هذا يمنع مفتاحًا أدنى ثقة مسرَّبًا من توقيع تحديث root من نوع flashless.

‏`vdlu-pack` **يستبعد الـ keyring وثنائيّات `verify/` من التغذية** (جذر الثقة فلاش-فقط، لا يُخدَم عبر الشبكة أبدًا)، إلى جانب `baseline.json`، وسقالة المثبِّت (`META-INF/`، `customize.sh`)، وبوابة الفلاش `.vd/`، و`update.json`/`update-mmrl.json` المملوءَين بـ CI، ورفقاء `.sha256` لكل ملف. محتوى الوحدة وحده قابل للتحديث عبر التغذية، فلا يستطيع مانيفست أبدًا إعادة كتابة مرساة الثقة على الجهاز.

<!-- doc-footer -->

---

> _تم إنشاء هذا التوثيق باستخدام Claude (Anthropic) ويتولى صيانته VD171. التصحيحات والتحسينات مرحّب بها؛ راجع [CONTRIBUTING.md](CONTRIBUTING.md)._
