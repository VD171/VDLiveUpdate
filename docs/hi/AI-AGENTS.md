> **Languages:** [English](../AI-AGENTS.md) · [العربية](../ar/AI-AGENTS.md) · [Čeština](../cs/AI-AGENTS.md) · [Deutsch](../de/AI-AGENTS.md) · [Español](../es/AI-AGENTS.md) · [فارسی](../fa/AI-AGENTS.md) · [Français](../fr/AI-AGENTS.md) · हिन्दी · [Bahasa Indonesia](../id/AI-AGENTS.md) · [Italiano](../it/AI-AGENTS.md) · [日本語](../ja/AI-AGENTS.md) · [한국어](../ko/AI-AGENTS.md) · [Nederlands](../nl/AI-AGENTS.md) · [Polski](../pl/AI-AGENTS.md) · [Português](../pt/AI-AGENTS.md) · [Русский](../ru/AI-AGENTS.md) · [Svenska](../sv/AI-AGENTS.md) · [ไทย](../th/AI-AGENTS.md) · [Türkçe](../tr/AI-AGENTS.md) · [Українська](../uk/AI-AGENTS.md) · [Tiếng Việt](../vi/AI-AGENTS.md) · [中文](../zh/AI-AGENTS.md)

---

# एक AI एजेंट से VDLU चलाना

VDLiveUpdate (VDLU) वह flashless, वृद्धिशील अपडेटर है जिसे KSU/Magisk मॉड्यूल `vdlu/` में वेंडर करते हैं। पूरा इंजन शेल से चलाया जाता है, इसलिए एक AI सहायक या एजेंट बिना UI के किसी अपडेट को जाँच, लागू, फिर से शुरू और पूरा कर सकता है, वही चक्र जो WebUI चलाता है, बिना UI और बिना मानव के लूप में। यह जो JSON छापता है उसे पार्स करें, कभी टेक्स्ट स्क्रैप न करें।

## अनुबंध

एक ही प्रवेश बिंदु, डिवाइस पर root के रूप में चलाया जाता है, इंजन के तीन परिवेश चर सेट किए हुए:

```sh
VDLU_DIR=/data/adb/<mod>/vdlu MODULE_DIR=/data/adb/modules/<mod> MODID=<mod> \
  sh "$MODULE_DIR/vdlu/update.sh" <verb>
```

- `VDLU_DIR` Tier-2 स्थिति निर्देशिका है (मॉड्यूल के बाहर, एक रीफ़्लैश से बची रहती है), `MODULE_DIR` मॉड्यूल का जीवित वृक्ष है, `MODID` मॉड्यूल id है।
- `rc 0` = ठीक, `rc != 0` = त्रुटि, कारण stderr पर।
- पढ़ने वाली क्रियाएँ (`check`, `status`) stdout पर **एक JSON वस्तु** छापती हैं। उसे पार्स करें, कभी टेक्स्ट स्क्रैप न करें।
- इंजन केवल toybox (`sha256sum`/`gzip`/`base64`) पर, साथ एक embedded `ed25519-mini` पर, साथ पहले https अपडेट पर प्राप्त एक static `curl` पर निर्भर करता है, शून्य `jq`।

विकास के दौरान वही स्क्रिप्ट इस रिपॉज़िटरी में `engine/update.sh` पर रहती है, इसलिए तीन चर सेट किए हुए `sh engine/update.sh <verb>` एक परीक्षण प्रति को उसी तरह चलाता है।

## क्रियाएँ

| क्रिया | करता है | छापता है |
|------|------|--------|
| `check` | फ़ीड के विरुद्ध केवल-पढ़ने वाला DIFF, कुछ नहीं बदलता | `{"update":bool,"from":N,"to":M,"fetch":K,"reboot":bool}`, या जब डिवाइस फ़ीड से आगे हो तो `{"update":false,"ahead":true,"from":N,"to":M}` (डाउनग्रेड अवरुद्ध, सौम्य, rc 0) |
| `run` | पूर्ण LIVE चक्र DIFF -> FETCH -> APPLY -> COMMIT, LIVE फ़ाइलें लागू करता है और REBOOT-hard को मंचित करता है, `cancel` का सम्मान करता है | `journal.json` में प्रगति |
| `resume` | लंबित लेनदेन को उसकी वर्तमान फ़ेज़ से फिर शुरू करता है, निष्क्रिय-दोहराव-सुरक्षित, कभी `.so` नहीं बदलता | अद्यतन `journal.json` |
| `boot` | pre-zygote मोड, `resume` साथ मंचित `.so` की अदला-बदली, `PENDING_REBOOT` को `DONE` में बंद करता है | अद्यतन `journal.json` |
| `status` | केवल-पढ़ने वाला स्नैपशॉट, कुछ नहीं बदलता | `journal.json`, या जब कोई लेनदेन सक्रिय न हो तो `{"state":"idle"}` |
| `cancel` | रुकने का अनुरोध करता है, चल रहा `run` अगले सुरक्षित बिंदु पर रुक जाता है | `$VDLU_DIR/cancel` बनाता है |

