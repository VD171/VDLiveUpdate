> **Languages:** [English](../SECURITY.md) · [العربية](../ar/SECURITY.md) · [Čeština](../cs/SECURITY.md) · [Deutsch](../de/SECURITY.md) · [Español](../es/SECURITY.md) · فارسی · [Français](../fr/SECURITY.md) · [हिन्दी](../hi/SECURITY.md) · [Bahasa Indonesia](../id/SECURITY.md) · [Italiano](../it/SECURITY.md) · [日本語](../ja/SECURITY.md) · [한국어](../ko/SECURITY.md) · [Nederlands](../nl/SECURITY.md) · [Polski](../pl/SECURITY.md) · [Português](../pt/SECURITY.md) · [Русский](../ru/SECURITY.md) · [Svenska](../sv/SECURITY.md) · [ไทย](../th/SECURITY.md) · [Türkçe](../tr/SECURITY.md) · [Українська](../uk/SECURITY.md) · [Tiếng Việt](../vi/SECURITY.md) · [中文](../zh/SECURITY.md)

---

# سیاستِ امنیت و مدلِ اعتماد

VDLiveUpdate (VDLU) **به‌روزرسانی‌های root flashless** را روی یک ماژولِ زنده اعمال می‌کند: در
`/data/adb/modules/<mod>` می‌نویسد و یک `.so`ِ Zygisk را هنگام boot swap می‌کند. هر فیلدِ یک
مانیفستِ واکشی‌شده (`path`، `sha256`، `delete[]`، `mode`، ...) یک **ورودیِ خصمانه** است - یک
feedِ مسموم یا یک MITM آن را تحویل می‌دهد. این صفحه مدلِ اعتماد و سیاستِ افشای مسئولانه است.
برای قراردادِ کاملِ درز نگاه کنید به [`INTERFACES.md`](INTERFACES.md)، و بواطنِ engine/producer در
[`ENGINE.md`](ENGINE.md) و [`PRODUCER.md`](PRODUCER.md)؛ صفحه‌ی ویکیِ
**Security-and-Trust-Model** همین مدل را برای خوانندگانِ بیرونِ مخزن حمل می‌کند.

## نسخه‌های پشتیبانی‌شده

رفع‌های امنیتی در تازه‌ترین `ENGINE_VERSION` فرود می‌آیند؛ یک مانیفستِ امضاشده حداقلِ موتوری را که
نیاز دارد از طریقِ `engine_min` اعلام می‌کند، و موتورِ روی دستگاه مانیفستی را که بیش از آنچه
پیاده کرده بخواهد رد می‌کند. انتظار می‌رود موتورهای vendorشده‌ی قدیمی‌تر برای برداشتنِ یک رفع
**re-vendor** شوند، نه اینکه درجا patch شوند.

| ENGINE_VERSION | وضعیت |
|---|---|
| 4 (جاری) | پشتیبانی‌شده - فهرست مجازِ `key_id`، ردِ path‌های dot-segment/trailing-slash، سقف‌های اندازه، قفلِ check-time |
| 3 | جایگزین‌شده - پیش‌فرضِ `hardened`، `profile`ِ fail-closed با وارونگی، bindِ module/MODID، مسدودیِ downgrade |
| <= 2 | بدون پشتیبانی - موتورِ جاری را re-vendor کن |

هر تغییر در تاییدِ موتور یا منطقِ apply، `ENGINE_VERSION` را بالا می‌برد.

## گزارشِ یک آسیب‌پذیری

خصوصی گزارش بده. برای یک باگِ امنیتی یک issue، PR یا پستِ انجمنِ عمومی **باز نکن**. از
تماس‌های پروژه استفاده کن (نگاه کنید به [`CONTRIBUTING.md`](../CONTRIBUTING.md)):

