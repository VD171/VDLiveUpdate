> **Languages:** [English](../AI-AGENTS.md) · [العربية](../ar/AI-AGENTS.md) · [Čeština](../cs/AI-AGENTS.md) · [Deutsch](../de/AI-AGENTS.md) · [Español](../es/AI-AGENTS.md) · [فارسی](../fa/AI-AGENTS.md) · [Français](../fr/AI-AGENTS.md) · [हिन्दी](../hi/AI-AGENTS.md) · [Bahasa Indonesia](../id/AI-AGENTS.md) · [Italiano](../it/AI-AGENTS.md) · [日本語](../ja/AI-AGENTS.md) · [한국어](../ko/AI-AGENTS.md) · [Nederlands](../nl/AI-AGENTS.md) · [Polski](../pl/AI-AGENTS.md) · [Português](../pt/AI-AGENTS.md) · [Русский](../ru/AI-AGENTS.md) · [Svenska](../sv/AI-AGENTS.md) · ไทย · [Türkçe](../tr/AI-AGENTS.md) · [Українська](../uk/AI-AGENTS.md) · [Tiếng Việt](../vi/AI-AGENTS.md) · [中文](../zh/AI-AGENTS.md)

---

# ขับเคลื่อน VDLU จากเอเจนต์ AI

VDLiveUpdate (VDLU) คือตัวอัปเดตแบบเพิ่มหน่วยที่ไม่ต้องแฟลช ซึ่งโมดูล KSU/Magisk ฝังไว้ใน `vdlu/` ทั้งเอนจินถูกขับเคลื่อนจากเชลล์ ดังนั้นผู้ช่วยหรือเอเจนต์ AI จึงสามารถตรวจสอบ ปรับใช้ ดำเนินต่อ และทำการอัปเดตให้เสร็จแบบไม่มีส่วนติดต่อได้ เป็นวงจรเดียวกับที่ WebUI รัน โดยไม่มี UI และไม่มีมนุษย์ในลูป จงแยกวิเคราะห์ JSON ที่มันพิมพ์ อย่าขูดข้อความเด็ดขาด

## สัญญา

จุดเข้าเพียงจุดเดียว รันในฐานะ root บนอุปกรณ์ โดยตั้งค่าตัวแปรสภาพแวดล้อมสามตัวของเอนจิน:

```sh
VDLU_DIR=/data/adb/<mod>/vdlu MODULE_DIR=/data/adb/modules/<mod> MODID=<mod> \
  sh "$MODULE_DIR/vdlu/update.sh" <verb>
```

- `VDLU_DIR` คือไดเรกทอรีสถานะ Tier-2 (อยู่นอกโมดูล รอดจากการรีแฟลช), `MODULE_DIR` คือต้นไม้โมดูลที่มีชีวิต, `MODID` คือ id ของโมดูล
- `rc 0` = โอเค, `rc != 0` = ข้อผิดพลาด พร้อมเหตุผลบน stderr
- คำกริยาอ่าน (`check`, `status`) พิมพ์ **อ็อบเจกต์ JSON หนึ่งตัว** บน stdout จงแยกวิเคราะห์มัน อย่าขูดข้อความเด็ดขาด
- เอนจินพึ่งพาเพียง toybox (`sha256sum`/`gzip`/`base64`) บวก `ed25519-mini` ที่ฝังไว้ บวก `curl` แบบสแตติกที่ดึงมาในการอัปเดต https ครั้งแรก ศูนย์ `jq`

ระหว่างการพัฒนา สคริปต์เดียวกันอยู่ที่ `engine/update.sh` ในที่เก็บนี้ ดังนั้น `sh engine/update.sh <verb>` โดยตั้งค่าตัวแปรสามตัวจึงขับเคลื่อนสำเนาทดสอบในแบบเดียวกัน

## คำกริยา

| คำกริยา | ทำอะไร | พิมพ์ |
|------|------|--------|
| `check` | DIFF แบบอ่านอย่างเดียวเทียบกับฟีด ไม่เปลี่ยนอะไรเลย | `{"update":bool,"from":N,"to":M,"fetch":K,"reboot":bool}` หรือ `{"update":false,"ahead":true,"from":N,"to":M}` เมื่ออุปกรณ์ล้ำหน้าฟีด (บล็อกการดาวน์เกรด ไม่เป็นภัย rc 0) |
| `run` | วงจร LIVE เต็มรูป DIFF -> FETCH -> APPLY -> COMMIT ปรับใช้ไฟล์ LIVE และจัดฉาก REBOOT-hard เคารพ `cancel` | ความคืบหน้าใน `journal.json` |
| `resume` | ดำเนินธุรกรรมที่ค้างต่อจากเฟสปัจจุบัน ทำซ้ำได้ไม่เปลี่ยนผล ไม่เคยสลับ `.so` | `journal.json` ที่อัปเดตแล้ว |
| `boot` | โหมด pre-zygote, `resume` บวกการสลับ `.so` ที่จัดฉากไว้ ปิด `PENDING_REBOOT` เป็น `DONE` | `journal.json` ที่อัปเดตแล้ว |
| `status` | ภาพรวมแบบอ่านอย่างเดียว ไม่เปลี่ยนอะไรเลย | `journal.json` หรือ `{"state":"idle"}` เมื่อไม่มีธุรกรรมที่ทำงานอยู่ |
| `cancel` | ร้องขอการหยุด `run` ที่กำลังทำงานจะหยุดที่จุดปลอดภัยถัดไป | สร้าง `$VDLU_DIR/cancel` |

