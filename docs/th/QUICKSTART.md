> **Languages:** [English](../QUICKSTART.md) · [العربية](../ar/QUICKSTART.md) · [Čeština](../cs/QUICKSTART.md) · [Deutsch](../de/QUICKSTART.md) · [Español](../es/QUICKSTART.md) · [فارسی](../fa/QUICKSTART.md) · [Français](../fr/QUICKSTART.md) · [हिन्दी](../hi/QUICKSTART.md) · [Bahasa Indonesia](../id/QUICKSTART.md) · [Italiano](../it/QUICKSTART.md) · [日本語](../ja/QUICKSTART.md) · [한국어](../ko/QUICKSTART.md) · [Nederlands](../nl/QUICKSTART.md) · [Polski](../pl/QUICKSTART.md) · [Português](../pt/QUICKSTART.md) · [Русский](../ru/QUICKSTART.md) · [Svenska](../sv/QUICKSTART.md) · ไทย · [Türkçe](../tr/QUICKSTART.md) · [Українська](../uk/QUICKSTART.md) · [Tiếng Việt](../vi/QUICKSTART.md) · [中文](../zh/QUICKSTART.md)

---

# quickstart การ adopt VDLU

เช็คลิสต์แบบ copy-paste สำหรับการ vendor **VDLiveUpdate** เข้าไปในโมดูล VDLU ไม่ใช่โมดูลในตัวมันเอง:
มันถูกวางลงใน `<module>/vdlu/` และ ship อยู่ใน zip ของโมดูลคุณ สำหรับเหตุผลเต็มรูปแบบดูที่
[`INTERFACES.md`](INTERFACES.md) (สัญญา seam), [`ENGINE.md`](ENGINE.md), [`PRODUCER.md`](PRODUCER.md)
และ [`WEBUI.md`](WEBUI.md)

แทนที่ `<id>` ด้วย id ของคีย์สำหรับเซ็นของคุณ, `<abi>` ด้วย ABI ของอุปกรณ์ที่คุณ ship
(`arm64-v8a`, `armeabi-v7a`, `x86_64`, `x86`), และ `<module>` ด้วยต้นไม้โมดูลของคุณ

## Layout เป้าหมาย

นี่คือต้นไม้ `vdlu/` ที่โมดูลพกไว้หลังการ adopt อย่างแม่นยำ:

```
<module>/
├── module.prop
├── post-fs-data.sh            # pre-zygote trigger: sh "$MODDIR/vdlu/update.sh" boot
├── webroot/
│   └── index.html             # your WebUI, wiring the Updates panel (step 5)
└── vdlu/
    ├── update.sh              # the engine (vendored byte-for-byte)
    ├── vdlu-verify            # ed25519 verify shim (device-side, no openssl)
    ├── verify/
    │   └── <abi>/ed25519-mini # per-ABI verifier binary
    ├── keyring/
    │   └── <id>.pub           # RAW 32-byte public key (NEVER the PEM)
    ├── config.default         # profile + source + automation defaults
    └── baseline.json          # install seed (unsigned, keyless)
```

สถานะที่เปลี่ยนแปลงได้ของ engine (`config`, `current.json`, journal, lock) อยู่ใน Tier-2,
`/data/adb/<modid>/vdlu/`, นอก module dir, `config.default` seed มันในการรันครั้งแรก

## 1. Vendor engine

คัดลอก engine, verify shim และ verifier ต่อ ABI เข้าไปใน `<module>/vdlu/`:

```sh
mkdir -p <module>/vdlu/verify
cp engine/update.sh      <module>/vdlu/update.sh
cp engine/vdlu-verify    <module>/vdlu/vdlu-verify
cp -r verify/<abi>       <module>/vdlu/verify/<abi>      # ed25519-mini per ABI
```

Ship เฉพาะ ABI ที่คุณรองรับ, `customize.sh` สามารถ prune `verify/` ให้เหลือ ABI ของอุปกรณ์ตอนติดตั้ง

## 2. สร้างคีย์สำหรับเซ็น (ทำครั้งเดียว)

```sh
producer/vdlu-keygen <id> ./keys
```

สิ่งนี้ปล่อย `<id>.pem` (priv, เก็บให้พ้นจากทุกอุปกรณ์และพ้นจากการ push repo ใด ๆ), `<id>.pub`
(PEM, PC-side เท่านั้น) และ `<id>.pub.raw` (RAW 32 ไบต์, สำหรับ keyring ของอุปกรณ์)

## 3. ฝัง raw public key

keyring ของอุปกรณ์ถือคีย์ **RAW 32 ไบต์**, ไม่เคยเป็น PEM (`ed25519-mini` อ่าน PEM ไม่ได้):

