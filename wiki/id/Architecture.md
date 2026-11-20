# Architecture

VDLU memiliki dua sisi yang disatukan oleh satu hal di tengah. Di PC, [[Producer]] mengubah tree modul menjadi feed yang ditandatangani dan content-addressed. Di perangkat, [[Engine]] membaca feed itu, mencari tahu apa yang berubah, dan menerapkannya. Jahitan di antara keduanya adalah **manifest yang ditandatangani ditambah blob store** (lihat [[Feed Format]]). Tidak ada hal lain yang melintasi celah itu.

```
        PC / release host                                device
  +--------------------------+                 +---------------------------+
  |  Producer                |                 |  Engine  (update.sh)      |
  |  vdlu-pack  -> manifest  |    signed       |  POSIX sh, no jq          |
  |  vdlu-sign  -> sig       |    feed         |  DIFF FETCH APPLY COMMIT  |
  |  vdlu-gc    -> prune     | =============>  |  journal + rollback       |
  +--------------------------+   manifest.json |  ed25519-mini verify      |
                                 blobs/<sha>   +-------------+-------------+
                                                             |
                                                       +-----v------+
                                                       |  WebUI     |
                                                       |  Updates   |
                                                       |  panel     |
                                                       +------------+
```

Kedua sisi tidak pernah berbagi runtime. Producer memakai `python3` dan `openssl`; Engine murni POSIX `sh` dengan toybox dan `ed25519-mini` yang tertanam. Keduanya sepakat hanya karena keduanya menurunkan **byte kanonik yang sama** dari sebuah manifest (lihat [[Security and Trust Model]]). WebUI adalah panel vanilla-JS yang tipis yang menggerakkan engine melalui bridge root-manager dan membaca journal progresnya; ia tidak memiliki logika update sendiri. Lihat [[WebUI]].

## Kedua sisi

| Sisi | Berjalan di | Dibangun dari | Tugas |
|---|---|---|---|
| [[Producer]] | PC / CI | `python3` + `sh` + `openssl` | Menelusuri tree modul menjadi `manifest.json` + `blobs/`, menandatanganinya, membersihkan orphan |
| [[Engine]] | perangkat | POSIX `sh` + toybox + `ed25519-mini` | Mendiff tree yang terpasang terhadap feed, mengambil delta, menerapkan, commit |
| [[WebUI]] | perangkat (webview) | vanilla JS/CSS | Memicu update, menampilkan progres, mengedit config, menampilkan banner reboot |

## Pipeline update

Setiap update adalah satu transaksi, dijalankan dalam urutan tetap:

```
  DIFF  ------>  FETCH  ------>  APPLY  ------>  COMMIT
  read feed      download        write live     re-hash all,
  + validate     only missing    files now,      promote target
  + plan         blobs, verify   stage reboot     -> current,
  (no changes)   each sha256     ones             DONE or
                                                  PENDING_REBOOT
```

- **DIFF** (`update.sh check` adalah fase ini, read-only). Engine mengunduh hanya manifest, menjalankan `validate_plan()` atas setiap field **sebelum** menyentuh apa pun, lalu membandingkan feed terhadap `current.json` untuk membangun plan per-file. Ia tidak mengubah apa pun di disk. Perangkat yang lebih maju dari feed adalah hasil "ahead" yang benign, bukan error.
- **FETCH.** Mengunduh hanya blob yang hilang dari plan, ke dalam `<sha>.part`, mendekompres `gz`, memeriksa `sha256sum` terhadap manifest, dan secara atomik `mv` setiap blob yang terverifikasi ke dalam cache. Blob yang sudah di-cache (atau di-seed dari file lokal yang tidak berubah) dilewati, jadi sebuah revert atau file bersama tidak menghabiskan biaya apa pun. Tiga kegagalan pada satu blob membatalkan fase tanpa menerapkan apa pun. Download yang diblokir oleh kebijakan jaringan keluar sebagai `DEFERRED` (resumable), bukan error.
- **APPLY.** File biasa (`live` / `soft`) dituliskan sekarang: backup ke `rollback/<v>/`, tulis sebuah `.vdlu-tmp`, `chmod`, verifikasi, lalu `rename` atomik di atas target. File kelas reboot dimaterialisasi ke dalam `staged/<path>.vdlu-new` dan inode live dibiarkan tak tersentuh. Entri `delete[]` dibackup, lalu dihapus. Setiap langkah idempoten: file yang sudah pada hash target dilewati.
- **COMMIT.** Me-re-hash setiap file live; hanya jika semuanya cocok engine mempromosikan `target.json` menjadi `current.json`. Jika ada yang di-stage, transaksi berakhir dalam `PENDING_REBOOT`; selain itu `DONE`.

## Manifest dan blob yang content-addressed

Feed itu content-addressed: manifest mendaftar tree target **lengkap**, setiap file dibawa oleh `sha256`-nya, dan blob store menyimpan satu salinan dari setiap konten berbeda di bawah `blobs/<sha256>` (atau `blobs/<sha256>.gz`).

