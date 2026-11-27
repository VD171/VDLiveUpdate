> **Languages:** [English](../../SECURITY.md) · العربية · [Čeština](../cs/SECURITY.md) · [Deutsch](../de/SECURITY.md) · [Español](../es/SECURITY.md) · [فارسی](../fa/SECURITY.md) · [Français](../fr/SECURITY.md) · [हिन्दी](../hi/SECURITY.md) · [Bahasa Indonesia](../id/SECURITY.md) · [Italiano](../it/SECURITY.md) · [日本語](../ja/SECURITY.md) · [한국어](../ko/SECURITY.md) · [Nederlands](../nl/SECURITY.md) · [Polski](../pl/SECURITY.md) · [Português](../pt/SECURITY.md) · [Русский](../ru/SECURITY.md) · [Svenska](../sv/SECURITY.md) · [ไทย](../th/SECURITY.md) · [Türkçe](../tr/SECURITY.md) · [Українська](../uk/SECURITY.md) · [Tiếng Việt](../vi/SECURITY.md) · [中文](../zh/SECURITY.md)

---

# سياسة الأمان

يطبّق VDLiveUpdate (VDLU) تحديثات flashless بصلاحيات الجذر على وحدة نشطة: فهو يكتب في دليل
الوحدة الخاص بها ويستبدل ملف `.so` الخاص بـ Zygisk عند الإقلاع، مع التشغيل في سياق جذر
الوحدة. نحن نأخذ الأمان على محمل الجد.

## الإبلاغ عن ثغرة أمنية

- **Site:** https://vd171.ru
- **Site:** https://vd.priv8.ru
- **Issues:** https://github.com/VD171/VDLiveUpdate/issues
- **GitHub:** [@VD171](https://github.com/VD171)
- **XDA-Developers:** [@VD171](https://xdaforums.com/m/vd171.4699873/)
- **Telegram:** [@VD_Priv8](https://t.me/VD_Priv8)
- **Channel:** [@Priv8_VD](https://t.me/Priv8_VD)
- **Discord:** [@VD.Priv8](https://discord.com/users/1296831918989639721)
- **E-mail:** vd.priv8@pm.me

أرفق وصفًا واضحًا، وإن أمكن، ملف manifest أو feed يعيد إنتاج المشكلة. سنردّ في أقرب وقت ممكن
وسننسب الفضل إليك إذا رغبت.

## ملاحظات النطاق

- التحديثات عبارة عن كتل (blobs) معنونة بالمحتوى (content-addressed) بالإضافة إلى
  `manifest.json` موقّع بـ ed25519. يتحقق الجهاز من التوقيع باستخدام `ed25519-mini` مضمّن
  (بدون openssl على الجهاز)، ويُفحص كل blob مقابل `sha256` الخاص به قبل استخدامه.
- يتطلب ملف تعريف hardened (الوضع الافتراضي العام) توقيعًا صالحًا ويمنع downgrade. يكون الحد
  الأدنى لإصدار "المصدر" هو `versionCode` للوحدة المثبّتة (المقروء من `module.prop`)، لذا لا
  تُعاد الوحدة أبدًا إلى ما قبل feed.
- جذر الثقة (مفتاح ed25519 العام الخام في `keyring/` وملفات `verify/` الثنائية) هو flash فقط
  ولا يُدوَّر أبدًا عبر الشبكة. يستبعده المنتج من feed ويتجاهل engine كل مسار `vdlu/` في خطة
  تم تنزيلها، لذا لا يمكن لمفتاح توقيع مسرَّب أن يستبدل المتحقق أو المفتاح وأن يُبقي الجذر.
- لا يمكن لملف manifest موقّع بشكل صالح لوحدة أخرى أن يكتب في دليل وحدة مختلفة. يجب أن يساوي
  حقل `module` الموقّع قيمة `MODID` على الجهاز (فحص الارتباط بين الوحدات)، وتبقى كل عملية كتابة
  وحذف محصورة في دليل الوحدة.
- يعمل engine في سياق جذر الوحدة الخاص بها ولا يُضعفه أبدًا. فهو لا يضيف أي صلاحية ولا يُدرج
  أي حقل من manifest في shell، ويُتحقق من كل قيمة `path` و`sha256` و`mode` و`delete[]` بوصفها
  إدخالًا عدائيًا قبل الاستخدام.
- الموقف هو fail-closed. لا تنزلق أبدًا قيمة `profile` تالفة أو غير معروفة إلى قبول محتوى غير
  موقّع (أي شيء ليس `trusted` بالضبط يُعامَل على أنه `hardened`)، وتُكتب نسخة احتياطية قبل
  الكتابة فوق أي ملف، لذا لا يُدمّر apply فاشل الإصدار المثبّت أبدًا.
- راجع [TRUST-MODEL.md](TRUST-MODEL.md) للاطّلاع على نموذج الثقة الكامل وضمانات fail-closed
  وتفاصيل hardening.

<!-- doc-footer -->

---

> _تم إنشاء هذا التوثيق باستخدام Claude (Anthropic) ويتولى صيانته VD171. التصحيحات والتحسينات مرحّب بها؛ راجع [CONTRIBUTING.md](CONTRIBUTING.md)._
