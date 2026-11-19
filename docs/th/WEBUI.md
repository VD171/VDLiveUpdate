> **Languages:** [English](../WEBUI.md) · [العربية](../ar/WEBUI.md) · [Čeština](../cs/WEBUI.md) · [Deutsch](../de/WEBUI.md) · [Español](../es/WEBUI.md) · [فارسی](../fa/WEBUI.md) · [Français](../fr/WEBUI.md) · [हिन्दी](../hi/WEBUI.md) · [Bahasa Indonesia](../id/WEBUI.md) · [Italiano](../it/WEBUI.md) · [日本語](../ja/WEBUI.md) · [한국어](../ko/WEBUI.md) · [Nederlands](../nl/WEBUI.md) · [Polski](../pl/WEBUI.md) · [Português](../pt/WEBUI.md) · [Русский](../ru/WEBUI.md) · [Svenska](../sv/WEBUI.md) · ไทย · [Türkçe](../tr/WEBUI.md) · [Українська](../uk/WEBUI.md) · [Tiếng Việt](../vi/WEBUI.md) · [中文](../zh/WEBUI.md)

---

# VDLU - WebUI widget (อัปเดตแบบ flashless)

อินเทอร์เฟซ VDLU (VD Live Update) สำหรับ WebUI ของ root manager แบบ KernelSU/APatch Vanilla JS, ไม่มี framework, ไม่มี
build, ไม่มี CDN Drop-in: `index.html` ของ host โหลดไฟล์ 2 ไฟล์และเรียก API

การบรรจบ: `INTERFACES.md` §9 (WEBUI<->ENGINE), §4 (journal.json), §5 (config)

## ไฟล์

| ไฟล์ | คืออะไร |
|---|---|
| `vdlu.js` | คอมโพเนนต์ - expose `window.VDLU` |
| `vdlu.css` | progress toast, reboot banner, แท็บ "Updates" (ธีมมืด, สืบทอดตัวแปรของ host) |
| `demo.html` | หน้า standalone พร้อม `ksu.exec` ที่ mock ไว้ - เปิดในเบราว์เซอร์, ไม่มีอุปกรณ์ |

## การ Integrate เข้ากับ `index.html` ของ host

```html
<link rel="stylesheet" href="vdlu.css">
...
<script src="vdlu.js"></script>
<script>
  VDLU.init({
    moduleDir: '/data/adb/modules/' + MODID,   // $MODULE_DIR
    vdluDir:   '/data/adb/' + MODID + '/vdlu',  // $VDLU_DIR  (Tier-2, outside the module dir)
    modid:     MODID,
    module:    'Demo',                     // name shown in the toast (default: modid)
    exec:   ex,          // (optional) the host's ksu.exec wrapper; see below
    toast:  toast,       // (optional) the host's transient toast
    confirm: askConfirm  // (optional) the host's confirmation modal
  });

  VDLU.onWebUIOpen();                          // on load: evaluates journal + banner + auto_on_webui_open
  VDLU.mountUpdatesPanel(document.getElementById('b-updates'));  // when the "Updates" tab is opened
</script>
```

### สิ่งที่ host ต้องกำหนด

- **`moduleDir`** = `$MODULE_DIR` (`/data/adb/modules/<modid>`), ที่ซึ่งเอนจินถูก vendor
  (`vdlu/update.sh`)
- **`vdluDir`** = `$VDLU_DIR` (`/data/adb/<modid>/vdlu`), สถานะ Tier-2 (`journal.json`, `config`,
  `cancel`)
- **`modid`** = id ของโมดูล

Widget ประกอบคำสั่งเอนจินโดยนำ env ของสัญญา (§1) ติดมาด้วยแล้ว:
`VDLU_DIR=... MODULE_DIR=... MODID=... sh $MODULE_DIR/vdlu/update.sh <cmd>` `run`/`resume` ไปที่
**background** (`(... &)`), และความคืบหน้าถูกอ่านด้วย poll เบา ๆ (~1s) ของ `cat $VDLU_DIR/journal.json`

