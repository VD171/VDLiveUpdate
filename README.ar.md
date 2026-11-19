<!--
  ======================================================================
   VDLiveUpdate (VDLU)  ::  flashless, incremental module updates
   A self-update engine for KernelSU/APatch/Magisk modules: fetch only the
   files that changed, apply the live ones with no reboot, verified by ed25519.

   Copyright (C) 2026  VD171
   SPDX-License-Identifier: Apache-2.0

   Licensed under the Apache License, Version 2.0; you may obtain a copy at
   http://www.apache.org/licenses/LICENSE-2.0

   Site           : https://vd171.ru
   Site           : https://vd.priv8.ru
   Source         : https://github.com/VD171/VDLiveUpdate
   GitHub         : @VD171 https://github.com/VD171
   XDA-Developers : @VD171 https://xdaforums.com/m/vd171.4699873/
   Telegram       : @VD_Priv8 https://t.me/VD_Priv8
   Channel        : @Priv8_VD https://t.me/Priv8_VD
   Discord        : @VD.Priv8 https://discord.com/users/1296831918989639721
   E-mail         : vd.priv8@pm.me
  ======================================================================
-->

# VDLiveUpdate

> **Languages:** [English](README.md) · [العربية](README.ar.md) · [Čeština](README.cs.md) · [Deutsch](README.de.md) · [Español](README.es.md) · [فارسی](README.fa.md) · [Français](README.fr.md) · [हिन्दी](README.hi.md) · [Bahasa Indonesia](README.id.md) · [Italiano](README.it.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Nederlands](README.nl.md) · [Polski](README.pl.md) · [Português](README.pt.md) · [Русский](README.ru.md) · [Svenska](README.sv.md) · [ไทย](README.th.md) · [Türkçe](README.tr.md) · [Українська](README.uk.md) · [Tiếng Việt](README.vi.md) · [中文](README.zh.md)

**VDLU** هو محرك تحديث ذاتي تزايدي بلا فلاش لوحدات **KernelSU / APatch / Magisk**. تُحدِّث الوحدة المثبّتة نفسها بجلب **الملفات التي تغيّرت فقط** (كتل معنونة بالمحتوى + ملف بيان موقَّع)، وتطبِّق الملفات الحية **دون إعادة تشغيل**، وتُنظِّم وتُؤشِّر القليل منها الذي يحتاج فعلًا إلى إعادة تشغيل (ملف `.so`، أو تراكب على `/system`، أو `sepolicy.rule`). بلا مدير جذر، وبلا إعادة تنزيل ملف `.zip` بالكامل، وبلا إعادة تشغيل إلا لتلك الملفات المُنظَّمة.

وهو مصمَّم ليُدمَج **بالاحتواء (vendored)** داخل وحدة (يُسقَط في `<module>/vdlu/`)، لا ليعمل كوحدة بذاته.

## لماذا

يُرسِل التحديث العادي للوحدة ملف `.zip` كاملًا من جديد. فبالنسبة لوحدة كبيرة يعني ذلك تنزيلًا كبيرًا من أجل بضعة أسطر متغيّرة، كما أن البيان الساكن للتحديث لا يستطيع الإشارة إلا إلى `zipUrl` واحد، فلا يمكنه خدمة النكهة (ABI، كامل مقابل lite) التي يملكها الجهاز فعلًا. يقارن VDLU الشجرة **المثبّتة** مقابل feed موقَّع ويجلب الفروق فقط، فيبقى تثبيت arm64-full على حاله arm64-full، ويبقى تثبيت lite على حاله lite، وتُطبَّق معظم التحديثات حيّة.

## كيف يعمل

- **المُنتِج (PC / الإصدار):** يحوّل `vdlu-pack` شجرة وحدة إلى feed معنون بالمحتوى (`manifest.json` + `blobs/<sha256>`، gzip، إزالة التكرار، `delete[]`)؛ و`vdlu-keygen` / `vdlu-sign` (ed25519)؛ ويُقلِّم `vdlu-gc` الكتل اليتيمة بالرجوع إلى آخر N من البيانات (آمن عند الفشل، تشغيل تجريبي افتراضيًا).
- **المحرك (الجهاز):** POSIX sh، بلا `jq`. يشغِّل `update.sh` (`check | run | resume | boot | status | cancel`) المسار DIFF -> FETCH -> APPLY -> COMMIT كمعاملة **قابلة للاستئناف** (journal)، مع تراجع وقفل `mkdir`. يُتحقَّق من التوقيع عبر `ed25519-mini` المُضمَّن (بلا `openssl` على الجهاز).
- **WebUI:** لوحة تحديثات جاهزة للإسقاط (إشعار تقدّم منبثق، إلغاء، لافتة إعادة تشغيل)، بلغة JS صِرفة.

## الملفات التعريفية (Profiles)

- `trusted`: استخدام خاص، مصدر `file://` أو SSH، تحقّق بأفضل جهد (التجزئة دائمًا).
- `hardened`: استخدام عام، **التوقيع إلزامي**، والرجوع إلى إصدار أقدم محظور. البيان **مربوط بمعرِّف الوحدة**، وكل حقل يُتحقَّق منه fail-closed قبل تنزيل أي شيء.

## اعتمدْه في وحدتك

