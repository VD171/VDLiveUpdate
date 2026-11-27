> **Languages:** [English](../INTERFACES.md) · [العربية](../ar/INTERFACES.md) · [Čeština](../cs/INTERFACES.md) · [Deutsch](../de/INTERFACES.md) · [Español](../es/INTERFACES.md) · [فارسی](../fa/INTERFACES.md) · [Français](../fr/INTERFACES.md) · [हिन्दी](../hi/INTERFACES.md) · [Bahasa Indonesia](../id/INTERFACES.md) · [Italiano](../it/INTERFACES.md) · [日本語](../ja/INTERFACES.md) · [한국어](../ko/INTERFACES.md) · [Nederlands](../nl/INTERFACES.md) · [Polski](../pl/INTERFACES.md) · [Português](../pt/INTERFACES.md) · [Русский](../ru/INTERFACES.md) · [Svenska](../sv/INTERFACES.md) · ไทย · [Türkçe](../tr/INTERFACES.md) · [Українська](../uk/INTERFACES.md) · [Tiếng Việt](../vi/INTERFACES.md) · [中文](../zh/INTERFACES.md)

---

# VDLU - สัญญาอินเทอร์เฟซ (รอยต่อระหว่างคอมโพเนนต์)

**กฎแห่งการบรรจบ (Law of convergence):** ทุกคอมโพเนนต์ต้องสอดคล้องกับไฟล์นี้ ชิ้นส่วนจาก 4 เอเจนต์ต้อง **ประกอบเข้ากันได้** - ลายเซ็น
CLI, ชื่อไฟล์ และคีย์ JSON ด้านล่างนี้ **เปลี่ยนแปลงไม่ได้** (การเปลี่ยนแปลงหมายถึงต้องปรับให้ตรงกันที่นี่ก่อน)

หลักการที่สืบทอดมาจากรีโพ: **pure POSIX sh** บนอุปกรณ์ (ไม่มี bashism, รันด้วย toybox/busybox +
`sha256sum`/`gzip`/`base64` ของ toybox + `curl` ที่ดึงมา + `ed25519-mini` ที่ฝังไว้ - เรียว ไม่มีชุด bin
ติดมาด้วย), **ไม่มีคอมเมนต์ที่ไม่จำเป็น**, **เป็น release เสมอ**, **เข้มงวดเมื่อล้มเหลว** (ทรานแซกชันที่กลับมาทำต่อได้, ไม่มีอะไร
"เสร็จแล้ว" แบบปลอม ๆ, ไม่มีอะไรสูญหาย), **ไม่ผ่อนปรนอะไร**

---

## 1. โครงสร้างสถานะ (Tier-2, อยู่นอกไดเรกทอรีของโมดูล)

```
$VDLU_DIR = /data/adb/<module>/vdlu
  config               # key=value (§5)
  current.json         # manifest of the ACTIVE version (diff base); absent = never updated
  journal.json         # transaction in progress (§4); absent = idle
  cancel               # presence = cancel request (WebUI creates it; engine deletes it on stop)
  lock.d/              # mkdir-lock (flock unworkable on toybox; stale-recovery by PID)
  blobs/<sha256>       # cache of verified blobs (ORIGINAL content, already decompressed)
  rollback/<version>/<path>   # backup of overwritten files
  staged/<path>.vdlu-new      # REBOOT-hard awaiting swap at boot
  target.json          # PINNED manifest of the in-flight transaction (presence = active transaction; becomes current.json on DONE)
  plan.tsv  plan.del   # engine's internal plan (progress); the WebUI IGNORES it (reads only journal/config/current)
```
`cancelled:true` ใน journal = เอนจินหยุดเพราะการยกเลิก (สถานะที่ยังไม่สิ้นสุด, กลับมาทำต่อได้, `error`
ยังคงเป็น null)

เอนจินถูก vendor เข้าไปในโมดูล: `$MODULE_DIR/vdlu/update.sh` (+ `vdlu-verify`) `$MODULE_DIR =
/data/adb/modules/<module>` เอนจินรับผ่าน env: `VDLU_DIR`, `MODULE_DIR`, `MODID`

