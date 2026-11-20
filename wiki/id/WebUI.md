# WebUI

VDLU mengirim widget WebUI drop-in opsional: panel "Updates" kecil untuk WebUI root-manager KernelSU atau APatch. Ia memberi pengguna tombol Check, tombol Update now, toast progres live dengan cancel, banner reboot, dan panel settings, semuanya tanpa pengguna pernah menyentuh terminal.

Ia **vanilla JavaScript**: tanpa framework, tanpa build step, tanpa CDN. Tiga file:

| File | Apa itu |
|---|---|
| `vdlu.js` | widget; mengekspos `window.VDLU` |
| `vdlu.css` | style untuk toast, banner dan panel (tema gelap, mewarisi variabel CSS host) |
| `demo.html` | halaman mandiri yang memock bridge perangkat sehingga seluruh UI berjalan di browser biasa |

Widget ini sepenuhnya opsional. [[Engine]] berjalan baik-baik saja sendiri dari trigger boot; WebUI hanyalah wajah ramah di atasnya. Lihat [[Quick Start]] untuk menyambungkannya ke dalam modul.

---

## Bagaimana UI berbicara dengan engine: bridge `ksu.exec`

Widget tidak pernah melakukan apa pun yang privileged sendiri. Ia membangun perintah shell dan menyerahkannya ke bridge `ksu.exec` root manager, yang menjalankannya sebagai root dan mengembalikan stdout / stderr / exit code. Semua yang ditampilkan panel dibaca kembali dari file yang ditulis engine.

Widget membungkus bridge itu dalam satu fungsi `exec(cmd)` yang mengembalikan sebuah `Promise`:

- **resolve** dengan stdout ketika perintah exit 0
- **reject** dengan stderr (atau `rc=N`) selain itu

Setiap perintah membawa environment dari kontrak, dirakit oleh widget:

```
VDLU_DIR=... MODULE_DIR=... MODID=... sh $MODULE_DIR/vdlu/update.sh <cmd>
```

Beberapa panggilan konkret:

- **Memulai update:** `update.sh run` diluncurkan di **background** (`(... &)`) sehingga UI tidak pernah terblokir oleh download yang panjang.
- **Membaca progres:** poll ringan (sekitar sekali per detik) dari `cat $VDLU_DIR/journal.json`.
- **Cancel:** `touch $VDLU_DIR/cancel` (engine berhenti di titik aman berikutnya).
- **Config:** membaca dan menulis `$VDLU_DIR/config` (key=value), mempertahankan urutan dan key tak dikenal dan hanya menyentuh key yang diubah pengguna.

Jika host meneruskan helper `exec`, `toast` dan `confirm`-nya sendiri ke `init()`, widget merutekan melalui antrean perintah yang terserialisasi dan visual milik host sendiri, jadi ia terlihat dan berperilaku seperti sisanya dari WebUI itu. Jika keduanya dihilangkan, widget jatuh ke memanggil `ksu.exec` secara langsung dan menyuntikkan mini-toast-nya sendiri.

---

## Toast progres (dengan cancel)

Begitu sebuah update berjalan, widget menampilkan toast sudut non-blocking dan mem-poll `journal.json`. Toast mencerminkan state machine engine:

```
PLANNED -> FETCHING -> FETCHED -> APPLYING -> APPLIED_LIVE -> (PENDING_REBOOT | DONE)
```

Ia merender progress bar ditambah satu baris `phase done/total - current file - bytes`, dan membawa tombol **Cancel** sepanjang waktu. Setiap state terminal mendapat perlakuannya sendiri:

- **DONE** -> toast hijau, "vX applied - all verified".
- **PENDING_REBOOT** -> toast hijau ditambah banner reboot yang persisten (di bawah).
- **ERROR** -> toast merah dengan alasan dari `journal.error` atau stderr, menawarkan Retry. Ia tidak pernah memalsukan sukses.
- **Cancelled** -> toast amber, "cancelled - N/M applied, resumable", menawarkan **Resume**.
- **DEFERRED** -> toast info biru yang lembut, "download deferred, waiting for the allowed network". Ini adalah tunggu kebijakan jaringan yang benign, bukan error; ia dilanjutkan pada check atau boot berikutnya di jaringan yang tepat.

