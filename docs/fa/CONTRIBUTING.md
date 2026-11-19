> **Languages:** [English](../../CONTRIBUTING.md) · [العربية](../ar/CONTRIBUTING.md) · [Čeština](../cs/CONTRIBUTING.md) · [Deutsch](../de/CONTRIBUTING.md) · [Español](../es/CONTRIBUTING.md) · فارسی · [Français](../fr/CONTRIBUTING.md) · [हिन्दी](../hi/CONTRIBUTING.md) · [Bahasa Indonesia](../id/CONTRIBUTING.md) · [Italiano](../it/CONTRIBUTING.md) · [日本語](../ja/CONTRIBUTING.md) · [한국어](../ko/CONTRIBUTING.md) · [Nederlands](../nl/CONTRIBUTING.md) · [Polski](../pl/CONTRIBUTING.md) · [Português](../pt/CONTRIBUTING.md) · [Русский](../ru/CONTRIBUTING.md) · [Svenska](../sv/CONTRIBUTING.md) · [ไทย](../th/CONTRIBUTING.md) · [Türkçe](../tr/CONTRIBUTING.md) · [Українська](../uk/CONTRIBUTING.md) · [Tiếng Việt](../vi/CONTRIBUTING.md) · [中文](../zh/CONTRIBUTING.md)

---

# مشارکت در VDLiveUpdate

VDLU یک موتورِ خودبه‌روزرسانیِ flashless و تدریجی است که در ماژول‌های KernelSU/APatch/Magisk تعبیه (vendor) می‌شود.
مشارکت‌ها خوش‌آمدند.

- ابتدا [INTERFACES.md](INTERFACES.md) را بخوان: این قراردادِ درزِ میان مولفه‌هاست (قانون همگرایی). آن را تغییرناپذیر تلقی
  کن مگر آنکه یک تغییر در سراسرِ موتور، producer و WebUI هماهنگ شود.
- پیش از یک PR، سر-تا-سر آزمون کن: `producer/vdlu-keygen`، `vdlu-pack`، `vdlu-sign`، سپس موتور (`check` / `run` / `boot`).
  همچنین `sh -n engine/*.sh` و `node --check webui/vdlu.js`.
- امنیت غیرقابل‌مذاکره است: هر فیلدِ مانیفست ورودیِ خصمانه است و `validate_plan()`، fail-closed می‌ماند؛ کلیدِ خصوصیِ امضا هرگز
  CI یا یک دستگاه را لمس نمی‌کند.
- sh POSIX روی دستگاه (بدون bashism فراتر از `local`، بدون `jq`)؛ کامنت‌ها را موجز نگه دار.
- یک تغییرِ منطقی در هر PR؛ بگو چه تغییر کرد و چرا.

## تماس‌ها

- Telegram: @VD_Priv8 https://t.me/VD_Priv8
- کانال: @Priv8_VD https://t.me/Priv8_VD
- E-mail: vd.priv8@pm.me

<!-- doc-footer -->

---

> _این مستندات با Claude (Anthropic) تولید شده و توسط VD171 نگهداری می‌شود. اصلاحات و بهبودها خوش‌آمد است؛ به [CONTRIBUTING.md](CONTRIBUTING.md) مراجعه کنید._
