> **Languages:** [English](../TRUST-MODEL.md) · [العربية](../ar/TRUST-MODEL.md) · [Čeština](../cs/TRUST-MODEL.md) · [Deutsch](../de/TRUST-MODEL.md) · [Español](../es/TRUST-MODEL.md) · [فارسی](../fa/TRUST-MODEL.md) · [Français](../fr/TRUST-MODEL.md) · [हिन्दी](../hi/TRUST-MODEL.md) · Bahasa Indonesia · [Italiano](../it/TRUST-MODEL.md) · [日本語](../ja/TRUST-MODEL.md) · [한국어](../ko/TRUST-MODEL.md) · [Nederlands](../nl/TRUST-MODEL.md) · [Polski](../pl/TRUST-MODEL.md) · [Português](../pt/TRUST-MODEL.md) · [Русский](../ru/TRUST-MODEL.md) · [Svenska](../sv/TRUST-MODEL.md) · [ไทย](../th/TRUST-MODEL.md) · [Türkçe](../tr/TRUST-MODEL.md) · [Українська](../uk/TRUST-MODEL.md) · [Tiếng Việt](../vi/TRUST-MODEL.md) · [中文](../zh/TRUST-MODEL.md)

---

# Kebijakan keamanan dan model kepercayaan

VDLiveUpdate (VDLU) menerapkan **pembaruan root flashless** ke modul yang live: ia menulis
ke `/data/adb/modules/<mod>` dan menukar sebuah `.so` Zygisk saat boot. Setiap field dari
manifest yang diambil (`path`, `sha256`, `delete[]`, `mode`, ...) adalah **input hostil** - sebuah
feed yang diracuni atau MITM mengirimkannya. Halaman ini adalah model kepercayaan dan kebijakan
pengungkapan yang bertanggung jawab. Untuk kontrak jahitan lengkap lihat [`INTERFACES.md`](INTERFACES.md),
dan internal engine/producer di [`ENGINE.md`](ENGINE.md) dan
[`PRODUCER.md`](PRODUCER.md), halaman wiki **Security-and-Trust-Model** membawa model yang
sama untuk pembaca di luar repo.

## Versi yang didukung

Perbaikan keamanan mendarat di `ENGINE_VERSION` terbaru, sebuah manifest yang ditandatangani
mendeklarasikan engine minimum yang dibutuhkannya via `engine_min`, dan engine di perangkat menolak
sebuah manifest yang meminta lebih dari yang diimplementasikannya. Engine ter-vendor yang lebih lama
diharapkan untuk **re-vendor** guna mengambil sebuah perbaikan, bukan di-back-patch di tempat.

| ENGINE_VERSION | status |
|---|---|
| 7 (saat ini) | didukung - jangan pernah merevert modul yang lebih maju dari feed (`versionCode` terpasang live menjadi lantai versi "from"), self-heal saat boot untuk plan downgrade usang |
| 6 | digantikan - self-heal saat boot untuk journal usang dengan `target <= 0` (baseline 0 dari stub yang dihapus tidak lagi memicu UI atau aksi boot apa pun) |
| 5 | digantikan - pengecualian jangkar-kepercayaan sisi-engine (dir `vdlu/` diabaikan bahkan jika sebuah feed membawanya), batas 128 MiB per-file / 2 MiB manifest |
| 4 | digantikan - allowlist `key_id`, penolakan path dot-segment/trailing-slash, batas ukuran, lock saat check |
| <= 3 | tidak didukung - re-vendor engine saat ini |

Setiap perubahan pada logika verifikasi atau apply engine menaikkan `ENGINE_VERSION`.

## Melaporkan kerentanan

Laporkan secara privat. **Jangan** membuka issue, PR, atau posting forum publik untuk sebuah bug
keamanan. Gunakan kontak proyek (lihat [`CONTRIBUTING.md`](../CONTRIBUTING.md)):