## 2. CLI ของเอนจิน (คอมโพเนนต์ ENGINE)

`sh update.sh <cmd>` - rc 0 = ok, !=0 = error (stderr มีเหตุผลอยู่):

| cmd | ทำอะไร |
|---|---|
| `check` | DIFF: ดาวน์โหลด manifest, เปรียบเทียบ; พิมพ์ JSON บรรทัดเดียว `{"update":bool,"from":N,"to":M,"fetch":K,"reboot":bool}`; ไม่เปลี่ยนแปลงอะไร อุปกรณ์ AHEAD (ล้ำหน้า) กว่าฟีด (บล็อก downgrade, ทำให้แข็งแรงขึ้น) = สถานะ BENIGN (ไม่เป็นอันตราย): `{"update":false,"ahead":true,"from":N,"to":M}` + rc0 (ไม่เคยเป็น "check failed") do_diff rc: 2 fetch/parse, 3 verify/meta, 4 ahead |
| `run` | รอบเต็ม: DIFF->FETCH->APPLY->COMMIT; เคารพ `cancel`; เขียนความคืบหน้าไปยัง `journal.json`; apply แบบ LIVE, stage REBOOT-hard |
| `resume` | ทำทรานแซกชัน `journal.json` ต่อจากเฟสปัจจุบัน (idempotent) |
| `boot` | โหมด pre-zygote: `resume` + ทำ SWAP ของ `staged/*.vdlu-new` (apply `.so`), ปิด `PENDING_REBOOT`->`DONE` |
| `status` | พิมพ์ `journal.json` (หรือ `{"state":"idle"}`) |
| `cancel` | สร้าง `$VDLU_DIR/cancel` (`run` ที่กำลังทำงานจะหยุดที่จุดปลอดภัยถัดไป) |

แหล่งของ blob/manifest: `source` จาก config `<source>` + `/manifest.json`, `/blobs/<sha>`, `/blobs/<sha>.gz`
`source` ขึ้นต้นด้วย `https://` (curl แบบ static ดึงมา, TLS) หรือ `file://` (staging แบบ local)

## 3. manifest.json (ผลิตโดย PRODUCER, บริโภคโดย ENGINE)

```json
{ "schema":1, "module":"<id>", "version":<int>, "version_name":"<str>", "built":"<ISO8601>",
  "engine_min":5, "key_id":"<str>", "channel":"stable",
  "files":[ {"path":"webroot/index.html","sha256":"<hex64>","size":<int>,"mode":"0644","enc":"raw|gz","class":"live|soft|reboot"} ],
  "delete":["<path>"], "sig":"<base64>" }
```

- `files[]` = ต้นไม้เป้าหมายแบบครบถ้วน `class`: `live` (webroot/bin/lib/confs/scripts-on-demand/module.prop) ·
  `soft` (service.sh/post-fs-data.sh/boot-completed.sh) · `reboot` (`zygisk/**/*.so`, `system/**`, `*.rule`)
  ค่าดีฟอลต์ตาม path, ไม่เคยลดระดับ `reboot`->`live`
- `enc`: `gz` (gzip `-9 -n`, deterministic, toybox gunzip บนอุปกรณ์) เฉพาะเมื่อบีบอัดได้ดี และ
  ขนาดมีนัยสำคัญ, `sha256` เป็นของเนื้อหาต้นฉบับ เสมอ
