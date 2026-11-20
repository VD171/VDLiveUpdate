# WebUI

VDLU एक वैकल्पिक drop-in WebUI widget भेजता है: एक KernelSU या APatch root-manager WebUI के लिए एक छोटा "Updates" panel. यह एक user को एक Check button, एक Update now button, cancel के साथ एक live progress toast, एक reboot banner, और एक settings panel देता है, वह भी बिना user के कभी एक terminal छुए।

यह **vanilla JavaScript** है: कोई framework नहीं, कोई build step नहीं, कोई CDN नहीं। तीन files:

| File | यह क्या है |
|---|---|
| `vdlu.js` | widget; `window.VDLU` expose करता है |
| `vdlu.css` | toast, banner और panel के styles (dark theme, host के CSS variables inherit करता है) |
| `demo.html` | एक standalone page जो device bridge को mock करता है ताकि पूरा UI एक सादे browser में चले |

widget पूरी तरह वैकल्पिक है। [[Engine]] boot triggers से अपने आप ठीक चलता है; WebUI उसके ऊपर बस एक दोस्ताना चेहरा है। इसे एक module में wire करने के लिए देखें [[Quick Start]]।

---

## UI engine से कैसे बात करता है: `ksu.exec` bridge

widget खुद कभी कुछ भी privileged नहीं करता। यह एक shell command बनाता है और उसे root manager के `ksu.exec` bridge को सौंप देता है, जो उसे root के रूप में चलाता है और stdout / stderr / exit code लौटाता है। panel जो कुछ भी दिखाता है वह उन files से वापस पढ़ा जाता है जो engine लिखता है।

widget उस bridge को एक अकेले `exec(cmd)` function में लपेटता है जो एक `Promise` लौटाता है:

- जब command 0 exit करता है तो stdout के साथ **resolve** होता है
- वरना stderr (या `rc=N`) के साथ **reject** होता है

हर command contract का environment ढोता है, जो widget द्वारा assemble किया जाता है:

```
VDLU_DIR=... MODULE_DIR=... MODID=... sh $MODULE_DIR/vdlu/update.sh <cmd>
```

कुछ ठोस calls:

- **एक update शुरू करें:** `update.sh run` को **background** (`(... &)`) में launch किया जाता है ताकि UI कभी एक लंबे download से block न हो।
- **Progress पढ़ें:** `cat $VDLU_DIR/journal.json` का एक हल्का poll (लगभग प्रति सेकंड एक बार)।
- **Cancel:** `touch $VDLU_DIR/cancel` (engine अगले safe point पर रुक जाता है)।
- **Config:** `$VDLU_DIR/config` (key=value) पढ़ना और लिखना, क्रम और अज्ञात keys को संरक्षित करते हुए और सिर्फ उन्हीं keys को छूते हुए जो user ने बदलीं।

अगर host अपने खुद के `exec`, `toast` और `confirm` helpers `init()` को पास करता है, तो widget host की अपनी serialized command queue और visuals के ज़रिए route करता है, तो यह उस WebUI के बाकी हिस्से जैसा दिखता और व्यवहार करता है। अगर वे छोड़ दिए जाते हैं, तो widget सीधे `ksu.exec` को call करने पर वापस आ जाता है और अपना खुद का mini-toast inject करता है।

---

## Progress toast (cancel के साथ)

एक बार एक update चलने लगे, widget एक non-blocking corner toast दिखाता है और `journal.json` poll करता है। toast engine की state machine को दर्शाता है:

```
PLANNED -> FETCHING -> FETCHED -> APPLYING -> APPLIED_LIVE -> (PENDING_REBOOT | DONE)
```

यह एक progress bar और साथ में `phase done/total - current file - bytes` की एक line render करता है, और भर एक **Cancel** button ढोता है। terminal states में से हर एक को अपना treatment मिलता है:

- **DONE** -> एक हरा toast, "vX applied - all verified".
- **PENDING_REBOOT** -> एक हरा toast और साथ में एक persistent reboot banner (नीचे)।
- **ERROR** -> `journal.error` या stderr से वजह के साथ एक लाल toast, Retry की पेशकश करता है। यह कभी success का दिखावा नहीं करता।
- **Cancelled** -> एक amber toast, "cancelled - N/M applied, resumable", **Resume** की पेशकश करता है।
- **DEFERRED** -> एक सौम्य नीला info toast, "download deferred, waiting for the allowed network". यह एक सौम्य network-policy प्रतीक्षा है, कोई error नहीं; यह सही network पर अगले check या boot पर resume होता है।

