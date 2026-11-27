<!--
  ======================================================================
   VDLiveUpdate (VDLU)  ::  flashless, incremental module updates
   A self-update engine for KernelSU/APatch/Magisk modules: fetch only the
   files that changed, apply the live ones with no reboot, verified by ed25519.

   Copyright (C) 2026  VD171
   SPDX-License-Identifier: Apache-2.0

   Licensed under the Apache License, Version 2.0; you may obtain a copy at
   http://www.apache.org/licenses/LICENSE-2.0

   Site           : https://vd171.ru
   Site           : https://vd.priv8.ru
   Source         : https://github.com/VD171/VDLiveUpdate
   GitHub         : @VD171 https://github.com/VD171
   XDA-Developers : @VD171 https://xdaforums.com/m/vd171.4699873/
   Telegram       : @VD_Priv8 https://t.me/VD_Priv8
   Channel        : @Priv8_VD https://t.me/Priv8_VD
   Discord        : @VD.Priv8 https://discord.com/users/1296831918989639721
   E-mail         : vd.priv8@pm.me
  ======================================================================
-->

# VD Live Update

> **Languages:** [English](README.md) · [العربية](README.ar.md) · [Čeština](README.cs.md) · [Deutsch](README.de.md) · [Español](README.es.md) · [فارسی](README.fa.md) · [Français](README.fr.md) · [हिन्दी](README.hi.md) · [Bahasa Indonesia](README.id.md) · [Italiano](README.it.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Nederlands](README.nl.md) · [Polski](README.pl.md) · [Português](README.pt.md) · [Русский](README.ru.md) · [Svenska](README.sv.md) · ไทย · [Türkçe](README.tr.md) · [Українська](README.uk.md) · [Tiếng Việt](README.vi.md) · [中文](README.zh.md)

<p align="center">
  <img src="images/logo-wordmark.png" alt="VD Live Update" width="320">
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-Apache--2.0-1a7f37" alt="License"></a>
  <a href="https://github.com/VD171/VDLiveUpdate/stargazers"><img src="https://img.shields.io/github/stars/VD171/VDLiveUpdate?color=d29922" alt="Stars"></a>
</p>

<p align="center">
  <a href="docs/QUICKSTART.md">Quickstart</a> ·
  <a href="docs/ENGINE.md">Engine</a> ·
  <a href="docs/PRODUCER.md">Producer</a> ·
  <a href="docs/WEBUI.md">WebUI</a> ·
  <a href="docs/INTERFACES.md">Interfaces</a> ·
  <a href="docs/AI-AGENTS.md">AI agents</a> ·
  <a href="docs/TRUST-MODEL.md">Trust model</a>
</p>

**VDLU** เป็นเอนจินสำหรับการอัปเดตตัวเองแบบ flashless และแบบเพิ่มส่วนต่าง (incremental) สำหรับโมดูล **KernelSU / APatch / Magisk** โมดูลที่ติดตั้งแล้วจะอัปเดตตัวเองโดยดึง **เฉพาะไฟล์ที่เปลี่ยนแปลง** (blobs แบบ content-addressed + manifest ที่เซ็นลายเซ็นแล้ว) นำไฟล์ที่ทำได้ไปใช้แบบ live **โดยไม่ต้องรีบูต** และจัดเตรียม (stage) พร้อมติดธงให้กับไฟล์ไม่กี่ไฟล์ที่จำเป็นต้องรีบูตจริง ๆ (ไฟล์ `.so`, overlay บน `/system`, `sepolicy.rule`) ไม่ต้องใช้ root manager ไม่ต้องดาวน์โหลด `.zip` ทั้งก้อนใหม่ และไม่ต้องรีบูตยกเว้นสำหรับไฟล์ที่จัดเตรียมไว้เหล่านั้น

มันถูกออกแบบมาเพื่อ **vendor** เข้าไปในโมดูล (วางไว้ใน `<module>/vdlu/`) ไม่ใช่เพื่อรันเป็นโมดูลด้วยตัวมันเอง

## ทำไม

