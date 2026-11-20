# Architecture

VDLU के दो पहलू हैं जो बीच में एक चीज़ से जुड़े हैं। PC पर, [[Producer]] एक module tree को एक signed, content-addressed feed में बदल देता है। device पर, [[Engine]] उस feed को पढ़ता है, पता लगाता है कि क्या बदला, और उसे लागू करता है। इन दोनों के बीच की सीम (seam) है **signed manifest plus the blob store** (the [[Feed Format]])। इसके अलावा और कुछ भी इस खाई को पार नहीं करता।

```
        PC / release host                                device
  +--------------------------+                 +---------------------------+
  |  Producer                |                 |  Engine  (update.sh)      |
  |  vdlu-pack  -> manifest  |    signed       |  POSIX sh, no jq          |
  |  vdlu-sign  -> sig       |    feed         |  DIFF FETCH APPLY COMMIT  |
  |  vdlu-gc    -> prune     | =============>  |  journal + rollback       |
  +--------------------------+   manifest.json |  ed25519-mini verify      |
                                 blobs/<sha>   +-------------+-------------+
                                                             |
                                                       +-----v------+
                                                       |  WebUI     |
                                                       |  Updates   |
                                                       |  panel     |
                                                       +------------+
```

दोनों पहलू कभी एक runtime साझा नहीं करते। Producer `python3` और `openssl` इस्तेमाल करता है; Engine शुद्ध POSIX `sh` है, toybox और एक embedded `ed25519-mini` के साथ। वे सिर्फ इसलिए सहमत होते हैं क्योंकि दोनों एक manifest से **वही canonical bytes** निकालते हैं (देखें [[Security and Trust Model]])। WebUI एक पतला, vanilla-JS panel है जो root-manager bridge के ऊपर engine को चलाता है और उसकी progress journal पढ़ता है; इसके पास अपना कोई update logic नहीं है। देखें [[WebUI]]।

## दो पहलू (The two sides)

| पहलू | कहाँ चलता है | किससे बना | काम |
|---|---|---|---|
| [[Producer]] | PC / CI | `python3` + `sh` + `openssl` | module tree को `manifest.json` + `blobs/` में walk करना, उसे sign करना, orphans prune करना |
| [[Engine]] | device | POSIX `sh` + toybox + `ed25519-mini` | इंस्टॉल किए हुए tree को feed के विरुद्ध diff करना, deltas fetch करना, apply करना, commit करना |
| [[WebUI]] | device (webview) | vanilla JS/CSS | updates trigger करना, progress दिखाना, config edit करना, reboot banner दिखाना |

## Update pipeline

हर update एक transaction है, जो एक तय क्रम में चलता है:

```
  DIFF  ------>  FETCH  ------>  APPLY  ------>  COMMIT
  read feed      download        write live     re-hash all,
  + validate     only missing    files now,      promote target
  + plan         blobs, verify   stage reboot     -> current,
  (no changes)   each sha256     ones             DONE or
                                                  PENDING_REBOOT
```

- **DIFF** (`update.sh check` यही phase है, read-only)। Engine सिर्फ manifest डाउनलोड करता है, कुछ भी छूने से **पहले** हर field पर `validate_plan()` चलाता है, फिर एक per-file plan बनाने के लिए feed की `current.json` से तुलना करता है। यह disk पर कुछ नहीं बदलता। feed से आगे वाला device एक सौम्य "ahead" परिणाम है, कोई error नहीं।
- **FETCH.** सिर्फ उन्हीं blobs को डाउनलोड करता है जो plan में गायब हैं, `<sha>.part` में, `gz` को decompress करता है, manifest के विरुद्ध `sha256sum` जाँचता है, और हर verified blob को atomically cache में `mv` कर देता है। पहले से cached (या किसी अनबदली local file से seed किया गया) blob skip कर दिया जाता है, तो एक revert या एक shared file की कोई कीमत नहीं पड़ती। एक ही blob पर तीन विफलताएँ phase को बिना कुछ apply किए abort कर देती हैं। network policy द्वारा रोका गया एक download एक error के बजाय `DEFERRED` (resumable) के रूप में निकलता है।
- **APPLY.** सामान्य (`live` / `soft`) फाइलें अभी लिखी जाती हैं: `rollback/<v>/` में backup, एक `.vdlu-tmp` लिखना, `chmod`, verify, फिर target के ऊपर atomic `rename`। Reboot-class फाइलें `staged/<path>.vdlu-new` में materialize की जाती हैं और live inode को नहीं छुआ जाता। एक `delete[]` entry का backup लिया जाता है, फिर हटाया जाता है। हर कदम idempotent है: पहले से target hash पर मौजूद file skip कर दी जाती है।
- **COMMIT.** हर live file को re-hash करता है; सिर्फ तभी जब सब कुछ मेल खाता है, engine `target.json` को `current.json` में promote करता है। अगर कुछ भी staged हुआ, तो transaction `PENDING_REBOOT` में समाप्त होता है; वरना `DONE`।

## Content-addressed manifest और blobs

feed content-addressed है: manifest **पूरे** target tree को सूचीबद्ध करता है, हर file अपने `sha256` से ढोई जाती है, और blob store हर अलग content की एक प्रति `blobs/<sha256>` (या `blobs/<sha256>.gz`) के नीचे रखता है।

