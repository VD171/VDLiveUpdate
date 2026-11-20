> **Languages:** [English](../ENGINE.md) · [العربية](../ar/ENGINE.md) · [Čeština](../cs/ENGINE.md) · [Deutsch](../de/ENGINE.md) · [Español](../es/ENGINE.md) · [فارسی](../fa/ENGINE.md) · [Français](../fr/ENGINE.md) · [हिन्दी](../hi/ENGINE.md) · Bahasa Indonesia · [Italiano](../it/ENGINE.md) · [日本語](../ja/ENGINE.md) · [한국어](../ko/ENGINE.md) · [Nederlands](../nl/ENGINE.md) · [Polski](../pl/ENGINE.md) · [Português](../pt/ENGINE.md) · [Русский](../ru/ENGINE.md) · [Svenska](../sv/ENGINE.md) · [ไทย](../th/ENGINE.md) · [Türkçe](../tr/ENGINE.md) · [Українська](../uk/ENGINE.md) · [Tiếng Việt](../vi/ENGINE.md) · [中文](../zh/ENGINE.md)

---

# Engine VDLU (`update.sh`)

Klien pembaruan flashless dan inkremental untuk modul KSU/Magisk. Mengimplementasikan
siklus `DIFF -> FETCH -> APPLY -> COMMIT` sebagai transaksi yang dapat dilanjutkan. Menyesuaikan diri dengan `INTERFACES.md` (hukum
konvergensi).

sh POSIX murni (mksh/busybox/toybox). **RAMPING:** ia hanya bergantung pada toybox (`sha256sum`/`gzip`/`base64`/`date`) +
`ed25519-mini` yang tertanam (verify ed25519; **tanpa openssl di perangkat**) + `curl` statis yang **diambil** pada
pembaruan https pertama (WebUI melakukan `fetch()`, menyimpannya di Tier-2, dan `install-tool` memverifikasi
tanda tangan+hash-nya SEBELUM menggunakannya). `file://` tidak membutuhkan curl. Nol ketergantungan pada `jq`.

## Invokasi

```sh
VDLU_DIR=/data/adb/<mod>/vdlu MODULE_DIR=/data/adb/modules/<mod> MODID=<mod> \
  sh $MODULE_DIR/vdlu/update.sh <cmd>
```

`rc 0` = ok; `rc != 0` = error (alasan di stderr). `vdlu-verify` disediakan oleh komponen lain
(tanda tangan di `INTERFACES.md §6`); engine hanya memanggilnya.

| cmd | melakukan |
|---|---|
| `check` | DIFF hanya-baca; mencetak `{"update":bool,"from":N,"to":M,"fetch":K,"reboot":bool}`; tidak mengubah apa pun |
| `run` | siklus LIVE penuh + men-stage REBOOT-hard; menghormati `cancel`; progres di `journal.json` |
| `resume` | melanjutkan transaksi yang tertunda (`target.json`) dari fase saat ini; idempoten; **tidak** men-swap `.so` |
| `boot` | mode pre-zygote: resume **+** men-swap `staged/*.vdlu-new` -> menutup `PENDING_REBOOT`->`DONE`. Tanpa transaksi yang tertunda, ia menjalankan siklus segar dan menerapkan segalanya (termasuk `.so`) dalam satu boot |
| `status` | mencetak `journal.json` (atau `{"state":"idle"}`) |
| `cancel` | membuat `$VDLU_DIR/cancel`; sebuah `run` yang sedang berlangsung berhenti pada titik aman berikutnya |

## Mesin state (journal.json)

```
PLANNED -> FETCHING -> FETCHED -> APPLYING -> APPLIED_LIVE -> (PENDING_REBOOT | DONE)
```

`DONE` hanya setelah re-hash SEGALANYA cocok. Jika ada REBOOT-hard yang di-stage ⇒ `PENDING_REBOOT` (tidak pernah
`DONE` palsu). `ERROR` pada kegagalan apa pun, tanpa merusak modul (file LIVE yang diterapkan dikembalikan
dari `rollback/<v>/`; tidak ada yang "setengah-diterapkan sambil berbohong tentangnya"). Jalan keluar benign dari fase `fetch`: **`DEFERRED`** -
unduhan ditunda oleh `net_policy` (jaringan tidak diizinkan); plan/target tetap ada dan dilanjutkan pada
check/boot berikutnya (WebUI menampilkan toast info biru "menunggu jaringan X", bukan error).

## Jaminan ketat

- **FETCH:** diatur oleh `net_policy` (any/wifi/mobile; hanya http/https, `file://` tidak pernah) - jaringan yang tidak diizinkan ⇒
  `DEFERRED` (dapat dilanjutkan), tanpa menghabiskan data. Mengunduh hanya yang hilang ke `<sha>.part` (curl dengan
  `--connect-timeout` + `--speed-time`, tidak pernah menggantung), mendekompresi `gz` (toybox `gunzip`), memeriksa `sha256sum` ==
  manifest, `mv` atomik ke `blobs/<sha>`. Sebuah blob cache+ok dilewati. Ia dapat menyemai blob dari file
  lokal yang tidak berubah (dedup/offline). **3 kegagalan pada blob yang sama = fase dibatalkan tanpa menerapkan apa pun.** Ia
  baru menjadi `FETCHED` ketika SEMUA blob dari plan ada+terverifikasi.
