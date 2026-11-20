# Producer

**producer**, VDLU का PC / release पहलू है: tools का वह छोटा समूह जो एक तैयार module tree को एक signed, content-addressed feed में बदल देते हैं जिससे device update कर सकता है। यहाँ कुछ भी phone पर नहीं चलता। ये tools आपकी release machine पर चलते हैं (या, उन हिस्सों के लिए जो सुरक्षित हैं, CI में)।

इनमें चार हैं:

| Tool | कहाँ चलता है | Language | काम |
|---|---|---|---|
| `vdlu-pack` | PC / CI | python3 | अंतिम module tree को `manifest.json` + `blobs/<sha256>` में walk करना |
| `vdlu-keygen` | PC | sh + openssl | एक ed25519 signing keypair generate करना |
| `vdlu-sign` | PC | sh + openssl | एक manifest में `key_id` + signature inject करना, जगह पर ही |
| `vdlu-gc` | PC | python3 | एक published feed से orphan blobs prune करना (fail-safe) |

release flow तीन चरणों का है, हर release में एक बार किया जाता है: **pack, फिर sign, फिर publish**। `vdlu-keygen` एक one-time setup है, और `vdlu-gc` housekeeping है जो feed बढ़ने पर चलाते हैं। producer जो कुछ भी emit करता है वह [[Feed Format]] के अनुरूप है, जो वही है जो device पर engine consume करता है।

---

## vdlu-pack

`vdlu-pack` **ठीक वह tree लेता है जो आपकी `.zip` भेजती है** (अंतिम tree, आपके build द्वारा अपना whitelist और ABI pruning लागू करने के बाद) और उसके लिए feed बनाता है।

```sh
vdlu-pack <module_tree_dir> <out_dir> <module_id> <version> \
          [--version-name v106] [--channel stable] [--prev ./prev/manifest.json]
```

यह `<out_dir>` में दो चीज़ें लिखता है:

- `manifest.json` - target tree का पूरा विवरण (हर file अपने `sha256`, `size`, `mode`, encoding और reboot class के साथ), अभी भी **unsigned** (`key_id` और `sig` fields खाली placeholders हैं)।
- `blobs/<sha256>` (या `blobs/<sha256>.gz`) - हर अलग file content के लिए एक blob।

### Content-addressed और deduplicating

हर blob को उसके **मूल (uncompressed) content के sha256** से नाम दिया जाता है। क्योंकि नाम ही hash है, एक समान content एक ही blob पर उतरता है। `vdlu-pack` एक blob सिर्फ तभी लिखता है जब वह पहले से मौजूद न हो, तो:

- एक file जो नहीं बदली वह वही blob नाम रखती है, और कभी दोबारा नहीं लिखी या push नहीं होती।
- एक समान content वाली दो अलग files एक blob साझा करती हैं।
- एक पलटी हुई (reverted) file उसी blob को दोबारा इस्तेमाल करती है जो पहले से वहाँ थी।

इसलिए Publishing **निर्माण से ही incremental** है: releases के पार, `blobs/` सिर्फ बढ़ता है, और सिर्फ सचमुच नया content ही जोड़ा जाता है। device उन्हीं hashes से fetch करता है, तो वह सिर्फ वही blobs डाउनलोड करता है जो उसके पास पहले से नहीं हैं।

### Compression (`enc` field)

हर file के लिए, `vdlu-pack` तय करता है कि blob को कैसे संग्रहीत करना है:

- `gz` जब file कम से कम 4096 bytes की हो **और** gzip (deterministic `-9 -n`) कम से कम 10 प्रतिशत बचाए।
- `raw` वरना (छोटी files जिन्हें on-the-wire gzip पहले ही कवर कर लेता है, या पहले से incompressible data)।
- अगर build host पर `gzip` गायब है, तो सब कुछ `raw` संग्रहीत होता है। Packing इसके कारण कभी विफल नहीं होती।

