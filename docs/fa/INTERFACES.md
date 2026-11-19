> **Languages:** [English](../INTERFACES.md) · [العربية](../ar/INTERFACES.md) · [Čeština](../cs/INTERFACES.md) · [Deutsch](../de/INTERFACES.md) · [Español](../es/INTERFACES.md) · فارسی · [Français](../fr/INTERFACES.md) · [हिन्दी](../hi/INTERFACES.md) · [Bahasa Indonesia](../id/INTERFACES.md) · [Italiano](../it/INTERFACES.md) · [日本語](../ja/INTERFACES.md) · [한국어](../ko/INTERFACES.md) · [Nederlands](../nl/INTERFACES.md) · [Polski](../pl/INTERFACES.md) · [Português](../pt/INTERFACES.md) · [Русский](../ru/INTERFACES.md) · [Svenska](../sv/INTERFACES.md) · [ไทย](../th/INTERFACES.md) · [Türkçe](../tr/INTERFACES.md) · [Українська](../uk/INTERFACES.md) · [Tiếng Việt](../vi/INTERFACES.md) · [中文](../zh/INTERFACES.md)

---

# VDLU - قرارداد رابط (درز میان مولفه‌ها)

**قانون همگرایی:** هر مولفه با این فایل تطبیق می‌یابد. قطعه‌های برآمده از ۴ عامل باید **با هم جفت شوند** - امضاهای
CLI، نام فایل‌ها و کلیدهای JSON پایین **تغییرناپذیر** هستند (هر تغییری یعنی ابتدا همین‌جا هماهنگ کن).

اصول به‌ارث‌رسیده از مخزن‌ها: **sh خالصِ POSIX** روی دستگاه (بدون bashism؛ با toybox/busybox + `sha256sum`/`gzip`/`base64`
از toybox + `curl` واکشی‌شده + `ed25519-mini` تعبیه‌شده اجرا می‌شود - سبک، بدون بسته‌ی باینری)، **صفر کامنت بی‌مورد**،
**همیشه release**، **سخت‌گیری هنگام شکست** (تراکنش ازسرگیری‌پذیر، هیچ‌چیز به‌دروغ «تمام‌شده» نیست، هیچ‌چیز گم نمی‌شود)،
**هیچ‌چیز شل نشده**.

---

## ۱. چیدمان وضعیت (Tier-2، بیرون از دایرکتوری ماژول)

```
$VDLU_DIR = /data/adb/<module>/vdlu
  config               # key=value (§5)
  current.json         # manifest of the ACTIVE version (diff base); absent = never updated
  journal.json         # transaction in progress (§4); absent = idle
  cancel               # presence = cancel request (WebUI creates it; engine deletes it on stop)
  lock.d/              # mkdir-lock (flock unworkable on toybox; stale-recovery by PID)
  blobs/<sha256>       # cache of verified blobs (ORIGINAL content, already decompressed)
  rollback/<version>/<path>   # backup of overwritten files
  staged/<path>.vdlu-new      # REBOOT-hard awaiting swap at boot
  target.json          # PINNED manifest of the in-flight transaction (presence = active transaction; becomes current.json on DONE)
  plan.tsv  plan.del   # engine's internal plan (progress); the WebUI IGNORES it (reads only journal/config/current)
```
`cancelled:true` در journal = موتور بر اثر یک درخواست لغو ایستاد (یک وضعیت غیرپایانی و ازسرگیری‌پذیر؛ `error` null می‌ماند).

موتور vendor‌شده در ماژول: `$MODULE_DIR/vdlu/update.sh` (+ `vdlu-verify`). `$MODULE_DIR = /data/adb/modules/<module>`.
موتور از طریق env دریافت می‌کند: `VDLU_DIR`، `MODULE_DIR`، `MODID`.

## ۲. CLI موتور (مولفه‌ی ENGINE)

`sh update.sh <cmd>` - rc 0 = ok، !=0 = خطا (stderr دلیل را دارد):

