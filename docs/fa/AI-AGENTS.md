> **Languages:** [English](../AI-AGENTS.md) · [العربية](../ar/AI-AGENTS.md) · [Čeština](../cs/AI-AGENTS.md) · [Deutsch](../de/AI-AGENTS.md) · [Español](../es/AI-AGENTS.md) · فارسی · [Français](../fr/AI-AGENTS.md) · [हिन्दी](../hi/AI-AGENTS.md) · [Bahasa Indonesia](../id/AI-AGENTS.md) · [Italiano](../it/AI-AGENTS.md) · [日本語](../ja/AI-AGENTS.md) · [한국어](../ko/AI-AGENTS.md) · [Nederlands](../nl/AI-AGENTS.md) · [Polski](../pl/AI-AGENTS.md) · [Português](../pt/AI-AGENTS.md) · [Русский](../ru/AI-AGENTS.md) · [Svenska](../sv/AI-AGENTS.md) · [ไทย](../th/AI-AGENTS.md) · [Türkçe](../tr/AI-AGENTS.md) · [Українська](../uk/AI-AGENTS.md) · [Tiếng Việt](../vi/AI-AGENTS.md) · [中文](../zh/AI-AGENTS.md)

---

# راندن VDLU از یک عامل هوش مصنوعی

VDLiveUpdate (VDLU) به‌روزرسانی افزایشیِ بدون فلش است که ماژول‌های KSU/Magisk آن را در `vdlu/` جاسازی می‌کنند. کل موتور از پوسته رانده می‌شود، بنابراین یک دستیار یا عامل هوش مصنوعی می‌تواند یک به‌روزرسانی را بدون رابط بررسی، اعمال، از سر‌گیری و تکمیل کند، همان چرخه‌ای که WebUI اجرا می‌کند، بدون رابط کاربری و بدون انسان در حلقه. JSON که چاپ می‌کند را تجزیه کنید، هرگز متن را اسکرپ نکنید.

## قرارداد

یک نقطهٔ ورود واحد، که با دسترسی root روی دستگاه اجرا می‌شود، با سه متغیر محیطی موتور تنظیم‌شده:

```sh
VDLU_DIR=/data/adb/<mod>/vdlu MODULE_DIR=/data/adb/modules/<mod> MODID=<mod> \
  sh "$MODULE_DIR/vdlu/update.sh" <verb>
```

- `VDLU_DIR` دایرکتوری وضعیت Tier-2 است (بیرون از ماژول، از یک ری‌فلش جان سالم به در می‌برد)، `MODULE_DIR` درخت زندهٔ ماژول است، `MODID` شناسهٔ ماژول است.
- `rc 0` = درست، `rc != 0` = خطا، با دلیل روی stderr.
- افعال خواندن (`check`، `status`) **یک شیء JSON** را روی stdout چاپ می‌کنند. آن را تجزیه کنید، هرگز متن را اسکرپ نکنید.
- موتور تنها به toybox (`sha256sum`/`gzip`/`base64`) به‌علاوهٔ یک `ed25519-mini` جاسازی‌شده به‌علاوهٔ یک `curl` ایستا که در نخستین به‌روزرسانی https دریافت می‌شود وابسته است، صفر `jq`.

در حین توسعه همان اسکریپت در `engine/update.sh` در این مخزن قرار دارد، بنابراین `sh engine/update.sh <verb>` با سه متغیر تنظیم‌شده یک نسخهٔ آزمایشی را به همان روش می‌راند.

## افعال

| فعل | انجام می‌دهد | چاپ می‌کند |
|------|------|--------|
| `check` | DIFF فقط‌خواندنی در برابر فید، چیزی را تغییر نمی‌دهد | `{"update":bool,"from":N,"to":M,"fetch":K,"reboot":bool}`، یا `{"update":false,"ahead":true,"from":N,"to":M}` هنگامی که دستگاه از فید جلوتر است (تنزل مسدود، بی‌خطر، rc 0) |
| `run` | چرخهٔ کامل LIVE یعنی DIFF -> FETCH -> APPLY -> COMMIT، فایل‌های LIVE را اعمال و REBOOT-hard را صحنه‌آرایی می‌کند، `cancel` را رعایت می‌کند | پیشرفت در `journal.json` |
| `resume` | تراکنش معلق را از فاز کنونی‌اش از سر می‌گیرد، خودتوان، هرگز `.so` را جابه‌جا نمی‌کند | `journal.json` به‌روز |
| `boot` | حالت pre-zygote، `resume` به‌علاوهٔ جابه‌جایی `.so` صحنه‌آرایی‌شده، `PENDING_REBOOT` را به `DONE` می‌بندد | `journal.json` به‌روز |
| `status` | عکس فوری فقط‌خواندنی، چیزی را تغییر نمی‌دهد | `journal.json`، یا `{"state":"idle"}` هنگامی که هیچ تراکنشی فعال نیست |
| `cancel` | درخواست توقف می‌دهد، یک `run` در حال اجرا در نقطهٔ امن بعدی می‌ایستد | `$VDLU_DIR/cancel` را می‌سازد |

