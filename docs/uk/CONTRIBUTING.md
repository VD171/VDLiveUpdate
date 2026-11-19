> **Languages:** [English](../../CONTRIBUTING.md) · [العربية](../ar/CONTRIBUTING.md) · [Čeština](../cs/CONTRIBUTING.md) · [Deutsch](../de/CONTRIBUTING.md) · [Español](../es/CONTRIBUTING.md) · [فارسی](../fa/CONTRIBUTING.md) · [Français](../fr/CONTRIBUTING.md) · [हिन्दी](../hi/CONTRIBUTING.md) · [Bahasa Indonesia](../id/CONTRIBUTING.md) · [Italiano](../it/CONTRIBUTING.md) · [日本語](../ja/CONTRIBUTING.md) · [한국어](../ko/CONTRIBUTING.md) · [Nederlands](../nl/CONTRIBUTING.md) · [Polski](../pl/CONTRIBUTING.md) · [Português](../pt/CONTRIBUTING.md) · [Русский](../ru/CONTRIBUTING.md) · [Svenska](../sv/CONTRIBUTING.md) · [ไทย](../th/CONTRIBUTING.md) · [Türkçe](../tr/CONTRIBUTING.md) · Українська · [Tiếng Việt](../vi/CONTRIBUTING.md) · [中文](../zh/CONTRIBUTING.md)

---

# Внесок у VDLiveUpdate

VDLU - це flashless, інкрементальний self-update engine, вендоризований у модулі KernelSU/APatch/Magisk.
Внески вітаються.

- Спочатку прочитайте [INTERFACES.md](INTERFACES.md): це контракт шва між компонентами (закон
  конвергенції). Трактуйте його як незмінний, якщо тільки зміна не скоординована через engine, producer і WebUI.
- Тестуйте наскрізно перед PR: `producer/vdlu-keygen`, `vdlu-pack`, `vdlu-sign`, потім engine
  (`check` / `run` / `boot`). Також `sh -n engine/*.sh` і `node --check webui/vdlu.js`.
- Безпека не підлягає обговоренню: кожне поле маніфесту є ворожим вводом, а `validate_plan()` залишається
  fail-closed; приватний ключ підпису ніколи не торкається CI чи пристрою.
- POSIX sh на пристрої (без башизмів поза `local`, без `jq`); тримайте коментарі лаконічними.
- Одна логічна зміна на PR; скажіть, що змінилося і чому.

## Контакти

- Telegram: @VD_Priv8 https://t.me/VD_Priv8
- Канал: @Priv8_VD https://t.me/Priv8_VD
- E-mail: vd.priv8@pm.me

<!-- doc-footer -->

---

> _Ця документація створена за допомогою Claude (Anthropic) і підтримується VD171. Виправлення та покращення вітаються; див. [CONTRIBUTING.md](CONTRIBUTING.md)._
