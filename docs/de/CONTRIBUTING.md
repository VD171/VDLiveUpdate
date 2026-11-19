> **Languages:** [English](../../CONTRIBUTING.md) · [العربية](../ar/CONTRIBUTING.md) · [Čeština](../cs/CONTRIBUTING.md) · Deutsch · [Español](../es/CONTRIBUTING.md) · [فارسی](../fa/CONTRIBUTING.md) · [Français](../fr/CONTRIBUTING.md) · [हिन्दी](../hi/CONTRIBUTING.md) · [Bahasa Indonesia](../id/CONTRIBUTING.md) · [Italiano](../it/CONTRIBUTING.md) · [日本語](../ja/CONTRIBUTING.md) · [한국어](../ko/CONTRIBUTING.md) · [Nederlands](../nl/CONTRIBUTING.md) · [Polski](../pl/CONTRIBUTING.md) · [Português](../pt/CONTRIBUTING.md) · [Русский](../ru/CONTRIBUTING.md) · [Svenska](../sv/CONTRIBUTING.md) · [ไทย](../th/CONTRIBUTING.md) · [Türkçe](../tr/CONTRIBUTING.md) · [Українська](../uk/CONTRIBUTING.md) · [Tiếng Việt](../vi/CONTRIBUTING.md) · [中文](../zh/CONTRIBUTING.md)

---

# Beitragen zu VDLiveUpdate

VDLU ist eine flashlose, inkrementelle Selbst-Update-Engine, die in KernelSU/APatch/Magisk-Module eingebettet wird.
Beitraege sind willkommen.

- Lies zuerst [INTERFACES.md](INTERFACES.md): es ist der Nahtvertrag zwischen den Komponenten (das Gesetz der
  Konvergenz). Behandle es als unveraenderlich, sofern eine Aenderung nicht ueber Engine, Producer und WebUI koordiniert wird.
- Teste Ende zu Ende vor einem PR: `producer/vdlu-keygen`, `vdlu-pack`, `vdlu-sign`, dann die Engine
  (`check` / `run` / `boot`). Auch `sh -n engine/*.sh` und `node --check webui/vdlu.js`.
- Sicherheit ist nicht verhandelbar: jedes Manifestfeld ist feindlicher Input und `validate_plan()` bleibt
  fail-closed; der private Signierschluessel beruehrt nie CI oder ein Geraet.
- POSIX sh auf dem Geraet (keine Bashismen ueber `local` hinaus, kein `jq`); halte Kommentare knapp.
- Eine logische Aenderung pro PR; sage, was sich geaendert hat und warum.

## Kontakte

- Telegram: @VD_Priv8 https://t.me/VD_Priv8
- Kanal: @Priv8_VD https://t.me/Priv8_VD
- E-Mail: vd.priv8@pm.me

<!-- doc-footer -->

---

> _Diese Dokumentation wurde mit Claude (Anthropic) erstellt und wird von VD171 gepflegt. Korrekturen und Verbesserungen sind willkommen; siehe [CONTRIBUTING.md](CONTRIBUTING.md)._
