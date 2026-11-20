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

# VDLiveUpdate

> **Languages:** [English](README.md) · [العربية](README.ar.md) · [Čeština](README.cs.md) · [Deutsch](README.de.md) · [Español](README.es.md) · [فارسی](README.fa.md) · [Français](README.fr.md) · [हिन्दी](README.hi.md) · [Bahasa Indonesia](README.id.md) · [Italiano](README.it.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Nederlands](README.nl.md) · [Polski](README.pl.md) · [Português](README.pt.md) · [Русский](README.ru.md) · [Svenska](README.sv.md) · [ไทย](README.th.md) · [Türkçe](README.tr.md) · [Українська](README.uk.md) · [Tiếng Việt](README.vi.md) · [中文](README.zh.md)

**VDLU** adalah mesin self-update inkremental tanpa-flash untuk modul **KernelSU / APatch / Magisk**. Sebuah modul yang terpasang memperbarui dirinya sendiri dengan mengambil **hanya berkas yang berubah** (blob ber-alamat-konten + manifest bertanda tangan), menerapkan yang live **tanpa reboot**, lalu menyiapkan (stage) dan menandai segelintir berkas yang memang memerlukannya (sebuah `.so`, overlay `/system`, sebuah `sepolicy.rule`). Tanpa root manager, tanpa mengunduh ulang seluruh `.zip`, dan tanpa reboot kecuali untuk berkas-berkas yang di-stage itu.

Ia dirancang untuk **di-vendor** ke dalam sebuah modul (diletakkan di `<module>/vdlu/`), bukan dijalankan sebagai modul tersendiri.

## Mengapa

Pembaruan modul biasa mengirim ulang seluruh `.zip`. Untuk modul besar, itu berarti unduhan ulang yang besar hanya untuk beberapa baris yang berubah, dan manifest pembaruan statis hanya bisa menunjuk ke satu `zipUrl`, sehingga ia tidak dapat menyajikan flavor (ABI, full vs lite) yang benar-benar dimiliki perangkat. VDLU membandingkan (diff) pohon yang **terpasang** terhadap sebuah feed bertanda tangan dan hanya mengambil delta-nya, sehingga pemasangan arm64-full tetap arm64-full, pemasangan lite tetap lite, dan sebagian besar pembaruan diterapkan secara live.

## Cara kerjanya

- **Producer (PC / rilis):** `vdlu-pack` mengubah pohon modul menjadi feed ber-alamat-konten (`manifest.json` + `blobs/<sha256>`, gzip, dedup, `delete[]`); `vdlu-keygen` / `vdlu-sign` (ed25519); `vdlu-gc` memangkas blob yatim berdasarkan referensi ke N manifest terakhir (fail-safe, dry-run secara default).
- **Engine (perangkat):** POSIX sh, tanpa `jq`. `update.sh` (`check | run | resume | boot | status | cancel`) menjalankan DIFF -> FETCH -> APPLY -> COMMIT sebagai **transaksi yang dapat dilanjutkan (resumable)** (journal), dengan rollback dan kunci `mkdir`. Tanda tangan diverifikasi oleh `ed25519-mini` yang tertanam (tanpa `openssl` di perangkat).
- **WebUI:** panel Updates siap-pakai (toast kemajuan, cancel, banner reboot), vanilla JS.

## Profil

- `trusted`: penggunaan privat, sumber `file://` atau SSH, verifikasi best-effort (hash selalu).
- `hardened`: penggunaan publik, **tanda tangan wajib**, downgrade diblokir. Manifest **terikat pada id modul**, dan setiap field divalidasi secara fail-closed sebelum apa pun diunduh.

## Adopsi di modul Anda

Vendor `engine/update.sh` + `vdlu-verify` + `verify/<abi>/ed25519-mini` ke dalam `<module>/vdlu/`, sertakan **public key mentah 32-byte** Anda sebagai `vdlu/keyring/<id>.pub`, tambahkan sebuah `config` (profil + sumber), sambungkan pemicu-pemicunya (`post-fs-data.sh` pre-zygote untuk auto-update saat boot; sebuah pemicu WebUI-open), dan tambahkan `vdlu-pack` + `vdlu-sign` ke rilis Anda. Lihat [`docs/QUICKSTART.md`](docs/QUICKSTART.md) untuk templat yang sudah jadi.

## Keamanan

- **Setiap field manifest adalah input yang bermusuhan.** `validate_plan()` menolak seluruh manifest secara fail-closed pada path absolut atau `..`, sebuah `sha256` yang bukan 64 karakter hex, atau mode / class / encoding yang tidak valid, **sebelum** fetch atau apply apa pun.
- **Kunci penanda-tangan privat tidak pernah menyentuh CI maupun perangkat**; hanya public key mentah yang ditanamkan, dan verifikasi memakai `ed25519-mini`, bukan `openssl`.
- `hardened` bersifat fail-closed melalui inversi: apa pun selain literal `trusted` diperlakukan sebagai `hardened`, sehingga nilai profil yang rusak tidak akan pernah secara diam-diam menerima manifest tanpa tanda tangan.
- Berkas kelas-reboot (`.so`, overlay `/system`, `sepolicy.rule`) **di-stage, tidak pernah ditulis di atas inode yang live**; selebihnya diterapkan secara live. Sebuah apply yang gagal akan dibatalkan (abort) alih-alih menimpa tanpa cadangan.

