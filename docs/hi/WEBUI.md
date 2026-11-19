> **Languages:** [English](../WEBUI.md) · [العربية](../ar/WEBUI.md) · [Čeština](../cs/WEBUI.md) · [Deutsch](../de/WEBUI.md) · [Español](../es/WEBUI.md) · [فارسی](../fa/WEBUI.md) · [Français](../fr/WEBUI.md) · हिन्दी · [Bahasa Indonesia](../id/WEBUI.md) · [Italiano](../it/WEBUI.md) · [日本語](../ja/WEBUI.md) · [한국어](../ko/WEBUI.md) · [Nederlands](../nl/WEBUI.md) · [Polski](../pl/WEBUI.md) · [Português](../pt/WEBUI.md) · [Русский](../ru/WEBUI.md) · [Svenska](../sv/WEBUI.md) · [ไทย](../th/WEBUI.md) · [Türkçe](../tr/WEBUI.md) · [Українська](../uk/WEBUI.md) · [Tiếng Việt](../vi/WEBUI.md) · [中文](../zh/WEBUI.md)

---

# VDLU - WebUI widget (flashless update)

एक KernelSU/APatch root manager WebUI के लिए VDLU (VD Live Update) इंटरफ़ेस। Vanilla JS, कोई framework नहीं, कोई
build नहीं, कोई CDN नहीं। Drop-in: host `index.html` 2 फ़ाइलें लोड करता है और API को कॉल करता है।

अभिसरण: `INTERFACES.md` §9 (WEBUI↔ENGINE), §4 (journal.json), §5 (config)।

## फ़ाइलें

| File | क्या |
|---|---|
| `vdlu.js` | घटक - `window.VDLU` को उजागर करता है |
| `vdlu.css` | progress toast, reboot banner, "Updates" tab (dark theme, host के variables विरासत में लेता है) |
| `demo.html` | एक mocked `ksu.exec` के साथ standalone page - एक browser में खुलता है, कोई डिवाइस नहीं |

## host `index.html` में एकीकरण

```html
<link rel="stylesheet" href="vdlu.css">
...
<script src="vdlu.js"></script>
<script>
  VDLU.init({
    moduleDir: '/data/adb/modules/' + MODID,   // $MODULE_DIR
    vdluDir:   '/data/adb/' + MODID + '/vdlu',  // $VDLU_DIR  (Tier-2, outside the module dir)
    modid:     MODID,
    module:    'Demo',                     // name shown in the toast (default: modid)
    exec:   ex,          // (optional) the host's ksu.exec wrapper; see below
    toast:  toast,       // (optional) the host's transient toast
    confirm: askConfirm  // (optional) the host's confirmation modal
  });

  VDLU.onWebUIOpen();                          // on load: evaluates journal + banner + auto_on_webui_open
  VDLU.mountUpdatesPanel(document.getElementById('b-updates'));  // when the "Updates" tab is opened
</script>
```

### host को क्या परिभाषित करना चाहिए

- **`moduleDir`** = `$MODULE_DIR` (`/data/adb/modules/<modid>`), जहाँ engine vendor किया गया है
  (`vdlu/update.sh`)।
- **`vdluDir`** = `$VDLU_DIR` (`/data/adb/<modid>/vdlu`), Tier-2 state (`journal.json`, `config`,
  `cancel`)।
- **`modid`** = मॉड्यूल id।

Widget engine कमांड को असेंबल करता है जो पहले से अनुबंध का env (§1) ले जाता है:
`VDLU_DIR=… MODULE_DIR=… MODID=… sh $MODULE_DIR/vdlu/update.sh <cmd>`। `run`/`resume` **background** में जाते हैं
(`(… &)`), और प्रगति `cat $VDLU_DIR/journal.json` के एक हल्के poll (~1s) द्वारा पढ़ी जाती है।

### `exec`/`toast`/`confirm` (वैकल्पिक)

यदि छोड़ दिए जाएँ, तो widget अपने स्वयं के उपयोग करता है:
- **`exec(cmd)`** को एक `Promise` लौटाना चाहिए जो stdout (rc 0) के साथ **resolve** हो और stderr के साथ **reject** हो
  (rc≠0) - ठीक Demo के `webroot/index.html` के `ex()` का हस्ताक्षर। आंतरिक fallback उसी अनुबंध के साथ
  `ksu.exec(cmd, '{}', cb)` को कॉल करता है।
- **`toast(msg)`** = एक छोटी क्षणिक अधिसूचना (fallback अपना स्वयं का mini-toast इंजेक्ट करता है)।
- **`confirm(title,msg,ok,danger,fn)`** = एक modal (आज केवल host द्वारा उपयोग किया जाता है; widget को किसी भी flow में
  किसी पुष्टि की आवश्यकता नहीं)।

host के अपने को पास करने से widget शेष WebUI के समान ही serialized queue और visuals के माध्यम से बात करता है।

## सार्वजनिक API (`window.VDLU`)

