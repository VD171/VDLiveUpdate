> **Languages:** [English](../AI-AGENTS.md) · [العربية](../ar/AI-AGENTS.md) · [Čeština](../cs/AI-AGENTS.md) · [Deutsch](../de/AI-AGENTS.md) · [Español](../es/AI-AGENTS.md) · [فارسی](../fa/AI-AGENTS.md) · [Français](../fr/AI-AGENTS.md) · [हिन्दी](../hi/AI-AGENTS.md) · Bahasa Indonesia · [Italiano](../it/AI-AGENTS.md) · [日本語](../ja/AI-AGENTS.md) · [한국어](../ko/AI-AGENTS.md) · [Nederlands](../nl/AI-AGENTS.md) · [Polski](../pl/AI-AGENTS.md) · [Português](../pt/AI-AGENTS.md) · [Русский](../ru/AI-AGENTS.md) · [Svenska](../sv/AI-AGENTS.md) · [ไทย](../th/AI-AGENTS.md) · [Türkçe](../tr/AI-AGENTS.md) · [Українська](../uk/AI-AGENTS.md) · [Tiếng Việt](../vi/AI-AGENTS.md) · [中文](../zh/AI-AGENTS.md)

---

# Mengendalikan VDLU dari agen AI

VDLiveUpdate (VDLU) adalah pembaru inkremental tanpa flash yang disertakan modul KSU/Magisk di `vdlu/`. Seluruh mesin dikendalikan dari shell, sehingga asisten atau agen AI dapat memeriksa, menerapkan, melanjutkan, dan menyelesaikan pembaruan secara headless, siklus yang sama yang dijalankan WebUI, tanpa UI dan tanpa manusia dalam loop. Parse JSON yang dicetaknya, jangan pernah mengorek teks.

## Kontrak

Satu titik masuk, dijalankan sebagai root di perangkat, dengan tiga variabel lingkungan mesin yang disetel:

```sh
VDLU_DIR=/data/adb/<mod>/vdlu MODULE_DIR=/data/adb/modules/<mod> MODID=<mod> \
  sh "$MODULE_DIR/vdlu/update.sh" <verb>
```

- `VDLU_DIR` adalah direktori status Tier-2 (di luar modul, bertahan dari reflash), `MODULE_DIR` adalah pohon modul yang hidup, `MODID` adalah id modul.
- `rc 0` = ok, `rc != 0` = error, dengan alasannya di stderr.
- Verba baca (`check`, `status`) mencetak **satu objek JSON** di stdout. Parse itu, jangan pernah mengorek teks.
- Mesin hanya bergantung pada toybox (`sha256sum`/`gzip`/`base64`) ditambah `ed25519-mini` tertanam ditambah `curl` statis yang diambil pada pembaruan https pertama, nol `jq`.

Selama pengembangan skrip yang sama berada di `engine/update.sh` dalam repositori ini, jadi `sh engine/update.sh <verb>` dengan tiga variabel yang disetel mengendalikan salinan uji dengan cara yang sama.

## Verba

| Verba | Melakukan | Mencetak |
|------|------|--------|
| `check` | DIFF hanya-baca terhadap feed, tidak mengubah apa pun | `{"update":bool,"from":N,"to":M,"fetch":K,"reboot":bool}`, atau `{"update":false,"ahead":true,"from":N,"to":M}` saat perangkat lebih maju dari feed (downgrade diblokir, jinak, rc 0) |
| `run` | siklus LIVE penuh DIFF -> FETCH -> APPLY -> COMMIT, menerapkan berkas LIVE dan memanggungkan REBOOT-hard, menghormati `cancel` | kemajuan di `journal.json` |
| `resume` | melanjutkan transaksi tertunda dari fase saat ini, idempoten, tidak pernah menukar `.so` | `journal.json` terbarui |
| `boot` | mode pre-zygote, `resume` ditambah penukaran `.so` yang dipanggungkan, menutup `PENDING_REBOOT` menjadi `DONE` | `journal.json` terbarui |
| `status` | snapshot hanya-baca, tidak mengubah apa pun | `journal.json`, atau `{"state":"idle"}` saat tidak ada transaksi aktif |
| `cancel` | meminta penghentian, `run` yang berjalan berhenti di titik aman berikutnya | membuat `$VDLU_DIR/cancel` |

