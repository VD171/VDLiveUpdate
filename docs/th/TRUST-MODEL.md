> **Languages:** [English](../TRUST-MODEL.md) · [العربية](../ar/TRUST-MODEL.md) · [Čeština](../cs/TRUST-MODEL.md) · [Deutsch](../de/TRUST-MODEL.md) · [Español](../es/TRUST-MODEL.md) · [فارسی](../fa/TRUST-MODEL.md) · [Français](../fr/TRUST-MODEL.md) · [हिन्दी](../hi/TRUST-MODEL.md) · [Bahasa Indonesia](../id/TRUST-MODEL.md) · [Italiano](../it/TRUST-MODEL.md) · [日本語](../ja/TRUST-MODEL.md) · [한국어](../ko/TRUST-MODEL.md) · [Nederlands](../nl/TRUST-MODEL.md) · [Polski](../pl/TRUST-MODEL.md) · [Português](../pt/TRUST-MODEL.md) · [Русский](../ru/TRUST-MODEL.md) · [Svenska](../sv/TRUST-MODEL.md) · ไทย · [Türkçe](../tr/TRUST-MODEL.md) · [Українська](../uk/TRUST-MODEL.md) · [Tiếng Việt](../vi/TRUST-MODEL.md) · [中文](../zh/TRUST-MODEL.md)

---

# นโยบายความปลอดภัยและ trust model

VDLiveUpdate (VDLU) ใช้ **การอัปเดต root แบบ flashless** กับโมดูลที่กำลังทำงานอยู่: มันเขียน
ลงใน `/data/adb/modules/<mod>` และ swap `.so` ของ Zygisk ตอน boot ทุกฟิลด์ของ manifest
ที่ fetch มา (`path`, `sha256`, `delete[]`, `mode`, ...) คือ **input ที่เป็นอันตราย** - ฟีดที่ถูกวางยา
หรือ MITM เป็นผู้ส่งมันมา หน้านี้คือ trust model และนโยบายการเปิดเผยช่องโหว่อย่างมีความรับผิดชอบ
สำหรับสัญญา seam เต็มรูปแบบดูที่ [`INTERFACES.md`](INTERFACES.md), และ internals ของ engine/producer
ใน [`ENGINE.md`](ENGINE.md) และ [`PRODUCER.md`](PRODUCER.md), หน้าวิกิ **Security-and-Trust-Model**
พก model เดียวกันนี้ไว้สำหรับผู้อ่านนอก repo

## เวอร์ชันที่รองรับ

การแก้ไขด้านความปลอดภัยลงใน `ENGINE_VERSION` ล่าสุด, manifest ที่เซ็นแล้วประกาศ engine ขั้นต่ำ
ที่มันต้องการผ่าน `engine_min`, และ engine บนอุปกรณ์ปฏิเสธ manifest ที่ขอมากกว่าที่มันทำได้ engine
ที่ถูก vendor ไว้รุ่นเก่าคาดว่าจะต้อง **re-vendor** เพื่อรับการแก้ไข, ไม่ใช่ถูก back-patch ในที่เดิม

| ENGINE_VERSION | สถานะ |
|---|---|
| 7 (ปัจจุบัน) | รองรับ - ไม่ย้อนโมดูลที่ล้ำหน้ากว่าฟีด (`versionCode` ที่ติดตั้งอยู่จริงเป็นขอบล่างของเวอร์ชัน "from"), การซ่อมแซมตัวเองตอนบูตสำหรับ downgrade plan เก่า |
| 6 | ถูกแทนที่ - การซ่อมแซมตัวเองตอนบูตสำหรับ journal เก่าที่มี `target <= 0` (baseline 0 ที่ stub ที่ถูกลบทิ้งไว้ ไม่ขับเคลื่อน UI หรือการกระทำตอนบูตอีกต่อไป) |
| 5 | ถูกแทนที่ - การกัน trust anchor ออกฝั่ง engine (ไดเรกทอรี `vdlu/` ถูกเพิกเฉยแม้ว่าฟีดจะพกมันมา), เพดาน 128 MiB ต่อไฟล์ / 2 MiB สำหรับ manifest |
| 4 | ถูกแทนที่ - allowlist ของ `key_id`, ปฏิเสธ path ที่มี dot-segment/trailing-slash, size cap, check-time lock |
| <= 3 | ไม่รองรับ - re-vendor engine ปัจจุบัน |

การเปลี่ยนแปลงใด ๆ ต่อการ verify ของ engine หรือ logic การ apply จะดัน `ENGINE_VERSION` ขึ้น

## การรายงานช่องโหว่

รายงานแบบส่วนตัว **อย่า** เปิด issue, PR, หรือโพสต์ในฟอรัมแบบสาธารณะสำหรับบั๊กด้านความปลอดภัย
ใช้ช่องทางติดต่อของโปรเจกต์ (ดู [`CONTRIBUTING.md`](../CONTRIBUTING.md)):