การอัปเดตโมดูลแบบปกติจะส่ง `.zip` ทั้งก้อนมาอีกครั้ง สำหรับโมดูลขนาดใหญ่ นั่นหมายถึงการดาวน์โหลดซ้ำก้อนใหญ่เพื่อโค้ดที่เปลี่ยนไปไม่กี่บรรทัด และ manifest การอัปเดตแบบ static ชี้ไปได้เพียง `zipUrl` เดียว จึงไม่สามารถให้บริการ flavor (ABI, full vs lite) ตามที่อุปกรณ์มีจริงได้ VDLU จะ diff ต้นไม้ที่ **ติดตั้งอยู่** เทียบกับฟีดที่เซ็นลายเซ็นแล้ว แล้วดึงเฉพาะส่วนต่าง (delta) เท่านั้น ดังนั้นการติดตั้งแบบ arm64-full ก็ยังเป็น arm64-full การติดตั้งแบบ lite ก็ยังเป็น lite และการอัปเดตส่วนใหญ่ก็ถูกนำไปใช้แบบ live

## วิธีการทำงาน

- **ตัวผลิต (Producer, PC / release):** `vdlu-pack` แปลงต้นไม้ของโมดูลให้เป็นฟีดแบบ content-addressed (`manifest.json` + `blobs/<sha256>`, gzip, dedup, `delete[]`), `vdlu-keygen` / `vdlu-sign` (ed25519), `vdlu-gc` ตัดแต่ง blobs ที่กำพร้าโดยอ้างอิงกับ manifest N ชุดล่าสุด (fail-safe, dry-run เป็นค่าเริ่มต้น)
- **เอนจิน (อุปกรณ์):** POSIX sh ไม่ใช้ `jq` `update.sh` (`check | run | resume | boot | status | cancel`) รัน DIFF -> FETCH -> APPLY -> COMMIT เป็น **ธุรกรรมที่กลับมาทำต่อได้** (journal) พร้อม rollback และล็อกแบบ `mkdir` ลายเซ็นถูกตรวจสอบด้วย `ed25519-mini` ที่ฝังมา (ไม่มี `openssl` บนอุปกรณ์)
- **WebUI:** แผง Updates แบบ drop-in (toast แสดงความคืบหน้า, ยกเลิก, แบนเนอร์รีบูต), vanilla JS

## โปรไฟล์

- `trusted`: ใช้งานส่วนตัว, แหล่ง `file://` หรือ SSH, ตรวจสอบแบบ best-effort (hash เสมอ)
- `hardened`: ใช้งานสาธารณะ, **ลายเซ็นบังคับ**, บล็อกการ downgrade. manifest ถูก **ผูกกับ id ของโมดูล** และทุกฟิลด์ถูกตรวจสอบแบบ fail-closed ก่อนที่จะมีการดาวน์โหลดสิ่งใด

## นำไปใช้ในโมดูลของคุณ

Vendor `engine/update.sh` + `vdlu-verify` + `verify/<abi>/ed25519-mini` เข้าไปใน `<module>/vdlu/`, ฝัง **กุญแจสาธารณะแบบ raw 32 ไบต์** ของคุณเป็น `vdlu/keyring/<id>.pub`, เพิ่ม `config` (profile + source), ต่อสาย triggers (`post-fs-data.sh` แบบ pre-zygote สำหรับการอัปเดตอัตโนมัติตอนบูต, trigger เมื่อเปิด WebUI) และเพิ่ม `vdlu-pack` + `vdlu-sign` เข้าไปในขั้นตอน release ของคุณ ดูเทมเพลตที่ทำไว้ให้แล้วได้ที่ [`docs/QUICKSTART.md`](docs/QUICKSTART.md)

## ความปลอดภัย

