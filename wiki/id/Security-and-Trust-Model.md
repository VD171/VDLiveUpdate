# Security and Trust Model

VDLU memperbarui modul di tempat, melalui jaringan, sebagai root. Itu kekuatan besar yang diarahkan pada file yang berasal dari sebuah feed, jadi seluruh engine dibangun di atas satu asumsi tunggal:

> **Setiap field dalam manifest adalah input yang bermusuhan.**

Sebuah feed dapat diracuni di sumbernya, atau di-swap dan dikacaukan dalam transit oleh MITM. Ketika itu terjadi manifest tetap tiba terlihat seperti manifest: ia membawa path file, string `sha256`, daftar `delete[]`, mode, class dan flag encoding. VDLU memperlakukan tidak satu pun dari itu sebagai tepercaya. Ia memvalidasi seluruh plan sebelum ia mengunduh satu byte pun, dan ia tidak pernah membiarkan nilai manifest mencapai shell.

Halaman ini adalah cerita trust lengkap. Lihat [[Feed Format]] untuk skema manifest yang divalidasinya, dan [[Engine]] untuk di mana pemeriksaan ini duduk dalam transaksi DIFF -> FETCH -> APPLY -> COMMIT.

---

## Ide inti: fail-closed, sebelum apa pun terjadi

`validate_plan()` berjalan di dalam fase `check`/diff, **sebelum** fetch apa pun dan **sebelum** apply apa pun. Ia menelusuri setiap entri dalam tree file yang direncanakan dan setiap entri dalam `delete[]`, dan jika satu entri tunggal mana pun cacat ia **menolak seluruh manifest** dan transaksi tidak pernah dimulai. Tidak ada penerimaan parsial, tidak ada "lewati yang buruk dan terapkan sisanya". Satu field buruk meracuni batch, dengan sengaja.

Sebuah manifest diterima hanya jika **semua** hal ini berlaku untuk **setiap** entri:

| Field | Aturan | Mengapa |
|---|---|---|
| `path` | tidak absolut, tanpa komponen `..`, tanpa komponen `.`, tanpa `./` di awal, tanpa `/./` tertanam, tanpa slash di akhir, tanpa karakter kontrol (tab / newline) | sebuah path harus tetap di dalam `MODULE_DIR`; path absolut atau `..` berarti write-anywhere |
| `sha256` | cocok `^[0-9a-f]{64}$` persis | sha non-hex jika tidak akan diinterpolasi ke dalam path shell; ia adalah content address, jadi ia harus digest hex murni dan tidak lebih |
| `mode` | oktal saja (`[0-7]`) | string mode menjadi argumen `chmod` |
| `size` | digit saja, dan `<=` plafon ukuran engine | membatasi download dan dekompresi |
| `class` | persis `live`, `soft` atau `reboot` | class memutuskan apakah file diterapkan live atau di-stage untuk reboot |
| `enc` | persis `raw` atau `gz` | encoding memutuskan apakah blob di-gunzip |
| entri `delete[]` | aturan path yang sama seperti di atas | entri `delete[]` menggerakkan sebuah penghapusan; `..` yang tidak diperiksa akan menjadi `rm` di luar tree |

Karena ini berjalan lebih dulu, manifest yang diracuni tidak pernah dapat menulis di luar modul, tidak pernah menghapus di luar modul, dan tidak pernah menyuntikkan token non-hex ke dalam command line.

### Nilai manifest tidak pernah menyentuh shell

Paruh kedua aturan: bahkan setelah sebuah nilai lolos validasi, ia tidak pernah diinterpolasi ke dalam `sh`, dan tidak pernah diumpankan ke `awk system()`. Perintah check sengaja ditulis ulang agar tidak mengandung panggilan `system()`. Content addressing melakukan sisa pekerjaan: sebuah blob diambil berdasarkan `sha256`-nya, ditulis ke path cache yang dinamai oleh `sha256` yang sama itu, dan byte yang diunduh di-re-hash dan dibandingkan sebelum apa pun diterapkan. Sebuah nilai yang bukan digest 64-hex bersih tidak pernah sampai sejauh itu, karena `validate_plan()` sudah menolaknya.

### Garis pertahanan kedua pada saat apply

`validate_plan()` memblokir `..` secara **leksikal**, tetapi symlink yang sudah ada di dalam tree masih bisa mengalihkan penulisan. Jadi pada saat apply `contained()` me-resolve path target nyata dan memastikan ia duduk di bawah base modul, fail-closed ketika ia tidak dapat me-resolve. Penulisan bersifat atomik (tulis ke nama temp, lalu `rename` di atas target) dan setiap penimpaan dibackup ke `rollback/` terlebih dahulu; backup yang gagal membatalkan apply alih-alih menimpa tanpa jaring pengaman.

