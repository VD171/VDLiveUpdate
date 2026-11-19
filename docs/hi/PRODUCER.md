> **Languages:** [English](../PRODUCER.md) · [العربية](../ar/PRODUCER.md) · [Čeština](../cs/PRODUCER.md) · [Deutsch](../de/PRODUCER.md) · [Español](../es/PRODUCER.md) · [فارسی](../fa/PRODUCER.md) · [Français](../fr/PRODUCER.md) · हिन्दी · [Bahasa Indonesia](../id/PRODUCER.md) · [Italiano](../it/PRODUCER.md) · [日本語](../ja/PRODUCER.md) · [한국어](../ko/PRODUCER.md) · [Nederlands](../nl/PRODUCER.md) · [Polski](../pl/PRODUCER.md) · [Português](../pt/PRODUCER.md) · [Русский](../ru/PRODUCER.md) · [Svenska](../sv/PRODUCER.md) · [ไทย](../th/PRODUCER.md) · [Türkçe](../tr/PRODUCER.md) · [Українська](../uk/PRODUCER.md) · [Tiếng Việt](../vi/PRODUCER.md) · [中文](../zh/PRODUCER.md)

---

# VDLU producer + हस्ताक्षर परत

एक मॉड्यूल के लिए content-addressed delivery (manifest + blobs) बनाता है और इसे हस्ताक्षरित करता है।
[`INTERFACES.md`](INTERFACES.md) §3/§6/§7 के अनुरूप।

| tool | किस पर चलता है | भाषा | काम |
|---|---|---|---|
| `producer/vdlu-pack` | PC / CI | python3 | अंतिम मॉड्यूल वृक्ष को walk करता है -> `manifest.json` + `blobs/` |
| `producer/vdlu-keygen` | PC | sh + openssl | ed25519 keypair (`<id>.pem` priv, `<id>.pub` PEM, slim keyring के लिए `<id>.pub.raw` RAW 32B) |
| `producer/vdlu-sign` | PC | sh + openssl | एक manifest में `key_id` + `sig` इंजेक्ट करता है, in place |
| `engine/vdlu-verify` | **डिवाइस** | sh + ed25519-mini | अंतर्निहित ed25519-mini के माध्यम से `sig` सत्यापित करता है; keyring = RAW 32B pubkey (डिवाइस पर कोई openssl नहीं) |

## Pipeline

```sh
# 1. one-time: a signing key. Keep the .pem off every device and off any repo push.
producer/vdlu-keygen release-2026 ./keys

# 2. each release: pack the final tree (same tree the .zip ships, post-whitelist).
producer/vdlu-pack  ./module_tree  ./out  demo 106 --version-name v106 --channel stable \
                    [--prev ./prev/manifest.json]      # delete[] = paths gone since prev

# 3. sign the manifest in place.
producer/vdlu-sign  ./out/manifest.json  ./keys/release-2026.pem  release-2026

# 4. publish ./out/{manifest.json,blobs/} to <source> (Pages batch for public; rsync for private).
#    The slim device keyring holds ./keys/release-2026.pub.raw as keyring/release-2026.pub (RAW 32B).
```

`vdlu-pack` content-addressed और deduplicating है: एक blob जिसका `<sha256>` पहले से मौजूद है, पुनः नहीं लिखा जाता,
इसलिए प्रकाशन incremental है और अपरिवर्तित / वापस की गई सामग्री कभी पुनः push नहीं की जाती।

### `enc` निर्णय (vdlu-pack)

`sha256` **हमेशा** मूल (असंपीड़ित) सामग्री का होता है; `enc` केवल यह नाम देता है कि blob कैसे संग्रहीत किया जाता है।

- `gz` जब `size >= 4096` **और** gzip (`-9 -n`, नियतात्मक) कम से कम 10% बचाता है (`comp <= raw*0.90`)।
- `raw` अन्यथा (छोटा टेक्स्ट जिसे HTTP gzip पहले से कवर करता है, या पहले से असंपीड्य डेटा)।
- build host पर gzip गायब -> सब कुछ `raw` (कभी विफल नहीं होता)।

एक blob एक बार, एक प्रारूप में संग्रहीत होता है: `blobs/<sha256>` (raw) या `blobs/<sha256>.gz` (gz)। डिवाइस
toybox `gunzip` (हमेशा मौजूद) के साथ डीकंप्रेस करता है, इसलिए कोई zstd बंडल नहीं किया जाता।

### `class` निर्णय (vdlu-pack) - reboot वर्गीकरण

