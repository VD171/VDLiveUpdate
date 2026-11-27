> **Languages:** [English](../TRUST-MODEL.md) · [العربية](../ar/TRUST-MODEL.md) · [Čeština](../cs/TRUST-MODEL.md) · [Deutsch](../de/TRUST-MODEL.md) · [Español](../es/TRUST-MODEL.md) · [فارسی](../fa/TRUST-MODEL.md) · [Français](../fr/TRUST-MODEL.md) · हिन्दी · [Bahasa Indonesia](../id/TRUST-MODEL.md) · [Italiano](../it/TRUST-MODEL.md) · [日本語](../ja/TRUST-MODEL.md) · [한국어](../ko/TRUST-MODEL.md) · [Nederlands](../nl/TRUST-MODEL.md) · [Polski](../pl/TRUST-MODEL.md) · [Português](../pt/TRUST-MODEL.md) · [Русский](../ru/TRUST-MODEL.md) · [Svenska](../sv/TRUST-MODEL.md) · [ไทย](../th/TRUST-MODEL.md) · [Türkçe](../tr/TRUST-MODEL.md) · [Українська](../uk/TRUST-MODEL.md) · [Tiếng Việt](../vi/TRUST-MODEL.md) · [中文](../zh/TRUST-MODEL.md)

---

# सुरक्षा नीति और विश्वास मॉडल

VDLiveUpdate (VDLU) एक लाइव मॉड्यूल पर **flashless root अपडेट** लागू करता है: यह
`/data/adb/modules/<mod>` में लिखता है और boot पर एक Zygisk `.so` को swap करता है। fetch
किए गए manifest का हर फ़ील्ड (`path`, `sha256`, `delete[]`, `mode`, ...) **शत्रुतापूर्ण इनपुट** है - एक
ज़हरीला feed या एक MITM इसे पहुँचाता है। यह पृष्ठ विश्वास मॉडल और ज़िम्मेदार
प्रकटीकरण नीति है। पूर्ण सीवन अनुबंध के लिए [`INTERFACES.md`](INTERFACES.md) देखें,
और engine/producer के आंतरिक विवरण के लिए [`ENGINE.md`](ENGINE.md) और
[`PRODUCER.md`](PRODUCER.md), wiki पृष्ठ **Security-and-Trust-Model** रिपॉज़िटरी के बाहर के पाठकों के लिए
वही मॉडल ले जाता है।

## समर्थित संस्करण

सुरक्षा फ़िक्स नवीनतम `ENGINE_VERSION` में उतरते हैं, एक हस्ताक्षरित manifest `engine_min` के माध्यम से
अपनी ज़रूरत के न्यूनतम engine की घोषणा करता है, और on-device engine एक ऐसे manifest को अस्वीकार करता है
जो उससे अधिक माँगता है जितना वह लागू करता है। पुराने vendored engines से अपेक्षा है कि एक फ़िक्स उठाने के लिए
वे **re-vendor** करें, न कि उन्हें यथास्थान back-patch किया जाए।

| ENGINE_VERSION | स्थिति |
|---|---|
| 7 (वर्तमान) | समर्थित - feed से आगे वाले module को कभी revert न करें (live installed `versionCode` "from" version की न्यूनतम सीमा तय करता है), boot पर पुराने downgrade plan का self-heal |
| 6 | प्रतिस्थापित - boot पर पुराने `target <= 0` journal का self-heal (हटाए गए stub का baseline 0 अब कोई UI या boot क्रिया नहीं चलाता) |
| 5 | प्रतिस्थापित - engine-side trust-anchor exclusion (`vdlu/` dir को अनदेखा किया जाता है भले ही एक feed इसे ढोए), 128 MiB प्रति-file / 2 MiB manifest सीमाएँ |
| 4 | प्रतिस्थापित - `key_id` allowlist, dot-segment/trailing-slash path अस्वीकृति, size caps, check-time lock |
| <= 3 | असमर्थित - वर्तमान engine को re-vendor करें |

engine verification या apply logic में कोई भी परिवर्तन `ENGINE_VERSION` को bump करता है।

## एक भेद्यता की रिपोर्ट करना

निजी तौर पर रिपोर्ट करें। किसी सुरक्षा बग के लिए एक सार्वजनिक issue, PR, या forum पोस्ट **न** खोलें।
प्रोजेक्ट संपर्कों का उपयोग करें (देखें [`CONTRIBUTING.md`](../CONTRIBUTING.md)):

