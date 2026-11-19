> **Languages:** [English](../WEBUI.md) · [العربية](../ar/WEBUI.md) · [Čeština](../cs/WEBUI.md) · [Deutsch](../de/WEBUI.md) · [Español](../es/WEBUI.md) · [فارسی](../fa/WEBUI.md) · [Français](../fr/WEBUI.md) · [हिन्दी](../hi/WEBUI.md) · Bahasa Indonesia · [Italiano](../it/WEBUI.md) · [日本語](../ja/WEBUI.md) · [한국어](../ko/WEBUI.md) · [Nederlands](../nl/WEBUI.md) · [Polski](../pl/WEBUI.md) · [Português](../pt/WEBUI.md) · [Русский](../ru/WEBUI.md) · [Svenska](../sv/WEBUI.md) · [ไทย](../th/WEBUI.md) · [Türkçe](../tr/WEBUI.md) · [Українська](../uk/WEBUI.md) · [Tiếng Việt](../vi/WEBUI.md) · [中文](../zh/WEBUI.md)

---

# VDLU - Widget WebUI (pembaruan flashless)

Antarmuka VDLU (VD Live Update) untuk WebUI root manager KernelSU/APatch. Vanilla JS, tanpa framework, tanpa
build, tanpa CDN. Drop-in: `index.html` host memuat 2 file dan memanggil API.

Konvergensi: `INTERFACES.md` §9 (WEBUI↔ENGINE), §4 (journal.json), §5 (config).

## File

| File | Apa |
|---|---|
| `vdlu.js` | komponen - mengekspos `window.VDLU` |
| `vdlu.css` | toast progres, banner reboot, tab "Updates" (tema gelap, mewarisi variabel host) |
| `demo.html` | halaman standalone dengan `ksu.exec` yang di-mock - terbuka di browser, tanpa perangkat |

## Integrasi ke dalam `index.html` host

```html
<link rel="stylesheet" href="vdlu.css">
...
<script src="vdlu.js"></script>
<script>
  VDLU.init({
    moduleDir: '/data/adb/modules/' + MODID,   // $MODULE_DIR
    vdluDir:   '/data/adb/' + MODID + '/vdlu',  // $VDLU_DIR  (Tier-2, di luar direktori modul)
    modid:     MODID,
    module:    'Demo',                     // nama yang ditampilkan di toast (default: modid)
    exec:   ex,          // (opsional) wrapper ksu.exec host; lihat di bawah
    toast:  toast,       // (opsional) toast transien host
    confirm: askConfirm  // (opsional) modal konfirmasi host
  });

  VDLU.onWebUIOpen();                          // saat load: mengevaluasi journal + banner + auto_on_webui_open
  VDLU.mountUpdatesPanel(document.getElementById('b-updates'));  // ketika tab "Updates" dibuka
</script>
```

### Apa yang harus didefinisikan host

- **`moduleDir`** = `$MODULE_DIR` (`/data/adb/modules/<modid>`), tempat engine di-vendor
  (`vdlu/update.sh`).
- **`vdluDir`** = `$VDLU_DIR` (`/data/adb/<modid>/vdlu`), state Tier-2 (`journal.json`, `config`,
  `cancel`).
- **`modid`** = id modul.

Widget merakit perintah engine yang sudah membawa env kontrak (§1):
`VDLU_DIR=… MODULE_DIR=… MODID=… sh $MODULE_DIR/vdlu/update.sh <cmd>`. `run`/`resume` berjalan di
**background** (`(… &)`), dan progres dibaca oleh poll ringan (~1s) dari `cat $VDLU_DIR/journal.json`.

### `exec`/`toast`/`confirm` (opsional)

Jika dihilangkan, widget menggunakan miliknya sendiri:
- **`exec(cmd)`** harus mengembalikan `Promise` yang **resolve** dengan stdout (rc 0) dan **reject** dengan stderr
  (rc≠0) - persis tanda tangan `ex()` milik `webroot/index.html` Demo. Fallback internal memanggil
  `ksu.exec(cmd, '{}', cb)` dengan kontrak yang sama.
- **`toast(msg)`** = notifikasi transien singkat (fallback menyuntikkan mini-toast-nya sendiri).
- **`confirm(title,msg,ok,danger,fn)`** = sebuah modal (saat ini hanya digunakan oleh host; widget tidak membutuhkan
  konfirmasi dalam alur apa pun).

Meneruskan milik host sendiri membuat widget berbicara melalui antrean terserialisasi dan visual yang SAMA seperti sisanya dari
WebUI.

## API publik (`window.VDLU`)