path से व्युत्पन्न (INTERFACES §3, doc §4)। केवल डिफ़ॉल्ट; एक path नियम कभी `reboot`->`live` डाउनग्रेड नहीं करता।

| class | किससे मेल खाता है | लागू |
|---|---|---|
| `reboot` | `system/**`, `zygisk/**/*.so`, `*.rule` | staged `.vdlu-new`, boot पर swap |
| `soft` | root `service.sh` / `post-fs-data.sh` / `boot-completed.sh` | live लिखा गया, अगले boot पर चलता है |
| `live` | बाकी सब कुछ (webroot, bin, lib, confs, module.prop, ...) | live लिखा गया, atomic |

Symlinks का **अनुसरण नहीं किया जाता** (वृक्ष के बाहर से सामग्री कभी लीक नहीं करता, उदा. `/etc/shadow` का एक link)
और एक चेतावनी के साथ छोड़ दिए जाते हैं, क्योंकि manifest स्कीमा में कोई symlink प्रकार नहीं है।
गैर-नियमित फ़ाइलें (dirs, fifos, devices) छोड़ दी जाती हैं। `built` पुनरुत्पादनीय manifests के लिए
`SOURCE_DATE_EPOCH` का सम्मान करता है।

### Baseline (इंस्टॉल seed) - अहस्ताक्षरित, keyless

`baseline.json` (मॉड्यूल zip में `vdlu/baseline.json` पर भेजा गया) एक नए इंस्टॉल पर `current.json` को seed करता है
ताकि डिवाइस "वर्तमान" पैदा हो (कोई from:0 नहीं, कोई re-fetch नहीं)। Engine इसे एक **स्थानीय विश्वसनीय seed** के रूप में मानता है
(यह flash की गई zip में आया, जो इंस्टॉल विश्वास सीमा है) और इसके **हस्ताक्षर को सत्यापित नहीं करता** -
केवल feed से FETCH किया गया manifest `vdlu-verify` से गुज़रता है। इसलिए baseline को **किसी कुंजी की आवश्यकता नहीं**: यह
बस भेजे गए वृक्ष पर `vdlu-pack` का आउटपुट है (अहस्ताक्षरित; `sig`/`key_id` खाली रहते हैं)। इसलिए एक CI इसे
**keyless** उत्पन्न कर सकता है, हस्ताक्षर कुंजी को CI से 100% बाहर रखते हुए - केवल प्रकाशित FEED हस्ताक्षरित होता है (ऑपरेटर,
स्थानीय रूप से)। `vdlu-pack` अपने स्वयं के manifest से `baseline.json` को बाहर करता है (anti स्व-संदर्भ)। अनुपस्थित होने पर
गैर-घातक: डिवाइस बस पहले अपडेट पर from:0 से शुरू होता है, कभी टूटा नहीं।

## कैनोनिकलीकरण (अभिसरण बिंदु)

`vdlu-sign` और `engine/vdlu-verify` को एक manifest से **समान बाइट्स** व्युत्पन्न करनी चाहिए, दो
विभिन्न रनटाइम पर (PC openssl बनाम device toybox + openssl)। यह नियम जानबूझकर एक बाइट
रूपांतरण है, JSON पुनः-serialization नहीं, ताकि इसे डिवाइस पर किसी JSON लाइब्रेरी की आवश्यकता न हो:

1. `vdlu-pack` `manifest.json` को **कॉम्पैक्ट, कुंजियाँ क्रमबद्ध, UTF-8** लिखता है
   (`json.dumps(obj, sort_keys=True, separators=(",",":"), ensure_ascii=False)`), हमेशा
   `key_id` और `sig` फ़ील्ड शामिल करता है (हस्ताक्षरित होने तक खाली स्ट्रिंग प्लेसहोल्डर)। यह कैनोनिकल भंडारण
   रूप है।
2. **कैनोनिकल रूप = वह टेक्स्ट जिसमें `"sig"` फ़ील्ड हटा दिया गया हो।** चूँकि कुंजियाँ क्रमबद्ध हैं, `sig`
   हमेशा `,"sig":"<value>",` के रूप में प्रकट होता है, जो `"schema"` (पहले) और `"version"` (बाद में) के बीच घिरा होता है,
   दोनों हमेशा मौजूद। इसे हटाने से सुव्यवस्थित `...,"schema":N,"version":...` बचता है।
   JSON स्ट्रिंग मानों के भीतर प्रत्येक `"` को `\"` में escape करता है, इसलिए संरचनात्मक टोकन `"sig":"`
   एक ऐसे filename के विरुद्ध भी असंदिग्ध है जिसमें शाब्दिक रूप से `"sig":"` हो (परीक्षित)।
