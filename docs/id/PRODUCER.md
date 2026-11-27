> **Languages:** [English](../PRODUCER.md) · [العربية](../ar/PRODUCER.md) · [Čeština](../cs/PRODUCER.md) · [Deutsch](../de/PRODUCER.md) · [Español](../es/PRODUCER.md) · [فارسی](../fa/PRODUCER.md) · [Français](../fr/PRODUCER.md) · [हिन्दी](../hi/PRODUCER.md) · Bahasa Indonesia · [Italiano](../it/PRODUCER.md) · [日本語](../ja/PRODUCER.md) · [한국어](../ko/PRODUCER.md) · [Nederlands](../nl/PRODUCER.md) · [Polski](../pl/PRODUCER.md) · [Português](../pt/PRODUCER.md) · [Русский](../ru/PRODUCER.md) · [Svenska](../sv/PRODUCER.md) · [ไทย](../th/PRODUCER.md) · [Türkçe](../tr/PRODUCER.md) · [Українська](../uk/PRODUCER.md) · [Tiếng Việt](../vi/PRODUCER.md) · [中文](../zh/PRODUCER.md)

---

# Lapisan producer + penandatanganan VDLU

Membangun delivery content-addressed (manifest + blob) untuk sebuah modul dan menandatanganinya.
Menyesuaikan diri dengan [`INTERFACES.md`](INTERFACES.md) §3/§6/§7.

| tool | berjalan di | bahasa | tugas |
|---|---|---|---|
| `producer/vdlu-pack` | PC / CI | python3 | menelusuri pohon modul final -> `manifest.json` + `blobs/` |
| `producer/vdlu-keygen` | PC | sh + openssl | pasangan kunci ed25519 (`<id>.pem` priv, `<id>.pub` PEM, `<id>.pub.raw` RAW 32B untuk keyring ramping) |
| `producer/vdlu-sign` | PC | sh + openssl | menyuntikkan `key_id` + `sig` ke dalam manifest, in place |
| `engine/vdlu-verify` | **perangkat** | sh + ed25519-mini | memverifikasi `sig` via ed25519-mini yang tertanam; keyring = pubkey RAW 32B (TANPA openssl di perangkat) |

## Pipeline

```sh
# 1. one-time: a signing key. Keep the .pem off every device and off any repo push.
producer/vdlu-keygen release-2026 ./keys

# 2. each release: pack the final tree (same tree the .zip ships, post-whitelist).
producer/vdlu-pack  ./module_tree  ./out  demo 106 --version-name v106 --channel stable \
                    [--prev ./prev/manifest.json]      # delete[] = paths gone since prev

# 3. sign the manifest in place.
producer/vdlu-sign  ./out/manifest.json  ./keys/release-2026.pem  release-2026

# 4. publish ./out/{manifest.json,blobs/} to <source> (Pages batch for public; rsync for private).
#    The slim device keyring holds ./keys/release-2026.pub.raw as keyring/release-2026.pub (RAW 32B).
```

`vdlu-pack` bersifat content-addressed dan deduplicating: sebuah blob yang `<sha256>`-nya sudah ada tidak
ditulis ulang, sehingga publikasi bersifat inkremental dan konten yang tidak berubah / dikembalikan tidak pernah di-push ulang.

### Keputusan `enc` (vdlu-pack)

`sha256` **selalu** dari konten asli (tidak terkompresi), `enc` hanya menamai bagaimana blob disimpan.

- `gz` ketika `size >= 4096` **dan** gzip (`-9 -n`, deterministik) menghemat setidaknya 10% (`comp <= raw*0.90`).
- `raw` jika tidak (teks kecil yang sudah dicakup gzip HTTP, atau data yang sudah tidak dapat dikompresi).
- gzip tidak ada di host build -> segalanya `raw` (tidak pernah gagal).

Sebuah blob disimpan sekali, dalam satu format: `blobs/<sha256>` (raw) atau `blobs/<sha256>.gz` (gz). Perangkat
mendekompresi dengan toybox `gunzip` (selalu ada), jadi tidak ada zstd yang dibundel.

### Keputusan `class` (vdlu-pack) - taksonomi reboot

Diturunkan dari path (INTERFACES §3, doc §4). Hanya default, sebuah aturan path tidak pernah men-downgrade `reboot`->`live`.

