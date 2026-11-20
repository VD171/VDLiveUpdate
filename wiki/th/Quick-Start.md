# เริ่มต้นอย่างรวดเร็ว

นี่คือเช็กลิสต์การนำเข้าใช้: วิธีฝัง **VDLiveUpdate (VDLU)** เข้าไปในโมดูล
KernelSU / APatch / Magisk VDLU ไม่ใช่โมดูลในตัวมันเอง มันถูกวางไว้ใน
`<module>/vdlu/` และส่งมาภายใน zip ของโมดูลคุณ เพื่อให้โมดูลที่ติดตั้งแล้วสามารถ
อัปเดตตัวเองโดยไม่ต้องแฟลชจากฟีดที่ลงลายเซ็นซึ่งคุณเผยแพร่

ตลอดทั้งหน้า ให้แทนที่ `<id>` ด้วย id คีย์ลงลายเซ็นของคุณ `<abi>` ด้วย
ABI ของอุปกรณ์ที่คุณส่ง (`arm64-v8a`, `armeabi-v7a`, `x86_64`, `x86`) และ `<module>`
ด้วยต้นไม้ไฟล์โมดูลของคุณ

สำหรับเหตุผลเบื้องหลังแต่ละส่วน ดู [[Engine]], [[Producer]], [[WebUI]] และ
[[Security and Trust Model]]

## โครงสร้าง `vdlu/` ในโมดูล

นี่คือต้นไม้ไฟล์ที่แน่ชัดที่โมดูลคุณพกหลังการนำเข้าใช้:

```
<module>/
|-- module.prop
|-- post-fs-data.sh            # pre-zygote trigger: sh "$MODDIR/vdlu/update.sh" boot
|-- webroot/
|   `-- index.html             # your WebUI, wiring the Updates panel (step 5)
`-- vdlu/
    |-- update.sh              # the engine (vendored byte-for-byte)
    |-- vdlu-verify            # ed25519 verify shim (device-side, no openssl)
    |-- verify/
    |   `-- <abi>/ed25519-mini # per-ABI verifier binary
    |-- keyring/
    |   `-- <id>.pub           # RAW 32-byte public key (NEVER the PEM)
    |-- config.default         # profile + source + automation defaults
    `-- baseline.json          # install seed (unsigned, keyless)
```

สถานะที่เปลี่ยนแปลงได้ของเอนจิน (`config`, `current.json`, journal, ล็อก, แคช blob)
อยู่ใน Tier-2 ที่ `/data/adb/<modid>/vdlu/` นอกไดเรกทอรีโมดูล
`config.default` seed `config` ใน Tier-2 นั้นในการรันครั้งแรก ดู [[Engine]] สำหรับ
โครงสร้างสถานะฉบับเต็ม

## 1. ฝังเอนจิน

คัดลอกเอนจิน verify shim และไบนารีตัวตรวจสอบต่อ ABI เข้าไปใน
`<module>/vdlu/`:

```sh
mkdir -p <module>/vdlu/verify
cp engine/update.sh   <module>/vdlu/update.sh
cp engine/vdlu-verify <module>/vdlu/vdlu-verify
cp -r verify/<abi>    <module>/vdlu/verify/<abi>    # ed25519-mini per ABI
```

ส่งเฉพาะ ABI ที่คุณรองรับ `customize.sh` ของคุณสามารถตัด `verify/` ลงเหลือ
ABI ของอุปกรณ์ในเวลาติดตั้ง

## 2. สร้างคีย์ลงลายเซ็น (ครั้งเดียว)

```sh
producer/vdlu-keygen <id> ./keys
```

สิ่งนี้ปล่อยสามไฟล์:

- `<id>.pem` - คีย์ส่วนตัว เก็บมันให้พ้นจากทุกอุปกรณ์และพ้นจากการ push repo ใด ๆ
  หรือ CI secret
- `<id>.pub` - คีย์สาธารณะ PEM ฝั่ง PC เท่านั้น (ใช้โดย `vdlu-sign`)
- `<id>.pub.raw` - คีย์สาธารณะดิบ 32 ไบต์ สำหรับ keyring ของอุปกรณ์

ดู [[Security and Trust Model]] สำหรับเหตุผลที่การแบ่งนี้สำคัญ

## 3. ฝังคีย์สาธารณะดิบ

keyring ของอุปกรณ์เก็บคีย์ **ดิบ 32 ไบต์** ไม่เคยเป็น PEM `ed25519-mini`
อ่าน PEM ไม่ได้ ดังนั้นการคัดลอก PEM มาที่นี่ทำลายการตรวจสอบบนอุปกรณ์:

```sh
mkdir -p <module>/vdlu/keyring
cp ./keys/<id>.pub.raw <module>/vdlu/keyring/<id>.pub
```

keyring เสถียรข้ามรีลีส: มันเปลี่ยนเฉพาะเมื่อมีการหมุนคีย์ เมื่อฝังซ้ำ
**ให้ตรวจสอบมัน อย่าเขียนทับมัน**

## 4. เขียนคอนฟิก

ส่ง `config.default` ใน `<module>/vdlu/` มัน seed `config` ใน Tier-2 ในการรันครั้ง
แรก:

```
auto_on_reboot=1
auto_on_webui_open=1
source=https://<user>.github.io/<repo>/<module>
channel=stable
profile=hardened        # public feed: signature mandatory, downgrade blocked
net_policy=any
pubkey_dir=keyring
```

ใช้ `profile=trusted` เฉพาะสำหรับต้นทาง `file://` ส่วนตัวหรือ SSH (การตรวจสอบเป็น
แบบพยายามอย่างดีที่สุดที่นั่น แต่ sha256 ของทุก blob ก็ยังถูกตรวจสอบ) ค่าใด ๆ ที่ไม่ใช่
`trusted` ตามตัวอักษรจะถูกปฏิบัติเป็น `hardened` แบบ fail-closed ดู
[[Security and Trust Model]] สำหรับความหมายของโปรไฟล์ฉบับเต็ม

