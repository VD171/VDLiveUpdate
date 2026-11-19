<!--
  ======================================================================
   VDLiveUpdate (VDLU)  ::  flashless, incremental module updates
   A self-update engine for KernelSU/APatch/Magisk modules: fetch only the
   files that changed, apply the live ones with no reboot, verified by ed25519.

   Copyright (C) 2026  VD171
   SPDX-License-Identifier: Apache-2.0

   Licensed under the Apache License, Version 2.0; you may obtain a copy at
   http://www.apache.org/licenses/LICENSE-2.0

   Site           : https://vd171.ru
   Site           : https://vd.priv8.ru
   Source         : https://github.com/VD171/VDLiveUpdate
   GitHub         : @VD171 https://github.com/VD171
   XDA-Developers : @VD171 https://xdaforums.com/m/vd171.4699873/
   Telegram       : @VD_Priv8 https://t.me/VD_Priv8
   Channel        : @Priv8_VD https://t.me/Priv8_VD
   Discord        : @VD.Priv8 https://discord.com/users/1296831918989639721
   E-mail         : vd.priv8@pm.me
  ======================================================================
-->

# VDLiveUpdate

> **Languages:** [English](README.md) · [العربية](README.ar.md) · [Čeština](README.cs.md) · [Deutsch](README.de.md) · [Español](README.es.md) · [فارسی](README.fa.md) · [Français](README.fr.md) · [हिन्दी](README.hi.md) · [Bahasa Indonesia](README.id.md) · [Italiano](README.it.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Nederlands](README.nl.md) · [Polski](README.pl.md) · [Português](README.pt.md) · [Русский](README.ru.md) · [Svenska](README.sv.md) · [ไทย](README.th.md) · [Türkçe](README.tr.md) · [Українська](README.uk.md) · [Tiếng Việt](README.vi.md) · [中文](README.zh.md)

**VDLU** एक फ़्लैशलेस, वृद्धिशील सेल्फ़-अपडेट इंजन है जो **KernelSU / APatch / Magisk** मॉड्यूल के लिए है। एक इंस्टॉल्ड मॉड्यूल **केवल बदली हुई फ़ाइलों** (कंटेंट-एड्रेस्ड ब्लॉब्स + एक हस्ताक्षरित मैनिफ़ेस्ट) को लाकर खुद को अपडेट करता है, लाइव फ़ाइलों को **बिना रीबूट** लागू करता है, और उन चंद फ़ाइलों को स्टेज तथा फ़्लैग करता है जिन्हें रीबूट की ज़रूरत होती है (एक `.so`, एक `/system` ओवरले, एक `sepolicy.rule`)। कोई रूट प्रबंधक नहीं, पूरे `.zip` को दोबारा डाउनलोड करना नहीं, और उन स्टेज की गई फ़ाइलों के अलावा कोई रीबूट नहीं।

इसे किसी मॉड्यूल में **vendored** किए जाने के लिए डिज़ाइन किया गया है (`<module>/vdlu/` में रखा जाता है), न कि खुद एक मॉड्यूल के रूप में चलाने के लिए।

## क्यों

एक सामान्य मॉड्यूल अपडेट पूरे `.zip` को फिर से भेजता है। किसी बड़े मॉड्यूल के लिए इसका मतलब कुछ बदली हुई लाइनों के लिए एक भारी री-डाउनलोड है, और एक स्थिर अपडेट मैनिफ़ेस्ट केवल एक ही `zipUrl` की ओर इशारा कर सकता है, इसलिए वह वही फ़्लेवर (ABI, full बनाम lite) नहीं परोस सकता जो डिवाइस के पास वास्तव में है। VDLU **इंस्टॉल्ड** ट्री की तुलना एक हस्ताक्षरित फ़ीड से करता है और केवल डेल्टा लाता है, इसलिए एक arm64-full इंस्टॉल arm64-full बना रहता है, एक lite इंस्टॉल lite बना रहता है, और अधिकांश अपडेट लाइव लागू होते हैं।

## यह कैसे काम करता है

