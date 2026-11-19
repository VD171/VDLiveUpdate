> **Languages:** [English](../../CONTRIBUTING.md) · [العربية](../ar/CONTRIBUTING.md) · [Čeština](../cs/CONTRIBUTING.md) · [Deutsch](../de/CONTRIBUTING.md) · [Español](../es/CONTRIBUTING.md) · [فارسی](../fa/CONTRIBUTING.md) · [Français](../fr/CONTRIBUTING.md) · [हिन्दी](../hi/CONTRIBUTING.md) · [Bahasa Indonesia](../id/CONTRIBUTING.md) · Italiano · [日本語](../ja/CONTRIBUTING.md) · [한국어](../ko/CONTRIBUTING.md) · [Nederlands](../nl/CONTRIBUTING.md) · [Polski](../pl/CONTRIBUTING.md) · [Português](../pt/CONTRIBUTING.md) · [Русский](../ru/CONTRIBUTING.md) · [Svenska](../sv/CONTRIBUTING.md) · [ไทย](../th/CONTRIBUTING.md) · [Türkçe](../tr/CONTRIBUTING.md) · [Українська](../uk/CONTRIBUTING.md) · [Tiếng Việt](../vi/CONTRIBUTING.md) · [中文](../zh/CONTRIBUTING.md)

---

# Contribuire a VDLiveUpdate

VDLU e un engine di auto-aggiornamento flashless e incrementale vendorizzato nei moduli KernelSU/APatch/Magisk.
I contributi sono benvenuti.

- Leggi prima [INTERFACES.md](INTERFACES.md): e il contratto di cucitura tra i componenti (la legge
  di convergenza). Trattalo come immutabile a meno che una modifica non sia coordinata tra engine, producer e WebUI.
- Testa end to end prima di una PR: `producer/vdlu-keygen`, `vdlu-pack`, `vdlu-sign`, poi l'engine
  (`check` / `run` / `boot`). Anche `sh -n engine/*.sh` e `node --check webui/vdlu.js`.
- La sicurezza non e negoziabile: ogni campo del manifest e input ostile e `validate_plan()` resta
  fail-closed; la chiave di firma privata non tocca mai la CI o un dispositivo.
- sh POSIX sul dispositivo (niente bashism oltre a `local`, niente `jq`); mantieni i commenti stringati.
- Una modifica logica per PR; dì cosa e cambiato e perche.

## Contatti

- Telegram: @VD_Priv8 https://t.me/VD_Priv8
- Canale: @Priv8_VD https://t.me/Priv8_VD
- E-mail: vd.priv8@pm.me

<!-- doc-footer -->

---

> _Questa documentazione è stata generata con Claude (Anthropic) ed è gestita da VD171. Correzioni e miglioramenti sono benvenuti; vedi [CONTRIBUTING.md](CONTRIBUTING.md)._