| cmd | چه می‌کند |
|---|---|
| `check` | DIFF: مانیفست را دانلود می‌کند، مقایسه می‌کند؛ یک JSON تک‌خطی `{"update":bool,"from":N,"to":M,"fetch":K,"reboot":bool}` چاپ می‌کند؛ چیزی را تغییر نمی‌دهد. دستگاهِ جلوتر از feed (downgrade مسدود، سخت‌گیرانه) = یک وضعیت خوش‌خیم: `{"update":false,"ahead":true,"from":N,"to":M}` + rc0 (هرگز "check failed"). rc مربوط به do_diff: 2 fetch/parse، 3 verify/meta، 4 ahead |
| `run` | چرخه‌ی کامل: DIFF→FETCH→APPLY→COMMIT؛ به `cancel` احترام می‌گذارد؛ پیشرفت را در `journal.json` می‌نویسد؛ LIVE را اعمال می‌کند، REBOOT-hard را صحنه‌چینی می‌کند |
| `resume` | تراکنش `journal.json` را از فاز جاری ازسر می‌گیرد (ایدمپوتنت) |
| `boot` | حالت pre-zygote: `resume` + SWAP فایل‌های `staged/*.vdlu-new` را انجام می‌دهد (`.so` را اعمال می‌کند)، `PENDING_REBOOT`→`DONE` را می‌بندد |
| `status` | `journal.json` را چاپ می‌کند (یا `{"state":"idle"}`) |
| `cancel` | `$VDLU_DIR/cancel` را می‌سازد (یک `run` در جریان در نخستین نقطه‌ی امن می‌ایستد) |

منبع blob/مانیفست: `source` از config. `<source>` + `/manifest.json`، `/blobs/<sha>`، `/blobs/<sha>.gz`.
`source` با `https://` (curl استاتیکِ واکشی‌شده، TLS) یا `file://` (staging محلی) آغاز می‌شود.

## ۳. manifest.json (تولیدشده توسط PRODUCER، مصرف‌شده توسط ENGINE)

```json
{ "schema":1, "module":"<id>", "version":<int>, "version_name":"<str>", "built":"<ISO8601>",
  "engine_min":3, "key_id":"<str>", "channel":"stable",
  "files":[ {"path":"webroot/index.html","sha256":"<hex64>","size":<int>,"mode":"0644","enc":"raw|gz","class":"live|soft|reboot"} ],
  "delete":["<path>"], "sig":"<base64>" }
```

- `files[]` = درختِ هدفِ کامل. `class`: `live` (webroot/bin/lib/confs/scripts-on-demand/module.prop) ·
  `soft` (service.sh/post-fs-data.sh/boot-completed.sh) · `reboot` (`zygisk/**/*.so`، `system/**`، `*.rule`).
  پیش‌فرض بر پایه‌ی path؛ هرگز `reboot`→`live` را تنزل نمی‌دهد.
- `enc`: `gz` (gzip با `-9 -n`، قطعی؛ toybox gunzip روی دستگاه) تنها زمانی که خوب فشرده شود و اندازه قابل‌توجه باشد؛
  `sha256` همیشه از محتوای اصلی است.
- `sig`: امضای مانیفستِ canonical بدون فیلد `sig` (§4 از verify).

## ۴. journal.json (ENGINE می‌نویسد، WEBUI می‌خواند - قرارداد پیشرفت)

```json
{ "schema":1, "module":"<id>", "target":<version>, "from":<version>,
  "phase":"diff|fetch|apply|commit", "state":"PLANNED|FETCHING|FETCHED|APPLYING|APPLIED_LIVE|PENDING_REBOOT|DONE|ERROR|DEFERRED",
  "total":<int>, "done":<int>, "current":"<path>", "bytes":<int>, "reboot_pending":bool,
  "cancelled":bool, "error":"<str|null>", "updated":"<ISO8601>",
  "items":[ {"path":"<p>","sha256":"<h>","class":"<c>","st":"pending|fetched|applied|staged|skipped"} ] }
```

ماشین وضعیت (ترتیب ثابت): `PLANNED→FETCHING→FETCHED→APPLYING→APPLIED_LIVE→(PENDING_REBOOT|DONE)`.
`DONE` تنها زمانی که re-hash همه‌چیز مطابقت کند. یک REBOOT-hardِ صحنه‌چینی‌شده ⇒ `PENDING_REBOOT` (نه `DONE`).
خروجی‌های فاز `fetch`: `ERROR` (شکست سخت) یا `DEFERRED` (net_policy دانلود را مسدود کرد - خوش‌خیم/ازسرگیری‌پذیر، نه یک خطا).