### `exec`/`toast`/`confirm` (ไม่บังคับ)

หากละไว้, widget ใช้ของตัวเอง:
- **`exec(cmd)`** ต้องคืน `Promise` ที่ **resolve** ด้วย stdout (rc 0) และ **reject** ด้วย stderr
  (rc≠0) - ลายเซ็นของ `ex()` ใน `webroot/index.html` ของ Demo เป๊ะ ๆ Fallback ภายในเรียก
  `ksu.exec(cmd, '{}', cb)` ด้วยสัญญาเดียวกัน
- **`toast(msg)`** = การแจ้งเตือนชั่วคราวสั้น ๆ (fallback ฉีด mini-toast ของตัวเอง)
- **`confirm(title,msg,ok,danger,fn)`** = modal (วันนี้ใช้โดย host เท่านั้น; widget ไม่ต้องการการ
  ยืนยันในขั้นตอนใด ๆ)

การส่งของ host เองเข้ามาทำให้ widget พูดผ่าน queue แบบ serialize เดียวกันและ visual เดียวกันกับส่วนที่เหลือของ
WebUI

## API สาธารณะ (`window.VDLU`)

| ฟังก์ชัน | ทำอะไร |
|---|---|
| `init(opts)` | configure (ดูด้านบน) คืน `window.VDLU` |
| `onWebUIOpen()` | เรียกมันตอน load: แสดง banner ถ้า `reboot_pending`; เสนอ **Resume** ถ้ามีทรานแซกชันที่ยังไม่สิ้นสุด; ด้วย `auto_on_webui_open=1` มันรัน **auto-update แบบเงียบ** (`check()` เงียบ ๆ ก่อน; จะยิง `run`+persistent toast ก็ต่อเมื่อ `update && fetch>0` - ทันสมัยแล้ว/ล้ำหน้า = ผลลัพธ์ inline ในแผง, ไม่มี toast) |
| `mountUpdatesPanel(el)` | เรนเดอร์แท็บ "Updates" ภายใน `el` (string id หรือ element): **Check for update**, **Update now**, toggle `auto_on_webui_open`/`auto_on_reboot`, ฟิลด์ boot-retry, select **Network** (`net_policy`: Wi-Fi+mobile / Wi-Fi-only / mobile-only) และฟิลด์ `source`/`channel`/`profile` |
| `check()` | รัน `update.sh check`; `Promise<{update,from,to,fetch,reboot}>` |
| `startUpdate()` | ยิง `run` ใน background + progress toast พร้อม **Cancel** |
| `cancel()` | สร้าง `$VDLU_DIR/cancel` (เอนจินหยุดที่จุดปลอดภัย) |
| `resume()` | `update.sh resume` + toast (ทำเฟสปัจจุบันต่อ) |
| `refreshBanner()` | ประเมิน banner pending-reboot ถาวรใหม่ |

Toast (corner overlay, non-blocking) และ banner (ด้านบน, ถาวร) ถูกฉีดโดย widget เข้าไปใน
`document.body` - host ไม่ต้องการ HTML สำหรับมัน แท็บ "Updates" เป็นจุดเดียวที่ host จัดสรร (
`<div>` ว่าง)

### การไหลของสถานะที่ toast สะท้อน (journal.json, §4)

`PLANNED → FETCHING → FETCHED → APPLYING → APPLIED_LIVE → (PENDING_REBOOT | DONE)`; `ERROR` ได้ทุกเมื่อ
Toast แสดง **บาร์ + `phase done/total · current · bytes`** Terminal:
- **`DONE`** → green toast "v&lt;target&gt; applied"
- **`PENDING_REBOOT`** (หรือ `reboot_pending=true`) → green toast + **banner ถาวร** "⚠️ Reboot to
  activate the new `.so` (vX)"
