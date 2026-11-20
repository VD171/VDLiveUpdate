# VDLiveUpdate (VDLU)

**VDLU adalah engine self-update inkremental tanpa flash untuk modul KernelSU / APatch / Magisk: modul yang sudah terpasang memperbarui file-nya sendiri melalui feed yang ditandatangani, mengambil hanya apa yang berubah dan menerapkan sebagian besar di antaranya tanpa reboot.**

Update modul biasa mengirim seluruh `.zip` lagi, jadi beberapa baris yang berubah menghabiskan biaya re-download penuh, dan manifest update statis hanya dapat menunjuk ke satu `zipUrl` (satu flavor untuk setiap perangkat). VDLU menempuh jalur berbeda: ia mendiff tree yang benar-benar terpasang terhadap feed yang ditandatangani dan content-addressed, mengunduh hanya delta-nya, dan menuliskannya di tempat. Instalasi full arm64 tetap full arm64, instalasi lite tetap lite, dan modul tidak pernah di-flash ulang.

VDLU dimaksudkan untuk **di-vendor** ke dalam sebuah modul, diletakkan di `<module>/vdlu/`. Ia bukan modul tersendiri.

## Tujuan

- **Self-update tanpa flash.** Memperbarui modul yang terpasang di tempat, over the air, tanpa root manager, tanpa re-flash `.zip`, dan tanpa kehilangan flavor yang terpasang.
- **Inkremental berdasarkan konten.** Mentransfer hanya blob yang kontennya berubah. Feed yang content-addressed (`manifest.json` + `blobs/<sha256>`) berarti file yang tidak berubah atau yang di-revert tidak pernah diambil ulang.
- **Bebas reboot bila aman.** Menerapkan file biasa secara live, langsung. Menyimpan staged reboot hanya untuk sedikit file yang benar-benar membutuhkannya (sebuah `.so`, sebuah overlay `/system`, sebuah `sepolicy.rule`).
- **Ramping di perangkat.** Murni POSIX `sh`, tanpa `jq`, tanpa `bash`, tanpa `openssl` di perangkat. Verifikasi bergantung pada `ed25519-mini` yang tertanam; satu-satunya biner yang diambil adalah `curl` statis, dipakai hanya untuk feed `https`.
- **Fail-closed dan jujur.** Setiap field manifest diperlakukan sebagai input yang bermusuhan dan divalidasi sebelum apa pun diunduh. Tidak ada yang pernah dilaporkan "done" kecuali re-hash membuktikannya, dan tidak ada yang ditimpa tanpa backup terlebih dahulu.

## Keistimewaan

Yang membuat VDLU berbeda dari klien OTA biasa:

- **Tanpa flash dan inkremental.** Diff / fetch / apply yang content-addressed dengan dedup: perangkat menghitung delta terhadap feed yang ditandatangani dan hanya menarik blob yang hilang.
- **Bebas reboot bila mungkin.** File biasa diterapkan secara live; hanya file `.so`, overlay `/system`, dan `sepolicy.rule` yang di-stage dan di-swap pada satu reboot. Lihat [[Reboot Handling]].
- **POSIX `sh` di perangkat.** Berjalan di bawah toybox / busybox / mksh. Tanpa `jq` (sebuah flattener `awk` gaya `gron` mem-parse JSON), tanpa `bash`isme, tanpa runtime berat.
- **Verifikasi ramping.** Sebuah `ed25519-mini` yang tertanam memverifikasi signature. **Tidak ada `openssl` di perangkat**; private key tidak pernah menyentuh perangkat atau CI.
- **Keamanan fail-closed.** `validate_plan()` menolak **seluruh** manifest pada field buruk apa pun (path absolut atau `..`, sebuah `sha256` yang bukan 64 karakter hex, mode / class / encoding yang tidak valid). Dua profil, `trusted` dan `hardened`, dengan `hardened` fail-closed melalui inversi. Lihat [[Security and Trust Model]].
- **Resumable dan atomik.** Sebuah journal membuat setiap transaksi aman terhadap crash; penulisan memakai `rename` / `mv`; backup diambil sebelum setiap penimpaan sehingga apply yang gagal di-rollback alih-alih merusak modul.

## Mulai dari sini

| Jika Anda ingin... | Buka |
|---|---|
| Mengadopsi VDLU ke dalam modul Anda, langkah demi langkah | [[Quick Start]] |
| Memahami keseluruhan sistem sekilas | [[Architecture]] |
| Mempelajari engine sisi perangkat (`update.sh`) | [[Engine]] |
| Membangun dan menandatangani feed di PC Anda | [[Producer]] |
| Memasang panel Updates | [[WebUI]] |
| Membaca trust model dan postur ancaman | [[Security and Trust Model]] |
| Melihat tata letak manifest dan blob | [[Feed Format]] |
| Mengetahui apa yang di-reboot dan mengapa | [[Reboot Handling]] |
| Mengajukan pertanyaan umum | [[FAQ]] |
| Berkontribusi | [[Contributing]] |

## Tautan proyek

- **Source:** https://github.com/VD171/VDLiveUpdate
- **Channel (updates):** @Priv8_VD https://t.me/Priv8_VD

VDLiveUpdate adalah proyek independen dan tidak resmi. "Android" adalah merek dagang Google LLC; "KernelSU", "Magisk", dan "APatch" adalah merek dari para penulisnya masing-masing. VDLU berjalan sepenuhnya di perangkat Anda dan di release host Anda sendiri.
