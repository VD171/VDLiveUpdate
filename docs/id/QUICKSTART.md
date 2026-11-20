> **Languages:** [English](../QUICKSTART.md) · [العربية](../ar/QUICKSTART.md) · [Čeština](../cs/QUICKSTART.md) · [Deutsch](../de/QUICKSTART.md) · [Español](../es/QUICKSTART.md) · [فارسی](../fa/QUICKSTART.md) · [Français](../fr/QUICKSTART.md) · [हिन्दी](../hi/QUICKSTART.md) · Bahasa Indonesia · [Italiano](../it/QUICKSTART.md) · [日本語](../ja/QUICKSTART.md) · [한국어](../ko/QUICKSTART.md) · [Nederlands](../nl/QUICKSTART.md) · [Polski](../pl/QUICKSTART.md) · [Português](../pt/QUICKSTART.md) · [Русский](../ru/QUICKSTART.md) · [Svenska](../sv/QUICKSTART.md) · [ไทย](../th/QUICKSTART.md) · [Türkçe](../tr/QUICKSTART.md) · [Українська](../uk/QUICKSTART.md) · [Tiếng Việt](../vi/QUICKSTART.md) · [中文](../zh/QUICKSTART.md)

---

# Quickstart adopsi VDLU

Sebuah checklist salin-tempel untuk mem-vendor **VDLiveUpdate** ke dalam sebuah modul. VDLU bukan
sebuah modul tersendiri: ia diletakkan ke dalam `<module>/vdlu/` dan dikirim di dalam zip modul Anda.
Untuk rasional lengkap lihat [`INTERFACES.md`](INTERFACES.md) (kontrak jahitan),
[`ENGINE.md`](ENGINE.md), [`PRODUCER.md`](PRODUCER.md) dan [`WEBUI.md`](WEBUI.md).

Ganti `<id>` dengan id kunci penandatanganan Anda, `<abi>` dengan ABI perangkat yang Anda kirim
(`arm64-v8a`, `armeabi-v7a`, `x86_64`, `x86`), dan `<module>` dengan pohon modul Anda.

## Tata letak target

Ini adalah pohon `vdlu/` persis yang dibawa modul setelah adopsi:

```
<module>/
├── module.prop
├── post-fs-data.sh            # trigger pre-zygote: sh "$MODDIR/vdlu/update.sh" boot
├── webroot/
│   └── index.html             # WebUI Anda, mengaitkan panel Updates (langkah 5)
└── vdlu/
    ├── update.sh              # engine (di-vendor byte-demi-byte)
    ├── vdlu-verify            # shim verify ed25519 (sisi-perangkat, tanpa openssl)
    ├── verify/
    │   └── <abi>/ed25519-mini # biner verifier per-ABI
    ├── keyring/
    │   └── <id>.pub           # kunci publik RAW 32-byte (TIDAK PERNAH PEM)
    ├── config.default         # default profile + source + otomatisasi
    └── baseline.json          # benih instalasi (tanpa tanda tangan, tanpa kunci)
```

State yang mutable milik engine (`config`, `current.json`, journal, lock) berada di
Tier-2, `/data/adb/<modid>/vdlu/`, di luar direktori modul; `config.default` menyemainya
pada run pertama.

## 1. Vendor engine

Salin engine, shim verify dan verifier per-ABI ke dalam `<module>/vdlu/`:

```sh
mkdir -p <module>/vdlu/verify
cp engine/update.sh      <module>/vdlu/update.sh
cp engine/vdlu-verify    <module>/vdlu/vdlu-verify
cp -r verify/<abi>       <module>/vdlu/verify/<abi>      # ed25519-mini per ABI
```

Kirim hanya ABI yang Anda dukung; `customize.sh` dapat memangkas `verify/` ke ABI perangkat
saat instalasi.

## 2. Hasilkan kunci penandatanganan (sekali saja)

```sh
producer/vdlu-keygen <id> ./keys
```

Ini memancarkan `<id>.pem` (privat, jauhkan dari setiap perangkat dan dari setiap push repo),
`<id>.pub` (PEM, hanya sisi-PC) dan `<id>.pub.raw` (RAW 32 byte, untuk keyring perangkat).

## 3. Tanamkan kunci publik mentah