- Telegram: **@VD_Priv8** (https://t.me/VD_Priv8)
- Kanal: **@Priv8_VD** (https://t.me/Priv8_VD)
- E-mail: **vd.priv8@pm.me**

Sertakan versi engine, `profile` yang sedang digunakan, dan sebuah manifest atau feed yang
mereproduksi masalah tersebut. Perbaikan dikirim sebagai `ENGINE_VERSION` baru dengan entri
`CHANGELOG.md`, koordinasikan waktu pengungkapan pada thread laporan.

## Model kepercayaan

- **Tanda tangan ed25519 terpisah (detached).** Producer menandatangani manifest kanonik di PC
  (openssl), perangkat memverifikasi dengan `ed25519-mini` yang tertanam - **tanpa openssl di
  perangkat**. Pesan yang ditandatangani adalah heksadesimal sha256 dari manifest tanpa field `sig`-nya
  (kunci terurut, ringkas, UTF-8), sehingga sign dan verify menurunkan byte yang sama pada dua runtime
  tanpa library JSON di perangkat.
- **Keyring = pubkey RAW 32-byte**, hanya-flash. Keyring perangkat mengirim `<key_id>.pub`
  sebagai kunci 32-byte mentah (tidak pernah PEM), `vdlu-pack` **mengecualikan** keyring dan
  biner `verify/` dari feed, sehingga sebuah manifest tidak pernah dapat menulis ulang jangkar
  kepercayaan di perangkat lewat kabel.
- **Pengecualian jangkar-kepercayaan sisi-engine (VDLU#2).** Terlepas dari pengecualian sisi-producer di
  atas, engine di perangkat **mengabaikan** setiap path `vdlu/` (`update.sh`, `vdlu-verify`, `verify/*`,
  `keyring/*`, config) dalam sebuah plan yang diambil - ia tidak pernah mengambil, menerapkan, atau
  menghapusnya, bahkan jika sebuah feed membawanya. Sebuah feed yang dipublikasikan mengirim seluruh pohon
  modul, termasuk `vdlu/`, sehingga engine secara diam-diam membuang path-path itu alih-alih menolak
  manifest: modul tetap diperbarui, dan jangkar kepercayaan hanya berubah melalui re-flash bertanda tangan
  penuh. Sebuah kunci penandatanganan tunggal yang bocor tidak lagi dapat menukar verifier atau kunci
  penandatanganan lewat kabel dan mempertahankan root.
- **Allowlist `key_id` module-update (fail-closed, sebelum pemilihan pubkey).** Sebuah keyring
  secara sah dapat membawa lebih dari satu kunci (misalnya kunci fingerprint-feed berkepercayaan lebih
  rendah di samping kunci release). Sebelum `<key_id>.pub` dipilih, `verify_manifest` menolak setiap
  manifest yang `key_id`-nya tidak ada dalam allowlist yang dikonfigurasi, di **kedua** profile, dan
  mencerminkan set yang diselesaikan ke dalam `vdlu-verify` via `VDLU_KEYID_ALLOW`. Ini menutup sebuah
  bypass di mana kunci berkepercayaan lebih rendah yang bocor jika tidak demikian dapat menandatangani
  pembaruan root flashless penuh. Aman-secara-default saat `key_id` tidak disetel: keyring **kunci
  tunggal** otomatis mem-pin ke satu kunci itu, keyring **multi-kunci** ditolak sampai `key_id` dipin
  (dipisah koma untuk rotasi).
- **Akar kepercayaan fingerprint-feed adalah path terpisah yang dipatok** dengan kuncinya sendiri, ia
  tidak pernah dapat dijangkau melalui jalur module-update di atas.
- **Baseline adalah benih lokal yang dipercaya.** `baseline.json` tiba di dalam zip yang di-flash -
  batas kepercayaan instalasi - sehingga ia tidak ditandatangani dan tanpa kunci serta **tidak**
  dijalankan melalui `vdlu-verify`, hanya manifest yang **diambil** dari feed yang diverifikasi. Ini
  menjaga kunci penandatanganan tetap di luar CI.

## Jaminan fail-closed

- **`validate_plan` berjalan sebelum fetch atau apply apa pun.** Di `do_diff`, fail-closed, ia
  menolak **seluruh** manifest jika ada `path` yang absolut, berisi segmen `..` atau `.`, berakhir
  dengan `/`, atau memuat karakter kontrol, jika ada `sha256` yang bukan `^[0-9a-f]{64}$`, atau jika ada
  `mode`/`class`/`enc` yang tidak valid. Tidak ada field hostil yang mencapai shell, dan `cmd_check`
  tidak membawa interpolasi `system()`.
- **Penampungan path.** Setiap penulisan dan penghapusan dibatasi ke `MODULE_DIR` via
  `contained()` - apply, delete, dan `stage_file` saat reboot semuanya melewati penjaga yang sama.
  Symlink di dalam pohon dilewati oleh producer (tidak pernah membocorkan konten dari luarnya).
- **Dua profile, fail-closed melalui inversi.** `trusted` (privat, sumber SSH-staged) adalah
  **satu-satunya** opt-in ke verify best-effort, **nilai lain apa pun** - termasuk sebuah typo,
  spasi/CR di akhir, atau huruf besar-kecil yang berbeda - diperlakukan sebagai `hardened`, di mana
  sebuah tanda tangan yang valid bersifat **wajib** dan sebuah kegagalan membatalkan. `sha256` setiap
  blob diperiksa di kedua profile.
- **Tanda tangan + hash sebelum eksekusi tool apa pun.** `curl` statis yang diambil berjalan sebagai
  root, jadi `install-tool` memverifikasi tanda tangan tools-manifest (ed25519-mini, wajib di **profile
  apa pun**) dan hash curl **sebelum** ia diinstal dan dieksekusi - sig+hash sebelum exec menutup RCE.
- **Transaksi yang dapat dilanjutkan dan aman-pin.** Manifest yang sedang berjalan dipatok di
  `target.json`, sebuah crash, hilangnya jaringan, atau reboot dilanjutkan dari journal tanpa memutuskan
  ulang plan. Downgrade diblokir (`version` monotonik), field `module` yang ditandatangani harus sama
  dengan `MODID`, dan `delete[]` hanya berjalan pada `finalize_done` (sebuah `PENDING_REBOOT` tidak
  menghapus apa pun). Tidak pernah ada yang "selesai" tanpa re-hash penuh, tidak ada yang ditimpa tanpa
  backup `rollback/<v>/` terlebih dahulu.

## Hardening (pertahanan berlapis)

- **Batas ukuran.** Manifest, tools-manifest, dan jalur unduhan `wget`/`head -c` tanpa-curl semuanya
  dibatasi sebelum dibaca (anti-OOM / anti-flood). Sebuah blob menggagalkan fasenya setelah 3 percobaan.
  Batasnya adalah **128 MiB per file** (`MAX_FILE_BYTES`) dan **2 MiB untuk manifest**
  (`MAX_MANIFEST_BYTES`), ditegakkan di `update.sh` dan dicerminkan di `vdlu-verify`.
- **Lock saat check.** `check` mengambil mkdir-lock sebelum membangun ulang direktori kerjanya,
  sehingga sebuah run yang bersamaan tidak dapat berlomba dengannya.
- **Penampungan staging.** `stage_file` memiliki penjaga `contained()` yang sama dengan primitif apply
  live, sehingga sebuah path reboot-hard yang di-stage juga tidak dapat lolos dari `MODULE_DIR`.
- **TLS adalah pertahanan berlapis, bukan akar kepercayaan.** curl statis menggunakan mbedTLS dengan
  trust store Android (`--capath`, override `ca_path`), jaminan integritas adalah tanda tangan ed25519,
  pemeriksaan sertifikat adalah lapisan kedua.

## Lihat juga

- [`INTERFACES.md`](INTERFACES.md) - kontrak jahitan yang tidak dapat diubah (§5 config, §6 tanda tangan, §11 toolchain).
- [`ENGINE.md`](ENGINE.md) - engine sisi-perangkat dan mesin state-nya.
- [`PRODUCER.md`](PRODUCER.md) - packing, penandatanganan, kanonikalisasi, dan rotasi kunci.
- Wiki: **Security-and-Trust-Model**.

<!-- doc-footer -->

---

> _Dokumentasi ini dibuat dengan Claude (Anthropic) dan dikelola oleh VD171. Koreksi dan perbaikan dipersilakan, lihat [CONTRIBUTING.md](CONTRIBUTING.md)._
