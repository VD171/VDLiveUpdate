# Producer

**Producer** adalah sisi PC / release dari VDLU: kumpulan kecil tool yang mengubah tree modul yang sudah jadi menjadi feed yang ditandatangani dan content-addressed yang bisa jadi sumber update perangkat. Tidak ada di sini yang berjalan di ponsel. Tool-tool ini berjalan di mesin release Anda (atau, untuk bagian yang aman, di CI).

Ada empat di antaranya:

| Tool | Berjalan di | Bahasa | Tugas |
|---|---|---|---|
| `vdlu-pack` | PC / CI | python3 | Menelusuri tree modul final menjadi `manifest.json` + `blobs/<sha256>` |
| `vdlu-keygen` | PC | sh + openssl | Membuat keypair penandatangan ed25519 |
| `vdlu-sign` | PC | sh + openssl | Menyuntikkan `key_id` + signature ke dalam manifest, di tempat |
| `vdlu-gc` | PC | python3 | Membersihkan blob orphan dari feed yang dipublikasikan (fail-safe) |

Alur release adalah tiga langkah, dilakukan sekali per rilis: **pack, lalu sign, lalu publish**. `vdlu-keygen` adalah setup satu kali, dan `vdlu-gc` adalah housekeeping yang Anda jalankan ketika feed membesar. Semua yang dipancarkan producer sesuai dengan [[Feed Format]], yang itulah yang dikonsumsi engine di perangkat.

---

## vdlu-pack

`vdlu-pack` mengambil **tree persis yang dikirim `.zip` Anda** (tree final, setelah build Anda menerapkan whitelist dan pruning ABI-nya sendiri) dan menghasilkan feed untuknya.

```sh
vdlu-pack <module_tree_dir> <out_dir> <module_id> <version> \
          [--version-name v106] [--channel stable] [--prev ./prev/manifest.json]
```

Ia menulis dua hal ke `<out_dir>`:

- `manifest.json` - deskripsi lengkap dari tree target (setiap file dengan `sha256`, `size`, `mode`, encoding dan kelas reboot-nya), masih **belum ditandatangani** (field `key_id` dan `sig` adalah placeholder kosong).
- `blobs/<sha256>` (atau `blobs/<sha256>.gz`) - satu blob per konten file yang berbeda.

### Content-addressed dan dedup

Setiap blob dinamai oleh **sha256 dari konten asli (tidak terkompresi)**-nya. Karena namanya adalah hash, konten identik mendarat pada blob yang sama. `vdlu-pack` menulis blob hanya jika belum ada, jadi:

- File yang tidak berubah mempertahankan nama blob yang sama, dan tidak pernah ditulis ulang atau di-push ulang.
- Dua file berbeda dengan konten identik berbagi satu blob.
- File yang di-revert memakai ulang blob yang sudah ada dari sebelumnya.

Publikasi karenanya **inkremental by construction**: lintas rilis, `blobs/` hanya pernah bertumbuh, dan hanya konten yang benar-benar baru yang ditambahkan. Perangkat mengambil berdasarkan hash yang sama, jadi ia hanya mengunduh blob yang belum dimilikinya.

### Kompresi (field `enc`)

Untuk setiap file, `vdlu-pack` memutuskan bagaimana menyimpan blob:

- `gz` ketika file berukuran minimal 4096 byte **dan** gzip (deterministik `-9 -n`) menghemat minimal 10 persen.
- `raw` selain itu (file kecil yang sudah tercakup oleh gzip on-the-wire, atau data yang sudah tidak dapat dikompres).
- Jika `gzip` tidak ada di build host, semuanya disimpan `raw`. Packing tidak pernah gagal karena ini.

`sha256` dalam manifest **selalu** dari konten asli; `enc` hanya menamai bagaimana blob kebetulan disimpan. Perangkat mendekompres blob `gz` dengan toybox `gunzip` lalu memeriksa hash terhadap yang asli.

