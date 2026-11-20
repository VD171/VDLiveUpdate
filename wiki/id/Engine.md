# Engine

Engine adalah sisi perangkat dari VDLU: bagian yang berjalan di ponsel, memutuskan apa yang berubah, mengunduhnya, dan menerapkannya. Ia adalah satu skrip shell POSIX, `engine/update.sh`, ditambah pemeriksa signature mungil, `engine/vdlu-verify`. Keduanya di-vendor ke dalam modul host di `<module>/vdlu/` dan dijalankan oleh root.

Seluruh engine dibangun di sekitar satu ide: sebuah update adalah **transaksi yang resumable**. Jika ponsel di-reboot, dimatikan, atau kehilangan jaringan di tengah jalan, run berikutnya melanjutkan tepat di tempat ia berhenti, dan modul tidak pernah dibiarkan setengah diterapkan sambil berpura-pura selesai.

Jika Anda ingin gambaran besarnya dulu, lihat [[Architecture]]. Untuk bagaimana update menghindari reboot kapan pun bisa, lihat [[Reboot Handling]].

## Ditulis untuk perangkat, bukan untuk laptop Anda

`update.sh` murni POSIX `sh`. Ia berjalan di bawah mksh, busybox, atau toybox, tanpa fitur khusus bash, dan ia lolos `sh -n`. Itu penting karena lingkungan pada perangkat Android yang di-root itu kecil dan ketat.

Khususnya, tidak ada `jq`. VDLU mem-parse `manifest.json` dengan flattener kecil gaya gron yang ditulis dalam `awk`: ia menelusuri JSON satu karakter demi satu dan memancarkan satu baris `path<TAB>value` per daun (misalnya `files/0/sha256<TAB>ab..` atau `version<TAB>6`). Shell lalu membaca baris-baris itu dengan `grep` dan `cut`. Ini bekerja pada JSON yang ringkas maupun yang di-pretty-print, dan ia tidak pernah memanggil tool JSON yang tidak ada di sana.

Engine hanya bergantung pada apa yang sudah dibawa toybox (`sha256sum`, `gzip`/`gunzip`, `base64`, `date`), verifier `ed25519-mini` yang tertanam, dan, untuk feed `https://`, sebuah `curl` statis kecil yang diambil dan diverifikasi sekali. Feed `file://` tidak membutuhkan `curl` sama sekali.

## Enam perintah

Anda memanggil engine dengan path modul dalam environment dan satu perintah:

```sh
VDLU_DIR=/data/adb/<mod>/vdlu MODULE_DIR=/data/adb/modules/<mod> MODID=<mod> \
  sh "$MODULE_DIR/vdlu/update.sh" <cmd>
```

Exit code `0` berarti sukses; kode lain apa pun berarti error, dengan alasan dicetak ke stderr.

| Perintah | Yang dilakukannya |
|---|---|
| `check` | Diff read-only. Mengunduh manifest, membandingkannya dengan apa yang terpasang, dan mencetak ringkasan JSON satu baris: `{"update":bool,"from":N,"to":M,"fetch":K,"reboot":bool}`. Tidak mengubah apa pun di disk. Jika perangkat lebih baru dari feed (downgrade yang diblokir) ia melaporkan `{"update":false,"ahead":true,...}` dengan exit `0`, bukan error. |
| `run` | Siklus live penuh: DIFF, FETCH, APPLY, COMMIT. Menerapkan setiap file live segera dan men-stage sedikit file kelas reboot. Menghormati `cancel`. Menulis progres ke `journal.json`. |
| `resume` | Melanjutkan transaksi yang terinterupsi, mulai dari fase apa pun yang sedang dijalani. Idempoten. Ia **tidak** men-swap sebuah `.so` yang di-stage (itu disediakan untuk `boot`). |
| `boot` | Jalur pre-zygote. Melakukan `resume` lalu men-swap file `*.vdlu-new` yang di-stage ke tempatnya, menutup `PENDING_REBOOT` menjadi `DONE`. Jika tidak ada transaksi tertunda, ia menjalankan siklus baru dan menerapkan segalanya, termasuk `.so`, dalam satu boot itu. |
| `status` | Mencetak `journal.json`, atau `{"state":"idle"}` ketika tidak ada yang sedang berjalan. |
| `cancel` | Membuat marker `cancel`. Sebuah `run` yang sedang berjalan berhenti dengan rapi di titik aman berikutnya. |

Perintah `check` sengaja murah, sehingga UI dapat memberi tahu Anda bahwa sebuah update ada di jaringan apa pun. Download yang sesungguhnya di-gate terpisah (lihat fase fetch di bawah).

## Transaksi, langkah demi langkah

Setiap `run` bergerak melalui state machine tetap, dicatat dalam `journal.json` sehingga WebUI (dan Anda) dapat mengamatinya:

```
PLANNED -> FETCHING -> FETCHED -> APPLYING -> APPLIED_LIVE -> (PENDING_REBOOT | DONE)
```