| Fungsi | Melakukan |
|---|---|
| `init(opts)` | mengonfigurasi (lihat di atas). Mengembalikan `window.VDLU`. |
| `onWebUIOpen()` | panggil saat load: menampilkan banner jika `reboot_pending`; menawarkan **Resume** jika ada transaksi non-terminal; dengan `auto_on_webui_open=1` ia menjalankan **auto-update SENYAP** (sebuah `check()` senyap terlebih dahulu; hanya memicu `run`+toast persisten jika `update && fetch>0` - terkini/ahead = hasil inline di panel, nol toast). |
| `mountUpdatesPanel(el)` | merender tab "Updates" di dalam `el` (id string atau elemen): **Check for update**, **Update now**, toggle `auto_on_webui_open`/`auto_on_reboot`, field boot-retry, select **Network** (`net_policy`: Wi-Fi+mobile / Wi-Fi-saja / mobile-saja) dan field `source`/`channel`/`profile`. |
| `check()` | menjalankan `update.sh check`; `Promise<{update,from,to,fetch,reboot}>`. |
| `startUpdate()` | memicu `run` di background + sebuah toast progres dengan **Cancel**. |
| `cancel()` | membuat `$VDLU_DIR/cancel` (engine berhenti pada titik aman). |
| `resume()` | `update.sh resume` + toast (melanjutkan fase saat ini). |
| `refreshBanner()` | mengevaluasi ulang banner pending-reboot yang persisten. |

Toast (overlay sudut, non-blocking) dan banner (atas, persisten) disuntikkan oleh widget ke dalam
`document.body` - host tidak membutuhkan HTML untuk mereka. Tab "Updates" adalah satu-satunya titik yang dialokasikan host (sebuah
`<div>` kosong).

### Alur state yang direfleksikan toast (journal.json, §4)

`PLANNED → FETCHING → FETCHED → APPLYING → APPLIED_LIVE → (PENDING_REBOOT | DONE)`; `ERROR` kapan saja. Toast
menampilkan **sebuah bar + `phase done/total · current · bytes`**. Terminal:
- **`DONE`** → toast hijau "v&lt;target&gt; diterapkan".
- **`PENDING_REBOOT`** (atau `reboot_pending=true`) → toast hijau + **banner persisten** "⚠️ Reboot untuk
  mengaktifkan `.so` baru (vX)".
- **`ERROR`** → toast merah dengan alasan (`journal.error`/stderr). Tidak pernah memalsukan keberhasilan.
- **Cancelled** → "cancelled - N/M, dapat dilanjutkan" + sebuah tombol **Resume**.

## Menjalankan demo

Buka `demo.html` di browser (`xdg-open webui/demo.html`). `ksu.exec` yang di-mock menyimulasikan `update.sh` dan
`journal.json` yang berkembang; tombol-tombol beralih antara skenario **LIVE→DONE**, **reboot_pending**, **error di tengah**
dan **dapat dibatalkan**. Ia adalah `vdlu.js`/`vdlu.css` yang sama seperti di perangkat.

## i18n (bahasa)

String widget default ke **bahasa Inggris** (netral untuk modul publik multi-bahasa). Host menimpa
kunci apa pun dengan meneruskan sebuah map di `init`:

```html
<script src="i18n/pt-BR.js"></script>   <!-- mendefinisikan window.VDLU_I18N_PT_BR -->
<script>VDLU.init({ exec: ex, moduleDir: MOD, vdluDir: VDL, modid: 'x', i18n: window.VDLU_I18N_PT_BR });</script>
```

- Merge **parsial** boleh: sebuah kunci yang hilang jatuh kembali ke default bahasa Inggris.
- Kunci phase/state adalah `ph_<phase>` / `st_<STATE>`; sisanya datar (`cancel`, `updateNow`, …).
- Map kunci lengkap = objek `DEFAULT_I18N` di `vdlu.js` (juga diekspos sebagai `VDLU.i18n`).
- Sebuah terjemahan siap disediakan sebagai contoh kerja: `i18n/pt-BR.js`. Bahasa baru = sebuah file
  `i18n/<lang>.js` dalam cetakan yang sama, atau host membangun map dari sistem i18n-nya sendiri.

## Sumber tunggal (paritas lintas modul)

`vdlu.js`/`vdlu.css` ini adalah **salinan kanonik**. Setiap modul yang menyematkan widget
**me-re-vendor** salinan ini byte-per-byte ke dalam `webroot/`-nya - ia **tidak pernah** mengedit
miliknya sendiri in place. Sebuah fitur widget baru lahir di sini dan mengalir ke bawah melalui re-vendor; sebaliknya menghasilkan drift
senyap (telah terjadi dalam praktik: sebuah salinan yang di-vendor tertinggal dan kehilangan `net_policy`, toast
`DEFERRED`, dan field `boot_retry`).

Penjaga: [`../tools/webui-parity.sh`](../../tools/webui-parity.sh) menemukan setiap salinan di pohon sumber dan menandai
yang menyimpang dari yang kanonik (hanya `vdlu.js`/`vdlu.css`; keyring adalah "verifikasi, bukan salin").

```sh
tools/webui-parity.sh         # laporan; keluar dengan 1 jika ada drift
tools/webui-parity.sh --fix   # me-re-vendor yang menyimpang dari yang kanonik
```

> 🪤 Keyring (`keyring/<id>.pub` RAW 32B) dan engine (`vdlu/update.sh`) memiliki kadens re-vendor-nya sendiri;
> penjaga ini mencakup **hanya widget WebUI**.

<!-- doc-footer -->

---

> _Dokumentasi ini dibuat dengan Claude (Anthropic) dan dikelola oleh VD171. Koreksi dan perbaikan dipersilakan; lihat [CONTRIBUTING.md](CONTRIBUTING.md)._