Poll bersifat defensif. Journal yang tertulis setengah (engine menulis secara bersamaan) diabaikan untuk tick itu alih-alih salah di-parse. Jika journal menjadi absen setelah progres terlihat, itu berarti commit menghapusnya: widget melaporkan DONE. Jika journal absen dari awal selama 8 tick, ia melaporkan "no response". Dan jika journal membeku pada nilai yang sama selama 20 tick, widget memeriksa `lock.d` engine: jika lock hidup itu hanyalah fetch single-blob yang lambat dan toast terus menunggu; jika lock mati run mati di tengah jalan, jadi widget memunculkan error dengan tombol Resume alih-alih berputar pada "updating" selamanya.

---

## Banner reboot

Beberapa file tidak dapat di-swap pada sistem live: sebuah `.so`, sebuah overlay `/system`, sebuah `sepolicy.rule`. Engine men-stage itu dan menandai transaksi `PENDING_REBOOT`. Widget lalu menampilkan **banner atas yang persisten**: "Reboot to activate the new `.so` (vX)". Ia tetap sampai file yang di-stage di-swap pada boot berikutnya. Saat WebUI dibuka banner dievaluasi ulang dari journal, jadi pengguna yang menutup dan membuka kembali UI tetap melihatnya. Lihat [[Reboot Handling]] untuk apa yang terjadi saat boot.

Perhatikan banner bertumpu pada state terminal `PENDING_REBOOT`, bukan pada flag `reboot_pending` (yang menjadi true segera setelah `.so` mana pun memasuki plan). Itu menjaga banner agar tidak muncul di tengah run sebelum apa pun benar-benar di-stage.

---

## Panel "Updates": toggle per-kategori independen

`mountUpdatesPanel(el)` merender panel settings ke dalam `<div>` kosong yang disediakan host. Ia memiliki tiga seksi, dan setiap kontrol independen dan menyimpan sendiri-sendiri:

**Actions**
- **Check for updates** -> menjalankan `check`, menampilkan hasil inline (up to date / lebih baru dari feed / update tersedia dengan jumlah file dan tag reboot).
- **Update now** -> memicu `run` ditambah toast progres.

**Automation** (toggle independen, masing-masing ditulis ke `config` saat ia dibalik)
- **On WebUI open** (`auto_on_webui_open`) -> menjalankan update senyap ketika UI dibuka.
- **On reboot** (`auto_on_reboot`) -> menerapkan di pre-zygote saat boot.
- **Boot retry every (s)** dan **Boot retry up to (min)** -> field numerik untuk mencoba ulang fetch manifest ketika perangkat boot offline.

**Source**
- `source` (URL feed), `channel` (stable / canary), `profile` (trusted / hardened), dan sebuah pilihan **Network** yang memetakan ke `net_policy` (Wi-Fi + mobile / Wi-Fi only / mobile only).

Toggle dan field numerik menyimpan segera dan kembali secara visual jika penulisan gagal. Field teks dan select di seksi Source menandai dirinya dirty dan menyimpan bersama pada tombol Save eksplisit. Panel hanya pernah menulis ulang key yang disentuh pengguna, jadi key config tak dikenal atau masa depan apa pun dipertahankan.

### Perilaku auto-open

`onWebUIOpen()` dipanggil saat host load. Ia mengevaluasi journal (menampilkan banner reboot atau menawarkan Resume untuk transaksi non-terminal yang ditinggalkan sesi sebelumnya), lalu, jika `auto_on_webui_open=1`, ia menjalankan `check()` yang **senyap** dulu. Toast progres persisten dan `run` yang sesungguhnya hanya memicu ketika ada download nyata untuk dilakukan (`update && fetch > 0`). Jika perangkat up to date atau lebih maju dari feed, hasilnya ditampilkan inline di panel dan tidak ada toast yang ditinggalkan di layar, sehingga auto-update senon-intrusif tombol manual.

---

## i18n (string per-bahasa)

Setiap string UI default ke **Inggris**, yang merupakan pilihan netral untuk modul publik multi-bahasa. Key map lengkap hidup dalam objek `DEFAULT_I18N` di `vdlu.js` (juga diekspos sebagai `VDLU.i18n`). Host menimpa subset key mana pun dengan meneruskan sebuah map ke `init({ i18n: ... })`:

```html
<script src="i18n/pt-BR.js"></script>   <!-- defines window.VDLU_I18N_PT_BR -->
<script>
  VDLU.init({ exec: ex, moduleDir: MOD, vdluDir: VDL, modid: 'x',
              i18n: window.VDLU_I18N_PT_BR });
</script>
```

