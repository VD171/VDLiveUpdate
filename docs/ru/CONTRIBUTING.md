> **Languages:** [English](../../CONTRIBUTING.md) · [العربية](../ar/CONTRIBUTING.md) · [Čeština](../cs/CONTRIBUTING.md) · [Deutsch](../de/CONTRIBUTING.md) · [Español](../es/CONTRIBUTING.md) · [فارسی](../fa/CONTRIBUTING.md) · [Français](../fr/CONTRIBUTING.md) · [हिन्दी](../hi/CONTRIBUTING.md) · [Bahasa Indonesia](../id/CONTRIBUTING.md) · [Italiano](../it/CONTRIBUTING.md) · [日本語](../ja/CONTRIBUTING.md) · [한국어](../ko/CONTRIBUTING.md) · [Nederlands](../nl/CONTRIBUTING.md) · [Polski](../pl/CONTRIBUTING.md) · [Português](../pt/CONTRIBUTING.md) · Русский · [Svenska](../sv/CONTRIBUTING.md) · [ไทย](../th/CONTRIBUTING.md) · [Türkçe](../tr/CONTRIBUTING.md) · [Українська](../uk/CONTRIBUTING.md) · [Tiếng Việt](../vi/CONTRIBUTING.md) · [中文](../zh/CONTRIBUTING.md)

---

# Вклад в VDLiveUpdate

VDLU это flashless инкрементальный движок самообновления, вендоренный в модули KernelSU/APatch/Magisk.
Вклад приветствуется.

- Сначала прочтите [INTERFACES.md](INTERFACES.md): это контракт шва между компонентами (закон
  сходимости). Относитесь к нему как к неизменному, если только изменение не согласовано между engine, producer и WebUI.
- Тестируйте от края до края перед PR: `producer/vdlu-keygen`, `vdlu-pack`, `vdlu-sign`, затем engine
  (`check` / `run` / `boot`). Также `sh -n engine/*.sh` и `node --check webui/vdlu.js`.
- Безопасность не обсуждается: каждое поле манифеста это враждебный ввод, и `validate_plan()` остаётся
  fail-closed; приватный ключ подписи никогда не касается CI или устройства.
- POSIX sh на устройстве (без башизмов, кроме `local`, без `jq`); держите комментарии краткими.
- Одно логическое изменение на PR; скажите, что изменилось и почему.

## Контакты

- Telegram: @VD_Priv8 https://t.me/VD_Priv8
- Канал: @Priv8_VD https://t.me/Priv8_VD
- E-mail: vd.priv8@pm.me

<!-- doc-footer -->

---

> _Эта документация создана с помощью Claude (Anthropic) и поддерживается VD171. Исправления и улучшения приветствуются; см. [CONTRIBUTING.md](CONTRIBUTING.md)._
