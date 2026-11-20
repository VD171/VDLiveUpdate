# Engine

Engine, VDLU का device पहलू है: वह हिस्सा जो phone पर चलता है, तय करता है कि क्या बदला, उसे डाउनलोड करता है, और लागू करता है। यह एक अकेली POSIX shell script है, `engine/update.sh`, साथ में एक छोटा signature checker, `engine/vdlu-verify`। दोनों को host module में `<module>/vdlu/` पर vendor किया जाता है और root द्वारा चलाया जाता है।

पूरा engine एक विचार के इर्द-गिर्द बना है: एक update एक **resumable transaction** है। अगर phone को बीच में reboot, kill, या network खो जाए, तो अगला run ठीक वहीं से उठा लेता है जहाँ वह रुका था, और module को कभी आधा-लागू करके "done" होने का दिखावा करता हुआ नहीं छोड़ा जाता।

अगर आप पहले बड़ी तस्वीर चाहते हैं, देखें [[Architecture]]। updates जब भी हो सके reboot से कैसे बचते हैं, इसके लिए देखें [[Reboot Handling]]।

## Device के लिए लिखा गया, आपके laptop के लिए नहीं

`update.sh` शुद्ध POSIX `sh` है। यह mksh, busybox, या toybox के नीचे चलता है, बिना किसी bash-only feature के, और यह `sh -n` पास करता है। यह मायने रखता है क्योंकि एक rooted Android device पर environment छोटा और सख्त है।

खासकर, वहाँ कोई `jq` नहीं है। VDLU `manifest.json` को `awk` में लिखे एक छोटे gron-शैली के flattener से parse करता है: यह JSON को एक-एक अक्षर करके walk करता है और हर leaf के लिए एक `path<TAB>value` line निकालता है (उदाहरण के लिए `files/0/sha256<TAB>ab..` या `version<TAB>6`)। फिर shell उन lines को `grep` और `cut` से पढ़ती है। यह compact और pretty-printed दोनों JSON पर काम करता है, और यह कभी ऐसे JSON tool को shell-out नहीं करता जो वहाँ है ही नहीं।

Engine सिर्फ उसी पर निर्भर है जो toybox पहले से भेजता है (`sha256sum`, `gzip`/`gunzip`, `base64`, `date`), embedded `ed25519-mini` verifier, और, `https://` feeds के लिए, एक छोटा static `curl` जो एक बार fetch और verify किया जाता है। एक `file://` feed को किसी `curl` की ज़रूरत ही नहीं।

## छह commands

आप engine को environment में module के paths और एक command के साथ invoke करते हैं:

```sh
VDLU_DIR=/data/adb/<mod>/vdlu MODULE_DIR=/data/adb/modules/<mod> MODID=<mod> \
  sh "$MODULE_DIR/vdlu/update.sh" <cmd>
```

Exit code `0` का मतलब success; कोई भी दूसरा code एक error का मतलब है, जिसकी वजह stderr पर प्रिंट होती है।

| Command | यह क्या करता है |
|---|---|
| `check` | Read-only diff. manifest डाउनलोड करता है, उसकी इंस्टॉल की हुई चीज़ से तुलना करता है, और एक one-line JSON summary प्रिंट करता है: `{"update":bool,"from":N,"to":M,"fetch":K,"reboot":bool}`. disk पर कुछ नहीं बदलता। अगर device feed से नया है (एक blocked downgrade) तो यह `{"update":false,"ahead":true,...}` exit `0` के साथ रिपोर्ट करता है, error नहीं। |
| `run` | पूरा live cycle: DIFF, FETCH, APPLY, COMMIT. हर live file तुरंत लागू करता है और चंद reboot-class files stage करता है। `cancel` का सम्मान करता है। progress `journal.json` में लिखता है। |
| `resume` | एक ऐसे transaction को जारी रखता है जो बाधित हुआ था, जिस भी phase में था वहीं से शुरू करके। Idempotent. यह एक staged `.so` को swap **नहीं** करता (वह `boot` के लिए आरक्षित है)। |
| `boot` | pre-zygote path. एक `resume` करता है और फिर किसी भी staged `*.vdlu-new` file को जगह पर swap करता है, `PENDING_REBOOT` को `DONE` में बंद करते हुए। अगर कोई pending transaction नहीं है, तो यह एक ताज़ा cycle चलाता है और सब कुछ लागू करता है, `.so` समेत, उसी एक boot में। |
| `status` | `journal.json` प्रिंट करता है, या `{"state":"idle"}` जब कुछ भी चल नहीं रहा होता। |
| `cancel` | एक `cancel` marker बनाता है। चल रहा एक `run` अगले safe point पर साफ-सुथरे रुक जाता है। |

`check` command जानबूझकर सस्ती है, ताकि UI आपको किसी भी network पर बता सके कि एक update मौजूद है। असल download अलग से gate किया जाता है (नीचे fetch phase देखें)।

## Transaction, चरण-दर-चरण

हर `run` एक तय state machine से गुज़रता है, जो `journal.json` में दर्ज होती है ताकि WebUI (और आप) उसे देख सकें:

```
PLANNED -> FETCHING -> FETCHED -> APPLYING -> APPLIED_LIVE -> (PENDING_REBOOT | DONE)
```

**DIFF.** Engine `manifest.json` fetch करता है, हर field validate करता है (नीचे और [[Security and Trust Model]] देखें), और signed target tree को `current.json` के विरुद्ध diff करता है, जो पहले से इंस्टॉल version का manifest है। परिणाम एक per-file plan है जो `plan.tsv` में लिखा जाता है: हर file के लिए एक row, जो उसकी class, target hash, mode, और progress state ढोती है। पहले से target hash पर मौजूद files skip के लिए चिह्नित की जाती हैं।

**FETCH.** हर अब भी ज़रूरी file के लिए, engine उसका content-addressed blob `<source>/blobs/<sha>` (या compressed होने पर `<sha>.gz`) से एक `.part` file में डाउनलोड करता है। अगर blob gzipped है तो उसे decompress किया जाता है, फिर उसका SHA-256 manifest के विरुद्ध जाँचा जाता है। सिर्फ मेल खाने पर ही उसे atomically `blobs/<sha>` में `mv` किया जाता है। सही hash के साथ पहले से cached एक blob पूरी तरह skip कर दिया जाता है, और एक अनबदली local file बिना किसी download के cache को seed कर सकती है। एक ही blob पर तीन विफलताएँ phase को बिना कुछ apply किए abort कर देती हैं। phase `FETCHED` पर तभी पहुँचता है जब plan में हर blob मौजूद और verified हो। ये blobs जिस [[Feed Format]] से आते हैं, उसके लिए वह पेज देखें।

fetch को network policy द्वारा gate किया जाता है: एक feed सिर्फ Wi-Fi तक, सिर्फ mobile तक, या किसी भी network तक सीमित हो सकता है। जब मौजूदा network अनुमत नहीं है, तो fetch विफल नहीं होता; यह सौम्य `DEFERRED` state में चला जाता है, plan और target को pinned रखता है, और सही network आने पर अगले check या boot पर resume होता है। इस बीच कोई data खर्च नहीं होता।

**APPLY.** सिर्फ `FETCHED` से ही प्रवेश किया जाता है। हर file के लिए engine class के हिसाब से काम करता है:

- `live` और `soft` files: मौजूदा file को `rollback/<version>/<path>` में backup करो, नया content एक `.vdlu-tmp` sibling में लिखो, उसे `chmod` करो, उसका hash verify करो, फिर उसे atomically target के ऊपर `rename` करो। पहले से target hash पर मौजूद एक file skip कर दी जाती है।
- `reboot` files (एक `.so`, एक `/system` overlay, एक `sepolicy.rule`): `staged/<path>.vdlu-new` में materialize करो। live inode को यहाँ कभी नहीं छुआ जाता। देखें [[Reboot Handling]]।
- deletions: backup, फिर हटाओ। Deletions सिर्फ बिल्कुल अंत में लागू होती हैं, एक साफ `DONE` पर, कभी भी जब एक reboot अभी भी pending हो तब नहीं।

**COMMIT.** Engine हर live और soft file को re-hash करता है जिसे उसने छुआ। सिर्फ तभी जब वे सब मेल खाते हैं, यह `current.json` लिखता है, नए version को diff base बनाते हुए। अगर कोई reboot-class file staged हुई थी, तो state `DONE` के बजाय `PENDING_REBOOT` बन जाता है; swap और अंतिम re-verify बाद में `boot` command के तहत होते हैं।

## निर्माण से ही Fail-safe

वे गारंटियाँ जो इसे बिना निगरानी चलाने के लिए सुरक्षित बनाती हैं:

- **किसी चीज़ को मेल खाते re-hash के बिना `DONE` चिह्नित नहीं किया जाता।** `DONE` तभी पहुँचा जाता है जब हर लागू की गई file को वापस पढ़ा गया हो और उसका SHA-256 manifest से मिलाया गया हो। एक staged reboot file `PENDING_REBOOT` मजबूर करती है, कभी एक फर्जी `DONE` नहीं।
- **कुछ भी खोया नहीं जाता।** हर file overwrite होने से पहले `rollback/<version>/` में backup की जाती है, और पिछली तीन versions रखी जाती हैं। अगर एक apply विफल होता है, तो live files को backup से वापस लाया जाता है; module को कभी आधा-लागू करके उसके बारे में झूठ बोलते हुए नहीं छोड़ा जाता। `apply_live` सीधे abort हो जाता है अगर backup step विफल होता है, बजाय इसके कि बिना वापसी के रास्ते के overwrite करे।
- **सब कुछ atomic है।** नया content target के ऊपर `rename`/`mv` के ज़रिए उतरता है, तो एक reader हमेशा या तो पुरानी file देखता है या नई, कभी एक truncated write नहीं।
- **एक crash या kill के बाद Resumable.** एक crash, एक खोया network, या बीच में एक reboot एक valid journal छोड़ता है; `resume` (या `boot`) दर्ज किए गए phase से जारी रखता है। design यह मानकर चलता है कि इसे बाधित किया जाएगा।
- **साफ-सुथरे degrade होता है।** एक गायब binary, एक down network, या एक full disk stderr पर एक स्पष्ट error और journal में `state:ERROR` पैदा करता है, बिना module को corrupt किए।