| Function | करता है |
|---|---|
| `init(opts)` | कॉन्फ़िगर करता है (ऊपर देखें)। `window.VDLU` लौटाता है। |
| `onWebUIOpen()` | इसे load पर कॉल करें: यदि `reboot_pending` तो banner दिखाता है; यदि कोई गैर-टर्मिनल ट्रांज़ैक्शन है तो **Resume** प्रस्तुत करता है; `auto_on_webui_open=1` के साथ यह एक **QUIET auto-update** चलाता है (पहले एक silent `check()`; `run`+स्थायी toast केवल तब चलाता है जब `update && fetch>0` - अप-टू-डेट/ahead = panel में inline परिणाम, शून्य toast)। |
| `mountUpdatesPanel(el)` | `el` (string id या element) के भीतर "Updates" tab रेंडर करता है: **Check for update**, **Update now**, `auto_on_webui_open`/`auto_on_reboot` toggles, boot-retry fields, **Network** select (`net_policy`: Wi-Fi+mobile / Wi-Fi-only / mobile-only) और `source`/`channel`/`profile` fields। |
| `check()` | `update.sh check` चलाता है; `Promise<{update,from,to,fetch,reboot}>`। |
| `startUpdate()` | background में `run` + **Cancel** के साथ एक progress toast चलाता है। |
| `cancel()` | `$VDLU_DIR/cancel` बनाता है (engine सुरक्षित बिंदु पर रुकता है)। |
| `resume()` | `update.sh resume` + toast (वर्तमान चरण पुनः आरंभ करता है)। |
| `refreshBanner()` | स्थायी pending-reboot banner को पुनः-मूल्यांकित करता है। |

toast (corner overlay, non-blocking) और banner (ऊपर, स्थायी) widget द्वारा `document.body` में इंजेक्ट किए जाते हैं -
host को उनके लिए किसी HTML की आवश्यकता नहीं। "Updates" tab एकमात्र बिंदु है जिसे host आवंटित करता है (एक
खाली `<div>`)।

### वह state प्रवाह जिसे toast दर्शाता है (journal.json, §4)

`PLANNED → FETCHING → FETCHED → APPLYING → APPLIED_LIVE → (PENDING_REBOOT | DONE)`; किसी भी क्षण `ERROR`।
toast **एक बार + `phase done/total · current · bytes`** दिखाता है। Terminals:
- **`DONE`** → हरा toast "v&lt;target&gt; applied"।
- **`PENDING_REBOOT`** (या `reboot_pending=true`) → हरा toast + **स्थायी banner** "⚠️ Reboot to
  activate the new `.so` (vX)"।
- **`ERROR`** → कारण के साथ लाल toast (`journal.error`/stderr)। कभी सफलता का दिखावा नहीं करता।
- **Cancelled** → "cancelled - N/M, resumable" + एक **Resume** बटन।

## डेमो चलाना

`demo.html` को एक browser में खोलें (`xdg-open webui/demo.html`)। mocked `ksu.exec` `update.sh` और
विकसित होते `journal.json` का अनुकरण करता है; बटन **LIVE→DONE**, **reboot_pending**, **error mid-way**
और **cancellable** परिदृश्यों के बीच स्विच करते हैं। यह डिवाइस पर जैसा वही `vdlu.js`/`vdlu.css` है।

## i18n (भाषा)

Widget स्ट्रिंग्स डिफ़ॉल्ट रूप से **अंग्रेज़ी** होती हैं (सार्वजनिक बहु-भाषा मॉड्यूलों के लिए तटस्थ)। host किसी भी
कुंजी को `init` में एक map पास करके अधिक्रमित करता है:

```html
<script src="i18n/pt-BR.js"></script>   <!-- defines window.VDLU_I18N_PT_BR -->
<script>VDLU.init({ exec: ex, moduleDir: MOD, vdluDir: VDL, modid: 'x', i18n: window.VDLU_I18N_PT_BR });</script>
```

- एक **आंशिक** merge ठीक है: एक गायब कुंजी अंग्रेज़ी डिफ़ॉल्ट पर वापस आती है।
- Phase/state कुंजियाँ `ph_<phase>` / `st_<STATE>` हैं; बाकी सपाट हैं (`cancel`, `updateNow`, …)।
- पूर्ण कुंजी map = `vdlu.js` में `DEFAULT_I18N` ऑब्जेक्ट (`VDLU.i18n` के रूप में भी उजागर)।
- एक तैयार अनुवाद एक काम किए गए उदाहरण के रूप में प्रदान किया गया है: `i18n/pt-BR.js`। नई भाषाएँ = उसी साँचे में
  एक `i18n/<lang>.js` फ़ाइल, या host अपने स्वयं के i18n सिस्टम से map बनाता है।

## एकल स्रोत (मॉड्यूलों के पार समानता)

ये `vdlu.js`/`vdlu.css` **कैनोनिकल प्रति** हैं। widget को एम्बेड करने वाला हर मॉड्यूल इस प्रति को
अपने `webroot/` में byte-for-byte **पुनः-vendor** करता है - यह अपनी स्वयं की प्रति को कभी in place
**संपादित नहीं करता**। एक नई widget सुविधा यहाँ पैदा होती है और पुनः-vendor द्वारा नीचे प्रवाहित होती है; विपरीत मूक
drift उत्पन्न करता है (यह व्यवहार में हुआ है: एक vendor की गई प्रति पीछे रह गई और `net_policy`, `DEFERRED`
toast और `boot_retry` fields गायब थे)।

Guardian: [`../tools/webui-parity.sh`](../../tools/webui-parity.sh) स्रोत वृक्ष में हर प्रति ढूँढता है और उन्हें
चिह्नित करता है जो कैनोनिकल से विचलित होती हैं (केवल `vdlu.js`/`vdlu.css`; keyring "verify, not copy" है)।

```sh
tools/webui-parity.sh         # report; exits 1 if there is drift
tools/webui-parity.sh --fix   # re-vendors the divergent ones from the canonical
```

> 🪤 keyring (`keyring/<id>.pub` RAW 32B) और engine (`vdlu/update.sh`) की अपनी स्वयं की पुनः-vendor cadence है;
> यह guardian **केवल WebUI widget** को कवर करता है।

<!-- doc-footer -->

---

> _यह दस्तावेज़ Claude (Anthropic) से तैयार किया गया है और इसे VD171 द्वारा अनुरक्षित किया जाता है। सुधार और संशोधन का स्वागत है; देखें [CONTRIBUTING.md](CONTRIBUTING.md)।_
