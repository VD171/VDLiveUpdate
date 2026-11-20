# Security and Trust Model

VDLU एक module को जगह पर, network के ऊपर, root के रूप में अपडेट करता है। यह एक ऐसी file की ओर ताका गया बहुत सारा अधिकार है जो एक feed से आती है, तो पूरा engine एक अकेली धारणा पर बना है:

> **manifest में हर field hostile input है।**

एक feed को source पर ज़हर दिया जा सकता है, या transit में एक MITM द्वारा swap और विकृत किया जा सकता है। जब ऐसा होता है तब भी manifest एक manifest जैसा दिखता हुआ ही आता है: यह file paths, `sha256` strings, एक `delete[]` सूची, modes, classes और एक encoding flag ढोता है। VDLU इनमें से किसी को भी भरोसेमंद नहीं मानता। यह एक भी byte डाउनलोड करने से पहले पूरे plan को validate करता है, और यह कभी एक manifest value को एक shell तक पहुँचने नहीं देता।

यह पेज पूरी trust कहानी है। जिस manifest schema को यह validate करता है उसके लिए देखें [[Feed Format]], और ये checks DIFF -> FETCH -> APPLY -> COMMIT transaction में कहाँ बैठते हैं इसके लिए देखें [[Engine]]।

---

## मूल विचार: fail-closed, कुछ भी होने से पहले

`validate_plan()` `check`/diff phase के अंदर चलता है, किसी भी fetch से **पहले** और किसी भी apply से **पहले**। यह planned file tree की हर entry और `delete[]` की हर entry को walk करता है, और अगर कोई एक भी entry malformed है तो यह **पूरे manifest को अस्वीकार कर देता है** और transaction शुरू ही नहीं होता। कोई partial accept नहीं, कोई "खराब वाले को skip करो और बाकी apply करो" नहीं। एक खराब field पूरे batch को ज़हर दे देता है, जानबूझकर।

एक manifest सिर्फ तभी स्वीकार होता है जब **हर** entry के लिए ये **सब** सही हों:

| Field | नियम | क्यों |
|---|---|---|
| `path` | absolute नहीं, कोई `..` component नहीं, कोई `.` component नहीं, कोई leading `./` नहीं, कोई embedded `/./` नहीं, कोई trailing slash नहीं, कोई control character नहीं (tab / newline) | एक path को `MODULE_DIR` के अंदर रहना चाहिए; एक absolute या `..` path कहीं-भी-लिखो है |
| `sha256` | ठीक `^[0-9a-f]{64}$` से मेल खाता है | एक non-hex sha वरना एक shell path में interpolate हो जाता; यह content address है, तो यह एक शुद्ध hex digest होना चाहिए और और कुछ नहीं |
| `mode` | सिर्फ octal (`[0-7]`) | एक mode string एक `chmod` argument बनता है |
| `size` | सिर्फ digits, और engine की size ceiling से `<=` | download और decompression को सीमित करता है |
| `class` | ठीक `live`, `soft` या `reboot` | class तय करती है कि एक file live लागू होती है या reboot के लिए stage होती है |
| `enc` | ठीक `raw` या `gz` | encoding तय करता है कि blob gunzip होता है या नहीं |
| `delete[]` entries | ऊपर जैसे ही वही path नियम | एक `delete[]` entry एक removal चलाती है; एक बिना-जाँचा `..` tree के बाहर `rm` होता |

क्योंकि यह पहले चलता है, एक ज़हरीला manifest कभी module के बाहर नहीं लिख सकता, कभी module के बाहर delete नहीं कर सकता, और कभी एक command line में एक non-hex token inject नहीं कर सकता।

### Manifest values कभी एक shell को नहीं छूतीं

नियम का दूसरा आधा: एक value के validation पास करने के बाद भी, यह कभी `sh` में interpolate नहीं होती, और कभी `awk system()` को नहीं दी जाती। check command जानबूझकर दोबारा लिखा गया था ताकि इसमें कोई `system()` call न हो। Content addressing बाकी का काम करता है: एक blob उसके `sha256` से fetch होता है, उसी `sha256` से नामित एक cache path में लिखा जाता है, और डाउनलोड किए गए bytes किसी चीज़ के लागू होने से पहले दोबारा-hash और तुलना किए जाते हैं। एक value जो एक साफ 64-hex digest नहीं है वह कभी इतनी दूर नहीं पहुँचती, क्योंकि `validate_plan()` उसे पहले ही अस्वीकार कर चुका होता है।

### Apply time पर एक दूसरी रक्षा पंक्ति