Pembaruan headless adalah `check` untuk melihat apakah ada yang tertunda, `run` untuk menerapkan semua yang bisa menjadi live, lalu `boot` pada boot berikutnya untuk menukar setiap `.so` yang dipanggungkan (atau `resume` untuk mengulang unduhan yang ditangguhkan). Setiap verba aman dipanggil ulang, kerusakan atau jaringan putus di tengah siklus meninggalkan jurnal yang dapat dilanjutkan, tidak pernah modul yang separuh diterapkan.

## JSON status

`status` (dan berkas hidup di `$VDLU_DIR/journal.json`) adalah kontrak kemajuan yang dibaca WebUI dan agen:

```json
{ "schema":1, "module":"<id>", "target":<version>, "from":<version>,
  "phase":"diff|fetch|apply|commit",
  "state":"PLANNED|FETCHING|FETCHED|APPLYING|APPLIED_LIVE|PENDING_REBOOT|DONE|ERROR|DEFERRED",
  "total":<int>, "done":<int>, "current":"<path>", "bytes":<int>,
  "reboot_pending":bool, "cancelled":bool, "error":"<str|null>",
  "updated":"<ISO8601>",
  "items":[ {"path":"<p>","sha256":"<h>","class":"<c>","st":"pending|fetched|applied|staged|skipped"} ] }
```

- `state` bergerak dalam urutan tetap: `PLANNED -> FETCHING -> FETCHED -> APPLYING -> APPLIED_LIVE -> (PENDING_REBOOT | DONE)`.
- `DONE` tercapai hanya setelah hash ulang atas segalanya cocok. Berkas REBOOT-hard yang dipanggungkan menghasilkan `PENDING_REBOOT`, tidak pernah `DONE` palsu, jalankan `boot` untuk menyelesaikannya.
- `DEFERRED` berarti `net_policy` memblokir unduhan, keadaan jinak dan dapat dilanjutkan dan bukan error, rencana tetap ada dan `check`/`boot` berikutnya melanjutkan.
- `ERROR` membawa alasan di `error`, berkas LIVE yang diterapkan dikembalikan dari `rollback/`, modul tidak pernah dibiarkan separuh diterapkan.
- `cancelled:true` dengan `error:null` adalah penghentian bersih, jurnal tetap dapat dilanjutkan.

## Kontrak jahitan

Setiap komponen (mesin, produser, WebUI) menyesuaikan diri dengan [`INTERFACES.md`](INTERFACES.md), hukum konvergensi. Verba CLI, skema `manifest.json`, kunci `journal.json`, dan kunci config yang didefinisikan di sana bersifat **tak dapat diubah**, perlakukan berkas itu sebagai satu-satunya sumber kebenaran dan selaraskan dengannya sebelum mengubah salah satunya. Untuk internal mesin (transaksi yang dapat dilanjutkan, jaminan kekakuan, pengecualian trust-anchor) lihat [`ENGINE.md`](ENGINE.md), untuk sisi feed (membangun dan menandatangani feed beralamat konten) lihat [`PRODUCER.md`](PRODUCER.md).

## Aturan untuk agen

- Gunakan verba dan JSON, jangan pernah mengorek WebUI dan jangan pernah menyunting berkas status dengan tangan.
- Perlakukan `INTERFACES.md` sebagai tak dapat diubah, sebuah perubahan berarti menyelaraskan kontrak lebih dulu.
- Sebuah patch dari agen AI memenuhi palang tinjauan yang sama seperti yang lain, build selalu release, jangan longgarkan apa pun, jangan hilangkan apa pun.

<!-- doc-footer -->

---

> _Dokumentasi ini dibuat dengan Claude (Anthropic) dan dikelola oleh VD171. Koreksi dan perbaikan dipersilakan, lihat [CONTRIBUTING.md](CONTRIBUTING.md)._
