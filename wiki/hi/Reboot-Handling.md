# Reboot Handling

VDLU का पूरा मकसद एक module को दोबारा फ्लैश किए बिना अपडेट करना है, और, जहाँ भी संभव हो, बिल्कुल reboot किए बिना। एक module में अधिकांश files device के चलते रहते हुए बदली जा सकती हैं। चंद सचमुच नहीं बदल सकतीं, क्योंकि kernel या zygote process उन्हें पहले ही map कर चुका है और अगले boot तक एक बदलाव नहीं नोटिस करेगा।

VDLU का काम उन दोनों समूहों को अपने आप अलग बताना है, जो कुछ भी यह सुरक्षित रूप से कर सकता है वह सब **live** लागू करना है, और सिर्फ सचमुच boot-bound files को एक reboot के लिए defer करना है जिसे यह स्पष्ट रूप से flag करता है। यह पेज बताता है कि कैसे।

इसके नीचे engine mechanics के लिए, देखें [[Engine]]। बड़ी तस्वीर के लिए, देखें [[Architecture]]।

## हर बार बस reboot क्यों न किया जाए

एक reboot सबसे महँगी चीज़ है जो एक update किसी से माँग सकता है। यह जो भी वे कर रहे हों उसे बाधित करता है, इसमें एक मिनट या उससे ज़्यादा लगता है, और यह लोगों को updates से डरना सिखा देता है। एक अच्छे incremental updater को अदृश्य महसूस होना चाहिए: आप update tap करते हैं, कुछ files चल रहे system के नीचे बदल जाती हैं, और आप पहले से ही नए version पर हैं।

तो VDLU सामान्य धारणा को उलट देता है। default live है। एक file को एक reboot के लिए सिर्फ तभी defer किया जाता है जब यह प्रमाणित रूप से kernel- या zygote-bound तरह की हो, और तब भी सिर्फ वही file इंतज़ार करती है। उसके आसपास सब कुछ फिर भी तुरंत update होता है।

## तीन classes

feed में हर file को एक class सौंपी जाती है। producer इसे manifest में स्पष्ट रूप से सेट कर सकता है, पर व्यवहार में class path से व्युत्पन्न होती है, और engine एक file को सिर्फ `reboot` की ओर upgrade करेगा, कभी उसे `live` की ओर downgrade नहीं करेगा। classes हैं:

**LIVE** आम मामला है: web UI assets, binaries, scripts जो माँग पर पढ़े जाते हैं, config files, `module.prop`, और कुछ भी और जो नीचे के नियमों से मेल नहीं खाता। एक live file का backup लिया जाता है और फिर system के चलते हुए atomically target के ऊपर rename की जाती है। कोई reboot नहीं, और बदलाव उसी पल प्रभावी होता है जब rename उतरता है।

**SOFT** module की अपनी lifecycle scripts हैं: `service.sh`, `post-fs-data.sh`, और `boot-completed.sh`। ये बिल्कुल LIVE files की तरह live लागू होती हैं, तो नई copy पहले से ही disk पर होती है। इन्हें अपनी class मिलने की वजह यह है कि चल रहे system ने इस boot पर पुरानी copy पहले ही execute कर ली है; नई बस अगले boot चलती है, बिना किसी staging और बिना किसी banner के। defer करने के लिए कुछ नहीं है, बस एक स्वाभाविक handover।

**REBOOT-hard** वह छोटा समूह है जो एक चल रहे system के नीचे नहीं बदल सकता:

- native libraries, `*.so` (एक `zygisk/` path के नीचे कुछ भी), क्योंकि zygote उन्हें startup पर हर app में map करता है;
- `/system` overlay files, क्योंकि overlay boot पर mount होता है;
- `sepolicy.rule` files, क्योंकि SELinux policy जल्दी load होती है।

एक REBOOT-hard file को कभी system के ऊपर रहते हुए उसके live inode के ऊपर नहीं लिखा जाता। एक `.so` को overwrite करना जिसे zygote पहले ही map कर चुका है, ऐसे ही आपको crashes और असंगत state मिलते हैं। इसके बजाय नया content state directory के बगल में **staged** किया जाता है और अगले boot पर swap किया जाता है, इससे पहले कि कुछ भी इसे map कर सके।

## Path से class, एक नज़र में

engine class को path से इस तरह व्युत्पन्न करता है:

| Path pattern | Class | लागू |
|---|---|---|
| `zygisk/**`, `**/zygisk/**` (the `.so` files) | REBOOT-hard | staged, boot पर pre-zygote swapped |
| `system/**` (overlay) | REBOOT-hard | staged, boot पर swapped |
| `*.rule` (sepolicy) | REBOOT-hard | staged, boot पर swapped |
| `service.sh`, `post-fs-data.sh`, `boot-completed.sh` | SOFT | live लिखी, अगले boot चलती है |
| `webroot/**`, `bin/**`, `lib/**`, configs, `module.prop`, बाकी सब कुछ | LIVE | live लिखी, तुरंत प्रभावी |

manifest हर file पर एक स्पष्ट `class` ढो सकता है, पर व्युत्पन्न class एक floor की तरह काम करती है: अगर एक file अपने path से REBOOT-hard दिखती है, तो उसे REBOOT-hard माना जाता है, manifest कुछ और कहे तब भी। यह एक गलत-label किए गए feed को कभी एक `.so` को hot-swap करने की कोशिश करने से रोकता है।