poll रक्षात्मक है। एक आधा-लिखा journal (engine समानांतर में लिखता है) उस tick के लिए अनदेखा कर दिया जाता है बजाय इसके कि गलत parse हो। अगर progress दिखने के बाद journal अनुपस्थित हो जाता है, तो इसका मतलब है commit ने उसे साफ कर दिया: widget DONE रिपोर्ट करता है। अगर journal शुरू से ही 8 ticks के लिए अनुपस्थित है, तो यह "no response" रिपोर्ट करता है। और अगर journal 20 ticks के लिए उन्हीं values पर जम जाता है, तो widget engine की `lock.d` जाँचता है: अगर lock ज़िंदा है तो यह बस एक धीमा single-blob fetch है और toast इंतज़ार करता रहता है; अगर lock मर चुका है तो run बीच में मर गया, तो widget "updating" पर हमेशा घूमते रहने के बजाय एक Resume button के साथ एक error सामने लाता है।

---

## Reboot banner

कुछ files एक live system पर swap नहीं की जा सकतीं: एक `.so`, एक `/system` overlay, एक `sepolicy.rule`। engine उन्हें stage करता है और transaction को `PENDING_REBOOT` चिह्नित करता है। फिर widget एक **persistent top banner** दिखाता है: "Reboot to activate the new `.so` (vX)". यह तब तक रहता है जब तक staged files अगले boot पर swap न हो जाएँ। WebUI खुलने पर banner journal से दोबारा मूल्यांकित होता है, तो एक user जो UI बंद करके दोबारा खोलता है वह अभी भी इसे देखता है। boot पर क्या होता है, इसके लिए देखें [[Reboot Handling]]।

ध्यान दें कि banner terminal state `PENDING_REBOOT` से trigger होता है, `reboot_pending` flag से नहीं (जो किसी भी `.so` के plan में आते ही true हो जाता है)। यह banner को run के बीच में, कुछ भी असल में stage होने से पहले, प्रकट होने से रोकता है।

---

## "Updates" panel: स्वतंत्र per-category toggles

`mountUpdatesPanel(el)` settings panel को एक खाली `<div>` में render करता है जो host प्रदान करता है। इसमें तीन sections हैं, और हर control स्वतंत्र है और अपने आप save होता है:

**Actions**
- **Check for updates** -> `check` चलाता है, परिणाम inline दिखाता है (up to date / feed से नया / file count और एक reboot tag के साथ update available)।
- **Update now** -> `run` और साथ में progress toast fire करता है।

**Automation** (स्वतंत्र toggles, हर एक flip होते ही `config` में लिखा जाता है)
- **On WebUI open** (`auto_on_webui_open`) -> UI खुलने पर एक quiet update चलाओ।
- **On reboot** (`auto_on_reboot`) -> boot पर pre-zygote में apply करो।
- **Boot retry every (s)** और **Boot retry up to (min)** -> एक manifest fetch को तब retry करने के लिए numeric fields जब device offline boot होता है।

**Source**
- `source` (feed URL), `channel` (stable / canary), `profile` (trusted / hardened), और एक **Network** select जो `net_policy` से map होता है (Wi-Fi + mobile / Wi-Fi only / mobile only)।

Toggles और numeric fields तुरंत save होते हैं और अगर write विफल हो तो visually revert हो जाते हैं। Source section में text और select fields खुद को dirty चिह्नित करते हैं और एक स्पष्ट Save button पर एक साथ save होते हैं। panel सिर्फ उन्हीं keys को दोबारा लिखता है जिन्हें user ने छुआ, तो कोई भी अज्ञात या भविष्य की config keys संरक्षित रहती हैं।

### Auto-open व्यवहार

`onWebUIOpen()` host load पर call होता है। यह journal का मूल्यांकन करता है (reboot banner दिखाते हुए या एक पिछले session द्वारा छोड़े गए non-terminal transaction के लिए Resume की पेशकश करते हुए), फिर, अगर `auto_on_webui_open=1`, यह पहले एक **quiet** `check()` चलाता है। persistent progress toast और असल `run` सिर्फ तभी fire होते हैं जब करने के लिए एक असली download हो (`update && fetch > 0`)। अगर device up to date है या feed से आगे है, तो परिणाम panel में inline दिखता है और screen पर कोई toast नहीं छूटता, तो auto-update manual button जितना ही गैर-दखलंदाज़ है।

---

## i18n (per-language strings)

हर UI string **English** पर default होती है, जो public multi-language modules के लिए तटस्थ विकल्प है। पूरा key map `vdlu.js` में `DEFAULT_I18N` object में रहता है (जो `VDLU.i18n` के रूप में भी expose होता है)। एक host `init({ i18n: ... })` को एक map पास करके keys के किसी भी subset को override करता है:

```html
<script src="i18n/pt-BR.js"></script>   <!-- defines window.VDLU_I18N_PT_BR -->
<script>
  VDLU.init({ exec: ex, moduleDir: MOD, vdluDir: VDL, modid: 'x',
              i18n: window.VDLU_I18N_PT_BR });
</script>
```

