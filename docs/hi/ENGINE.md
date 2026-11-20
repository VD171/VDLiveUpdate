> **Languages:** [English](../ENGINE.md) · [العربية](../ar/ENGINE.md) · [Čeština](../cs/ENGINE.md) · [Deutsch](../de/ENGINE.md) · [Español](../es/ENGINE.md) · [فارسی](../fa/ENGINE.md) · [Français](../fr/ENGINE.md) · हिन्दी · [Bahasa Indonesia](../id/ENGINE.md) · [Italiano](../it/ENGINE.md) · [日本語](../ja/ENGINE.md) · [한국어](../ko/ENGINE.md) · [Nederlands](../nl/ENGINE.md) · [Polski](../pl/ENGINE.md) · [Português](../pt/ENGINE.md) · [Русский](../ru/ENGINE.md) · [Svenska](../sv/ENGINE.md) · [ไทย](../th/ENGINE.md) · [Türkçe](../tr/ENGINE.md) · [Українська](../uk/ENGINE.md) · [Tiếng Việt](../vi/ENGINE.md) · [中文](../zh/ENGINE.md)

---

# VDLU engine (`update.sh`)

KSU/Magisk मॉड्यूल के लिए Flashless, incremental अपडेट क्लाइंट।
`DIFF -> FETCH -> APPLY -> COMMIT` चक्र को एक पुनः आरंभ करने योग्य ट्रांज़ैक्शन के रूप में लागू करता है। `INTERFACES.md` (अभिसरण
का नियम) के अनुरूप।

शुद्ध POSIX sh (mksh/busybox/toybox)। **SLIM:** यह केवल toybox (`sha256sum`/`gzip`/`base64`/`date`) +
अंतर्निहित `ed25519-mini` (ed25519 verify; **डिवाइस पर कोई openssl नहीं**) + पहले https अपडेट पर **fetch** किए गए एक static `curl`
पर निर्भर करता है (WebUI `fetch()` करता है, इसे Tier-2 में बनाए रखता है, और `install-tool` इसका उपयोग करने से पहले इसके
हस्ताक्षर+हैश को सत्यापित करता है)। `file://` को curl की आवश्यकता नहीं। `jq` पर शून्य निर्भरता।

## Invocation

```sh
VDLU_DIR=/data/adb/<mod>/vdlu MODULE_DIR=/data/adb/modules/<mod> MODID=<mod> \
  sh $MODULE_DIR/vdlu/update.sh <cmd>
```

`rc 0` = ठीक; `rc != 0` = त्रुटि (कारण stderr पर)। `vdlu-verify` किसी अन्य घटक द्वारा प्रदान किया जाता है
(हस्ताक्षर `INTERFACES.md §6` में); engine इसे केवल कॉल करता है।

| cmd | करता है |
|---|---|
| `check` | केवल-पढ़ने वाला DIFF; `{"update":bool,"from":N,"to":M,"fetch":K,"reboot":bool}` प्रिंट करता है; कुछ नहीं बदलता |
| `run` | पूर्ण LIVE चक्र + REBOOT-hard को stage करता है; `cancel` का सम्मान करता है; प्रगति `journal.json` में |
| `resume` | लंबित ट्रांज़ैक्शन (`target.json`) को वर्तमान चरण से पुनः आरंभ करता है; idempotent; `.so` को swap **नहीं** करता |
| `boot` | pre-zygote मोड: resume **+** `staged/*.vdlu-new` को swap करता है -> `PENDING_REBOOT`->`DONE` बंद करता है। कोई लंबित ट्रांज़ैक्शन न होने पर, यह एक नया चक्र चलाता है और सब कुछ (`.so` सहित) एक ही boot में लागू करता है |
| `status` | `journal.json` प्रिंट करता है (या `{"state":"idle"}`) |
| `cancel` | `$VDLU_DIR/cancel` बनाता है; चल रहा एक `run` अगले सुरक्षित बिंदु पर रुकता है |

## State मशीन (journal.json)