- Telegram: **@VD_Priv8** (https://t.me/VD_Priv8)
- ช่อง: **@Priv8_VD** (https://t.me/Priv8_VD)
- อีเมล: **vd.priv8@pm.me**

กรุณาแนบเวอร์ชันของ engine, `profile` ที่ใช้อยู่, และ manifest หรือฟีดที่ reproduce ปัญหาได้ การแก้ไข
ส่งมาในรูปของ `ENGINE_VERSION` ใหม่พร้อมรายการใน `CHANGELOG.md`, ประสานงานเวลาเปิดเผยกันใน
เธรดของรายงาน

## Trust model

- **ลายเซ็น ed25519 แบบ detached** producer เซ็น manifest แบบ canonical บน PC (openssl), อุปกรณ์
  verify ด้วย `ed25519-mini` ที่ฝังไว้ - **ไม่มี openssl บนอุปกรณ์** ข้อความที่ถูกเซ็นคือ sha256 hex
  ของ manifest ที่ปราศจากฟิลด์ `sig` (คีย์เรียงลำดับ, compact, UTF-8), ดังนั้น sign และ verify จึง derive
  ไบต์เดียวกันบนสอง runtime โดยไม่ต้องใช้ JSON library บนอุปกรณ์
- **Keyring = pubkey RAW 32 ไบต์**, flash-only keyring บนอุปกรณ์ ship `<key_id>.pub` ในรูปของคีย์ RAW
  32 ไบต์ (ไม่เคยเป็น PEM), `vdlu-pack` **กัน** keyring และไบนารี `verify/` ออกจากฟีด, ดังนั้น manifest
  จึงไม่มีทางเขียนทับ trust anchor บนอุปกรณ์ผ่านเครือข่ายได้
- **การกัน trust anchor ออกฝั่ง engine (VDLU#2)** เป็นอิสระจากการกันฝั่ง producer ข้างต้น engine บนอุปกรณ์
  **เพิกเฉย** ทุก path `vdlu/` (`update.sh`, `vdlu-verify`, `verify/*`, `keyring/*`, config) ใน plan ที่
  fetch มา - มันไม่เคย fetch, apply, หรือลบพวกมัน แม้ว่าฟีดจะพกมันมา ฟีดที่เผยแพร่แล้ว ship ต้นไม้โมดูลทั้งหมด
  รวมถึง `vdlu/` ดังนั้น engine จึงทิ้ง path เหล่านั้นอย่างเงียบ ๆ แทนที่จะปฏิเสธ manifest: โมดูลยังอัปเดตอยู่
  และ trust anchor เปลี่ยนได้เฉพาะผ่านการ re-flash ที่เซ็นแล้วเต็มรูปแบบเท่านั้น คีย์สำหรับเซ็นที่รั่วไหลเพียง
  คีย์เดียวไม่สามารถ swap verifier หรือคีย์สำหรับเซ็นผ่านเครือข่ายและคง root ไว้ได้อีกต่อไป
- **allowlist ของ `key_id` สำหรับ module-update (fail-closed, ก่อนการเลือก pubkey)** keyring อาจพกคีย์
  มากกว่าหนึ่งอย่างชอบธรรม (เช่น คีย์ fingerprint-feed ที่ความเชื่อถือต่ำกว่าเคียงข้างคีย์ release) ก่อนที่
  `<key_id>.pub` จะถูกเลือก, `verify_manifest` ปฏิเสธ manifest ใด ๆ ที่ `key_id` ไม่อยู่ใน allowlist ที่
  กำหนดไว้, ใน **ทั้งสอง** profiles, และสะท้อน set ที่ resolve แล้วเข้า `vdlu-verify` ผ่าน `VDLU_KEYID_ALLOW`
  สิ่งนี้ปิด bypass ที่คีย์ความเชื่อถือต่ำกว่าซึ่งรั่วไหลอาจเซ็นการอัปเดต flashless root เต็มรูปแบบได้
  ปลอดภัยโดยปริยายเมื่อ `key_id` ไม่ได้ตั้งค่า: keyring **คีย์เดียว** auto-pin ไปที่คีย์นั้นหนึ่งเดียว;
  keyring **หลายคีย์** จะถูกปฏิเสธจนกว่าจะปักหมุด `key_id` (คั่นด้วยจุลภาคสำหรับการ rotate)
- **trust root ของ fingerprint-feed เป็น path แยกต่างหากที่ปักหมุดไว้** พร้อมคีย์ของตัวเอง, มันไม่เคย
  เข้าถึงได้ผ่าน path ของ module-update ข้างต้น
- **Baseline คือ seed ที่เชื่อถือได้แบบ local** `baseline.json` มาใน zip ที่ flash - ขอบเขตความเชื่อถือของ
  การติดตั้ง - ดังนั้นมันไม่มีลายเซ็นและไม่มีคีย์ และ **ไม่** ถูกรันผ่าน `vdlu-verify`, เฉพาะ manifest ที่
  **fetch** จากฟีดเท่านั้นที่ถูก verify สิ่งนี้เก็บคีย์สำหรับเซ็นให้อยู่นอก CI

## การรับประกันแบบ fail-closed

- **`validate_plan` รันก่อน fetch หรือ apply ใด ๆ** ใน `do_diff`, แบบ fail-closed, มันปฏิเสธ manifest
  **ทั้งก้อน** หาก `path` ใดเป็น absolute, มี segment `..` หรือ `.`, ลงท้ายด้วย `/`, หรือมี control character;
  หาก `sha256` ใดไม่ตรง `^[0-9a-f]{64}$`, หรือหาก `mode`/`class`/`enc` ใดไม่ถูกต้อง ไม่มีฟิลด์ที่เป็น
  อันตรายเข้าถึง shell, และ `cmd_check` ไม่มีการ interpolate แบบ `system()`
- **การ contain ของ path** ทุกการเขียนและการลบถูกจำกัดอยู่ใน `MODULE_DIR` ผ่าน `contained()` - apply,
  delete, และ `stage_file` ตอน reboot ล้วนผ่าน guard เดียวกัน symlink ในต้นไม้ถูกข้ามโดย producer
  (ไม่เคยรั่วเนื้อหาจากนอกมัน)
- **สอง profiles, fail-closed โดยการ invert** `trusted` (ส่วนตัว, source ที่ stage ผ่าน SSH) คือ opt-in
  **เพียงหนึ่งเดียว** สู่การ verify แบบ best-effort, ค่าอื่น **ใด ๆ** - รวมถึง typo, trailing space/CR, หรือ
  case ที่ต่างไป - ถูกปฏิบัติเป็น `hardened`, ซึ่งลายเซ็นที่ถูกต้องเป็น **ข้อบังคับ** และความล้มเหลวจะ abort
  `sha256` ของทุก blob ถูกตรวจสอบในทั้งสอง profiles
- **ลายเซ็น + hash ก่อนการ exec tool ใด ๆ** `curl` แบบ static ที่ fetch มารันในฐานะ root, ดังนั้น
  `install-tool` verify ลายเซ็นของ tools-manifest (ed25519-mini, บังคับใน **ทุก** profile) และ hash ของ curl
  **ก่อน** มันถูกติดตั้งและ exec - sig+hash ก่อน exec ปิด RCE
- **ทรานแซกชันที่ resume ได้และ pin ปลอดภัย** manifest ที่กำลังดำเนินอยู่ถูกปักหมุดใน `target.json`, crash,
  เครือข่ายขาด, หรือ reboot จะ resume จาก journal โดยไม่ตัดสิน plan ใหม่ downgrade ถูกบล็อก (`version` แบบ
  monotonic), ฟิลด์ `module` ที่เซ็นแล้วต้องเท่ากับ `MODID`, และ `delete[]` รันเฉพาะที่ `finalize_done`
  (`PENDING_REBOOT` ไม่ลบอะไร) ไม่มีสิ่งใด "เสร็จ" โดยไม่มีการ re-hash เต็มรูปแบบ, ไม่มีสิ่งใดถูกเขียนทับ
  โดยไม่มี backup `rollback/<v>/` ก่อน

## การ hardening (defense in depth)

- **Size cap** manifest, tools-manifest, และ path การดาวน์โหลดแบบ `wget`/`head -c` ที่ไม่มี curl ล้วนถูก
  bound ก่อนถูกอ่าน (anti-OOM / anti-flood) blob จะล้มเหลวในเฟสของมันหลังจาก 3 ครั้ง เพดานคือ
  **128 MiB ต่อไฟล์** (`MAX_FILE_BYTES`) และ **2 MiB สำหรับ manifest** (`MAX_MANIFEST_BYTES`), บังคับใช้ใน
  `update.sh` และสะท้อนใน `vdlu-verify`
- **Check-time lock** `check` คว้า mkdir-lock ก่อน rebuild work dir ของมัน, ดังนั้น run ที่ทำงานพร้อมกัน
  จึง race มันไม่ได้
- **การ contain ของ staging** `stage_file` มี guard `contained()` เดียวกับ primitive ของ live apply,
  ดังนั้น path แบบ reboot-hard ที่ stage ไว้จึงหนีออกจาก `MODULE_DIR` ไม่ได้เช่นกัน
- **TLS คือ defense in depth, ไม่ใช่ trust root** curl แบบ static ใช้ mbedTLS กับ trust store ของ Android
  (`--capath`, override ด้วย `ca_path`), การรับประกัน integrity คือลายเซ็น ed25519, การตรวจ cert เป็นชั้นที่สอง

## ดูเพิ่มเติม

- [`INTERFACES.md`](INTERFACES.md) - สัญญา seam ที่ไม่เปลี่ยนแปลง (§5 config, §6 signature, §11 toolchain)
- [`ENGINE.md`](ENGINE.md) - engine ฝั่งอุปกรณ์และเครื่องจักรสถานะของมัน
- [`PRODUCER.md`](PRODUCER.md) - การ pack, การ sign, canonicalization, และการ rotate คีย์
- วิกิ: **Security-and-Trust-Model**

<!-- doc-footer -->

---

> _เอกสารนี้สร้างขึ้นด้วย Claude (Anthropic) และดูแลโดย VD171 ยินดีรับการแก้ไขและการปรับปรุง ดู [CONTRIBUTING.md](CONTRIBUTING.md)_
