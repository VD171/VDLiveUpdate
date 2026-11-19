> **Languages:** [English](../../CONTRIBUTING.md) · [العربية](../ar/CONTRIBUTING.md) · [Čeština](../cs/CONTRIBUTING.md) · [Deutsch](../de/CONTRIBUTING.md) · [Español](../es/CONTRIBUTING.md) · [فارسی](../fa/CONTRIBUTING.md) · [Français](../fr/CONTRIBUTING.md) · [हिन्दी](../hi/CONTRIBUTING.md) · [Bahasa Indonesia](../id/CONTRIBUTING.md) · [Italiano](../it/CONTRIBUTING.md) · [日本語](../ja/CONTRIBUTING.md) · [한국어](../ko/CONTRIBUTING.md) · Nederlands · [Polski](../pl/CONTRIBUTING.md) · [Português](../pt/CONTRIBUTING.md) · [Русский](../ru/CONTRIBUTING.md) · [Svenska](../sv/CONTRIBUTING.md) · [ไทย](../th/CONTRIBUTING.md) · [Türkçe](../tr/CONTRIBUTING.md) · [Українська](../uk/CONTRIBUTING.md) · [Tiếng Việt](../vi/CONTRIBUTING.md) · [中文](../zh/CONTRIBUTING.md)

---

# Bijdragen aan VDLiveUpdate

VDLU is een flashless, incrementele zelf-update-engine die mee-geleverd wordt in KernelSU/APatch/Magisk-modules.
Bijdragen zijn welkom.

- Lees eerst [INTERFACES.md](INTERFACES.md): het is het naad-contract tussen de componenten (de wet van
  convergentie). Behandel het als onwrikbaar tenzij een wijziging is afgestemd over de engine, producer en WebUI heen.
- Test end-to-end vóór een PR: `producer/vdlu-keygen`, `vdlu-pack`, `vdlu-sign`, dan de engine
  (`check` / `run` / `boot`). Ook `sh -n engine/*.sh` en `node --check webui/vdlu.js`.
- Beveiliging is niet onderhandelbaar: elk manifest-veld is vijandige invoer en `validate_plan()` blijft
  fail-closed; de private signeersleutel raakt nooit CI of een toestel aan.
- POSIX sh op het toestel (geen bashisms buiten `local`, geen `jq`); houd commentaren beknopt.
- Eén logische wijziging per PR; zeg wat er veranderde en waarom.

## Contacten

- Telegram: @VD_Priv8 https://t.me/VD_Priv8
- Channel: @Priv8_VD https://t.me/Priv8_VD
- E-mail: vd.priv8@pm.me

<!-- doc-footer -->

---

> _Deze documentatie is gegenereerd met Claude (Anthropic) en wordt onderhouden door VD171. Correcties en verbeteringen zijn welkom; zie [CONTRIBUTING.md](CONTRIBUTING.md)._