**DIFF.** Engine mengambil `manifest.json`, memvalidasi setiap field (lihat di bawah dan [[Security and Trust Model]]), dan mendiff tree target yang ditandatangani terhadap `current.json`, manifest dari versi yang sudah terpasang. Hasilnya adalah plan per-file yang ditulis ke `plan.tsv`: satu baris per file, membawa class, hash target, mode, dan state progresnya. File yang sudah pada hash target ditandai untuk dilewati.

**FETCH.** Untuk setiap file yang masih dibutuhkan, engine mengunduh blob content-addressed-nya dari `<source>/blobs/<sha>` (atau `<sha>.gz` ketika terkompresi), ke dalam file `.part`. Jika blob di-gzip, ia didekompres, lalu SHA-256-nya diperiksa terhadap manifest. Hanya pada kecocokan ia secara atomik `mv` ke `blobs/<sha>`. Blob yang sudah di-cache dengan hash yang benar dilewati sepenuhnya, dan file lokal yang tidak berubah dapat men-seed cache tanpa download apa pun. Tiga kegagalan pada blob yang sama membatalkan fase tanpa apa pun yang diterapkan. Fase mencapai `FETCHED` hanya setelah setiap blob dalam plan hadir dan terverifikasi. Untuk [[Feed Format]] asal blob-blob ini, lihat halaman itu.

Fetch di-gate oleh kebijakan jaringan: sebuah feed dapat dibatasi ke Wi-Fi saja, mobile saja, atau jaringan apa pun. Ketika jaringan saat ini tidak diizinkan, fetch tidak gagal; ia memasuki state `DEFERRED` yang benign, mempertahankan plan dan target yang di-pin, dan dilanjutkan pada check atau boot berikutnya begitu jaringan yang tepat muncul. Tidak ada data yang dihabiskan sementara itu.

**APPLY.** Hanya pernah dimasuki dari `FETCHED`. Untuk setiap file engine bertindak per class:

- File `live` dan `soft`: backup file saat ini ke `rollback/<version>/<path>`, tulis konten baru ke sebuah sibling `.vdlu-tmp`, `chmod`, verifikasi hash-nya, lalu secara atomik `rename` di atas target. File yang sudah pada hash target dilewati.
- File `reboot` (sebuah `.so`, sebuah overlay `/system`, sebuah `sepolicy.rule`): dimaterialisasi ke dalam `staged/<path>.vdlu-new`. Inode live tidak pernah disentuh di sini. Lihat [[Reboot Handling]].
- penghapusan: backup, lalu hapus. Penghapusan hanya diterapkan di paling akhir, pada `DONE` yang bersih, tidak pernah selagi reboot masih tertunda.

**COMMIT.** Engine me-re-hash setiap file live dan soft yang disentuhnya. Hanya ketika semuanya cocok ia menulis `current.json`, menjadikan versi baru sebagai basis diff. Jika ada file kelas reboot yang di-stage, state menjadi `PENDING_REBOOT` alih-alih `DONE`; swap dan re-verify akhir terjadi kemudian di bawah perintah `boot`.

## Fail-safe by construction

Jaminan yang membuat ini aman dijalankan tanpa pengawasan:

- **Tidak ada yang ditandai `DONE` tanpa re-hash yang cocok.** `DONE` dicapai hanya setelah setiap file yang diterapkan dibaca kembali dan SHA-256-nya dibandingkan dengan manifest. File reboot yang di-stage memaksa `PENDING_REBOOT`, tidak pernah `DONE` palsu.
- **Tidak ada yang hilang.** Setiap file dibackup ke `rollback/<version>/` sebelum ditimpa, dan tiga versi terakhir disimpan. Jika sebuah apply gagal, file live di-revert dari backup; modul tidak pernah dibiarkan setengah diterapkan sambil berbohong tentangnya. `apply_live` membatalkan secara langsung jika langkah backup gagal, alih-alih menimpa tanpa jalan kembali.
- **Semuanya atomik.** Konten baru mendarat melalui `rename`/`mv` di atas target, jadi pembaca hanya pernah melihat file lama atau file baru, tidak pernah penulisan yang terpotong.
- **Resumable setelah crash atau kill.** Sebuah crash, jaringan yang hilang, atau reboot di tengah jalan meninggalkan journal yang valid; `resume` (atau `boot`) melanjutkan dari fase yang tercatat. Desain berasumsi ia akan terinterupsi.
- **Menurun dengan rapi.** Biner yang hilang, jaringan yang mati, atau disk penuh menghasilkan error yang jelas di stderr dan `state:ERROR` dalam journal, tanpa merusak modul.

## Lock

Hanya satu transaksi yang boleh menyentuh state pada satu waktu. `flock` tidak andal di toybox, jadi VDLU menyerialisasi dengan directory lock: `mkdir "$VDLU_DIR/lock.d"` berhasil untuk tepat satu pemanggil dan gagal untuk sisanya, yang atomik pada filesystem waras mana pun. Lock stale yang ditinggalkan proses mati dipulihkan dengan memeriksa PID yang tercatat.

