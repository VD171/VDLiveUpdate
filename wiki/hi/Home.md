# VDLiveUpdate (VDLU)

**VDLU, KernelSU / APatch / Magisk modules के लिए एक flashless, incremental self-update engine है: एक इंस्टॉल किया हुआ module एक signed feed के ऊपर अपनी ही फाइलों को अपडेट करता है, सिर्फ वही लाता है जो बदला है, और उसमें से अधिकांश बिना reboot के लागू कर देता है।**

एक सामान्य module अपडेट पूरी `.zip` दोबारा भेजता है, तो कुछ बदली हुई लाइनों के लिए एक पूरा re-download चुकाना पड़ता है, और एक static update manifest सिर्फ एक अकेले `zipUrl` की ओर इशारा कर सकता है (हर device के लिए एक ही flavor)। VDLU एक अलग रास्ता अपनाता है: यह उस tree को, जो असल में इंस्टॉल है, एक signed, content-addressed feed के विरुद्ध diff करता है, सिर्फ deltas डाउनलोड करता है, और उन्हें जगह पर ही लिख देता है। एक arm64 full install arm64 full ही रहता है, एक lite install lite ही रहता है, और module को कभी दोबारा फ्लैश नहीं किया जाता।

VDLU को एक module में **vendor** किया जाना है, उसे `<module>/vdlu/` में डाला जाता है। यह अपने आप में कोई module नहीं है।

## उद्देश्य (Objectives)

- **Flashless self-update.** एक इंस्टॉल किए हुए module को जगह पर ही अपडेट करें, over the air, बिना किसी root manager के, बिना `.zip` को दोबारा फ्लैश किए, और इंस्टॉल किए हुए flavor को खोए बिना।
- **Content के हिसाब से Incremental.** सिर्फ उन्हीं blobs को ट्रांसफर करें जिनका content बदला है। एक content-addressed feed (`manifest.json` + `blobs/<sha256>`) का मतलब है कि अनबदली या पलटी हुई (reverted) फाइलें कभी दोबारा फेच नहीं होतीं।
- **जहाँ सुरक्षित हो वहाँ Reboot-free.** सामान्य फाइलों को live, तुरंत लागू करें। एक staged reboot सिर्फ उन चंद फाइलों के लिए रखें जिन्हें सचमुच इसकी जरूरत होती है (एक `.so`, एक `/system` overlay, एक `sepolicy.rule`)।
- **Device पर Slim.** शुद्ध POSIX `sh`, device पर कोई `jq` नहीं, कोई `bash` नहीं, कोई `openssl` नहीं। Verification एक embedded `ed25519-mini` पर टिका है; एकमात्र फेच किया गया binary एक static `curl` है, जो सिर्फ `https` feeds के लिए इस्तेमाल होता है।
- **Fail-closed और ईमानदार।** हर manifest field को hostile input माना जाता है और कुछ भी डाउनलोड होने से पहले validate किया जाता है। किसी चीज़ को तब तक "done" नहीं बताया जाता जब तक एक re-hash यह साबित न कर दे, और किसी चीज़ को बिना पहले backup लिए overwrite नहीं किया जाता।

## विशेषताएँ (Peculiarities)

जो चीज़ VDLU को एक सामान्य OTA client से अलग बनाती है:

- **Flashless और incremental.** dedup के साथ content-addressed diff / fetch / apply: device, signed feed के विरुद्ध delta कंप्यूट करता है और सिर्फ गायब blobs खींचता है।
- **जहाँ संभव हो Reboot-free.** सामान्य फाइलें live लागू होती हैं; सिर्फ `.so`, `/system` overlays, और `sepolicy.rule` फाइलें stage होती हैं और एक अकेले reboot पर swap होती हैं। देखें [[Reboot Handling]]।
- **Device पर POSIX `sh`.** toybox / busybox / mksh के नीचे चलता है। कोई `jq` नहीं (एक `gron`-शैली का `awk` flattener JSON parse करता है), कोई `bash`ism नहीं, कोई भारी runtime नहीं।
- **Slim verification.** एक embedded `ed25519-mini` signatures verify करता है। **device पर कोई `openssl` नहीं है**; private key कभी किसी device या CI को नहीं छूती।
- **Fail-closed security.** `validate_plan()` किसी भी गलत field पर **पूरे** manifest को अस्वीकार कर देता है (absolute या `..` path, एक `sha256` जो 64 hex अक्षरों का न हो, एक invalid mode / class / encoding)। दो profiles, `trusted` और `hardened`, जिसमें `hardened` inversion से fail-closed है। देखें [[Security and Trust Model]]।
- **Resumable और atomic.** एक journal हर transaction को crash-safe बनाता है; writes `rename` / `mv` का इस्तेमाल करते हैं; किसी भी overwrite से पहले एक backup लिया जाता है ताकि एक असफल apply, module को corrupt करने के बजाय rollback हो जाए।

## यहाँ से शुरू करें

| अगर आप चाहते हैं... | यहाँ जाएँ |
|---|---|
| VDLU को अपने module में अपनाना, चरण-दर-चरण | [[Quick Start]] |
| पूरे सिस्टम को एक नज़र में समझना | [[Architecture]] |
| device-side engine (`update.sh`) सीखना | [[Engine]] |
| अपने PC पर एक feed बनाना और sign करना | [[Producer]] |
| Updates panel को ड्रॉप इन करना | [[WebUI]] |
| trust model और threat posture पढ़ना | [[Security and Trust Model]] |
| manifest और blob layout देखना | [[Feed Format]] |
| जानना कि क्या reboot करता है और क्यों | [[Reboot Handling]] |
| एक आम सवाल पूछना | [[FAQ]] |
| योगदान देना | [[Contributing]] |

## प्रोजेक्ट लिंक

- **Source:** https://github.com/VD171/VDLiveUpdate
- **Channel (updates):** @Priv8_VD https://t.me/Priv8_VD

VDLiveUpdate एक स्वतंत्र, अनौपचारिक प्रोजेक्ट है। "Android", Google LLC का एक trademark है; "KernelSU", "Magisk", और "APatch" अपने-अपने लेखकों के marks हैं। VDLU पूरी तरह आपके device और आपके अपने release host पर चलता है।