`validate_plan()` `..` को **lexically** रोकता है, लेकिन tree के अंदर पहले से मौजूद एक symlink अभी भी एक write को redirect कर सकता है। तो apply time पर `contained()` असल target path resolve करता है और पुष्टि करता है कि यह module base के नीचे बैठता है, resolve न होने पर fail-closed होते हुए। Writes atomic हैं (एक temp नाम में लिखो, फिर target के ऊपर `rename`) और हर overwrite पहले `rollback/` में backup होता है; एक विफल backup बिना safety net के overwrite करने के बजाय apply को abort कर देता है।

---

## दो profiles

VDLU दो trust profiles में से एक में चलता है, जो config में `profile=` से सेट होता है।

### `hardened` (public default)

- **Signature अनिवार्य है।** manifest को on-device keyring में एक key से एक valid ed25519 signature ढोनी चाहिए, वरना transaction abort हो जाता है।
- **Downgrade blocked है।** एक manifest जिसका `version` इंस्टॉल version से कम है, मना कर दिया जाता है। एक attacker आपको एक ज्ञात-vulnerable build पर वापस roll नहीं कर सकता।
- यह किसी भी ऐसे module के लिए profile है जो `https://` के ऊपर public को distribute किया जाता है।

### `trusted` (private, SSH-staged source)

- Signature verification **best-effort** है: source एक private `file://` या SSH-staged feed है जिसे आप नियंत्रित करते हैं, तो एक गायब या unverifiable signature hard-abort नहीं करती।
- **लेकिन हर blob का `sha256` फिर भी जाँचा जाता है, हमेशा।** `trusted` *किसने manifest sign किया* इसे ढील देता है, कभी *bytes plan से मेल खाते हैं या नहीं* इसे नहीं। Content integrity दोनों profiles में गैर-परक्राम्य है।

---

## Inversion से Fail-closed

यह सूक्ष्म हिस्सा है, और यही वह हिस्सा है जिसे अधिकांश सिस्टम गलत करते हैं।

`trusted` **एकमात्र** string है जो relaxed verification में opt-in करती है। engine "क्या यह `hardened` है?" test नहीं करता। यह test करता है "क्या यह `trusted` **नहीं** है?":

```sh
prof=$(cfg profile hardened | tr -d '[:space:]')
...
if [ "$prof" != trusted ]; then
    # signature mandatory
fi
```

तो literal `trusted` के अलावा **कुछ भी** hardened व्यवहार पर resolve होता है:

- line पूरी तरह गायब है -> hardened
- एक typo जैसे `hardend` -> hardened
- एक trailing space वाला `trusted `, या CRLF से एक `\r` -> hardened
- गलत case वाला `Trusted` -> hardened
- एक MITM-विकृत value -> hardened

एक पहले का version एक *गायब* line को hardened पर default करता था, जो फिर भी एक corrupt *value* को open path तक गिरने देता था। वह एक fail-open था: एक विकृत profile string चुपचाप एक unsigned manifest स्वीकार कर सकती थी, और एक unsigned manifest का मतलब है MITM के तहत swap किया गया एक attacker-सप्लाई किया `.so`, जो root-level remote code execution है। inversion इसे बंद करता है। relaxed verification पाने का एकमात्र तरीका `trusted` को बिल्कुल सही spell करना है, और तब भी blob hashes जाँचे जाते हैं। engine कभी unsigned code स्वीकार करने से एक typo की दूरी पर नहीं होता। (`tr -d` भटके हुए whitespace को strip करता है ताकि लचर spacing वाला एक वैध `trusted` गलती से अस्वीकार न हो, छेद को दोबारा खोले बिना।)

**यह test load-bearing है। इसे `!= trusted` ही रहना चाहिए और कभी `== hardened` नहीं बनना चाहिए।**

---

## Manifest module से bound है

एक अकेली release key कई modules को sign करती है। तो एक manifest जो वैध रूप से signed है, एक *अलग* module के लिए, सिद्धांत रूप में इसको परोसा जा सकता है (एक feed misconfiguration, एक source swap, या एक MITM redirect) और उसकी signature जाँच पास कर जाती। 

VDLU इसे एक bind से बंद करता है: manifest के अंदर signed `module` field इस install की `MODID` के बराबर होनी चाहिए, वरना manifest एक cross-module feed के रूप में अस्वीकार हो जाता है। क्योंकि `module` signed canonical form के अंदर है, एक attacker इसे signature तोड़े बिना नहीं बदल सकता। module B के लिए एक वैध रूप से signed feed बस module A पर लागू नहीं हो सकता।

---

## पतला on-device verifier

device पर verification **ed25519-mini** इस्तेमाल करता है, TweetNaCl (public domain) पर बना एक छोटा verify-only checker। **device पर कोई `openssl` नहीं है**।