---

## Kedua profil

VDLU berjalan dalam salah satu dari dua profil trust, diatur oleh `profile=` dalam config.

### `hardened` (default publik)

- **Signature wajib.** Manifest harus membawa signature ed25519 yang valid dari sebuah key dalam keyring di perangkat, atau transaksi dibatalkan.
- **Downgrade diblokir.** Sebuah manifest yang `version`-nya lebih rendah dari versi yang terpasang ditolak. Penyerang tidak dapat memutar Anda kembali ke build yang diketahui-rentan.
- Ini adalah profil untuk modul apa pun yang didistribusikan ke publik melalui `https://`.

### `trusted` (privat, sumber SSH-staged)

- Verifikasi signature bersifat **best-effort**: sumbernya adalah feed `file://` privat atau SSH-staged yang Anda kontrol, jadi signature yang hilang atau tak terverifikasi tidak memaksa-batalkan.
- **Tetapi `sha256` setiap blob tetap diperiksa, selalu.** `trusted` melonggarkan *siapa yang menandatangani manifest*, tidak pernah *apakah byte cocok dengan plan*. Integritas konten tidak dapat ditawar dalam kedua profil.

---

## Fail-closed melalui inversi

Ini adalah bagian yang halus, dan ia adalah bagian yang paling sering salah dilakukan sebagian besar sistem.

`trusted` adalah **satu-satunya** string yang memilih verifikasi yang dilonggarkan. Engine tidak menguji "apakah ini `hardened`?" Ia menguji "apakah ini **bukan** `trusted`?":

```sh
prof=$(cfg profile hardened | tr -d '[:space:]')
...
if [ "$prof" != trusted ]; then
    # signature mandatory
fi
```

Jadi **apa pun** selain literal `trusted` di-resolve ke perilaku hardened:

- baris hilang sepenuhnya -> hardened
- salah ketik seperti `hardend` -> hardened
- `trusted ` dengan spasi di akhir, atau `\r` dari CRLF -> hardened
- `Trusted` dengan huruf besar yang salah -> hardened
- nilai yang dikacaukan MITM -> hardened

Versi lebih awal men-default sebuah baris yang *hilang* ke hardened, yang masih meninggalkan *nilai* yang rusak jatuh ke jalur open. Itu adalah fail-open: string profil yang dikacaukan dapat diam-diam menerima manifest tak-bertanda-tangan, dan manifest tak-bertanda-tangan berarti sebuah `.so` yang dipasok penyerang di-swap masuk di bawah MITM, yang itu adalah remote code execution tingkat root. Inversi menutupnya. Satu-satunya cara mendapatkan verifikasi yang dilonggarkan adalah mengeja `trusted` persis, dan bahkan saat itu hash blob diperiksa. Engine tidak pernah satu salah-ketik dari menerima kode tak-bertanda-tangan. (`tr -d` membersihkan whitespace liar sehingga `trusted` yang sah dengan spasi yang berantakan tidak keliru ditolak, tanpa membuka kembali lubangnya.)

**Pengujian ini load-bearing. Ia harus tetap `!= trusted` dan tidak pernah menjadi `== hardened`.**

---

## Manifest terikat ke modul

Satu release key menandatangani banyak modul. Jadi sebuah manifest yang ditandatangani secara valid, untuk modul *lain*, pada prinsipnya dapat disajikan ke yang ini (misconfiguration feed, source swap, atau redirect MITM) dan signature-nya akan lolos.

VDLU menutup ini dengan sebuah bind: field `module` yang ditandatangani di dalam manifest harus sama dengan `MODID` instalasi ini, atau manifest ditolak sebagai feed lintas-modul. Karena `module` ada di dalam bentuk kanonik yang ditandatangani, penyerang tidak dapat mengubahnya tanpa merusak signature. Sebuah feed yang ditandatangani valid untuk modul B sama sekali tidak dapat diterapkan ke modul A.

---

## Verifier di perangkat yang ramping

Verifikasi di perangkat memakai **ed25519-mini**, pemeriksa verify-only mungil yang dibangun di atas TweetNaCl (public domain). **Tidak ada `openssl` di perangkat.**

