> **Languages:** [English](../ENGINE.md) · [العربية](../ar/ENGINE.md) · [Čeština](../cs/ENGINE.md) · [Deutsch](../de/ENGINE.md) · [Español](../es/ENGINE.md) · [فارسی](../fa/ENGINE.md) · [Français](../fr/ENGINE.md) · [हिन्दी](../hi/ENGINE.md) · [Bahasa Indonesia](../id/ENGINE.md) · [Italiano](../it/ENGINE.md) · [日本語](../ja/ENGINE.md) · [한국어](../ko/ENGINE.md) · [Nederlands](../nl/ENGINE.md) · [Polski](../pl/ENGINE.md) · [Português](../pt/ENGINE.md) · [Русский](../ru/ENGINE.md) · [Svenska](../sv/ENGINE.md) · ไทย · [Türkçe](../tr/ENGINE.md) · [Українська](../uk/ENGINE.md) · [Tiếng Việt](../vi/ENGINE.md) · [中文](../zh/ENGINE.md)

---

# เอนจิน VDLU (`update.sh`)

ไคลเอนต์อัปเดตแบบ incremental, flashless สำหรับโมดูล KSU/Magisk ทำงานตามรอบ
`DIFF -> FETCH -> APPLY -> COMMIT` ในรูปของทรานแซกชันที่กลับมาทำต่อได้ สอดคล้องกับ `INTERFACES.md` (กฎ
แห่งการบรรจบ)

Pure POSIX sh (mksh/busybox/toybox) **SLIM:** มันพึ่งพาเฉพาะ toybox (`sha256sum`/`gzip`/`base64`/`date`) +
`ed25519-mini` ที่ฝังไว้ (ed25519 verify, **ไม่มี openssl บนอุปกรณ์**) + `curl` แบบ static ที่ **ดึงมา** ในการอัปเดต
https ครั้งแรก (WebUI ทำ `fetch()`, คงมันไว้ใน Tier-2, และ `install-tool` ตรวจสอบ
ลายเซ็น+hash ของมันก่อนใช้งาน) `file://` ไม่ต้องใช้ curl ไม่พึ่งพา `jq` เลย

## การเรียกใช้

```sh
VDLU_DIR=/data/adb/<mod>/vdlu MODULE_DIR=/data/adb/modules/<mod> MODID=<mod> \
  sh $MODULE_DIR/vdlu/update.sh <cmd>
```

`rc 0` = ok, `rc != 0` = error (เหตุผลบน stderr) `vdlu-verify` ถูกส่งมอบโดยคอมโพเนนต์อื่น
(ลายเซ็นใน `INTERFACES.md §6`), เอนจินเพียงแค่เรียกมัน

| cmd | ทำอะไร |
|---|---|
| `check` | DIFF แบบ read-only; พิมพ์ `{"update":bool,"from":N,"to":M,"fetch":K,"reboot":bool}`; ไม่เปลี่ยนแปลงอะไร |
| `run` | รอบ LIVE เต็ม + stage REBOOT-hard; เคารพ `cancel`; ความคืบหน้าใน `journal.json` |
| `resume` | ทำทรานแซกชันที่ค้างอยู่ (`target.json`) ต่อจากเฟสปัจจุบัน; idempotent; **ไม่** swap `.so` |
| `boot` | โหมด pre-zygote: resume **+** swap `staged/*.vdlu-new` -> ปิด `PENDING_REBOOT`->`DONE` หากไม่มีทรานแซกชันค้างอยู่ มันจะรันรอบใหม่และ apply ทุกอย่าง (รวมถึง `.so`) ในการ boot ครั้งเดียว |
| `status` | พิมพ์ `journal.json` (หรือ `{"state":"idle"}`) |
| `cancel` | สร้าง `$VDLU_DIR/cancel`; `run` ที่กำลังทำงานจะหยุดที่จุดปลอดภัยถัดไป |

## เครื่องจักรสถานะ (journal.json)

```
PLANNED -> FETCHING -> FETCHED -> APPLYING -> APPLIED_LIVE -> (PENDING_REBOOT | DONE)
```

`DONE` เกิดขึ้นเมื่อ re-hash ของ ทุกอย่าง ตรงกันเท่านั้น หาก REBOOT-hard ใดถูก stage => `PENDING_REBOOT` (ไม่เคย
เป็น `DONE` ปลอม) `ERROR` เมื่อล้มเหลวใด ๆ, โดยไม่ทำให้โมดูลเสียหาย (ไฟล์ LIVE ที่ apply ไปแล้วจะถูกย้อนกลับ
จาก `rollback/<v>/`, ไม่มี "ที่ apply ไปครึ่งเดียวแล้วโกหกว่าเสร็จ") ทางออกที่ไม่เป็นอันตรายของเฟส `fetch`: **`DEFERRED`** -
การดาวน์โหลดถูกเลื่อนโดย `net_policy` (เครือข่ายไม่อนุญาต), plan/target ยังคงอยู่และกลับมาทำต่อในการ
check/boot ครั้งถัดไป (WebUI แสดง toast info สีน้ำเงิน "waiting for X network", ไม่ใช่ error)