एक headless अपडेट है `check` यह देखने को कि कुछ लंबित है या नहीं, `run` उस सब को लागू करने को जो लाइव जा सकता है, फिर किसी भी मंचित `.so` की अदला-बदली के लिए अगले बूट पर `boot` (या किसी स्थगित fetch को फिर आज़माने के लिए `resume`)। हर क्रिया को फिर बुलाना सुरक्षित है, चक्र के बीच कोई क्रैश या नेटवर्क गिरना एक पुनः-आरंभ-योग्य journal छोड़ता है, कभी आधा-लागू मॉड्यूल नहीं।

## स्थिति JSON

`status` (और `$VDLU_DIR/journal.json` पर जीवित फ़ाइल) वह प्रगति अनुबंध है जिसे WebUI और एक एजेंट दोनों पढ़ते हैं:

```json
{ "schema":1, "module":"<id>", "target":<version>, "from":<version>,
  "phase":"diff|fetch|apply|commit",
  "state":"PLANNED|FETCHING|FETCHED|APPLYING|APPLIED_LIVE|PENDING_REBOOT|DONE|ERROR|DEFERRED",
  "total":<int>, "done":<int>, "current":"<path>", "bytes":<int>,
  "reboot_pending":bool, "cancelled":bool, "error":"<str|null>",
  "updated":"<ISO8601>",
  "items":[ {"path":"<p>","sha256":"<h>","class":"<c>","st":"pending|fetched|applied|staged|skipped"} ] }
```

- `state` एक निश्चित क्रम में बढ़ता है: `PLANNED -> FETCHING -> FETCHED -> APPLYING -> APPLIED_LIVE -> (PENDING_REBOOT | DONE)`.
- `DONE` तभी पहुँचता है जब हर चीज़ का पुनः-हैश मेल खाता है। एक मंचित REBOOT-hard फ़ाइल `PENDING_REBOOT` देती है, कभी झूठा `DONE` नहीं, उसे पूरा करने के लिए `boot` चलाएँ।
- `DEFERRED` का अर्थ है कि `net_policy` ने डाउनलोड रोक दिया, एक सौम्य और पुनः-आरंभ-योग्य स्थिति और कोई त्रुटि नहीं, योजना बनी रहती है और अगला `check`/`boot` जारी रहता है।
- `ERROR` कारण को `error` में रखता है, लागू LIVE फ़ाइलें `rollback/` से वापस लाई जाती हैं, मॉड्यूल कभी आधा-लागू नहीं छोड़ा जाता।
- `error:null` के साथ `cancelled:true` एक साफ़ ठहराव है, journal पुनः-आरंभ-योग्य रहता है।

## सीवन अनुबंध

हर घटक (इंजन, प्रोड्यूसर, WebUI) [`INTERFACES.md`](INTERFACES.md) के अनुरूप होता है, अभिसरण का नियम। CLI क्रियाएँ, `manifest.json` स्कीमा, `journal.json` कुंजियाँ और वहाँ परिभाषित config कुंजियाँ **अपरिवर्तनीय** हैं, उस फ़ाइल को सत्य का एकमात्र स्रोत मानें और उनमें से किसी को बदलने से पहले उससे संरेखित हों। इंजन की आंतरिक बातों (पुनः-आरंभ-योग्य लेनदेन, कठोरता की गारंटियाँ, trust-anchor बहिष्करण) के लिए [`ENGINE.md`](ENGINE.md) देखें, फ़ीड पक्ष (सामग्री-पते वाले फ़ीड को बनाना और हस्ताक्षर करना) के लिए [`PRODUCER.md`](PRODUCER.md) देखें।

## एक एजेंट के लिए नियम

- क्रियाओं और JSON का उपयोग करें, कभी WebUI स्क्रैप न करें और कभी स्थिति फ़ाइलों को हाथ से संपादित न करें।
- `INTERFACES.md` को अपरिवर्तनीय मानें, एक बदलाव का अर्थ है पहले अनुबंध को संरेखित करना।
- एक AI एजेंट का पैच किसी भी अन्य की तरह उसी समीक्षा-मानक से गुज़रता है, build सदा release, कुछ ढीला न करें, कुछ न खोएँ।

<!-- doc-footer -->

---

> _यह दस्तावेज़ Claude (Anthropic) से तैयार किया गया है और इसे VD171 द्वारा अनुरक्षित किया जाता है। सुधार और संशोधन का स्वागत है, देखें [CONTRIBUTING.md](CONTRIBUTING.md)।_
