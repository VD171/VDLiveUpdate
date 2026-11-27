> **Languages:** [English](../QUICKSTART.md) · [العربية](../ar/QUICKSTART.md) · [Čeština](../cs/QUICKSTART.md) · [Deutsch](../de/QUICKSTART.md) · [Español](../es/QUICKSTART.md) · فارسی · [Français](../fr/QUICKSTART.md) · [हिन्दी](../hi/QUICKSTART.md) · [Bahasa Indonesia](../id/QUICKSTART.md) · [Italiano](../it/QUICKSTART.md) · [日本語](../ja/QUICKSTART.md) · [한국어](../ko/QUICKSTART.md) · [Nederlands](../nl/QUICKSTART.md) · [Polski](../pl/QUICKSTART.md) · [Português](../pt/QUICKSTART.md) · [Русский](../ru/QUICKSTART.md) · [Svenska](../sv/QUICKSTART.md) · [ไทย](../th/QUICKSTART.md) · [Türkçe](../tr/QUICKSTART.md) · [Українська](../uk/QUICKSTART.md) · [Tiếng Việt](../vi/QUICKSTART.md) · [中文](../zh/QUICKSTART.md)

---

# quickstartِ پذیرشِ VDLU

یک چک‌لیستِ کپی-پیست برای vendorکردنِ **VDLiveUpdate** درونِ یک ماژول. VDLU خودش یک ماژول نیست:
در `<module>/vdlu/` انداخته می‌شود و درونِ zipِ ماژولِ تو عرضه می‌شود. برای rationaleِ کامل نگاه
کنید به [`INTERFACES.md`](INTERFACES.md) (قراردادِ درز)، [`ENGINE.md`](ENGINE.md)،
[`PRODUCER.md`](PRODUCER.md) و [`WEBUI.md`](WEBUI.md).

`<id>` را با idِ کلیدِ امضایت، `<abi>` را با ABI(هایی) که روی دستگاه عرضه می‌کنی
(`arm64-v8a`، `armeabi-v7a`، `x86_64`، `x86`)، و `<module>` را با درختِ ماژولت جایگزین کن.

## چیدمانِ هدف

این همان درختِ `vdlu/`ِ دقیقی است که ماژول پس از پذیرش حمل می‌کند:

```
<module>/
├── module.prop
├── post-fs-data.sh            # pre-zygote trigger: sh "$MODDIR/vdlu/update.sh" boot
├── webroot/
│   └── index.html             # your WebUI, wiring the Updates panel (step 5)
└── vdlu/
    ├── update.sh              # the engine (vendored byte-for-byte)
    ├── vdlu-verify            # ed25519 verify shim (device-side, no openssl)
    ├── verify/
    │   └── <abi>/ed25519-mini # per-ABI verifier binary
    ├── keyring/
    │   └── <id>.pub           # RAW 32-byte public key (NEVER the PEM)
    ├── config.default         # profile + source + automation defaults
    └── baseline.json          # install seed (unsigned, keyless)
```

وضعیتِ تغییرپذیرِ موتور (`config`، `current.json`، journal، lock) در Tier-2،
`/data/adb/<modid>/vdlu/`، بیرونِ دایرکتوریِ ماژول زندگی می‌کند؛ `config.default` در نخستین اجرا
آن را بذر می‌کند.

## ۱. vendorکردنِ موتور

موتور، verify shim و verifierِ per-ABI را درونِ `<module>/vdlu/` کپی کن:

```sh
mkdir -p <module>/vdlu/verify
cp engine/update.sh      <module>/vdlu/update.sh
cp engine/vdlu-verify    <module>/vdlu/vdlu-verify
cp -r verify/<abi>       <module>/vdlu/verify/<abi>      # ed25519-mini per ABI
```

تنها ABIهایی را که پشتیبانی می‌کنی عرضه کن؛ `customize.sh` می‌تواند `verify/` را هنگامِ نصب به
ABIِ دستگاه هرس کند.

## ۲. تولیدِ یک کلیدِ امضا (یک‌بار)

```sh
producer/vdlu-keygen <id> ./keys
```

این `<id>.pem` (خصوصی، آن را از هر دستگاه و از هر pushِ مخزن دور نگه دار)، `<id>.pub` (PEM، فقط
PC-side) و `<id>.pub.raw` (RAWِ ۳۲ بایتی، برای keyringِ دستگاه) را می‌دهد.

## ۳. تعبیه‌ی کلیدِ عمومیِ raw

