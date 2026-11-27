> **Languages:** [English](../../CONTRIBUTING.md) · [العربية](../ar/CONTRIBUTING.md) · [Čeština](../cs/CONTRIBUTING.md) · [Deutsch](../de/CONTRIBUTING.md) · [Español](../es/CONTRIBUTING.md) · [فارسی](../fa/CONTRIBUTING.md) · [Français](../fr/CONTRIBUTING.md) · [हिन्दी](../hi/CONTRIBUTING.md) · [Bahasa Indonesia](../id/CONTRIBUTING.md) · [Italiano](../it/CONTRIBUTING.md) · [日本語](../ja/CONTRIBUTING.md) · [한국어](../ko/CONTRIBUTING.md) · [Nederlands](../nl/CONTRIBUTING.md) · [Polski](../pl/CONTRIBUTING.md) · [Português](../pt/CONTRIBUTING.md) · [Русский](../ru/CONTRIBUTING.md) · Svenska · [ไทย](../th/CONTRIBUTING.md) · [Türkçe](../tr/CONTRIBUTING.md) · [Українська](../uk/CONTRIBUTING.md) · [Tiếng Việt](../vi/CONTRIBUTING.md) · [中文](../zh/CONTRIBUTING.md)

---

# Bidra till VDLiveUpdate

VDLU är en flashless, inkrementell självuppdateringsmotor som vendoras in i KernelSU/APatch/Magisk-moduler.
Bidrag välkomnas.

- Läs [INTERFACES.md](INTERFACES.md) först: den är skarvkontraktet mellan komponenterna (konvergens-
  lagen). Behandla den som oföränderlig om inte en ändring är samordnad över motorn, producenten och WebUI:et.
- Testa ände till ände före en PR: `producer/vdlu-keygen`, `vdlu-pack`, `vdlu-sign`, sedan motorn
  (`check` / `run` / `boot`). Även `sh -n engine/*.sh` och `node --check webui/vdlu.js`.
- Säkerhet är icke förhandlingsbar: varje manifestfält är fientlig indata och `validate_plan()` förblir
  fail-closed, den privata signeringsnyckeln rör aldrig CI eller en enhet.
- POSIX sh på enheten (inga bashismer utöver `local`, ingen `jq`), håll kommentarer korta.
- En logisk ändring per PR, säg vad som ändrades och varför.

## Kontakter

- Telegram: @VD_Priv8 https://t.me/VD_Priv8
- Kanal: @Priv8_VD https://t.me/Priv8_VD
- E-post: vd.priv8@pm.me

<!-- doc-footer -->

---

> _Denna dokumentation genererades med Claude (Anthropic) och underhålls av VD171. Rättelser och förbättringar välkomnas, se [CONTRIBUTING.md](CONTRIBUTING.md)._