- एक **partial** map ठीक है: कोई भी गायब key English default पर वापस आ जाती है।
- Phase और state labels keys `ph_<phase>` और `st_<STATE>` इस्तेमाल करते हैं; बाकी `cancel`, `updateNow` जैसी flat keys हैं।
- एक worked translation (`i18n/pt-BR.js`) एक template के रूप में भेजी जाती है; एक नई भाषा बस उसी आकार में एक `i18n/<lang>.js` file है, या host अपने खुद के i18n system से map बनाता है।

---

## demo.html: UI को बिना device के चलाएँ

`demo.html` `ksu.exec` bridge को mock करता है ताकि ठीक वही `vdlu.js` और `vdlu.css` एक सादे browser में चलें, बिना root और बिना phone के:

```sh
xdg-open webui/demo.html
```

mock `update.sh` और एक विकसित होते `journal.json` का simulation करता है, और इसके buttons scenarios के बीच switch करते हैं: DONE तक एक live update, एक `reboot_pending` finish, बीच में एक error, और एक cancellable run। यह UI देखने और उस पर iterate करने का सबसे तेज़ तरीका है, और यही वह है जो आप widget को एक module में vendor करने से पहले जाँचते हैं।

---

## इसे एक module में wire करना (WebUI-open trigger)

host `index.html` दोनों files load करता है और तीन functions call करता है:

```html
<link rel="stylesheet" href="vdlu.css">
<script src="vdlu.js"></script>
<script>
  VDLU.init({
    moduleDir: '/data/adb/modules/' + MODID,   // $MODULE_DIR (where the engine is vendored)
    vdluDir:   '/data/adb/' + MODID + '/vdlu',  // $VDLU_DIR  (Tier-2 state, outside the module dir)
    modid:     MODID,
    module:    'Demo',        // friendly name shown in the toast (default: modid)
    exec:   ex,               // optional: the host's ksu.exec wrapper
    toast:  toast,            // optional: the host's transient toast
    confirm: askConfirm       // optional: the host's modal
  });

  VDLU.onWebUIOpen();                          // the WebUI-open trigger: banner + auto-update eval
  VDLU.mountUpdatesPanel('b-updates');         // render the "Updates" tab into an empty div
</script>
```

host को सिर्फ Tier-2 paths सप्लाई करने और panel के लिए एक खाली `<div>` allocate करने की ज़रूरत है; toast और banner widget द्वारा `document.body` में inject किए जाते हैं। `onWebUIOpen()` ही WebUI-open trigger है: यही वह है जो reboot banner का मूल्यांकन करता है, एक बाधित transaction पर Resume की पेशकश करता है, और जब `auto_on_webui_open` सेट हो तो quiet auto-update चलाता है।

### एक अकेला source, byte for byte दोबारा vendor किया गया

`vdlu.js` और `vdlu.css` **canonical copy** हैं। एक module जो widget embed करता है इन files को अपरिवर्तित अपने `webroot/` में दोबारा vendor करता है; यह कभी अपनी खुद की copy जगह पर edit नहीं करता। एक नया feature canonical files में जन्म लेता है और दोबारा vendor से नीचे बहता है। एक vendored copy को edit करना silent drift पैदा करता है (यह हो चुका है: एक stale copy में `net_policy`, DEFERRED toast और boot-retry fields गायब थे)। source tree में एक parity guardian हर copy ढूँढता है और उन्हें flag या दोबारा vendor करता है जो diverge होती हैं, सिर्फ widget को कवर करते हुए; keyring की अपनी verify-not-copy cadence है।

---

### Public API (`window.VDLU`)

| Function | करता है |
|---|---|
| `init(opts)` | widget configure करो; `window.VDLU` लौटाता है |
| `onWebUIOpen()` | load पर call करो: banner, Resume पेशकश, और quiet auto-update |
| `mountUpdatesPanel(el)` | Updates panel को `el` (id string या element) में render करो |
| `check()` | `update.sh check` चलाओ; `Promise<{update, from, to, fetch, reboot}>` |
| `startUpdate()` | background में `run` fire करो और साथ में Cancel के साथ progress toast |
| `cancel()` | `$VDLU_DIR/cancel` बनाओ (engine एक safe point पर रुकता है) |
| `resume()` | मौजूदा transaction resume करो और साथ में एक toast |
| `refreshBanner()` | persistent pending-reboot banner का दोबारा मूल्यांकन करो |

---

यह भी देखें: widget जो commands चलाता है उनके लिए [[Engine]], पूर्ण adoption steps के लिए [[Quick Start]], और banner किसका इंतज़ार कर रहा है उसके लिए [[Reboot Handling]]।