keyringِ دستگاه کلیدِ **RAWِ ۳۲ بایتی** را نگه می‌دارد، هرگز PEM را (`ed25519-mini` نمی‌تواند یک
PEM را بخواند):

```sh
mkdir -p <module>/vdlu/keyring
cp ./keys/<id>.pub.raw <module>/vdlu/keyring/<id>.pub
```

keyring در طولِ release‌ها پایدار است (تنها چرخشِ کلید آن را تغییر می‌دهد): در یک re-vendor،
**تایید کن، بازنویسی نکن**.

## ۴. نوشتنِ config

`config.default` را در `<module>/vdlu/` عرضه کن (در نخستین اجرا `config`ِ Tier-2 را بذر می‌کند):

```
auto_on_reboot=1
auto_on_webui_open=1
source=https://<user>.github.io/<repo>/<module>
channel=stable
profile=hardened        # public feed: signature mandatory, downgrade blocked
net_policy=any
pubkey_dir=keyring
# apply_busy_file=/data/adb/<modid>/.busy   # OPT-IN: defer APPLY while this path exists (e.g. a running backup)
```

`profile=trusted` را تنها برای یک منبعِ خصوصیِ `file://`/SSH به کار ببر (verify best-effort؛
sha256ِ هر blob همچنان بررسی می‌شود). هر مقداری جز `trusted`ِ تحت‌اللفظی به‌عنوانِ `hardened`
تلقی می‌شود (fail-closed).

## ۵. سیم‌کشیِ triggerها

**هنگامِ reboot** (`auto_on_reboot`): موتور را pre-zygote از `post-fs-data.sh` صدا بزن تا
فایل‌های staged (یک `.so`، یک overlayِ `/system`، یک `sepolicy.rule`) بدونِ rebootِ اضافی swap
شوند:

```sh
# <module>/post-fs-data.sh
MODDIR=${0%/*}
sh "$MODDIR/vdlu/update.sh" boot
```

**هنگامِ بازشدنِ WebUI** (`auto_on_webui_open`): پنلِ drop-inِ Updates را در
`webroot/index.html`ِ خود سیم‌کشی کن:

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
  VDLU.onWebUIOpen();                                             // evaluates journal + banner + auto_on_webui_open
  VDLU.mountUpdatesPanel(document.getElementById('b-updates'));  // the "Updates" tab
</script>
```

(`vdlu.js` / `vdlu.css` از `webui/` vendor می‌شوند؛ یک ترجمه را می‌توان با
`i18n: window.VDLU_I18N_<LANG>` افزود.)

## ۶. امضای feed در workflowِ releaseِ خود

در هر release، درختِ نهاییِ ماژول را pack کن و مانیفست را امضا کن. کلیدِ خصوصی را روی ماشینِ
اپراتور نگه دار، هرگز در CI:

```sh
producer/vdlu-pack  <module>  ./out  <module> <versionCode> --version-name v<versionCode> --channel stable \
                    [--prev ./prev/manifest.json]        # delete[] = paths gone since prev
producer/vdlu-sign  ./out/manifest.json  ./keys/<id>.pem  <id>
# publish ./out/{manifest.json,blobs/} to <source>
```

## ۷. عرضه‌ی baseline

`baseline.json` را روی درختِ عرضه‌شده تولید کن و در `<module>/vdlu/baseline.json` قرار بده. در یک
نصبِ تازه `current.json` را بذر می‌کند تا دستگاه «به‌روز» متولد شود (بدونِ re-fetch). این یک **بذرِ
محلیِ موردِ اعتماد** است: بدون امضا و بدون کلید، پس CI می‌تواند آن را بدونِ هیچ‌گاه دست‌زدن به کلیدِ
امضا بسازد:

```sh
producer/vdlu-pack  <module>  ./seed  <module> <versionCode> --version-name v<versionCode>
cp ./seed/manifest.json <module>/vdlu/baseline.json
```

در صورتِ غیبت غیرمهلک است (دستگاه صرفاً در نخستین به‌روزرسانی از `0` آغاز می‌کند).

---

این کلِ پذیرش است. `sh -n <module>/vdlu/update.sh` باید pass شود؛ producer و موتور را همان‌طور که
در [`PRODUCER.md`](PRODUCER.md) و READMEِ ریشه نشان داده شده، پیش از عرضه سرتاسری تست کن.

<!-- doc-footer -->

---

> _این مستندات با Claude (Anthropic) تولید شده و توسط VD171 نگهداری می‌شود. اصلاحات و بهبودها خوش‌آمد است؛ به [CONTRIBUTING.md](CONTRIBUTING.md) مراجعه کنید._
