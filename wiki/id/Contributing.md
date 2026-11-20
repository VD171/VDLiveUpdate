# Contributing

Kontribusi sangat diterima. VDLU adalah engine self-update inkremental tanpa flash yang
di-vendor ke dalam modul KernelSU / APatch / Magisk. Halaman ini adalah workflow dev
praktis; untuk bagaimana bagian-bagiannya berpadu, baca [[Architecture]], [[Engine]] dan
[[Producer]] lebih dulu.

## Tidak ada yang dikompilasi

VDLU adalah skrip (POSIX sh, sedikit Python di sisi release, vanilla JS untuk
WebUI), jadi tidak ada build step. Anda memverifikasi sebuah perubahan dengan menjalankan pipeline
dari ujung ke ujung dan dengan static-check setiap bagian.

## Kontrak seam dulu

Kontrak interface antar komponen (signature CLI, nama file dan
key JSON yang dibagi oleh engine, producer dan WebUI) adalah **hukum
konvergensi**. Perlakukan ia sebagai immutable. Jika perubahan Anda menyentuh
seam producer-ke-engine (skema manifest, skema journal, key config, aturan
signature/kanonikalisasi), **selaraskan kontrak interface dulu**, lalu
ubah kode di kedua sisi agar cocok. Perubahan pada satu sisi seam tanpa
yang lainnya diam-diam merusak adopter. Lihat [[Producer]] untuk aturan kanonikalisasi
yang harus disepakati signer dan verifier byte demi byte.

## Uji dari ujung ke ujung sebelum PR

Jalankan producer dan engine bersama pada tree sekali pakai, dengan cara yang sama seperti
release adopter:

```sh
# 1. a signing key
producer/vdlu-keygen demo /tmp/k

# 2. pack a module tree into a feed
producer/vdlu-pack /tmp/tree /tmp/feed demo 1 --version-name v1

# 3. sign the manifest in place
producer/vdlu-sign /tmp/feed/manifest.json /tmp/k/demo.pem demo

# 4. verify the manifest the way the device will (RAW 32B keyring)
engine/vdlu-verify /tmp/feed/manifest.json /tmp/keyring

# 5. drive the engine against the feed (source=file:///tmp/feed in the config)
VDLU_DIR=... MODULE_DIR=... MODID=demo sh engine/update.sh check   # then run / boot
```

Lalu static-check setiap komponen:

```sh
sh -n engine/*.sh            # POSIX sh syntax, must pass
node --check webui/vdlu.js   # WebUI JS syntax
```

Dan buka `webui/demo.html` di browser: ia memock bridge root-manager
(`ksu.exec`), jadi Anda dapat menjalankan panel Updates, toast progres, cancel
dan banner reboot tanpa perangkat. Lihat [[WebUI]].

## Aturan rumah

- **POSIX sh di perangkat.** Tanpa bashisme di luar `local`, dan tanpa `jq`. Ia harus
  berjalan di toybox / busybox.
- **Keamanan tidak dapat ditawar.** Setiap field manifest adalah input yang bermusuhan;
  `validate_plan()` tetap fail-closed, dan private signing key tidak pernah menyentuh
  CI atau perangkat. Jangan longgarkan sebuah pemeriksaan untuk membuat test lolos.
- **Ketat pada kegagalan.** Jaga transaksi tetap resumable: tidak ada yang melaporkan "done"
  tanpa re-hash yang cocok, tidak ada yang ditimpa tanpa backup, dan
  apply tetap atomik.
- **Selalu kualitas release.** Jaga komentar tetap ringkas; tidak ada komentar yang berlebihan.
- **Satu perubahan logis per PR.** Katakan apa yang berubah dan mengapa.

## Mengajukan issue

Buka sebuah issue yang mendeskripsikan apa yang Anda lakukan, apa yang Anda harapkan, dan apa yang terjadi.
Untuk sebuah bug, sertakan id modul, profil sumber (`hardened` atau `trusted`),
perintah `update.sh` yang Anda jalankan, dan `journal.json` yang relevan (ia mencatat
fase, state dan error). Untuk sebuah fitur, katakan komponen mana yang disentuhnya (engine,
producer, atau WebUI) sehingga dampak seam jelas di awal.