## Build / tes

Ini adalah skrip, tidak ada yang perlu dikompilasi. End-to-end (producer + engine bersama-sama):

```sh
producer/vdlu-keygen demo /tmp/k
producer/vdlu-pack /tmp/tree /tmp/feed demo 1 --version-name v1
producer/vdlu-sign /tmp/feed/manifest.json /tmp/k/demo.pem demo
VDLU_DIR=... MODULE_DIR=... MODID=demo sh engine/update.sh check   # then run / boot
```

`sh -n engine/*.sh`, `node --check webui/vdlu.js`, dan buka `webui/demo.html` di sebuah peramban (ia mem-mock jembatan perangkat).

## Dokumentasi

- [`INTERFACES.md`](docs/INTERFACES.md): kontrak sambungan (seam contract) antar komponen (hukum konvergensi; perlakukan sebagai tak-berubah).
- [`ENGINE.md`](docs/ENGINE.md): engine sisi perangkat (`update.sh`): transaksi DIFF -> FETCH -> APPLY -> COMMIT yang dapat dilanjutkan.
- [`PRODUCER.md`](docs/PRODUCER.md): sisi PC/rilis: membangun dan menandatangani feed ber-alamat konten (`vdlu-pack`, `vdlu-sign`).
- [`WEBUI.md`](docs/WEBUI.md): widget panel Updates siap pakai (toast progres, batal, banner reboot).
- [`docs/QUICKSTART.md`](docs/QUICKSTART.md): panduan adopsi langkah-demi-langkah dan potongan kode wiring.

## Lihat juga

Proyek sejawat oleh penulis yang sama:

- **[VDInfos](https://github.com/VD171/VD-Infos)**: sebuah device method debugger yang membaca setiap item melalui setiap metode yang bisa membacanya.
- **[VDGoogle](https://github.com/VD171/VD-Google)**: membaca apa yang Google catat di perangkat Anda, sepenuhnya on-device dan tanpa internet.
- **[COPG-VD](https://github.com/VD171/COPG-VD)**: sebuah device spoofer yang mengubah fingerprint segar menjadi profil yang koheren dan konsisten.
- **[VD-dropbear](https://github.com/VD171/VD-dropbear)**: sebuah daemon SSH ber-root yang mandiri dan dapat dikonfigurasi untuk KernelSU/APatch/Magisk.
- **[VDBackup](https://github.com/VD171/VD-Backup)**: cadangkan dan pulihkan aplikasi serta data sepenuhnya sebagai root, dikendalikan seluruhnya dari sebuah WebUI.
- **[VDInstaller](https://github.com/VD171/VD-Installer)**: sebuah pemasang sideload ber-root tanpa hambatan untuk APK tunggal, batch, dan split, dengan sakelar verifier Play Protect dan pemalsuan sumber pemasangan.

## Kontak

- https://vd171.ru
- https://vd.priv8.ru
- **Telegram:** @VD_Priv8 https://t.me/VD_Priv8
- **Channel:** @Priv8_VD https://t.me/Priv8_VD
- **Discord:** @VD.Priv8 https://discord.com/users/1296831918989639721
- **E-mail:** vd.priv8@pm.me
- **XDA-Developers:** @VD171 https://xdaforums.com/m/vd171.4699873/
- **GitHub:** @VD171 https://github.com/VD171

## Lisensi

Kode milik VDLiveUpdate sendiri adalah **Apache-2.0**; lihat [LICENSE](LICENSE). Ia mem-vendor sebuah
verifier `ed25519-mini` kecil dan sebuah `curl` statis untuk bootstrap fetch, masing-masing di bawah lisensinya sendiri; lihat
[NOTICE.md](NOTICE.md) dan berkas-berkas `PROVENANCE.json` di samping biner yang di-bundel.

## Merek dagang

VDLiveUpdate adalah proyek independen dan tidak resmi, tidak berafiliasi dengan atau didukung oleh pihak ketiga mana pun.
"Android" adalah merek dagang Google LLC; "KernelSU", "Magisk" dan "APatch" adalah merek milik
penulis masing-masing. VDLU berjalan sepenuhnya di perangkat Anda dan di host rilis Anda sendiri.

## Tags

`VDLU` `flashless-update` `incremental-update` `KernelSU` `Magisk` `APatch` `module-update` `ed25519` `content-addressed` `OTA` `self-update` `Android` `VDLiveUpdate`