3. हस्ताक्षरित/सत्यापित संदेश कैनोनिकल रूप का **sha256 hex** है (64 ASCII वर्ण, कोई newline नहीं)।
   उस hex पर ed25519 (`openssl pkeyutl -sign/-verify -rawin`)।

POSIX sh में हटाना (दोनों tools में समान फ़ंक्शन, कोई `sed`/`jq` नहीं):

```sh
# $1 = full manifest text (trailing newline already stripped by $(cat ...))
_pre=${_c%%\"sig\":\"*}     # up to  ...,"schema":N,
_rest=${_c#*\"sig\":\"}      # after "sig":"
_tail=${_rest#*\",}          # after <value>",  ->  "version":...
printf '%s%s' "$_pre" "$_tail" | sha256sum | cut -d' ' -f1
```

`key_id` कैनोनिकल रूप का हिस्सा है (केवल `sig` हटाया जाता है); `vdlu-sign` हैशिंग से **पहले** `key_id` सेट करता है।
मान प्लेसहोल्डर खाली (`"sig":""`, sign समय) या भरा (verify समय) होने पर समान कैनोनिकल बाइट्स उत्पन्न करता है,
इसलिए sign और verify निर्माण द्वारा सहमत होते हैं।

Python इसे `re.sub(r'"sig":"[^"]*",', '', text.rstrip("\\n"), count=1)` फिर sha256 के रूप में पुनरुत्पादित करता है - केवल
cross-check के लिए उपयोग किया जाता है; आधिकारिक producers दो sh tools हैं।

## हस्ताक्षर (ed25519)

- `vdlu-keygen` (PC): `openssl genpkey -algorithm ed25519` (priv `0600`) + `openssl pkey -pubout` (pub **PEM**,
  हस्ताक्षर/openssl के लिए) + `openssl pkey -pubout -outform DER | tail -c 32` -> **`.pub.raw` (RAW 32B)** (ed25519
  SPKI DER एक 12-बाइट उपसर्ग + 32-बाइट कुंजी है, इसलिए `tail -c 32` ही कुंजी है)। यह दोनों उत्सर्जित करता है।
- `vdlu-sign` (PC): कैनोनिकल sha256 hex पर `openssl pkeyutl -sign -rawin`; हस्ताक्षर base64 में संग्रहीत।
- `vdlu-verify` (**डिवाइस, slim**): `ed25519-mini <pubkey32> <msg> <sig64>` - keyring को **RAW 32B** pubkey के रूप में
  पढ़ता है, डिवाइस पर कोई openssl नहीं। `key_id` path-sanitized है (कोई `/`, `.`, `..`, `"` नहीं)। 🚨 keyring
  **`.pub.raw` (32B)** भेजता है, कभी `.pub` PEM (113B) नहीं: PEM केवल PC-side है और `ed25519-mini` इसे नहीं पढ़ सकता।

विश्वास मॉडल (INTERFACES §6, doc §11/§13): `profile=hardened` (सार्वजनिक) verify को अनिवार्य बनाता है - एक
विफल या गायब हस्ताक्षर अपडेट को abort करता है। `profile=trusted` (निजी, SSH-staged स्रोत) verify को
best-effort के रूप में मानता है, लेकिन हर blob का sha256 तब भी जाँचा जाता है।

## Keyring + rotation

keyring `<key_id>.pub` फ़ाइलों की एक डायरेक्टरी है, प्रत्येक **RAW 32B** ed25519 pubkey (`keygen` के `.pub.raw` से),
PEM नहीं - `ed25519-mini` raw 32 बाइट्स पढ़ता है। वर्तमान **और** पिछली raw pubkey भेजें
(doc §13) ताकि एक rotate की गई कुंजी पुराने इंस्टॉल को brick न करे। नए `key_id` के साथ `vdlu-sign` और डिवाइस का
`<keyring>/<key_id>.pub` (raw) चुनना ही पूरा rotation तंत्र है - कोई engine बदलाव नहीं। keyring release के पार
**स्थिर** है (केवल key rotation इसे बदलता है): एक re-vendor को इसे **verify-not-copy** करना चाहिए, और इसे कभी
PC-side `.pub` PEM से अधिलेखित नहीं करना चाहिए।

<!-- doc-footer -->

---

> _यह दस्तावेज़ Claude (Anthropic) से तैयार किया गया है और इसे VD171 द्वारा अनुरक्षित किया जाता है। सुधार और संशोधन का स्वागत है; देखें [CONTRIBUTING.md](CONTRIBUTING.md)।_
