# Contributing

योगदान आमंत्रित हैं। VDLU एक flashless, incremental self-update engine है जो
KernelSU / APatch / Magisk modules में vendored है। यह पेज व्यावहारिक dev
workflow है; टुकड़े कैसे फिट होते हैं इसके लिए, पहले पढ़ें [[Architecture]], [[Engine]] और
[[Producer]]।

## कुछ भी compile नहीं होता

VDLU scripts हैं (POSIX sh, release पहलू पर थोड़ा Python, WebUI के लिए vanilla JS),
तो कोई build step नहीं है। आप एक change को pipeline को end-to-end चलाकर और हर टुकड़े को
static-check करके verify करते हैं।

## पहले Seam contract

components के बीच का interface contract (CLI signatures, file names और
JSON keys जो engine, producer और WebUI द्वारा साझा होते हैं) **law of
convergence** है। इसे immutable मानें। अगर आपका change
producer-to-engine seam (manifest schema, journal schema, config keys,
signature/canonicalization rule) को छूता है, तो **पहले interface contract align करें**, फिर
दोनों पहलुओं पर code को मेल खाने के लिए बदलें। seam के एक पहलू पर एक change बिना
दूसरे के चुपचाप adopters को तोड़ देता है। वह canonicalization rule जिस पर signer और verifier को byte-दर-byte
सहमत होना चाहिए, उसके लिए देखें [[Producer]]।

## एक PR से पहले end-to-end test करें

producer और engine को एक throwaway tree पर एक साथ चलाएँ, उसी तरह जैसे एक
adopter की release करती है:

```sh
# 1. a signing key
producer/vdlu-keygen demo /tmp/k

# 2. pack a module tree into a feed
producer/vdlu-pack /tmp/tree /tmp/feed demo 1 --version-name v1

# 3. sign the manifest in place
producer/vdlu-sign /tmp/feed/manifest.json /tmp/k/demo.pem demo

# 4. verify the manifest the way the device will (RAW 32B keyring)
engine/vdlu-verify /tmp/feed/manifest.json /tmp/keyring

# 5. drive the engine against the feed (source=file:///tmp/feed in the config)
VDLU_DIR=... MODULE_DIR=... MODID=demo sh engine/update.sh check   # then run / boot
```

फिर हर component को static-check करें:

```sh
sh -n engine/*.sh            # POSIX sh syntax, must pass
node --check webui/vdlu.js   # WebUI JS syntax
```

और `webui/demo.html` को एक browser में खोलें: यह root-manager bridge
(`ksu.exec`) को mock करता है, तो आप Updates panel, progress toast, cancel
और reboot banner को बिना किसी device के exercise कर सकते हैं। देखें [[WebUI]]।

## घर के नियम (House rules)

- **device पर POSIX sh.** `local` से आगे कोई bashism नहीं, और कोई `jq` नहीं। इसे
  toybox / busybox पर चलना होता है।
- **Security गैर-परक्राम्य है।** हर manifest field hostile input है;
  `validate_plan()` fail-closed रहता है, और private signing key कभी
  CI या एक device को नहीं छूती। एक test पास कराने के लिए एक check ढीला मत करो।
- **Failure पर कठोरता।** transaction को resumable रखो: कोई चीज़ एक मेल खाते re-hash के बिना "done" रिपोर्ट नहीं करती,
  कोई चीज़ बिना एक backup के overwrite नहीं होती, और
  applies atomic रहती हैं।
- **हमेशा release quality.** comments संक्षिप्त रखो; कोई बेवजह comments नहीं।
- **प्रति PR एक logical change.** बताओ कि क्या बदला और क्यों।

## Issues दर्ज करना

एक issue खोलें जो वर्णन करे कि आपने क्या किया, आपने क्या उम्मीद की, और क्या हुआ।
एक bug के लिए, module id, source profile (`hardened` या `trusted`),
जो `update.sh` command आपने चलाई, और संबंधित `journal.json` शामिल करें (यह phase, state और error
दर्ज करता है)। एक feature के लिए, बताएँ कि यह कौन से component को छूता है (engine,
producer, या WebUI) ताकि seam प्रभाव शुरू से ही स्पष्ट हो।
