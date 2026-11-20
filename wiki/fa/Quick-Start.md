# Quick Start

این فهرست بررسی اتخاذ است: چگونه **VDLiveUpdate (VDLU)** را در یک
ماژول KernelSU / APatch / Magisk جاسازی کنید. VDLU خودش یک ماژول نیست. در
`<module>/vdlu/` قرار می‌گیرد و درون زیپ ماژول شما عرضه می‌شود، تا یک ماژول نصب‌شده بتواند
خود را بدون فلش از یک feed امضاشده که شما منتشر می‌کنید به‌روز کند.

در سراسر، `<id>` را با id کلید امضای خود، `<abi>` را با
ABIهای دستگاهی که عرضه می‌کنید (`arm64-v8a`، `armeabi-v7a`، `x86_64`، `x86`)، و `<module>`
را با درخت ماژول خود جایگزین کنید.

برای منطق پشت هر قطعه، ببینید [[Engine]]، [[Producer]]، [[WebUI]] و
[[Security and Trust Model]].

## چیدمان `vdlu/` درون‌ماژول

این دقیقاً درختی است که ماژول شما پس از اتخاذ حمل می‌کند:

```
<module>/
|-- module.prop
|-- post-fs-data.sh            # pre-zygote trigger: sh "$MODDIR/vdlu/update.sh" boot
|-- webroot/
|   `-- index.html             # your WebUI, wiring the Updates panel (step 5)
`-- vdlu/
    |-- update.sh              # the engine (vendored byte-for-byte)
    |-- vdlu-verify            # ed25519 verify shim (device-side, no openssl)
    |-- verify/
    |   `-- <abi>/ed25519-mini # per-ABI verifier binary
    |-- keyring/
    |   `-- <id>.pub           # RAW 32-byte public key (NEVER the PEM)
    |-- config.default         # profile + source + automation defaults
    `-- baseline.json          # install seed (unsigned, keyless)
```

وضعیت قابل‌تغییر موتور (`config`، `current.json`، ژورنال، قفل، کش blob)
در Tier-2 در `/data/adb/<modid>/vdlu/`، بیرون از دایرکتوری ماژول، زندگی می‌کند.
`config.default` در اولین اجرا آن `config` مربوط به Tier-2 را بذر می‌دهد. برای
چیدمان کامل وضعیت ببینید [[Engine]].

## ۱. جاسازی موتور

موتور، شیم تأیید و باینری تأیید‌کننده به‌ازای هر ABI را در
`<module>/vdlu/` کپی کنید:

```sh
mkdir -p <module>/vdlu/verify
cp engine/update.sh   <module>/vdlu/update.sh
cp engine/vdlu-verify <module>/vdlu/vdlu-verify
cp -r verify/<abi>    <module>/vdlu/verify/<abi>    # ed25519-mini per ABI
```

فقط ABIهایی را که پشتیبانی می‌کنید عرضه کنید. `customize.sh` شما می‌تواند `verify/` را در زمان
نصب تا ABI دستگاه هرس کند.

## ۲. تولید یک کلید امضا (یک‌باره)

```sh
producer/vdlu-keygen <id> ./keys
```

این سه فایل تولید می‌کند:

- `<id>.pem` - کلید خصوصی. آن را از هر دستگاه و از هر push مخزن
  یا راز CI دور نگه دارید.
- `<id>.pub` - کلید عمومی PEM. فقط سمت PC (توسط `vdlu-sign` استفاده می‌شود).
- `<id>.pub.raw` - کلید عمومی ۳۲-بایتی خام، برای keyring دستگاه.

برای اینکه چرا این تقسیم‌بندی مهم است ببینید [[Security and Trust Model]].

## ۳. جاسازی کلید عمومی خام

keyring دستگاه کلید **۳۲-بایتی خام** را نگه می‌دارد، هرگز PEM را. `ed25519-mini`
نمی‌تواند یک PEM را بخواند، بنابراین کپی‌کردن PEM اینجا تأیید روی دستگاه را می‌شکند:

```sh
mkdir -p <module>/vdlu/keyring
cp ./keys/<id>.pub.raw <module>/vdlu/keyring/<id>.pub
```

keyring در میان نسخه‌ها پایدار است: فقط در یک چرخش کلید تغییر می‌کند. در یک
دوباره‌جاسازی، **آن را تأیید کنید، بازنویسی نکنید**.

## ۴. نوشتن config

`config.default` را در `<module>/vdlu/` عرضه کنید. در اولین اجرا `config` مربوط به Tier-2 را
بذر می‌دهد:

```
auto_on_reboot=1
auto_on_webui_open=1
source=https://<user>.github.io/<repo>/<module>
channel=stable
profile=hardened        # public feed: signature mandatory, downgrade blocked
net_policy=any
pubkey_dir=keyring
```

`profile=trusted` را فقط برای یک منبع خصوصی `file://` یا SSH استفاده کنید (تأیید آنجا
بهترین-تلاش است، اما sha256 هر blob همچنان بررسی می‌شود). هر مقداری جز
`trusted` واقعی به‌عنوان `hardened`، به‌صورت fail-closed، تلقی می‌شود. برای
معنای کامل پروفایل‌ها ببینید [[Security and Trust Model]].