| class | dicocokkan oleh | diterapkan |
|---|---|---|
| `reboot` | `system/**`, `zygisk/**/*.so`, `*.rule` | di-stage `.vdlu-new`, swap saat boot |
| `soft` | root `service.sh` / `post-fs-data.sh` / `boot-completed.sh` | ditulis live, berjalan pada boot berikutnya |
| `live` | segalanya yang lain (webroot, bin, lib, confs, module.prop, ...) | ditulis live, atomik |

Symlink **tidak diikuti** (tidak pernah membocorkan konten dari luar pohon, mis. sebuah link ke
`/etc/shadow`) dan dilewati dengan peringatan, karena skema manifest tidak memiliki tipe symlink.
File non-reguler (dir, fifo, device) dilewati. `built` menghormati `SOURCE_DATE_EPOCH` untuk
manifest yang reproducible.

### Baseline (benih instalasi) - tidak ditandatangani, tanpa kunci

`baseline.json` (dikirim di `vdlu/baseline.json` dalam zip modul) menyemai `current.json` pada instalasi segar
sehingga perangkat lahir "terkini" (tanpa from:0, tanpa re-fetch). Engine memperlakukannya sebagai **benih lokal yang dipercaya**
(ia tiba dalam zip yang di-flash, yang merupakan batas kepercayaan instalasi) dan **TIDAK memverifikasi tanda tangannya** -
hanya manifest yang DIAMBIL dari feed yang melewati `vdlu-verify`. Jadi baseline tidak membutuhkan **kunci apa pun**: ia
hanyalah output `vdlu-pack` atas pohon yang dikirim (tidak ditandatangani, `sig`/`key_id` tetap kosong). Sebuah CI karena itu dapat
menghasilkannya **tanpa kunci**, menjaga kunci penandatanganan 100% di luar CI - hanya FEED yang dipublikasikan yang ditandatangani (operator,
secara lokal). `vdlu-pack` mengecualikan `baseline.json` dari manifest-nya sendiri (anti referensi-diri). Tidak fatal jika
tidak ada: perangkat cukup mulai dari from:0 pada pembaruan pertama, tidak pernah rusak.

## Kanonikalisasi (titik konvergensi)

`vdlu-sign` dan `engine/vdlu-verify` harus menurunkan **byte yang sama** dari sebuah manifest, pada dua
runtime yang berbeda (openssl PC vs toybox perangkat). Aturannya secara sengaja merupakan transformasi
byte, bukan re-serialisasi JSON, sehingga tidak membutuhkan library JSON di perangkat:

1. `vdlu-pack` menulis `manifest.json` **ringkas, kunci terurut, UTF-8**
   (`json.dumps(obj, sort_keys=True, separators=(",",":"), ensure_ascii=False)`), selalu menyertakan
   field `key_id` dan `sig` (placeholder string kosong hingga ditandatangani). Ini adalah bentuk penyimpanan
   kanonik.
2. **Bentuk kanonik = teks tersebut dengan field `"sig"` dihapus.** Karena kunci terurut, `sig`
   selalu muncul sebagai `,"sig":"<value>",` diapit oleh `"schema"` (sebelum) dan `"version"` (sesudah),
   keduanya selalu ada. Menghapusnya meninggalkan `...,"schema":N,"version":...` yang well-formed.
   JSON meng-escape setiap `"` di dalam nilai string menjadi `\"`, jadi token struktural `"sig":"` bersifat
   tidak ambigu bahkan terhadap sebuah filename yang secara harfiah berisi `"sig":"` (teruji).
3. Pesan yang ditandatangani/diverifikasi adalah **sha256 heksadesimal** (64 karakter ASCII, tanpa newline) dari bentuk
   kanonik. ed25519 atas heksadesimal tersebut (`openssl pkeyutl -sign/-verify -rawin`).

Penghapusan dalam sh POSIX (fungsi identik di kedua tool, tanpa `sed`/`jq`):

```sh
# $1 = full manifest text (trailing newline already stripped by $(cat ...))
_pre=${_c%%\"sig\":\"*}     # up to  ...,"schema":N,
_rest=${_c#*\"sig\":\"}      # after "sig":"
_tail=${_rest#*\",}          # after <value>",  ->  "version":...
printf '%s%s' "$_pre" "$_tail" | sha256sum | cut -d' ' -f1
```

`key_id` adalah bagian dari bentuk kanonik (hanya `sig` yang dicabut), `vdlu-sign` mengatur `key_id` **sebelum**
hashing. Placeholder nilai yang kosong (`"sig":""`, saat sign) atau terisi (saat verify) menghasilkan byte kanonik
yang identik, jadi sign dan verify sepakat secara konstruksi.

