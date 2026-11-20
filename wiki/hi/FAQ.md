# FAQ

उन सवालों के छोटे जवाब जो सबसे ज़्यादा आते हैं। हर एक उस पेज से link करता है जहाँ
पूरी कहानी है।

## "flashless" का क्या मतलब है? क्या मुझे पहली बार फिर भी flash करना होगा?

हाँ, आप एक बार flash करते हैं। module सामान्य तरीके से इंस्टॉल होता है (अपने root manager में
zip flash करें)। "Flashless" उसके बाद के हर update का वर्णन करता है: VDLU सिर्फ
उन्हीं files को fetch करता है जो बदलीं और उन्हें जगह पर लागू करता है, तो आप कुछ बदली हुई लाइनें भेजने के लिए
कभी एक पूरी zip दोबारा flash नहीं करते। देखें [[Architecture]]।

## क्या एक update को reboot चाहिए?

आमतौर पर नहीं। अधिकांश files (आपका WebUI, binaries, libraries, configs, `module.prop`)
**live** class हैं और बिना किसी reboot के atomically लागू होती हैं। सिर्फ reboot-class files
(`zygisk/` के नीचे एक `.so`, एक `/system/**` overlay, एक `*.rule` sepolicy file)
**staged** होती हैं और अगले boot पर swap होती हैं, क्योंकि एक चल रहा process
live inode को पहले ही map कर चुका है। जब ऐसा होता है तो WebUI एक persistent "reboot to
activate" banner दिखाता है। देखें [[Reboot Handling]]।

## क्या यह सुरक्षित है अगर feed MITM'd या poisoned हो?

हाँ, एक `hardened` feed पर। हर manifest field को hostile input माना जाता है।
manifest को अपने canonical form के ऊपर एक valid ed25519 signature ढोनी चाहिए, और
`validate_plan()` **किसी भी download से पहले** fail-closed चलता है: यह पूरे
manifest को एक absolute या `..` path, एक `sha256` जो 64 hex characters का न हो,
या एक invalid mode, class या encoding पर अस्वीकार कर देता है। manifest आपके module
id से भी bound है, तो एक अलग module के लिए एक वैध रूप से signed feed इसके बदले परोसा नहीं जा सकता।
हर blob का sha256 download के बाद verify होता है, profile चाहे जो हो। देखें
[[Security and Trust Model]]।

## device पर इसे क्या चाहिए (dependencies)?

बहुत कम। शुद्ध POSIX sh (mksh / busybox / toybox) और साथ में toybox के `sha256sum`,
`gzip`, `base64` और `date`; embedded `ed25519-mini` verifier; और, सिर्फ एक
`https` source के लिए, एक static `curl` जो एक बार fetch और Tier-2 में cache होता है।
एक `file://` source को किसी curl की ज़रूरत ही नहीं। **`jq` पर कोई dependency नहीं है**:
engine JSON को `awk` में लिखे एक gron-शैली के flattener से parse करता है। देखें [[Engine]]।

## क्या device पर openssl ज़रूरी है?

नहीं। `openssl` सिर्फ PC/release पहलू पर इस्तेमाल होता है (`vdlu-keygen`, `vdlu-sign`)।
device पर, signature verification पतले embedded `ed25519-mini`
binary का इस्तेमाल करता है, जो एक RAW 32-byte public key पढ़ता है। देखें [[Producer]] और
[[Security and Trust Model]]।

## मैं signing key कैसे rotate करूँ?

`vdlu-keygen` से एक नया keypair generate करें, नई RAW 32-byte public key को
device keyring में पिछली के साथ जोड़ें, और नई `key_id` से sign करना शुरू करें।
device manifest की `key_id` से `<keyring>/<key_id>.pub` चुनता है,
तो किसी engine change की ज़रूरत नहीं। मौजूदा और पिछली दोनों public key भेजने
का मतलब है कि एक rotated key कभी पुराने installs को brick नहीं करती। चूँकि एक rotation keyring में एक से अधिक key छोड़ देती है, आपको यह भी pin करना होगा कि कौन सी key एक module update sign कर सकती है: `key_id` config सेट करें (rotation window के दौरान comma से अलग)। एक single-key keyring अपने आप pin हो जाती है और किसी config की ज़रूरत नहीं। देखें [[Security and Trust Model]]।

## hardened बनाम trusted - मैं कौन सा इस्तेमाल करूँ?

किसी भी public feed के लिए `hardened` इस्तेमाल करें (`https` के ऊपर परोसा गया, जैसे GitHub Pages)।
यह signature को अनिवार्य बनाता है और downgrades को block करता है। `trusted` सिर्फ एक
private `file://` या SSH-staged source के लिए इस्तेमाल करें जिसे आप पहले से नियंत्रित करते हैं, जहाँ signature
best-effort है (हर blob hash फिर भी जाँचा जाता है)। संदेह होने पर, `hardened` इस्तेमाल करें:
यह fail-closed default है, और कोई भी non-`trusted` value `hardened` मानी जाती है। देखें [[Security and Trust Model]]।

## अगर एक blob tampered हो या manifest malformed हो तो क्या?

update abort हो जाता है और कुछ भी लागू नहीं होता। एक malformed manifest को
किसी भी fetch से पहले `validate_plan()` द्वारा पूरा अस्वीकार कर दिया जाता है। एक blob जिसका sha256 manifest से
मेल नहीं खाता, अस्वीकार हो जाता है; एक ही blob पर तीन विफलताएँ fetch phase को
बिना कुछ लागू किए abort कर देती हैं। किसी भी hard failure पर journal `ERROR` दर्ज करता है और module
intact छोड़ा जाता है। देखें [[Engine]]।

## क्या एक update मेरी files delete कर सकता है या device brick कर सकता है?

जोखिम design से सीमित है। Overwrite की गई और delete की गई files पहले
`rollback/<version>/` में backup होती हैं, और `apply` एक सफल backup के बिना overwrite करने के बजाय
abort हो जाता है। Deletes सिर्फ तभी चलती हैं जब एक transaction `DONE` पहुँचता है, कभी
तब नहीं जब एक reboot अभी भी pending हो। एक विफल apply उन live files को revert कर देता है जो उसने पहले ही
लिख दीं। Paths उपयोग से पहले module directory के अंदर containment के लिए validate की जाती हैं,
तो एक manifest tree के बाहर लिख या delete नहीं कर सकता। देखें [[Engine]] और
[[Security and Trust Model]]।

## क्या यह KernelSU और Magisk और APatch पर काम करता है?

हाँ। VDLU सादी POSIX sh और साथ में एक WebUI है, module में vendored, तो यह
KernelSU, APatch और Magisk सब पर चलता है। यह engine को चलाने और progress poll करने के लिए root manager के WebUI bridge
(`ksu.exec`) का इस्तेमाल करता है। देखें [[Architecture]] और
[[WebUI]]।

## on-device footprint कितना बड़ा है?

छोटा। engine scripts हैं; एकमात्र binaries per-ABI `ed25519-mini`
verifier (छोटा) और, एक `https` source के लिए, एक static `curl` (~1MB) हैं जो
एक बार fetch और cache होता है। एक module जो पहले से अपना खुद का `curl` bundle करता है वह उसे दोबारा इस्तेमाल करता है
और कोई download नहीं जोड़ता। Tier-2 blob cache verified content और साथ में
पिछली 3 rollback versions रखता है। देखें [[Engine]] और [[Architecture]]।
