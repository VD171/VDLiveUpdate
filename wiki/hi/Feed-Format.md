# Feed Format

**feed** वह है जो VDLU wire के ऊपर परोसता है और जिससे device अपडेट करता है। यह एक सादी static directory है, जिसे कुछ भी serve कर सकता है (GitHub Pages, एक rsync target, एक `file://` path):

```
<source>/
  manifest.json          # the signed description of the current release
  blobs/<sha256>         # one blob per distinct file content
  blobs/<sha256>.gz      # (when the blob is stored gzipped)
```

module खुद एक अतिरिक्त file, `baseline.json`, `.zip` के अंदर भी भेजता है (feed से serve नहीं होती)। यह सब जो producer बनाता है उसे [[Producer]] में वर्णित किया गया है; यह पेज on-wire contract है।

---

## manifest.json

manifest एक release का पूरा विवरण है: target tree में हर file, क्या delete करना है, और पूरी चीज़ के ऊपर signature।

```json
{
  "schema": 1,
  "module": "demo",
  "version": 106,
  "version_name": "v106",
  "built": "2026-11-19T12:00:00Z",
  "engine_min": 5,
  "channel": "stable",
  "key_id": "release-2026",
  "files": [
    {
      "path": "webroot/index.html",
      "sha256": "<hex64>",
      "size": 1234,
      "mode": "0644",
      "enc": "raw",
      "class": "live"
    }
  ],
  "delete": ["webroot/old.html"],
  "sig": "<base64>"
}
```

### Fields

| Field | अर्थ |
|---|---|
| `schema` | manifest का खुद का Format version (वर्तमान में `1`)। |
| `module` | module id। अगर यह उसके अपने module id से मेल नहीं खाता तो device manifest को अस्वीकार कर देता है, तो एक अलग module के लिए एक वैध रूप से signed feed इसके बदले परोसा नहीं जा सकता। |
| `version` | Integer version। engine सिर्फ आगे की ओर update करता है; device से पुराना एक feed एक सौम्य "ahead" state है, कोई error नहीं। |
| `version_name` | मानव-पठनीय version string (उदाहरण के लिए `v106`)। |
| `built` | ISO 8601 build timestamp। reproducibility के लिए `SOURCE_DATE_EPOCH` का सम्मान करता है। |
| `engine_min` | इस manifest को लागू करने के लिए आवश्यक न्यूनतम engine version। |
| `channel` | Release channel (उदाहरण के लिए `stable`)। |
| `key_id` | device keyring में कौन सी key ने इस manifest को sign किया। verification के लिए public key चुनता है, और engine की module-update allowlist में होनी चाहिए (देखें [[Security and Trust Model]]); एक key जो keyring में बस मौजूद है पर allowlisted नहीं है, उसकी pubkey load होने से पहले ही अस्वीकार हो जाती है। |
| `files[]` | **पूरा** target tree (एक diff नहीं)। हर entry: `path`, `sha256`, `size`, `mode`, `enc` (`raw`/`gz`), `class` (`live`/`soft`/`reboot`)। |
| `delete[]` | पिछली release में मौजूद paths जो अब चले गए, device के हटाने के लिए। |
| `sig` | ed25519 signature, base64। नीचे canonicalization देखें। |

`files[]` **पूरे** tree का वर्णन करता है, एक delta का नहीं। device खुद delta कंप्यूट करता है, manifest की उसकी पहले से मौजूद चीज़ से तुलना करके, और सिर्फ उन्हीं blobs को fetch करता है जिनका `sha256` उसके पास गायब है। `sha256` हमेशा मूल (uncompressed) content का होता है; `enc` सिर्फ यह कहता है कि वह blob `blobs/` में कैसे संग्रहीत है। `class` का अर्थ और device हर value के साथ क्या करता है, वह [[Reboot Handling]] में शामिल है।

---

## Canonicalization (signed bytes)

यह format में सबसे महत्वपूर्ण अकेला invariant है। PC signer और on-device verifier पूरी तरह अलग runtimes पर चलते हैं (PC पर openssl, device पर toybox + एक छोटा embedded verifier, और device पर **बिल्कुल कोई JSON library नहीं**)। उन्हें फिर भी sign करने और verify करने के लिए ठीक वही bytes निकालने होते हैं। इसलिए नियम एक जानबूझकर किया गया **byte transform** है, एक JSON re-serialization नहीं।

**Step 1: एक तय store form.** `vdlu-pack` `manifest.json` को compact लिखता है, keys sorted, UTF-8, हमेशा `key_id` और `sig` समेत (sign होने तक खाली strings के रूप में):

```
json.dumps(obj, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
```