- **Producer (PC / रिलीज़):** `vdlu-pack` एक मॉड्यूल ट्री को एक कंटेंट-एड्रेस्ड फ़ीड में बदलता है (`manifest.json` + `blobs/<sha256>`, gzip, dedup, `delete[]`); `vdlu-keygen` / `vdlu-sign` (ed25519); `vdlu-gc` अनाथ ब्लॉब्स को अंतिम N मैनिफ़ेस्ट के संदर्भ से छाँटता है (fail-safe, डिफ़ॉल्ट रूप से dry-run)।
- **Engine (डिवाइस):** POSIX sh, कोई `jq` नहीं। `update.sh` (`check | run | resume | boot | status | cancel`) एक **पुनः-आरंभ-योग्य (resumable) लेन-देन** (journal) के रूप में DIFF -> FETCH -> APPLY -> COMMIT चलाता है, रोलबैक और एक `mkdir` लॉक के साथ। हस्ताक्षर को अंतर्निहित `ed25519-mini` द्वारा सत्यापित किया जाता है (डिवाइस पर कोई `openssl` नहीं)।
- **WebUI:** एक ड्रॉप-इन Updates पैनल (प्रगति टोस्ट, cancel, reboot बैनर), वनीला JS।

## प्रोफ़ाइलें

- `trusted`: निजी उपयोग, `file://` या SSH स्रोत, best-effort सत्यापन (हैश हमेशा)।
- `hardened`: सार्वजनिक उपयोग, **हस्ताक्षर अनिवार्य**, डाउनग्रेड अवरुद्ध। मैनिफ़ेस्ट **मॉड्यूल id से बँधा होता है**, और कुछ भी डाउनलोड होने से पहले हर फ़ील्ड fail-closed रूप से मान्य की जाती है।

## इसे अपने मॉड्यूल में अपनाएँ

`engine/update.sh` + `vdlu-verify` + `verify/<abi>/ed25519-mini` को `<module>/vdlu/` में vendor करें, अपनी **raw 32-byte public key** को `vdlu/keyring/<id>.pub` के रूप में embark करें, एक `config` जोड़ें (profile + source), ट्रिगर वायर करें (बूट पर ऑटो-अपडेट के लिए `post-fs-data.sh` pre-zygote; एक WebUI-open ट्रिगर), और अपने रिलीज़ में `vdlu-pack` + `vdlu-sign` जोड़ें। एक तैयार टेम्पलेट के लिए [`integration/`](integration/) देखें।

## सुरक्षा

- **हर मैनिफ़ेस्ट फ़ील्ड शत्रुतापूर्ण इनपुट है।** `validate_plan()` किसी भी फ़ेच या apply से **पहले** पूरे मैनिफ़ेस्ट को fail-closed अस्वीकार कर देता है यदि कोई पथ निरपेक्ष हो या उसमें `..` हो, कोई `sha256` जो 64 hex अक्षर न हो, या कोई अमान्य mode / class / encoding हो।
- **निजी हस्ताक्षर कुंजी कभी CI या किसी डिवाइस को नहीं छूती**; केवल raw public key अंतर्निहित की जाती है, और सत्यापन `ed25519-mini` का उपयोग करता है, `openssl` का नहीं।
- `hardened` उलटाव (inversion) के ज़रिए fail-closed है: शाब्दिक `trusted` के अलावा कुछ भी `hardened` माना जाता है, इसलिए एक भ्रष्ट profile मान कभी भी चुपचाप किसी अहस्ताक्षरित मैनिफ़ेस्ट को स्वीकार नहीं कर सकता।
- रीबूट-श्रेणी की फ़ाइलें (`.so`, `/system` ओवरले, `sepolicy.rule`) को **स्टेज किया जाता है, कभी भी किसी लाइव inode पर नहीं लिखा जाता**; बाक़ी सब कुछ लाइव लागू होता है। एक असफल apply बिना बैकअप के ओवरराइट करने के बजाय गर्भपात (abort) कर देता है।

## बिल्ड / टेस्ट

