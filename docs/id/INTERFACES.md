> **Languages:** [English](../INTERFACES.md) · [العربية](../ar/INTERFACES.md) · [Čeština](../cs/INTERFACES.md) · [Deutsch](../de/INTERFACES.md) · [Español](../es/INTERFACES.md) · [فارسی](../fa/INTERFACES.md) · [Français](../fr/INTERFACES.md) · [हिन्दी](../hi/INTERFACES.md) · Bahasa Indonesia · [Italiano](../it/INTERFACES.md) · [日本語](../ja/INTERFACES.md) · [한국어](../ko/INTERFACES.md) · [Nederlands](../nl/INTERFACES.md) · [Polski](../pl/INTERFACES.md) · [Português](../pt/INTERFACES.md) · [Русский](../ru/INTERFACES.md) · [Svenska](../sv/INTERFACES.md) · [ไทย](../th/INTERFACES.md) · [Türkçe](../tr/INTERFACES.md) · [Українська](../uk/INTERFACES.md) · [Tiếng Việt](../vi/INTERFACES.md) · [中文](../zh/INTERFACES.md)

---

# VDLU - Kontrak antarmuka (sambungan antar komponen)

**Hukum konvergensi:** setiap komponen menyesuaikan diri dengan file ini. Bagian-bagian dari 4 agen harus **cocok
satu sama lain** - tanda tangan CLI, nama file, dan kunci JSON di bawah ini bersifat **immutable** (sebuah perubahan berarti
menyelaraskannya di sini terlebih dahulu).

Prinsip yang diwarisi dari repo: **sh POSIX murni** di perangkat (tanpa bashism; berjalan dengan toybox/busybox +
`sha256sum`/`gzip`/`base64` milik toybox + `curl` yang diambil + `ed25519-mini` yang tertanam - ramping, tanpa
bundle biner), **nol komentar cuma-cuma**, **selalu release**, **ketat saat gagal** (transaksi yang dapat dilanjutkan, tidak ada
yang palsu "selesai", tidak ada yang hilang), **tidak ada yang dilonggarkan**.

---

## 1. Tata letak state (Tier-2, di luar direktori modul)

```
$VDLU_DIR = /data/adb/<module>/vdlu
  config               # key=value (§5)
  current.json         # manifest versi AKTIF (basis diff); tidak ada = belum pernah diperbarui
  journal.json         # transaksi sedang berlangsung (§4); tidak ada = idle
  cancel               # keberadaan = permintaan pembatalan (WebUI membuatnya; engine menghapusnya saat berhenti)
  lock.d/              # mkdir-lock (flock tidak praktis di toybox; pemulihan stale berdasarkan PID)
  blobs/<sha256>       # cache blob yang terverifikasi (konten ASLI, sudah didekompresi)
  rollback/<version>/<path>   # backup file yang ditimpa
  staged/<path>.vdlu-new      # REBOOT-hard menunggu swap saat boot
  target.json          # manifest yang DIPATOK dari transaksi berjalan (keberadaan = transaksi aktif; menjadi current.json saat DONE)
  plan.tsv  plan.del   # rencana internal engine (progres); WebUI MENGABAIKANnya (hanya membaca journal/config/current)
```
`cancelled:true` di journal = engine berhenti karena pembatalan (state non-terminal yang dapat dilanjutkan; `error`
tetap null).

Engine di-vendor dalam modul: `$MODULE_DIR/vdlu/update.sh` (+ `vdlu-verify`). `$MODULE_DIR =
/data/adb/modules/<module>`. Engine menerima via env: `VDLU_DIR`, `MODULE_DIR`, `MODID`.

## 2. CLI engine (komponen ENGINE)

`sh update.sh <cmd>` - rc 0 = ok, !=0 = error (stderr berisi alasannya):

