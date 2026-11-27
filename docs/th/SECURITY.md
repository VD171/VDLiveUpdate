> **Languages:** [English](../../SECURITY.md) · [العربية](../ar/SECURITY.md) · [Čeština](../cs/SECURITY.md) · [Deutsch](../de/SECURITY.md) · [Español](../es/SECURITY.md) · [فارسی](../fa/SECURITY.md) · [Français](../fr/SECURITY.md) · [हिन्दी](../hi/SECURITY.md) · [Bahasa Indonesia](../id/SECURITY.md) · [Italiano](../it/SECURITY.md) · [日本語](../ja/SECURITY.md) · [한국어](../ko/SECURITY.md) · [Nederlands](../nl/SECURITY.md) · [Polski](../pl/SECURITY.md) · [Português](../pt/SECURITY.md) · [Русский](../ru/SECURITY.md) · [Svenska](../sv/SECURITY.md) · ไทย · [Türkçe](../tr/SECURITY.md) · [Українська](../uk/SECURITY.md) · [Tiếng Việt](../vi/SECURITY.md) · [中文](../zh/SECURITY.md)

---

# นโยบายความปลอดภัย

VDLiveUpdate (VDLU) ใช้การอัปเดตแบบ flashless ด้วยสิทธิ์ root กับโมดูลที่กำลังทำงาน
โดยจะเขียนลงในไดเรกทอรีของโมดูลเองและสลับไฟล์ `.so` ของ Zygisk ขณะบูต ทำงานในบริบท root
ของโมดูล เราให้ความสำคัญกับความปลอดภัยอย่างจริงจัง

## การรายงานช่องโหว่

- **Site:** https://vd171.ru
- **Site:** https://vd.priv8.ru
- **Issues:** https://github.com/VD171/VDLiveUpdate/issues
- **GitHub:** [@VD171](https://github.com/VD171)
- **XDA-Developers:** [@VD171](https://xdaforums.com/m/vd171.4699873/)
- **Telegram:** [@VD_Priv8](https://t.me/VD_Priv8)
- **Channel:** [@Priv8_VD](https://t.me/Priv8_VD)
- **Discord:** [@VD.Priv8](https://discord.com/users/1296831918989639721)
- **E-mail:** vd.priv8@pm.me

โปรดแนบคำอธิบายที่ชัดเจน และหากเป็นไปได้ แนบ manifest หรือ feed ที่ทำให้เกิดปัญหาซ้ำได้
เราจะตอบกลับโดยเร็วที่สุดและให้เครดิตคุณหากคุณต้องการ

## หมายเหตุขอบเขต

- การอัปเดตคือบล็อบแบบ content-addressed พร้อมกับ `manifest.json` ที่ลงนามด้วย ed25519
  อุปกรณ์ตรวจสอบลายเซ็นด้วย `ed25519-mini` ที่ฝังอยู่ (ไม่มี openssl บนอุปกรณ์)
  และบล็อบแต่ละอันจะถูกตรวจสอบกับ `sha256` ของตัวเองก่อนนำไปใช้
- โปรไฟล์ hardened (ค่าเริ่มต้นสาธารณะ) กำหนดให้ต้องมีลายเซ็นที่ถูกต้องและบล็อก downgrade
  เวอร์ชัน "ต้นทาง" ถูกจำกัดขั้นต่ำด้วย `versionCode` ของโมดูลที่ติดตั้งไว้ (อ่านจาก
  `module.prop`) ดังนั้นโมดูลจะไม่ถูกย้อนกลับไปหลัง feed
- รากความเชื่อถือ (กุญแจสาธารณะ ed25519 แบบดิบใน `keyring/` และไบนารีใน `verify/`)
  เป็นแบบ flash เท่านั้นและไม่เคยถูกหมุนเวียนผ่านเครือข่าย ผู้ผลิตจะกันมันออกจาก feed
  และ engine จะเพิกเฉยต่อทุกเส้นทาง `vdlu/` ในแผนที่ดาวน์โหลดมา
  ดังนั้นกุญแจลงนามที่รั่วไหลจึงไม่สามารถสลับตัวตรวจสอบหรือกุญแจและคง root ไว้ได้
- manifest ที่ลงนามอย่างถูกต้องสำหรับอีกโมดูลหนึ่งไม่สามารถเขียนลงในไดเรกทอรีของโมดูลอื่นได้
  ฟิลด์ `module` ที่ลงนามต้องเท่ากับ `MODID` บนอุปกรณ์ (การตรวจสอบการผูกข้ามโมดูล)
  และการเขียนและการลบทุกครั้งจะถูกจำกัดอยู่ในไดเรกทอรีของโมดูล
- engine ทำงานในบริบท root ของโมดูลเองและไม่เคยทำให้มันอ่อนแอลง มันไม่เพิ่มสิทธิ์ใด ๆ
  และไม่แทรกฟิลด์ใดของ manifest ลงใน shell ค่าของ `path`, `sha256`, `mode` และ `delete[]`
  แต่ละค่าจะถูกตรวจสอบว่าเป็นอินพุตที่เป็นปฏิปักษ์ก่อนนำไปใช้
- ท่าทีเป็นแบบ fail-closed ค่า `profile` ที่เสียหายหรือไม่รู้จักจะไม่มีวันหลุดไปสู่การยอมรับ
  เนื้อหาที่ไม่ได้ลงนาม (สิ่งใดก็ตามที่ไม่ใช่ `trusted` เป๊ะ ๆ จะถูกปฏิบัติเป็น `hardened`)
  และจะมีการเขียนข้อมูลสำรองก่อนที่จะเขียนทับไฟล์ใด ๆ ดังนั้น apply ที่ล้มเหลวจะไม่มีวัน
  ทำลายเวอร์ชันที่ติดตั้งไว้
- ดูแบบจำลองความเชื่อถือแบบเต็ม การรับประกัน fail-closed และรายละเอียด hardening ได้ที่
  [TRUST-MODEL.md](TRUST-MODEL.md)

<!-- doc-footer -->

---

> _เอกสารนี้สร้างขึ้นด้วย Claude (Anthropic) และดูแลโดย VD171 ยินดีรับการแก้ไขและการปรับปรุง ดู [CONTRIBUTING.md](CONTRIBUTING.md)_