- Telegram: **@VD_Priv8** (https://t.me/VD_Priv8)
- کانال: **@Priv8_VD** (https://t.me/Priv8_VD)
- ایمیل: **vd.priv8@pm.me**

لطفاً نسخه‌ی موتور، `profile`ِ در استفاده، و یک مانیفست یا feed که مسئله را بازتولید کند بگنجان.
رفع‌ها به‌صورتِ یک `ENGINE_VERSION`ِ تازه با یک ورودی در `CHANGELOG.md` عرضه می‌شوند؛ زمان‌بندیِ
افشا را روی رشته‌ی گزارش هماهنگ کن.

## مدلِ اعتماد

- **امضاهای ed25519ِ جدا (detached).** producer، مانیفستِ canonical را روی PC امضا می‌کند
  (openssl)؛ دستگاه با `ed25519-mini`ِ تعبیه‌شده تایید می‌کند - **بدون openssl روی دستگاه**.
  پیامِ امضاشده همان sha256 هگزِ مانیفست بدونِ فیلدِ `sig`ِ آن است (کلیدها مرتب، فشرده، UTF-8)،
  پس امضا و verify روی دو runtime همان بایت‌ها را بدونِ کتابخانه‌ی JSON روی دستگاه مشتق می‌کنند.
- **keyring = pubkeyهای RAWِ ۳۲ بایتی**، فقط-فلش. keyringِ دستگاه `<key_id>.pub` را به‌صورتِ کلیدِ
  rawِ ۳۲ بایتی عرضه می‌کند (هرگز PEM)؛ `vdlu-pack`، keyring و باینری‌های `verify/` را از feed
  **کنار می‌گذارد**، پس یک مانیفست هرگز نمی‌تواند لنگرِ اعتمادِ روی دستگاه را از طریقِ شبکه بازنویسی کند.
- **فهرست مجازِ `key_id`ِ module-update (fail-closed، پیش از انتخابِ pubkey).** یک keyring ممکن است
  مشروعاً بیش از یک کلید حمل کند (مثلاً یک کلیدِ fingerprint-feedِ کم‌اعتمادتر در کنارِ کلیدِ
  release). پیش از آنکه `<key_id>.pub` اصلاً انتخاب شود، `verify_manifest` هر مانیفستی را که
  `key_id`ِ آن در فهرستِ مجازِ پیکربندی‌شده نباشد، در **هر دو** profiles رد می‌کند، و مجموعه‌ی
  حل‌شده را از طریقِ `VDLU_KEYID_ALLOW` به `vdlu-verify` منعکس می‌کند. این یک دور زدن را می‌بندد که
  در آن یک کلیدِ کم‌اعتمادترِ نشت‌یافته می‌توانست وگرنه یک به‌روزرسانیِ کاملِ flashless root را امضا
  کند. در حالتِ تنظیم‌نشده به‌طورِ پیش‌فرض امن: یک keyringِ **تک‌کلیدی** به‌طورِ خودکار به همان یک
  کلید پین می‌شود؛ یک keyringِ **چندکلیدی** تا پین‌شدنِ `key_id` رد می‌شود (برای چرخش با کاما جدا).
- **ریشه‌ی اعتمادِ fingerprint-feed یک pathِ جدا و پین‌شده** با کلیدِ خودش است؛ هرگز از طریقِ
  pathِ module-updateِ بالا قابلِ دسترسی نیست.
- **baseline یک بذرِ محلیِ موردِ اعتماد است.** `baseline.json` درونِ zipِ فلش‌شده می‌آید - مرزِ
  اعتمادِ نصب - پس بدون امضا و بدون کلید است و از `vdlu-verify` **نمی‌گذرد**؛ تنها مانیفستِ
  **واکشی‌شده** از feed تایید می‌شود. این کلیدِ امضا را بیرونِ CI نگه می‌دارد.

## تضمین‌های fail-closed

- **`validate_plan` پیش از هر fetch یا apply اجرا می‌شود.** در `do_diff`، به‌صورتِ fail-closed،
  **کلِ** مانیفست را رد می‌کند اگر هر `path` مطلق باشد، شاملِ یک segmentِ `..` یا `.` باشد، به
  `/` ختم شود، یا یک کاراکترِ کنترلی داشته باشد؛ اگر هر `sha256` برابرِ `^[0-9a-f]{64}$` نباشد؛
  یا اگر هر `mode`/`class`/`enc` نامعتبر باشد. هیچ فیلدِ خصمانه‌ای به یک shell نمی‌رسد، و
  `cmd_check` هیچ درون‌یابیِ `system()` حمل نمی‌کند.
- **مهارِ path.** هر نوشتن و حذف از طریقِ `contained()` به `MODULE_DIR` محدود است - apply، delete،
  و `stage_file`ِ reboot همگی از همان نگهبان می‌گذرند. symlinkهای درونِ درخت را producer رد می‌کند
  (هرگز محتوایی از بیرونِ آن نشت نمی‌دهند).
- **دو profiles، fail-closed با وارونگی.** `trusted` (خصوصی، منبعِ staged از طریقِ SSH) **تنها**
  opt-in به verifyِ best-effort است؛ **هر** مقدارِ دیگر - از جمله یک typo، یک فاصله/CRِ انتهایی،
  یا حروفِ متفاوت - به‌عنوانِ `hardened` تلقی می‌شود، که در آن یک امضای معتبر **الزامی** است و یک
  شکست abort می‌کند. `sha256`ِ هر blob در هر دو profiles بررسی می‌شود.
- **امضا + هش پیش از هر اجرای ابزار.** `curl`ِ استاتیکِ واکشی‌شده به‌عنوانِ root اجرا می‌شود، پس
  `install-tool` امضای tools-manifest (ed25519-mini، الزامی در **هر** profile) و هشِ curl را
  **پیش از** نصب و اجرای آن تایید می‌کند - sig+hash پیش از exec، RCE را می‌بندد.
- **تراکنشِ ازسرگیری‌پذیر و pin-safe.** مانیفستِ در جریان در `target.json` پین می‌شود؛ یک crash،
  قطعِ شبکه، یا reboot از journal ازسر گرفته می‌شود بدونِ تصمیم‌گیریِ دوباره‌ی plan. downgrade
  مسدود است (`version`ِ یکنوا)، فیلدِ `module`ِ امضاشده باید برابرِ `MODID` باشد، و `delete[]` تنها
  در `finalize_done` اجرا می‌شود (یک `PENDING_REBOOT` هیچ‌چیز حذف نمی‌کند). هیچ‌چیز هرگز بدونِ یک
  re-hashِ کامل «انجام‌شده» نیست؛ هیچ‌چیز بدونِ یک پشتیبانِ `rollback/<v>/` از پیش بازنویسی نمی‌شود.

## سخت‌سازی (دفاع در عمق)

- **سقف‌های اندازه.** مانیفست، tools-manifest، و مسیرِ دانلودِ `wget`/`head -c`ِ بدونِ curl همگی
  پیش از خوانده‌شدن کران‌دار می‌شوند (ضدِ OOM / ضدِ flood). یک blob پس از ۳ تلاش در فازش شکست
  می‌خورد.
- **قفلِ check-time.** `check` پیش از بازسازیِ دایرکتوریِ کارش، mkdir-lock را می‌گیرد، پس یک runِ
  هم‌زمان نمی‌تواند با آن مسابقه دهد.
- **مهارِ staging.** `stage_file` همان نگهبانِ `contained()` را دارد که primitiveهای applyِ زنده
  دارند، پس یک pathِ reboot-hardِ staged نیز نمی‌تواند از `MODULE_DIR` بگریزد.
- **TLS دفاع در عمق است، نه ریشه‌ی اعتماد.** curlِ استاتیک از mbedTLS با trust storeِ اندروید
  استفاده می‌کند (`--capath`، overrideِ `ca_path`)؛ تضمینِ یکپارچگی امضای ed25519 است، بررسیِ cert
  یک لایه‌ی دوم است.

## همچنین نگاه کنید

- [`INTERFACES.md`](INTERFACES.md) - قراردادِ تغییرناپذیرِ درز (§5 config، §6 امضا، §11 toolchain).
- [`ENGINE.md`](ENGINE.md) - موتورِ سمتِ دستگاه و ماشینِ وضعیتش.
- [`PRODUCER.md`](PRODUCER.md) - packing، امضا، canonicalization، و چرخشِ کلید.
- ویکی: **Security-and-Trust-Model**.

<!-- doc-footer -->

---

> _این مستندات با Claude (Anthropic) تولید شده و توسط VD171 نگهداری می‌شود. اصلاحات و بهبودها خوش‌آمد است؛ به [CONTRIBUTING.md](CONTRIBUTING.md) مراجعه کنید._
