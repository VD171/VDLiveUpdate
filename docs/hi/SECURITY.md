> **Languages:** [English](../../SECURITY.md) · [العربية](../ar/SECURITY.md) · [Čeština](../cs/SECURITY.md) · [Deutsch](../de/SECURITY.md) · [Español](../es/SECURITY.md) · [فارسی](../fa/SECURITY.md) · [Français](../fr/SECURITY.md) · हिन्दी · [Bahasa Indonesia](../id/SECURITY.md) · [Italiano](../it/SECURITY.md) · [日本語](../ja/SECURITY.md) · [한국어](../ko/SECURITY.md) · [Nederlands](../nl/SECURITY.md) · [Polski](../pl/SECURITY.md) · [Português](../pt/SECURITY.md) · [Русский](../ru/SECURITY.md) · [Svenska](../sv/SECURITY.md) · [ไทย](../th/SECURITY.md) · [Türkçe](../tr/SECURITY.md) · [Українська](../uk/SECURITY.md) · [Tiếng Việt](../vi/SECURITY.md) · [中文](../zh/SECURITY.md)

---

# सुरक्षा नीति

VDLiveUpdate (VDLU) एक चालू मॉड्यूल पर flashless root अपडेट लागू करता है: यह मॉड्यूल की अपनी
डायरेक्टरी में लिखता है और बूट के समय एक Zygisk `.so` को बदल देता है, और मॉड्यूल के root
संदर्भ में चलता है। हम सुरक्षा को गंभीरता से लेते हैं।

## किसी भेद्यता की रिपोर्ट करना

- **Site:** https://vd171.ru
- **Site:** https://vd.priv8.ru
- **Issues:** https://github.com/VD171/VDLiveUpdate/issues
- **GitHub:** [@VD171](https://github.com/VD171)
- **XDA-Developers:** [@VD171](https://xdaforums.com/m/vd171.4699873/)
- **Telegram:** [@VD_Priv8](https://t.me/VD_Priv8)
- **Channel:** [@Priv8_VD](https://t.me/Priv8_VD)
- **Discord:** [@VD.Priv8](https://discord.com/users/1296831918989639721)
- **E-mail:** vd.priv8@pm.me

एक स्पष्ट विवरण और, यदि संभव हो, एक manifest या feed शामिल करें जो समस्या को पुन: उत्पन्न
करता है। हम जितनी जल्दी हो सके जवाब देंगे और यदि आप चाहें तो आपको श्रेय देंगे।

## दायरे संबंधी टिप्पणियाँ

- अपडेट content-addressed ब्लॉब्स के साथ एक ed25519 से हस्ताक्षरित `manifest.json` होते हैं।
  डिवाइस एक एम्बेडेड `ed25519-mini` से हस्ताक्षर सत्यापित करता है (डिवाइस पर openssl नहीं), और
  उपयोग से पहले प्रत्येक blob को उसके `sha256` के विरुद्ध जाँचा जाता है।
- hardened प्रोफ़ाइल (सार्वजनिक डिफ़ॉल्ट) एक मान्य हस्ताक्षर की माँग करती है और downgrade को
  रोकती है। "स्रोत" संस्करण स्थापित मॉड्यूल के `versionCode` (जो `module.prop` से पढ़ा जाता
  है) द्वारा नीचे से सीमित होता है, इसलिए किसी मॉड्यूल को कभी भी feed से पीछे नहीं लौटाया
  जाता।
- विश्वास की जड़ (`keyring/` में कच्ची ed25519 सार्वजनिक कुंजी और `verify/` के बाइनरी) केवल
  flash है और इसे कभी भी नेटवर्क के ज़रिए घुमाया नहीं जाता। निर्माता इसे feed से बाहर रखता है
  और engine डाउनलोड की गई योजना में हर `vdlu/` पथ को अनदेखा करता है, इसलिए एक लीक हुई हस्ताक्षर
  कुंजी सत्यापनकर्ता या कुंजी को बदल कर root बनाए नहीं रख सकती।
- किसी अन्य मॉड्यूल के लिए मान्य रूप से हस्ताक्षरित manifest किसी भिन्न मॉड्यूल की डायरेक्टरी
  में नहीं लिख सकता। हस्ताक्षरित `module` फ़ील्ड डिवाइस पर `MODID` के बराबर होना चाहिए
  (मॉड्यूल-के-बीच बाइंडिंग जाँच), और हर लेखन और विलोपन मॉड्यूल डायरेक्टरी तक सीमित रहता है।
- engine मॉड्यूल के अपने root संदर्भ में चलता है और उसे कभी कमज़ोर नहीं करता। यह कोई
  विशेषाधिकार नहीं जोड़ता और किसी भी manifest फ़ील्ड को shell में प्रक्षेपित नहीं करता, उपयोग
  से पहले हर `path`, `sha256`, `mode` और `delete[]` मान को शत्रुतापूर्ण इनपुट के रूप में
  सत्यापित किया जाता है।
- रुख fail-closed है। एक दूषित या अज्ञात `profile` मान कभी भी बिना हस्ताक्षर वाली सामग्री को
  स्वीकार करने तक नहीं फिसलता (जो कुछ भी ठीक `trusted` नहीं है उसे `hardened` माना जाता है),
  और किसी भी फ़ाइल के ऊपर लिखे जाने से पहले एक बैकअप लिखा जाता है, इसलिए एक विफल apply कभी भी
  स्थापित संस्करण को नष्ट नहीं करता।
- पूर्ण विश्वास मॉडल, fail-closed गारंटी और hardening विवरण के लिए
  [TRUST-MODEL.md](TRUST-MODEL.md) देखें।

<!-- doc-footer -->

---

> _यह दस्तावेज़ Claude (Anthropic) से तैयार किया गया है और इसे VD171 द्वारा अनुरक्षित किया जाता है। सुधार और संशोधन का स्वागत है, देखें [CONTRIBUTING.md](CONTRIBUTING.md)।_
