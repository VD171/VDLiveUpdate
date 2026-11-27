> **Languages:** [English](../../SECURITY.md) · [العربية](../ar/SECURITY.md) · [Čeština](../cs/SECURITY.md) · [Deutsch](../de/SECURITY.md) · [Español](../es/SECURITY.md) · [فارسی](../fa/SECURITY.md) · [Français](../fr/SECURITY.md) · [हिन्दी](../hi/SECURITY.md) · Bahasa Indonesia · [Italiano](../it/SECURITY.md) · [日本語](../ja/SECURITY.md) · [한국어](../ko/SECURITY.md) · [Nederlands](../nl/SECURITY.md) · [Polski](../pl/SECURITY.md) · [Português](../pt/SECURITY.md) · [Русский](../ru/SECURITY.md) · [Svenska](../sv/SECURITY.md) · [ไทย](../th/SECURITY.md) · [Türkçe](../tr/SECURITY.md) · [Українська](../uk/SECURITY.md) · [Tiếng Việt](../vi/SECURITY.md) · [中文](../zh/SECURITY.md)

---

# Kebijakan Keamanan

VDLiveUpdate (VDLU) menerapkan pembaruan flashless dengan root ke modul yang aktif: ia
menulis ke direktori milik modul itu sendiri dan menukar sebuah `.so` Zygisk saat boot,
berjalan dalam konteks root modul. Kami menanggapi keamanan dengan serius.

## Melaporkan kerentanan

- **Site:** https://vd171.ru
- **Site:** https://vd.priv8.ru
- **Issues:** https://github.com/VD171/VDLiveUpdate/issues
- **GitHub:** [@VD171](https://github.com/VD171)
- **XDA-Developers:** [@VD171](https://xdaforums.com/m/vd171.4699873/)
- **Telegram:** [@VD_Priv8](https://t.me/VD_Priv8)
- **Channel:** [@Priv8_VD](https://t.me/Priv8_VD)
- **Discord:** [@VD.Priv8](https://discord.com/users/1296831918989639721)
- **E-mail:** vd.priv8@pm.me

Sertakan deskripsi yang jelas dan, jika memungkinkan, sebuah manifest atau feed yang
mereproduksi masalahnya. Kami akan merespons secepat mungkin dan memberi Anda kredit jika
Anda mau.

## Catatan cakupan

- Pembaruan adalah blob content-addressed ditambah sebuah `manifest.json` yang ditandatangani
  dengan ed25519. Perangkat memverifikasi tanda tangan dengan `ed25519-mini` yang tertanam
  (tanpa openssl di perangkat), dan setiap blob diperiksa terhadap `sha256`-nya sebelum
  digunakan.
- Profil hardened (default publik) mewajibkan tanda tangan yang valid dan memblokir
  downgrade. Versi "asal" dibatasi bawah oleh `versionCode` modul yang terpasang (dibaca
  dari `module.prop`), sehingga sebuah modul tidak pernah dikembalikan ke belakang feed.
- Akar kepercayaan (kunci publik ed25519 mentah di `keyring/` dan biner di `verify/`)
  bersifat hanya-flash dan tidak pernah dirotasi melalui jaringan. Produsen mengecualikannya
  dari feed dan engine mengabaikan setiap path `vdlu/` dalam rencana yang diunduh, sehingga
  kunci penandatanganan yang bocor tidak dapat menukar verifier atau kunci dan mempertahankan
  root.
- Sebuah manifest yang ditandatangani secara valid untuk modul lain tidak dapat menulis ke
  direktori modul yang berbeda. Field `module` yang ditandatangani harus sama dengan `MODID`
  di perangkat (pemeriksaan ikatan antar-modul), dan setiap penulisan dan penghapusan tetap
  terbatas pada direktori modul.
- Engine berjalan dalam konteks root milik modul itu sendiri dan tidak pernah melemahkannya.
  Ia tidak menambahkan privilese dan tidak menginterpolasi field manifest apa pun ke dalam
  shell, setiap nilai `path`, `sha256`, `mode`, dan `delete[]` divalidasi sebagai masukan
  bermusuhan sebelum digunakan.
- Posturnya fail-closed. Nilai `profile` yang rusak atau tidak dikenal tidak pernah jatuh ke
  menerima konten yang tidak ditandatangani (apa pun yang bukan persis `trusted` diperlakukan
  sebagai `hardened`), dan sebuah cadangan ditulis sebelum berkas apa pun ditimpa, sehingga
  apply yang gagal tidak pernah menghancurkan versi yang terpasang.
- Lihat [TRUST-MODEL.md](TRUST-MODEL.md) untuk model kepercayaan lengkap, jaminan fail-closed,
  dan detail hardening.

<!-- doc-footer -->

---

> _Dokumentasi ini dibuat dengan Claude (Anthropic) dan dikelola oleh VD171. Koreksi dan perbaikan dipersilakan, lihat [CONTRIBUTING.md](CONTRIBUTING.md)._