Retry boot-time yang sabar (dipakai ketika perangkat offline saat boot) **tidak** memegang lock ini selagi menunggu. Ia mengambil dan melepas di antara percobaan, jadi `run` manual tidak pernah diblokir oleh boot yang menunggu jaringan, dan ia tidak pernah memegang wakelock. Hemat baterai by design. Lebih lanjut soal itu di [[Reboot Handling]].

## Pemeriksaan signature: `vdlu-verify`

`vdlu-verify` adalah pemeriksa signature di perangkat, dijaga sengaja ramping:

```
vdlu-verify <manifest.json> <keyring_dir>
```

Exit `0` berarti signature manifest valid terhadap public key keyring yang id-nya cocok dengan `key_id` manifest; kode lain apa pun adalah penolakan.

Yang membuatnya ramping adalah ia memakai **tanpa `openssl` di perangkat**. Ia membaca public key keyring sebagai file **raw 32-byte**, mengkanonikalisasi manifest (teks manifest dengan field `sig` dihilangkan), meng-hash-nya dengan toybox `sha256sum`, meng-base64-decode signature, dan menyerahkan raw key, message, dan signature 64-byte ke biner `ed25519-mini` yang tertanam. Pemeriksa juga menolak apa pun yang cacat sebelum ia pernah memverifikasi: `key_id` atau `sig` yang hilang atau kosong, `key_id` yang mengandung pemisah path, public key yang bukan tepat 32 byte, atau signature yang bukan tepat 64 byte.

Sebelum ia memilih key sama sekali, engine menegakkan sebuah **allowlist `key_id`**: `key_id` manifest harus merupakan key yang diizinkan config untuk menandatangani sebuah *update modul*, dan key yang sekadar ada di keyring tetapi tidak di-allowlist ditolak sebelum pubkey-nya pernah dimuat. Keyring satu-key otomatis mengunci satu key itu tanpa config; keyring banyak-key wajib mengunci `key_id` atau engine fail-closed. Himpunan yang diizinkan diteruskan ke `vdlu-verify` sebagai `VDLU_KEYID_ALLOW`, dan berlaku di kedua profil. Ini menghentikan sebuah key berkepercayaan-lebih-rendah, seperti key feed fingerprint yang berbagi keyring, dari menandatangani update root penuh; feed fingerprint yang terpisah mempertahankan key ter-pin-nya sendiri, `FEED_KEY_ID`. Cerita lengkapnya ada di [[Security and Trust Model]].

Kanonikalisasi itu byte demi byte identik dengan signer producer, yang itulah yang membuat sebuah signature terverifikasi lintas tool. Private key yang cocok tidak pernah menyentuh perangkat atau CI; hanya raw public key yang tertanam. Cerita trust lengkap, kedua profil, dan mengapa `hardened` fail-closed melalui inversi ada di [[Security and Trust Model]].

Engine memanggil `vdlu-verify` selama fase diff. Di bawah profil `hardened` verifikasi yang gagal membatalkan seluruh update; di bawah `trusted` verifikasi bersifat best-effort, tetapi hash setiap blob tetap selalu diperiksa, jadi konten yang rusak tertangkap terlepas dari profil.

## State di disk

Semua state engine hidup dalam `$VDLU_DIR` (di luar direktori modul), jadi tree modul itu sendiri hanya pernah menyimpan file yang sudah jadi:

| Path | Peran |
|---|---|
| `config` | setting key=value (source, profile, channel, kebijakan jaringan, boot retry) |
| `current.json` | manifest dari versi aktif; ini adalah basis diff. Absen berarti tidak pernah diupdate |
| `target.json` | manifest yang di-pin dari transaksi yang sedang berjalan. Kehadirannya menandai transaksi aktif; ia menjadi `current.json` pada `DONE` |
| `plan.tsv` / `plan.del` | plan per-file dan progres, dan daftar path untuk dihapus |
| `journal.json` | progres untuk WebUI, ditulis ulang pada setiap perubahan state |
| `blobs/<sha256>` | cache konten asli yang terverifikasi dan terdekompres |
| `rollback/<version>/<path>` | backup file yang ditimpa; tiga versi terakhir disimpan |
| `staged/<path>.vdlu-new` | file kelas reboot yang menunggu swap saat boot |
| `lock.d/` | mkdir lock |
| `tools/<abi>/curl` | curl statis yang diambil dan terverifikasi; bertahan lintas update |
| `cancel` | sebuah permintaan cancel |

## Lihat juga

- [[Reboot Handling]]: bagaimana sistem class menjaga sebagian besar update tetap bebas reboot, dan bagaimana sebuah `.so` yang di-stage di-swap pre-zygote.
- [[Security and Trust Model]]: kedua profil, validasi fail-closed, dan rantai ed25519 raw-key.
- [[Feed Format]]: manifest dan blob content-addressed yang dikonsumsi engine.
- [[Architecture]]: bagaimana engine, producer, dan WebUI berpadu.