- **ทุกฟิลด์ของ manifest คือ input ที่เป็นอันตราย** `validate_plan()` ปฏิเสธ manifest ทั้งก้อนแบบ fail-closed เมื่อเจอ path ที่เป็น absolute หรือ `..`, ค่า `sha256` ที่ไม่ใช่ hex 64 ตัว, หรือ mode / class / encoding ที่ไม่ถูกต้อง **ก่อน** ที่จะมีการ fetch หรือ apply ใด ๆ
- **กุญแจสำหรับเซ็นลายเซ็นส่วนตัวไม่เคยแตะต้อง CI หรืออุปกรณ์** มีเพียงกุญแจสาธารณะแบบ raw เท่านั้นที่ถูกฝัง และการตรวจสอบใช้ `ed25519-mini` ไม่ใช่ `openssl`
- `hardened` เป็น fail-closed โดยการกลับด้าน (inversion): อะไรก็ตามที่ไม่ใช่คำว่า `trusted` ตรงตัวจะถูกถือเป็น `hardened` ดังนั้นค่าโปรไฟล์ที่เสียหายจะไม่มีทางยอมรับ manifest ที่ไม่ได้เซ็นลายเซ็นแบบเงียบ ๆ ได้
- ไฟล์คลาสที่ต้องรีบูต (`.so`, overlay บน `/system`, `sepolicy.rule`) จะถูก **จัดเตรียมไว้ ไม่เขียนทับ inode ที่กำลังทำงานอยู่** ส่วนที่เหลือจะถูกนำไปใช้แบบ live การ apply ที่ล้มเหลวจะยกเลิก แทนที่จะเขียนทับโดยไม่มีสำเนาสำรอง

## การสร้าง / ทดสอบ

มันเป็นสคริปต์ ไม่มีอะไรต้องคอมไพล์ แบบ end-to-end (producer + engine ด้วยกัน):

```sh
producer/vdlu-keygen demo /tmp/k
producer/vdlu-pack /tmp/tree /tmp/feed demo 1 --version-name v1
producer/vdlu-sign /tmp/feed/manifest.json /tmp/k/demo.pem demo
VDLU_DIR=... MODULE_DIR=... MODID=demo sh engine/update.sh check   # then run / boot
```

`sh -n engine/*.sh`, `node --check webui/vdlu.js`, และเปิด `webui/demo.html` ในเว็บเบราว์เซอร์ (มัน mock สะพานเชื่อมอุปกรณ์ไว้)

## เอเจนต์ AI

เอนจินถูกควบคุมทั้งหมดจากเชลล์ (`sh engine/update.sh <check|run|resume|boot|status|cancel>` พิมพ์สถานะที่เครื่องอ่านได้) ดังนั้นเอเจนต์ AI จึงสามารถตรวจสอบ ใช้งาน และดำเนินการอัปเดตต่อได้โดยไม่ต้องมีส่วนติดต่อผู้ใช้ สัญญารอยต่อระหว่างส่วนประกอบอยู่ใน [`docs/INTERFACES.md`](docs/INTERFACES.md) และแพตช์จาก AI ต้องผ่านมาตรฐานการตรวจทานเดียวกับแพตช์อื่น ๆ

## เอกสาร

- [`INTERFACES.md`](docs/INTERFACES.md): สัญญารอยต่อ (seam contract) ระหว่างคอมโพเนนต์ (กฎแห่งการบรรจบ, ให้ถือว่าเปลี่ยนแปลงไม่ได้)
- [`ENGINE.md`](docs/ENGINE.md): engine ฝั่งอุปกรณ์ (`update.sh`): ทรานแซกชัน DIFF -> FETCH -> APPLY -> COMMIT ที่กลับมาทำต่อได้
- [`PRODUCER.md`](docs/PRODUCER.md): ฝั่ง PC/release: การสร้างและเซ็นฟีดแบบระบุที่อยู่ด้วยเนื้อหา (`vdlu-pack`, `vdlu-sign`)
- [`WEBUI.md`](docs/WEBUI.md): วิดเจ็ตแผง Updates แบบพร้อมใช้ (toast ความคืบหน้า, ยกเลิก, แบนเนอร์รีบูต)
- [`docs/QUICKSTART.md`](docs/QUICKSTART.md): คู่มือการนำไปใช้แบบทีละขั้นตอนและสคริปต์การต่อสาย

## ดูเพิ่มเติม