| cmd | melakukan |
|---|---|
| `check` | DIFF: mengunduh manifest, membandingkan; mencetak JSON 1 baris `{"update":bool,"from":N,"to":M,"fetch":K,"reboot":bool}`; tidak mengubah apa pun. Perangkat LEBIH MAJU dari feed (downgrade diblokir, hardened) = state BENIGN: `{"update":false,"ahead":true,"from":N,"to":M}` + rc0 (tidak pernah "check failed"). rc do_diff: 2 fetch/parse, 3 verify/meta, 4 ahead |
| `run` | siklus penuh: DIFF->FETCH->APPLY->COMMIT; menghormati `cancel`; menulis progres ke `journal.json`; menerapkan LIVE, men-stage REBOOT-hard |
| `resume` | melanjutkan transaksi `journal.json` dari fase saat ini (idempoten) |
| `boot` | mode pre-zygote: `resume` + melakukan SWAP dari `staged/*.vdlu-new` (menerapkan `.so`), menutup `PENDING_REBOOT`->`DONE` |
| `status` | mencetak `journal.json` (atau `{"state":"idle"}`) |
| `cancel` | membuat `$VDLU_DIR/cancel` (sebuah `run` yang sedang berlangsung berhenti pada titik aman berikutnya) |

Sumber blob/manifest: `source` dari config. `<source>` + `/manifest.json`, `/blobs/<sha>`, `/blobs/<sha>.gz`.
`source` diawali dengan `https://` (curl statis yang diambil, TLS) atau `file://` (staging lokal).

## 3. manifest.json (dihasilkan oleh PRODUCER, dikonsumsi oleh ENGINE)

```json
{ "schema":1, "module":"<id>", "version":<int>, "version_name":"<str>", "built":"<ISO8601>",
  "engine_min":3, "key_id":"<str>", "channel":"stable",
  "files":[ {"path":"webroot/index.html","sha256":"<hex64>","size":<int>,"mode":"0644","enc":"raw|gz","class":"live|soft|reboot"} ],
  "delete":["<path>"], "sig":"<base64>" }
```

- `files[]` = pohon target LENGKAP. `class`: `live` (webroot/bin/lib/confs/script-on-demand/module.prop) ·
  `soft` (service.sh/post-fs-data.sh/boot-completed.sh) · `reboot` (`zygisk/**/*.so`, `system/**`, `*.rule`).
  Default berdasarkan path; tidak pernah men-downgrade `reboot`->`live`.
- `enc`: `gz` (gzip `-9 -n`, deterministik; gunzip toybox di perangkat) hanya ketika kompresi bagus DAN
  ukurannya signifikan; `sha256` SELALU dari konten asli.
- `sig`: tanda tangan manifest kanonik TANPA field `sig` (§4 dari verify).

## 4. journal.json (ENGINE menulis, WEBUI membaca - kontrak progres)

```json
{ "schema":1, "module":"<id>", "target":<version>, "from":<version>,
  "phase":"diff|fetch|apply|commit", "state":"PLANNED|FETCHING|FETCHED|APPLYING|APPLIED_LIVE|PENDING_REBOOT|DONE|ERROR|DEFERRED",
  "total":<int>, "done":<int>, "current":"<path>", "bytes":<int>, "reboot_pending":bool,
  "cancelled":bool, "error":"<str|null>", "updated":"<ISO8601>",
  "items":[ {"path":"<p>","sha256":"<h>","class":"<c>","st":"pending|fetched|applied|staged|skipped"} ] }
```

Mesin state (urutan tetap): `PLANNED->FETCHING->FETCHED->APPLYING->APPLIED_LIVE->(PENDING_REBOOT|DONE)`.
`DONE` hanya setelah re-hash SEGALANYA cocok. Sebuah REBOOT-hard yang di-stage ⇒ `PENDING_REBOOT` (bukan `DONE`). Jalan keluar
dari fase `fetch`: `ERROR` (kegagalan keras) atau `DEFERRED` (net_policy memblokir unduhan - benign/dapat dilanjutkan,
bukan error).

## 5. config (key=value, satu per baris; dapat diedit di WEBUI)

```
auto_on_webui_open=0
auto_on_reboot=1
source=https://<user>.github.io/<repo>/<module>
channel=stable
profile=trusted        # trusted | hardened. DEFAULT KODE (baris tidak ada) = hardened (fail-closed, 9a9a824)
net_policy=any         # any (Wi-Fi+mobile) | wifi (Wi-Fi saja) | mobile (mobile saja) - mengatur UNDUHAN berdasarkan tipe jaringan
allow_metered=0        # ⚠️ DIGANTIKAN oleh net_policy (tidak dikonsumsi oleh engine)
pubkey_dir=keyring     # relatif terhadap $MODULE_DIR/vdlu (keyring pubkey untuk verify)
ca_path=               # kosong = auto-deteksi trust store Android; atur sebuah path untuk menimpa
tools_source=          # kosong = diturunkan dari source (.../vdlu-tools); feed curl statis
boot_retry_interval=30 # detik antar probe ketika BOOT menemukan perangkat offline (minimum 5s)
boot_retry_minutes=0   # batas atas retry SABAR (waktu AWAKE) hanya saat boot; 0 = mati. Hemat baterai (tanpa wakelock,
                       # tanpa lock ditahan, probe route tidak pernah membangunkan radio) -> batas atas yang murah hati ~gratis
```

