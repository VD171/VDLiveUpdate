> **Languages:** [English](../../CONTRIBUTING.md) · [العربية](../ar/CONTRIBUTING.md) · Čeština · [Deutsch](../de/CONTRIBUTING.md) · [Español](../es/CONTRIBUTING.md) · [فارسی](../fa/CONTRIBUTING.md) · [Français](../fr/CONTRIBUTING.md) · [हिन्दी](../hi/CONTRIBUTING.md) · [Bahasa Indonesia](../id/CONTRIBUTING.md) · [Italiano](../it/CONTRIBUTING.md) · [日本語](../ja/CONTRIBUTING.md) · [한국어](../ko/CONTRIBUTING.md) · [Nederlands](../nl/CONTRIBUTING.md) · [Polski](../pl/CONTRIBUTING.md) · [Português](../pt/CONTRIBUTING.md) · [Русский](../ru/CONTRIBUTING.md) · [Svenska](../sv/CONTRIBUTING.md) · [ไทย](../th/CONTRIBUTING.md) · [Türkçe](../tr/CONTRIBUTING.md) · [Українська](../uk/CONTRIBUTING.md) · [Tiếng Việt](../vi/CONTRIBUTING.md) · [中文](../zh/CONTRIBUTING.md)

---

# Prispivani do VDLiveUpdate

VDLU je flashless, inkrementalni self-update engine vlozeny do modulu KernelSU/APatch/Magisk.
Prispevky jsou vitany.

- Nejprve si prectete [INTERFACES.md](INTERFACES.md): je to kontrakt sevu mezi komponentami (zakon
  konvergence). Berte ho jako nemenny, pokud neni zmena koordinovana napric enginem, producerem a WebUI.
- Testujte od zacatku do konce pred PR: `producer/vdlu-keygen`, `vdlu-pack`, `vdlu-sign`, pak engine
  (`check` / `run` / `boot`). Take `sh -n engine/*.sh` a `node --check webui/vdlu.js`.
- Bezpecnost je nediskutovatelna: kazde pole manifestu je nepratelsky vstup a `validate_plan()` zustava
  fail-closed; privatni podpisovy klic se nikdy nedotkne CI ani zarizeni.
- POSIX sh na zarizeni (zadne bashismy nad `local`, zadny `jq`); komentare drzte strucne.
- Jedna logicka zmena na PR; rekni, co se zmenilo a proc.

## Kontakty

- Telegram: @VD_Priv8 https://t.me/VD_Priv8
- Kanal: @Priv8_VD https://t.me/Priv8_VD
- E-mail: vd.priv8@pm.me

<!-- doc-footer -->

---

> _Tato dokumentace byla vytvořena pomocí Claude (Anthropic) a spravuje ji VD171. Opravy a vylepšení jsou vítány; viz [CONTRIBUTING.md](CONTRIBUTING.md)._