- **APPLY** (hanya dari `FETCHED`): `live`/`soft` -> backup ke `rollback/<v>/` -> `.vdlu-tmp` -> `chmod` -> verify ->
  `rename` atomik. `reboot` -> mematerialisasikan ke `staged/<path>.vdlu-new` (TIDAK menyentuh inode live).
  `delete[]` -> backup -> menghapus. Idempoten (sebuah file yang sudah pada hash target dilewati).
- **COMMIT:** re-hash setiap `live`/`soft`; baru kemudian menulis `current.json`. Dengan file yang di-stage ⇒
  `PENDING_REBOOT`. `boot` melakukan `mv -f staged/....vdlu-new $MODULE_DIR/<path>` (pre-zygote) + memverifikasi ulang +
  `DONE`.
- **cancel:** diperiksa di antara file (titik aman); menghapus `.vdlu-tmp`/`.part` yang berjalan, menghapus `cancel`,
  meninggalkan journal dalam keadaan dapat dilanjutkan (`cancelled:true`, `error:null`).
- **mkdir-lock `$VDLU_DIR/lock.d`** menserialisasi (flock tidak praktis di toybox; pemulihan stale berdasarkan PID). 
  boot-retry SABAR tidak menahan lock selama menunggu (`acquire_lock_try`+release di antara percobaan) maupun
  wakelock - hemat baterai. Sebuah crash/jaringan/reboot di tengah jalan -> `resume`/`boot` melanjutkan.
- **profile=hardened** ⇒ `vdlu-verify` wajib atas manifest SEBELUM digunakan; kegagalan = abort; downgrade diblokir
  (versi monotonik). **trusted** ⇒ verify bersifat best-effort, tetapi hash setiap blob SELALU diperiksa.
- **allowlist kunci module-update (kedua profiles):** `verify_manifest` menolak, fail-closed, setiap manifest yang `key_id`-nya tidak ada dalam allowlist `key_id` yang dikonfigurasi (lihat INTERFACES §5/§6) SEBELUM pubkey dipilih, sehingga kunci kepercayaan lebih rendah yang hanya berada di keyring (mis. kunci fingerprint-feed) tidak pernah dapat menandatangani pembaruan flashless root. Aman-secara-default saat tidak disetel: keyring kunci tunggal = hanya satu kunci itu; keyring multi-kunci = ditolak sampai `key_id` dipin.
- Menurun secara anggun: biner hilang / jaringan mati / disk penuh -> error jelas di stderr + `state:ERROR` di
  journal, tanpa merusak modul.

## Parsing JSON tanpa jq

Sebuah flattener gaya gron di `awk` (POSIX murni: `substr`/`index`/`gsub`/`split`/`printf` + lokal yang diteruskan sebagai
parameter) men-tokenisasi manifest karakter-demi-karakter dan memancarkan satu baris `path<TAB>value` per daun skalar
(`files/0/sha256<TAB>ab..`, `version<TAB>6`, `delete/0<TAB>etc/x`). Tangguh terhadap JSON ringkas ATAU pretty-printed.
`sh` mengonsumsinya dengan `grep`/`cut`; plan per-file disusun ulang di `awk` ke-2 menjadi TSV
(`class st mode enc sha size path`), yang menjadi `$VDLU_DIR/plan.tsv`.

## File state (di `$VDLU_DIR`, Tier-2)

| file | peran |
|---|---|
| `config` | key=value (`source`/`profile`/`channel`/`net_policy`/`key_id`/`boot_retry_*`/…; lihat INTERFACES §5) |
| `current.json` | manifest versi AKTIF (basis diff); tidak ada = belum pernah diperbarui |
| `target.json` | manifest yang dipatok dari transaksi berjalan (keberadaan = transaksi aktif); menjadi `current.json` saat `DONE` |
| `plan.tsv` / `plan.del` | plan + progres per-file (st) / path untuk dihapus |
| `journal.json` | progres untuk WebUI (diregenerasi pada setiap transisi) |
| `blobs/<sha256>` | cache konten asli yang terverifikasi |
| `rollback/<version>/<path>` | backup file yang ditimpa (undo; menyimpan 3 terakhir) |
| `staged/<path>.vdlu-new` | REBOOT-hard menunggu swap saat boot |
| `lock.d/` | mkdir-lock (flock tidak praktis di toybox; pemulihan stale berdasarkan PID) |
| `tools/<abi>/curl` | curl statis yang diambil (bootstrap ramping); bertahan lintas pembaruan |
| `cancel` | permintaan pembatalan |

<!-- doc-footer -->

---

> _Dokumentasi ini dibuat dengan Claude (Anthropic) dan dikelola oleh VD171. Koreksi dan perbaikan dipersilakan; lihat [CONTRIBUTING.md](CONTRIBUTING.md)._