## ۵. config (key=value، یکی در هر خط؛ قابل ویرایش در WEBUI)

```
auto_on_webui_open=0
auto_on_reboot=1
source=https://<user>.github.io/<repo>/<module>
channel=stable
profile=trusted        # trusted | hardened. CODE DEFAULT (line absent) = hardened (fail-closed, 9a9a824)
net_policy=any         # any (Wi-Fi+mobile) | wifi (Wi-Fi only) | mobile (mobile only) - gates the DOWNLOAD by network type
allow_metered=0        # ⚠️ SUPERSEDED by net_policy (not consumed by the engine)
pubkey_dir=keyring     # relative to $MODULE_DIR/vdlu (keyring of pubkeys for verify)
ca_path=               # empty = auto-detect of the Android trust store; set a path to override
tools_source=          # empty = derived from source (.../vdlu-tools); feed of the static curl
boot_retry_interval=30 # seconds between probes when BOOT finds the device offline (floor 5s)
boot_retry_minutes=0   # ceiling of the PATIENT retry (AWAKE-time) only at boot; 0 = off. Battery-safe (no wakelock,
                       # no held lock, route probe never wakes the radio) -> a generous ceiling is ~free
```

**تلاش مجدد هنگام boot (آفلاین) - صبور، ایمن برای باتری:** تنها در `boot` (هرگز در check/auto-open). اگر واکشی مانیفست
به‌خاطر شبکه شکست بخورد (`fetch_offline` بر پایه‌ی exit واکشی‌کننده دسته‌بندی می‌کند)، صبر می‌کند و تلاش را تکرار می‌کند تا
موفقیت یا تا پایانِ `boot_retry_minutes` از زمان بیداری (AWAKE). طراحی‌ای که **هیچ‌چیز را نگه نمی‌دارد و باتری را تخلیه نمی‌کند**:
- **صفر wakelock:** میان تلاش‌ها `sleep` است که در deep-sleep منجمد می‌شود → دستگاه به‌طور عادی می‌خوابد (~صفر باتری)؛
  تلاش مجدد مکث می‌کند و وقتی دستگاه پیشاپیش بیدار است ازسر گرفته می‌شود.
- **صفر قفلِ نگه‌داشته‌شده:** `acquire_lock_try`+release میان تلاش‌ها (قفل را حین انتظار نگه نمی‌دارد) → `run`/check دستی
  هرگز مسدود نمی‌شوند؛ اگر در این میان یک run دستی یک TARGET را صحنه‌چینی کند، boot کنار می‌کشد.
- **رادیو را بیهوده بیدار نمی‌کند:** یک probeی `net_allowed` (از طریق `net_type`/`ip route get`، یک جست‌وجوی مسیرِ هسته که
  policy-routing اندروید را رعایت می‌کند؛ بدون بسته) هر تلاش را دروازه‌بانی می‌کند - تنها وقتی شبکه ظاهر شد یک fetch خرج می‌کند.
- هرگز یک شکست قطعی (مانیفست/sig/downgrade) را تکرار نمی‌کند. `--connect-timeout 15` روی fetch (روی portalِ captive گیر نمی‌کند).
  `service.sh` آن را در پس‌زمینه می‌برد (boot هرگز گیر نمی‌کند).
- ⛔ **سخت: روشن‌کردن `boot_retry_minutes>0` موتورِ صبور را لازم دارد** (همان که `net_allowed`+`acquire_lock_try` دارد،
  canonical `da7115f4`+). تلاش مجدد boot پیشین (قفل را کل پنجره نگه می‌دارد + curlِ کورِ آفلاین را تکرار می‌کند) **باتری را تخلیه
  می‌کند/رادیو را بیدار می‌کند** - روشن‌کردن تلاش مجدد در موتور قدیمی یک footgun است. هنگام فعال‌سازی، موتور جاری را vendor کن.