## Lock

एक समय में सिर्फ एक transaction state को छू सकता है। toybox पर `flock` भरोसेमंद नहीं है, तो VDLU एक directory lock से serialize करता है: `mkdir "$VDLU_DIR/lock.d"` ठीक एक caller के लिए सफल होता है और बाकी के लिए विफल, जो किसी भी समझदार filesystem पर atomic है। एक मर चुके process द्वारा छोड़ा गया एक stale lock, दर्ज किए गए PID को जाँचकर recover किया जाता है।

धैर्यवान boot-time retry (जब device boot पर offline होता है तब इस्तेमाल होता है) इंतज़ार करते समय इस lock को **नहीं** रखता। यह प्रयासों के बीच इसे acquire और release करता है, तो एक manual `run` कभी एक ऐसे boot से block नहीं होता जो network का इंतज़ार कर रहा है, और यह कभी एक wakelock नहीं रखता। Design से ही Battery-safe। इसके बारे में और [[Reboot Handling]] में है।

## Signature checking: `vdlu-verify`

`vdlu-verify` on-device signature checker है, जानबूझकर पतला रखा गया:

```
vdlu-verify <manifest.json> <keyring_dir>
```

Exit `0` का मतलब है कि manifest की signature keyring की उस public key के विरुद्ध valid है जिसकी id manifest की `key_id` से मेल खाती है; कोई भी दूसरा code एक अस्वीकृति है।

जो चीज़ इसे पतला बनाती है वह यह है कि यह **device पर कोई `openssl`** इस्तेमाल नहीं करता। यह keyring public key को एक **raw 32-byte** file के रूप में पढ़ता है, manifest को canonicalize करता है (manifest text जिसमें `sig` field हटा दी गई हो), उसे toybox `sha256sum` से hash करता है, signature को base64-decode करता है, और raw key, message, और 64-byte signature को embedded `ed25519-mini` binary को सौंप देता है। checker verify करने से पहले ही किसी भी malformed चीज़ को मना कर देता है: एक गायब या खाली `key_id` या `sig`, path separators वाली एक `key_id`, एक public key जो ठीक 32 bytes की न हो, या एक signature जो ठीक 64 bytes की न हो।

canonicalization producer के signer के byte-दर-byte समान है, जो यही है जो एक signature को tools के पार verify कराता है। मेल खाती private key कभी किसी device या CI को नहीं छूती; सिर्फ raw public key embed किया जाता है। पूरी trust कहानी, दोनों profiles, और क्यों `hardened` inversion से fail-closed है, वे [[Security and Trust Model]] में हैं।

Engine diff phase के दौरान `vdlu-verify` को call करता है। `hardened` profile के तहत एक विफल verification पूरे update को abort कर देता है; `trusted` के तहत verification best-effort है, लेकिन हर blob का hash फिर भी हमेशा जाँचा जाता है, तो corrupt content profile चाहे जो हो, पकड़ा जाता है।

## Disk पर state

engine का सारा state `$VDLU_DIR` में रहता है (module directory के बाहर), तो module tree खुद कभी सिर्फ तैयार files ही रखता है:

| Path | भूमिका |
|---|---|
| `config` | key=value settings (source, profile, channel, network policy, boot retry) |
| `current.json` | active version का manifest; यही diff base है। अनुपस्थित का मतलब कभी update नहीं हुआ |
| `target.json` | in-flight transaction का pinned manifest. इसकी मौजूदगी एक active transaction को चिह्नित करती है; यह `DONE` पर `current.json` बन जाता है |
| `plan.tsv` / `plan.del` | per-file plan और progress, और हटाने के paths की सूची |
| `journal.json` | WebUI के लिए progress, हर state change पर दोबारा लिखा जाता है |
| `blobs/<sha256>` | verified, decompressed मूल content का cache |
| `rollback/<version>/<path>` | overwrite की गई files के backups; पिछली तीन versions रखी जाती हैं |
| `staged/<path>.vdlu-new` | boot swap का इंतज़ार कर रही एक reboot-class file |
| `lock.d/` | mkdir lock |
| `tools/<abi>/curl` | fetch किया गया, verified static curl; updates के पार बना रहता है |
| `cancel` | एक cancel अनुरोध |

## यह भी देखें

- [[Reboot Handling]]: class system कैसे अधिकांश updates को reboot-free रखता है, और एक staged `.so` कैसे pre-zygote swap होती है।
- [[Security and Trust Model]]: दोनों profiles, fail-closed validation, और raw-key ed25519 chain।
- [[Feed Format]]: manifest और content-addressed blobs जो engine consume करता है।
- [[Architecture]]: engine, producer, और WebUI कैसे एक साथ फिट होते हैं।