**Step 2: सिर्फ `sig` strip करो.** canonical form वही सटीक text है जिसमें **सिर्फ `"sig"` field हटी हो**। क्योंकि keys sorted हैं, `sig` हमेशा `,"sig":"<value>",` के रूप में प्रकट होती है जो इससे पहले `"schema"` और इसके बाद `"version"` से घिरी होती है (दोनों हमेशा मौजूद), तो इसे हटाने से well-formed text बचता है। JSON एक string value के अंदर हर `"` को `\"` के रूप में escape करता है, तो structural token `"sig":"` असंदिग्ध है, एक ऐसे filename के विरुद्ध भी जिसमें literally `"sig":"` हो।

removal चंद POSIX parameter expansions हैं, signer और verifier में समान, बिना किसी `sed` और बिना किसी `jq` के:

```sh
# $1 = the full manifest text
_pre=${_c%%\"sig\":\"*}     # up to  ...,"schema":N,
_rest=${_c#*\"sig\":\"}      # after "sig":"
_tail=${_rest#*\",}          # after <value>",  ->  "version":...
printf '%s%s' "$_pre" "$_tail" | sha256sum | cut -d' ' -f1
```

**Step 3: उसके hash को sign करो.** signed/verified message canonical form का **sha256 hex** है (64 ASCII characters, कोई newline नहीं)। ed25519 उस hex को sign करता है।

इससे निर्माण से ही दो परिणाम निकलते हैं:

- `key_id` canonical form का हिस्सा है (सिर्फ `sig` strip होती है)। `vdlu-sign` `key_id` को hashing से **पहले** सेट करता है, तो key identity signature द्वारा कवर होती है।
- चाहे `sig` placeholder खाली हो (`"sig":""`, sign time पर) या भरा हुआ (verify time पर), इसे strip करने से समान canonical bytes मिलते हैं। Signing और verifying अपने आप सहमत हो जाते हैं।

दोनों POSIX sh tools आधिकारिक हैं। एक Python समकक्ष, `re.sub(r'"sig":"[^"]*",', '', text, count=1)` फिर sha256, सिर्फ उन्हें cross-check करने के लिए मौजूद है।

इस सब के इर्द-गिर्द trust तर्क (verification on-device क्यों है, `hardened` कैसे fail closed होता है) [[Security and Trust Model]] में रहता है।

---

## baseline.json (install seed)

जब एक module नया इंस्टॉल होता है, तो इसे अपने खुद के भेजे गए version के लिए पहले से ही "current" होना चाहिए, जो version इसने अभी इंस्टॉल किया उसके एक बेकार self-update के बिना। यही `baseline.json` करता है।

`baseline.json` **module zip के अंदर** भेजी जाती है (`vdlu/baseline.json` पर), feed पर नहीं। एक fresh install पर, engine अपना "active version" record इससे seed करता है, तो device जन्म से current होता है, बिना किसी `from:0` और बिना उसका दोबारा fetch किए जो उसके पास पहले से है।

मुख्य गुण:

- यह भेजे गए version के लिए **signed manifest की एक keyless copy** है: वही `vdlu-pack` output, unsigned छोड़ा हुआ (`key_id` और `sig` खाली रहते हैं)।
- यह **verify नहीं होती**। engine इसे एक local trusted seed मानता है क्योंकि यह flashed zip के अंदर आई, जो install trust boundary है। सिर्फ एक *feed से fetch किया गया* manifest signature verification से गुज़रता है।
- क्योंकि इसे किसी signature की ज़रूरत नहीं, **CI इसे keyless generate कर सकता है**, जो यही है जो signing key को पूरी तरह CI से बाहर रखता है (देखें [[Producer]])।
- `vdlu-pack` **`baseline.json` को अपने खुद के manifest से बाहर रखता है**, तो manifest कभी baseline को reference नहीं करता (वह एक self-reference loop होता: manifest से baseline से manifest)।
- यह **अनुपस्थित होने पर गैर-घातक है**। इसके बिना, device बस अपने पहले update पर `from:0` से शुरू करता है और जो ज़रूरी है वह fetch करता है। कभी टूटा नहीं, बस कम इष्टतम।

---

## Blobs

हर अलग file content `blobs/` के नीचे एक blob है, जो **मूल content के sha256** से नामित है:

- `blobs/<sha256>` एक raw blob के लिए।
- `blobs/<sha256>.gz` एक gzipped blob के लिए (gzip सिर्फ तभी रखा जाता है जब file कम से कम 4096 bytes की हो और compression कम से कम 10 प्रतिशत बचाए)।