## एक run दोनों समूहों को एक साथ कैसे संभालता है

एक सामान्य `run` (DIFF से FETCH से APPLY से COMMIT cycle जो [[Engine]] में वर्णित है) के दौरान, दोनों समूह एक ही transaction में संभाले जाते हैं:

```
run:
  LIVE + SOFT  --> backup -> write .vdlu-tmp -> verify -> atomic rename   (effective now)
  REBOOT-hard  --> materialize into staged/<path>.vdlu-new                (live inode untouched)

  re-hash every LIVE + SOFT file
       |
       +-- nothing staged  --> DONE
       +-- something staged --> PENDING_REBOOT  (reboot banner in the WebUI)
```

तो एक ऐसे run के बाद जिसने एक `.so` को छुआ, आप हर live file के लिए पहले से ही नए version पर हैं, और सिर्फ staged टुकड़े इंतज़ार कर रहे हैं। journal `reboot_pending` रिपोर्ट करता है, और WebUI एक persistent banner दिखाता है जो staged files को activate करने के लिए एक reboot को आमंत्रित करता है। कोई फर्जी "done" नहीं है: staged files वाला एक run `PENDING_REBOOT` में समाप्त होता है, `DONE` में नहीं।

## boot पर swap

staged files को `boot` command द्वारा लागू किया जाता है, जिसे host module `post-fs-data.sh` में wire करता है, ताकि यह synchronously और **pre-zygote** चले, इससे पहले कि कोई process नई `.so` को map कर सके।

`boot` एक `resume` करता है (किसी भी बाधित phase को खत्म करने के लिए) और फिर swap। हर staged REBOOT-hard file के लिए यह:

1. पुष्टि करता है कि staged path module directory के अंदर रहता है (एक containment check);
2. `staged/<path>.vdlu-new` को manifest hash के विरुद्ध दोबारा-hash करता है;
3. मौजूदा live file का backup लेता है;
4. staged file को live के ऊपर `mv -f` करता है और उसे `chmod` करता है;
5. अब जगह पर मौजूद file को दोबारा-hash करता है, यह पुष्टि करने के लिए कि swap सही उतरा;
6. उसे applied चिह्नित करता है।

सिर्फ तभी जब हर staged file swap और दोबारा-verify हो चुकी हो, transaction `PENDING_REBOOT` से `DONE` में बंद होता है। अगर कोई step विफल होता है, तो journal error दर्ज करता है और module अपनी पिछली files रखता है; कुछ भी आधा-swapped नहीं छोड़ा जाता।

क्योंकि swap दोबारा-hashes और atomic renames का एक क्रम है, `boot` चलाना तब भी सुरक्षित है जब यह पिछली बार बाधित हुआ हो। यह बस staged files को वापस उठा लेता है।

## auto_on_reboot

Staging एक reboot-free एहसास का सिर्फ आधा है; दूसरा आधा यह है कि user को कभी swap चलाना याद नहीं रखना चाहिए। config में `auto_on_reboot=1` के साथ, host module की `post-fs-data.sh` हर boot पर `update.sh boot` को call करती है। इसका मतलब:

- अगर एक transaction reboot के लिए pending है, तो staged files zygote शुरू होने से पहले अपने आप swap हो जाती हैं, और user बस खुद को पूरी तरह नए version पर पाता है;
- अगर कुछ भी pending नहीं है, तो `boot` एक ताज़ा cycle चला सकता है और सब कुछ लागू कर सकता है, एक `.so` समेत, उसी एक boot में, क्योंकि यह पहले से ही pre-zygote चल रहा है।

दूसरे शब्दों में, एक staged `.so` की user को एक reboot से ज़्यादा कोई कीमत नहीं पड़ती जो वे वैसे भी करने वाले थे। उन्हें दूसरी बार कुछ भी tap नहीं करना पड़ता।

## boot पर offline, बिना battery खींचे

कभी-कभी `boot` feed जाँचना चाहता है पर device के पास अभी तक कोई network नहीं है। VDLU इसका इंतज़ार कर सकता है, धैर्यपूर्वक और सस्ते में, `boot_retry_minutes` (0 इसे बंद कर देता है) द्वारा नियंत्रित। प्रतीक्षा जानबूझकर battery-safe है:

- प्रयासों के बीच यह बस `sleep` करता है, जो deep sleep में जम जाता है, तो device सामान्य रूप से सोता है और retry सिर्फ तभी resume होता है जब device पहले से ही जागा हो;
- यह कोई wakelock नहीं रखता और इंतज़ार करते समय engine lock नहीं रखता, तो एक manual run कभी block नहीं होता;
- हर प्रयास से पहले यह एक kernel route lookup से जाँचता है कि network अनुमत है या नहीं, जो कोई packet नहीं भेजता और radio नहीं जगाता;
- यह कभी एक deterministic failure जैसे एक खराब signature या एक blocked downgrade को retry नहीं करता, सिर्फ एक सच्ची network-absent स्थिति को।

manifest check खुद किसी भी network पर मुफ्त रहता है, तो आप हमेशा जान जाते हैं कि एक update मौजूद है; सिर्फ download network policy के संतुष्ट होने का इंतज़ार करता है, error करने के बजाय साफ-सुथरे defer होते हुए।

## यह भी देखें

- [[Engine]]: transaction, apply-by-class logic, और पूरा `boot` command।
- [[Architecture]]: engine producer और WebUI के बीच कहाँ बैठता है।
