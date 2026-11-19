> **Languages:** [English](../../CONTRIBUTING.md) · العربية · [Čeština](../cs/CONTRIBUTING.md) · [Deutsch](../de/CONTRIBUTING.md) · [Español](../es/CONTRIBUTING.md) · [فارسی](../fa/CONTRIBUTING.md) · [Français](../fr/CONTRIBUTING.md) · [हिन्दी](../hi/CONTRIBUTING.md) · [Bahasa Indonesia](../id/CONTRIBUTING.md) · [Italiano](../it/CONTRIBUTING.md) · [日本語](../ja/CONTRIBUTING.md) · [한국어](../ko/CONTRIBUTING.md) · [Nederlands](../nl/CONTRIBUTING.md) · [Polski](../pl/CONTRIBUTING.md) · [Português](../pt/CONTRIBUTING.md) · [Русский](../ru/CONTRIBUTING.md) · [Svenska](../sv/CONTRIBUTING.md) · [ไทย](../th/CONTRIBUTING.md) · [Türkçe](../tr/CONTRIBUTING.md) · [Українська](../uk/CONTRIBUTING.md) · [Tiếng Việt](../vi/CONTRIBUTING.md) · [中文](../zh/CONTRIBUTING.md)

---

# المساهمة في VDLiveUpdate

VDLU محرّك تحديث ذاتي تزايدي بلا فلاش (flashless)، مُضمَّن في وحدات KernelSU/APatch/Magisk.
المساهمات مرحَّب بها.

- اقرأ [INTERFACES.md](INTERFACES.md) أولًا: إنه عقد الوصلة بين المكوّنات (قانون
  التقارب). عامله كثابت لا يتغيّر ما لم يكن التغيير منسَّقًا عبر المحرّك والمنتِج والـ WebUI.
- اختبر من طرف إلى طرف قبل أي PR: `producer/vdlu-keygen` و`vdlu-pack` و`vdlu-sign`، ثم المحرّك
  (`check` / `run` / `boot`). وكذلك `sh -n engine/*.sh` و`node --check webui/vdlu.js`.
- الأمن غير قابل للتفاوض: كل حقل في المانيفست مدخلٌ معادٍ و`validate_plan()` يبقى
  fail-closed؛ مفتاح التوقيع الخاص لا يمسّ CI ولا جهازًا أبدًا.
- POSIX sh على الجهاز (بلا bashisms عدا `local`، بلا `jq`)؛ أبقِ التعليقات موجزة.
- تغيير منطقي واحد لكل PR؛ بيّن ما تغيّر ولماذا.

## جهات الاتصال

- Telegram: @VD_Priv8 https://t.me/VD_Priv8
- القناة: @Priv8_VD https://t.me/Priv8_VD
- البريد الإلكتروني: vd.priv8@pm.me

<!-- doc-footer -->

---

> _تم إنشاء هذا التوثيق باستخدام Claude (Anthropic) ويتولى صيانته VD171. التصحيحات والتحسينات مرحّب بها؛ راجع [CONTRIBUTING.md](CONTRIBUTING.md)._
