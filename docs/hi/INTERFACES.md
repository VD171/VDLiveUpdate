> **Languages:** [English](../INTERFACES.md) · [العربية](../ar/INTERFACES.md) · [Čeština](../cs/INTERFACES.md) · [Deutsch](../de/INTERFACES.md) · [Español](../es/INTERFACES.md) · [فارسی](../fa/INTERFACES.md) · [Français](../fr/INTERFACES.md) · हिन्दी · [Bahasa Indonesia](../id/INTERFACES.md) · [Italiano](../it/INTERFACES.md) · [日本語](../ja/INTERFACES.md) · [한국어](../ko/INTERFACES.md) · [Nederlands](../nl/INTERFACES.md) · [Polski](../pl/INTERFACES.md) · [Português](../pt/INTERFACES.md) · [Русский](../ru/INTERFACES.md) · [Svenska](../sv/INTERFACES.md) · [ไทย](../th/INTERFACES.md) · [Türkçe](../tr/INTERFACES.md) · [Українська](../uk/INTERFACES.md) · [Tiếng Việt](../vi/INTERFACES.md) · [中文](../zh/INTERFACES.md)

---

# VDLU - इंटरफ़ेस अनुबंध (घटकों के बीच की सीवन)

**अभिसरण का नियम:** हर घटक इस फ़ाइल के अनुरूप होता है। 4 एजेंटों के टुकड़ों को **एक-दूसरे में फ़िट होना** चाहिए - नीचे दिए गए
CLI हस्ताक्षर, फ़ाइल नाम और JSON कुंजियाँ **अपरिवर्तनीय** हैं (बदलाव का अर्थ है पहले यहाँ संरेखण करना)।

रिपॉज़ से विरासत में मिले सिद्धांत: डिवाइस पर **शुद्ध POSIX sh** (कोई bashism नहीं, toybox/busybox +
toybox के `sha256sum`/`gzip`/`base64` + fetch किया गया `curl` + अंतर्निहित `ed25519-mini` के साथ चलता है - दुबला, कोई बाइनरी
बंडल नहीं), **शून्य व्यर्थ टिप्पणियाँ**, **हमेशा release**, **विफलता पर कठोरता** (पुनः आरंभ करने योग्य ट्रांज़ैक्शन, कुछ भी
झूठा "पूर्ण" नहीं, कुछ भी खोया नहीं), **कुछ भी ढीला नहीं**।

---

## 1. State का लेआउट (Tier-2, मॉड्यूल डायरेक्टरी के बाहर)

```
$VDLU_DIR = /data/adb/<module>/vdlu
  config               # key=value (§5)
  current.json         # manifest of the ACTIVE version (diff base); absent = never updated
  journal.json         # transaction in progress (§4); absent = idle
  cancel               # presence = cancel request (WebUI creates it; engine deletes it on stop)
  lock.d/              # mkdir-lock (flock unworkable on toybox; stale-recovery by PID)
  blobs/<sha256>       # cache of verified blobs (ORIGINAL content, already decompressed)
  rollback/<version>/<path>   # backup of overwritten files
  staged/<path>.vdlu-new      # REBOOT-hard awaiting swap at boot
  target.json          # PINNED manifest of the in-flight transaction (presence = active transaction; becomes current.json on DONE)
  plan.tsv  plan.del   # engine's internal plan (progress); the WebUI IGNORES it (reads only journal/config/current)
```
journal में `cancelled:true` = engine एक cancel पर रुका (एक गैर-टर्मिनल, पुनः आरंभ करने योग्य state, `error`
null ही रहता है)।

मॉड्यूल में vendor किया गया engine: `$MODULE_DIR/vdlu/update.sh` (+ `vdlu-verify`)। `$MODULE_DIR =
/data/adb/modules/<module>`। Engine env के माध्यम से प्राप्त करता है: `VDLU_DIR`, `MODULE_DIR`, `MODID`।