## 5. ต่อเชื่อมทริกเกอร์

**เมื่อรีบูต** (`auto_on_reboot`): เรียกเอนจินก่อน zygote จาก
`post-fs-data.sh` เพื่อให้ไฟล์คลาสรีบูตที่จัดเตรียมไว้ (`.so`, overlay ของ `/system`,
`sepolicy.rule`) สลับเข้าโดยไม่มีการรีบูตเพิ่ม:

```sh
# <module>/post-fs-data.sh
MODDIR=${0%/*}
sh "$MODDIR/vdlu/update.sh" boot
```

**เมื่อเปิด WebUI** (`auto_on_webui_open`): ต่อเชื่อมแผง Updates แบบ drop-in ใน
`webroot/index.html` ของคุณ:

```html
<link rel="stylesheet" href="vdlu.css">
<script src="vdlu.js"></script>
<script>
  VDLU.init({
    moduleDir: '/data/adb/modules/' + MODID,
    vdluDir:   '/data/adb/' + MODID + '/vdlu',
    modid:     MODID,
    module:    'YourModule'
  });
  VDLU.onWebUIOpen();                                            // journal + banner + auto_on_webui_open
  VDLU.mountUpdatesPanel(document.getElementById('b-updates'));  // the "Updates" tab
</script>
```

`vdlu.js` และ `vdlu.css` ถูกฝังจาก `webui/` คำแปลสามารถเพิ่มได้
ด้วย `i18n: window.VDLU_I18N_<LANG>` ดู [[WebUI]] สำหรับสัญญาของแผง

## 6. ลงลายเซ็นฟีดในเวิร์กโฟลว์รีลีสของคุณ

ในแต่ละรีลีส pack ต้นไม้ไฟล์โมดูลสุดท้ายและลงลายเซ็น manifest เก็บคีย์ส่วนตัว
ไว้บนเครื่องผู้ปฏิบัติงาน ไม่เคยใน CI:

```sh
producer/vdlu-pack  <module>  ./out  <module> <versionCode> \
                    --version-name v<versionCode> --channel stable \
                    [--prev ./prev/manifest.json]      # delete[] = paths gone since prev
producer/vdlu-sign  ./out/manifest.json  ./keys/<id>.pem  <id>
# publish ./out/{manifest.json,blobs/} to <source>
```

`vdlu-pack` กำหนดที่อยู่ด้วยเนื้อหาและตัดข้อมูลซ้ำ ดังนั้นการเผยแพร่จึงเป็นแบบเพิ่มทีละส่วน:
blob ที่ไม่เปลี่ยนจะไม่เคยถูกส่งซ้ำ ดู [[Producer]] และ [[Feed Format]]

## 7. ส่ง baseline

สร้าง `baseline.json` ครอบคลุมต้นไม้ไฟล์ที่ส่งมาและวางมันที่
`<module>/vdlu/baseline.json` มัน seed `current.json` เมื่อติดตั้งใหม่ เพื่อให้
อุปกรณ์เกิดมาเป็น "ปัจจุบัน" และไม่ fetch เวอร์ชันที่ส่งมาของตัวเองซ้ำ มันเป็น
**seed ท้องถิ่นที่เชื่อถือได้**: ไม่ลงลายเซ็นและไร้คีย์ เพื่อให้ CI สร้างมันได้โดยไม่เคย
แตะต้องคีย์ลงลายเซ็น:

```sh
producer/vdlu-pack  <module>  ./seed  <module> <versionCode> --version-name v<versionCode>
cp ./seed/manifest.json <module>/vdlu/baseline.json
```

มันไม่ร้ายแรงหากขาดหาย: อุปกรณ์เพียงเริ่มจากเวอร์ชัน `0` ในการ
อัปเดตครั้งแรก

---

นั่นคือการนำเข้าใช้ทั้งหมด ก่อนที่คุณจะส่ง `sh -n <module>/vdlu/update.sh`
ต้องผ่าน และคุณควรทดสอบ producer และเอนจินตั้งแต่ต้นจนจบตามที่แสดงใน
[[Contributing]] และ [[Producer]]