manifest में `sha256` **हमेशा** मूल content का होता है; `enc` सिर्फ यह नाम देता है कि blob कैसे संग्रहीत होता है। device `gz` blobs को toybox `gunzip` से decompress करता है और फिर hash को मूल के विरुद्ध जाँचता है।

### Reboot class और safety

`vdlu-pack` हर file को उसके path से व्युत्पन्न एक reboot `class` (`live`, `soft`, `reboot`) से भी tag करता है, ताकि engine जाने कि क्या बिना reboot के लागू हो सकता है और क्या stage होना चाहिए। नियम और device हर class के साथ क्या करता है, वे [[Reboot Handling]] में शामिल हैं।

कुछ चीज़ें जो `vdlu-pack` जानबूझकर **नहीं** करता:

- यह symlinks का अनुसरण नहीं करता (यह उन्हें एक warning के साथ skip करता है, ताकि tree के बाहर का content, जैसे एक system file की एक link, कभी एक blob में leak न हो सके)।
- यह non-regular files (directories, fifos, devices) को skip करता है।
- यह `built` timestamp के लिए `SOURCE_DATE_EPOCH` का सम्मान करता है, तो manifests reproducible होते हैं।
- यह paths के एक तय समूह को feed से पूरी तरह बाहर रखता है (trust root, installer scaffolding, और कुछ अन्य)। पूरी सूची, और हर एक को क्यों बाहर रखा गया, वह [[Feed Format]] में है।

### `delete[]` सूची

`--prev <previous manifest.json>` पास करें और `vdlu-pack` `delete[]` कंप्यूट करता है: वे paths जो पिछली release में मौजूद थे पर इसमें नहीं हैं, ताकि device उन्हें हटा दे बजाय इसके कि पीछे orphans छोड़े। Excluded paths को कभी deletes के रूप में emit नहीं किया जाता, तब भी नहीं जब वे पिछले manifest में दिखें (सटीक semantics के लिए देखें [[Feed Format]])।

---

## vdlu-keygen

एक one-time step. `vdlu-keygen` आपके feed के लिए ed25519 signing keypair बनाता है।

```sh
vdlu-keygen <id> <out_dir>
```

यह तीन files लिखता है:

| File | यह क्या है | कहाँ जाता है |
|---|---|---|
| `<id>.pem` | **private** signing key (mode `0600`) | आपकी release machine पर रहता है। कभी नहीं। |
| `<id>.pub` | public key PEM के रूप में | सिर्फ PC-side tooling |
| `<id>.pub.raw` | public key **raw 32 bytes** के रूप में | module की on-device keyring entry के रूप में भेजा जाता है |

raw 32-byte public key वही है जो device verifier पढ़ता है (यह कोई `openssl` नहीं ढोता, तो यह PEM नहीं पढ़ सकता)। आप `<id>.pub.raw` को module में `vdlu/keyring/<id>.pub` के रूप में embed करते हैं। PEM सिर्फ PC-side इस्तेमाल के लिए है। यह विभाजन, और key rotation कैसे काम करता है, वह [[Security and Trust Model]] में समझाया गया है।

> private `.pem` पूरे सिस्टम का एकमात्र रहस्य है। इसे हर device से दूर और हर repository push से बाहर रखें। नीचे CI note देखें।

---

## vdlu-sign

`vdlu-sign` उस unsigned manifest को लेता है जो `vdlu-pack` ने बनाया और उसे **जगह पर ही** sign करता है।

```sh
vdlu-sign <manifest.json> <privkey.pem> <key_id>
```

यह `key_id` field सेट करता है, manifest का canonical रूप कंप्यूट करता है, और ed25519 signature (base64) को `sig` field में लिखता है। signature manifest के एक सटीक byte transform के ऊपर है ताकि PC और device बिल्कुल वही signed bytes निकालें, device पर बिना किसी JSON library के। वह transform (**canonicalization**) format में सबसे महत्वपूर्ण अकेला invariant है, और यह [[Feed Format]] में पूरा documented है।

