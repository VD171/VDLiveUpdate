# Quick Start

यह adoption checklist है: **VDLiveUpdate (VDLU)** को एक
KernelSU / APatch / Magisk module में कैसे vendor करें। VDLU खुद एक module नहीं है। इसे
`<module>/vdlu/` में डाला जाता है और आपके module की zip के अंदर भेजा जाता है, ताकि एक इंस्टॉल किया हुआ module
आपके द्वारा publish किए गए एक signed feed से खुद को flashlessly अपडेट कर सके।

पूरे दौरान, `<id>` को अपनी signing-key id से बदलें, `<abi>` को उस device
ABI(s) से जो आप भेजते हैं (`arm64-v8a`, `armeabi-v7a`, `x86_64`, `x86`), और `<module>`
को अपने module tree से।

हर टुकड़े के पीछे के तर्क के लिए, देखें [[Engine]], [[Producer]], [[WebUI]] और
[[Security and Trust Model]]।

## in-module `vdlu/` layout

यह वह सटीक tree है जो आपका module adoption के बाद ढोता है:

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

engine का mutable state (`config`, `current.json`, journal, lock, blob cache)
Tier-2 में `/data/adb/<modid>/vdlu/` पर रहता है, module directory के बाहर।
`config.default` पहले run पर उस Tier-2 `config` को seed करता है। पूरे state layout के लिए देखें
[[Engine]]।

## 1. Engine को vendor करें

engine, verify shim और per-ABI verifier binary को
`<module>/vdlu/` में copy करें:

```sh
mkdir -p <module>/vdlu/verify
cp engine/update.sh   <module>/vdlu/update.sh
cp engine/vdlu-verify <module>/vdlu/vdlu-verify
cp -r verify/<abi>    <module>/vdlu/verify/<abi>    # ed25519-mini per ABI
```

सिर्फ वही ABIs भेजें जिन्हें आप support करते हैं। आपका `customize.sh` install time पर `verify/` को
device की ABI तक prune कर सकता है।

## 2. एक signing key generate करें (one-time)

```sh
producer/vdlu-keygen <id> ./keys
```

यह तीन files निकालता है:

- `<id>.pem` - private key। इसे हर device से दूर और किसी भी repo
  push या CI secret से बाहर रखें।
- `<id>.pub` - PEM public key। सिर्फ PC-side (`vdlu-sign` द्वारा इस्तेमाल)।
- `<id>.pub.raw` - RAW 32-byte public key, device keyring के लिए।

विभाजन क्यों मायने रखता है, इसके लिए देखें [[Security and Trust Model]]।

## 3. raw public key embed करें

device keyring **RAW 32-byte** key रखती है, कभी PEM नहीं। `ed25519-mini`
एक PEM नहीं पढ़ सकता, तो PEM को यहाँ copy करना on-device verification तोड़ देता है:

```sh
mkdir -p <module>/vdlu/keyring
cp ./keys/<id>.pub.raw <module>/vdlu/keyring/<id>.pub
```

keyring releases के पार stable है: यह सिर्फ key rotation पर बदलती है। एक
दोबारा vendor पर, **इसे verify करो, इसे overwrite मत करो**।

## 4. config लिखें

`<module>/vdlu/` में `config.default` भेजें। यह पहले
run पर Tier-2 `config` को seed करता है:

```
auto_on_reboot=1
auto_on_webui_open=1
source=https://<user>.github.io/<repo>/<module>
channel=stable
profile=hardened        # public feed: signature mandatory, downgrade blocked
net_policy=any
pubkey_dir=keyring
```

`profile=trusted` का उपयोग सिर्फ एक private `file://` या SSH source के लिए करें (verify वहाँ
best-effort है, पर हर blob का sha256 फिर भी जाँचा जाता है)। literal `trusted` के अलावा कोई भी value
`hardened` मानी जाती है, fail-closed। पूर्ण profile semantics के लिए देखें
[[Security and Trust Model]]।

## 5. triggers wire करें

**On reboot** (`auto_on_reboot`): engine को pre-zygote
`post-fs-data.sh` से call करें, ताकि staged reboot-class files (एक `.so`, एक `/system` overlay,
एक `sepolicy.rule`) बिना किसी अतिरिक्त reboot के swap हो जाएँ:

```sh
# <module>/post-fs-data.sh
MODDIR=${0%/*}
sh "$MODDIR/vdlu/update.sh" boot
```

**On WebUI open** (`auto_on_webui_open`): अपने
`webroot/index.html` में drop-in Updates panel wire करें:

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

`vdlu.js` और `vdlu.css` `webui/` से vendor किए जाते हैं। एक translation
`i18n: window.VDLU_I18N_<LANG>` के साथ जोड़ी जा सकती है। panel contract के लिए देखें [[WebUI]]।

## 6. अपने release workflow में feed sign करें

हर release, अंतिम module tree को pack करें और manifest को sign करें। private
key को operator machine पर रखें, कभी CI में नहीं:

```sh
producer/vdlu-pack  <module>  ./out  <module> <versionCode> \
                    --version-name v<versionCode> --channel stable \
                    [--prev ./prev/manifest.json]      # delete[] = paths gone since prev
producer/vdlu-sign  ./out/manifest.json  ./keys/<id>.pem  <id>
# publish ./out/{manifest.json,blobs/} to <source>
```

`vdlu-pack` content-addressed और deduplicating है, तो publishing incremental है:
अनबदले blobs कभी दोबारा push नहीं होते। देखें [[Producer]] और [[Feed Format]]।

## 7. baseline भेजें

भेजे गए tree के ऊपर `baseline.json` generate करें और उसे
`<module>/vdlu/baseline.json` पर रखें। यह एक fresh install पर `current.json` को seed करता है, ताकि
device जन्म से "current" हो और अपने खुद के भेजे गए version को दोबारा fetch न करे। यह एक
**local trusted seed** है: unsigned और keyless, तो CI इसे signing key को कभी छुए
बिना बना सकता है:

```sh
producer/vdlu-pack  <module>  ./seed  <module> <versionCode> --version-name v<versionCode>
cp ./seed/manifest.json <module>/vdlu/baseline.json
```

यह अनुपस्थित होने पर गैर-घातक है: device बस
पहले update पर version `0` से शुरू करता है।

---

बस यही पूरा adoption है। भेजने से पहले, `sh -n <module>/vdlu/update.sh`
पास होना चाहिए, और आपको producer और engine को end-to-end test करना चाहिए जैसा
[[Contributing]] और [[Producer]] में दिखाया गया है।
