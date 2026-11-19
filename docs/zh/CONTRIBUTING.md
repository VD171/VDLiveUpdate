> **Languages:** [English](../../CONTRIBUTING.md) · [العربية](../ar/CONTRIBUTING.md) · [Čeština](../cs/CONTRIBUTING.md) · [Deutsch](../de/CONTRIBUTING.md) · [Español](../es/CONTRIBUTING.md) · [فارسی](../fa/CONTRIBUTING.md) · [Français](../fr/CONTRIBUTING.md) · [हिन्दी](../hi/CONTRIBUTING.md) · [Bahasa Indonesia](../id/CONTRIBUTING.md) · [Italiano](../it/CONTRIBUTING.md) · [日本語](../ja/CONTRIBUTING.md) · [한국어](../ko/CONTRIBUTING.md) · [Nederlands](../nl/CONTRIBUTING.md) · [Polski](../pl/CONTRIBUTING.md) · [Português](../pt/CONTRIBUTING.md) · [Русский](../ru/CONTRIBUTING.md) · [Svenska](../sv/CONTRIBUTING.md) · [ไทย](../th/CONTRIBUTING.md) · [Türkçe](../tr/CONTRIBUTING.md) · [Українська](../uk/CONTRIBUTING.md) · [Tiếng Việt](../vi/CONTRIBUTING.md) · 中文

---

# 为 VDLiveUpdate 做贡献

VDLU 是一个免刷写、增量的自更新 engine，被 vendor 进 KernelSU/APatch/Magisk 模块。
欢迎贡献。

- 先阅读 [INTERFACES.md](INTERFACES.md)：它是各组件之间的接缝契约（收敛
  法则）。将其视为不可变，除非一次更改在 engine、producer 和 WebUI 之间得到协调。
- 在 PR 之前做端到端测试：`producer/vdlu-keygen`、`vdlu-pack`、`vdlu-sign`，然后是 engine
  （`check` / `run` / `boot`）。还有 `sh -n engine/*.sh` 和 `node --check webui/vdlu.js`。
- 安全不可妥协：每个清单字段都是敌意输入，而 `validate_plan()` 保持
  fail-closed；私有签名密钥绝不接触 CI 或设备。
- 设备上用 POSIX sh（除 `local` 外无 bashism，无 `jq`）；保持注释简短。
- 每个 PR 一个逻辑更改；说明改了什么以及为什么。

## 联系方式

- Telegram：@VD_Priv8 https://t.me/VD_Priv8
- 频道：@Priv8_VD https://t.me/Priv8_VD
- E-mail：vd.priv8@pm.me

<!-- doc-footer -->

---

> _本文档由 Claude (Anthropic) 生成，并由 VD171 维护。欢迎修正和改进；请参阅 [CONTRIBUTING.md](CONTRIBUTING.md)。_