### Kelas reboot dan keamanan

`vdlu-pack` juga menandai setiap file dengan `class` reboot (`live`, `soft`, `reboot`) yang diturunkan dari path-nya, sehingga engine tahu apa yang dapat diterapkan tanpa reboot dan apa yang harus di-stage. Aturannya dan apa yang perangkat lakukan dengan setiap class dibahas di [[Reboot Handling]].

Beberapa hal yang sengaja **tidak** dilakukan `vdlu-pack`:

- Ia tidak mengikuti symlink (ia melewatinya dengan peringatan, sehingga konten dari luar tree, seperti link ke file sistem, tidak pernah bisa bocor ke dalam blob).
- Ia melewati file non-reguler (direktori, fifo, device).
- Ia menghormati `SOURCE_DATE_EPOCH` untuk timestamp `built`, jadi manifest dapat direproduksi.
- Ia mengecualikan sekumpulan path tetap dari feed sepenuhnya (trust root, scaffolding installer, dan beberapa lainnya). Daftar lengkap, dan mengapa masing-masing dikecualikan, ada di [[Feed Format]].

### Daftar `delete[]`

Berikan `--prev <previous manifest.json>` dan `vdlu-pack` menghitung `delete[]`: path yang ada di rilis sebelumnya tetapi hilang di rilis ini, sehingga perangkat menghapusnya alih-alih meninggalkan orphan. Path yang dikecualikan tidak pernah dipancarkan sebagai delete, bahkan ketika muncul di manifest sebelumnya (lihat [[Feed Format]] untuk semantik persisnya).

---

## vdlu-keygen

Langkah satu kali. `vdlu-keygen` membuat keypair penandatangan ed25519 untuk feed Anda.

```sh
vdlu-keygen <id> <out_dir>
```

Ia menulis tiga file:

| File | Apa itu | Ke mana perginya |
|---|---|---|
| `<id>.pem` | **Private** signing key (mode `0600`) | Tetap di mesin release Anda. Jangan pernah. |
| `<id>.pub` | Public key sebagai PEM | Hanya tooling sisi PC |
| `<id>.pub.raw` | Public key sebagai **raw 32 byte** | Dikirim sebagai entri keyring di perangkat modul |

Raw 32-byte public key adalah yang dibaca verifier perangkat (ia tidak membawa `openssl`, jadi ia tidak dapat membaca PEM). Anda menanamkan `<id>.pub.raw` ke dalam modul sebagai `vdlu/keyring/<id>.pub`. PEM hanya untuk penggunaan sisi PC. Pemisahan ini, dan bagaimana rotasi key bekerja, dijelaskan di [[Security and Trust Model]].

> **Keyring banyak-key wajib mengunci `key_id`.** Jika keyring modul mengirim lebih dari satu key (misalnya release key plus key feed fingerprint berkepercayaan-lebih-rendah), engine tidak akan menebak yang mana yang boleh menandatangani update modul. Setel config `key_id` ke key, atau key-key yang dipisah koma selama jendela rotasi, yang diizinkan menandatangani update; keyring satu-key otomatis mengunci dan tidak butuh config. Ini adalah allowlist update-modul, dibahas di [[Security and Trust Model]].

> `.pem` private adalah satu-satunya rahasia dalam seluruh sistem. Jaga agar tetap jauh dari setiap perangkat dan di luar setiap push repository. Lihat catatan CI di bawah.

---

## vdlu-sign

`vdlu-sign` mengambil manifest tak-bertanda-tangan yang dihasilkan `vdlu-pack` dan menandatanganinya **di tempat**.

```sh
vdlu-sign <manifest.json> <privkey.pem> <key_id>
```

Ia mengatur field `key_id`, menghitung bentuk kanonik dari manifest, dan menulis signature ed25519 (base64) ke dalam field `sig`. Signature itu atas transformasi byte yang presisi dari manifest sehingga PC dan perangkat menurunkan byte-bertanda-tangan yang persis sama tanpa library JSON di perangkat. Transformasi itu (**kanonikalisasi**) adalah invariant terpenting tunggal dalam format, dan ia didokumentasikan lengkap di [[Feed Format]].

