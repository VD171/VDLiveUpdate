> **Languages:** [English](../../CONTRIBUTING.md) · [العربية](../ar/CONTRIBUTING.md) · [Čeština](../cs/CONTRIBUTING.md) · [Deutsch](../de/CONTRIBUTING.md) · [Español](../es/CONTRIBUTING.md) · [فارسی](../fa/CONTRIBUTING.md) · [Français](../fr/CONTRIBUTING.md) · [हिन्दी](../hi/CONTRIBUTING.md) · [Bahasa Indonesia](../id/CONTRIBUTING.md) · [Italiano](../it/CONTRIBUTING.md) · [日本語](../ja/CONTRIBUTING.md) · [한국어](../ko/CONTRIBUTING.md) · [Nederlands](../nl/CONTRIBUTING.md) · [Polski](../pl/CONTRIBUTING.md) · [Português](../pt/CONTRIBUTING.md) · [Русский](../ru/CONTRIBUTING.md) · [Svenska](../sv/CONTRIBUTING.md) · [ไทย](../th/CONTRIBUTING.md) · Türkçe · [Українська](../uk/CONTRIBUTING.md) · [Tiếng Việt](../vi/CONTRIBUTING.md) · [中文](../zh/CONTRIBUTING.md)

---

# VDLiveUpdate'e katkıda bulunma

VDLU, KernelSU/APatch/Magisk modüllerine vendor edilen flashless, artımlı bir kendi-kendini-güncelleme motorudur.
Katkılar hoş karşılanır.

- Önce [INTERFACES.md](INTERFACES.md)'yi okuyun: bu, bileşenler arasındaki ek yeri sözleşmesidir (yakınsama
  yasası). Bir değişiklik motor, üretici ve WebUI arasında koordine edilmediği sürece onu değişmez olarak ele alın.
- Bir PR'den önce uçtan uca test edin: `producer/vdlu-keygen`, `vdlu-pack`, `vdlu-sign`, ardından motor
  (`check` / `run` / `boot`). Ayrıca `sh -n engine/*.sh` ve `node --check webui/vdlu.js`.
- Güvenlik pazarlık konusu değildir: her manifest alanı düşmanca girdidir ve `validate_plan()` fail-closed
  kalır, özel imzalama anahtarı asla CI'ya ya da bir cihaza dokunmaz.
- Cihazda POSIX sh (`local` dışında bashism yok, `jq` yok), yorumları kısa tutun.
- PR başına bir mantıksal değişiklik, neyin neden değiştiğini söyleyin.

## İletişim

- Telegram: @VD_Priv8 https://t.me/VD_Priv8
- Kanal: @Priv8_VD https://t.me/Priv8_VD
- E-posta: vd.priv8@pm.me

<!-- doc-footer -->

---

> _Bu belgeler Claude (Anthropic) ile oluşturulmuş olup VD171 tarafından yürütülmektedir. Düzeltmeler ve iyileştirmeler memnuniyetle karşılanır, bkz. [CONTRIBUTING.md](CONTRIBUTING.md)._