- keyring entry **raw 32-byte public key** है, जो `keyring/<key_id>.pub` के रूप में संग्रहीत होती है। (PEM public key सिर्फ एक PC-side artifact है; एक PEM को device keyring में copy करना verification तोड़ देता है, क्योंकि verifier ठीक 32 raw bytes की उम्मीद करता है।)
- `vdlu-verify <manifest.json> <keyring_dir>` canonical form को पुनर्निर्मित करता है (manifest text जिसमें `sig` field हटी हो, compact, sorted keys), उसे उस 64-char hex message में hash करता है जिसे signature कवर करती है, base64 signature decode करता है, जाँचता है कि यह 64 bytes है, और `ed25519-mini <pub32> <msg> <sig64>` से एक फैसला माँगता है। rc 0 = valid, और कुछ भी = reject।
- binary per ABI static है (arm64-v8a, armeabi-v7a, x86, x86_64), एक `PROVENANCE.json` के साथ जो सटीक TweetNaCl sources, wrapper hash और build flags pin करता है, ताकि जो चीज़ root के रूप में चल रही है वह auditable हो।
- manifest से `key_id` खुद sanitize की जाती है (कोई `/` नहीं, कोई `..` नहीं, कोई quote नहीं) इससे पहले कि इसका उपयोग एक keyring file चुनने के लिए हो, ताकि यह keyring directory से बच न सके।

### keyring flash-only, verify-not-copy, stable है

keyring flash time पर module के अंदर भेजी जाती है और update engine द्वारा दोबारा नहीं लिखी जाती। दोबारा vendor पर नियम है **verify करो, copy मत करो**: keyring सिर्फ एक जानबूझकर की गई key rotation पर बदलती है, कभी एक update के साइड इफेक्ट के रूप में नहीं।

### Key rotation पुराने installs को brick नहीं करती

जब एक signing key rotate होती है, तो keyring **मौजूदा और पिछली दोनों raw public keys** भेजती है। verifier manifest की `key_id` से key file चुनता है, तो पुरानी key से अभी भी signed एक feed पुराने pubkey के विरुद्ध verify होता है, और नई key से signed एक feed नए के विरुद्ध। एक device जो rotation से आगे update नहीं हुआ है वह काम करता रहता है; कुछ भी अटका नहीं रहता।

---

## tools-manifest क्या बंद करता है

पतला fetch bootstrap उन modules के लिए पहले उपयोग पर एक static `curl` डाउनलोड करता है जो अपना खुद का नहीं भेजते। क्योंकि वह binary root के रूप में चलता है, इसकी अपनी manifest signature (ed25519-mini) और इसका hash किसी भी profile में **अनिवार्य** हैं, `trusted` समेत, इससे पहले कि इसे कभी install या execute किया जाए। webview सिर्फ transport है; trust on-device signature और hash check से आता है, कभी इस तथ्य से नहीं कि एक download सफल हुआ।

---

## एक attacker क्या नहीं कर सकता

feed का मालिक होकर भी, या एक पूरे MITM के रूप में wire पर बैठकर भी, एक attacker नहीं कर सकता:

- **module के बाहर लिखना।** Absolute paths, `..`, `.`, control characters और trailing slashes सब किसी भी apply से पहले अस्वीकार हो जाते हैं, और symlink redirection apply time पर दोबारा पकड़ी जाती है।
- **module के बाहर delete करना।** `delete[]` entries वही path validation पास करती हैं।
- **एक command inject करना।** कोई manifest value एक shell या `awk system()` में interpolate नहीं होती; `sha256` को शुद्ध 64-hex होना चाहिए वरना पूरा manifest अस्वीकार हो जाता है।
- **एक public install को unsigned code भेजना।** `hardened` signature को अनिवार्य बनाता है, और profile inversion से fail-closed है, तो कोई typo या विकृत value उसे downgrade नहीं करती।
- **यहाँ एक दूसरे module का signed feed परोसना।** signed `module` field इस `MODID` के बराबर होनी चाहिए।
- **आपको वापस roll करना।** `hardened` में Downgrade blocked है।
- **एक blob को बिना पकड़े corrupt करना।** हर डाउनलोड किया गया blob दोनों profiles में manifest `sha256` के विरुद्ध दोबारा-hash होता है; तीन प्रयासों के बाद एक mismatch phase को बिना कुछ लागू किए abort कर देता है।
- **एक नकली root fetcher swap करना।** bootstrapped `curl` हर profile में install या run होने से पहले signature- और hash-checked होता है।
- **एक corrupt update को आधा-apply करना।** transaction `DONE` तभी पहुँचता है जब हर चीज़ का re-hash मेल खाता है; एक विफल apply बिना backup के overwrite करने के बजाय rollback हो जाता है।

---

यह भी देखें: manifest schema के लिए [[Feed Format]], इन checks जिस transaction में रहते हैं उसके लिए [[Engine]], और बड़ी तस्वीर के लिए [[Architecture]]।