private key सिर्फ यहीं, आपकी machine पर, पढ़ी जाती है, और कभी इसे नहीं छोड़ती।

### Signing key CI से बाहर रहती है

यह एक जानबूझकर किया गया design बिंदु है। CI `vdlu-pack` चला सकता है और एक पूरी तरह valid **keyless baseline** बना सकता है (एक unsigned seed manifest; देखें [[Feed Format]]), तो एक fresh install जन्म से current होता है बिना CI के कभी किसी private key को छुए। published feed की असल signing आप करते हैं, स्थानीय रूप से, `vdlu-sign` से। इस तरह signing key 100 प्रतिशत CI से बाहर है, और सिर्फ वही feed जो आप हाथ से publish करते हैं वह signed है।

---

## vdlu-gc

क्योंकि blobs content-addressed और immutable हैं, `blobs/` सिर्फ बढ़ता है: `vdlu-pack` जोड़ता है, यह कभी हटाता नहीं। कई releases के दौरान feed (और उसे host कर रही Pages site) ऐसे blobs जमा कर लेता है जिन्हें कोई मौजूदा manifest अब reference नहीं करता। `vdlu-gc` उन orphans को prune करता है।

```sh
vdlu-gc <feed_dir> [--keep-last N] [--keep extra.json ...] [--apply]
```

यह manifests का **retained set** बनाता है: मौजूदा `manifest.json`, साथ में version के हिसाब से पिछले `N` archived manifests (default `N=3`, एक rollback margin देते हुए), साथ में जो भी आप `--keep` से नाम देते हैं। एक blob जिसे **किसी भी** retained manifest द्वारा reference नहीं किया जाता वह एक orphan है और हटाने का एक उम्मीदवार है। retained set एक union है, तो एक blob तब तक रहता है जब तक कोई retained release अभी भी उसकी ज़रूरत रखती है; एक पुरानी retained version पर बैठा एक device कभी अपना fetch नहीं खोता।

`vdlu-gc` सुरक्षित होने के लिए बनाया गया है:

- **Default से Dry-run.** बिना `--apply` के, यह सिर्फ प्रिंट करता है कि यह क्या हटाता। आप असल में हटाने के लिए `--apply` जोड़ते हैं।
- **Fail-safe.** अगर इसे बिल्कुल भी कोई retained manifest नहीं मिलता, तो यह एक feed खाली करने का जोखिम लेने के बजाय prune करने से मना कर देता है।
- **Reference से retention, date से नहीं.** एक blob इसलिए रखा जाता है क्योंकि एक retained manifest उस पर इशारा करता है, कभी एक timestamp के कारण नहीं।

Pruning के बाद, छोटे feed को अपने host पर push करें। अगर आपका host batched writes को rate-limit करता है तो write को फैला दें।

---

## सब जोड़ते हुए

एक सामान्य release, शुरू से अंत तक:

```sh
# one-time: make a signing key. Keep the .pem off every device and every repo push.
vdlu-keygen release-2026 ./keys

# each release: pack the final shipped tree (post-whitelist, same tree the .zip ships)
vdlu-pack ./module_tree ./out demo 106 --version-name v106 --channel stable \
          --prev ./prev/manifest.json

# sign the manifest in place (local, private key never leaves your machine)
vdlu-sign ./out/manifest.json ./keys/release-2026.pem release-2026

# publish ./out/{manifest.json,blobs/} to your source (GitHub Pages, rsync, ...).
# occasionally: prune orphan blobs
vdlu-gc ./feed --keep-last 3            # dry-run first
vdlu-gc ./feed --keep-last 3 --apply    # then delete
```

VDLU को एक module में अपनाने के पूरे worked example के लिए, देखें [[Quick Start]]। producer जो कुछ भी emit करता है उसके on-wire आकार के लिए, देखें [[Feed Format]]। key handling के पीछे के तर्क और feed से क्या बाहर रखा गया है, उसके लिए देखें [[Security and Trust Model]]।