Python mereproduksinya sebagai `re.sub(r'"sig":"[^"]*",', '', text.rstrip("\\n"), count=1)` lalu sha256 - digunakan
hanya untuk cross-check, produsen yang otoritatif adalah dua tool sh.

## Tanda tangan (ed25519)

- `vdlu-keygen` (PC): `openssl genpkey -algorithm ed25519` (priv `0600`) + `openssl pkey -pubout` (pub **PEM**,
  untuk penandatanganan/openssl) + `openssl pkey -pubout -outform DER | tail -c 32` -> **`.pub.raw` (RAW 32B)** (DER SPKI
  ed25519 adalah prefiks 12-byte + kunci 32-byte, jadi `tail -c 32` ADALAH kunci). Ia memancarkan KEDUANYA.
- `vdlu-sign` (PC): `openssl pkeyutl -sign -rawin` atas sha256 heksadesimal kanonik, tanda tangan disimpan base64.
- `vdlu-verify` (**perangkat, ramping**): `ed25519-mini <pubkey32> <msg> <sig64>` - membaca keyring sebagai pubkey **RAW 32B**,
  TANPA openssl di perangkat. `key_id` disanitasi sebagai path (tanpa `/`, `.`, `..`, `"`). 🚨 Keyring mengirim
  **`.pub.raw` (32B)**, tidak pernah `.pub` PEM (113B): PEM hanya untuk sisi-PC dan `ed25519-mini` tidak dapat membacanya.

Model kepercayaan (INTERFACES §6, doc §11/§13): `profile=hardened` (publik) membuat verify wajib - sebuah
tanda tangan yang gagal atau hilang membatalkan pembaruan. `profile=trusted` (privat, sumber SSH-staged) memperlakukan
verify sebagai best-effort, tetapi sha256 setiap blob tetap diperiksa.

## Keyring + rotasi

Keyring adalah sebuah direktori berisi file `<key_id>.pub`, masing-masing pubkey ed25519 **RAW 32B** (dari `.pub.raw`
milik `keygen`), BUKAN PEM - `ed25519-mini` membaca 32 byte mentah. Kirim pubkey mentah saat ini **dan** yang sebelumnya
(doc §13) sehingga kunci yang dirotasi tidak mem-brick instalasi yang lebih lama. `vdlu-sign` dengan `key_id` baru dan perangkat
memilih `<keyring>/<key_id>.pub` (mentah) adalah keseluruhan mekanisme rotasi - tanpa perubahan engine. Keyring bersifat
**stabil** lintas release (hanya rotasi kunci yang mengubahnya): sebuah re-vendor harus **verifikasi-bukan-salin**, dan tidak pernah
menimpanya dengan `.pub` PEM sisi-PC.

**Keyring multi-kunci WAJIB mem-pin kunci modul.** Engine membatasi `key_id` mana yang boleh menandatangani MODULE-UPDATE ke allowlist `key_id` config (INTERFACES §5/§6), diperiksa fail-closed sebelum pubkey dipilih. Keyring kunci tunggal aman-secara-default (satu kunci itu diterima). Tetapi sebuah modul yang keyring-nya JUGA membawa kunci kepercayaan lebih rendah - mis. kunci fingerprint-feed di samping kunci release - ditolak sampai `config`-nya mendeklarasikan kunci modul, mis. `key_id=vd-2026` (dipisah koma untuk rotasi, mis. `key_id=vd-2026,vd-2027`). Ini mencegah kunci kepercayaan lebih rendah yang bocor menandatangani pembaruan flashless root.

`vdlu-pack` **mengecualikan keyring dan biner `verify/` dari feed** (akar kepercayaan bersifat hanya-flash, tidak pernah disajikan lewat kabel), bersama `baseline.json`, scaffolding installer (`META-INF/`, `customize.sh`), gerbang flash `.vd/`, `update.json`/`update-mmrl.json` yang diisi CI, dan pendamping `.sha256` per file. Hanya konten milik modul itu sendiri yang dapat diperbarui lewat feed, sehingga sebuah manifest tidak pernah dapat menulis ulang jangkar kepercayaan di perangkat.

<!-- doc-footer -->

---

> _Dokumentasi ini dibuat dengan Claude (Anthropic) dan dikelola oleh VD171. Koreksi dan perbaikan dipersilakan, lihat [CONTRIBUTING.md](CONTRIBUTING.md)._
