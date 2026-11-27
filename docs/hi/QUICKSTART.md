> **Languages:** [English](../QUICKSTART.md) · [العربية](../ar/QUICKSTART.md) · [Čeština](../cs/QUICKSTART.md) · [Deutsch](../de/QUICKSTART.md) · [Español](../es/QUICKSTART.md) · [فارسی](../fa/QUICKSTART.md) · [Français](../fr/QUICKSTART.md) · हिन्दी · [Bahasa Indonesia](../id/QUICKSTART.md) · [Italiano](../it/QUICKSTART.md) · [日本語](../ja/QUICKSTART.md) · [한국어](../ko/QUICKSTART.md) · [Nederlands](../nl/QUICKSTART.md) · [Polski](../pl/QUICKSTART.md) · [Português](../pt/QUICKSTART.md) · [Русский](../ru/QUICKSTART.md) · [Svenska](../sv/QUICKSTART.md) · [ไทย](../th/QUICKSTART.md) · [Türkçe](../tr/QUICKSTART.md) · [Українська](../uk/QUICKSTART.md) · [Tiếng Việt](../vi/QUICKSTART.md) · [中文](../zh/QUICKSTART.md)

---

# VDLU अपनाने की quickstart

एक मॉड्यूल में **VDLiveUpdate** को vendor करने के लिए एक copy-paste चेकलिस्ट। VDLU स्वयं एक मॉड्यूल नहीं
है: इसे `<module>/vdlu/` में रखा जाता है और यह आपके मॉड्यूल की zip के अंदर भेजा जाता है। पूर्ण औचित्य के लिए
[`INTERFACES.md`](INTERFACES.md) (सीवन अनुबंध), [`ENGINE.md`](ENGINE.md), [`PRODUCER.md`](PRODUCER.md) और
[`WEBUI.md`](WEBUI.md) देखें।

`<id>` को अपनी signing-key id से, `<abi>` को उन डिवाइस ABI(s) से जिन्हें आप भेजते हैं (`arm64-v8a`,
`armeabi-v7a`, `x86_64`, `x86`), और `<module>` को अपने मॉड्यूल वृक्ष से बदलें।

## लक्ष्य लेआउट

अपनाने के बाद मॉड्यूल जो सटीक `vdlu/` वृक्ष ले जाता है वह यह है:

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

engine की परिवर्तनीय state (`config`, `current.json`, journal, lock) Tier-2 में रहती है,
`/data/adb/<modid>/vdlu/`, मॉड्यूल dir के बाहर, `config.default` पहले run पर इसे seed करता है।

## 1. engine को vendor करें

engine, verify shim और per-ABI verifier को `<module>/vdlu/` में कॉपी करें:

```sh
mkdir -p <module>/vdlu/verify
cp engine/update.sh      <module>/vdlu/update.sh
cp engine/vdlu-verify    <module>/vdlu/vdlu-verify
cp -r verify/<abi>       <module>/vdlu/verify/<abi>      # ed25519-mini per ABI
```

केवल उन ABIs को भेजें जिनका आप समर्थन करते हैं, `customize.sh` इंस्टॉल समय पर `verify/` को डिवाइस के ABI तक
prune कर सकता है।

## 2. एक signing key उत्पन्न करें (एक-बार)

```sh
producer/vdlu-keygen <id> ./keys
```

यह `<id>.pem` (private, इसे हर डिवाइस से और किसी भी repo push से दूर रखें), `<id>.pub` (PEM, केवल PC-side) और
`<id>.pub.raw` (RAW 32 बाइट्स, डिवाइस keyring के लिए) उत्सर्जित करता है।

## 3. raw public key को embed करें

डिवाइस keyring **RAW 32-बाइट** कुंजी रखता है, कभी PEM नहीं (`ed25519-mini` एक PEM नहीं पढ़ सकता):

```sh
mkdir -p <module>/vdlu/keyring
cp ./keys/<id>.pub.raw <module>/vdlu/keyring/<id>.pub
```

keyring release के पार स्थिर है (यह केवल key rotation पर बदलता है): एक re-vendor पर, इसे **verify करें,
अधिलेखित न करें**।

## 4. config लिखें

`config.default` को `<module>/vdlu/` में भेजें (पहले run पर Tier-2 `config` को seed करता है):

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

`profile=trusted` का उपयोग केवल एक निजी `file://`/SSH स्रोत के लिए करें (verify best-effort, हर blob का
sha256 फिर भी जाँचा जाता है)। शाब्दिक `trusted` के अलावा कोई भी मान `hardened` (fail-closed) के रूप में माना
जाता है।

## 5. triggers को wire करें

**Reboot पर** (`auto_on_reboot`): `post-fs-data.sh` से engine को pre-zygote कॉल करें ताकि staged फ़ाइलें (एक
`.so`, एक `/system` overlay, एक `sepolicy.rule`) बिना किसी अतिरिक्त reboot के swap हो जाएँ:

```sh
# <module>/post-fs-data.sh
MODDIR=${0%/*}
sh "$MODDIR/vdlu/update.sh" boot
```

**WebUI open पर** (`auto_on_webui_open`): अपने `webroot/index.html` में drop-in Updates panel को wire करें:

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

(`vdlu.js` / `vdlu.css` को `webui/` से vendor किया जाता है, `i18n: window.VDLU_I18N_<LANG>` के साथ एक अनुवाद
जोड़ा जा सकता है।)

## 6. अपने release workflow में feed को sign करें

प्रत्येक release पर, अंतिम मॉड्यूल वृक्ष को pack करें और manifest को sign करें। private key को operator मशीन
पर रखें, कभी CI में नहीं:

```sh
producer/vdlu-pack  <module>  ./out  <module> <versionCode> --version-name v<versionCode> --channel stable \
                    [--prev ./prev/manifest.json]        # delete[] = paths gone since prev
producer/vdlu-sign  ./out/manifest.json  ./keys/<id>.pem  <id>
# publish ./out/{manifest.json,blobs/} to <source>
```

## 7. baseline भेजें

भेजे गए वृक्ष पर `baseline.json` उत्पन्न करें और इसे `<module>/vdlu/baseline.json` पर रखें। यह एक ताज़ा इंस्टॉल
पर `current.json` को seed करता है ताकि डिवाइस "वर्तमान" पैदा हो (कोई re-fetch नहीं)। यह एक **स्थानीय विश्वसनीय
seed** है: अहस्ताक्षरित और keyless, इसलिए CI इसे signing key को कभी छुए बिना build कर सकता है:

```sh
producer/vdlu-pack  <module>  ./seed  <module> <versionCode> --version-name v<versionCode>
cp ./seed/manifest.json <module>/vdlu/baseline.json
```

अनुपस्थित होने पर यह गैर-घातक है (डिवाइस बस पहले अपडेट पर `0` से शुरू होता है)।

---

यही पूरी अपनाने की प्रक्रिया है। `sh -n <module>/vdlu/update.sh` पास होना चाहिए, भेजने से पहले producer और
engine को end-to-end परीक्षण करें जैसा [`PRODUCER.md`](PRODUCER.md) और root README में दिखाया गया है।

<!-- doc-footer -->

---

> _यह दस्तावेज़ Claude (Anthropic) से तैयार किया गया है और इसे VD171 द्वारा अनुरक्षित किया जाता है। सुधार और संशोधन का स्वागत है, देखें [CONTRIBUTING.md](CONTRIBUTING.md)।_