```
PLANNED -> FETCHING -> FETCHED -> APPLYING -> APPLIED_LIVE -> (PENDING_REBOOT | DONE)
```

`DONE` केवल तब जब सब कुछ का पुनः-हैश मेल खाता है। यदि कोई भी REBOOT-hard stage किया गया ⇒ `PENDING_REBOOT` (कभी एक झूठा
`DONE` नहीं)। किसी भी विफलता पर `ERROR`, मॉड्यूल को भ्रष्ट किए बिना (लागू किए गए LIVE फ़ाइलें `rollback/<v>/` से वापस लौटा दी
जाती हैं; कुछ भी "आधा-लागू और इसके बारे में झूठ बोलता हुआ" नहीं)। `fetch` चरण का सौम्य निकास: **`DEFERRED`** -
डाउनलोड `net_policy` द्वारा स्थगित किया गया (नेटवर्क अनुमत नहीं); plan/target बने रहते हैं और यह अगले check/boot पर पुनः आरंभ होता है
(WebUI एक नीला info toast "X नेटवर्क की प्रतीक्षा में" दिखाता है, कोई त्रुटि नहीं)।

## कठोरता की गारंटियाँ

- **FETCH:** `net_policy` द्वारा नियंत्रित (any/wifi/mobile; केवल http/https, `file://` कभी नहीं) - एक अननुमत नेटवर्क ⇒
  `DEFERRED` (पुनः आरंभ करने योग्य), डेटा खर्च किए बिना। केवल जो गायब है उसे `<sha>.part` में डाउनलोड करता है (curl के साथ
  `--connect-timeout` + `--speed-time`, कभी अटकता नहीं), `gz` को डीकंप्रेस करता है (toybox `gunzip`), `sha256sum` ==
  manifest जाँचता है, `blobs/<sha>` में atomic `mv`। एक cached+ok blob छोड़ दिया जाता है। यह एक अपरिवर्तित स्थानीय फ़ाइल से
  blob को seed कर सकता है (dedup/offline)। **एक ही blob पर 3 विफलताएँ = चरण कुछ भी लागू किए बिना abort हो जाता है।** यह
  केवल तब `FETCHED` बनता है जब plan के सभी blobs मौजूद+सत्यापित हों।
- **APPLY** (केवल `FETCHED` से): `live`/`soft` -> `rollback/<v>/` में backup -> `.vdlu-tmp` -> `chmod` -> verify ->
  atomic `rename`। `reboot` -> `staged/<path>.vdlu-new` में materialize करता है (live inode को स्पर्श नहीं करता)।
  `delete[]` -> backup -> हटाता है। Idempotent (पहले से लक्ष्य हैश पर एक फ़ाइल छोड़ दी जाती है)।
- **COMMIT:** प्रत्येक `live`/`soft` का पुनः-हैश; तभी यह `current.json` लिखता है। stage की गई फ़ाइलों के साथ ⇒
  `PENDING_REBOOT`। `boot` `mv -f staged/....vdlu-new $MODULE_DIR/<path>` (pre-zygote) करता है + पुनः-सत्यापित करता है +
  `DONE`।
- **cancel:** फ़ाइलों के बीच जाँचा जाता है (सुरक्षित बिंदु); चल रहे `.vdlu-tmp`/`.part` को हटाता है, `cancel` को मिटाता है,
  journal को पुनः आरंभ करने योग्य छोड़ देता है (`cancelled:true`, `error:null`)।
- **mkdir-lock `$VDLU_DIR/lock.d`** क्रमबद्ध करता है (toybox पर flock अव्यवहार्य; PID द्वारा stale-recovery)।
  धैर्यवान boot-retry प्रतीक्षा के दौरान न lock पकड़े रहता है (`acquire_lock_try`+release प्रयासों के बीच) न ही एक
  wakelock - बैटरी-सुरक्षित। बीच में एक crash/network/reboot -> `resume`/`boot` जारी रखता है।
