<!--
  ======================================================================
   VDLiveUpdate (VDLU)  ::  flashless, incremental module updates
   A self-update engine for KernelSU/APatch/Magisk modules: fetch only the
   files that changed, apply the live ones with no reboot, verified by ed25519.

   Copyright (C) 2026  VD171
   SPDX-License-Identifier: Apache-2.0

   Licensed under the Apache License, Version 2.0; you may obtain a copy at
   http://www.apache.org/licenses/LICENSE-2.0

   Site           : https://vd171.ru
   Site           : https://vd.priv8.ru
   Source         : https://github.com/VD171/VDLiveUpdate
   GitHub         : @VD171 https://github.com/VD171
   XDA-Developers : @VD171 https://xdaforums.com/m/vd171.4699873/
   Telegram       : @VD_Priv8 https://t.me/VD_Priv8
   Channel        : @Priv8_VD https://t.me/Priv8_VD
   Discord        : @VD.Priv8 https://discord.com/users/1296831918989639721
   E-mail         : vd.priv8@pm.me
  ======================================================================
-->

# VDLiveUpdate

> **Languages:** [English](README.md) · [العربية](README.ar.md) · [Čeština](README.cs.md) · [Deutsch](README.de.md) · [Español](README.es.md) · [فارسی](README.fa.md) · [Français](README.fr.md) · [हिन्दी](README.hi.md) · [Bahasa Indonesia](README.id.md) · [Italiano](README.it.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Nederlands](README.nl.md) · [Polski](README.pl.md) · [Português](README.pt.md) · [Русский](README.ru.md) · [Svenska](README.sv.md) · [ไทย](README.th.md) · [Türkçe](README.tr.md) · [Українська](README.uk.md) · [Tiếng Việt](README.vi.md) · [中文](README.zh.md)

**VDLU** یک موتور خودبه‌روزرسانی افزایشی و بدون فلش برای ماژول‌های **KernelSU / APatch / Magisk** است. یک ماژول نصب‌شده خودش را با گرفتن **فقط فایل‌هایی که تغییر کرده‌اند** (بلاب‌های آدرس‌دهی‌شده بر پایهٔ محتوا + یک مانیفست امضاشده) به‌روز می‌کند، آن‌هایی را که می‌تواند **بدون راه‌اندازی مجدد** به‌صورت زنده اعمال می‌کند، و آن چند موردی را که واقعاً به راه‌اندازی مجدد نیاز دارند (یک `.so`، یک پوشانندهٔ `/system`، یک `sepolicy.rule`) آماده و نشانه‌گذاری می‌کند. بدون مدیر روت، بدون دانلود دوبارهٔ کل `.zip`، و بدون راه‌اندازی مجدد جز برای همان فایل‌های آماده‌شده.

این ابزار طوری طراحی شده که درون یک ماژول **وندور (vendored)** شود (در `<module>/vdlu/` قرار بگیرد)، نه اینکه خودش به‌عنوان یک ماژول اجرا شود.

## چرا

یک به‌روزرسانی عادی ماژول کل `.zip` را دوباره می‌فرستد. برای یک ماژول بزرگ این یعنی یک دانلود مجدد حجیم برای چند خط تغییرکرده، و یک مانیفست به‌روزرسانی ایستا تنها می‌تواند به یک `zipUrl` اشاره کند، پس نمی‌تواند همان طعمی (ABI، کامل در برابر lite) را که دستگاه واقعاً دارد ارائه دهد. VDLU درخت **نصب‌شده** را با یک feed امضاشده مقایسه می‌کند و تنها دلتاها را می‌گیرد، پس یک نصب arm64-full همان arm64-full می‌ماند، یک نصب lite همان lite می‌ماند، و بیشتر به‌روزرسانی‌ها به‌صورت زنده اعمال می‌شوند.

## چگونه کار می‌کند

- **تولیدکننده (PC / انتشار):** `vdlu-pack` یک درخت ماژول را به یک feed آدرس‌دهی‌شده بر پایهٔ محتوا تبدیل می‌کند (`manifest.json` + `blobs/<sha256>`، gzip، حذف تکرار، `delete[]`)؛ `vdlu-keygen` / `vdlu-sign` (ed25519)؛ `vdlu-gc` بلاب‌های یتیم را با ارجاع به N مانیفست آخر هرس می‌کند (fail-safe، به‌طور پیش‌فرض dry-run).
- **موتور (دستگاه):** POSIX sh، بدون `jq`. `update.sh` (`check | run | resume | boot | status | cancel`) مراحل DIFF -> FETCH -> APPLY -> COMMIT را به‌صورت یک **تراکنش ازسرگرفتنی** (journal) اجرا می‌کند، همراه با rollback و یک قفل مبتنی بر `mkdir`. امضا توسط `ed25519-mini` تعبیه‌شده راستی‌آزمایی می‌شود (بدون `openssl` روی دستگاه).
- **WebUI:** یک پنل Updates آمادهٔ استفاده (toast پیشرفت، لغو، بنر راه‌اندازی مجدد)، با JS خالص.

