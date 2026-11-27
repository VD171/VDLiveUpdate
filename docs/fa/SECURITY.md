> **Languages:** [English](../../SECURITY.md) · [العربية](../ar/SECURITY.md) · [Čeština](../cs/SECURITY.md) · [Deutsch](../de/SECURITY.md) · [Español](../es/SECURITY.md) · فارسی · [Français](../fr/SECURITY.md) · [हिन्दी](../hi/SECURITY.md) · [Bahasa Indonesia](../id/SECURITY.md) · [Italiano](../it/SECURITY.md) · [日本語](../ja/SECURITY.md) · [한국어](../ko/SECURITY.md) · [Nederlands](../nl/SECURITY.md) · [Polski](../pl/SECURITY.md) · [Português](../pt/SECURITY.md) · [Русский](../ru/SECURITY.md) · [Svenska](../sv/SECURITY.md) · [ไทย](../th/SECURITY.md) · [Türkçe](../tr/SECURITY.md) · [Українська](../uk/SECURITY.md) · [Tiếng Việt](../vi/SECURITY.md) · [中文](../zh/SECURITY.md)

---

# سیاست امنیتی

‏VDLiveUpdate (VDLU) به‌روزرسانی‌های flashless با دسترسی روت را روی یک ماژول فعال اعمال
می‌کند: در دایرکتوری خودِ ماژول می‌نویسد و هنگام بوت یک فایل `.so` مربوط به Zygisk را
جابه‌جا می‌کند و در زمینهٔ روت ماژول اجرا می‌شود. ما امنیت را جدی می‌گیریم.

## گزارش یک آسیب‌پذیری

- **Site:** https://vd171.ru
- **Site:** https://vd.priv8.ru
- **Issues:** https://github.com/VD171/VDLiveUpdate/issues
- **GitHub:** [@VD171](https://github.com/VD171)
- **XDA-Developers:** [@VD171](https://xdaforums.com/m/vd171.4699873/)
- **Telegram:** [@VD_Priv8](https://t.me/VD_Priv8)
- **Channel:** [@Priv8_VD](https://t.me/Priv8_VD)
- **Discord:** [@VD.Priv8](https://discord.com/users/1296831918989639721)
- **E-mail:** vd.priv8@pm.me

یک توضیح روشن و در صورت امکان یک manifest یا feed که مشکل را بازتولید کند ضمیمه کنید. در
اسرع وقت پاسخ می‌دهیم و اگر بخواهید از شما نام می‌بریم.

## یادداشت‌های محدوده

- به‌روزرسانی‌ها بلاب‌های content-addressed به‌علاوهٔ یک `manifest.json` امضاشده با ed25519
  هستند. دستگاه امضا را با `ed25519-mini` تعبیه‌شده بررسی می‌کند (بدون openssl روی دستگاه) و
  هر blob پیش از استفاده در برابر `sha256` خودش بررسی می‌شود.
- پروفایل hardened (پیش‌فرض عمومی) امضای معتبر را الزامی می‌کند و downgrade را مسدود می‌کند.
  نسخهٔ "مبدأ" با `versionCode` ماژول نصب‌شده (خوانده‌شده از `module.prop`) از پایین محدود
  می‌شود، بنابراین یک ماژول هرگز به عقب‌تر از feed بازگردانده نمی‌شود.
- ریشهٔ اعتماد (کلید عمومی خام ed25519 در `keyring/` و باینری‌های `verify/`) فقط-فلش است و
  هرگز از طریق شبکه چرخانده نمی‌شود. تولیدکننده آن را از feed حذف می‌کند و engine هر مسیر
  `vdlu/` را در یک طرح دانلودشده نادیده می‌گیرد، بنابراین یک کلید امضای فاش‌شده نمی‌تواند
  تأییدکننده یا کلید را جابه‌جا کند و روت را ماندگار کند.
- یک manifest که به‌طور معتبر برای ماژول دیگری امضا شده نمی‌تواند در دایرکتوری یک ماژول
  متفاوت بنویسد. فیلد `module` امضاشده باید با `MODID` روی دستگاه برابر باشد (بررسی اتصال بین
  ماژول‌ها) و هر نوشتن و حذف محدود به دایرکتوری ماژول می‌ماند.
- ‏engine در زمینهٔ روت خودِ ماژول اجرا می‌شود و هرگز آن را تضعیف نمی‌کند. هیچ امتیازی اضافه
  نمی‌کند و هیچ فیلدی از manifest را در یک shell درج نمی‌کند، هر مقدار `path`، `sha256`،
  `mode` و `delete[]` پیش از استفاده به‌عنوان ورودی خصمانه اعتبارسنجی می‌شود.
- وضعیت fail-closed است. یک مقدار `profile` خراب یا ناشناخته هرگز به پذیرش محتوای امضانشده
  نمی‌لغزد (هر چیزی که دقیقاً `trusted` نباشد به‌عنوان `hardened` در نظر گرفته می‌شود) و پیش
  از بازنویسی هر فایلی یک پشتیبان نوشته می‌شود، بنابراین یک apply ناموفق هرگز نسخهٔ نصب‌شده را
  از بین نمی‌برد.
- برای مدل اعتماد کامل، ضمانت‌های fail-closed و جزئیات hardening به [TRUST-MODEL.md](TRUST-MODEL.md)
  مراجعه کنید.

<!-- doc-footer -->

---

> _این مستندات با Claude (Anthropic) تولید شده و توسط VD171 نگهداری می‌شود. اصلاحات و بهبودها خوش‌آمد است؛ به [CONTRIBUTING.md](CONTRIBUTING.md) مراجعه کنید._
