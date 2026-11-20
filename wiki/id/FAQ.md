# FAQ

Jawaban singkat untuk pertanyaan yang paling sering muncul. Masing-masing menautkan ke halaman dengan
cerita lengkapnya.

## Apa arti "flashless"? Apakah saya tetap flash pertama kali?

Ya, Anda flash sekali. Modul dipasang dengan cara biasa (flash zip di
root manager Anda). "Flashless" mendeskripsikan setiap update setelah itu: VDLU mengambil
hanya file yang berubah dan menerapkannya di tempat, jadi Anda tidak pernah mem-flash ulang
zip penuh hanya untuk mengirim beberapa baris yang berubah. Lihat [[Architecture]].

## Apakah sebuah update membutuhkan reboot?

Biasanya tidak. Sebagian besar file (WebUI Anda, biner, library, config, `module.prop`)
adalah class **live** dan diterapkan secara atomik tanpa reboot. Hanya file kelas reboot
(sebuah `.so` di bawah `zygisk/`, sebuah overlay `/system/**`, sebuah file sepolicy `*.rule`) yang
**di-stage** dan di-swap masuk pada boot berikutnya, karena proses yang berjalan telah
memetakan inode live. Ketika itu terjadi WebUI menampilkan banner "reboot to
activate" yang persisten. Lihat [[Reboot Handling]].

## Apakah aman jika feed di-MITM atau diracuni?

Ya, pada feed `hardened`. Setiap field manifest diperlakukan sebagai input yang bermusuhan.
Manifest harus membawa signature ed25519 yang valid atas bentuk kanoniknya, dan
`validate_plan()` berjalan fail-closed **sebelum download apa pun**: ia menolak seluruh
manifest pada path absolut atau `..`, sebuah `sha256` yang bukan 64 karakter hex,
atau mode, class atau encoding yang tidak valid. Manifest juga terikat ke id modul
Anda, jadi feed yang ditandatangani valid untuk modul berbeda tidak dapat disajikan sebagai gantinya.
`sha256` setiap blob diverifikasi setelah download terlepas dari profil. Lihat
[[Security and Trust Model]].

## Apa yang dibutuhkannya di perangkat (dependensi)?

Sangat sedikit. Murni POSIX sh (mksh / busybox / toybox) ditambah `sha256sum`,
`gzip`, `base64` dan `date` toybox; verifier `ed25519-mini` yang tertanam; dan, hanya untuk
sumber `https`, sebuah `curl` statis yang diambil sekali dan di-cache di Tier-2.
Sumber `file://` tidak membutuhkan curl sama sekali. **Tidak ada dependensi pada `jq`**:
engine mem-parse JSON dengan flattener gaya gron yang ditulis dalam `awk`. Lihat [[Engine]].

## Apakah openssl dibutuhkan di perangkat?

Tidak. `openssl` dipakai hanya di sisi PC/release (`vdlu-keygen`, `vdlu-sign`).
Di perangkat, verifikasi signature memakai biner `ed25519-mini` yang tertanam dan ramping,
yang membaca RAW 32-byte public key. Lihat [[Producer]] dan
[[Security and Trust Model]].

## Bagaimana saya merotasi signing key?

Buat keypair baru dengan `vdlu-keygen`, tambahkan RAW 32-byte public key baru ke
keyring perangkat di samping yang sebelumnya, dan mulai menandatangani dengan `key_id`
baru. Perangkat memilih `<keyring>/<key_id>.pub` berdasarkan `key_id` manifest,
jadi tidak ada perubahan engine yang dibutuhkan. Mengirim baik public key saat ini maupun sebelumnya
berarti key yang dirotasi tidak pernah mem-brick instalasi lama. Karena sebuah rotasi meninggalkan lebih dari satu key di keyring, Anda juga harus mengunci key mana yang boleh menandatangani update modul: setel config `key_id` (dipisah koma selama jendela rotasi). Keyring satu-key otomatis mengunci dan tidak butuh config. Lihat [[Security and Trust Model]].

## hardened vs trusted - mana yang saya pakai?

Gunakan `hardened` untuk feed publik apa pun (disajikan melalui `https`, misalnya GitHub Pages).
Ia membuat signature wajib dan memblokir downgrade. Gunakan `trusted` hanya untuk
sumber `file://` atau SSH-staged privat yang sudah Anda kontrol, di mana signature
best-effort (hash setiap blob tetap diperiksa). Jika ragu, gunakan `hardened`:
ia adalah default fail-closed, dan nilai non-`trusted` apa pun diperlakukan sebagai
`hardened`. Lihat [[Security and Trust Model]].

## Bagaimana jika sebuah blob diutak-atik atau manifest cacat?

Update dibatalkan dan tidak ada yang diterapkan. Manifest yang cacat ditolak utuh
oleh `validate_plan()` sebelum fetch apa pun. Blob yang sha256-nya tidak cocok dengan
manifest ditolak; tiga kegagalan pada blob yang sama membatalkan fase fetch dengan
tidak ada yang diterapkan. Pada kegagalan keras apa pun journal mencatat `ERROR` dan modul
dibiarkan utuh. Lihat [[Engine]].

## Bisakah sebuah update menghapus file saya atau mem-brick perangkat?

Risiko dibendung by design. File yang ditimpa dan dihapus pertama-tama dibackup
ke `rollback/<version>/`, dan `apply` dibatalkan alih-alih menimpa tanpa
backup yang sukses. Delete berjalan hanya ketika sebuah transaksi mencapai `DONE`, tidak pernah
selagi reboot masih tertunda. Apply yang gagal me-revert file live yang sudah
ditulisnya. Path divalidasi untuk containment di dalam direktori modul sebelum dipakai,
jadi sebuah manifest tidak dapat menulis atau menghapus di luar tree. Lihat [[Engine]] dan
[[Security and Trust Model]].

## Apakah ia bekerja di KernelSU DAN Magisk DAN APatch?

Ya. VDLU adalah POSIX sh biasa ditambah WebUI, di-vendor ke dalam modul, jadi ia berjalan di
KernelSU, APatch dan Magisk sama saja. Ia memakai bridge WebUI root manager
(`ksu.exec`) untuk menggerakkan engine dan mem-poll progres. Lihat [[Architecture]] dan
[[WebUI]].

## Seberapa besar footprint di perangkat?

Kecil. Engine adalah skrip; satu-satunya biner adalah verifier `ed25519-mini`
per-ABI (mungil) dan, untuk sumber `https`, sebuah `curl` statis (~1MB) yang
diambil sekali dan di-cache. Modul yang sudah membundel `curl`-nya sendiri memakainya ulang
dan tidak menambahkan download sama sekali. Blob cache Tier-2 menyimpan konten terverifikasi ditambah
3 versi rollback terakhir. Lihat [[Engine]] dan [[Architecture]].
