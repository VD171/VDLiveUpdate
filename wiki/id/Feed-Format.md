# Feed Format

**Feed** adalah apa yang VDLU sajikan melalui kabel dan apa yang perangkat jadikan sumber update. Ia adalah direktori statis biasa, yang dapat disajikan oleh apa pun (GitHub Pages, target rsync, sebuah path `file://`):

```
<source>/
  manifest.json          # the signed description of the current release
  blobs/<sha256>         # one blob per distinct file content
  blobs/<sha256>.gz      # (when the blob is stored gzipped)
```

Modul itu sendiri juga mengirim satu file ekstra, `baseline.json`, di dalam `.zip` (tidak disajikan dari feed). Producer yang membangun semua ini dideskripsikan di [[Producer]]; halaman ini adalah kontrak on-wire.

---

## manifest.json

Manifest adalah deskripsi lengkap dari satu rilis: setiap file dalam tree target, apa yang harus dihapus, dan signature atas keseluruhannya.

```json
{
  "schema": 1,
  "module": "demo",
  "version": 106,
  "version_name": "v106",
  "built": "2026-11-19T12:00:00Z",
  "engine_min": 3,
  "channel": "stable",
  "key_id": "release-2026",
  "files": [
    {
      "path": "webroot/index.html",
      "sha256": "<hex64>",
      "size": 1234,
      "mode": "0644",
      "enc": "raw",
      "class": "live"
    }
  ],
  "delete": ["webroot/old.html"],
  "sig": "<base64>"
}
```

### Field

| Field | Arti |
|---|---|
| `schema` | Versi format dari manifest itu sendiri (saat ini `1`). |
| `module` | Id modul. Perangkat menolak manifest jika ia tidak cocok dengan id modulnya sendiri, sehingga feed yang ditandatangani valid untuk modul berbeda tidak dapat disajikan sebagai gantinya. |
| `version` | Versi integer. Engine memperbarui hanya maju; feed yang lebih lama dari perangkat adalah state "ahead" yang benign, bukan error. |
| `version_name` | String versi yang terbaca manusia (misalnya `v106`). |
| `built` | Timestamp build ISO 8601. Menghormati `SOURCE_DATE_EPOCH` untuk reproduksibilitas. |
| `engine_min` | Versi engine minimum yang dibutuhkan untuk menerapkan manifest ini. |
| `channel` | Channel rilis (misalnya `stable`). |
| `key_id` | Key mana dalam keyring perangkat yang menandatangani manifest ini. Memilih public key untuk verifikasi, dan harus ada dalam allowlist update-modul engine (lihat [[Security and Trust Model]]); key yang sekadar ada di keyring tetapi tidak di-allowlist ditolak sebelum pubkey-nya dimuat. |
| `files[]` | Tree target **lengkap** (bukan diff). Setiap entri: `path`, `sha256`, `size`, `mode`, `enc` (`raw`/`gz`), `class` (`live`/`soft`/`reboot`). |
| `delete[]` | Path yang hadir di rilis sebelumnya tetapi hilang sekarang, untuk dihapus perangkat. |
| `sig` | Signature ed25519, base64. Lihat kanonikalisasi di bawah. |

`files[]` mendeskripsikan tree **keseluruhan**, bukan delta. Perangkat menghitung delta itu sendiri dengan membandingkan manifest terhadap apa yang sudah dimilikinya, dan mengambil hanya blob yang `sha256`-nya hilang. `sha256` selalu dari konten asli (tidak terkompresi); `enc` hanya mengatakan bagaimana blob itu disimpan di `blobs/`. Arti `class` dan apa yang perangkat lakukan dengan setiap nilai dibahas di [[Reboot Handling]].

---

## Kanonikalisasi (byte yang ditandatangani)

Ini adalah invariant terpenting tunggal dalam format. Signer PC dan verifier di perangkat berjalan pada runtime yang sepenuhnya berbeda (openssl di PC, toybox + verifier mungil yang tertanam di perangkat, dan **tanpa library JSON sama sekali** di perangkat). Keduanya tetap harus menurunkan byte persis yang sama untuk ditandatangani dan untuk diverifikasi. Aturannya karenanya adalah **transformasi byte** yang disengaja, bukan re-serialisasi JSON.