การอัปเดตแบบไม่มีส่วนติดต่อคือ `check` เพื่อดูว่ามีอะไรค้างอยู่ไหม `run` เพื่อปรับใช้ทุกสิ่งที่สามารถขึ้นไลฟ์ได้ จากนั้น `boot` ในการบูตครั้งถัดไปเพื่อสลับ `.so` ที่จัดฉากไว้ใด ๆ (หรือ `resume` เพื่อลองดึงที่เลื่อนไว้ใหม่) ทุกคำกริยาปลอดภัยที่จะเรียกซ้ำ การล่มหรือเน็ตหลุดกลางวงจรทิ้งเจอร์นัลที่ดำเนินต่อได้ ไม่เคยทิ้งโมดูลที่ปรับใช้ครึ่ง ๆ กลาง ๆ

## JSON สถานะ

`status` (และไฟล์ที่มีชีวิตที่ `$VDLU_DIR/journal.json`) คือสัญญาความคืบหน้าที่ทั้ง WebUI และเอเจนต์อ่าน:

```json
{ "schema":1, "module":"<id>", "target":<version>, "from":<version>,
  "phase":"diff|fetch|apply|commit",
  "state":"PLANNED|FETCHING|FETCHED|APPLYING|APPLIED_LIVE|PENDING_REBOOT|DONE|ERROR|DEFERRED",
  "total":<int>, "done":<int>, "current":"<path>", "bytes":<int>,
  "reboot_pending":bool, "cancelled":bool, "error":"<str|null>",
  "updated":"<ISO8601>",
  "items":[ {"path":"<p>","sha256":"<h>","class":"<c>","st":"pending|fetched|applied|staged|skipped"} ] }
```

- `state` เคลื่อนในลำดับคงที่: `PLANNED -> FETCHING -> FETCHED -> APPLYING -> APPLIED_LIVE -> (PENDING_REBOOT | DONE)`
- `DONE` จะไปถึงก็ต่อเมื่อการแฮชทุกสิ่งซ้ำแล้วตรงกัน ไฟล์ REBOOT-hard ที่จัดฉากไว้ให้ผลเป็น `PENDING_REBOOT` ไม่เคยเป็น `DONE` ปลอม จงรัน `boot` เพื่อทำให้เสร็จ
- `DEFERRED` หมายถึง `net_policy` บล็อกการดาวน์โหลด เป็นสถานะไม่เป็นภัยและดำเนินต่อได้ ไม่ใช่ข้อผิดพลาด แผนคงอยู่และ `check`/`boot` ครั้งถัดไปดำเนินต่อ
- `ERROR` บรรจุเหตุผลไว้ใน `error` ไฟล์ LIVE ที่ปรับใช้ถูกย้อนกลับจาก `rollback/` โมดูลไม่เคยถูกทิ้งไว้ปรับใช้ครึ่งเดียว
- `cancelled:true` กับ `error:null` คือการหยุดที่สะอาด เจอร์นัลยังดำเนินต่อได้

## สัญญารอยต่อ

ทุกส่วนประกอบ (เอนจิน ผู้ผลิต WebUI) สอดคล้องกับ [`INTERFACES.md`](INTERFACES.md) กฎแห่งการลู่เข้า คำกริยา CLI สคีมา `manifest.json` คีย์ `journal.json` และคีย์ config ที่นิยามไว้ที่นั่นเป็น **สิ่งที่เปลี่ยนไม่ได้** จงปฏิบัติต่อไฟล์นั้นเป็นแหล่งความจริงเพียงหนึ่งเดียวและปรับให้ตรงกับมันก่อนเปลี่ยนสิ่งใด สำหรับภายในเอนจิน (ธุรกรรมที่ดำเนินต่อได้ การรับประกันความเข้มงวด การกันออกของ trust-anchor) ดู [`ENGINE.md`](ENGINE.md) สำหรับฝั่งฟีด (การสร้างและเซ็นฟีดที่กำหนดที่อยู่ตามเนื้อหา) ดู [`PRODUCER.md`](PRODUCER.md)

## กฎสำหรับเอเจนต์

- ใช้คำกริยาและ JSON อย่าขูด WebUI เด็ดขาด และอย่าแก้ไฟล์สถานะด้วยมือเด็ดขาด
- ปฏิบัติต่อ `INTERFACES.md` เป็นสิ่งที่เปลี่ยนไม่ได้ การเปลี่ยนหมายถึงปรับสัญญาให้ตรงกันก่อน
- แพตช์จากเอเจนต์ AI ผ่านเกณฑ์การรีวิวเดียวกับแพตช์อื่นใด build เป็น release เสมอ อย่าผ่อนอะไร อย่าทำอะไรหาย

<!-- doc-footer -->

---

> _เอกสารนี้สร้างขึ้นด้วย Claude (Anthropic) และดูแลโดย VD171 ยินดีรับการแก้ไขและการปรับปรุง ดู [CONTRIBUTING.md](CONTRIBUTING.md)_