## 2. Engine CLI (ENGINE घटक)

`sh update.sh <cmd>` - rc 0 = ठीक, !=0 = त्रुटि (stderr में कारण होता है):

| cmd | करता है |
|---|---|
| `check` | DIFF: manifest डाउनलोड करता है, तुलना करता है; एक 1-पंक्ति JSON `{"update":bool,"from":N,"to":M,"fetch":K,"reboot":bool}` प्रिंट करता है; कुछ नहीं बदलता। डिवाइस feed से आगे (downgrade अवरुद्ध, hardened) = एक सौम्य state: `{"update":false,"ahead":true,"from":N,"to":M}` + rc0 (कभी "check failed" नहीं)। do_diff rc: 2 fetch/parse, 3 verify/meta, 4 ahead |
| `run` | पूर्ण चक्र: DIFF->FETCH->APPLY->COMMIT; `cancel` का सम्मान करता है; प्रगति `journal.json` में लिखता है; LIVE लागू करता है, REBOOT-hard को stage करता है |
| `resume` | `journal.json` ट्रांज़ैक्शन को वर्तमान चरण से पुनः आरंभ करता है (idempotent) |
| `boot` | pre-zygote मोड: `resume` + `staged/*.vdlu-new` का SWAP करता है (`.so` लागू करता है), `PENDING_REBOOT`->`DONE` बंद करता है |
| `status` | `journal.json` प्रिंट करता है (या `{"state":"idle"}`) |
| `cancel` | `$VDLU_DIR/cancel` बनाता है (चल रहा एक `run` अगले सुरक्षित बिंदु पर रुकता है) |

Blob/manifest स्रोत: config से `source`। `<source>` + `/manifest.json`, `/blobs/<sha>`, `/blobs/<sha>.gz`।
`source` `https://` से शुरू होता है (static curl fetch किया गया, TLS) या `file://` से (स्थानीय staging)।

## 3. manifest.json (PRODUCER द्वारा उत्पादित, ENGINE द्वारा उपभोग किया गया)

```json
{ "schema":1, "module":"<id>", "version":<int>, "version_name":"<str>", "built":"<ISO8601>",
  "engine_min":5, "key_id":"<str>", "channel":"stable",
  "files":[ {"path":"webroot/index.html","sha256":"<hex64>","size":<int>,"mode":"0644","enc":"raw|gz","class":"live|soft|reboot"} ],
  "delete":["<path>"], "sig":"<base64>" }
```

- `files[]` = संपूर्ण लक्ष्य वृक्ष। `class`: `live` (webroot/bin/lib/confs/scripts-on-demand/module.prop) ·
  `soft` (service.sh/post-fs-data.sh/boot-completed.sh) · `reboot` (`zygisk/**/*.so`, `system/**`, `*.rule`)।
  path द्वारा डिफ़ॉल्ट, कभी `reboot`->`live` डाउनग्रेड नहीं करता।
- `enc`: `gz` (gzip `-9 -n`, नियतात्मक, डिवाइस पर toybox gunzip) केवल तब जब यह अच्छी तरह संपीड़ित होता है और
  आकार महत्वपूर्ण होता है, `sha256` हमेशा मूल सामग्री का होता है।