## การรับประกันความเข้มงวด

- **FETCH:** คุมโดย `net_policy` (any/wifi/mobile, http/https เท่านั้น, `file://` ไม่เคย) - เครือข่ายที่ไม่อนุญาต =>
  `DEFERRED` (กลับมาทำต่อได้), โดยไม่ใช้ดาต้า ดาวน์โหลดเฉพาะสิ่งที่ขาดเข้าไปใน `<sha>.part` (curl ด้วย
  `--connect-timeout` + `--speed-time`, ไม่เคยค้าง), decompress `gz` (toybox `gunzip`), ตรวจสอบ `sha256sum` ==
  manifest, `mv` แบบ atomic ไปยัง `blobs/<sha>` blob ที่ cache+ok จะถูกข้าม มันสามารถ seed blob จากไฟล์
  local ที่ไม่เปลี่ยนแปลงได้ (dedup/offline) **ล้มเหลว 3 ครั้งบน blob เดียวกัน = เฟสยกเลิกโดยไม่ apply อะไร** มัน
  จะกลายเป็น `FETCHED` ก็ต่อเมื่อ blob ของ plan ทั้งหมด present+verified เท่านั้น ที่ขั้นตั้งค่า toolchain
  มัน log TLS trust ที่ resolve แล้ว (path ของ CA + ความสามารถในการอ่าน, ขนาด bundle และจำนวน cert) เพื่อให้
  curl `rc 77` ตอน boot อธิบายตัวเองได้ใน `boot.log` - มันแยก store ที่ว่างเปล่าออกจาก store ที่อ่านไม่ได้
  (กรณี SELinux-context ตอน boot)
- **APPLY** (เฉพาะจาก `FETCHED`): `live`/`soft` -> backup ไปยัง `rollback/<v>/` -> `.vdlu-tmp` -> `chmod` -> verify ->
  `rename` แบบ atomic `reboot` -> สร้างชิ้นเข้าไปใน `staged/<path>.vdlu-new` (ไม่ แตะ inode ของ live)
  `delete[]` -> backup -> ลบ idempotent (ไฟล์ที่อยู่ที่ hash เป้าหมายแล้วจะถูกข้าม)
- **COMMIT:** re-hash ของทุก `live`/`soft`, แล้วจึงเขียน `current.json` หากมีไฟล์ที่ stage =>
  `PENDING_REBOOT` `boot` ทำ `mv -f staged/....vdlu-new $MODULE_DIR/<path>` (pre-zygote) + re-verify +
  `DONE`
- **cancel:** เช็คระหว่างไฟล์ (จุดปลอดภัย), ลบ `.vdlu-tmp`/`.part` ที่ค้างอยู่, ลบ `cancel`,
  ทิ้ง journal ให้กลับมาทำต่อได้ (`cancelled:true`, `error:null`)
- **mkdir-lock `$VDLU_DIR/lock.d`** ทำให้ทำงานแบบ serial (flock ใช้ไม่ได้บน toybox, stale-recovery ด้วย PID) boot-retry
  แบบ PATIENT ไม่ยึด lock ขณะรอ (`acquire_lock_try`+release ระหว่างรอบ) และไม่ยึด
  wakelock - ประหยัดแบตเตอรี่ crash/network/reboot กลางทาง -> `resume`/`boot` ทำต่อ
- **profile=hardened** => `vdlu-verify` จำเป็นบน manifest ก่อนใช้งาน, ล้มเหลว = abort, downgrade ถูกบล็อก
  (version แบบ monotonic) **trusted** => verify เป็น best-effort, แต่ hash ของทุก blob ถูกตรวจสอบ เสมอ
- **allowlist ของคีย์ module-update (ทั้งสอง profiles):** `verify_manifest` ปฏิเสธแบบ fail-closed ต่อ manifest ใด ๆ ที่ `key_id` ไม่อยู่ใน allowlist `key_id` ที่กำหนดไว้ (ดู INTERFACES §5/§6) ก่อนที่จะเลือก pubkey ดังนั้นคีย์ที่ความเชื่อถือต่ำกว่าซึ่งเพียงแค่อยู่ใน keyring (เช่น คีย์ fingerprint-feed) จึงไม่มีทางเซ็นการอัปเดต flashless root ได้ ปลอดภัยโดยปริยายเมื่อไม่ได้ตั้งค่า: keyring คีย์เดียว = เฉพาะคีย์เดียวนั้น, keyring หลายคีย์ = ปฏิเสธจนกว่าจะปักหมุด `key_id`
- **การกัน trust anchor (VDLU#2):** engine เพิกเฉยทุก path `vdlu/` ใน plan ที่ fetch มา (`update.sh`,
  `vdlu-verify`, `verify/*`, `keyring/*`, config) - ไม่เคย fetch, apply, หรือลบ - แม้ว่าฟีดที่เซ็นแล้วจะพกมันมา
  ฟีดไม่สามารถ swap verifier หรือคีย์สำหรับเซ็นบนอุปกรณ์ได้เลย, trust anchor เปลี่ยนได้เฉพาะด้วยการ re-flash ที่
  เซ็นแล้วเต็มรูปแบบ ดังนั้นคีย์สำหรับเซ็นที่รั่วไหลเพียงคีย์เดียวจึงคง root ผ่านเครือข่ายไม่ได้
