> **Languages:** [English](../../CONTRIBUTING.md) · [العربية](../ar/CONTRIBUTING.md) · [Čeština](../cs/CONTRIBUTING.md) · [Deutsch](../de/CONTRIBUTING.md) · [Español](../es/CONTRIBUTING.md) · [فارسی](../fa/CONTRIBUTING.md) · [Français](../fr/CONTRIBUTING.md) · [हिन्दी](../hi/CONTRIBUTING.md) · [Bahasa Indonesia](../id/CONTRIBUTING.md) · [Italiano](../it/CONTRIBUTING.md) · 日本語 · [한국어](../ko/CONTRIBUTING.md) · [Nederlands](../nl/CONTRIBUTING.md) · [Polski](../pl/CONTRIBUTING.md) · [Português](../pt/CONTRIBUTING.md) · [Русский](../ru/CONTRIBUTING.md) · [Svenska](../sv/CONTRIBUTING.md) · [ไทย](../th/CONTRIBUTING.md) · [Türkçe](../tr/CONTRIBUTING.md) · [Українська](../uk/CONTRIBUTING.md) · [Tiếng Việt](../vi/CONTRIBUTING.md) · [中文](../zh/CONTRIBUTING.md)

---

# VDLiveUpdate への貢献

VDLU は KernelSU/APatch/Magisk モジュールに同梱される、flashless で増分的な自己更新エンジンである。
貢献を歓迎する。

- まず [INTERFACES.md](INTERFACES.md) を読むこと: これはコンポーネント間の継ぎ目契約である (収束の
  法則)。エンジン、プロデューサ、WebUI をまたいで調整される変更でない限り、これを不変として扱うこと。
- PR の前にエンドツーエンドでテストすること: `producer/vdlu-keygen`、`vdlu-pack`、`vdlu-sign`、そしてエンジン
  (`check` / `run` / `boot`)。さらに `sh -n engine/*.sh` と `node --check webui/vdlu.js`。
- セキュリティは譲れない: すべての manifest フィールドは敵対的入力であり、`validate_plan()` は
  fail-closed のままである。秘密の署名鍵は CI にもデバイスにも決して触れさせない。
- デバイス上では POSIX sh (`local` 以外の bashism なし、`jq` なし)。コメントは簡潔に保つこと。
- PR ごとに論理的な変更を 1 つ。何がどう変わり、なぜかを述べること。

## 連絡先

- Telegram: @VD_Priv8 https://t.me/VD_Priv8
- Channel: @Priv8_VD https://t.me/Priv8_VD
- E-mail: vd.priv8@pm.me

<!-- doc-footer -->

---

> _このドキュメントは Claude (Anthropic) で生成され、VD171 によって保守されています。修正や改善を歓迎します。[CONTRIBUTING.md](CONTRIBUTING.md) を参照してください。_