**`net_policy` (any|wifi|mobile):** **دانلود** را بر پایه‌ی نوع شبکه دروازه‌بانی می‌کند. `net_type()` خروجیِ `ip route get` را
دسته‌بندی می‌کند (iface سلولی `rmnet/ccmni/v4-*/clat` = mobile؛ هر چیز دیگر = wifi؛ جست‌وجوی هسته، بدون بسته). `net_allowed()`
با `net_policy` مقایسه می‌کند و `do_fetch` (بلاب‌ها) + probeی تلاش مجدد boot صبور را دروازه‌بانی می‌کند. **چکِ مانیفست آزاد می‌ماند**
(ریز → UI روی هر شبکه‌ای یک به‌روزرسانی را گزارش می‌دهد)؛ تنها دانلود منتظر شبکه‌ی مجاز می‌ماند. دانلود روی شبکه‌ی غیرمجاز = وضعیت
**`DEFERRED`** در journal (نه ERROR؛ یک toast اطلاعاتیِ آبیِ ملایم «در انتظار شبکه‌ی X»؛ plan/target باقی می‌مانند، در
check/boot بعدی روی شبکه‌ی درست ازسر گرفته می‌شود). `net_policy` جایگزینِ `allow_metered` می‌شود (که هرگز مصرف نشد).
موتور `97baf887`+ (`file://` هرگز دروازه‌بانی نمی‌شود).

## ۶. امضا (PRODUCER روی PC با openssl امضا می‌کند؛ ENGINE روی دستگاه با ed25519-mini تایید می‌کند)

- Canonicalization: مانیفست بدون `sig`، کلیدها مرتب‌شده، JSON فشرده (بدون فاصله‌های زائد)، UTF-8.
  آنچه امضا/تایید می‌شود = `sha256` هگزِ آن شکل canonical (قطعیت بین‌ابزاری می‌دهد).
- `producer/vdlu-sign <manifest.json> <privkey.pem> <key_id>` → `key_id` + `sig` (base64 امضای ed25519 از sha256 canonical) را درجا به مانیفست تزریق می‌کند.
- `engine/vdlu-verify <manifest.json> <keyring_dir>` → rc 0 اگر `sig` با pubkeyِ `<key_id>.pub` در keyring مطابقت کند
  (SLIM: pubkey به‌صورت **RAW 32 بایت**). در داخل، بدون openssl: toybox `sha256sum`/`base64 -d` + باینریِ تعبیه‌شده‌ی
  `ed25519-mini` (CLI `ed25519-mini <pub32> <msg> <sig64>`، rc 0=معتبر/1=نامعتبر/2=usage).
  rc!=0 = رد. **`profile=hardened` ⇒ verify الزامی؛ شکست = abort.**
  `profile=trusted` ⇒ verify تا حد امکان است (منبع پیشاپیش از طریق SSH مورد اعتماد)، اما هشِ هر بلاب همیشه بررسی می‌شود.
- `producer/vdlu-keygen <id> <out>` → `<id>.pem` (priv) + `<id>.pub` (PEM، برای ابزارها روی PC) +
  `<id>.pub.raw` (**RAW 32B** = همان `<id>.pub` در keyring سبک روی دستگاه) را تولید می‌کند. openssl `genpkey -algorithm ed25519`.

## ۷. بلاب - تایید (ENGINE)

`<source>/blobs/<sha>` را دانلود می‌کند (یا `.gz` اگر `enc=gz`)، `.part` را می‌نویسد، اگر `gz` باشد از حالت فشرده خارج می‌کند
(`gunzip`)، بررسی می‌کند `sha256sum` == همان `sha256` مانیفست؛ مطابقت → `mv` اتمی به `$VDLU_DIR/blobs/<sha>`. ۳ شکست روی یک
بلاب = فاز را abort می‌کند (هیچ‌چیز اعمال نمی‌شود). بلابی که پیشاپیش در `$VDLU_DIR/blobs/<sha>` با هش درست هست = دانلود را رد می‌کند.

## ۸. APPLY بر پایه‌ی class (ENGINE)

