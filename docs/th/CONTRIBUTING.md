> **Languages:** [English](../../CONTRIBUTING.md) · [العربية](../ar/CONTRIBUTING.md) · [Čeština](../cs/CONTRIBUTING.md) · [Deutsch](../de/CONTRIBUTING.md) · [Español](../es/CONTRIBUTING.md) · [فارسی](../fa/CONTRIBUTING.md) · [Français](../fr/CONTRIBUTING.md) · [हिन्दी](../hi/CONTRIBUTING.md) · [Bahasa Indonesia](../id/CONTRIBUTING.md) · [Italiano](../it/CONTRIBUTING.md) · [日本語](../ja/CONTRIBUTING.md) · [한국어](../ko/CONTRIBUTING.md) · [Nederlands](../nl/CONTRIBUTING.md) · [Polski](../pl/CONTRIBUTING.md) · [Português](../pt/CONTRIBUTING.md) · [Русский](../ru/CONTRIBUTING.md) · [Svenska](../sv/CONTRIBUTING.md) · ไทย · [Türkçe](../tr/CONTRIBUTING.md) · [Українська](../uk/CONTRIBUTING.md) · [Tiếng Việt](../vi/CONTRIBUTING.md) · [中文](../zh/CONTRIBUTING.md)

---

# การร่วมพัฒนา VDLiveUpdate

VDLU เป็นเอนจิน self-update แบบ incremental, flashless ที่ถูก vendor เข้าไปในโมดูล KernelSU/APatch/Magisk
ยินดีรับการร่วมพัฒนา

- อ่าน [INTERFACES.md](INTERFACES.md) ก่อน: มันคือสัญญารอยต่อระหว่างคอมโพเนนต์ (กฎ
  แห่งการบรรจบ) ปฏิบัติกับมันเป็นสิ่งที่เปลี่ยนแปลงไม่ได้ เว้นแต่การเปลี่ยนแปลงจะถูกประสานงานข้ามเอนจิน, producer และ WebUI
- ทดสอบ end to end ก่อน PR: `producer/vdlu-keygen`, `vdlu-pack`, `vdlu-sign`, แล้วจึงเอนจิน
  (`check` / `run` / `boot`) รวมถึง `sh -n engine/*.sh` และ `node --check webui/vdlu.js`
- ความปลอดภัยต่อรองไม่ได้: ทุกฟิลด์ของ manifest คือ input ที่เป็นปฏิปักษ์และ `validate_plan()` ยังคงเป็น
  fail-closed; คีย์สำหรับเซ็นแบบ private ไม่เคยแตะ CI หรืออุปกรณ์
- POSIX sh บนอุปกรณ์ (ไม่มี bashism นอกจาก `local`, ไม่มี `jq`); เขียนคอมเมนต์ให้กระชับ
- หนึ่งการเปลี่ยนแปลงเชิงตรรกะต่อ PR; บอกว่าเปลี่ยนอะไรและทำไม

## ติดต่อ

- Telegram: @VD_Priv8 https://t.me/VD_Priv8
- Channel: @Priv8_VD https://t.me/Priv8_VD
- E-mail: vd.priv8@pm.me

<!-- doc-footer -->

---

> _เอกสารนี้สร้างขึ้นด้วย Claude (Anthropic) และดูแลโดย VD171 ยินดีรับการแก้ไขและการปรับปรุง ดู [CONTRIBUTING.md](CONTRIBUTING.md)_