احتوِ `engine/update.sh` + `vdlu-verify` + `verify/<abi>/ed25519-mini` داخل `<module>/vdlu/`، واضمِّن **مفتاحك العام الخام 32 بايت** بوصفه `vdlu/keyring/<id>.pub`، وأضِف ملف `config` (الملف التعريفي + المصدر)، وصِل المُطلِقات (`post-fs-data.sh` قبل zygote للتحديث التلقائي عند الإقلاع؛ ومُطلِق فتح WebUI)، وأضِف `vdlu-pack` + `vdlu-sign` إلى إصدارك. انظر [`integration/`](integration/) للاطّلاع على قالب مُنجَز.

## الأمان

- **كل حقل في البيان مُدخَل عدائي.** يرفض `validate_plan()` البيان كاملًا fail-closed عند أي مسار مطلق أو `..`، أو `sha256` ليس 64 خانة سداسية عشرية، أو وضع / صنف / ترميز غير صالح، **قبل** أي جلب أو تطبيق.
- **مفتاح التوقيع الخاص لا يلمس أبدًا CI ولا جهازًا**؛ يُضمَّن المفتاح العام الخام فقط، والتحقّق يستخدم `ed25519-mini`، لا `openssl`.
- `hardened` مغلق عند الفشل بالعكس: أي قيمة غير `trusted` الحرفية تُعامَل كأنها `hardened`، فلا يمكن لقيمة ملف تعريف تالفة أن تقبل بيانًا غير موقَّع بصمت أبدًا.
- ملفات صنف إعادة التشغيل (`.so`، تراكب `/system`، `sepolicy.rule`) **تُنظَّم، ولا تُكتَب أبدًا فوق inode حيّ**؛ وكل ما عداها يُطبَّق حيًّا. التطبيق الفاشل يُجهِض بدلًا من الكتابة فوق الملف دون نسخة احتياطية.

## البناء / الاختبار

كلّه سكربتات، لا شيء يُترجَم. من طرف إلى طرف (المُنتِج + المحرك معًا):

```sh
producer/vdlu-keygen demo /tmp/k
producer/vdlu-pack /tmp/tree /tmp/feed demo 1 --version-name v1
producer/vdlu-sign /tmp/feed/manifest.json /tmp/k/demo.pem demo
VDLU_DIR=... MODULE_DIR=... MODID=demo sh engine/update.sh check   # then run / boot
```

`sh -n engine/*.sh`، و`node --check webui/vdlu.js`، وافتح `webui/demo.html` في متصفّح (يُحاكي جسر الجهاز).

## التوثيق

- [`INTERFACES.md`](docs/INTERFACES.md): عقد الوصل بين المكوّنات (قانون التقارب؛ عامِله كأنه غير قابل للتغيير).
- `integration/`: دليل اعتماد خطوة بخطوة ومقتطفات التوصيل.

## انظر أيضًا

مشاريع شقيقة للمؤلف نفسه:

- **[VDBackup](https://github.com/VD171/VD-Backup)**: نسخ احتياطي واستعادة كاملان للتطبيقات والبيانات بصلاحيات الجذر، يُدار بالكامل من واجهة WebUI.
- **[COPG-VD](https://github.com/VD171/COPG-VD)**: مُزيِّف جهاز يحوّل بصمة جديدة إلى ملف تعريف متماسك ومتسق.
- **[VD-dropbear](https://github.com/VD171/VD-dropbear)**: خادم SSH مستقل وقابل للإعداد يعمل بصلاحيات الجذر لـ KernelSU/APatch/Magisk.
- **[VDInfos](https://github.com/VD171/VD-Infos)**: مُنقِّح طرق الجهاز يقرأ كل عنصر عبر كل طريقة قادرة على قراءته.
- **[VDGoogle](https://github.com/VD171/VD-Google)**: يقرأ ما تسجّله Google على جهازك، على الجهاز بالكامل ودون إنترنت.

## جهات الاتصال

- https://vd171.ru
- https://vd.priv8.ru
- **Telegram:** @VD_Priv8 https://t.me/VD_Priv8
- **Channel:** @Priv8_VD https://t.me/Priv8_VD
- **Discord:** @VD.Priv8 https://discord.com/users/1296831918989639721
- **E-mail:** vd.priv8@pm.me
- **XDA-Developers:** @VD171 https://xdaforums.com/m/vd171.4699873/
- **GitHub:** @VD171 https://github.com/VD171

## الرخصة

شيفرة VDLiveUpdate نفسها تحت **Apache-2.0**؛ انظر [LICENSE](LICENSE). وهي تحتوي مُحقِّق `ed25519-mini`
صغيرًا و`curl` ساكنًا لإقلاع الجلب، كلٌّ تحت رخصته الخاصة؛ انظر
[NOTICE.md](NOTICE.md) وملفات `PROVENANCE.json` المجاورة للملفات الثنائية المُضمَّنة.

## العلامات التجارية

VDLiveUpdate مشروع مستقل وغير رسمي، غير مرتبط بأي طرف ثالث ولا معتمَد منه.
"Android" علامة تجارية لـ Google LLC؛ و"KernelSU" و"Magisk" و"APatch" علامات أصحابها
المعنيّين. يعمل VDLU بالكامل على جهازك وعلى مضيف الإصدار الخاص بك.

## Tags

`VDLU` `flashless-update` `incremental-update` `KernelSU` `Magisk` `APatch` `module-update` `ed25519` `content-addressed` `OTA` `self-update` `Android` `VDLiveUpdate`

---

📣 **Join the channel for updates:** @Priv8_VD https://t.me/Priv8_VD