## پروفایل‌ها

- `trusted`: استفادهٔ خصوصی، منبع `file://` یا SSH، راستی‌آزمایی best-effort (هش همیشه).
- `hardened`: استفادهٔ عمومی، **امضا الزامی**، downgrade مسدود. مانیفست **به شناسهٔ ماژول گره خورده** است، و پیش از دانلود هر چیزی هر فیلد به‌صورت fail-closed اعتبارسنجی می‌شود.

## در ماژول خود به‌کارش بگیرید

`engine/update.sh` + `vdlu-verify` + `verify/<abi>/ed25519-mini` را در `<module>/vdlu/` وندور کنید، **کلید عمومی خام ۳۲ بایتی** خود را به‌عنوان `vdlu/keyring/<id>.pub` جاسازی کنید، یک `config` (پروفایل + منبع) بیفزایید، تریگرها را سیم‌کشی کنید (`post-fs-data.sh` پیش از zygote برای خودبه‌روزرسانی هنگام بوت؛ یک تریگر باز شدن WebUI)، و `vdlu-pack` + `vdlu-sign` را به فرایند انتشار خود اضافه کنید. برای یک قالب کامل به [`docs/QUICKSTART.md`](docs/QUICKSTART.md) مراجعه کنید.

## امنیت

- **هر فیلد مانیفست یک ورودی خصمانه است.** `validate_plan()` در صورت وجود یک مسیر مطلق یا دارای `..`، یک `sha256` که ۶۴ کاراکتر هگز نباشد، یا یک mode / class / encoding نامعتبر، کل مانیفست را به‌صورت fail-closed **پیش از** هر fetch یا apply رد می‌کند.
- **کلید خصوصی امضا هرگز به CI یا دستگاه نمی‌رسد**؛ تنها کلید عمومی خام تعبیه می‌شود، و راستی‌آزمایی از `ed25519-mini` استفاده می‌کند، نه `openssl`.
- `hardened` با وارونگی fail-closed است: هر چیزی جز رشتهٔ تحت‌اللفظی `trusted` به‌عنوان `hardened` در نظر گرفته می‌شود، پس یک مقدار پروفایلِ خراب هرگز نمی‌تواند بی‌صدا یک مانیفست امضانشده را بپذیرد.
- فایل‌های ردهٔ راه‌اندازی مجدد (`.so`، پوشانندهٔ `/system`، `sepolicy.rule`) **آماده می‌شوند و هرگز روی یک inode زنده نوشته نمی‌شوند**؛ هر چیز دیگری به‌صورت زنده اعمال می‌شود. یک apply ناموفق به‌جای بازنویسی بدون پشتیبان، متوقف می‌شود.

## ساخت / آزمون

اینها اسکریپت‌اند، چیزی برای کامپایل نیست. سرتاسری (تولیدکننده + موتور با هم):

```sh
producer/vdlu-keygen demo /tmp/k
producer/vdlu-pack /tmp/tree /tmp/feed demo 1 --version-name v1
producer/vdlu-sign /tmp/feed/manifest.json /tmp/k/demo.pem demo
VDLU_DIR=... MODULE_DIR=... MODID=demo sh engine/update.sh check   # then run / boot
```

`sh -n engine/*.sh`، `node --check webui/vdlu.js`، و `webui/demo.html` را در یک مرورگر باز کنید (پل دستگاه را شبیه‌سازی می‌کند).

## مستندات