- Entri keyring adalah **raw 32-byte public key**, disimpan sebagai `keyring/<key_id>.pub`. (PEM public key adalah artifact sisi PC saja; menyalin PEM ke keyring perangkat merusak verifikasi, karena verifier mengharapkan tepat 32 raw byte.)
- `vdlu-verify <manifest.json> <keyring_dir>` merekonstruksi bentuk kanonik (teks manifest dengan field `sig` dihilangkan, compact, key terurut), meng-hash-nya ke message hex 64-karakter yang dicakup signature, mendekode signature base64, memeriksa ia 64 byte, dan menanyakan `ed25519-mini <pub32> <msg> <sig64>` untuk sebuah verdict. rc 0 = valid, selain itu = tolak.
- Biner bersifat static per ABI (arm64-v8a, armeabi-v7a, x86, x86_64), dengan sebuah `PROVENANCE.json` yang memaku source TweetNaCl persis, hash wrapper dan build flag, sehingga hal yang berjalan sebagai root dapat diaudit.
- `key_id` dari manifest itu sendiri disanitasi (tanpa `/`, tanpa `..`, tanpa quote) sebelum ia dipakai untuk memilih file keyring, sehingga ia tidak dapat melarikan diri dari direktori keyring.

### Keyring bersifat flash-only, verify-not-copy, stabil

Keyring dikirim di dalam modul pada saat flash dan tidak ditulis ulang oleh engine update. Pada re-vendor aturannya adalah **verify, jangan copy**: keyring berubah hanya pada rotasi key yang disengaja, tidak pernah sebagai efek samping dari sebuah update.

### Rotasi key tidak mem-brick instalasi lama

Ketika sebuah signing key dirotasi, keyring mengirim **baik raw public key saat ini maupun yang sebelumnya**. Verifier memilih file key berdasarkan `key_id` manifest, jadi feed yang masih ditandatangani oleh key lama terverifikasi terhadap pubkey lama, dan feed yang ditandatangani oleh key baru terverifikasi terhadap yang baru. Perangkat yang belum update melewati rotasi tetap berjalan; tidak ada yang terdampar.

---

## Apa yang ditutup tools-manifest

Bootstrap fetch yang ramping mengunduh `curl` statis pada penggunaan pertama untuk modul yang tidak mengirim `curl`-nya sendiri. Karena biner itu berjalan sebagai root, signature manifest-nya sendiri (ed25519-mini) dan hash-nya **wajib dalam profil apa pun**, termasuk `trusted`, sebelum ia pernah dipasang atau dieksekusi. Webview hanyalah transport; trust datang dari pemeriksaan signature dan hash di perangkat, tidak pernah dari fakta bahwa sebuah download berhasil.

---

## Apa yang TIDAK DAPAT dilakukan penyerang

Bahkan dengan memiliki feed, atau duduk di kabel sebagai MITM penuh, penyerang tidak dapat:

- **Menulis di luar modul.** Path absolut, `..`, `.`, karakter kontrol dan slash di akhir semuanya ditolak sebelum apply apa pun, dan pengalihan symlink tertangkap lagi pada saat apply.
- **Menghapus di luar modul.** Entri `delete[]` lolos validasi path yang sama.
- **Menyuntikkan perintah.** Tidak ada nilai manifest yang diinterpolasi ke dalam shell atau `awk system()`; `sha256` harus 64-hex murni atau seluruh manifest ditolak.
- **Mengirim kode tak-bertanda-tangan ke instalasi publik.** `hardened` membuat signature wajib, dan profil fail-closed melalui inversi, jadi tidak ada salah ketik atau nilai yang dikacaukan yang men-downgrade itu.
- **Menyajikan feed yang ditandatangani milik modul lain di sini.** Field `module` yang ditandatangani harus sama dengan `MODID` ini.
- **Memutar Anda kembali.** Downgrade diblokir dalam `hardened`.
- **Merusak sebuah blob tanpa terdeteksi.** Setiap blob yang diunduh di-re-hash terhadap `sha256` manifest dalam kedua profil; ketidakcocokan setelah tiga percobaan membatalkan fase tanpa apa pun yang diterapkan.
- **Men-swap masuk fetcher root palsu.** `curl` yang di-bootstrap diperiksa signature dan hash-nya sebelum ia dipasang atau dijalankan, dalam setiap profil.
- **Setengah-menerapkan update yang rusak.** Transaksi hanya mencapai `DONE` ketika re-hash atas segalanya cocok; apply yang gagal di-rollback alih-alih menimpa tanpa backup.

---

Lihat juga: [[Feed Format]] untuk skema manifest, [[Engine]] untuk transaksi tempat pemeriksaan ini hidup, dan [[Architecture]] untuk gambaran besar.
