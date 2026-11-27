> **Languages:** [English](../PRODUCER.md) · [العربية](../ar/PRODUCER.md) · [Čeština](../cs/PRODUCER.md) · [Deutsch](../de/PRODUCER.md) · [Español](../es/PRODUCER.md) · [فارسی](../fa/PRODUCER.md) · [Français](../fr/PRODUCER.md) · [हिन्दी](../hi/PRODUCER.md) · [Bahasa Indonesia](../id/PRODUCER.md) · [Italiano](../it/PRODUCER.md) · [日本語](../ja/PRODUCER.md) · [한국어](../ko/PRODUCER.md) · [Nederlands](../nl/PRODUCER.md) · [Polski](../pl/PRODUCER.md) · [Português](../pt/PRODUCER.md) · [Русский](../ru/PRODUCER.md) · [Svenska](../sv/PRODUCER.md) · ไทย · [Türkçe](../tr/PRODUCER.md) · [Українська](../uk/PRODUCER.md) · [Tiếng Việt](../vi/PRODUCER.md) · [中文](../zh/PRODUCER.md)

---

# เลเยอร์ producer + signing ของ VDLU

สร้างการส่งมอบแบบ content-addressed (manifest + blobs) สำหรับโมดูลและเซ็นมัน
สอดคล้องกับ [`INTERFACES.md`](INTERFACES.md) §3/§6/§7

| เครื่องมือ | ทำงานบน | ภาษา | งาน |
|---|---|---|---|
| `producer/vdlu-pack` | PC / CI | python3 | เดินต้นไม้ของโมดูลสุดท้าย -> `manifest.json` + `blobs/` |
| `producer/vdlu-keygen` | PC | sh + openssl | ed25519 keypair (`<id>.pem` priv, `<id>.pub` PEM, `<id>.pub.raw` RAW 32B สำหรับ keyring แบบเรียว) |
| `producer/vdlu-sign` | PC | sh + openssl | ฉีด `key_id` + `sig` เข้าไปใน manifest ในที่เดิม |
| `engine/vdlu-verify` | **device** | sh + ed25519-mini | ตรวจสอบ `sig` ผ่าน ed25519-mini ที่ฝังไว้; keyring = pubkey RAW 32B (ไม่มี openssl บนอุปกรณ์) |

## Pipeline

```sh
# 1. one-time: a signing key. Keep the .pem off every device and off any repo push.
producer/vdlu-keygen release-2026 ./keys

# 2. each release: pack the final tree (same tree the .zip ships, post-whitelist).
producer/vdlu-pack  ./module_tree  ./out  demo 106 --version-name v106 --channel stable \
                    [--prev ./prev/manifest.json]      # delete[] = paths gone since prev

# 3. sign the manifest in place.
producer/vdlu-sign  ./out/manifest.json  ./keys/release-2026.pem  release-2026

# 4. publish ./out/{manifest.json,blobs/} to <source> (Pages batch for public; rsync for private).
#    The slim device keyring holds ./keys/release-2026.pub.raw as keyring/release-2026.pub (RAW 32B).
```

`vdlu-pack` เป็น content-addressed และ deduplicating: blob ที่ `<sha256>` ของมันมีอยู่แล้วจะไม่ถูก
เขียนใหม่, ดังนั้นการ publish จึงเป็น incremental และเนื้อหาที่ไม่เปลี่ยนแปลง / ที่ revert แล้วไม่เคยถูก push ซ้ำ

### การตัดสินใจ `enc` (vdlu-pack)

`sha256` เป็นของเนื้อหาต้นฉบับ (uncompressed) **เสมอ**, `enc` เพียงแค่บอกว่า blob ถูกเก็บอย่างไร

