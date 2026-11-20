> **Languages:** [English](../PRODUCER.md) · [العربية](../ar/PRODUCER.md) · [Čeština](../cs/PRODUCER.md) · [Deutsch](../de/PRODUCER.md) · [Español](../es/PRODUCER.md) · فارسی · [Français](../fr/PRODUCER.md) · [हिन्दी](../hi/PRODUCER.md) · [Bahasa Indonesia](../id/PRODUCER.md) · [Italiano](../it/PRODUCER.md) · [日本語](../ja/PRODUCER.md) · [한국어](../ko/PRODUCER.md) · [Nederlands](../nl/PRODUCER.md) · [Polski](../pl/PRODUCER.md) · [Português](../pt/PRODUCER.md) · [Русский](../ru/PRODUCER.md) · [Svenska](../sv/PRODUCER.md) · [ไทย](../th/PRODUCER.md) · [Türkçe](../tr/PRODUCER.md) · [Українська](../uk/PRODUCER.md) · [Tiếng Việt](../vi/PRODUCER.md) · [中文](../zh/PRODUCER.md)

---

# لایه‌ی producer + امضای VDLU

تحویلِ محتوا-نشانی‌شده (مانیفست + بلاب‌ها) را برای یک ماژول می‌سازد و آن را امضا می‌کند.
با [`INTERFACES.md`](INTERFACES.md) §3/§6/§7 تطبیق دارد.

| tool | اجرا روی | زبان | کار |
|---|---|---|---|
| `producer/vdlu-pack` | PC / CI | python3 | پیمایش درختِ نهاییِ ماژول -> `manifest.json` + `blobs/` |
| `producer/vdlu-keygen` | PC | sh + openssl | جفت‌کلید ed25519 (`<id>.pem` priv، `<id>.pub` PEM، `<id>.pub.raw` RAW 32B برای keyring سبک) |
| `producer/vdlu-sign` | PC | sh + openssl | تزریق `key_id` + `sig` به یک مانیفست، درجا |
| `engine/vdlu-verify` | **دستگاه** | sh + ed25519-mini | تایید `sig` از طریق ed25519-mini تعبیه‌شده؛ keyring = pubkeyِ RAW 32B (بدون openssl روی دستگاه) |

## خط‌لوله

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

`vdlu-pack` محتوا-نشانی‌شده و زدایش‌گرِ تکرار است: بلابی که `<sha256>` آن پیشاپیش وجود دارد دوباره نوشته نمی‌شود، پس انتشار
تدریجی است و محتوای بدون‌تغییر / بازگشته هرگز دوباره push نمی‌شود.

### تصمیمِ `enc` (vdlu-pack)

`sha256` **همیشه** از محتوای اصلی (نافشرده) است؛ `enc` تنها نام می‌دهد که بلاب چگونه ذخیره می‌شود.

- `gz` وقتی `size >= 4096` **و** gzip (`-9 -n`، قطعی) دست‌کم ۱۰٪ صرفه‌جویی کند (`comp <= raw*0.90`).
- `raw` در غیر این صورت (متن کوچکی که gzipِ HTTP پیشاپیش پوشش می‌دهد، یا داده‌ی از پیش نافشرده‌شدنی).
- نبودِ gzip روی میزبانِ build -> همه‌چیز `raw` (هرگز شکست نمی‌خورد).

یک بلاب یک‌بار، در یک قالب ذخیره می‌شود: `blobs/<sha256>` (raw) یا `blobs/<sha256>.gz` (gz). دستگاه با toybox `gunzip`
(همیشه حاضر) از حالت فشرده خارج می‌کند، پس هیچ zstdی بسته‌بندی نمی‌شود.

### تصمیمِ `class` (vdlu-pack) - رده‌بندیِ reboot

از path مشتق می‌شود (INTERFACES §3، doc §4). تنها پیش‌فرض؛ یک قاعده‌ی path هرگز `reboot`->`live` را تنزل نمی‌دهد.

| class | شناسایی‌شده با | اعمال‌شده |
|---|---|---|
| `reboot` | `system/**`، `zygisk/**/*.so`، `*.rule` | صحنه‌چینی‌شده `.vdlu-new`، swap هنگام boot |
| `soft` | `service.sh` / `post-fs-data.sh` / `boot-completed.sh`ِ ریشه | به‌صورت زنده نوشته می‌شود، در boot بعدی اجرا می‌شود |
| `live` | هر چیز دیگر (webroot، bin، lib، confs، module.prop، ...) | به‌صورت زنده نوشته می‌شود، اتمی |

symlinkها **دنبال نمی‌شوند** (هرگز محتوایی را از بیرونِ درخت نشت نمی‌دهند، مثلاً یک لینک به `/etc/shadow`) و با یک هشدار رد
می‌شوند، چون شِمای مانیفست نوعِ symlink ندارد. فایل‌های غیرعادی (دایرکتوری‌ها، fifoها، deviceها) رد می‌شوند. `built` به
`SOURCE_DATE_EPOCH` احترام می‌گذارد تا مانیفست‌ها بازتولیدپذیر باشند.

