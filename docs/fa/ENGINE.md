> **Languages:** [English](../ENGINE.md) · [العربية](../ar/ENGINE.md) · [Čeština](../cs/ENGINE.md) · [Deutsch](../de/ENGINE.md) · [Español](../es/ENGINE.md) · فارسی · [Français](../fr/ENGINE.md) · [हिन्दी](../hi/ENGINE.md) · [Bahasa Indonesia](../id/ENGINE.md) · [Italiano](../it/ENGINE.md) · [日本語](../ja/ENGINE.md) · [한국어](../ko/ENGINE.md) · [Nederlands](../nl/ENGINE.md) · [Polski](../pl/ENGINE.md) · [Português](../pt/ENGINE.md) · [Русский](../ru/ENGINE.md) · [Svenska](../sv/ENGINE.md) · [ไทย](../th/ENGINE.md) · [Türkçe](../tr/ENGINE.md) · [Українська](../uk/ENGINE.md) · [Tiếng Việt](../vi/ENGINE.md) · [中文](../zh/ENGINE.md)

---

# موتور VDLU (`update.sh`)

کلاینت به‌روزرسانیِ flashless و تدریجی برای ماژول‌های KSU/Magisk. چرخه‌ی `DIFF -> FETCH -> APPLY -> COMMIT` را به‌صورت یک
تراکنشِ ازسرگیری‌پذیر پیاده می‌کند. با `INTERFACES.md` (قانون همگرایی) تطبیق دارد.

sh خالصِ POSIX (mksh/busybox/toybox). **SLIM:** تنها به toybox (`sha256sum`/`gzip`/`base64`/`date`) + `ed25519-mini`
تعبیه‌شده (verify ed25519؛ **بدون openssl روی دستگاه**) + یک `curl` استاتیک که در نخستین به‌روزرسانی https **واکشی می‌شود**
(WebUI کارِ `fetch()` را انجام می‌دهد، آن را در Tier-2 ماندگار می‌کند، و `install-tool` پیش از استفاده امضا+هش آن را تایید
می‌کند) وابسته است. `file://` نیازی به curl ندارد. صفر وابستگی به `jq`.

## فراخوانی

```sh
VDLU_DIR=/data/adb/<mod>/vdlu MODULE_DIR=/data/adb/modules/<mod> MODID=<mod> \
  sh $MODULE_DIR/vdlu/update.sh <cmd>
```

`rc 0` = ok؛ `rc != 0` = خطا (دلیل روی stderr). `vdlu-verify` را مولفه‌ی دیگری تحویل می‌دهد (امضا در `INTERFACES.md §6`)؛
موتور تنها آن را صدا می‌زند.

| cmd | چه می‌کند |
|---|---|
| `check` | DIFF فقط‌خواندنی؛ `{"update":bool,"from":N,"to":M,"fetch":K,"reboot":bool}` را چاپ می‌کند؛ چیزی را تغییر نمی‌دهد |
| `run` | چرخه‌ی کاملِ LIVE + صحنه‌چینیِ REBOOT-hard؛ به `cancel` احترام می‌گذارد؛ پیشرفت در `journal.json` |
| `resume` | تراکنشِ معلق (`target.json`) را از فاز جاری ازسر می‌گیرد؛ ایدمپوتنت؛ `.so` را swap **نمی‌کند** |
| `boot` | حالت pre-zygote: resume **+** فایل‌های `staged/*.vdlu-new` را swap می‌کند → `PENDING_REBOOT`→`DONE` را می‌بندد. بدون تراکنشِ معلق، یک چرخه‌ی تازه اجرا می‌کند و همه‌چیز (ازجمله `.so`) را در یک boot اعمال می‌کند |
| `status` | `journal.json` را چاپ می‌کند (یا `{"state":"idle"}`) |
| `cancel` | `$VDLU_DIR/cancel` را می‌سازد؛ یک `run` در جریان در نخستین نقطه‌ی امن می‌ایستد |

## ماشین وضعیت (journal.json)

```
PLANNED -> FETCHING -> FETCHED -> APPLYING -> APPLIED_LIVE -> (PENDING_REBOOT | DONE)
```

`DONE` تنها زمانی که re-hash همه‌چیز مطابقت کند. اگر هر REBOOT-hardی صحنه‌چینی شده باشد ⇒ `PENDING_REBOOT` (هرگز یک `DONE`
ساختگی). `ERROR` در هر شکست، بدون خراب‌کردن ماژول (فایل‌های LIVEِ اعمال‌شده از `rollback/<v>/` بازگردانده می‌شوند؛ هیچ‌چیزِ
«نیمه‌اعمال‌شده که درباره‌اش دروغ بگوید»). خروجیِ خوش‌خیمِ فاز `fetch`: **`DEFERRED`** - دانلود توسط `net_policy` به‌تعویق
افتاد (شبکه مجاز نبود)؛ plan/target باقی می‌مانند و در check/boot بعدی ازسر گرفته می‌شود (WebUI یک toast اطلاعاتیِ آبی
«در انتظار شبکه‌ی X» نشان می‌دهد، نه یک خطا).

## تضمین‌های سخت‌گیری