یک به‌روزرسانی بدون رابط یعنی `check` برای دیدن اینکه آیا چیزی معلق است، `run` برای اعمال هر چیزی که می‌تواند زنده شود، سپس `boot` در بوت بعدی برای جابه‌جایی هر `.so` صحنه‌آرایی‌شده (یا `resume` برای تلاش دوبارهٔ یک دریافت به‌تعویق‌افتاده). هر فعل برای فراخوانی دوباره امن است، یک کرش یا قطع شبکه در میانهٔ چرخه یک ژورنال قابل‌ازسرگیری باقی می‌گذارد، هرگز یک ماژول نیمه‌اعمال‌شده نه.

## JSON وضعیت

`status` (و فایل زنده در `$VDLU_DIR/journal.json`) قرارداد پیشرفتی است که هم WebUI و هم عامل آن را می‌خوانند:

```json
{ "schema":1, "module":"<id>", "target":<version>, "from":<version>,
  "phase":"diff|fetch|apply|commit",
  "state":"PLANNED|FETCHING|FETCHED|APPLYING|APPLIED_LIVE|PENDING_REBOOT|DONE|ERROR|DEFERRED",
  "total":<int>, "done":<int>, "current":"<path>", "bytes":<int>,
  "reboot_pending":bool, "cancelled":bool, "error":"<str|null>",
  "updated":"<ISO8601>",
  "items":[ {"path":"<p>","sha256":"<h>","class":"<c>","st":"pending|fetched|applied|staged|skipped"} ] }
```

- `state` در ترتیبی ثابت حرکت می‌کند: `PLANNED -> FETCHING -> FETCHED -> APPLYING -> APPLIED_LIVE -> (PENDING_REBOOT | DONE)`.
- `DONE` تنها پس از آنکه هش دوبارهٔ همه‌چیز مطابقت کند حاصل می‌شود. یک فایل REBOOT-hard صحنه‌آرایی‌شده `PENDING_REBOOT` می‌دهد، هرگز `DONE` ساختگی نه، `boot` را اجرا کنید تا آن را تمام کند.
- `DEFERRED` یعنی `net_policy` دانلود را مسدود کرده است، حالتی بی‌خطر و قابل‌ازسرگیری و نه یک خطا، طرح باقی می‌ماند و `check`/`boot` بعدی ادامه می‌دهد.
- `ERROR` دلیل را در `error` حمل می‌کند، فایل‌های LIVE اعمال‌شده از `rollback/` بازگردانده می‌شوند، ماژول هرگز نیمه‌اعمال‌شده رها نمی‌شود.
- `cancelled:true` با `error:null` یک توقف تمیز است، ژورنال قابل‌ازسرگیری می‌ماند.

## قرارداد درز

هر مؤلفه (موتور، تولیدکننده، WebUI) با [`INTERFACES.md`](INTERFACES.md)، قانون هم‌گرایی، مطابقت دارد. افعال CLI، شمای `manifest.json`، کلیدهای `journal.json` و کلیدهای config تعریف‌شده در آنجا **تغییرناپذیر** هستند، آن فایل را یگانه منبع حقیقت بدانید و پیش از تغییر هر یک از آن‌ها خود را با آن هم‌تراز کنید. برای درون‌ذات موتور (تراکنش قابل‌ازسرگیری، تضمین‌های سخت‌گیری، استثنای trust-anchor) به [`ENGINE.md`](ENGINE.md) بنگرید، برای سمت فید (ساخت و امضای فید آدرس‌دهی‌شده با محتوا) به [`PRODUCER.md`](PRODUCER.md) بنگرید.

## قواعد برای یک عامل

- افعال و JSON را به کار ببرید، هرگز WebUI را اسکرپ نکنید و هرگز فایل‌های وضعیت را دستی ویرایش نکنید.
- `INTERFACES.md` را تغییرناپذیر بدانید، یک تغییر یعنی ابتدا هم‌ترازکردن قرارداد.
- یک وصله از یک عامل هوش مصنوعی همان خط‌کش بازبینی را مانند هر وصلهٔ دیگر می‌گذراند، build همیشه release، چیزی را سست نکنید، چیزی را از دست ندهید.

<!-- doc-footer -->

---

> _این مستندات با Claude (Anthropic) تولید شده و توسط VD171 نگهداری می‌شود. اصلاحات و بهبودها خوش‌آمد است؛ به [CONTRIBUTING.md](CONTRIBUTING.md) مراجعه کنید._