- **Busy-defer (opt-in `apply_busy_file`):** เมื่อตั้ง `apply_busy_file` (path สัมบูรณ์ที่โมดูลโฮสต์แตะ
  ระหว่างการทำงานของตัวเอง เช่น backup ที่กำลังทำงาน), APPLY จะถูกเลื่อนออกไปตราบที่ path นั้นยังอยู่ - การ
  อัปเดตจะไม่เคย swap ไฟล์โมดูลกลางการทำงาน blob ถูก fetch มาแล้ว ดังนั้น trigger ครั้งถัดไปจึง apply โดยไม่
  ต้องดาวน์โหลดซ้ำ
- **เพดานขนาด:** 128 MiB ต่อไฟล์ (`MAX_FILE_BYTES`) และ 2 MiB ต่อ manifest (`MAX_MANIFEST_BYTES`),
  บังคับใช้ก่อนการอ่านในทั้ง `update.sh` และ `vdlu-verify` (anti decompression-bomb / anti-OOM)
- ลดระดับอย่างนุ่มนวล: ไบนารีขาด / เครือข่ายล่ม / ดิสก์เต็ม -> error ที่ชัดเจนบน stderr + `state:ERROR` ใน
  journal, โดยไม่ทำให้โมดูลเสียหาย

## การ parse JSON โดยไม่มี jq

Flattener สไตล์ gron ใน `awk` (pure POSIX: `substr`/`index`/`gsub`/`split`/`printf` + locals ที่ส่งเป็น
พารามิเตอร์) tokenize manifest ทีละตัวอักษรและปล่อยหนึ่งบรรทัด `path<TAB>value` ต่อ scalar leaf หนึ่งตัว
(`files/0/sha256<TAB>ab..`, `version<TAB>6`, `delete/0<TAB>etc/x`) ทนทานต่อ JSON แบบ compact หรือ pretty-print
`sh` บริโภคมันด้วย `grep`/`cut`, plan ต่อไฟล์ถูกประกอบใหม่ใน `awk` ตัวที่ 2 เป็น TSV
(`class st mode enc sha size path`), ซึ่งกลายเป็น `$VDLU_DIR/plan.tsv`

## ไฟล์สถานะ (ใน `$VDLU_DIR`, Tier-2)

| ไฟล์ | บทบาท |
|---|---|
| `config` | key=value (`source`/`profile`/`channel`/`net_policy`/`key_id`/`apply_busy_file`/`boot_retry_*`/...; ดู INTERFACES §5) |
| `current.json` | manifest ของเวอร์ชัน ACTIVE (diff base); absent = ไม่เคยอัปเดต |
| `target.json` | manifest ที่ปักไว้ของทรานแซกชันที่กำลังดำเนินอยู่ (presence = active transaction); กลายเป็น `current.json` เมื่อ `DONE` |
| `plan.tsv` / `plan.del` | plan + ความคืบหน้าต่อไฟล์ (st) / path ที่จะลบ |
| `journal.json` | ความคืบหน้าสำหรับ WebUI (สร้างใหม่ในทุกการเปลี่ยนสถานะ) |
| `blobs/<sha256>` | cache ของเนื้อหาต้นฉบับที่ verified แล้ว |
| `rollback/<version>/<path>` | backup ของไฟล์ที่ถูกเขียนทับ (undo; เก็บ 3 ตัวสุดท้าย) |
| `staged/<path>.vdlu-new` | REBOOT-hard ที่รอ swap ตอน boot |
| `lock.d/` | mkdir-lock (flock ใช้ไม่ได้บน toybox; stale-recovery ด้วย PID) |
| `tools/<abi>/curl` | curl แบบ static ที่ดึงมา (slim bootstrap); คงอยู่ข้ามการอัปเดต |
| `cancel` | คำขอยกเลิก |

<!-- doc-footer -->

---

> _เอกสารนี้สร้างขึ้นด้วย Claude (Anthropic) และดูแลโดย VD171 ยินดีรับการแก้ไขและการปรับปรุง ดู [CONTRIBUTING.md](CONTRIBUTING.md)_