**Boot retry (offline) - SABAR, hemat baterai:** hanya saat `boot` (tidak pernah pada check/auto-open). Jika fetch manifest
gagal karena JARINGAN (`fetch_offline` mengklasifikasikan berdasarkan exit dari fetcher), ia menunggu dan mencoba lagi sampai
berhasil ATAU `boot_retry_minutes` waktu AWAKE habis. Sebuah desain yang **tidak menahan apa pun dan tidak menguras**:
- **Nol wakelock:** di antara percobaan ia adalah `sleep`, yang membeku di deep-sleep -> perangkat tidur normal
  (~nol baterai); retry berjeda dan dilanjutkan setelah perangkat sudah terjaga.
- **Nol lock ditahan:** `acquire_lock_try`+release DI ANTARA percobaan (tidak menahan lock selama menunggu) ->
  `run`/check manual tidak pernah memblokir; jika sebuah run manual men-stage sebuah TARGET sementara itu, boot menunda.
- **Tidak membangunkan radio percuma:** sebuah probe `net_allowed` (via `net_type`/`ip route get`, lookup route kernel
  yang menghormati policy-routing Android; tanpa paket) mengatur setiap percobaan - ia hanya menghabiskan sebuah fetch setelah
  jaringan muncul.
- TIDAK PERNAH mencoba lagi kegagalan deterministik (manifest/sig/downgrade). `--connect-timeout 15` pada fetch (tidak
  menggantung pada captive portal). `service.sh` menjalankannya di background (boot tidak pernah menggantung).
- ⛔ **HARD: mengaktifkan `boot_retry_minutes>0` membutuhkan engine SABAR** (yang dengan
  `net_allowed`+`acquire_lock_try`, kanonik `da7115f4`+). Boot-retry SEBELUMNYA (menahan lock sepanjang
  jendela + mencoba lagi curl buta offline) **MENGURAS baterai/membangunkan radio** - mengaktifkan retry pada engine lama
  adalah bumerang. Saat mengaktifkannya, vendor engine saat ini.

**`net_policy` (any|wifi|mobile):** mengatur **UNDUHAN** berdasarkan tipe jaringan. `net_type()` mengklasifikasikan egress
dari `ip route get` (iface seluler `rmnet/ccmni/v4-*/clat` = mobile; segala sesuatu yang lain = wifi; lookup kernel, tanpa
paket). `net_allowed()` membandingkannya dengan `net_policy` dan mengatur `do_fetch` (blob) + probe boot-retry
sabar. **Check manifest tetap bebas** (kecil -> UI melaporkan pembaruan pada jaringan apa pun); hanya unduhan yang
menunggu jaringan yang diizinkan. Sebuah unduhan pada jaringan yang tidak diizinkan = state **`DEFERRED`** di journal
(BUKAN ERROR; sebuah toast INFO biru yang lembut "menunggu jaringan X"; plan/target tetap ada, dilanjutkan pada
check/boot berikutnya di jaringan yang benar). `net_policy` **menggantikan** `allow_metered` (yang tidak pernah dikonsumsi).
Engine `97baf887`+ (`file://` tidak pernah diatur).

## 6. Tanda tangan (PRODUCER menandatangani di PC via openssl; ENGINE memverifikasi di perangkat via ed25519-mini)

- Kanonikalisasi: manifest TANPA `sig`, kunci terurut, JSON ringkas (tanpa spasi berlebih), UTF-8.
  Yang ditandatangani/diverifikasi = heksadesimal `sha256` dari bentuk kanonik tersebut (memberi determinisme lintas-tool).