```sh
mkdir -p <module>/vdlu/keyring
cp ./keys/<id>.pub.raw <module>/vdlu/keyring/<id>.pub
```

keyring เสถียรข้ามการ release (มันเปลี่ยนเฉพาะตอน rotate คีย์): ในการ re-vendor,
**verify, อย่าเขียนทับ** มัน

## 4. เขียน config

Ship `config.default` ใน `<module>/vdlu/` (seed `config` ใน Tier-2 ในการรันครั้งแรก):

```
auto_on_reboot=1
auto_on_webui_open=1
source=https://<user>.github.io/<repo>/<module>
channel=stable
profile=hardened        # public feed: signature mandatory, downgrade blocked
net_policy=any
pubkey_dir=keyring
# apply_busy_file=/data/adb/<modid>/.busy   # OPT-IN: defer APPLY while this path exists (e.g. a running backup)
```

ใช้ `profile=trusted` เฉพาะกับ source แบบ `file://`/SSH ที่เป็นส่วนตัว (verify best-effort;
sha256 ของทุก blob ยังคงถูกตรวจสอบ) ค่าใด ๆ ที่ไม่ใช่ตัวอักษร `trusted` ล้วนถูกปฏิบัติเป็น
`hardened` (fail-closed)

## 5. เดินสาย trigger

**ตอน reboot** (`auto_on_reboot`): เรียก engine แบบ pre-zygote จาก `post-fs-data.sh` เพื่อให้ไฟล์ที่
stage ไว้ (`.so`, overlay ของ `/system`, `sepolicy.rule`) swap เข้ามาโดยไม่ต้อง reboot เพิ่ม:

```sh
# <module>/post-fs-data.sh
MODDIR=${0%/*}
sh "$MODDIR/vdlu/update.sh" boot
```

**ตอนเปิด WebUI** (`auto_on_webui_open`): เดินสาย Updates panel แบบ drop-in ใน `webroot/index.html`
ของคุณ:

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
  VDLU.onWebUIOpen();                                             // evaluates journal + banner + auto_on_webui_open
  VDLU.mountUpdatesPanel(document.getElementById('b-updates'));  // the "Updates" tab
</script>
```

(`vdlu.js` / `vdlu.css` ถูก vendor มาจาก `webui/`, สามารถเพิ่มการแปลได้ด้วย
`i18n: window.VDLU_I18N_<LANG>`)

## 6. เซ็นฟีดใน release workflow ของคุณ

ในแต่ละ release, pack ต้นไม้โมดูลสุดท้ายและเซ็น manifest เก็บคีย์ private ไว้บนเครื่อง operator,
ไม่เคยใน CI:

```sh
producer/vdlu-pack  <module>  ./out  <module> <versionCode> --version-name v<versionCode> --channel stable \
                    [--prev ./prev/manifest.json]        # delete[] = paths gone since prev
producer/vdlu-sign  ./out/manifest.json  ./keys/<id>.pem  <id>
# publish ./out/{manifest.json,blobs/} to <source>
```

## 7. Ship baseline

สร้าง `baseline.json` เหนือต้นไม้ที่ ship และวางไว้ที่ `<module>/vdlu/baseline.json` มัน seed
`current.json` ในการติดตั้งใหม่เพื่อให้อุปกรณ์เกิดมา "current" (ไม่มีการ re-fetch) มันเป็น **seed ที่
เชื่อถือได้แบบ local**: ไม่มีลายเซ็นและไม่มีคีย์, ดังนั้น CI จึงสร้างมันได้โดยไม่เคยแตะคีย์สำหรับเซ็น:

```sh
producer/vdlu-pack  <module>  ./seed  <module> <versionCode> --version-name v<versionCode>
cp ./seed/manifest.json <module>/vdlu/baseline.json
```

มันไม่ fatal หากขาดหาย (อุปกรณ์แค่เริ่มจาก `0` ในการอัปเดตครั้งแรก)

---

นั่นคือการ adopt ทั้งหมด `sh -n <module>/vdlu/update.sh` ต้องผ่าน, ทดสอบ producer และ engine
แบบ end-to-end ตามที่แสดงใน [`PRODUCER.md`](PRODUCER.md) และ README ของรากก่อนที่คุณจะ ship

<!-- doc-footer -->

---

> _เอกสารนี้สร้างขึ้นด้วย Claude (Anthropic) และดูแลโดย VD171 ยินดีรับการแก้ไขและการปรับปรุง ดู [CONTRIBUTING.md](CONTRIBUTING.md)_