- `gz` เมื่อ `size >= 4096` **และ** gzip (`-9 -n`, deterministic) ประหยัดได้อย่างน้อย 10% (`comp <= raw*0.90`)
- `raw` ในกรณีอื่น (ข้อความเล็ก ๆ ที่ HTTP gzip ครอบคลุมอยู่แล้ว, หรือข้อมูลที่บีบอัดไม่ได้อยู่แล้ว)
- gzip ขาดหายบน build host -> ทุกอย่างเป็น `raw` (ไม่เคยล้มเหลว)

blob ถูกเก็บครั้งเดียว, ในรูปแบบเดียว: `blobs/<sha256>` (raw) หรือ `blobs/<sha256>.gz` (gz) อุปกรณ์
decompress ด้วย toybox `gunzip` (มีอยู่เสมอ), ดังนั้นจึงไม่มี zstd bundle มาด้วย

### การตัดสินใจ `class` (vdlu-pack) - taxonomy ของ reboot

Derive มาจาก path (INTERFACES §3, doc §4) เป็นค่าดีฟอลต์เท่านั้น, กฎของ path ไม่เคยลดระดับ `reboot`->`live`

| class | จับคู่โดย | การนำไปใช้ |
|---|---|---|
| `reboot` | `system/**`, `zygisk/**/*.so`, `*.rule` | staged `.vdlu-new`, swap ตอน boot |
| `soft` | root `service.sh` / `post-fs-data.sh` / `boot-completed.sh` | เขียน live, รันตอน boot ครั้งถัดไป |
| `live` | อย่างอื่นทั้งหมด (webroot, bin, lib, confs, module.prop, ...) | เขียน live, atomic |

Symlink **ไม่ถูกตาม** (ไม่เคยรั่วเนื้อหาจากนอกต้นไม้, เช่น link ไปยัง
`/etc/shadow`) และถูกข้ามพร้อมคำเตือน, เนื่องจาก schema ของ manifest ไม่มี symlink type
ไฟล์ที่ไม่ใช่ regular (dirs, fifos, devices) ถูกข้าม `built` เคารพ `SOURCE_DATE_EPOCH` สำหรับ
manifest ที่ reproducible

### Baseline (seed สำหรับการติดตั้ง) - ไม่มีลายเซ็น, ไม่มีคีย์

`baseline.json` (ship ที่ `vdlu/baseline.json` ใน zip ของโมดูล) seed `current.json` ในการติดตั้งใหม่
เพื่อให้อุปกรณ์เกิดมา "current" (ไม่มี from:0, ไม่มี re-fetch) เอนจินปฏิบัติกับมันเป็น **local trusted seed**
(มันมาใน zip ที่ flash, ซึ่งคือขอบเขตความเชื่อถือของการติดตั้ง) และ **ไม่ ตรวจสอบลายเซ็นของมัน** -
เฉพาะ manifest ที่ FETCHED จากฟีดเท่านั้นที่ผ่าน `vdlu-verify` ดังนั้น baseline จึง **ไม่ต้องการคีย์**: มันเป็นเพียง
output ของ `vdlu-pack` เหนือต้นไม้ที่ ship (unsigned, `sig`/`key_id` ยังคงว่าง) CI จึงสามารถ
สร้างมันแบบ **keyless**, โดยเก็บคีย์สำหรับเซ็นให้อยู่ นอก CI 100% - เฉพาะ FEED ที่ publish เท่านั้นที่ถูกเซ็น (operator,
locally) `vdlu-pack` กัน `baseline.json` ออกจาก manifest ของตัวเอง (anti self-reference) ไม่ fatal หาก
ขาดหาย: อุปกรณ์แค่เริ่มจาก from:0 ในการอัปเดตครั้งแรก, ไม่เคยพัง

## Canonicalization (จุดบรรจบ)

`vdlu-sign` และ `engine/vdlu-verify` ต้อง derive **ไบต์เดียวกัน** จาก manifest, บน runtime สอง
ตัวที่ต่างกัน (PC openssl vs device toybox) กฎนี้จงใจให้เป็น byte
transform, ไม่ใช่การ re-serialize JSON, เพื่อให้ไม่ต้องใช้ JSON library บนอุปกรณ์:

1. `vdlu-pack` เขียน `manifest.json` แบบ **compact, คีย์เรียงลำดับ, UTF-8**
   (`json.dumps(obj, sort_keys=True, separators=(",",":"), ensure_ascii=False)`), รวมฟิลด์
   `key_id` และ `sig` เสมอ (empty string placeholder จนกว่าจะเซ็น) นี่คือรูปจัดเก็บ canonical
2. **รูป canonical = ข้อความนั้นโดยลบฟิลด์ `"sig"` ออก** เนื่องจากคีย์เรียงลำดับ, `sig`
   ปรากฏเป็น `,"sig":"<value>",` เสมอ คั่นด้วย `"schema"` (ก่อน) และ `"version"` (หลัง),
   ทั้งคู่มีอยู่เสมอ การลบมันออกทิ้ง `...,"schema":N,"version":...` ที่ well-formed ไว้
   JSON escape ทุก `"` ภายในค่า string เป็น `\"`, ดังนั้น structural token `"sig":"` จึง
   ไม่กำกวมแม้เทียบกับชื่อไฟล์ที่มี `"sig":"` อยู่จริง (ทดสอบแล้ว)
3. ข้อความที่ถูกเซ็น/ตรวจสอบคือ **sha256 hex** (64 ASCII chars, ไม่มี newline) ของรูป canonical
   ed25519 เหนือ hex นั้น (`openssl pkeyutl -sign/-verify -rawin`)

การลบใน POSIX sh (ฟังก์ชันเหมือนกันในทั้งสองเครื่องมือ, ไม่มี `sed`/`jq`):

```sh
# $1 = full manifest text (trailing newline already stripped by $(cat ...))
_pre=${_c%%\"sig\":\"*}     # up to  ...,"schema":N,
_rest=${_c#*\"sig\":\"}      # after "sig":"
_tail=${_rest#*\",}          # after <value>",  ->  "version":...
printf '%s%s' "$_pre" "$_tail" | sha256sum | cut -d' ' -f1
```

`key_id` เป็นส่วนหนึ่งของรูป canonical (ลบเฉพาะ `sig`), `vdlu-sign` ตั้ง `key_id` **ก่อน**
hashing ค่า placeholder ที่เป็น empty (`"sig":""`, ตอนเซ็น) หรือเติมแล้ว (ตอน verify) ให้
ไบต์ canonical ที่เหมือนกัน, ดังนั้น sign และ verify จึงตรงกันโดยโครงสร้าง

Python reproduce มันเป็น `re.sub(r'"sig":"[^"]*",', '', text.rstrip("\\n"), count=1)` แล้ว sha256 - ใช้
เฉพาะเพื่อ cross-check, producer ที่เป็นผู้มีอำนาจคือเครื่องมือ sh สองตัว

## ลายเซ็น (ed25519)

- `vdlu-keygen` (PC): `openssl genpkey -algorithm ed25519` (priv `0600`) + `openssl pkey -pubout` (pub **PEM**,
  สำหรับ signing/openssl) + `openssl pkey -pubout -outform DER | tail -c 32` -> **`.pub.raw` (RAW 32B)** (ed25519
  SPKI DER คือ prefix 12 ไบต์ + คีย์ 32 ไบต์, ดังนั้น `tail -c 32` คือ คีย์) มันปล่อยออกมา ทั้งคู่
- `vdlu-sign` (PC): `openssl pkeyutl -sign -rawin` เหนือ canonical sha256 hex, ลายเซ็นเก็บเป็น base64
- `vdlu-verify` (**device, slim**): `ed25519-mini <pubkey32> <msg> <sig64>` - อ่าน keyring เป็น pubkey **RAW 32B**,
  ไม่มี openssl บนอุปกรณ์ `key_id` ถูก path-sanitize (ไม่มี `/`, `.`, `..`, `"`) 🚨 keyring ship
  **`.pub.raw` (32B)**, ไม่เคย `.pub` PEM (113B): PEM เป็น PC-side เท่านั้นและ `ed25519-mini` อ่านมันไม่ได้