- `producer/vdlu-sign <manifest.json> <privkey.pem> <key_id>` -> menyuntikkan `key_id` + `sig` (base64 dari tanda tangan ed25519 atas sha256 kanonik) ke dalam manifest, in place.
- `engine/vdlu-verify <manifest.json> <keyring_dir>` -> rc 0 jika `sig` cocok dengan pubkey `<key_id>.pub` di
  keyring (RAMPING: pubkey **RAW 32 byte**). Secara internal, tanpa openssl: `sha256sum`/`base64 -d` toybox + biner
  `ed25519-mini` yang tertanam (CLI `ed25519-mini <pub32> <msg> <sig64>`, rc 0=valid/1=invalid/2=penggunaan).
  rc!=0 = tolak. **`profile=hardened` ⇒ verify wajib; kegagalan = abort.**
  `profile=trusted` ⇒ verify bersifat best-effort (sumber sudah dipercaya via SSH), tetapi hash setiap blob SELALU diperiksa.
- `producer/vdlu-keygen <id> <out>` -> menghasilkan `<id>.pem` (priv) + `<id>.pub` (PEM, untuk tooling di PC) +
  `<id>.pub.raw` (**RAW 32B** = `<id>.pub` dari keyring ramping di perangkat). openssl `genpkey -algorithm ed25519`.

## 7. Blob - verifikasi (ENGINE)

Mengunduh `<source>/blobs/<sha>` (atau `.gz` jika `enc=gz`), menulis `.part`, jika `gz` mendekompresi (`gunzip`),
memeriksa `sha256sum` == `sha256` dari manifest; cocok -> `mv` atomik ke `$VDLU_DIR/blobs/<sha>`. 3 kegagalan pada
blob yang sama = membatalkan fase (tidak ada yang diterapkan). Sebuah blob yang sudah ada di `$VDLU_DIR/blobs/<sha>` dengan hash ok =
melewati unduhan.

## 8. APPLY berdasarkan class (ENGINE)

- `live`/`soft`: backup `rollback/<v>/<path>` -> menulis `$MODULE_DIR/<path>.vdlu-tmp` dari blob -> `chmod mode` ->
  `rename` atomik di atas target. Sudah pada hash target = lewati. (Dalam varian Zygisk penulisan menuju
  direktori yang di-mount = merge per-file, tidak pernah `rm -rf` direktori.)
- `reboot`: mematerialisasikan ke `$VDLU_DIR/staged/<path>.vdlu-new` (TIDAK menyentuh yang live). Swap dilakukan saat `boot`.
- `delete[]`: backup -> menghapus.

## 9. WEBUI ↔ ENGINE (komponen WEBUI)

- Memicu: `ksu.exec("sh $MODULE_DIR/vdlu/update.sh run")` (background).
- Progres: poll ringan `ksu.exec("cat $VDLU_DIR/journal.json")` setiap ~1s; merender `{phase,state,total,done,current,bytes}`.
- Liveness: journal tidak ada selama 8 tick ⇒ "tidak ada respons". Journal BEKU (nilai sama) selama 20 tick ⇒ memeriksa `lock.d`: hidup = berlanjut (fetch lambat 1 blob), mati = error + Resume. Tanpa ini, sebuah run yang mati di tengah fetch akan membekukan toast pada "updating".
- Cancel: `ksu.exec("touch $VDLU_DIR/cancel")`.
- Config: membaca/menulis `$VDLU_DIR/config` (key=value) di tab "Updates".
- Toast: bar + `phase done/total · current`; saat selesai dengan `reboot_pending` ⇒ sebuah banner persisten "reboot untuk mengaktifkan .so".
- Auto-open (`auto_on_webui_open=1`): melakukan `check()` SENYAP terlebih dahulu (tanpa toast progres); hanya memicu `run`+toast persisten jika `update && fetch>0`. Terkini/ahead/tidak-ada-yang-baru = hasil inline di panel, nol toast sisa. Tidak mengganggu seperti tombol manual (toast hanya muncul ketika ada unduhan nyata). Bootstrap curl bersifat sekali-saja.

## 10. Integrasi ke dalam demo (komponen INTEGRATION) - SNIPPET, jangan edit file live

Menghasilkan, di `integration/demo/`, snippet + sebuah `INTEGRATION.md` yang menyebutkan di mana masing-masing ditempatkan (tanpa menerapkan):
- hook `auto_on_reboot` di `post-fs-data`/`service.sh` (pre-zygote -> `update.sh boot`) dan `auto_on_webui_open`.
- default `config` + keyring tertanam + vendoring (`modules/<mod>/vdlu/`).
- varian PARSIAL (merge ke dalam direktori yang di-mount).