- `live`/`soft`: پشتیبان `rollback/<v>/<path>` → `$MODULE_DIR/<path>.vdlu-tmp` را از بلاب می‌نویسد → `chmod mode` →
  `rename` اتمی روی هدف. پیشاپیش در هشِ هدف = skip. (در گونه‌ی Zygisk نوشتن به دایرکتوری mount‌شده می‌رود = ادغام فایل‌به‌فایل،
  هرگز `rm -rf` دایرکتوری.)
- `reboot`: در `$VDLU_DIR/staged/<path>.vdlu-new` تحقق می‌یابد (به نسخه‌ی زنده دست نمی‌زند). swap در `boot` است.
- `delete[]`: پشتیبان → حذف.

## ۹. WEBUI ↔ ENGINE (مولفه‌ی WEBUI)

- شلیک می‌کند: `ksu.exec("sh $MODULE_DIR/vdlu/update.sh run")` (پس‌زمینه).
- پیشرفت: یک poll سبک `ksu.exec("cat $VDLU_DIR/journal.json")` هر ~۱ ثانیه؛ `{phase,state,total,done,current,bytes}` را رندر می‌کند.
- زنده‌بودن: نبودِ journal برای ۸ تیک ⇒ «بدون پاسخ». journalِ منجمد (مقادیر یکسان) برای ۲۰ تیک ⇒ `lock.d` را بررسی می‌کند:
  زنده = ادامه می‌دهد (واکشی کُندِ ۱ بلاب)، مرده = خطا + Resume. بدون این، یک run که وسط fetch مرده باشد toast را روی «در حال به‌روزرسانی» منجمد می‌کرد.
- لغو: `ksu.exec("touch $VDLU_DIR/cancel")`.
- Config: `$VDLU_DIR/config` (key=value) را در یک زبانه‌ی "Updates" می‌خواند/می‌نویسد.
- Toast: نوار + `phase done/total · current`؛ در پایان با `reboot_pending` ⇒ یک بنرِ ماندگار «برای فعال‌سازی .so ری‌استارت کن».
- Auto-open (`auto_on_webui_open=1`): ابتدا یک `check()` بی‌صدا می‌کند (بدون toast پیشرفت)؛ تنها اگر `update && fetch>0` باشد
  `run`+toast ماندگار را شلیک می‌کند. به‌روز/جلوتر/چیز تازه‌ای نیست = یک نتیجه‌ی درون‌خطی در پنل، صفر toast باقی‌مانده. غیرمزاحم
  مانند دکمه‌ی دستی (toast تنها وقتی ظاهر می‌شود که دانلود واقعی باشد). bootstrap مربوط به curl یک‌بار است.

## ۱۰. ادغام در demo (مولفه‌ی INTEGRATION) - SNIPPETها، فایل‌های زنده را ویرایش نکن

در `integration/demo/`، snippetها + یک `INTEGRATION.md` تولید می‌کند که می‌گوید هرکدام کجا می‌رود (بدون اعمال):
- هوکِ `auto_on_reboot` در `post-fs-data`/`service.sh` (pre-zygote → `update.sh boot`) و `auto_on_webui_open`.
- پیش‌فرض‌های `config` + keyring تعبیه‌شده + vendor‌سازی (`modules/<mod>/vdlu/`).
- گونه‌ی PARTIAL (ادغام در دایرکتوری mount‌شده).

## ۱۱. زنجیره‌ابزارِ واکشی‌شده + baseline (SLIM، رویکرد B)

**چیدمان در ماژول (zip):** `vdlu/{update.sh, vdlu-verify, config.default, keyring/<id>.pub (RAW 32B),
verify/<abi>/ed25519-mini, baseline.json}`. **بدون** `bin/` (openssl/curl/zstd). `customize.sh` می‌تواند `verify/` را
تا ABI دستگاه هرس کند (`vdlu-verify` مینی را در `<dir>/ed25519-mini` یا `<dir>/verify/<abi>/ed25519-mini` پیدا می‌کند).

**ed25519-mini** (باینری تعبیه‌شده، تنها verify): `ed25519-mini <pubkey32> <msg> <sig64>` → rc 0=معتبر، 1=نامعتبر،
2=usage/IO. msg = همان بایت‌های امضاشده‌ی دقیق (دوباره هش نمی‌کند). TweetNaCl PD، استاتیک بر پایه‌ی ABI، PROVENANCE.