Trust model (INTERFACES §6, doc §11/§13): `profile=hardened` (public) ทำให้ verify จำเป็น - ลายเซ็นที่
ล้มเหลวหรือขาดหายจะ abort การอัปเดต `profile=trusted` (private, แหล่ง SSH-staged) ปฏิบัติกับ
verify เป็น best-effort, แต่ sha256 ของทุก blob ถูกตรวจสอบไม่ว่ากรณีใด

## Keyring + การ rotate

Keyring คือไดเรกทอรีของไฟล์ `<key_id>.pub`, แต่ละตัวเป็น ed25519 pubkey **RAW 32B** (จาก `.pub.raw`
ของ `keygen`), ไม่ใช่ PEM - `ed25519-mini` อ่าน raw 32 bytes Ship pubkey raw ตัวปัจจุบัน **และ** ตัวก่อนหน้า
(doc §13) เพื่อให้คีย์ที่ rotate แล้วไม่ brick การติดตั้งเก่า `vdlu-sign` ด้วย `key_id` ใหม่และอุปกรณ์
เลือก `<keyring>/<key_id>.pub` (raw) คือกลไกการ rotate ทั้งหมด - ไม่ต้องเปลี่ยนเอนจิน keyring
**เสถียร** ข้ามการ release (เปลี่ยนเฉพาะตอน rotate คีย์): การ re-vendor ต้อง **verify-not-copy** มัน, และไม่เคย
เขียนทับมันด้วย `.pub` PEM ฝั่ง PC

**keyring หลายคีย์ต้องปักหมุดคีย์ของโมดูล** engine จำกัดว่า `key_id` ใดสามารถเซ็น MODULE-UPDATE ได้ ให้อยู่ใน allowlist `key_id` ของ config (INTERFACES §5/§6) ซึ่งตรวจแบบ fail-closed ก่อนที่จะเลือก pubkey keyring คีย์เดียวปลอดภัยโดยปริยาย (คีย์เดียวนั้นถูกยอมรับ) แต่โมดูลที่ keyring พกคีย์ที่ความเชื่อถือต่ำกว่าด้วย - เช่น คีย์ fingerprint-feed เคียงข้างคีย์ release - จะถูกปฏิเสธจนกว่า `config` ของมันจะประกาศคีย์ของโมดูล เช่น `key_id=vd-2026` (คั่นด้วยจุลภาคสำหรับการ rotate เช่น `key_id=vd-2026,vd-2027`) สิ่งนี้หยุดไม่ให้คีย์ที่ความเชื่อถือต่ำกว่าที่รั่วไหลเซ็นการอัปเดต flashless root ได้

`vdlu-pack` **กัน keyring และไบนารี `verify/` ออกจากฟีด** (รากความเชื่อถืออยู่ใน flash เท่านั้น, ไม่เคยถูกเสิร์ฟผ่านเครือข่าย), เคียงข้างกับ `baseline.json`, โครงนั่งร้านของ installer (`META-INF/`, `customize.sh`), flash gate `.vd/`, `update.json`/`update-mmrl.json` ที่ CI เติม, และไฟล์คู่ `.sha256` ต่อไฟล์ มีเพียงเนื้อหาของโมดูลเองที่อัปเดตผ่านฟีดได้, ดังนั้น manifest จึงไม่มีทางเขียนทับ trust anchor บนอุปกรณ์ได้

<!-- doc-footer -->

---

> _เอกสารนี้สร้างขึ้นด้วย Claude (Anthropic) และดูแลโดย VD171 ยินดีรับการแก้ไขและการปรับปรุง ดู [CONTRIBUTING.md](CONTRIBUTING.md)_