- `sig`: ลายเซ็นของ manifest เชิง canonical โดยไม่มีฟิลด์ `sig` (§4 ของ verify)
- **การกัน trust anchor (ฝั่ง engine, VDLU#2):** engine ทิ้งจาก plan ทุก path `files[]`/`delete[]` ที่อยู่
  ภายใต้ `vdlu/` (`update.sh`/`vdlu-verify`/`verify/*`/`keyring/*`/config ของตัวเอง) - ไม่เคย fetch, apply,
  หรือลบ - แม้ว่าฟีดที่เซ็นแล้วจะพกมันมา trust anchor บนอุปกรณ์เปลี่ยนได้เฉพาะด้วยการ re-flash ที่เซ็นแล้ว
  เต็มรูปแบบ ไม่ใช่ผ่านเครือข่าย, `vdlu-pack` ก็กัน `vdlu/` ออกฝั่ง producer ด้วย ดังนั้นนี่จึงเป็น guard ที่สอง
  ฝั่ง engine ต่อคีย์สำหรับเซ็นที่รั่วไหล

## 4. journal.json (ENGINE เขียน, WEBUI อ่าน - สัญญาเรื่องความคืบหน้า)

```json
{ "schema":1, "module":"<id>", "target":<version>, "from":<version>,
  "phase":"diff|fetch|apply|commit", "state":"PLANNED|FETCHING|FETCHED|APPLYING|APPLIED_LIVE|PENDING_REBOOT|DONE|ERROR|DEFERRED",
  "total":<int>, "done":<int>, "current":"<path>", "bytes":<int>, "reboot_pending":bool,
  "cancelled":bool, "error":"<str|null>", "updated":"<ISO8601>",
  "items":[ {"path":"<p>","sha256":"<h>","class":"<c>","st":"pending|fetched|applied|staged|skipped"} ] }
```

เครื่องจักรสถานะ (ลำดับตายตัว): `PLANNED->FETCHING->FETCHED->APPLYING->APPLIED_LIVE->(PENDING_REBOOT|DONE)`
`DONE` เกิดขึ้นเมื่อ re-hash ของ ทุกอย่าง ตรงกันเท่านั้น หาก stage REBOOT-hard => `PENDING_REBOOT` (ไม่ใช่ `DONE`) ทางออก
จากเฟส `fetch`: `ERROR` (ความล้มเหลวร้ายแรง) หรือ `DEFERRED` (net_policy บล็อกการดาวน์โหลด - ไม่เป็นอันตราย/กลับมาทำต่อได้,
ไม่ใช่ error)

## 5. config (key=value, หนึ่งต่อบรรทัด, แก้ไขได้ใน WEBUI)

```
auto_on_webui_open=0
auto_on_reboot=1
source=https://<user>.github.io/<repo>/<module>
channel=stable
profile=trusted        # trusted | hardened. CODE DEFAULT (line absent) = hardened (fail-closed, 9a9a824)
net_policy=any         # any (Wi-Fi+mobile) | wifi (Wi-Fi only) | mobile (mobile only) - gates the DOWNLOAD by network type
allow_metered=0        # ⚠️ SUPERSEDED by net_policy (not consumed by the engine)
pubkey_dir=keyring     # relative to $MODULE_DIR/vdlu (keyring of pubkeys for verify)
key_id=                # ALLOWLIST of accepted MODULE-UPDATE signing key id(s), comma-separated (rotation).
                       # UNSET = default-safe: a single-key keyring accepts only that one key; a MULTI-key
                       # keyring (one that also ships a fingerprint-feed key) MUST pin its module key here.
ca_path=               # empty = auto-detect of the Android trust store; set a path to override
ca_cert=               # empty = auto-build a CA bundle from the trust store; set a path to a bundle to override
tools_source=          # empty = derived from source (.../vdlu-tools); feed of the static curl
apply_busy_file=       # OPT-IN: absolute path the host module touches during its own operations (e.g. a
                       # backup). While it EXISTS, APPLY is deferred to the next trigger (blobs already
                       # fetched, no re-download) so an update never swaps module files mid-operation. UNSET = off.
boot_retry_interval=30 # seconds between probes when BOOT finds the device offline (floor 5s)
boot_retry_minutes=0   # ceiling of the PATIENT retry (AWAKE-time) only at boot; 0 = off. Battery-safe (no wakelock,
                       # no held lock, route probe never wakes the radio) -> a generous ceiling is ~free
```

**Boot retry (ออฟไลน์) - อดทน (PATIENT), ประหยัดแบตเตอรี่:** เฉพาะตอน `boot` (ไม่เคยตอน check/auto-open) หากการดึง
manifest ล้มเหลวเพราะ เครือข่าย (`fetch_offline` จำแนกจาก exit ของ fetcher) มันจะรอแล้วลองใหม่จนกว่าจะ
สำเร็จ หรือ จนกว่า AWAKE-time จำนวน `boot_retry_minutes` จะหมดลง การออกแบบที่ **ไม่ยึดอะไรไว้และไม่ดูดแบตเตอรี่**:
- **Zero wakelock:** ระหว่างรอบมันคือ `sleep` ซึ่งถูกแช่แข็งใน deep-sleep -> อุปกรณ์หลับได้ตามปกติ
  (~แบตเตอรี่เป็นศูนย์), การลองใหม่จะหยุดชั่วคราวและกลับมาทำต่อเมื่ออุปกรณ์ตื่นอยู่แล้ว
- **Zero held lock:** `acquire_lock_try`+release ระหว่างรอบ (ไม่ยึด lock ไว้ขณะรอ) ->
  `run`/การ check ด้วยมือไม่เคยถูกบล็อก, ถ้าการ run ด้วยมือ stage TARGET ในระหว่างนั้น boot จะเลื่อนออกไป
- **ไม่ปลุกวิทยุ (radio) โดยไม่จำเป็น:** การ probe แบบ `net_allowed` (ผ่าน `net_type`/`ip route get`, การ
  lookup route ของ kernel ที่เคารพ policy-routing ของ Android, ไม่มีแพ็กเก็ต) คอยคุมแต่ละรอบ - มันใช้ fetch
  ก็ต่อเมื่อเครือข่ายปรากฏขึ้นแล้วเท่านั้น
- ไม่เคย ลองใหม่กับความล้มเหลวแบบ deterministic (manifest/sig/downgrade) `--connect-timeout 15` บน fetch (ไม่
  ค้างกับ captive portal) `service.sh` รันมันเป็น background (boot ไม่เคยค้าง)
- ⛔ **HARD: การเปิด `boot_retry_minutes>0` ต้องใช้เอนจินแบบ PATIENT** (ตัวที่มี
  `net_allowed`+`acquire_lock_try`, canonical `da7115f4`+) boot-retry รุ่นก่อน (ยึด lock ไว้ตลอดทั้ง
  หน้าต่างเวลา + ลองใหม่ด้วย blind curl ขณะออฟไลน์) **ดูดแบตเตอรี่/ปลุกวิทยุ** - การเปิดการลองใหม่ในเอนจินเก่า
  เป็น footgun เมื่อจะเปิดใช้งาน ให้ vendor เอนจินปัจจุบัน

**`net_policy` (any|wifi|mobile):** คอยคุม **การดาวน์โหลด** ตามประเภทเครือข่าย `net_type()` จำแนก egress
ของ `ip route get` (cellular iface `rmnet/ccmni/v4-*/clat` = mobile, อย่างอื่นทั้งหมด = wifi, kernel lookup, ไม่มี
แพ็กเก็ต) `net_allowed()` เปรียบเทียบกับ `net_policy` และคอยคุม `do_fetch` (blobs) + การ probe ของ boot-retry
แบบอดทน **การ check manifest ยังคงฟรี** (เล็ก -> UI รายงานว่ามีอัปเดตบนเครือข่ายใดก็ได้), เฉพาะการดาวน์โหลด
เท่านั้นที่รอเครือข่ายที่อนุญาต การดาวน์โหลดบนเครือข่ายที่ไม่อนุญาต = สถานะ **`DEFERRED`** ใน journal
(ไม่ใช่ ERROR, toast INFO สีน้ำเงินอย่างนุ่มนวล "waiting for X network", plan/target ยังคงอยู่, มันกลับมาทำต่อในการ
check/boot ครั้งถัดไปบนเครือข่ายที่ถูกต้อง) `net_policy` **แทนที่** `allow_metered` (ซึ่งไม่เคยถูกบริโภค)
เอนจิน `97baf887`+ (`file://` ไม่เคยถูกคุม)

## 6. ลายเซ็น (PRODUCER เซ็นบน PC ผ่าน openssl, ENGINE ตรวจสอบบนอุปกรณ์ผ่าน ed25519-mini)

- Canonicalization: manifest ที่ไม่มี `sig`, คีย์เรียงลำดับ, JSON แบบ compact (ไม่มีช่องว่างเกิน), UTF-8
  สิ่งที่ถูกเซ็น/ตรวจสอบ = `sha256` hex ของรูป canonical นั้น (ให้ determinism ข้ามเครื่องมือ)
- `producer/vdlu-sign <manifest.json> <privkey.pem> <key_id>` -> ฉีด `key_id` + `sig` (base64 ของลายเซ็น ed25519 ของ canonical sha256) เข้าไปใน manifest ในที่เดิม
- `engine/vdlu-verify <manifest.json> <keyring_dir>` -> rc 0 ถ้า `sig` ตรงกับ pubkey `<key_id>.pub` ใน
  keyring (SLIM: pubkey **RAW 32 bytes**) ภายใน ไม่มี openssl: toybox `sha256sum`/`base64 -d` + ไบนารี
  `ed25519-mini` ที่ฝังไว้ (CLI `ed25519-mini <pub32> <msg> <sig64>`, rc 0=valid/1=invalid/2=usage)
  rc!=0 = reject **`profile=hardened` => verify จำเป็น, ล้มเหลว = abort**
  `profile=trusted` => verify เป็น best-effort (แหล่งเชื่อถือแล้วผ่าน SSH), แต่ hash ของทุก blob ถูกตรวจสอบ เสมอ
- **allowlist ของคีย์ module-update (fail-closed, ก่อนการเลือก pubkey):** `key_id` ของ manifest ต้องเป็นคีย์ MODULE-UPDATE ที่ยอมรับแล้วก่อนที่จะเลือก `<key_id>.pub` - `key_id` ของ config (§5) คือ allowlist นั้น keyring อาจพกคีย์ที่ความเชื่อถือต่ำกว่าได้ด้วย (เช่น คีย์ fingerprint-feed, อัตโนมัติ, คนละบัญชี) หากไม่มี allowlist, manifest ที่เซ็นด้วยคีย์นั้นจะผ่านการตรวจสอบและใช้การอัปเดต flashless root เต็มรูปแบบหากรั่วไหล `verify_manifest` บังคับใช้ในทั้งสอง profiles และส่งเซ็ตที่แก้แล้วให้ `vdlu-verify` ผ่าน env `VDLU_KEYID_ALLOW` (เพื่อให้ verifier แบบ standalone เห็นตรงกัน) ไม่ได้ตั้งค่า = ปลอดภัยโดยปริยาย (keyring คีย์เดียว: เฉพาะคีย์นั้น, keyring หลายคีย์: ปฏิเสธจนกว่าจะปักหมุด `key_id`) รากความเชื่อถือของ fingerprint-feed เป็นเส้นทางแยกต่างหากที่มีคีย์ปักหมุดของตัวเอง และไม่ได้รับผลกระทบ
- `producer/vdlu-keygen <id> <out>` -> สร้าง `<id>.pem` (priv) + `<id>.pub` (PEM, สำหรับ tooling บน PC) +
  `<id>.pub.raw` (**RAW 32B** = `<id>.pub` ของ keyring แบบเรียวบนอุปกรณ์) openssl `genpkey -algorithm ed25519`

## 7. Blob - การตรวจสอบ (ENGINE)

ดาวน์โหลด `<source>/blobs/<sha>` (หรือ `.gz` ถ้า `enc=gz`), เขียน `.part`, ถ้าเป็น `gz` ก็ decompress (`gunzip`),
ตรวจสอบ `sha256sum` == `sha256` ของ manifest, ตรงกัน -> `mv` แบบ atomic ไปยัง `$VDLU_DIR/blobs/<sha>` ล้มเหลว 3 ครั้งบน
blob เดียวกัน = ยกเลิกเฟส (ไม่มีการ apply อะไร) blob ที่อยู่ใน `$VDLU_DIR/blobs/<sha>` แล้วและมี hash ที่ถูกต้อง =
ข้ามการดาวน์โหลด

## 8. APPLY ตาม class (ENGINE)

- `live`/`soft`: backup `rollback/<v>/<path>` -> เขียน `$MODULE_DIR/<path>.vdlu-tmp` จาก blob -> `chmod mode` ->
  `rename` แบบ atomic ทับเป้าหมาย อยู่ที่ hash เป้าหมายแล้ว = ข้าม (ในรุ่น Zygisk การเขียนไปที่ไดเรกทอรีที่
  mount ไว้ = merge ทีละไฟล์, ไม่เคย `rm -rf` ไดเรกทอรี)
- `reboot`: สร้างชิ้นเข้าไปใน `$VDLU_DIR/staged/<path>.vdlu-new` (ไม่ แตะตัว live) การ swap อยู่ที่ `boot`
- `delete[]`: backup -> ลบ

## 9. WEBUI <-> ENGINE (คอมโพเนนต์ WEBUI)

- ยิง: `ksu.exec("sh $MODULE_DIR/vdlu/update.sh run")` (background)
- ความคืบหน้า: poll เบา ๆ `ksu.exec("cat $VDLU_DIR/journal.json")` ทุก ~1s, เรนเดอร์ `{phase,state,total,done,current,bytes}`
- Liveness: journal หายไป 8 ticks => "no response" journal FROZEN (ค่าเดิม) 20 ticks => เช็ค `lock.d`: ยังมีชีวิต = ทำต่อ (fetch blob 1 ตัวช้า), ตาย = error + Resume หากไม่มีสิ่งนี้ การ run ที่ตายกลางการ fetch จะทำให้ toast ค้างอยู่ที่ "updating"
- Cancel: `ksu.exec("touch $VDLU_DIR/cancel")`
- Config: อ่าน/เขียน `$VDLU_DIR/config` (key=value) ในแท็บ "Updates"
- Toast: บาร์ + `phase done/total · current`, เมื่อจบด้วย `reboot_pending` => แบนเนอร์ถาวร "reboot to activate the .so"
- Auto-open (`auto_on_webui_open=1`): ทำ `check()` แบบ เงียบ ก่อน (ไม่มี toast ความคืบหน้า), จะยิง `run`+toast ถาวรก็ต่อเมื่อ `update && fetch>0` ทันสมัยแล้ว/ล้ำหน้า/ไม่มีอะไรใหม่ = ผลลัพธ์ inline ในแผง, ไม่มี toast ค้าง ไม่รบกวนเหมือนปุ่มกดเอง (toast ปรากฏเฉพาะเมื่อมีการดาวน์โหลดจริง) การ bootstrap curl เป็นครั้งเดียว

## 10. การ Integrate เข้ากับ demo (คอมโพเนนต์ INTEGRATION) - SNIPPET, อย่าแก้ไฟล์ที่ใช้งานจริง

ผลิต, ใน `integration/demo/`, snippet + `INTEGRATION.md` ที่ระบุว่าแต่ละอันไปอยู่ตรงไหน (โดยไม่ apply):
- hook `auto_on_reboot` ใน `post-fs-data`/`service.sh` (pre-zygote -> `update.sh boot`) และ `auto_on_webui_open`
- ค่าดีฟอลต์ `config` + keyring ที่ฝังไว้ + การ vendor (`modules/<mod>/vdlu/`)
- รุ่น PARTIAL (merge เข้าไปในไดเรกทอรีที่ mount ไว้)

## 11. toolchain ที่ดึงมา + baseline (SLIM, แนวทาง B)

**โครงสร้างในโมดูล (zip):** `vdlu/{update.sh, vdlu-verify, config.default, keyring/<id>.pub (RAW 32B),
verify/<abi>/ed25519-mini, baseline.json}` **ไม่มี** `bin/` (openssl/curl/zstd) `customize.sh` สามารถตัด
`verify/` ให้เหลือแค่ ABI ของอุปกรณ์ได้ (`vdlu-verify` หา mini ที่ `<dir>/ed25519-mini` หรือ `<dir>/verify/<abi>/ed25519-mini`)

**ed25519-mini** (ไบนารีฝังไว้, verify-only): `ed25519-mini <pubkey32> <msg> <sig64>` -> rc 0=valid,
1=invalid, 2=usage/IO msg = ไบต์ที่ถูกเซ็นแบบตรงเป๊ะ (ไม่ re-hash) TweetNaCl PD, static ต่อ ABI, PROVENANCE

**tools-feed** (เฉพาะโปรไฟล์ public/https): ให้บริการที่ `<tools_source>` (default ที่ derive มา: สลับ segment
สุดท้ายของ `source` เป็น `vdlu-tools`, เช่น `https://<user>.github.io/<repo>/vdlu-tools`) มี:
- `tools-manifest.json` - manifest `vdlu-pack` ที่ SIGNED แล้ว เหนือต้นไม้ `<abi>/curl`, ปัก `sha256` ของ
  curl แต่ละตัว (คีย์ `release-2026` เดียวกัน)
- `<abi>/curl` - curl แบบ **static** ดิบ (self-contained, ~1MB, curl 8.11.1 + mbedTLS) 🪤 mbedTLS ไม่
  มี CA bundle: `fetch_url` ส่ง `--capath` (auto-detect ของ Android trust store: `/system/etc/security/cacerts`
  -> APEX conscrypt, `ca_path` override) ไม่มี capath = error 60 ความถูกต้องคือ ed25519, การเช็ค cert เป็น defense-in-depth

**install-tool** (ENGINE): `update.sh install-tool <abi>` อ่าน `$VDLU_DIR/.work/{tools-manifest.json, tool.<abi>}`
(WEBUI ดาวน์โหลดมันผ่าน `fetch()` และเขียนไว้ที่นั่น), **ตรวจสอบลายเซ็นของ tools-manifest (ed25519-mini,
จำเป็นในทุกโปรไฟล์)** + hash ของ curl == manifest, แล้วจึงติดตั้งไปที่ `$VDLU_DIR/tools/<abi>/curl` (0755) เท่านั้น
curl รันในฐานะ root -> sig+hash ก่อน exec ปิดช่อง RCE คงอยู่ใน Tier-2: ไม่เคยดาวน์โหลดใหม่ (ยกเว้นตอน uninstall)

**fetch-bootstrap** (WEBUI, `ensureToolchain()`): รันก่อน check/run/resume `file://` = no-op, curl พร้อมใช้งานอยู่แล้ว
(Tier-2, หรือ `module/bin/<abi>/curl` จากโมดูลที่ **bundle มาเอง**, หรือ system) = no-op
(VDLU ใช้ curl ที่มีอยู่ซ้ำ), เฉพาะ `https` **ที่ไม่มี curl เลย** เท่านั้นที่ดาวน์โหลด curl + tools-manifest ผ่าน webview, เขียน
ไว้ที่ `.work` (base64 เป็น chunk ผ่าน `ksu.exec`), เรียก `install-tool` ความเชื่อถือ = การเช็คบนอุปกรณ์, ไม่ใช่การดาวน์โหลด

> 🪤 **Slim (fetch-bootstrap) != จำเป็น** โมดูลที่มี `bin/` อยู่เพื่อฟีเจอร์ของ ตัวเอง (เช่น bundle
> restic/rclone/age/tar/curl...) **ไม่** เรียวลงเหลือ ~2MB และไม่ดาวน์โหลด curl - VDLU รับเอนจินแบบ slim
> (gz, mini, baseline, fixes) และ **ใช้ซ้ำ** toolchain ที่ฝังไว้ เฉพาะโมดูลที่ไม่มี toolchain ของตัวเอง
> เท่านั้นที่ได้รับ ~2MB เพิ่ม

**baseline.json** (fix from:0): release คัดลอก `manifest.json` ที่ SIGNED แล้ว ของเวอร์ชันที่ ship ไปยัง
`vdlu/baseline.json`, ในการติดตั้งใหม่เอนจิน seed `current.json` จากมัน (`init_paths`, เฉพาะเมื่อไม่มี) -> อุปกรณ์
เกิดมา "current" โดยไม่มีการ auto-update ตัวเองและไม่มีการ re-fetch

<!-- doc-footer -->

---

> _เอกสารนี้สร้างขึ้นด้วย Claude (Anthropic) และดูแลโดย VD171 ยินดีรับการแก้ไขและการปรับปรุง ดู [CONTRIBUTING.md](CONTRIBUTING.md)_
