> **Languages:** [English](../../CONTRIBUTING.md) · [العربية](../ar/CONTRIBUTING.md) · [Čeština](../cs/CONTRIBUTING.md) · [Deutsch](../de/CONTRIBUTING.md) · [Español](../es/CONTRIBUTING.md) · [فارسی](../fa/CONTRIBUTING.md) · [Français](../fr/CONTRIBUTING.md) · हिन्दी · [Bahasa Indonesia](../id/CONTRIBUTING.md) · [Italiano](../it/CONTRIBUTING.md) · [日本語](../ja/CONTRIBUTING.md) · [한국어](../ko/CONTRIBUTING.md) · [Nederlands](../nl/CONTRIBUTING.md) · [Polski](../pl/CONTRIBUTING.md) · [Português](../pt/CONTRIBUTING.md) · [Русский](../ru/CONTRIBUTING.md) · [Svenska](../sv/CONTRIBUTING.md) · [ไทย](../th/CONTRIBUTING.md) · [Türkçe](../tr/CONTRIBUTING.md) · [Українська](../uk/CONTRIBUTING.md) · [Tiếng Việt](../vi/CONTRIBUTING.md) · [中文](../zh/CONTRIBUTING.md)

---

# VDLiveUpdate में योगदान

VDLU एक flashless, incremental self-update engine है जो KernelSU/APatch/Magisk मॉड्यूलों में vendor किया जाता है।
योगदान का स्वागत है।

- पहले [INTERFACES.md](INTERFACES.md) पढ़ें: यह घटकों के बीच का सीवन अनुबंध है (अभिसरण
  का नियम)। इसे अपरिवर्तनीय मानें जब तक कि कोई बदलाव engine, producer और WebUI के पार समन्वित न हो।
- एक PR से पहले end to end परीक्षण करें: `producer/vdlu-keygen`, `vdlu-pack`, `vdlu-sign`, फिर engine
  (`check` / `run` / `boot`)। साथ ही `sh -n engine/*.sh` और `node --check webui/vdlu.js`।
- सुरक्षा गैर-परक्राम्य है: हर manifest फ़ील्ड शत्रुतापूर्ण इनपुट है और `validate_plan()` fail-closed रहता है;
  निजी हस्ताक्षर कुंजी कभी CI या किसी डिवाइस को स्पर्श नहीं करती।
- डिवाइस पर POSIX sh (`local` से परे कोई bashism नहीं, कोई `jq` नहीं), टिप्पणियाँ संक्षिप्त रखें।
- प्रति PR एक तार्किक बदलाव, बताएँ कि क्या बदला और क्यों।

## संपर्क

- Telegram: @VD_Priv8 https://t.me/VD_Priv8
- Channel: @Priv8_VD https://t.me/Priv8_VD
- E-mail: vd.priv8@pm.me

<!-- doc-footer -->

---

> _यह दस्तावेज़ Claude (Anthropic) से तैयार किया गया है और इसे VD171 द्वारा अनुरक्षित किया जाता है। सुधार और संशोधन का स्वागत है, देखें [CONTRIBUTING.md](CONTRIBUTING.md)।_
