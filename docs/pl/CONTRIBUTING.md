> **Languages:** [English](../../CONTRIBUTING.md) · [العربية](../ar/CONTRIBUTING.md) · [Čeština](../cs/CONTRIBUTING.md) · [Deutsch](../de/CONTRIBUTING.md) · [Español](../es/CONTRIBUTING.md) · [فارسی](../fa/CONTRIBUTING.md) · [Français](../fr/CONTRIBUTING.md) · [हिन्दी](../hi/CONTRIBUTING.md) · [Bahasa Indonesia](../id/CONTRIBUTING.md) · [Italiano](../it/CONTRIBUTING.md) · [日本語](../ja/CONTRIBUTING.md) · [한국어](../ko/CONTRIBUTING.md) · [Nederlands](../nl/CONTRIBUTING.md) · Polski · [Português](../pt/CONTRIBUTING.md) · [Русский](../ru/CONTRIBUTING.md) · [Svenska](../sv/CONTRIBUTING.md) · [ไทย](../th/CONTRIBUTING.md) · [Türkçe](../tr/CONTRIBUTING.md) · [Українська](../uk/CONTRIBUTING.md) · [Tiếng Việt](../vi/CONTRIBUTING.md) · [中文](../zh/CONTRIBUTING.md)

---

# Współtworzenie VDLiveUpdate

VDLU to flashless, inkrementalny silnik samo-aktualizacji wendorowany do modułów KernelSU/APatch/Magisk.
Wkład jest mile widziany.

- Najpierw przeczytaj [INTERFACES.md](INTERFACES.md): to kontrakt szwu między komponentami (prawo
  zbieżności). Traktuj go jako niezmienny, chyba że zmiana jest skoordynowana między engine, producer i WebUI.
- Testuj od końca do końca przed PR: `producer/vdlu-keygen`, `vdlu-pack`, `vdlu-sign`, następnie engine
  (`check` / `run` / `boot`). Także `sh -n engine/*.sh` i `node --check webui/vdlu.js`.
- Bezpieczeństwo jest nienegocjowalne: każde pole manifestu to wrogi input, a `validate_plan()` pozostaje
  fail-closed, prywatny klucz podpisujący nigdy nie dotyka CI ani urządzenia.
- POSIX sh na urządzeniu (bez bashizmów poza `local`, bez `jq`), trzymaj komentarze zwięzłe.
- Jedna logiczna zmiana na PR, powiedz, co się zmieniło i dlaczego.

## Kontakty

- Telegram: @VD_Priv8 https://t.me/VD_Priv8
- Kanał: @Priv8_VD https://t.me/Priv8_VD
- E-mail: vd.priv8@pm.me

<!-- doc-footer -->

---

> _Ta dokumentacja została wygenerowana za pomocą Claude (Anthropic) i jest utrzymywana przez VD171. Poprawki i ulepszenia są mile widziane, zobacz [CONTRIBUTING.md](CONTRIBUTING.md)._