- **Dedup.** tree में कहीं भी, या releases के पार, एक समान content एक ही blob है। Publishing incremental है: जिस blob का `sha256` host पर पहले से मौजूद है वह कभी दोबारा push नहीं होता, और device कभी वह content दोबारा fetch नहीं करता जो उसके पास पहले से है।
- **sha256 मूल (original) का होता है.** hash हमेशा uncompressed content को नाम देता है; `enc` (`raw` या `gz`) सिर्फ यह दर्ज करता है कि वह एक blob कैसे संग्रहीत किया गया है। device `gz` को toybox `gunzip` से decompress करता है, तो कोई अतिरिक्त compressor bundle नहीं किया जाता।
- **Flavor-stable.** क्योंकि device उसके विरुद्ध diff करता है जो असल में इंस्टॉल है, feed एक पूरे module family को ढो सकता है; हर install सिर्फ वही blobs खींचता है जो उसके अपने flavor को पूरा करते हैं।

पूरा field-दर-field layout [[Feed Format]] में है।

## Resumable journal

हर transaction crash-safe है क्योंकि उसकी progress एक journal (`journal.json`) में रहती है, और in-flight transaction का pinned target `target.json` में रहता है। state machine एक तय क्रम में चलती है:

```
PLANNED -> FETCHING -> FETCHED -> APPLYING -> APPLIED_LIVE -> ( PENDING_REBOOT | DONE )
                                                               \-> ERROR / DEFERRED
```

| State | अर्थ |
|---|---|
| `PLANNED` | Plan बन गया, अभी तक कुछ fetch नहीं हुआ |
| `FETCHING` / `FETCHED` | blobs डाउनलोड हो रहे / सारे blobs मौजूद और verified |
| `APPLYING` / `APPLIED_LIVE` | files लिखी जा रहीं / सारी live files लिख गईं |
| `PENDING_REBOOT` | एक reboot-class file staged है, boot swap का इंतज़ार कर रही है |
| `DONE` | हर चीज़ का re-hash मेल खा गया; `current.json` promote हुआ |
| `ERROR` | Hard failure; module uncorrupted छोड़ा गया, live files `rollback/` से वापस लाई गईं |
| `DEFERRED` | network policy द्वारा download रोका गया; plan बना रहता है, बाद में resume होता है |

`DONE` **सिर्फ** तभी पहुँचा जाता है जब हर चीज़ का re-hash मेल खाता है, तो journal कभी यह दावा नहीं करता कि एक आधा-लागू किया गया update पूरा है। एक crash, एक टूटा network, या बीच में एक reboot एक resumable journal छोड़ता है; `update.sh resume` (या `boot`) मौजूदा phase से उठा लेता है। command set और on-device state files के लिए देखें [[Engine]]।

## Atomicity और rollback

किसी चीज़ को कभी जगह पर overwrite नहीं किया जाता और कुछ भी खोया नहीं जाता:

- **Atomic writes.** हर file एक temp (`.vdlu-tmp`) और एक atomic `rename` / `mv` के ज़रिए उतरती है, तो एक reader कभी आधी-लिखी हुई file नहीं देखता।
- **Overwrite से पहले Backup.** पिछला content `rollback/<version>/<path>` में जाता है इससे पहले कि नई file उसके ऊपर rename हो (पिछली कुछ versions रखी जाती हैं)। अगर एक apply विफल होता है, तो live files को corrupt छोड़ने के बजाय rollback प्रति से वापस लाया जाता है। एक विफल backup, बिना safety net के overwrite करने के बजाय apply को **abort** कर देता है।
- **Serialized.** एक `mkdir`-आधारित lock (`lock.d/`, क्योंकि toybox पर `flock` अव्यवहार्य है, PID द्वारा stale recovery के साथ) एक साथ चलने वाले runs को serialize करता है।

## Reboot-free सिद्धांत

अधिकांश files module के live रहते हुए swap की जा सकती हैं, तो VDLU उन्हें तुरंत लागू करता है। सिर्फ तीन classes को reboot चाहिए, क्योंकि एक live process उन्हें पहले ही map कर चुका है: एक `.so` (Zygisk द्वारा लोडेड), एक `/system` overlay, और एक `sepolicy.rule`। वे **staged होती हैं, कभी live inode के ऊपर नहीं लिखी जातीं**, और अगले boot पर एक pre-zygote step में swap होती हैं। पूरी taxonomy और boot flow [[Reboot Handling]] में हैं।

## Fail-closed trust posture

feed ही एकमात्र चीज़ है जो PC से device तक पार करती है, तो engine उसके हर byte को hostile मानता है। `validate_plan()` DIFF phase में चलता है, किसी भी download से पहले, और किसी भी malformed field पर पूरे manifest को अस्वीकार कर देता है। Signature verification एक embedded `ed25519-mini` इस्तेमाल करता है (device पर कोई `openssl` नहीं), private key कभी किसी device या CI को नहीं छूती, और `hardened` profile inversion से fail-closed है ताकि एक corrupt profile value कभी चुपचाप एक unsigned feed स्वीकार न कर सके। पूरा model, दोनों profiles, और हर एक जिस threat का जवाब देता है, वे [[Security and Trust Model]] में हैं।