एक blob एक बार संग्रहीत होता है, एक format में। Content addressing मुफ्त में deduplication देता है: अनबदला, shared या पलटा हुआ content एक ऐसे blob पर map होता है जो पहले से मौजूद है, तो feed सिर्फ सचमुच नए content से बढ़ता है, और device सिर्फ उन्हीं hashes को डाउनलोड करता है जो उसके पास गायब हैं। device हर डाउनलोड किए गए blob का `sha256` manifest के विरुद्ध जाँचता है (एक `gz` blob decompress करने के बाद) उसे इस्तेमाल करने से पहले।

---

## feed से क्या बाहर रखा गया है, और क्यों

feed **सिर्फ module का अपना content** ढोता है। paths का एक तय समूह जानबूझकर इससे बाहर रखा जाता है। `vdlu-pack` एक exclusion predicate लागू करता है, दोनों जब tree walk करता है और जब `delete[]` कंप्यूट करता है।

| Excluded | क्यों |
|---|---|
| `vdlu/keyring/`, `vdlu/verify/` (trust root: raw public keys + verifier binary) | **यही मूल सुरक्षा कारण है।** trust anchor **flash-only** है। अगर keyring या verifier feed-deliverable होते, तो एक manifest उसी चीज़ को overwrite कर सकता था जो उसे validate करती है। उन्हें wire से बाहर रखने का मतलब है एक manifest कभी on-device trust anchor को दोबारा नहीं लिख सकता। एक दूसरे, स्वतंत्र guard के रूप में (`ENGINE_VERSION` 5), engine एक fetch किए गए plan में हर `vdlu/` path को भी **अनदेखा** करता है, तो एक feed जो उन्हें ढोता है वह भी anchor को छू नहीं सकता। |
| `vdlu/baseline.json` | यह signed manifest की एक copy है (install seed); इसे pack करना एक self-reference loop होता। |
| `.vd/` flash infrastructure | Flash-gate scaffolding जो zip में भेजी जाती है, कभी live लागू नहीं होती। |
| `update.json`, `update-mmrl.json` | इनका size/sha CI द्वारा zips बनने के *बाद* भरा जाता है, तो भेजी गई copy किसी भी feed copy से अलग होती है। इन्हें feed करना हर install के पहले self-update पर एक phantom single-file fetch पैदा करता, और वे on-device वैसे भी vestigial हैं (manager remote raw update JSON पढ़ता है)। |
| `META-INF/`, `customize.sh` (installer scaffolding) | **flash** time पर manager द्वारा consume होती हैं और इंस्टॉल किए हुए module में नहीं रखी जातीं। वे VDLU content नहीं हैं; उन्हें serve करना blobs बर्बाद करता है और, अगर कोई कभी versions के बीच बदल गई, तो वह live module directory में एक installer file के रूप में लिख दी जाती। |
| Per-file `.sha256` companions | वे सिर्फ flashable zip की हैं, एक incremental update के बाद stale हो जाती हैं, और manifest को दुगना कर देतीं। |
| Dev/doc files (`RELEASE.md`, `CLAUDE.md`, `.gitignore`) | कभी device को नहीं भेजी जातीं; उन्हें serve करना blobs बर्बाद करता है और हर doc edit पर signed manifest को churn करता है। |

trust-root exclusion के पीछे का तर्क [[Security and Trust Model]] में विस्तारित है।

---

## delete[] semantics

`delete[]` device को बताता है कि कौन से paths हटाने हैं, ताकि releases के बीच गिराई गई एक file device पर एक orphan के रूप में न टिकी रहे। इसे `vdlu-pack` को `--prev <previous manifest.json>` पास करके कंप्यूट किया जाता है: एक path जो पिछली release में था और मौजूदा में नहीं है वह एक delete entry बन जाता है।

महत्वपूर्ण नियम: **excluded paths को कभी deletes के रूप में emit नहीं किया जाता, `--prev` के साथ भी नहीं।** हर पिछला path उसी exclusion predicate से गुज़ारा जाता है जो tree walk करते समय इस्तेमाल होता है। अगर एक `--prev` एक पुराने manifest की ओर इशारा करता है जिसमें अभी भी अब-excluded paths सूचीबद्ध थे (एक भटका `baseline.json`, `META-INF/*`, एक keyring entry, वगैरह), तो वे paths delete entries में **नहीं** बदले जाते। एक excluded path कभी feed content नहीं था, तो यह VDLU का नहीं है कि इसे delete करे, और device को कभी एक ऐसी file हटाने का आदेश नहीं दिया जाता जो feed के ज़रिए परोसी ही नहीं गई। यही है जो exclusion सूची को कभी एक विनाशकारी निर्देश के रूप में वापस मुड़ने से रोकता है।