## ۵. سیم‌کشی محرک‌ها

**در ریبوت** (`auto_on_reboot`): موتور را پیش از zygote از
`post-fs-data.sh` فرا بخوانید، تا فایل‌های کلاس reboot مرحله‌بندی‌شده (یک `.so`، یک overlay مربوط به `/system`،
یک `sepolicy.rule`) بدون یک ریبوت اضافی جابه‌جا شوند:

```sh
# <module>/post-fs-data.sh
MODDIR=${0%/*}
sh "$MODDIR/vdlu/update.sh" boot
```

**در باز‌شدن WebUI** (`auto_on_webui_open`): پنل Updates آماده‌جاگذاری را در
`webroot/index.html` خود سیم‌کشی کنید:

```html
<link rel="stylesheet" href="vdlu.css">
<script src="vdlu.js"></script>
<script>
  VDLU.init({
    moduleDir: '/data/adb/modules/' + MODID,
    vdluDir:   '/data/adb/' + MODID + '/vdlu',
    modid:     MODID,
    module:    'YourModule'
  });
  VDLU.onWebUIOpen();                                            // journal + banner + auto_on_webui_open
  VDLU.mountUpdatesPanel(document.getElementById('b-updates'));  // the "Updates" tab
</script>
```

`vdlu.js` و `vdlu.css` از `webui/` جاسازی می‌شوند. یک ترجمه را می‌توان
با `i18n: window.VDLU_I18N_<LANG>` افزود. برای قرارداد پنل ببینید [[WebUI]].

## ۶. امضای feed در جریان انتشار خود

در هر نسخه، درخت نهایی ماژول را بسته‌بندی و مانیفست را امضا کنید. کلید خصوصی را
روی ماشین اپراتور نگه دارید، هرگز در CI:

```sh
producer/vdlu-pack  <module>  ./out  <module> <versionCode> \
                    --version-name v<versionCode> --channel stable \
                    [--prev ./prev/manifest.json]      # delete[] = paths gone since prev
producer/vdlu-sign  ./out/manifest.json  ./keys/<id>.pem  <id>
# publish ./out/{manifest.json,blobs/} to <source>
```

`vdlu-pack` آدرس‌دهی‌شده بر اساس محتوا و حذف‌کننده تکرار است، بنابراین انتشار افزایشی است:
blobهای بدون تغییر هرگز دوباره ارسال نمی‌شوند. ببینید [[Producer]] و [[Feed Format]].

## ۷. عرضه baseline

`baseline.json` را روی درخت عرضه‌شده تولید کنید و آن را در
`<module>/vdlu/baseline.json` قرار دهید. در یک نصب تازه `current.json` را بذر می‌دهد، تا
دستگاه «به‌روز» متولد شود و نسخه عرضه‌شده خودش را دوباره دریافت نکند. این یک
**بذر محلی قابل‌اعتماد** است: امضانشده و بدون‌کلید، تا CI بتواند آن را بدون آنکه هرگز
به کلید امضا دست بزند بسازد:

```sh
producer/vdlu-pack  <module>  ./seed  <module> <versionCode> --version-name v<versionCode>
cp ./seed/manifest.json <module>/vdlu/baseline.json
```

اگر غایب باشد غیرکشنده است: دستگاه به‌سادگی در اولین به‌روزرسانی از نسخه `0`
شروع می‌کند.

---

این کل اتخاذ است. پیش از عرضه، `sh -n <module>/vdlu/update.sh`
باید بگذرد، و باید تولیدکننده و موتور را سر تا ته آزمایش کنید همان‌طور که در
[[Contributing]] و [[Producer]] نشان داده شده.