- **[COPG-VD](https://github.com/VD171/COPG-VD)**: การสปูฟ fingerprint ของอุปกรณ์ทั้งเครื่อง / Play Integrity ครอบคลุมทั้งอุปกรณ์ พร้อมขอบเขตแยกตามแอป และ WebUI
- **[VDBackup](https://github.com/VD171/VD-Backup)**: สำรองและกู้คืนแอปและข้อมูลแบบเต็มในฐานะ root ขับเคลื่อนทั้งหมดจาก WebUI
- **[VD-dropbear](https://github.com/VD171/VD-dropbear)**: ตัว SSH daemon แบบสแตนด์อโลนที่ทำงานด้วยสิทธิ์รูท (Dropbear).
- **[VDGoogle](https://github.com/VD171/VD-Google)**: บริการ Google ของคุณ (RCS, Wallet, การรับรอง Play Integrity) อ่านได้บนอุปกรณ์ของคุณโดยไม่ต้องใช้อินเทอร์เน็ต.
- **[VDInstaller](https://github.com/VD171/VD-Installer)**: ตัวติดตั้งแบบ sideload ด้วยสิทธิ์ root ที่ไร้แรงเสียดทาน สำหรับ APK เดี่ยว แบบชุด และแบบแยก พร้อมสวิตช์ตัวตรวจสอบ Play Protect และการปลอมแหล่งที่มาของการติดตั้ง
- **[VDInfos](https://github.com/VD171/VD-Infos)**: ตัวดีบักเมธอดของอุปกรณ์: อ่านแต่ละรายการผ่านทุกเมธอดที่อ่านมันได้ แล้วนำมาเทียบกันเคียงข้าง.
- **[VD-Modules](https://github.com/VD171/VD-Modules)**: คลังมอดูลของเราสำหรับ MMRL/WebUI-X (ติดตั้งทั้งหมดนี้จากตัวจัดการ root ของคุณ)
- **[@VictorGabriel7Dev/build.prop](https://github.com/VictorGabriel7Dev/build.prop)**: ชุดข้อมูล fingerprint ของ `build.prop` จาก Pixel (fork ของ @T3SL4)
- **[@VictorGabriel7Dev/mtproto-store](https://github.com/VictorGabriel7Dev/mtproto-store)**: ใช้ Telegram เป็น object store ผ่าน CLI เล็ก ๆ ที่เขียนด้วย Go

## ติดต่อ

- https://vd171.ru
- https://vd.priv8.ru
- **Telegram:** @VD_Priv8 https://t.me/VD_Priv8
- **Channel:** @Priv8_VD https://t.me/Priv8_VD
- **Discord:** @VD.Priv8 https://discord.com/users/1296831918989639721
- **E-mail:** vd.priv8@pm.me
- **XDA-Developers:** @VD171 https://xdaforums.com/m/vd171.4699873/
- **GitHub:** @VD171 https://github.com/VD171

## ลิขสิทธิ์

โค้ดของ VDLiveUpdate เองเป็น **Apache-2.0**, ดู [LICENSE](LICENSE) มันได้ vendor ตัวตรวจสอบ `ed25519-mini` ขนาดเล็กและ `curl` แบบ static สำหรับ fetch bootstrap โดยแต่ละตัวอยู่ภายใต้ลิขสิทธิ์ของตัวเอง, ดู
[NOTICE.md](NOTICE.md) และไฟล์ `PROVENANCE.json` ที่อยู่ข้าง ๆ ไบนารีที่มาพร้อมกัน

## เครื่องหมายการค้า

VDLiveUpdate เป็นโปรเจกต์อิสระที่ไม่เป็นทางการ ไม่มีความเกี่ยวข้องกับหรือได้รับการรับรองจากบุคคลที่สามใด ๆ
"Android" เป็นเครื่องหมายการค้าของ Google LLC, "KernelSU", "Magisk" และ "APatch" เป็นเครื่องหมายของ
ผู้สร้างแต่ละราย VDLU ทำงานทั้งหมดบนอุปกรณ์ของคุณและบนโฮสต์ release ของคุณเอง

## Tags

`VDLU` `flashless-update` `incremental-update` `KernelSU` `Magisk` `APatch` `module-update` `ed25519` `content-addressed` `OTA` `self-update` `Android` `VDLiveUpdate`

---

📣 **เข้าร่วมช่องเพื่อรับการอัปเดต:** @Priv8_VD https://t.me/Priv8_VD