- **profile=hardened** ⇒ उपयोग से पहले manifest पर `vdlu-verify` अनिवार्य; विफलता = abort; downgrade अवरुद्ध
  (monotonic संस्करण)। **trusted** ⇒ verify best-effort है, लेकिन हर blob का हैश हमेशा जाँचा जाता है।
- **module-update कुंजी allowlist (दोनों profiles):** `verify_manifest`, pubkey चुने जाने से पहले, किसी भी ऐसे manifest को fail-closed अस्वीकार करता है जिसका `key_id` कॉन्फ़िगर की गई `key_id` allowlist (देखें INTERFACES §5/§6) में नहीं है, ताकि केवल keyring में पड़ी एक कम-भरोसे वाली कुंजी (जैसे एक fingerprint-feed कुंजी) कभी भी flashless root अपडेट पर हस्ताक्षर न कर सके। अनसेट होने पर डिफ़ॉल्ट-सुरक्षित: एकल-कुंजी keyring = केवल वही एक कुंजी; बहु-कुंजी keyring = `key_id` पिन होने तक अस्वीकृत।
- सुंदरता से घटता है: गायब बाइनरी / नेटवर्क डाउन / डिस्क भरी -> stderr पर एक स्पष्ट त्रुटि + journal में `state:ERROR`,
  मॉड्यूल को भ्रष्ट किए बिना।

## jq के बिना JSON parsing

`awk` में एक gron-शैली flattener (शुद्ध POSIX: `substr`/`index`/`gsub`/`split`/`printf` + पैरामीटर के रूप में पास किए गए
locals) manifest को char-by-char टोकनाइज़ करता है और प्रति scalar leaf एक `path<TAB>value` पंक्ति उत्सर्जित करता है
(`files/0/sha256<TAB>ab..`, `version<TAB>6`, `delete/0<TAB>etc/x`)। कॉम्पैक्ट या pretty-printed JSON के प्रति मज़बूत।
`sh` इसे `grep`/`cut` के साथ उपभोग करता है; प्रति-फ़ाइल plan को एक दूसरे `awk` में TSV में पुनः-संयोजित किया जाता है
(`class st mode enc sha size path`), जो `$VDLU_DIR/plan.tsv` बन जाता है।

## State फ़ाइलें (`$VDLU_DIR` में, Tier-2)

| file | भूमिका |
|---|---|
| `config` | key=value (`source`/`profile`/`channel`/`net_policy`/`key_id`/`boot_retry_*`/…; INTERFACES §5 देखें) |
| `current.json` | ACTIVE संस्करण का manifest (diff आधार); अनुपस्थित = कभी अपडेट नहीं |
| `target.json` | in-flight ट्रांज़ैक्शन का pinned manifest (उपस्थिति = सक्रिय ट्रांज़ैक्शन); `DONE` पर `current.json` बन जाता है |
| `plan.tsv` / `plan.del` | plan + प्रति-फ़ाइल प्रगति (st) / हटाने के लिए paths |
| `journal.json` | WebUI के लिए प्रगति (हर transition पर पुनः उत्पन्न) |
| `blobs/<sha256>` | सत्यापित मूल सामग्री का cache |
| `rollback/<version>/<path>` | अधिलेखित फ़ाइलों का backup (undo; अंतिम 3 रखता है) |
| `staged/<path>.vdlu-new` | REBOOT-hard boot पर swap की प्रतीक्षा में |
| `lock.d/` | mkdir-lock (toybox पर flock अव्यवहार्य; PID द्वारा stale-recovery) |
| `tools/<abi>/curl` | fetch किया गया static curl (slim bootstrap); अपडेट के पार बना रहता है |
| `cancel` | cancel अनुरोध |

<!-- doc-footer -->

---

> _यह दस्तावेज़ Claude (Anthropic) से तैयार किया गया है और इसे VD171 द्वारा अनुरक्षित किया जाता है। सुधार और संशोधन का स्वागत है; देखें [CONTRIBUTING.md](CONTRIBUTING.md)।_