### Baseline (بذرِ نصب) - بدون امضا، بدون کلید

`baseline.json` (که در `vdlu/baseline.json` درون zip ماژول عرضه می‌شود) در نصب تازه `current.json` را بذر می‌کند تا دستگاه
«به‌روز» متولد شود (بدون from:0، بدون واکشیِ دوباره). موتور آن را یک **بذرِ محلیِ موردِ اعتماد** تلقی می‌کند (در zipِ فلش‌شده
آمده است که مرز اعتمادِ نصب است) و **امضایش را تایید نمی‌کند** - تنها مانیفستِ واکشی‌شده از feed از `vdlu-verify` می‌گذرد.
پس baseline به **هیچ کلیدی** نیاز ندارد: فقط خروجیِ `vdlu-pack` روی درختِ عرضه‌شده است (بدون امضا؛ `sig`/`key_id` خالی
می‌مانند). بنابراین یک CI می‌تواند آن را **بدون کلید** تولید کند و کلیدِ امضا را ۱۰۰٪ بیرون از CI نگه دارد - تنها FEEDِ
منتشرشده امضا می‌شود (اپراتور، به‌صورت محلی). `vdlu-pack`، `baseline.json` را از مانیفستِ خودش کنار می‌گذارد (ضدِ خود-ارجاع).
در صورت غیبت غیرمهلک است: دستگاه صرفاً در نخستین به‌روزرسانی از from:0 آغاز می‌کند، هرگز خراب نمی‌شود.

## Canonicalization (نقطه‌ی همگرایی)

`vdlu-sign` و `engine/vdlu-verify` باید **همان بایت‌ها** را از یک مانیفست مشتق کنند، روی دو runtime متفاوت (openssl روی PC
در برابر toybox روی دستگاه). قاعده عمداً یک تبدیلِ بایتی است، نه یک سریال‌سازیِ دوباره‌ی JSON، پس روی دستگاه به هیچ
کتابخانه‌ی JSONی نیاز ندارد:

۱. `vdlu-pack`، `manifest.json` را **فشرده، کلیدها مرتب‌شده، UTF-8** می‌نویسد
   (`json.dumps(obj, sort_keys=True, separators=(",",":"), ensure_ascii=False)`)، و همیشه فیلدهای `key_id` و `sig`
   را می‌گنجاند (تا پیش از امضا، جای‌نگهدارِ رشته‌ی خالی). این همان شکلِ ذخیره‌ی canonical است.
۲. **شکلِ canonical = همان متن با فیلدِ `"sig"` حذف‌شده.** چون کلیدها مرتب‌اند، `sig` همیشه به‌صورت `,"sig":"<value>",` ظاهر
   می‌شود که میان `"schema"` (پیش) و `"version"` (پس) قاب گرفته، و هر دو همیشه حاضرند. حذف آن `...,"schema":N,"version":...`
   خوش‌فرم را برجا می‌گذارد. JSON هر `"` درون مقادیرِ رشته‌ای را به `\"` escape می‌کند، پس توکنِ ساختاریِ `"sig":"` حتی در
   برابر نام فایلی که به‌طور تحت‌اللفظی شاملِ `"sig":"` باشد بدون‌ابهام است (آزموده‌شده).
۳. پیامِ امضا/تاییدشده همان **sha256 هگز** (۶۴ کاراکتر ASCII، بدون newline) از شکلِ canonical است. ed25519 روی آن هگز
   (`openssl pkeyutl -sign/-verify -rawin`).

حذف در sh POSIX (تابعِ یکسان در هر دو ابزار، بدون `sed`/`jq`):

```sh
# $1 = full manifest text (trailing newline already stripped by $(cat ...))
_pre=${_c%%\"sig\":\"*}     # up to  ...,"schema":N,
_rest=${_c#*\"sig\":\"}      # after "sig":"
_tail=${_rest#*\",}          # after <value>",  ->  "version":...
printf '%s%s' "$_pre" "$_tail" | sha256sum | cut -d' ' -f1
```

`key_id` بخشی از شکلِ canonical است (تنها `sig` برداشته می‌شود)؛ `vdlu-sign`، `key_id` را **پیش از** هش‌کردن تنظیم می‌کند.
جای‌نگهدارِ مقدار، چه خالی (`"sig":""`، هنگام امضا) و چه پرشده (هنگام تایید)، بایت‌های canonical یکسان می‌دهد، پس امضا و تایید
بنا بر ساختار همخوان‌اند.

Python آن را به‌صورت `re.sub(r'"sig":"[^"]*",', '', text.rstrip("\\n"), count=1)` سپس sha256 بازتولید می‌کند - تنها برای
بررسیِ متقابل؛ تولیدکنندگانِ مرجع همان دو ابزارِ sh هستند.

## امضا (ed25519)