- **Dedup.** Konten identik di mana pun dalam tree, atau lintas rilis, adalah satu blob. Publikasi bersifat inkremental: sebuah blob yang `sha256`-nya sudah ada di host tidak pernah di-push ulang, dan perangkat tidak pernah mengambil ulang konten yang sudah dimilikinya.
- **sha256 adalah dari yang asli.** Hash selalu menamai konten yang tidak terkompresi; `enc` (`raw` atau `gz`) hanya mencatat bagaimana satu blob itu kebetulan disimpan. Perangkat mendekompres `gz` dengan toybox `gunzip`, jadi tidak ada kompresor tambahan yang dibundel.
- **Stabil terhadap flavor.** Karena perangkat mendiff terhadap apa yang benar-benar terpasang, feed dapat membawa seluruh keluarga modul; setiap instalasi hanya menarik blob yang melengkapi flavornya sendiri.

Tata letak field demi field yang lengkap ada di [[Feed Format]].

## Journal yang resumable

Setiap transaksi aman terhadap crash karena progresnya hidup dalam sebuah journal (`journal.json`), dan target yang di-pin dari transaksi yang sedang berjalan hidup dalam `target.json`. State machine berjalan dalam urutan tetap:

```
PLANNED -> FETCHING -> FETCHED -> APPLYING -> APPLIED_LIVE -> ( PENDING_REBOOT | DONE )
                                                               \-> ERROR / DEFERRED
```

| State | Arti |
|---|---|
| `PLANNED` | Plan dibangun, belum ada yang diambil |
| `FETCHING` / `FETCHED` | Mengunduh blob / semua blob hadir dan terverifikasi |
| `APPLYING` / `APPLIED_LIVE` | Menulis file / semua file live tertulis |
| `PENDING_REBOOT` | Sebuah file kelas reboot di-stage, menunggu swap saat boot |
| `DONE` | Re-hash atas segalanya cocok; `current.json` dipromosikan |
| `ERROR` | Kegagalan keras; modul dibiarkan tidak rusak, file live di-revert dari `rollback/` |
| `DEFERRED` | Download ditahan oleh kebijakan jaringan; plan bertahan, dilanjutkan nanti |

`DONE` dicapai **hanya** setelah re-hash atas segalanya cocok, jadi journal tidak pernah mengklaim bahwa update yang setengah diterapkan telah selesai. Sebuah crash, jaringan putus, atau reboot di tengah jalan meninggalkan journal yang resumable; `update.sh resume` (atau `boot`) melanjutkan dari fase saat ini. Lihat [[Engine]] untuk kumpulan perintah dan file state di perangkat.

## Atomicity dan rollback

Tidak ada yang pernah ditimpa di tempat dan tidak ada yang hilang:

- **Penulisan atomik.** Setiap file mendarat melalui temp (`.vdlu-tmp`) dan `rename` / `mv` atomik, jadi pembaca tidak pernah melihat file yang tertulis setengah.
- **Backup sebelum penimpaan.** Konten sebelumnya pergi ke `rollback/<version>/<path>` sebelum file baru di-rename di atasnya (beberapa versi terakhir disimpan). Jika sebuah apply gagal, file live di-revert dari salinan rollback alih-alih dibiarkan rusak. Backup yang gagal **membatalkan** apply alih-alih menimpa tanpa jaring pengaman.
- **Terserialisasi.** Sebuah lock berbasis `mkdir` (`lock.d/`, karena `flock` tidak bisa dipakai di toybox, dengan pemulihan stale lewat PID) menyerialisasi run yang bersamaan.

## Prinsip bebas reboot

Sebagian besar file dapat di-swap selagi modul live, jadi VDLU menerapkannya segera. Hanya tiga kelas yang membutuhkan reboot, karena proses live telah memetakannya: sebuah `.so` (dimuat oleh Zygisk), sebuah overlay `/system`, dan sebuah `sepolicy.rule`. Itu semua **di-stage, tidak pernah dituliskan di atas inode live**, dan di-swap dalam satu langkah pre-zygote pada boot berikutnya. Taksonomi lengkap dan alur boot ada di [[Reboot Handling]].

## Postur trust fail-closed

Feed adalah satu-satunya hal yang menyeberang dari PC ke perangkat, jadi engine memperlakukan setiap byte darinya sebagai bermusuhan. `validate_plan()` berjalan pada fase DIFF, sebelum download apa pun, dan menolak seluruh manifest pada field yang cacat apa pun. Verifikasi signature memakai `ed25519-mini` yang tertanam (tanpa `openssl` di perangkat), private key tidak pernah menyentuh perangkat atau CI, dan profil `hardened` fail-closed melalui inversi sehingga nilai profil yang rusak tidak pernah bisa diam-diam menerima feed yang tidak ditandatangani. Model lengkap, kedua profil, dan ancaman yang masing-masing dijawab ada di [[Security and Trust Model]].