- `sig`: `sig` फ़ील्ड के बिना कैनोनिकल manifest का हस्ताक्षर (verify का §4)।
- **Trust-anchor exclusion (engine-side, VDLU#2):** engine plan से `vdlu/` के नीचे किसी भी `files[]`/`delete[]` path (इसके अपने `update.sh`/`vdlu-verify`/`verify/*`/`keyring/*`/config) को गिरा देता है - कभी fetch, apply, या delete नहीं - भले ही एक signed feed उन्हें ढोए। on-device trust anchor सिर्फ एक पूर्ण signed re-flash से बदलता है, wire पर नहीं, `vdlu-pack` भी `vdlu/` को producer-side बाहर करता है, तो यह एक leak हुई signing key के विरुद्ध एक दूसरा, engine-side guard है।

## 4. journal.json (ENGINE लिखता है, WEBUI पढ़ता है - प्रगति अनुबंध)

```json
{ "schema":1, "module":"<id>", "target":<version>, "from":<version>,
  "phase":"diff|fetch|apply|commit", "state":"PLANNED|FETCHING|FETCHED|APPLYING|APPLIED_LIVE|PENDING_REBOOT|DONE|ERROR|DEFERRED",
  "total":<int>, "done":<int>, "current":"<path>", "bytes":<int>, "reboot_pending":bool,
  "cancelled":bool, "error":"<str|null>", "updated":"<ISO8601>",
  "items":[ {"path":"<p>","sha256":"<h>","class":"<c>","st":"pending|fetched|applied|staged|skipped"} ] }
```

State मशीन (निश्चित क्रम): `PLANNED->FETCHING->FETCHED->APPLYING->APPLIED_LIVE->(PENDING_REBOOT|DONE)`।
`DONE` केवल तब जब सब कुछ का पुनः-हैश मेल खाता है। एक stage किया गया REBOOT-hard ⇒ `PENDING_REBOOT` (`DONE` नहीं)। `fetch`
चरण से निकास: `ERROR` (कठोर विफलता) या `DEFERRED` (net_policy ने डाउनलोड अवरुद्ध किया - सौम्य/पुनः आरंभ करने योग्य,
कोई त्रुटि नहीं)।

## 5. config (key=value, प्रति पंक्ति एक, WEBUI में संपादन योग्य)

```
auto_on_webui_open=0
auto_on_reboot=1
source=https://<user>.github.io/<repo>/<module>
channel=stable
profile=trusted        # trusted | hardened. CODE DEFAULT (line absent) = hardened (fail-closed, 9a9a824)
net_policy=any         # any (Wi-Fi+mobile) | wifi (Wi-Fi only) | mobile (mobile only) - gates the DOWNLOAD by network type
allow_metered=0        # ⚠️ SUPERSEDED by net_policy (not consumed by the engine)
pubkey_dir=keyring     # relative to $MODULE_DIR/vdlu (keyring of pubkeys for verify)
key_id=                # ALLOWLIST of accepted MODULE-UPDATE signing key id(s), comma-separated (rotation).
                       # UNSET = default-safe: a single-key keyring accepts only that one key; a MULTI-key
                       # keyring (one that also ships a fingerprint-feed key) MUST pin its module key here.
ca_path=               # empty = auto-detect of the Android trust store; set a path to override
ca_cert=               # empty = auto-build a CA bundle from the trust store; set a path to a bundle to override
tools_source=          # empty = derived from source (.../vdlu-tools); feed of the static curl
apply_busy_file=       # OPT-IN: absolute path the host module touches during its own operations (e.g. a
                       # backup). While it EXISTS, APPLY is deferred to the next trigger (blobs already
                       # fetched, no re-download) so an update never swaps module files mid-operation. UNSET = off.
boot_retry_interval=30 # seconds between probes when BOOT finds the device offline (floor 5s)
boot_retry_minutes=0   # ceiling of the PATIENT retry (AWAKE-time) only at boot; 0 = off. Battery-safe (no wakelock,
                       # no held lock, route probe never wakes the radio) -> a generous ceiling is ~free
```

**Boot retry (offline) - धैर्यवान, बैटरी-सुरक्षित:** केवल `boot` पर (कभी check/auto-open पर नहीं)। यदि manifest
fetch नेटवर्क के कारण विफल होता है (`fetch_offline` fetcher के exit द्वारा वर्गीकृत करता है), तो यह प्रतीक्षा करता है और सफलता तक
पुनः प्रयास करता है या `boot_retry_minutes` का AWAKE-समय समाप्त होने तक। एक ऐसा डिज़ाइन जो **कुछ नहीं पकड़े रहता और बैटरी नहीं खींचता**:
- **शून्य wakelock:** प्रयासों के बीच यह `sleep` है, जो deep-sleep में जम जाता है -> डिवाइस सामान्य रूप से सोता है
  (~शून्य बैटरी), retry रुक जाता है और डिवाइस के पहले से जागे होने पर फिर से शुरू होता है।
- **शून्य पकड़ा हुआ lock:** प्रयासों के बीच `acquire_lock_try`+release (प्रतीक्षा के दौरान lock नहीं पकड़े रहता) ->
  `run`/मैन्युअल check कभी अवरुद्ध नहीं होते, यदि इस बीच कोई मैन्युअल run एक TARGET stage करता है, तो boot स्थगित कर देता है।
- **व्यर्थ में radio नहीं जगाता:** एक `net_allowed` probe (`net_type`/`ip route get` के माध्यम से, एक kernel route
  lookup जो Android की policy-routing का सम्मान करता है, कोई packet नहीं) हर प्रयास को नियंत्रित करता है - यह केवल तब एक fetch खर्च करता है जब
  नेटवर्क प्रकट हो गया हो।
- एक नियतात्मक विफलता (manifest/sig/downgrade) को कभी पुनः प्रयास नहीं करता। fetch पर `--connect-timeout 15` (captive portal पर
  अटकता नहीं)। `service.sh` इसे background में डालता है (boot कभी अटकता नहीं)।
- ⛔ **HARD: `boot_retry_minutes>0` चालू करने के लिए धैर्यवान engine आवश्यक है** (वह जिसमें
  `net_allowed`+`acquire_lock_try` है, कैनोनिकल `da7115f4`+)। पिछला boot-retry (पूरी विंडो के दौरान lock पकड़े रहता है +
  अंधाधुंध curl offline पुनः प्रयास करता है) **बैटरी खींचता है/radio जगाता है** - पुराने engine में retry चालू करना
  एक आत्मघाती कदम है। इसे सक्षम करते समय, वर्तमान engine को vendor करें।

**`net_policy` (any|wifi|mobile):** नेटवर्क प्रकार द्वारा **डाउनलोड** को नियंत्रित करता है। `net_type()` `ip route get`
के egress को वर्गीकृत करता है (सेल्युलर iface `rmnet/ccmni/v4-*/clat` = mobile, बाकी सब = wifi, kernel lookup, कोई
packet नहीं)। `net_allowed()` `net_policy` से तुलना करता है और `do_fetch` (blobs) + धैर्यवान boot-retry probe
को नियंत्रित करता है। **manifest check मुक्त रहता है** (छोटा -> UI किसी भी नेटवर्क पर अपडेट की रिपोर्ट करता है), केवल डाउनलोड
अनुमत नेटवर्क की प्रतीक्षा करता है। एक गैर-अनुमत नेटवर्क पर डाउनलोड = journal में **`DEFERRED`** state
(ERROR नहीं, एक कोमल नीला INFO toast "X नेटवर्क की प्रतीक्षा में", plan/target बने रहते हैं, यह सही नेटवर्क पर अगले
check/boot पर पुनः आरंभ होता है)। `net_policy` `allow_metered` को **अधिक्रमित करता है** (जो कभी उपभोग नहीं किया गया)।
Engine `97baf887`+ (`file://` को कभी नियंत्रित नहीं किया जाता)।

## 6. हस्ताक्षर (PRODUCER PC पर openssl के माध्यम से हस्ताक्षर करता है, ENGINE डिवाइस पर ed25519-mini के माध्यम से सत्यापित करता है)

- कैनोनिकलीकरण: `sig` के बिना manifest, कुंजियाँ क्रमबद्ध, कॉम्पैक्ट JSON (कोई अतिरिक्त स्थान नहीं), UTF-8।
  जो हस्ताक्षरित/सत्यापित किया जाता है = उस कैनोनिकल रूप का `sha256` hex (क्रॉस-टूल नियतात्मकता देता है)।
- `producer/vdlu-sign <manifest.json> <privkey.pem> <key_id>` -> manifest में `key_id` + `sig` (कैनोनिकल sha256 के ed25519 हस्ताक्षर का base64) इंजेक्ट करता है, in place।
- `engine/vdlu-verify <manifest.json> <keyring_dir>` -> rc 0 यदि `sig` keyring में `<key_id>.pub` pubkey से मेल खाता है
  (SLIM: pubkey **RAW 32 बाइट**)। आंतरिक रूप से, कोई openssl नहीं: toybox `sha256sum`/`base64 -d` + अंतर्निहित
  `ed25519-mini` बाइनरी (CLI `ed25519-mini <pub32> <msg> <sig64>`, rc 0=वैध/1=अमान्य/2=उपयोग)।
  rc!=0 = अस्वीकार। **`profile=hardened` ⇒ verify अनिवार्य, विफलता = abort।**
  `profile=trusted` ⇒ verify best-effort है (स्रोत पहले से SSH के माध्यम से विश्वसनीय), लेकिन हर blob का हैश हमेशा जाँचा जाता है।
- **module-update कुंजी allowlist (fail-closed, pubkey चयन से पहले):** manifest का `key_id` एक स्वीकृत MODULE-UPDATE कुंजी होना चाहिए, इससे पहले कि `<key_id>.pub` चुना जाए - config का `key_id` (§5) वही allowlist है। keyring एक कम-भरोसे वाली कुंजी भी रख सकता है (जैसे एक fingerprint-feed कुंजी, स्वचालित, अलग खाता), allowlist के बिना, उस कुंजी से हस्ताक्षरित manifest लीक होने पर सत्यापित हो जाएगा और एक पूर्ण flashless root अपडेट लागू कर देगा। `verify_manifest` इसे दोनों profiles में लागू करता है और हल किए गए सेट को env `VDLU_KEYID_ALLOW` के माध्यम से `vdlu-verify` को देता है (ताकि standalone verifier भी सहमत हो)। अनसेट डिफ़ॉल्ट-सुरक्षित है (एकल-कुंजी keyring: केवल वही कुंजी, बहु-कुंजी keyring: `key_id` पिन होने तक अस्वीकृत)। fingerprint-feed trust root एक अलग पथ है जिसकी अपनी पिन की गई कुंजी है और यह प्रभावित नहीं होता।
- `producer/vdlu-keygen <id> <out>` -> `<id>.pem` (priv) + `<id>.pub` (PEM, PC पर tooling के लिए) +
  `<id>.pub.raw` (**RAW 32B** = डिवाइस पर slim keyring का `<id>.pub`) उत्पन्न करता है। openssl `genpkey -algorithm ed25519`।

## 7. Blob - सत्यापन (ENGINE)

`<source>/blobs/<sha>` डाउनलोड करता है (या `.gz` यदि `enc=gz`), `.part` लिखता है, यदि `gz` तो डीकंप्रेस करता है (`gunzip`),
`sha256sum` == manifest के `sha256` की जाँच करता है, मेल -> `$VDLU_DIR/blobs/<sha>` में atomic `mv`। एक ही blob पर 3
विफलताएँ = चरण को abort करता है (कुछ भी लागू नहीं)। `$VDLU_DIR/blobs/<sha>` में पहले से मौजूद एक blob जिसका हैश ठीक है =
डाउनलोड छोड़ देता है।

## 8. class द्वारा APPLY (ENGINE)

- `live`/`soft`: backup `rollback/<v>/<path>` -> blob से `$MODULE_DIR/<path>.vdlu-tmp` लिखता है -> `chmod mode` ->
  लक्ष्य पर atomic `rename`। पहले से लक्ष्य हैश पर = छोड़ देता है। (Zygisk variant में लेखन mounted डायरेक्टरी में जाता है =
  प्रति-फ़ाइल merge, कभी डायरेक्टरी का `rm -rf` नहीं।)
- `reboot`: `$VDLU_DIR/staged/<path>.vdlu-new` में materialize करता है (live को स्पर्श नहीं करता)। swap `boot` पर होता है।
- `delete[]`: backup -> हटाता है।

## 9. WEBUI ↔ ENGINE (WEBUI घटक)

- चलाता है: `ksu.exec("sh $MODULE_DIR/vdlu/update.sh run")` (background)।
- प्रगति: एक हल्का poll `ksu.exec("cat $VDLU_DIR/journal.json")` हर ~1s, `{phase,state,total,done,current,bytes}` रेंडर करता है।
- Liveness: journal 8 ticks के लिए अनुपस्थित ⇒ "कोई प्रतिक्रिया नहीं"। Journal 20 ticks के लिए जमा हुआ (समान मान) ⇒ `lock.d` जाँचता है: जीवित = जारी रखता है (1 blob का धीमा fetch), मृत = त्रुटि + Resume। इसके बिना, fetch के बीच मरा एक run toast को "updating" पर जमा देगा।
- Cancel: `ksu.exec("touch $VDLU_DIR/cancel")`।
- Config: एक "Updates" tab में `$VDLU_DIR/config` (key=value) पढ़ता/लिखता है।
- Toast: बार + `phase done/total · current`, `reboot_pending` के साथ समाप्ति पर ⇒ एक स्थायी banner "reboot to activate the .so"।
- Auto-open (`auto_on_webui_open=1`): पहले एक QUIET `check()` करता है (कोई प्रगति toast नहीं), `run`+स्थायी toast केवल तब चलाता है जब `update && fetch>0`। अप-टू-डेट/ahead/कुछ-नया-नहीं = panel में एक inline परिणाम, शून्य बचा हुआ toast। मैन्युअल बटन की तरह गैर-घुसपैठी (toast केवल तब दिखता है जब एक वास्तविक डाउनलोड हो)। curl bootstrap एक-बार का है।

## 10. डेमो में एकीकरण (INTEGRATION घटक) - SNIPPETS, live फ़ाइलों को संपादित न करें

`integration/demo/` में उत्पादित करता है, snippets + एक `INTEGRATION.md` जो बताता है कि प्रत्येक कहाँ जाता है (लागू किए बिना):
- `post-fs-data`/`service.sh` में `auto_on_reboot` hook (pre-zygote -> `update.sh boot`) और `auto_on_webui_open`।
- `config` डिफ़ॉल्ट + अंतर्निहित keyring + vendoring (`modules/<mod>/vdlu/`)।
- PARTIAL variant (mounted डायरेक्टरी में merge)।

## 11. Fetch की गई toolchain + baseline (SLIM, दृष्टिकोण B)

**मॉड्यूल में लेआउट (zip):** `vdlu/{update.sh, vdlu-verify, config.default, keyring/<id>.pub (RAW 32B),
verify/<abi>/ed25519-mini, baseline.json}`। **कोई** `bin/` **नहीं** (openssl/curl/zstd)। `customize.sh` `verify/`
को डिवाइस के ABI तक छाँट सकता है (`vdlu-verify` mini को `<dir>/ed25519-mini` या `<dir>/verify/<abi>/ed25519-mini` में ढूँढता है)।

**ed25519-mini** (अंतर्निहित बाइनरी, केवल-verify): `ed25519-mini <pubkey32> <msg> <sig64>` -> rc 0=वैध,
1=अमान्य, 2=उपयोग/IO। msg = सटीक हस्ताक्षरित बाइट्स (पुनः-हैश नहीं करता)। TweetNaCl PD, static प्रति-ABI, PROVENANCE।

**tools-feed** (केवल सार्वजनिक/https प्रोफ़ाइल): `<tools_source>` पर परोसा गया (डिफ़ॉल्ट व्युत्पन्न: `source` के अंतिम खंड को
`vdlu-tools` से बदलता है, उदा. `https://<user>.github.io/<repo>/vdlu-tools`)। इसमें शामिल है:
- `tools-manifest.json` - `<abi>/curl` वृक्ष पर एक हस्ताक्षरित `vdlu-pack` manifest, प्रत्येक curl के `sha256` को
  पिन करता है (वही `release-2026` कुंजी)।
- `<abi>/curl` - RAW **static** curl (स्वयं-निहित, ~1MB, curl 8.11.1 + mbedTLS)। 🪤 mbedTLS एक CA bundle
  **नहीं** रखता: `fetch_url` `--capath` पास करता है (Android trust store का auto-detect: `/system/etc/security/cacerts`
  -> APEX conscrypt, `ca_path` अधिक्रमित करता है)। कोई capath नहीं = त्रुटि 60। अखंडता ed25519 है, cert-check गहराई-में-रक्षा है।

**install-tool** (ENGINE): `update.sh install-tool <abi>` `$VDLU_DIR/.work/{tools-manifest.json, tool.<abi>}` पढ़ता है
(WEBUI इसे `fetch()` के माध्यम से डाउनलोड करता है और वहाँ लिखता है), **tools-manifest हस्ताक्षर सत्यापित करता है (ed25519-mini,
किसी भी प्रोफ़ाइल में अनिवार्य)** + curl का हैश == manifest, और तभी इसे `$VDLU_DIR/tools/<abi>/curl` (0755) में इंस्टॉल करता है।
curl root के रूप में चलता है -> exec से पहले sig+hash RCE को बंद करता है। Tier-2 में बना रहता है: कभी पुनः डाउनलोड नहीं (uninstall को छोड़कर)।

**fetch-bootstrap** (WEBUI, `ensureToolchain()`): check/run/resume से पहले चलता है। `file://` = no-op, curl पहले से
उपलब्ध (Tier-2, या एक **self-bundled** मॉड्यूल से `module/bin/<abi>/curl`, या सिस्टम) = no-op
(VDLU मौजूदा curl का पुनः उपयोग करता है), केवल `https` **बिना किसी curl के** webview के माध्यम से curl + tools-manifest डाउनलोड करता है, उन्हें
`.work` में लिखता है (`ksu.exec` के माध्यम से chunked base64), `install-tool` को कॉल करता है। विश्वास = ऑन-डिवाइस जाँच, डाउनलोड नहीं।

> 🪤 **Slim (fetch-bootstrap) ≠ अनिवार्य।** एक मॉड्यूल जिसका `bin/` उसकी अपनी सुविधाओं के लिए मौजूद है (उदा. यह
> restic/rclone/age/tar/curl... बंडल करता है) ~2MB तक **दुबला नहीं होता** न ही curl डाउनलोड करता है - VDLU slim engine
> (gz, mini, baseline, fixes) को अपनाता है और अंतर्निहित toolchain का **पुनः उपयोग** करता है। केवल अपनी toolchain के बिना वाले मॉड्यूल
> ~2MB प्राप्त करते हैं।

**baseline.json** (from:0 का fix): release भेजे गए संस्करण के हस्ताक्षरित `manifest.json` को `vdlu/baseline.json` में
कॉपी करती है, एक नए इंस्टॉल पर engine इससे `current.json` seed करता है (`init_paths`, केवल यदि अनुपस्थित) -> डिवाइस "वर्तमान"
पैदा होता है, स्वयं के कोई auto-update के बिना और कोई re-fetch के बिना।

<!-- doc-footer -->

---

> _यह दस्तावेज़ Claude (Anthropic) से तैयार किया गया है और इसे VD171 द्वारा अनुरक्षित किया जाता है। सुधार और संशोधन का स्वागत है, देखें [CONTRIBUTING.md](CONTRIBUTING.md)।_