- [`INTERFACES.md`](docs/INTERFACES.md): قرارداد درز میان مؤلفه‌ها (قانون هم‌گرایی؛ آن را تغییرناپذیر در نظر بگیرید).
- [`ENGINE.md`](docs/ENGINE.md): موتور سمت دستگاه (`update.sh`): تراکنش قابل‌ازسرگیری DIFF -> FETCH -> APPLY -> COMMIT.
- [`PRODUCER.md`](docs/PRODUCER.md): سمت رایانه/انتشار: ساخت و امضای فید نشانی‌دهی‌شده با محتوا (`vdlu-pack`، `vdlu-sign`).
- [`WEBUI.md`](docs/WEBUI.md): ویجت آمادهٔ پنل به‌روزرسانی‌ها (نوتیف پیشرفت، لغو، نوار راه‌اندازی مجدد).
- [`docs/QUICKSTART.md`](docs/QUICKSTART.md): یک راهنمای به‌کارگیری گام‌به‌گام و قطعه‌های سیم‌کشی.

## همچنین ببینید

- **[COPG-VD](https://github.com/VD171/COPG-VD)**: جعل fingerprint سراسری دستگاه / Play Integrity، در کل دستگاه با دامنه‌ی هر برنامه و یک WebUI.
- **[VDBackup](https://github.com/VD171/VD-Backup)**: پشتیبان‌گیری و بازیابی کامل اپ و داده به‌صورت روت، که به‌طور کامل از یک WebUI رانده می‌شود.
- **[VD-dropbear](https://github.com/VD171/VD-dropbear)**: یک سرویس SSH مستقل با دسترسی روت (Dropbear).
- **[VDGoogle](https://github.com/VD171/VD-Google)**: سرویس‌های Google شما (RCS، Wallet، گواهی‌های Play Integrity)، روی دستگاهتان و بدون اینترنت خوانده می‌شوند.
- **[VDInstaller](https://github.com/VD171/VD-Installer)**: یک نصب‌کنندهٔ ساید‌لود روت‌شدهٔ بدون‌اصطکاک برای APKهای تکی، دسته‌ای و تقسیم‌شده، همراه با کلید تأییدکنندهٔ Play Protect و جعل منبع نصب.
- **[VDInfos](https://github.com/VD171/VD-Infos)**: یک اشکال‌زدای روش‌های دستگاه: هر مورد را از طریق هر روشی که می‌تواند آن را بخواند می‌خواند و آن‌ها را کنار هم مقایسه می‌کند.
- **[VD-Modules](https://github.com/VD171/VD-Modules)**: مخزن ماژول‌های ما برای MMRL/WebUI-X (همه‌ی این‌ها را از مدیر root خود نصب کنید).
- **[@VictorGabriel7Dev/build.prop](https://github.com/VictorGabriel7Dev/build.prop)**: یک مجموعه‌داده از fingerprintهای `build.prop` پیکسل (fork از @T3SL4).
- **[@VictorGabriel7Dev/mtproto-store](https://github.com/VictorGabriel7Dev/mtproto-store)**: از Telegram به‌عنوان یک object store از طریق یک CLI کوچک Go استفاده کنید.

## تماس‌ها

- https://vd171.ru
- https://vd.priv8.ru
- **Telegram:** @VD_Priv8 https://t.me/VD_Priv8
- **Channel:** @Priv8_VD https://t.me/Priv8_VD
- **Discord:** @VD.Priv8 https://discord.com/users/1296831918989639721
- **E-mail:** vd.priv8@pm.me
- **XDA-Developers:** @VD171 https://xdaforums.com/m/vd171.4699873/
- **GitHub:** @VD171 https://github.com/VD171

## مجوز

کد خودِ VDLiveUpdate تحت **Apache-2.0** است؛ به [LICENSE](LICENSE) مراجعه کنید. این ابزار یک راستی‌آزمای کوچک
`ed25519-mini` و یک `curl` ایستا را برای بوت‌استرپ دانلود وندور می‌کند، هر کدام تحت مجوز خودش؛ به
[NOTICE.md](NOTICE.md) و فایل‌های `PROVENANCE.json` کنار باینری‌های همراه مراجعه کنید.

## نشان‌های تجاری

VDLiveUpdate یک پروژهٔ مستقل و غیررسمی است که به هیچ شخص ثالثی وابسته نیست و از سوی آن تأیید نشده است.
«Android» یک نشان تجاری Google LLC است؛ «KernelSU»، «Magisk» و «APatch» نشان‌های نویسندگان مربوط به خودشان
هستند. VDLU به‌طور کامل روی دستگاه شما و روی هاست انتشار خودتان اجرا می‌شود.

## Tags

`VDLU` `flashless-update` `incremental-update` `KernelSU` `Magisk` `APatch` `module-update` `ed25519` `content-addressed` `OTA` `self-update` `Android` `VDLiveUpdate`

---

📣 **Join the channel for updates:** @Priv8_VD https://t.me/Priv8_VD