**tools-feed** (تنها پروفایل عمومی/https): در `<tools_source>` سرو می‌شود (پیش‌فرضِ مشتق‌شده: آخرین segment از `source` را
با `vdlu-tools` عوض می‌کند، مثلاً `https://<user>.github.io/<repo>/vdlu-tools`). شامل:
- `tools-manifest.json` - یک مانیفستِ امضاشده‌ی `vdlu-pack` روی درختِ `<abi>/curl`، که `sha256` هر curl را پین می‌کند (همان کلید `release-2026`).
- `<abi>/curl` - همان curlِ **استاتیکِ** خام (خودبسنده، ~۱MB؛ curl 8.11.1 + mbedTLS). 🪤 mbedTLS یک CA bundle حمل نمی‌کند:
  `fetch_url` با `--capath` (شناساییِ خودکارِ trust store اندروید: `/system/etc/security/cacerts` → APEX conscrypt؛
  `ca_path` بازنویسی می‌کند) عبور می‌دهد. بدون capath = خطای 60. یکپارچگی همان ed25519 است؛ بررسی گواهی defense-in-depth است.

**install-tool** (ENGINE): `update.sh install-tool <abi>` فایل `$VDLU_DIR/.work/{tools-manifest.json, tool.<abi>}` را می‌خواند
(WEBUI آن را از طریق `fetch()` دانلود و آنجا می‌نویسد)، **امضای tools-manifest را تایید می‌کند (ed25519-mini، در هر پروفایلی الزامی)**
+ هشِ curl == مانیفست، و تنها آنگاه آن را در `$VDLU_DIR/tools/<abi>/curl` (0755) نصب می‌کند. curl به‌عنوان root اجرا می‌شود →
sig+hash پیش از exec، RCE را می‌بندد. در Tier-2 باقی می‌ماند: هرگز دوباره دانلود نمی‌شود (جز هنگام حذف نصب).

**fetch-bootstrap** (WEBUI، `ensureToolchain()`): پیش از check/run/resume اجرا می‌شود. `file://` = no-op؛ curlِ از پیش
در دسترس (Tier-2، یا `module/bin/<abi>/curl` از یک ماژولِ **خود‌بسته‌بندی‌شده**، یا سیستم) = no-op (VDLU از curl موجود دوباره
استفاده می‌کند)؛ تنها `https` **بدون هیچ curlی** curl + tools-manifest را از طریق webview دانلود می‌کند، آن‌ها را در `.work`
می‌نویسد (base64 تکه‌تکه از طریق `ksu.exec`)، `install-tool` را صدا می‌زند. اعتماد = بررسی روی دستگاه، نه خودِ دانلود.

> 🪤 **Slim (fetch-bootstrap) ≠ الزامی.** ماژولی که `bin/` آن برای ویژگی‌های خودش وجود دارد (مثلاً restic/rclone/age/tar/curl…
> را بسته‌بندی می‌کند) **نه** به ~۲MB لاغر می‌شود و **نه** curl دانلود می‌کند - VDLU موتورِ slim را می‌پذیرد (gz، mini، baseline،
> fixes) و از زنجیره‌ابزار تعبیه‌شده **دوباره استفاده می‌کند**. تنها ماژول‌های بدون زنجیره‌ابزار خودشان ~۲MB می‌گیرند.

**baseline.json** (fix برای from:0): release نسخه‌ی امضاشده‌ی `manifest.json` نسخه‌ی عرضه‌شده را به `vdlu/baseline.json` کپی می‌کند؛
در نصب تازه موتور `current.json` را از آن بذر می‌کند (`init_paths`، تنها اگر غایب باشد) → دستگاه «به‌روز» متولد می‌شود، بدون
به‌روزرسانیِ خودکارِ خودش و بدون واکشیِ دوباره.

<!-- doc-footer -->

---

> _این مستندات با Claude (Anthropic) تولید شده و توسط VD171 نگهداری می‌شود. اصلاحات و بهبودها خوش‌آمد است؛ به [CONTRIBUTING.md](CONTRIBUTING.md) مراجعه کنید._
