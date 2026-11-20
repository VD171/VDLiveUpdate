# Quick Start

Ini adalah checklist adopsi: cara men-vendor **VDLiveUpdate (VDLU)** ke dalam
modul KernelSU / APatch / Magisk. VDLU bukan modul itu sendiri. Ia diletakkan di
`<module>/vdlu/` dan dikirim di dalam zip modul Anda, sehingga modul yang terpasang dapat
memperbarui dirinya tanpa flash dari feed yang ditandatangani yang Anda publikasikan.

Di sepanjang teks, ganti `<id>` dengan id signing-key Anda, `<abi>` dengan
ABI perangkat yang Anda kirim (`arm64-v8a`, `armeabi-v7a`, `x86_64`, `x86`), dan `<module>`
dengan tree modul Anda.

Untuk rasional di balik setiap bagian, lihat [[Engine]], [[Producer]], [[WebUI]] dan
[[Security and Trust Model]].

## Tata letak `vdlu/` di dalam modul

Ini adalah tree persis yang dibawa modul Anda setelah adopsi:

```
<module>/
|-- module.prop
|-- post-fs-data.sh            # pre-zygote trigger: sh "$MODDIR/vdlu/update.sh" boot
|-- webroot/
|   `-- index.html             # your WebUI, wiring the Updates panel (step 5)
`-- vdlu/
    |-- update.sh              # the engine (vendored byte-for-byte)
    |-- vdlu-verify            # ed25519 verify shim (device-side, no openssl)
    |-- verify/
    |   `-- <abi>/ed25519-mini # per-ABI verifier binary
    |-- keyring/
    |   `-- <id>.pub           # RAW 32-byte public key (NEVER the PEM)
    |-- config.default         # profile + source + automation defaults
    `-- baseline.json          # install seed (unsigned, keyless)
```

State mutable engine (`config`, `current.json`, journal, lock, blob cache)
hidup di Tier-2 di `/data/adb/<modid>/vdlu/`, di luar direktori modul.
`config.default` men-seed `config` Tier-2 itu pada run pertama. Lihat [[Engine]] untuk
tata letak state yang lengkap.

## 1. Vendor engine

Salin engine, verify shim dan biner verifier per-ABI ke dalam
`<module>/vdlu/`:

```sh
mkdir -p <module>/vdlu/verify
cp engine/update.sh   <module>/vdlu/update.sh
cp engine/vdlu-verify <module>/vdlu/vdlu-verify
cp -r verify/<abi>    <module>/vdlu/verify/<abi>    # ed25519-mini per ABI
```

Kirim hanya ABI yang Anda dukung. `customize.sh` Anda dapat memangkas `verify/` menjadi
ABI perangkat pada saat install.

## 2. Buat signing key (satu kali)

```sh
producer/vdlu-keygen <id> ./keys
```

Ini memancarkan tiga file:

- `<id>.pem` - private key. Jaga agar tetap jauh dari setiap perangkat dan di luar push repo
  atau secret CI mana pun.
- `<id>.pub` - PEM public key. Sisi PC saja (dipakai oleh `vdlu-sign`).
- `<id>.pub.raw` - RAW 32-byte public key, untuk keyring perangkat.

Lihat [[Security and Trust Model]] untuk mengapa pemisahan itu penting.

## 3. Sematkan raw public key

Keyring perangkat menyimpan key **RAW 32-byte**, tidak pernah PEM. `ed25519-mini`
tidak dapat membaca PEM, jadi menyalin PEM di sini merusak verifikasi di perangkat:

```sh
mkdir -p <module>/vdlu/keyring
cp ./keys/<id>.pub.raw <module>/vdlu/keyring/<id>.pub
```

Keyring stabil lintas rilis: ia hanya berubah pada rotasi key. Pada
re-vendor, **verifikasi ia, jangan timpa ia**.

## 4. Tulis config

Kirim `config.default` di `<module>/vdlu/`. Ia men-seed `config` Tier-2 pada run
pertama:

```
auto_on_reboot=1
auto_on_webui_open=1
source=https://<user>.github.io/<repo>/<module>
channel=stable
profile=hardened        # public feed: signature mandatory, downgrade blocked
net_policy=any
pubkey_dir=keyring
```

Gunakan `profile=trusted` hanya untuk sumber `file://` atau SSH privat (verify
best-effort di sana, tetapi sha256 setiap blob tetap diperiksa). Nilai apa pun selain
literal `trusted` diperlakukan sebagai `hardened`, fail-closed. Lihat
[[Security and Trust Model]] untuk semantik profil yang lengkap.

## 5. Sambungkan trigger

**On reboot** (`auto_on_reboot`): panggil engine pre-zygote dari
`post-fs-data.sh`, sehingga file kelas reboot yang di-stage (sebuah `.so`, sebuah overlay `/system`,
sebuah `sepolicy.rule`) di-swap masuk tanpa reboot tambahan:

```sh
# <module>/post-fs-data.sh
MODDIR=${0%/*}
sh "$MODDIR/vdlu/update.sh" boot
```

**On WebUI open** (`auto_on_webui_open`): sambungkan panel Updates drop-in di
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
  VDLU.onWebUIOpen();                                            // journal + banner + auto_on_webui_open
  VDLU.mountUpdatesPanel(document.getElementById('b-updates'));  // the "Updates" tab
</script>
```

`vdlu.js` dan `vdlu.css` di-vendor dari `webui/`. Sebuah terjemahan dapat ditambahkan
dengan `i18n: window.VDLU_I18N_<LANG>`. Lihat [[WebUI]] untuk kontrak panel.

## 6. Tandatangani feed dalam workflow release Anda

Setiap rilis, pack tree modul final dan tandatangani manifest. Jaga private
key di mesin operator, tidak pernah di CI:

```sh
producer/vdlu-pack  <module>  ./out  <module> <versionCode> \
                    --version-name v<versionCode> --channel stable \
                    [--prev ./prev/manifest.json]      # delete[] = paths gone since prev
producer/vdlu-sign  ./out/manifest.json  ./keys/<id>.pem  <id>
# publish ./out/{manifest.json,blobs/} to <source>
```

`vdlu-pack` content-addressed dan dedup, jadi publikasi bersifat inkremental:
blob yang tidak berubah tidak pernah di-push ulang. Lihat [[Producer]] dan [[Feed Format]].

## 7. Kirim baseline

Hasilkan `baseline.json` atas tree yang dikirim dan tempatkan di
`<module>/vdlu/baseline.json`. Ia men-seed `current.json` pada instalasi baru, sehingga
perangkat lahir "current" dan tidak me-re-fetch versi yang dikirimnya sendiri. Ia adalah
**seed lokal tepercaya**: tak-bertanda-tangan dan keyless, jadi CI dapat membangunnya tanpa pernah
menyentuh signing key:

```sh
producer/vdlu-pack  <module>  ./seed  <module> <versionCode> --version-name v<versionCode>
cp ./seed/manifest.json <module>/vdlu/baseline.json
```

Ia tidak fatal jika absen: perangkat cukup mulai dari versi `0` pada
update pertama.

---

Itulah keseluruhan adopsi. Sebelum Anda mengirim, `sh -n <module>/vdlu/update.sh`
harus lolos, dan Anda sebaiknya menguji producer dan engine dari ujung ke ujung seperti ditunjukkan di
[[Contributing]] dan [[Producer]].