यह स्क्रिप्ट्स हैं, कंपाइल करने के लिए कुछ नहीं। एंड-टू-एंड (producer + engine एक साथ):

```sh
producer/vdlu-keygen demo /tmp/k
producer/vdlu-pack /tmp/tree /tmp/feed demo 1 --version-name v1
producer/vdlu-sign /tmp/feed/manifest.json /tmp/k/demo.pem demo
VDLU_DIR=... MODULE_DIR=... MODID=demo sh engine/update.sh check   # then run / boot
```

`sh -n engine/*.sh`, `node --check webui/vdlu.js`, और `webui/demo.html` को किसी ब्राउज़र में खोलें (यह डिवाइस ब्रिज को mock करता है)।

## दस्तावेज़ीकरण

- [`INTERFACES.md`](INTERFACES.md): घटकों के बीच सीवन-अनुबंध (seam contract) (अभिसरण का नियम; इसे अपरिवर्तनीय मानें)।
- `integration/`: एक चरण-दर-चरण अपनाने की मार्गदर्शिका और वायरिंग स्निपेट्स।

## यह भी देखें

उसी लेखक की सहोदर परियोजनाएँ:

- **[VDBackup](https://github.com/VD171/VD-Backup)**: रूट के रूप में पूर्ण ऐप और डेटा बैकअप तथा पुनर्स्थापना, पूरी तरह एक WebUI से संचालित।
- **[COPG-VD](https://github.com/VD171/COPG-VD)**: एक डिवाइस स्पूफ़र जो एक ताज़ा फ़िंगरप्रिंट को एक सुसंगत, संगत प्रोफ़ाइल में बदल देता है।
- **[VD-dropbear](https://github.com/VD171/VD-dropbear)**: KernelSU/APatch/Magisk के लिए एक स्वतंत्र, कॉन्फ़िगर करने योग्य रूटेड SSH डीमन।
- **[VDInfos](https://github.com/VD171/VD-Infos)**: एक डिवाइस मेथड डिबगर जो हर आइटम को उस हर मेथड से पढ़ता है जो उसे पढ़ सकता है।
- **[VDGoogle](https://github.com/VD171/VD-Google)**: पढ़ता है कि Google आपके डिवाइस पर क्या रिकॉर्ड करता है, पूरी तरह ऑन-डिवाइस और बिना इंटरनेट के।

## संपर्क

- https://vd171.ru
- https://vd.priv8.ru
- **Telegram:** @VD_Priv8 https://t.me/VD_Priv8
- **Channel:** @Priv8_VD https://t.me/Priv8_VD
- **Discord:** @VD.Priv8 https://discord.com/users/1296831918989639721
- **E-mail:** vd.priv8@pm.me
- **XDA-Developers:** @VD171 https://xdaforums.com/m/vd171.4699873/
- **GitHub:** @VD171 https://github.com/VD171

## लाइसेंस

VDLiveUpdate का अपना कोड **Apache-2.0** है; देखें [LICENSE](LICENSE)। यह एक छोटे `ed25519-mini`
सत्यापनकर्ता और फ़ेच बूटस्ट्रैप के लिए एक स्थिर `curl` को vendor करता है, प्रत्येक अपने-अपने लाइसेंस के तहत; देखें
[NOTICE.md](NOTICE.md) और बंडल की गई बाइनरियों के साथ मौजूद `PROVENANCE.json` फ़ाइलें।

## ट्रेडमार्क

VDLiveUpdate एक स्वतंत्र, अनौपचारिक परियोजना है, जो किसी तीसरे पक्ष से संबद्ध या समर्थित नहीं है।
"Android" Google LLC का ट्रेडमार्क है; "KernelSU", "Magisk" और "APatch" अपने-अपने लेखकों के चिह्न हैं।
VDLU पूरी तरह आपके डिवाइस पर और आपके अपने रिलीज़ होस्ट पर चलता है।

## Tags

`VDLU` `flashless-update` `incremental-update` `KernelSU` `Magisk` `APatch` `module-update` `ed25519` `content-addressed` `OTA` `self-update` `Android` `VDLiveUpdate`