Keyring perangkat menyimpan kunci **RAW 32-byte**, tidak pernah PEM (`ed25519-mini`
tidak dapat membaca PEM):

```sh
mkdir -p <module>/vdlu/keyring
cp ./keys/<id>.pub.raw <module>/vdlu/keyring/<id>.pub
```

Keyring bersifat stabil lintas release (ia hanya berubah pada rotasi kunci): pada sebuah
re-vendor, **verifikasi, jangan timpa** ia.

## 4. Tulis config

Kirim `config.default` di `<module>/vdlu/` (menyemai `config` Tier-2 pada run pertama):

```
auto_on_reboot=1
auto_on_webui_open=1
source=https://<user>.github.io/<repo>/<module>
channel=stable
profile=hardened        # feed publik: tanda tangan wajib, downgrade diblokir
net_policy=any
pubkey_dir=keyring
```

Gunakan `profile=trusted` hanya untuk sumber `file://`/SSH privat (verify best-effort;
sha256 setiap blob tetap diperiksa). Nilai apa pun selain literal `trusted` diperlakukan
sebagai `hardened` (fail-closed).

## 5. Kaitkan trigger

**Saat reboot** (`auto_on_reboot`): panggil engine pre-zygote dari `post-fs-data.sh`
sehingga file yang di-stage (sebuah `.so`, sebuah overlay `/system`, sebuah `sepolicy.rule`)
ditukar masuk tanpa reboot tambahan:

```sh
# <module>/post-fs-data.sh
MODDIR=${0%/*}
sh "$MODDIR/vdlu/update.sh" boot
```

**Saat WebUI dibuka** (`auto_on_webui_open`): kaitkan panel Updates drop-in di
`webroot/index.html` Anda:

```html
<link rel="stylesheet" href="vdlu.css">
<script src="vdlu.js"></script>
<script>
  VDLU.init({
    moduleDir: '/data/adb/modules/' + MODID,
    vdluDir:   '/data/adb/' + MODID + '/vdlu',
    modid:     MODID,
    module:    'YourModule'
  });
  VDLU.onWebUIOpen();                                             // mengevaluasi journal + banner + auto_on_webui_open
  VDLU.mountUpdatesPanel(document.getElementById('b-updates'));  // tab "Updates"
</script>
```

(`vdlu.js` / `vdlu.css` di-vendor dari `webui/`; sebuah terjemahan dapat ditambahkan dengan
`i18n: window.VDLU_I18N_<LANG>`.)

## 6. Tandatangani feed di workflow release Anda

Setiap release, pack pohon modul final dan tandatangani manifest. Simpan kunci privat di mesin
operator, tidak pernah di CI:

```sh
producer/vdlu-pack  <module>  ./out  <module> <versionCode> --version-name v<versionCode> --channel stable \
                    [--prev ./prev/manifest.json]        # delete[] = path yang hilang sejak prev
producer/vdlu-sign  ./out/manifest.json  ./keys/<id>.pem  <id>
# publikasikan ./out/{manifest.json,blobs/} ke <source>
```

## 7. Kirim baseline

Hasilkan `baseline.json` atas pohon yang dikirim dan tempatkan di `<module>/vdlu/baseline.json`.
Ia menyemai `current.json` pada instalasi segar sehingga perangkat lahir "terkini" (tanpa
re-fetch). Ia adalah **benih lokal yang dipercaya**: tanpa tanda tangan dan tanpa kunci, sehingga CI
dapat membangunnya tanpa pernah menyentuh kunci penandatanganan:

```sh
producer/vdlu-pack  <module>  ./seed  <module> <versionCode> --version-name v<versionCode>
cp ./seed/manifest.json <module>/vdlu/baseline.json
```

Tidak fatal jika tidak ada (perangkat cukup mulai dari `0` pada pembaruan pertama).

---

Itulah keseluruhan adopsi. `sh -n <module>/vdlu/update.sh` harus lolos; uji producer dan engine
ujung-ke-ujung seperti ditunjukkan di [`PRODUCER.md`](PRODUCER.md) dan README akar sebelum Anda
mengirim.

<!-- doc-footer -->

---

> _Dokumentasi ini dibuat dengan Claude (Anthropic) dan dikelola oleh VD171. Koreksi dan perbaikan dipersilakan; lihat [CONTRIBUTING.md](CONTRIBUTING.md)._