**Langkah 1: bentuk store yang tetap.** `vdlu-pack` menulis `manifest.json` compact, dengan key terurut, UTF-8, selalu menyertakan `key_id` dan `sig` (sebagai string kosong sampai ditandatangani):

```
json.dumps(obj, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
```

**Langkah 2: hilangkan hanya `sig`.** Bentuk kanonik adalah teks persis itu dengan **hanya field `"sig"` dihilangkan**. Karena key terurut, `sig` selalu muncul sebagai `,"sig":"<value>",` diapit oleh `"schema"` sebelumnya dan `"version"` sesudahnya (keduanya selalu hadir), jadi menghilangkannya meninggalkan teks yang well-formed. JSON meng-escape setiap `"` di dalam nilai string sebagai `\"`, jadi token struktural `"sig":"` tidak ambigu bahkan terhadap nama file yang secara harfiah mengandung `"sig":"`.

Penghilangan itu adalah segelintir POSIX parameter expansion, identik di signer dan verifier, tanpa `sed` dan tanpa `jq`:

```sh
# $1 = the full manifest text
_pre=${_c%%\"sig\":\"*}     # up to  ...,"schema":N,
_rest=${_c#*\"sig\":\"}      # after "sig":"
_tail=${_rest#*\",}          # after <value>",  ->  "version":...
printf '%s%s' "$_pre" "$_tail" | sha256sum | cut -d' ' -f1
```

**Langkah 3: tandatangani hash dari itu.** Message yang ditandatangani/diverifikasi adalah **sha256 hex** (64 karakter ASCII, tanpa newline) dari bentuk kanonik. ed25519 menandatangani hex itu.

Dua konsekuensi jatuh dari ini by construction:

- `key_id` adalah bagian dari bentuk kanonik (hanya `sig` yang dihilangkan). `vdlu-sign` mengatur `key_id` **sebelum** meng-hash, jadi identitas key dicakup oleh signature.
- Entah placeholder `sig` kosong (`"sig":""`, pada saat sign) atau terisi (pada saat verify), menghilangkannya menghasilkan byte kanonik yang identik. Signing dan verifying sepakat secara otomatis.

Kedua tool POSIX sh adalah otoritatif. Sebuah ekuivalen Python, `re.sub(r'"sig":"[^"]*",', '', text, count=1)` lalu sha256, ada hanya untuk cross-check keduanya.

Penalaran trust seputar semua ini (mengapa verifikasi di perangkat, bagaimana `hardened` fail closed) hidup di [[Security and Trust Model]].

---

## baseline.json (install seed)

Ketika sebuah modul baru dipasang, ia seharusnya sudah "current" untuk versi yang dikirimnya sendiri, tanpa self-update yang tak perlu atas versi yang baru saja dipasangnya. Itulah yang dilakukan `baseline.json`.

`baseline.json` dikirim **di dalam zip modul** (di `vdlu/baseline.json`), bukan di feed. Pada instalasi baru, engine men-seed record "versi aktif"-nya darinya, sehingga perangkat lahir current, tanpa `from:0` dan tanpa re-fetch atas apa yang sudah dimilikinya.

Properti utama:

- Ia adalah **salinan keyless dari manifest yang ditandatangani** untuk versi yang dikirim: output `vdlu-pack` yang sama, dibiarkan tak-bertanda-tangan (`key_id` dan `sig` tetap kosong).
- Ia **tidak diverifikasi**. Engine memperlakukannya sebagai seed lokal tepercaya karena ia tiba di dalam zip yang di-flash, yang merupakan batas trust instalasi. Hanya manifest yang *diambil dari feed* yang melewati verifikasi signature.
- Karena ia tidak membutuhkan signature, **CI dapat menghasilkannya keyless**, yang itulah yang menjaga signing key sepenuhnya di luar CI (lihat [[Producer]]).
- `vdlu-pack` **mengecualikan `baseline.json` dari manifest-nya sendiri**, sehingga manifest tidak pernah mereferensikan baseline (itu akan menjadi loop referensi-diri: manifest ke baseline ke manifest).
- Ia **tidak fatal jika absen**. Tanpanya, perangkat cukup mulai dari `from:0` pada update pertamanya dan mengambil apa yang dibutuhkannya. Tidak pernah rusak, hanya kurang optimal.

---

## Blobs

Setiap konten file yang berbeda adalah satu blob di bawah `blobs/`, dinamai oleh **sha256 dari konten asli**:

- `blobs/<sha256>` untuk blob raw.
- `blobs/<sha256>.gz` untuk blob yang di-gzip (gzip dipertahankan hanya ketika file berukuran minimal 4096 byte dan kompresi menghemat minimal 10 persen).

Sebuah blob disimpan sekali, dalam satu format. Content addressing memberi deduplikasi secara gratis: konten yang tidak berubah, bersama atau di-revert memetakan ke blob yang sudah ada, jadi feed bertumbuh hanya oleh konten yang benar-benar baru, dan perangkat mengunduh hanya hash yang hilang. Perangkat memeriksa `sha256` setiap blob yang diunduh terhadap manifest (setelah mendekompres blob `gz`) sebelum memakainya.

---

## Apa yang dikecualikan dari feed, dan mengapa

Feed membawa **hanya konten milik modul sendiri**. Sekumpulan path tetap dijauhkan darinya dengan sengaja. `vdlu-pack` menerapkan satu predikat eksklusi baik ketika menelusuri tree maupun ketika menghitung `delete[]`.

| Dikecualikan | Mengapa |
|---|---|
| `vdlu/keyring/`, `vdlu/verify/` (trust root: raw public key + biner verifier) | **Ini adalah alasan keamanan inti.** Trust anchor bersifat **flash-only**. Jika keyring atau verifier dapat dikirim lewat feed, sebuah manifest dapat menimpa hal yang memvalidasinya. Menjauhkannya dari kabel berarti sebuah manifest tidak pernah dapat menulis ulang trust anchor di perangkat. |
| `vdlu/baseline.json` | Ia adalah salinan dari manifest yang ditandatangani (install seed); mem-pack-nya akan menjadi loop referensi-diri. |
| infrastruktur flash `.vd/` | Scaffolding flash-gate yang dikirim dalam zip, tidak pernah diterapkan live. |
| `update.json`, `update-mmrl.json` | size/sha-nya diisi oleh CI *setelah* zip dibangun, jadi salinan yang dikirim berbeda dari salinan feed mana pun. Mem-feed-nya akan menyebabkan phantom single-file fetch pada setiap self-update pertama instalasi, dan keduanya vestigial di perangkat toh (manager membaca update JSON raw jarak jauh). |
| `META-INF/`, `customize.sh` (scaffolding installer) | Dikonsumsi oleh manager pada saat **flash** dan tidak disimpan dalam modul yang terpasang. Keduanya bukan konten VDLU; menyajikannya memboroskan blob dan, jika salah satu pernah berubah antar versi, ia akan ditulis sebagai file installer ke dalam direktori modul live. |
| Pendamping `.sha256` per-file | Keduanya milik zip flashable saja, menjadi basi setelah update inkremental, dan akan menggandakan manifest. |
| File dev/doc (`RELEASE.md`, `CLAUDE.md`, `.gitignore`) | Tidak pernah dikirim ke perangkat; menyajikannya memboroskan blob dan mengaduk manifest yang ditandatangani pada setiap edit doc. |

Penalaran di balik eksklusi trust-root diperluas di [[Security and Trust Model]].

---

## Semantik delete[]

`delete[]` memberi tahu perangkat path mana yang harus dihapus, sehingga file yang dijatuhkan antar rilis tidak berlama-lama di perangkat sebagai orphan. Ia dihitung dengan meneruskan `--prev <previous manifest.json>` ke `vdlu-pack`: sebuah path yang ada di rilis sebelumnya dan tidak ada di rilis saat ini menjadi entri delete.

Aturan penting: **path yang dikecualikan tidak pernah dipancarkan sebagai delete, bahkan dengan `--prev`.** Setiap path sebelumnya dijalankan melalui predikat eksklusi yang sama yang dipakai ketika menelusuri tree. Jika sebuah `--prev` menunjuk ke manifest lebih lama yang masih mendaftar path yang sekarang-dikecualikan (`baseline.json` yang nyasar, `META-INF/*`, entri keyring, dan seterusnya), path-path itu **tidak** diubah menjadi entri delete. Path yang dikecualikan tidak pernah merupakan konten feed, jadi ia bukan milik VDLU untuk dihapus, dan perangkat tidak pernah diperintahkan menghapus file yang tidak disajikan melalui feed. Inilah yang menjaga daftar eksklusi agar tidak pernah berbalik menjadi instruksi yang destruktif.