- **`ERROR`** → red toast พร้อมเหตุผล (`journal.error`/stderr) ไม่เคยแกล้งทำว่าสำเร็จ
- **Cancelled** → "cancelled - N/M, resumable" + ปุ่ม **Resume**

## การรัน demo

เปิด `demo.html` ในเบราว์เซอร์ (`xdg-open webui/demo.html`) `ksu.exec` ที่ mock ไว้จำลอง `update.sh` และ
`journal.json` ที่วิวัฒน์ไป; ปุ่มสลับระหว่าง scenario **LIVE→DONE**, **reboot_pending**, **error mid-way**
และ **cancellable** มันคือ `vdlu.js`/`vdlu.css` เดียวกันกับบนอุปกรณ์

## i18n (ภาษา)

String ของ widget ดีฟอลต์เป็น **English** (เป็นกลางสำหรับโมดูล multi-language สาธารณะ) host override
คีย์ใดก็ได้โดยส่ง map ใน `init`:

```html
<script src="i18n/pt-BR.js"></script>   <!-- defines window.VDLU_I18N_PT_BR -->
<script>VDLU.init({ exec: ex, moduleDir: MOD, vdluDir: VDL, modid: 'x', i18n: window.VDLU_I18N_PT_BR });</script>
```

- การ merge แบบ **partial** ก็ใช้ได้: คีย์ที่ขาดหายจะ fallback เป็น English default
- คีย์ Phase/state คือ `ph_<phase>` / `st_<STATE>`; ที่เหลือเป็น flat (`cancel`, `updateNow`, ...)
- key map ครบถ้วน = object `DEFAULT_I18N` ใน `vdlu.js` (expose เป็น `VDLU.i18n` ด้วย)
- การแปลที่พร้อมใช้งานถูกให้ไว้เป็นตัวอย่าง: `i18n/pt-BR.js` ภาษาใหม่ = ไฟล์
  `i18n/<lang>.js` ในรูปแบบเดียวกัน, หรือ host สร้าง map จากระบบ i18n ของตัวเอง

## แหล่งเดียว (parity ข้ามโมดูล)

`vdlu.js`/`vdlu.css` เหล่านี้คือ **สำเนา canonical** ทุกโมดูลที่ฝัง widget
**re-vendor** สำเนานี้แบบ byte-for-byte เข้าไปใน `webroot/` ของมัน - มัน **ไม่เคย** แก้ไข
สำเนาของตัวเองในที่เดิม ฟีเจอร์ widget ใหม่เกิดขึ้นที่นี่และไหลลงไปโดยการ re-vendor; ทางกลับทำให้เกิด
drift เงียบ ๆ (มันเกิดขึ้นจริงมาแล้ว: สำเนาที่ vendor ไว้ตกยุคและขาด `net_policy`, toast
`DEFERRED` และฟิลด์ `boot_retry`)

Guardian: [`../tools/webui-parity.sh`](../../tools/webui-parity.sh) หาทุกสำเนาในต้นไม้ของ source และ flag
ตัวที่แตกต่างจากตัว canonical (เฉพาะ `vdlu.js`/`vdlu.css`; keyring เป็น "verify, not copy")

```sh
tools/webui-parity.sh         # report; exits 1 if there is drift
tools/webui-parity.sh --fix   # re-vendors the divergent ones from the canonical
```

> 🪤 keyring (`keyring/<id>.pub` RAW 32B) และเอนจิน (`vdlu/update.sh`) มีจังหวะการ re-vendor ของ
> ตัวเอง; guardian นี้ครอบคลุม **เฉพาะ WebUI widget**

<!-- doc-footer -->

---

> _เอกสารนี้สร้างขึ้นด้วย Claude (Anthropic) และดูแลโดย VD171 ยินดีรับการแก้ไขและการปรับปรุง ดู [CONTRIBUTING.md](CONTRIBUTING.md)_