- **FETCH:** توسط `net_policy` دروازه‌بانی می‌شود (any/wifi/mobile؛ فقط http/https، `file://` هرگز) - شبکه‌ی غیرمجاز ⇒
  `DEFERRED` (ازسرگیری‌پذیر)، بدون خرج داده. تنها آنچه را که کم است در `<sha>.part` دانلود می‌کند (curl با
  `--connect-timeout` + `--speed-time`، هرگز گیر نمی‌کند)، `gz` را از حالت فشرده خارج می‌کند (toybox `gunzip`)، بررسی می‌کند
  `sha256sum` == مانیفست، `mv` اتمی به `blobs/<sha>`. یک بلابِ کش‌شده+درست رد می‌شود. می‌تواند بلاب را از یک فایل محلیِ بدون
  تغییر بذر کند (dedup/آفلاین). **۳ شکست روی یک بلاب = فاز بدون اعمالِ چیزی abort می‌شود.** تنها زمانی `FETCHED` می‌شود که
  همه‌ی بلاب‌های planحاضر+تاییدشده باشند.
- **APPLY** (تنها از `FETCHED`): `live`/`soft` → پشتیبان به `rollback/<v>/` → `.vdlu-tmp` → `chmod` → verify →
  `rename` اتمی. `reboot` → در `staged/<path>.vdlu-new` تحقق می‌یابد (به inode زنده دست نمی‌زند).
  `delete[]` → پشتیبان → حذف. ایدمپوتنت (فایلی که پیشاپیش در هشِ هدف است رد می‌شود).
- **COMMIT:** re-hash هر `live`/`soft`؛ تنها آنگاه `current.json` را می‌نویسد. با فایل‌های صحنه‌چینی‌شده ⇒ `PENDING_REBOOT`.
  `boot` کارِ `mv -f staged/....vdlu-new $MODULE_DIR/<path>` را می‌کند (pre-zygote) + دوباره تایید می‌کند + `DONE`.
- **cancel:** میان فایل‌ها بررسی می‌شود (نقطه‌ی امن)؛ `.vdlu-tmp`/`.part`ِ در جریان را حذف می‌کند، `cancel` را پاک می‌کند،
  journal را ازسرگیری‌پذیر می‌گذارد (`cancelled:true`، `error:null`).
- **mkdir-lock `$VDLU_DIR/lock.d`** سریالی می‌کند (flock روی toybox غیرقابل‌استفاده است؛ بازیابیِ staleبا PID). تلاش مجددِ
  boot صبور، نه قفل را حین انتظار نگه می‌دارد (`acquire_lock_try`+release میان تلاش‌ها) و نه wakelock - ایمن برای باتری. یک
  crash/شبکه/reboot در میانه‌ی راه → `resume`/`boot` ادامه می‌دهد.
- **profile=hardened** ⇒ `vdlu-verify` روی مانیفست پیش از استفاده الزامی؛ شکست = abort؛ downgrade مسدود (نسخه‌ی یکنوا).
  **trusted** ⇒ verify تا حد امکان است، اما هشِ هر بلاب همیشه بررسی می‌شود.
- با وقار افت می‌کند: باینریِ گم‌شده / شبکه‌ی قطع / دیسکِ پر → یک خطای روشن روی stderr + `state:ERROR` در journal، بدون
  خراب‌کردن ماژول.

## تجزیه‌ی JSON بدون jq

یک مسطح‌کننده به‌سبکِ gron در `awk` (POSIX خالص: `substr`/`index`/`gsub`/`split`/`printf` + local‌هایی که به‌عنوان پارامتر
پاس می‌شوند) مانیفست را کاراکتربه‌کاراکتر توکن‌بندی می‌کند و برای هر برگِ اسکالر یک خط `path<TAB>value` می‌دهد
(`files/0/sha256<TAB>ab..`، `version<TAB>6`، `delete/0<TAB>etc/x`). در برابر JSONِ فشرده یا pretty-printed مقاوم است.
`sh` آن را با `grep`/`cut` مصرف می‌کند؛ planِ فایل‌به‌فایل در یک `awk` دومِ به TSV دوباره مونتاژ می‌شود
(`class st mode enc sha size path`) که به `$VDLU_DIR/plan.tsv` بدل می‌شود.

## فایل‌های وضعیت (در `$VDLU_DIR`، Tier-2)

| file | role |
|---|---|
| `config` | key=value (`source`/`profile`/`channel`/`net_policy`/`boot_retry_*`/…؛ نگاه کن به INTERFACES §5) |
| `current.json` | مانیفست نسخه‌ی ACTIVE (پایه‌ی diff)؛ غایب = هرگز به‌روز نشده |
| `target.json` | مانیفست پین‌شده‌ی تراکنشِ در جریان (حضور = تراکنش فعال)؛ در `DONE` به `current.json` بدل می‌شود |
| `plan.tsv` / `plan.del` | plan + پیشرفت فایل‌به‌فایل (st) / path‌هایی برای حذف |
| `journal.json` | پیشرفت برای WebUI (در هر گذار بازتولید می‌شود) |
| `blobs/<sha256>` | کش محتوای اصلیِ تاییدشده |
| `rollback/<version>/<path>` | پشتیبان فایل‌های بازنویسی‌شده (undo؛ ۳ تای آخر را نگه می‌دارد) |
| `staged/<path>.vdlu-new` | REBOOT-hard در انتظار swap هنگام boot |
| `lock.d/` | mkdir-lock (flock روی toybox غیرقابل‌استفاده؛ بازیابیِ staleبا PID) |
| `tools/<abi>/curl` | curlِ استاتیکِ واکشی‌شده (bootstrap سبک)؛ در طول به‌روزرسانی‌ها باقی می‌ماند |
| `cancel` | درخواست لغو |

<!-- doc-footer -->

---

> _این مستندات با Claude (Anthropic) تولید شده و توسط VD171 نگهداری می‌شود. اصلاحات و بهبودها خوش‌آمد است؛ به [CONTRIBUTING.md](CONTRIBUTING.md) مراجعه کنید._