- Sebuah map **parsial** tidak masalah: key yang hilang apa pun jatuh kembali ke default Inggris.
- Label phase dan state memakai key `ph_<phase>` dan `st_<STATE>`; sisanya adalah key datar seperti `cancel`, `updateNow`.
- Terjemahan yang dikerjakan (`i18n/pt-BR.js`) dikirim sebagai template; bahasa baru hanyalah file `i18n/<lang>.js` dalam bentuk yang sama, atau host membangun map dari sistem i18n-nya sendiri.

---

## demo.html: menjalankan UI tanpa perangkat

`demo.html` memock bridge `ksu.exec` sehingga `vdlu.js` dan `vdlu.css` yang persis sama berjalan di browser biasa, tanpa root dan tanpa ponsel:

```sh
xdg-open webui/demo.html
```

Mock menyimulasikan `update.sh` dan `journal.json` yang berkembang, dan tombol-tombolnya beralih di antara skenario: update live sampai DONE, penyelesaian `reboot_pending`, error di tengah jalan, dan run yang dapat di-cancel. Ini adalah cara tercepat untuk melihat dan mengiterasi UI, dan itulah yang Anda periksa sebelum men-vendor widget ke dalam modul.

---

## Menyambungkannya ke dalam modul (trigger WebUI-open)

`index.html` host memuat kedua file dan memanggil tiga fungsi:

```html
<link rel="stylesheet" href="vdlu.css">
<script src="vdlu.js"></script>
<script>
  VDLU.init({
    moduleDir: '/data/adb/modules/' + MODID,   // $MODULE_DIR (where the engine is vendored)
    vdluDir:   '/data/adb/' + MODID + '/vdlu',  // $VDLU_DIR  (Tier-2 state, outside the module dir)
    modid:     MODID,
    module:    'Demo',        // friendly name shown in the toast (default: modid)
    exec:   ex,               // optional: the host's ksu.exec wrapper
    toast:  toast,            // optional: the host's transient toast
    confirm: askConfirm       // optional: the host's modal
  });

  VDLU.onWebUIOpen();                          // the WebUI-open trigger: banner + auto-update eval
  VDLU.mountUpdatesPanel('b-updates');         // render the "Updates" tab into an empty div
</script>
```

Host hanya perlu menyediakan path Tier-2 dan mengalokasikan satu `<div>` kosong untuk panel; toast dan banner disuntikkan ke `document.body` oleh widget. `onWebUIOpen()` adalah trigger WebUI-open: itulah yang mengevaluasi banner reboot, menawarkan Resume pada transaksi yang terinterupsi, dan menjalankan auto-update senyap ketika `auto_on_webui_open` di-set.

### Sumber tunggal, di-re-vendor byte demi byte

`vdlu.js` dan `vdlu.css` adalah **salinan kanonik**. Modul yang menyematkan widget me-re-vendor file-file ini tanpa diubah ke dalam `webroot/`-nya; ia tidak pernah mengedit salinannya sendiri di tempat. Fitur baru lahir dalam file kanonik dan mengalir ke bawah lewat re-vendor. Mengedit salinan yang di-vendor menghasilkan drift senyap (itu pernah terjadi: salinan basi kehilangan `net_policy`, toast DEFERRED dan field boot-retry). Seorang parity guardian dalam source tree menemukan setiap salinan dan menandai atau me-re-vendor yang menyimpang, mencakup widget saja; keyring memiliki ritme verify-not-copy-nya sendiri.

---

### API publik (`window.VDLU`)

| Fungsi | Melakukan |
|---|---|
| `init(opts)` | mengkonfigurasi widget; mengembalikan `window.VDLU` |
| `onWebUIOpen()` | panggil saat load: banner, tawaran Resume, dan auto-update senyap |
| `mountUpdatesPanel(el)` | merender panel Updates ke dalam `el` (string id atau elemen) |
| `check()` | menjalankan `update.sh check`; `Promise<{update, from, to, fetch, reboot}>` |
| `startUpdate()` | memicu `run` di background ditambah toast progres dengan Cancel |
| `cancel()` | membuat `$VDLU_DIR/cancel` (engine berhenti di titik aman) |
| `resume()` | melanjutkan transaksi saat ini ditambah sebuah toast |
| `refreshBanner()` | mengevaluasi ulang banner pending-reboot yang persisten |

---

Lihat juga: [[Engine]] untuk perintah yang digerakkan widget, [[Quick Start]] untuk langkah adopsi penuh, dan [[Reboot Handling]] untuk apa yang ditunggu banner.