- Telegram: **@VD_Priv8** (https://t.me/VD_Priv8)
- चैनल: **@Priv8_VD** (https://t.me/Priv8_VD)
- ई-मेल: **vd.priv8@pm.me**

कृपया engine संस्करण, उपयोग में आया `profile`, और एक manifest या feed शामिल करें जो
समस्या को पुनरुत्पादित करता है। फ़िक्स एक `CHANGELOG.md` प्रविष्टि के साथ एक नए `ENGINE_VERSION` के रूप में
भेजे जाते हैं, प्रकटीकरण के समय का समन्वय रिपोर्ट थ्रेड पर करें।

## विश्वास मॉडल

- **Detached ed25519 हस्ताक्षर।** producer कैनोनिकल manifest को PC पर हस्ताक्षरित करता है (openssl);
  डिवाइस अंतर्निहित `ed25519-mini` के साथ सत्यापित करता है - **डिवाइस पर कोई openssl नहीं**। हस्ताक्षरित
  संदेश `sig` फ़ील्ड के बिना manifest का sha256 hex है (कुंजियाँ क्रमबद्ध, कॉम्पैक्ट, UTF-8), इसलिए sign और
  verify डिवाइस पर किसी JSON लाइब्रेरी के बिना दो रनटाइम पर समान बाइट्स व्युत्पन्न करते हैं।
- **Keyring = RAW 32-बाइट pubkeys**, केवल-flash। डिवाइस keyring `<key_id>.pub` को raw 32-बाइट कुंजी के रूप में
  भेजता है (कभी PEM नहीं), `vdlu-pack` keyring और `verify/` binaries को feed से **बाहर** करता है, इसलिए एक
  manifest कभी भी तार पर on-device trust anchor को पुनः नहीं लिख सकता।
- **Engine-side trust-anchor exclusion (VDLU#2)।** ऊपर दिए गए producer-side exclusion से स्वतंत्र रूप से, on-device engine एक fetch किए गए plan में हर `vdlu/` path (`update.sh`, `vdlu-verify`, `verify/*`, `keyring/*`, config) को **अनदेखा** करता है - यह उन्हें कभी fetch, apply, या delete नहीं करता, भले ही एक feed उन्हें ढोए। एक प्रकाशित feed पूरे module tree को भेजता है, `vdlu/` समेत, तो engine manifest को अस्वीकार करने के बजाय उन paths को चुपचाप गिरा देता है: module फिर भी update होता है, और trust anchor सिर्फ एक पूर्ण signed re-flash के ज़रिए बदलता है। एक अकेली leak हुई signing key अब verifier या signing key को wire पर swap करके root बनाए नहीं रख सकती।
- **Module-update `key_id` allowlist (fail-closed, pubkey चयन से पहले)।** एक keyring वैध रूप से एक से अधिक
  कुंजी ले जा सकता है (उदाहरण के लिए release कुंजी के बगल में एक कम-भरोसे वाली fingerprint-feed कुंजी)।
  इससे पहले कि `<key_id>.pub` कभी चुना जाए, `verify_manifest` **दोनों** profiles में किसी भी ऐसे manifest को
  अस्वीकार करता है जिसका `key_id` कॉन्फ़िगर की गई allowlist में नहीं है, और हल किए गए सेट को `VDLU_KEYID_ALLOW`
  के माध्यम से `vdlu-verify` में प्रतिबिंबित करता है। यह एक ऐसे bypass को बंद करता है जहाँ एक लीक हुई
  कम-भरोसे वाली कुंजी अन्यथा एक पूर्ण flashless root अपडेट पर हस्ताक्षर कर सकती थी। `key_id` अनसेट होने पर
  डिफ़ॉल्ट-सुरक्षित: एक **एकल-कुंजी** keyring स्वतः उस एक कुंजी पर pin हो जाता है, एक **बहु-कुंजी** keyring
  तब तक अस्वीकृत रहता है जब तक `key_id` pin न हो (rotation के लिए अल्पविराम से अलग)।
- **Fingerprint-feed trust root एक अलग, pinned path है** जिसकी अपनी कुंजी है, यह ऊपर दिए गए module-update
  path के माध्यम से कभी पहुँच योग्य नहीं है।
- **Baseline एक स्थानीय विश्वसनीय seed है।** `baseline.json` flash की गई zip के अंदर आता है - इंस्टॉल विश्वास
  सीमा - इसलिए यह अहस्ताक्षरित और keyless है और `vdlu-verify` से **नहीं** गुज़रता, केवल feed से **fetch** किया
  गया manifest सत्यापित होता है। यह signing कुंजी को CI से बाहर रखता है।

## Fail-closed गारंटियाँ

- **`validate_plan` किसी भी fetch या apply से पहले चलता है।** `do_diff` में, fail-closed, यह **पूरे** manifest
  को अस्वीकार करता है यदि कोई `path` absolute है, एक `..` या `.` segment रखता है, `/` में समाप्त होता है, या एक
  control character रखता है, यदि कोई `sha256` `^[0-9a-f]{64}$` नहीं है, या यदि कोई `mode`/`class`/`enc` अमान्य
  है। कोई शत्रुतापूर्ण फ़ील्ड किसी shell तक नहीं पहुँचता, और `cmd_check` कोई `system()` interpolation नहीं ले
  जाता।
- **Path containment।** हर write और delete `contained()` के माध्यम से `MODULE_DIR` तक सीमित है - apply, delete,
  और reboot `stage_file` सभी एक ही guard से गुज़रते हैं। वृक्ष में symlinks को producer द्वारा छोड़ दिया जाता
  है (इसके बाहर से कभी सामग्री लीक नहीं करता)।
- **दो profiles, inversion द्वारा fail-closed।** `trusted` (निजी, SSH-staged स्रोत) best-effort verify का
  **एकमात्र** opt-in है, **कोई भी** अन्य मान - जिसमें एक typo, एक trailing space/CR, या एक अलग case शामिल है -
  को `hardened` के रूप में माना जाता है, जहाँ एक वैध हस्ताक्षर **अनिवार्य** है और एक विफलता abort करती है। हर
  blob का `sha256` दोनों profiles में जाँचा जाता है।
- **किसी भी tool exec से पहले हस्ताक्षर + हैश।** fetch किया गया static `curl` root के रूप में चलता है, इसलिए
  `install-tool` tools-manifest हस्ताक्षर (ed25519-mini, **किसी भी** profile में अनिवार्य) और curl के हैश को
  उसके इंस्टॉल और execute किए जाने **से पहले** सत्यापित करता है - exec से पहले sig+hash RCE को बंद करता है।
- **पुनः आरंभ करने योग्य, pin-safe ट्रांज़ैक्शन।** in-flight manifest `target.json` में pin किया जाता है, एक
  crash, नेटवर्क हानि, या reboot plan को पुनः तय किए बिना journal से पुनः आरंभ करता है। Downgrade अवरुद्ध है
  (monotonic `version`), हस्ताक्षरित `module` फ़ील्ड `MODID` के बराबर होना चाहिए, और `delete[]` केवल
  `finalize_done` पर चलता है (एक `PENDING_REBOOT` कुछ भी नहीं हटाता)। एक पूर्ण पुनः-हैश के बिना कुछ भी कभी
  "done" नहीं होता, पहले एक `rollback/<v>/` backup के बिना कुछ भी अधिलेखित नहीं होता।

## कठोरता (गहराई में रक्षा)

- **Size caps।** manifest, tools-manifest, और curl-रहित `wget`/`head -c` डाउनलोड path सभी पढ़े जाने से पहले
  सीमित हैं (anti-OOM / anti-flood)। एक blob 3 प्रयासों के बाद अपने चरण में विफल होता है। सीमाएँ **128 MiB प्रति file** (`MAX_FILE_BYTES`) और **manifest के लिए 2 MiB** (`MAX_MANIFEST_BYTES`) हैं, जो `update.sh` में लागू होती हैं और `vdlu-verify` में प्रतिबिंबित होती हैं।
- **Check-time lock।** `check` अपनी work dir को पुनर्निर्मित करने से पहले mkdir-lock लेता है, इसलिए एक समवर्ती
  run इसके साथ race नहीं कर सकता।
- **Staging containment।** `stage_file` के पास लाइव apply primitives के समान `contained()` guard है, इसलिए एक
  staged reboot-hard path भी `MODULE_DIR` से बच नहीं सकता।
- **TLS गहराई में रक्षा है, trust root नहीं।** static curl Android trust store के साथ mbedTLS का उपयोग करता है
  (`--capath`, `ca_path` override), अखंडता की गारंटी ed25519 हस्ताक्षर है, cert जाँच एक दूसरी परत है।

## यह भी देखें

- [`INTERFACES.md`](INTERFACES.md) - अपरिवर्तनीय सीवन अनुबंध (§5 config, §6 signature, §11 toolchain)।
- [`ENGINE.md`](ENGINE.md) - device-side engine और इसकी state machine।
- [`PRODUCER.md`](PRODUCER.md) - packing, signing, कैनोनिकलीकरण, और key rotation।
- Wiki: **Security-and-Trust-Model**।

<!-- doc-footer -->

---

> _यह दस्तावेज़ Claude (Anthropic) से तैयार किया गया है और इसे VD171 द्वारा अनुरक्षित किया जाता है। सुधार और संशोधन का स्वागत है, देखें [CONTRIBUTING.md](CONTRIBUTING.md)।_