## 11. Toolchain yang diambil + baseline (RAMPING, Pendekatan B)

**Tata letak dalam modul (zip):** `vdlu/{update.sh, vdlu-verify, config.default, keyring/<id>.pub (RAW 32B),
verify/<abi>/ed25519-mini, baseline.json}`. **TANPA** `bin/` (openssl/curl/zstd). `customize.sh` dapat memangkas
`verify/` hingga ke ABI perangkat (`vdlu-verify` menemukan mini di `<dir>/ed25519-mini` ATAU `<dir>/verify/<abi>/ed25519-mini`).

**ed25519-mini** (biner tertanam, hanya-verify): `ed25519-mini <pubkey32> <msg> <sig64>` -> rc 0=valid,
1=invalid, 2=penggunaan/IO. msg = byte yang ditandatangani persis (TIDAK me-rehash). TweetNaCl PD, statis per-ABI, PROVENANCE.

**tools-feed** (hanya profil publik/https): disajikan di `<tools_source>` (default diturunkan: menukar segmen terakhir
dari `source` dengan `vdlu-tools`, mis. `https://<user>.github.io/<repo>/vdlu-tools`). Berisi:
- `tools-manifest.json` - sebuah manifest `vdlu-pack` DITANDATANGANI atas pohon `<abi>/curl`, memaku `sha256` dari
  setiap curl (kunci `release-2026` yang sama).
- `<abi>/curl` - curl **statis** MENTAH (mandiri, ~1MB; curl 8.11.1 + mbedTLS). 🪤 mbedTLS TIDAK
  membawa CA bundle: `fetch_url` meneruskan `--capath` (auto-deteksi trust store Android: `/system/etc/security/cacerts`
  -> conscrypt APEX; `ca_path` menimpa). Tanpa capath = error 60. Integritasnya adalah ed25519; cert-check adalah pertahanan berlapis.

**install-tool** (ENGINE): `update.sh install-tool <abi>` membaca `$VDLU_DIR/.work/{tools-manifest.json, tool.<abi>}`
(WEBUI mengunduhnya via `fetch()` dan menulisnya di sana), **memverifikasi tanda tangan tools-manifest (ed25519-mini,
WAJIB di profil mana pun)** + hash curl == manifest, dan baru kemudian memasangnya ke `$VDLU_DIR/tools/<abi>/curl` (0755).
curl berjalan sebagai root -> sig+hash sebelum exec menutup RCE. Bertahan di Tier-2: tidak pernah diunduh ulang (kecuali saat uninstall).

**fetch-bootstrap** (WEBUI, `ensureToolchain()`): berjalan sebelum check/run/resume. `file://` = no-op; curl SUDAH
tersedia (Tier-2, ATAU `module/bin/<abi>/curl` dari modul **self-bundled**, ATAU sistem) = no-op
(VDLU menggunakan kembali curl yang ada); hanya `https` **tanpa curl sama sekali** yang mengunduh curl + tools-manifest via webview, menulisnya
ke `.work` (base64 ter-chunk via `ksu.exec`), memanggil `install-tool`. Kepercayaan = pemeriksaan on-device, bukan unduhan.

> 🪤 **Ramping (fetch-bootstrap) ≠ wajib.** Sebuah modul yang `bin/`-nya ada untuk fitur MILIKNYA SENDIRI (mis. membundel
> restic/rclone/age/tar/curl...) **tidak** diramping ke ~2MB maupun mengunduh curl - VDLU mengadopsi engine ramping
> (gz, mini, baseline, perbaikan) dan **menggunakan kembali** toolchain yang tertanam. Hanya modul tanpa toolchain sendiri
> yang mendapat ~2MB.

**baseline.json** (perbaikan from:0): release menyalin `manifest.json` DITANDATANGANI dari versi yang dikirim ke
`vdlu/baseline.json`; pada instalasi segar engine menyemai `current.json` darinya (`init_paths`, hanya jika tidak ada) -> 
perangkat lahir "terkini", tanpa auto-update dirinya sendiri dan tanpa re-fetch.

<!-- doc-footer -->

---

> _Dokumentasi ini dibuat dengan Claude (Anthropic) dan dikelola oleh VD171. Koreksi dan perbaikan dipersilakan; lihat [CONTRIBUTING.md](CONTRIBUTING.md)._
