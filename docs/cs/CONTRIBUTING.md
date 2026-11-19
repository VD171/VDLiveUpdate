> **Languages:** [English](../../CONTRIBUTING.md) · [العربية](../ar/CONTRIBUTING.md) · Čeština · [Deutsch](../de/CONTRIBUTING.md) · [Español](../es/CONTRIBUTING.md) · [فارسی](../fa/CONTRIBUTING.md) · [Français](../fr/CONTRIBUTING.md) · [हिन्दी](../hi/CONTRIBUTING.md) · [Bahasa Indonesia](../id/CONTRIBUTING.md) · [Italiano](../it/CONTRIBUTING.md) · [日本語](../ja/CONTRIBUTING.md) · [한국어](../ko/CONTRIBUTING.md) · [Nederlands](../nl/CONTRIBUTING.md) · [Polski](../pl/CONTRIBUTING.md) · [Português](../pt/CONTRIBUTING.md) · [Русский](../ru/CONTRIBUTING.md) · [Svenska](../sv/CONTRIBUTING.md) · [ไทย](../th/CONTRIBUTING.md) · [Türkçe](../tr/CONTRIBUTING.md) · [Українська](../uk/CONTRIBUTING.md) · [Tiếng Việt](../vi/CONTRIBUTING.md) · [中文](../zh/CONTRIBUTING.md)

---

# Přispívání do VDLiveUpdate

VDLU je flashless, inkrementální self-update engine vložený do modulu KernelSU/APatch/Magisk.
Příspěvky jsou vítány.

- Nejprve si přečtěte [INTERFACES.md](INTERFACES.md): je to kontrakt švu mezi komponentami (zákon
  konvergence). Berte ho jako neměnný, pokud není změna koordinována napříč enginem, producerem a WebUI.
- Testujte od začátku do konce před PR: `producer/vdlu-keygen`, `vdlu-pack`, `vdlu-sign`, pak engine
  (`check` / `run` / `boot`). Také `sh -n engine/*.sh` a `node --check webui/vdlu.js`.
- Bezpečnost je nediskutovatelná: každé pole manifestu je nepřátelský vstup a `validate_plan()` zůstává
  fail-closed; privátní podpisový klíč se nikdy nedotkne CI ani zařízení.
- POSIX sh na zařízení (žádné bashismy nad `local`, žádný `jq`); komentáře držte stručně.
- Jedna logická změna na PR; řekni, co se změnilo a proč.

## Kontakty

- Telegram: @VD_Priv8 https://t.me/VD_Priv8
- Kanál: @Priv8_VD https://t.me/Priv8_VD
- E-mail: vd.priv8@pm.me

<!-- doc-footer -->

---

> _Tato dokumentace byla vytvořena pomocí Claude (Anthropic) a spravuje ji VD171. Opravy a vylepšení jsou vítány; viz [CONTRIBUTING.md](CONTRIBUTING.md)._