Private key dibaca hanya di sini, di mesin Anda, dan tidak pernah meninggalkannya.

### Signing key tetap jauh dari CI

Ini adalah titik desain yang disengaja. CI dapat menjalankan `vdlu-pack` dan menghasilkan **baseline keyless** yang sempurna valid (sebuah manifest seed tak-bertanda-tangan; lihat [[Feed Format]]), sehingga instalasi baru lahir dalam keadaan current tanpa CI pernah menyentuh private key. Penandatanganan aktual dari feed yang dipublikasikan dilakukan oleh Anda, secara lokal, dengan `vdlu-sign`. Dengan begitu signing key 100 persen di luar CI, dan hanya feed yang Anda publikasikan dengan tangan yang ditandatangani.

---

## vdlu-gc

Karena blob content-addressed dan immutable, `blobs/` hanya pernah bertumbuh: `vdlu-pack` menambahkan, ia tidak pernah menghapus. Selama banyak rilis feed (dan situs Pages yang menghostingnya) mengumpulkan blob yang tidak lagi direferensikan manifest current mana pun. `vdlu-gc` membersihkan orphan itu.

```sh
vdlu-gc <feed_dir> [--keep-last N] [--keep extra.json ...] [--apply]
```

Ia membangun **retained set** dari manifest: `manifest.json` current, ditambah `N` manifest terarsip terakhir berdasarkan versi (default `N=3`, memberi margin rollback), ditambah apa pun yang Anda namai dengan `--keep`. Sebuah blob yang direferensikan oleh **tidak ada** manifest retained adalah orphan dan merupakan kandidat untuk dihapus. Retained set adalah union, jadi sebuah blob tetap selama rilis retained mana pun masih membutuhkannya; perangkat yang bertahan di versi retained lebih lama tidak pernah kehilangan fetch-nya.

`vdlu-gc` dibuat agar aman:

- **Dry-run secara default.** Tanpa `--apply`, ia hanya mencetak apa yang *akan* dihapusnya. Anda menambahkan `--apply` untuk benar-benar menghapus.
- **Fail-safe.** Jika ia tidak menemukan manifest retained sama sekali, ia menolak membersihkan alih-alih berisiko mengosongkan feed.
- **Retensi berdasarkan referensi, bukan berdasarkan tanggal.** Sebuah blob disimpan karena manifest retained menunjuknya, tidak pernah karena timestamp.

Setelah pembersihan, push feed yang lebih kecil ke host Anda. Renggangkan penulisan jika host Anda membatasi laju penulisan batch.

---

## Menyatukannya

Sebuah release biasa, dari ujung ke ujung:

```sh
# one-time: make a signing key. Keep the .pem off every device and every repo push.
vdlu-keygen release-2026 ./keys

# each release: pack the final shipped tree (post-whitelist, same tree the .zip ships)
vdlu-pack ./module_tree ./out demo 106 --version-name v106 --channel stable \
          --prev ./prev/manifest.json

# sign the manifest in place (local, private key never leaves your machine)
vdlu-sign ./out/manifest.json ./keys/release-2026.pem release-2026

# publish ./out/{manifest.json,blobs/} to your source (GitHub Pages, rsync, ...).
# occasionally: prune orphan blobs
vdlu-gc ./feed --keep-last 3            # dry-run first
vdlu-gc ./feed --keep-last 3 --apply    # then delete
```

Untuk contoh lengkap yang dikerjakan tentang mengadopsi VDLU ke dalam modul, lihat [[Quick Start]]. Untuk bentuk on-wire dari semua yang dipancarkan producer, lihat [[Feed Format]]. Untuk penalaran di balik penanganan key dan apa yang dijauhkan dari feed, lihat [[Security and Trust Model]].
