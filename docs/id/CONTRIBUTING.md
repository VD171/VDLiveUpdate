> **Languages:** [English](../../CONTRIBUTING.md) · [العربية](../ar/CONTRIBUTING.md) · [Čeština](../cs/CONTRIBUTING.md) · [Deutsch](../de/CONTRIBUTING.md) · [Español](../es/CONTRIBUTING.md) · [فارسی](../fa/CONTRIBUTING.md) · [Français](../fr/CONTRIBUTING.md) · [हिन्दी](../hi/CONTRIBUTING.md) · Bahasa Indonesia · [Italiano](../it/CONTRIBUTING.md) · [日本語](../ja/CONTRIBUTING.md) · [한국어](../ko/CONTRIBUTING.md) · [Nederlands](../nl/CONTRIBUTING.md) · [Polski](../pl/CONTRIBUTING.md) · [Português](../pt/CONTRIBUTING.md) · [Русский](../ru/CONTRIBUTING.md) · [Svenska](../sv/CONTRIBUTING.md) · [ไทย](../th/CONTRIBUTING.md) · [Türkçe](../tr/CONTRIBUTING.md) · [Українська](../uk/CONTRIBUTING.md) · [Tiếng Việt](../vi/CONTRIBUTING.md) · [中文](../zh/CONTRIBUTING.md)

---

# Berkontribusi ke VDLiveUpdate

VDLU adalah engine self-update flashless dan inkremental yang di-vendor ke dalam modul KernelSU/APatch/Magisk.
Kontribusi diterima dengan senang hati.

- Baca [INTERFACES.md](INTERFACES.md) terlebih dahulu: ia adalah kontrak sambungan antar komponen (hukum
  konvergensi). Perlakukan sebagai immutable kecuali sebuah perubahan dikoordinasikan lintas engine, producer, dan WebUI.
- Uji end to end sebelum sebuah PR: `producer/vdlu-keygen`, `vdlu-pack`, `vdlu-sign`, lalu engine
  (`check` / `run` / `boot`). Juga `sh -n engine/*.sh` dan `node --check webui/vdlu.js`.
- Keamanan tidak dapat ditawar: setiap field manifest adalah input yang hostile dan `validate_plan()` tetap
  fail-closed, kunci penandatanganan privat tidak pernah menyentuh CI atau sebuah perangkat.
- sh POSIX di perangkat (tanpa bashism di luar `local`, tanpa `jq`), jaga komentar tetap ringkas.
- Satu perubahan logis per PR, sebutkan apa yang berubah dan mengapa.

## Kontak

- Telegram: @VD_Priv8 https://t.me/VD_Priv8
- Channel: @Priv8_VD https://t.me/Priv8_VD
- E-mail: vd.priv8@pm.me

<!-- doc-footer -->

---

> _Dokumentasi ini dibuat dengan Claude (Anthropic) dan dikelola oleh VD171. Koreksi dan perbaikan dipersilakan, lihat [CONTRIBUTING.md](CONTRIBUTING.md)._