- `vdlu-keygen` (PC): `openssl genpkey -algorithm ed25519` (priv `0600`) + `openssl pkey -pubout` (pub به‌صورت **PEM**،
  برای امضا/openssl) + `openssl pkey -pubout -outform DER | tail -c 32` -> **`.pub.raw` (RAW 32B)** (DER SPKIِ ed25519
  یک پیشوندِ ۱۲ بایتی + کلیدِ ۳۲ بایتی است، پس `tail -c 32` خودِ کلید است). هر دو را می‌دهد.
- `vdlu-sign` (PC): `openssl pkeyutl -sign -rawin` روی sha256 هگزِ canonical؛ امضا به‌صورت base64 ذخیره می‌شود.
- `vdlu-verify` (**دستگاه، سبک**): `ed25519-mini <pubkey32> <msg> <sig64>` - keyring را به‌صورت pubkeyِ **RAW 32B**
  می‌خواند، بدون openssl روی دستگاه. `key_id` از نظر path پاک‌سازی می‌شود (بدون `/`، `.`، `..`، `"`). 🚨 keyring همان
  **`.pub.raw` (32B)** را عرضه می‌کند، هرگز `.pub` PEM (113B) را: PEM تنها PC-side است و `ed25519-mini` نمی‌تواند آن را
  بخواند.

مدلِ اعتماد (INTERFACES §6، doc §11/§13): `profile=hardened` (عمومی) verify را الزامی می‌کند - یک امضای شکست‌خورده یا غایب
به‌روزرسانی را abort می‌کند. `profile=trusted` (خصوصی، منبعِ staged از طریق SSH)، verify را تا حد امکان تلقی می‌کند، اما
sha256 هر بلاب به‌هرحال بررسی می‌شود.

## Keyring + چرخش

keyring یک دایرکتوری از فایل‌های `<key_id>.pub` است، هرکدام pubkeyِ ed25519 به‌صورت **RAW 32B** (از `.pub.raw`ِ `keygen`)،
نه PEM - `ed25519-mini`، ۳۲ بایتِ raw را می‌خواند. pubkeyِ raw جاری **و** پیشین را عرضه کن (doc §13) تا کلیدِ چرخیده
نصب‌های قدیمی را از کار نیندازد. `vdlu-sign` با `key_id`ِ تازه و دستگاهی که `<keyring>/<key_id>.pub` (raw) را برمی‌گزیند،
کلِ سازوکارِ چرخش است - بدون تغییر در موتور. keyring در طول release‌ها **پایدار** است (تنها چرخشِ کلید آن را تغییر می‌دهد):
یک re-vendor باید آن را **تایید-نه-کپی** کند و هرگز با `.pub` PEMِ سمتِ PC بازنویسی‌اش نکند.

**keyring‌های چندکلیدی باید کلیدِ ماژول را پین کنند.** موتور محدود می‌کند که کدام `key_id` می‌تواند یک MODULE-UPDATE را امضا کند، به فهرستِ مجازِ `key_id`ِ config (INTERFACES §5/§6)، که پیش از انتخابِ pubkey به‌صورتِ fail-closed بررسی می‌شود. keyringِ تک‌کلیدی به‌طورِ پیش‌فرض امن است (همان یک کلید پذیرفته می‌شود). اما ماژولی که keyringِ آن کلیدی با اعتمادِ پایین‌تر را نیز حمل می‌کند - مثلاً یک کلیدِ fingerprint-feed در کنارِ کلیدِ release - تا زمانی که `config`ِ آن کلیدِ ماژول را اعلام کند رد می‌شود، مثلاً `key_id=vd-2026` (برای چرخش با کاما جدا می‌شود، مثلاً `key_id=vd-2026,vd-2027`). این کار مانع از آن می‌شود که یک کلیدِ نشت‌یافته‌ی اعتمادِ پایین‌تر یک به‌روزرسانیِ flashless root را امضا کند.

`vdlu-pack` **keyring و باینری‌های `verify/` را از feed کنار می‌گذارد** (ریشه‌ی اعتماد تنها-فلش است، هرگز از طریق شبکه سرو نمی‌شود)، در کنارِ `baseline.json`، داربستِ نصب‌کننده (`META-INF/`، `customize.sh`)، دروازه‌ی فلشِ `.vd/`، `update.json`/`update-mmrl.json`ِ پرشده توسطِ CI، و همراهانِ `.sha256`ِ هر فایل. تنها محتوای خودِ ماژول از feed به‌روزرسانی‌پذیر است، پس یک مانیفست هرگز نمی‌تواند لنگرِ اعتمادِ روی دستگاه را بازنویسی کند.

<!-- doc-footer -->

---

> _این مستندات با Claude (Anthropic) تولید شده و توسط VD171 نگهداری می‌شود. اصلاحات و بهبودها خوش‌آمد است؛ به [CONTRIBUTING.md](CONTRIBUTING.md) مراجعه کنید._
